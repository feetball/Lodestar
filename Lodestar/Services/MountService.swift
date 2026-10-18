import Foundation
import LodestarKit
import Observation

/// The GoTo mount: connection state, the mount's position, and the commands the screens give it.
///
/// One shared instance lives as long as the app, so the connection survives switching tabs and closing sheets. The
/// engine's controller itself lives on a worker thread inside a `MountSession`; this class only awaits its jobs, so
/// the main actor never waits for the mount. About once a second a poll refreshes `status`; commands are jobs on the
/// same worker, Stop goes first.
///
/// Safety rules kept here: nothing moves unless a person asked for it with a tap; the Sun is never a target; targets
/// below the altitude limit are refused before the engine sees them (and by the engine as well); the mount is stopped
/// and disconnected when the app goes to the background; every failure becomes text in `errorText` and never a crash.
@MainActor
@Observable
final class MountService {
    static let shared = MountService()

    /// The length of one nudge command. Holding an arrow repeats it a little faster than it runs out.
    private static let nudgePulseSeconds = 0.5
    private static let nudgeRepeat: Duration = .milliseconds(400)
    private static let pollInterval: Duration = .seconds(1)
    private static let nudgePollInterval: Duration = .milliseconds(500)
    /// Waits this long after a limit was changed before the controller is rebuilt with it.
    private static let reconfigureDelay: Duration = .seconds(1)

    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected
        /// The session ended without the person asking: the link dropped or the app went to the background.
        case lost(String)
    }

    enum DiscoveryState: Equatable {
        case idle
        case searching
        case finished(serverCount: Int, telescopeCount: Int)
    }

    // MARK: State for the screens

    private(set) var connection = Connection.disconnected
    private(set) var status = MountStatus.disconnected
    private(set) var capabilities: MountCapabilities?
    /// The kind of mount connected, connecting or lost.
    private(set) var connectedOption: MountConnectionOption?
    private(set) var connectedAddress: String?
    private(set) var isDemo = false
    /// The last failure, in words for the person, until it is dismissed or the next action starts.
    private(set) var errorText: String?
    /// The error behind a failed connection, for the advice under it.
    private(set) var connectError: MountError?
    /// A short confirmation: "Synced (was 1.2° off).".
    private(set) var noticeText: String?
    /// A GoTo, a sync or a change of limits is under way.
    private(set) var isWorking = false
    private(set) var isStopping = false
    /// How far the target was when the current slew began, degrees; the progress bar counts from it.
    private(set) var slewStartSeparation: Double?
    /// The name of the object of the last GoTo.
    private(set) var slewTargetName: String?
    private(set) var discoveryState = DiscoveryState.idle
    private(set) var discovered: [MountAlpacaTelescope] = []

    var settings = MountUserSettings() {
        didSet {
            guard settings != oldValue else { return }
            MountPreferences.save(settings)
            if settings.engineSettings != oldValue.engineSettings { scheduleReconfigure() }
        }
    }

    var memory = MountConnectionMemory() {
        didSet {
            guard memory != oldValue else { return }
            MountPreferences.save(memory)
        }
    }

    // MARK: Internals

    @ObservationIgnored private var session: MountSession?
    /// Changes whenever a session starts or ends; work that belongs to an older session sees the difference and stops.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observer: Observer?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var nudgeTask: Task<Void, Never>?
    @ObservationIgnored private var nudgeGate: MountCancelFlag?
    @ObservationIgnored private var reconfigureTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryFlag: MountCancelFlag?
    @ObservationIgnored private var lifecycle: MountLifecycle?
    @ObservationIgnored private var markerCache: MountMarkerCache?

    private init() {
        settings = MountPreferences.loadSettings()
        memory = MountPreferences.loadMemory()
        lifecycle = MountLifecycle { [weak self] in
            self?.handleEnteredBackground()
        }
    }

    // MARK: Derived state

    var isConnected: Bool { connection == .connected }

    /// A slew or a nudge is running.
    var isMoving: Bool { status.phase == .slewing || status.phase == .nudging }

    var selectedOption: MountConnectionOption {
        MountConnectionOption.option(id: memory.selectedOptionID) ?? .lx200
    }

    var selectedOptionID: String {
        get { selectedOption.id }
        set { memory.selectedOptionID = newValue }
    }

    /// The address typed for the selected kind of mount.
    var form: MountConnectionForm {
        get { memory.form(for: selectedOption) }
        set { memory.forms[selectedOption.id] = newValue }
    }

    /// What to call the mount on screen.
    var displayName: String {
        if isDemo { return "Demo mount" }
        if let name = capabilities?.name, !name.isEmpty { return name }
        return connectedOption?.title ?? selectedOption.title
    }

    /// The state in a few words, for the row in Settings.
    var summaryText: String {
        switch connection {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting\u{2026}"
        case .connected: return displayName
        case .lost: return "Connection lost"
        }
    }

    /// Changes the address typed for the selected kind of mount.
    func updateForm(_ change: (inout MountConnectionForm) -> Void) {
        var changed = form
        change(&changed)
        form = changed
    }

    /// Why the mount's alignment should be done first, or `nil`.
    var alignmentWarning: String? {
        guard isConnected, status.isAligned == false else { return nil }
        return "The mount is not aligned. Align it on the hand controller, then continue."
    }

    /// Why a GoTo to `object` cannot be started, or `nil` when it can.
    func goToUnavailableReason(for object: CelestialObject?, observer: Observer?) -> String? {
        guard isConnected, let capabilities else { return MountError.notConnected.userMessage }
        guard capabilities.canSlew else { return MountError.notSupported(feature: .slew).userMessage }
        guard let object else { return "Choose a target first." }
        if MountTargets.isSun(object) { return MountTargets.sunRefusal }
        if let observer {
            let target = MountTargets.resolve(object, observer: observer, date: Date())
            if target.lowestAltitude < settings.altitudeLimit {
                return MountError.belowHorizonLimit(altitude: target.lowestAltitude,
                                                    limit: settings.altitudeLimit).userMessage
            }
        }
        if capabilities.gotoNeedsAlignment && status.isAligned == false { return MountError.notAligned.userMessage }
        switch status.phase {
        case .slewing: return MountError.slewInProgress.userMessage
        case .nudging: return MountError.busy.userMessage
        case .idle, .disconnected: return nil
        }
    }

    /// Why the mount cannot be synced to `object` now, or `nil` when it can.
    func syncUnavailableReason(for object: CelestialObject?) -> String? {
        guard isConnected, let capabilities else { return MountError.notConnected.userMessage }
        guard capabilities.canSync else { return MountError.notSupported(feature: .sync).userMessage }
        guard let object else { return "Choose a target first." }
        if MountTargets.isSun(object) { return MountTargets.sunRefusal }
        switch status.phase {
        case .slewing: return MountError.slewInProgress.userMessage
        case .nudging: return MountError.busy.userMessage
        case .idle, .disconnected: return nil
        }
    }

    // MARK: Messages

    func dismissError() {
        errorText = nil
        connectError = nil
    }

    func dismissNotice() {
        noticeText = nil
    }

    private func clearMessages() {
        errorText = nil
        connectError = nil
        noticeText = nil
    }

    // MARK: Connecting

    /// Connects to the mount chosen on the connection screen. Does nothing while connecting or connected.
    func connect(observer: Observer?) {
        let option = selectedOption
        startConnection(option: option, form: form, observer: observer, isDemo: false)
    }

    /// Connects to the simulated mount.
    func connectDemo(observer: Observer?) {
        startConnection(option: .demo, form: MountConnectionForm(option: .demo), observer: observer, isDemo: true)
    }

    private func startConnection(option: MountConnectionOption, form: MountConnectionForm, observer: Observer?,
                                 isDemo: Bool) {
        switch connection {
        case .connecting, .connected: return
        case .disconnected, .lost: break
        }
        clearMessages()
        guard let observer else {
            errorText = "Lodestar needs to know where you are to check targets against your altitude limit. "
                + "Allow location access or choose an observing site first."
            return
        }
        if !isDemo && form.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorText = "Enter the mount's address first."
            return
        }
        guard let channel = option.makeChannel(for: form) else {
            errorText = "That address or port can't be used. Enter an IP address such as 192.168.0.1 and a port "
                + "from 1 to 65535."
            return
        }
        self.observer = observer
        self.isDemo = isDemo
        generation += 1
        let token = generation
        connectedOption = option
        connectedAddress = isDemo ? nil : form.addressText
        connection = .connecting
        let engine = settings.engineSettings
        var options = MountDriverOptions(epoch: option.supportsEpoch ? settings.epochChoice.epoch : nil,
                                         reversesEastWest: option.supportsAxisReversal && settings.reversesEastWest,
                                         deviceNumber: form.deviceNumber)
        if isDemo { options.demoStart = Self.demoStart(for: observer) }
        let sendsSiteAndTime = settings.sendsSiteAndTime
        connectTask = Task { [weak self] in
            await self?.performConnection(option: option, form: form, channel: channel, options: options,
                                          engine: engine, observer: observer, sendsSiteAndTime: sendsSiteAndTime,
                                          token: token)
        }
    }

    private func performConnection(option: MountConnectionOption, form: MountConnectionForm, channel: MountChannel,
                                   options: MountDriverOptions, engine: MountSettings, observer: Observer,
                                   sendsSiteAndTime: Bool, token: Int) async {
        var options = options
        var form = form
        if option.supportsDiscovery {
            // The server may host several telescopes: use the one chosen in the search, else the first.
            let address = MountAddress(text: form.host, defaultPort: form.port)
            let lookup = await mountRunBlocking {
                Result { try MountAlpacaDiscovery.telescopes(host: address.host, port: address.port) }
            }
            guard token == generation else {
                channel.close()
                return
            }
            switch lookup {
            case .failure(let error):
                channel.close()
                failConnection(error as? MountError ?? .transport(detail: "unexpected failure"))
                return
            case .success(let telescopes):
                guard let first = telescopes.first else {
                    channel.close()
                    failConnection(.rejected(detail: "no telescope is set up on that Alpaca server"))
                    return
                }
                if form.deviceName == nil || !telescopes.contains(where: { $0.deviceNumber == form.deviceNumber }) {
                    form.deviceNumber = first.deviceNumber
                    form.deviceName = first.name
                }
                options.deviceNumber = form.deviceNumber
            }
        }
        let session = MountSession(channel: channel)
        self.session = session
        let result = await session.connect(option: option, options: options, observer: observer, settings: engine)
        guard token == generation else {
            session.shutdown()
            return
        }
        switch result.result {
        case .failure(let error):
            session.shutdown()
            self.session = nil
            failConnection(error)
        case .success(let found):
            capabilities = found
            status = result.status
            connection = .connected
            if !isDemo {
                memory.selectedOptionID = option.id
                memory.forms[option.id] = form
            }
            startPolling(session: session, token: token)
            if sendsSiteAndTime && found.canSetSiteAndTime {
                await sendSiteAndTime(location: observer.location, announceSuccess: false)
            }
        }
    }

    private func failConnection(_ error: MountError) {
        connection = .disconnected
        connectedOption = nil
        connectedAddress = nil
        isDemo = false
        errorText = error.userMessage
        connectError = error
    }

    /// Gives up on a connection that is being made.
    func cancelConnect() {
        guard connection == .connecting else { return }
        generation += 1
        connectTask?.cancel()
        connectTask = nil
        session?.shutdown()
        session = nil
        connection = .disconnected
        connectedOption = nil
        connectedAddress = nil
        isDemo = false
    }

    /// Ends the connection the way the person asked for. A mount that is moving is stopped first; if it cannot be
    /// stopped the connection stays, so Stop can be tried again.
    func disconnect() {
        switch connection {
        case .disconnected:
            return
        case .connecting:
            cancelConnect()
        case .lost:
            finishSession(lost: nil)
        case .connected:
            guard let ending = session else {
                finishSession(lost: nil)
                return
            }
            Task {
                if isMoving {
                    stopNudgeLoop()
                    ending.interrupt()
                    let stopped = await ending.run(urgent: true) { controller in try controller.abort() }
                    if case .failure(let error) = stopped.result {
                        errorText = Self.stopFailureText(error)
                        return
                    }
                }
                guard session === ending else { return }
                finishSession(lost: nil)
            }
        }
    }

    /// Ends the session. With a `reason` the screens show "Connection lost" and offer to reconnect.
    private func finishSession(lost reason: String?) {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        reconfigureTask?.cancel()
        reconfigureTask = nil
        stopNudgeLoop()
        session?.shutdown()
        session = nil
        capabilities = nil
        status = .disconnected
        isStopping = false
        isWorking = false
        slewStartSeparation = nil
        slewTargetName = nil
        if let reason {
            connection = .lost(reason)
        } else {
            connection = .disconnected
            connectedOption = nil
            connectedAddress = nil
            isDemo = false
        }
    }

    private func handleEnteredBackground() {
        switch connection {
        case .connecting:
            cancelConnect()
        case .connected:
            guard let ending = session else { return }
            lifecycle?.beginBackgroundTask()
            stopNudgeLoop()
            Task {
                // Nobody can watch the mount from here, so it is stopped and let go.
                ending.interrupt()
                _ = await ending.run(urgent: true) { controller in
                    if controller.status.phase != .idle { _ = try? controller.abort() }
                }
                if session === ending {
                    finishSession(lost: "Disconnected when Lodestar went to the background. The mount was stopped.")
                }
                lifecycle?.endBackgroundTask()
            }
        case .disconnected, .lost:
            break
        }
    }

    // MARK: Polling

    private func startPolling(session: MountSession, token: Int) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let began = ContinuousClock.now
                let polled = await session.poll()
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.apply(polled)
                if polled.phase == .disconnected {
                    let reason = polled.lastError?.userMessage ?? MountError.connectionLost.userMessage
                    self.finishSession(lost: reason)
                    return
                }
                let interval = polled.phase == .nudging ? Self.nudgePollInterval : Self.pollInterval
                let remaining = interval - (ContinuousClock.now - began)
                if remaining > .zero { try? await Task.sleep(for: remaining) }
            }
        }
    }

    /// Takes over a status from the worker, and announces what changed for VoiceOver.
    private func apply(_ new: MountStatus) {
        let old = status
        guard new != old else { return }
        status = new
        if new.phase == .slewing && old.phase != .slewing {
            slewStartSeparation = new.separation
            MountLifecycle.announce("Slewing")
        } else if old.phase == .slewing && new.phase != .slewing {
            MountLifecycle.announce(Self.spokenOutcome(new.outcome))
        }
    }

    private static func spokenOutcome(_ outcome: MountSlewOutcome?) -> String {
        switch outcome {
        case .arrived?: return "Arrived"
        case .aborted?: return "Stopped"
        case .failed(let error)?:
            if case .slewStopped = error { return "Stopped short of the target" }
            return "Slew failed"
        case nil: return "Slew ended"
        }
    }

    // MARK: Commands

    /// Runs `work` on the mount's worker and takes over the status it leaves.
    private func execute<Value: Sendable>(
        urgent: Bool = false, _ work: @escaping @Sendable (MountController) throws -> Value
    ) async -> Result<Value, MountError> {
        guard let current = session else { return .failure(.notConnected) }
        let outcome = await current.run(urgent: urgent, work)
        if session === current { apply(outcome.status) }
        return outcome.result
    }

    /// Slews the mount to `object`. The person has confirmed it; the checks here and in the engine still apply.
    func goTo(_ object: CelestialObject, observer: Observer) async {
        guard isConnected, !isWorking else { return }
        clearMessages()
        if let reason = goToUnavailableReason(for: object, observer: observer) {
            errorText = reason
            return
        }
        let target = MountTargets.resolve(object, observer: observer, date: Date())
        let place = target.j2000
        let motion = target.properMotion
        isWorking = true
        defer { isWorking = false }
        let result = await execute { controller in try controller.goto(place, properMotion: motion) }
        switch result {
        case .success: slewTargetName = object.name
        case .failure(let error): errorText = error.userMessage
        }
    }

    /// Tells the mount it points at `object` now, after the person centred it.
    func syncMount(to object: CelestialObject, observer: Observer) async {
        guard isConnected, !isWorking else { return }
        clearMessages()
        if let reason = syncUnavailableReason(for: object) {
            errorText = reason
            return
        }
        let target = MountTargets.resolve(object, observer: observer, date: Date())
        let place = target.j2000
        let motion = target.properMotion
        isWorking = true
        defer { isWorking = false }
        let result = await execute { controller in try controller.sync(place, properMotion: motion) }
        switch result {
        case .success(let synced):
            noticeText = "Synced (was \(AppFormat.separation(synced.offsetDegrees)) off)."
        case .failure(let error):
            errorText = error.userMessage
        }
    }

    /// Stops the mount at once, whatever it is doing. Never waits for another command.
    func stop() {
        guard let current = session, isConnected else {
            if connection == .connecting { cancelConnect() }
            return
        }
        stopNudgeLoop()
        isStopping = true
        // Cut short the exchange that is waiting for the mount, so the stop does not sit out its timeout.
        current.interrupt()
        Task {
            let outcome = await current.run(urgent: true) { controller in try controller.abort() }
            guard session === current else { return }
            apply(outcome.status)
            isStopping = false
            switch outcome.result {
            case .success:
                errorText = nil
                noticeText = "Stopped."
            case .failure(let error):
                errorText = Self.stopFailureText(error)
            }
        }
    }

    private static func stopFailureText(_ error: MountError) -> String {
        "The mount may still be moving. \(error.userMessage) Stop it on its hand controller or switch it off."
    }

    func setTracking(_ enabled: Bool) {
        guard isConnected else { return }
        Task {
            let result = await execute { controller in try controller.setTracking(enabled) }
            switch result {
            case .success: noticeText = enabled ? "Tracking is on." : "Tracking is off."
            case .failure(let error): errorText = error.userMessage
            }
        }
    }

    /// Sends the phone's location and the time (UTC) to the mount.
    func sendSiteAndTime(location: GeographicLocation, announceSuccess: Bool = true) async {
        guard isConnected else { return }
        let result = await execute { controller in try controller.setSiteAndTime(location: location) }
        switch result {
        case .success:
            if announceSuccess { noticeText = "Location and time sent to the mount." }
        case .failure(let error):
            errorText = "Could not send the location and time. \(error.userMessage)"
        }
    }

    // MARK: Nudging

    /// Starts moving the mount in `direction` and keeps doing so until `endNudge`. The mount can only be held for
    /// as long as the app keeps asking: each command lasts half a second.
    func beginNudge(_ direction: MountNudgeDirection) {
        guard isConnected, capabilities?.canNudge == true, status.phase != .slewing else { return }
        stopNudgeLoop()
        let gate = MountCancelFlag()
        nudgeGate = gate
        errorText = nil
        let pulse = Self.nudgePulseSeconds
        nudgeTask = Task { [weak self] in
            while !Task.isCancelled && !gate.isCancelled {
                guard let self else { return }
                let rate = self.settings.nudgeRate
                let result = await self.execute { controller in
                    // A command that waited in the queue while the finger lifted must not start a move.
                    guard !gate.isCancelled else { return }
                    try controller.nudge(direction, rate: rate, durationSeconds: pulse)
                }
                if case .failure(let error) = result {
                    if !gate.isCancelled { self.errorText = error.userMessage }
                    return
                }
                try? await Task.sleep(for: Self.nudgeRepeat)
            }
        }
    }

    /// Stops a nudge that `beginNudge` started.
    func endNudge() {
        guard nudgeTask != nil || nudgeGate != nil else { return }
        stopNudgeLoop()
        guard isConnected else { return }
        Task {
            _ = await execute(urgent: true) { controller in try controller.stopNudge() }
        }
    }

    /// One short nudge, for VoiceOver and for a tap.
    func nudgeOnce(_ direction: MountNudgeDirection) {
        guard isConnected, capabilities?.canNudge == true else { return }
        let rate = settings.nudgeRate
        let pulse = Self.nudgePulseSeconds
        Task {
            let result = await execute { controller in try controller.nudge(direction, rate: rate, durationSeconds: pulse) }
            if case .failure(let error) = result { errorText = error.userMessage }
        }
    }

    private func stopNudgeLoop() {
        nudgeGate?.cancel()
        nudgeGate = nil
        nudgeTask?.cancel()
        nudgeTask = nil
    }

    // MARK: Observer and limits

    /// Tells the controller where the person is, for its altitude checks and the frame of the mount's coordinates.
    func updateObserver(_ new: Observer?) {
        guard let new, new != observer else { return }
        observer = new
        guard isConnected, let current = session else { return }
        Task {
            _ = await current.run { controller in controller.observer = new }
        }
    }

    /// Rebuilds the controller with new limits once the mount is idle. The old limits stay in force until then, and the
    /// check before each GoTo uses the new altitude limit at once.
    private func scheduleReconfigure() {
        reconfigureTask?.cancel()
        guard isConnected else { return }
        reconfigureTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reconfigureDelay)
            for _ in 0..<60 {
                guard let self, !Task.isCancelled, self.isConnected, let current = self.session else { return }
                if self.status.phase == .idle {
                    let result = await current.reconfigure(self.settings.engineSettings)
                    if self.session === current, case .failure(let error) = result.result, error != .busy {
                        self.errorText = "The new limits could not be sent to the mount's controller. \(error.userMessage)"
                    }
                    if self.session === current { self.apply(result.status) }
                    if case .failure(.busy) = result.result {
                        try? await Task.sleep(for: .seconds(1))
                        continue
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Finding Alpaca devices

    func startDiscovery() {
        guard discoveryState != .searching else { return }
        discoveryState = .searching
        discovered = []
        let flag = MountCancelFlag()
        discoveryFlag = flag
        discoveryTask = Task { [weak self] in
            let found = await mountRunBlocking { MountAlpacaDiscovery.search(cancel: flag) }
            guard let self, !flag.isCancelled else { return }
            self.discovered = found.telescopes
            self.discoveryState = .finished(serverCount: found.serverCount, telescopeCount: found.telescopes.count)
        }
    }

    func cancelDiscovery() {
        discoveryFlag?.cancel()
        discoveryFlag = nil
        discoveryTask?.cancel()
        discoveryTask = nil
        if discoveryState == .searching { discoveryState = .idle }
    }

    /// Puts the address and the device of a search result into the Alpaca form.
    func choose(_ telescope: MountAlpacaTelescope) {
        guard let alpaca = MountConnectionOption.option(id: MountConnectionOption.alpaca.id) else { return }
        var chosen = memory.form(for: alpaca)
        chosen.host = telescope.host
        chosen.port = telescope.port
        chosen.deviceNumber = telescope.deviceNumber
        chosen.deviceName = telescope.name
        memory.forms[alpaca.id] = chosen
        memory.selectedOptionID = alpaca.id
    }

    // MARK: Overlay

    /// Where the mount points, as a direction in the local sky (east, north, up) as the Aim overlay draws it, or `nil`
    /// without a connection or a reading. Worked out at most once a second.
    func overlayDirection(observer: Observer, at date: Date) -> (direction: Vector3, isMoving: Bool)? {
        guard isConnected, let position = status.position else { return nil }
        let second = Int(date.timeIntervalSince1970)
        let key = MountMarkerCache.Key(position: position, observer: observer, second: second)
        if let cache = markerCache, cache.key == key { return (cache.direction, isMoving) }
        let direction = SkyFrame(date: date, observer: observer)
            .horizontal(j2000: position, refraction: true).unitVector
        markerCache = MountMarkerCache(key: key, direction: direction)
        return (direction, isMoving)
    }

    // MARK: Demo

    /// The demonstration mount starts high in the southern sky, well above any altitude limit.
    private static func demoStart(for observer: Observer) -> EquatorialCoordinate {
        let frame = SkyFrame(date: Date(), observer: observer)
        let azimuth = observer.location.latitude >= 0 ? 180.0 : 0.0
        return frame.j2000(fromHorizontal: HorizontalCoordinate(azimuth: azimuth, altitude: 60), refracted: false)
    }
}

/// The last direction the overlay worked out for the mount's position.
struct MountMarkerCache {
    struct Key: Equatable {
        let position: EquatorialCoordinate
        let observer: Observer
        let second: Int
    }

    let key: Key
    let direction: Vector3
}
