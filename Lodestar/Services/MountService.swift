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
    /// The phone has to move this far (degrees of latitude or longitude) before the driver is handed the new place.
    private static let siteToleranceDegrees = 0.01
    /// The names of at most this many synced objects are kept, to name the alignment stars.
    private static let maximumRememberedObjects = 24

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
        case finished(serverCount: Int, deviceCount: Int)
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
    private(set) var discovered: [MountFoundDevice] = []
    /// What the driver tells besides the status: the alignment of a Sky-Watcher mount, its pier side and start position.
    private(set) var driverDetail: MountDriverDetail?
    /// The objects the mount was synced to since it was connected, to give the alignment stars their names.
    private(set) var syncedObjects: [MountSyncedObject] = []
    /// How far the mount was from its home position at the first sync of this alignment, degrees.
    private(set) var alignmentHomeError: Double?
    /// A connection has succeeded at some time (the simulated mount counts). Until then the Aim screen has no Mount button.
    private(set) var hasConnectedBefore = false

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
    /// The place the Sky-Watcher driver was last given.
    @ObservationIgnored private var handedLocation: GeographicLocation?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var nudgeTask: Task<Void, Never>?
    @ObservationIgnored private var nudgeGate: MountCancelFlag?
    /// Tripped by Stop and Disconnect, so a GoTo that is still queued does not start its slew after them.
    @ObservationIgnored private var motionGate: MountCancelFlag?
    @ObservationIgnored private var reconfigureTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryFlag: MountCancelFlag?
    @ObservationIgnored private var lifecycle: MountLifecycle?
    @ObservationIgnored private var markerCache: MountMarkerCache?

    private init() {
        settings = MountPreferences.loadSettings()
        memory = MountPreferences.loadMemory()
        hasConnectedBefore = MountPreferences.loadConnectedBefore()
        lifecycle = MountLifecycle { [weak self] in
            self?.handleEnteredBackground()
        }
    }

    // MARK: Derived state

    var isConnected: Bool { connection == .connected }

    /// Whether the Aim screen shows its Mount button: once a mount has been connected, and while one is connecting,
    /// connected or lost. Most people shoot from a plain tripod and never see it.
    var showsAimButton: Bool { hasConnectedBefore || connection != .disconnected }

    /// A slew or a nudge is running.
    var isMoving: Bool { status.phase == .slewing || status.phase == .nudging }

    var selectedOption: MountConnectionOption {
        MountConnectionOption.option(id: memory.selectedOptionID) ?? .lx200
    }

    /// The kind of mount the settings describe: the one connecting or connected, else the one chosen in the picker. After a
    /// connection was lost the picker is back, and the person may have chosen another kind since.
    var displayedOption: MountConnectionOption {
        switch connection {
        case .connecting, .connected: return connectedOption ?? selectedOption
        case .disconnected, .lost: return selectedOption
        }
    }

    var selectedOptionID: String {
        get { selectedOption.id }
        set {
            // Search results belong to the kind of mount they were looked for.
            if newValue != memory.selectedOptionID {
                cancelDiscovery()
                discovered = []
                discoveryState = .idle
            }
            memory.selectedOptionID = newValue
        }
    }

    /// The address typed for the selected kind of mount.
    var form: MountConnectionForm {
        get { memory.form(for: selectedOption) }
        set { memory.forms[selectedOption.id] = newValue }
    }

    /// What to call the mount on screen.
    var displayName: String {
        if let name = capabilities?.name, !name.isEmpty { return name + (isDemo ? " (simulated)" : "") }
        if isDemo { return connectedOption?.title ?? "Simulated mount" }
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

    /// Why the mount's alignment should be done first, or `nil`. A mount that Lodestar aligns itself says so in its own
    /// alignment line instead.
    var alignmentWarning: String? {
        guard isConnected, !usesLodestarAlignment, status.isAligned == false else { return nil }
        return "The mount is not aligned. Align it on the hand controller, then continue."
    }

    /// The connected mount knows nothing about the sky, so Lodestar aligns it on stars (Sky-Watcher Wi-Fi).
    var usesLodestarAlignment: Bool { connectedOption?.usesLodestarAlignment == true }

    /// The alignment stars with their names, oldest first.
    var alignedStars: [MountAlignedStar] {
        guard let stars = driverDetail?.alignment?.stars else { return [] }
        return stars.enumerated().map { index, star in
            let match = syncedObjects.min { $0.place.angularSeparation(to: star.place) < $1.place.angularSeparation(to: star.place) }
            let name = match.flatMap { $0.place.angularSeparation(to: star.place) < 2 ? $0.name : nil } ?? "Star \(index + 1)"
            return MountAlignedStar(index: index, name: name, residualDegrees: star.residualDegrees)
        }
    }

    /// The mount is aligned by Lodestar and no star has been synced yet.
    var needsFirstSync: Bool {
        usesLodestarAlignment && isConnected && (driverDetail?.alignment?.stars.isEmpty ?? true)
    }

    /// Words for the alignment: "Aligned on 3 stars, 0.02° residual, ≈ 0.2° accuracy", or what to do first. `nil` for
    /// mounts that Lodestar does not align.
    var alignmentLine: String? {
        guard usesLodestarAlignment, isConnected else { return nil }
        return MountAlignmentText.line(driverDetail?.alignment)
    }

    /// The start-position check after connecting: all is well, or what to do.
    var startPositionLine: String? {
        guard usesLodestarAlignment, isConnected else { return nil }
        if driverDetail?.startsAwayFromHome == true {
            return "The mount is not at its home position. Switch it off and on at the home position, or move it there "
                + "with the arrows and tap This is home."
        }
        return "The mount started at its home position."
    }

    var startsAwayFromHome: Bool { usesLodestarAlignment && isConnected && driverDetail?.startsAwayFromHome == true }

    /// "Tracking" or "Tracking is off"; `nil` when the mount does not say.
    var trackingLine: String? {
        switch status.isTracking {
        case true?: return "Tracking"
        case false?: return "Tracking is off"
        case nil: return nil
        }
    }

    /// "Telescope east of the pier": equatorial mounts only.
    var pierSideLine: String? {
        guard usesLodestarAlignment, let side = driverDetail?.pierSide else { return nil }
        return side == .east ? "Telescope east of the pier" : "Telescope west of the pier"
    }

    /// Tracking and pier side on one line: "Tracking \u{00B7} Telescope east of the pier".
    var trackingAndPierLine: String? {
        let parts = [trackingLine, pierSideLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// Why tracking stopped by itself, and what to do; `nil` while it has not.
    var trackingStopText: String? {
        guard usesLodestarAlignment, isConnected, status.isTracking != true,
              let reason = driverDetail?.trackingStopReason else { return nil }
        switch reason {
        case .outsideMountLimits where driverDetail?.arrangement == .equatorial:
            return "Tracking stopped at the meridian. Tap Go to to flip the mount"
        case .outsideMountLimits:
            return "Tracking stopped at a limit of the mount (cable wrap or near the zenith). Tap Go to to start again"
        case .mountOverheadLimit:
            return "Tracking stopped near the zenith, where this mount cannot follow"
        default:
            return "Tracking stopped: \(reason.userMessage)"
        }
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
        if usesLodestarAlignment {
            if needsFirstSync { return MountAlignmentText.notAlignedYet }
        } else if capabilities.gotoNeedsAlignment && status.isAligned == false {
            return MountError.notAligned.userMessage
        }
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

    /// The limits the controller runs with. A mount that Lodestar aligns checks every alignment star itself, and its first
    /// sync is as far off as the home position is, so the limit for syncs does not apply to it.
    private func engineSettings(for option: MountConnectionOption?) -> MountSettings {
        let user = settings.engineSettings
        guard option?.usesLodestarAlignment == true else { return user }
        // The altitude limit is applied before each GoTo (`goTo`), with the engine's own words, so a changed limit never has
        // to restart the controller: a new controller would forget the alignment.
        return MountSettings(altitudeLimit: MountUserSettings.altitudeLimitRange.lowerBound,
                             maximumSlewSeconds: user.maximumSlewSeconds)
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
        startConnection(option: option, form: form, observer: observer)
    }

    /// Connects again after the connection was lost: to the simulated mount if that was the one, else to the mount chosen
    /// on the connection screen.
    func reconnect(observer: Observer?) {
        if let option = connectedOption, option.isDemo {
            connectDemo(option, observer: observer)
        } else {
            connect(observer: observer)
        }
    }

    /// Connects to a simulated mount.
    func connectDemo(_ option: MountConnectionOption = .demo, observer: Observer?) {
        startConnection(option: option, form: MountConnectionForm(option: option), observer: observer)
    }

    private func startConnection(option: MountConnectionOption, form: MountConnectionForm, observer: Observer?) {
        let isDemo = option.isDemo
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
        let engine = engineSettings(for: option)
        let fields = option.advancedFields
        var options = MountDriverOptions(epoch: fields.contains(.epoch) ? settings.epochChoice.epoch : nil,
                                         reversesEastWest: fields.contains(.swapEastWest) && settings.reversesEastWest,
                                         deviceNumber: form.deviceNumber)
        options.location = observer.location
        options.arrangement = fields.contains(.arrangement) ? settings.arrangement.mode : nil
        options.reversesAxis1 = fields.contains(.reverseAxis1) && settings.reversesAxis1
        options.reversesAxis2 = fields.contains(.reverseAxis2) && settings.reversesAxis2
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
        if option.discovery == .alpaca {
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
            driverDetail = result.detail
            syncedObjects = []
            alignmentHomeError = nil
            handedLocation = observer.location
            connection = .connected
            if !hasConnectedBefore {
                hasConnectedBefore = true
                MountPreferences.saveConnectedBefore()
            }
            if !isDemo {
                memory.selectedOptionID = option.id
                memory.forms[option.id] = form
            }
            startPolling(session: session, token: token)
            // A mount that Lodestar aligns has been given the location already: nothing is sent to it.
            if sendsSiteAndTime && found.canSetSiteAndTime && !option.usesLodestarAlignment {
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
                // A GoTo that is being set up has not moved the mount yet as far as the status knows, but it may just have.
                if isMoving || isWorking {
                    stopNudgeLoop()
                    motionGate?.cancel()
                    motionGate = nil
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
        motionGate?.cancel()
        motionGate = nil
        session?.shutdown()
        session = nil
        capabilities = nil
        status = .disconnected
        isStopping = false
        isWorking = false
        slewStartSeparation = nil
        slewTargetName = nil
        driverDetail = nil
        syncedObjects = []
        alignmentHomeError = nil
        handedLocation = nil
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
            // A GoTo that is still queued must not start after the stop.
            motionGate?.cancel()
            motionGate = nil
            Task {
                // Nobody can watch the mount from here, so it is stopped and let go.
                ending.interrupt()
                let stopped = await ending.run(urgent: true) { controller in
                    if controller.status.phase != .idle { try controller.abort() }
                }
                if session === ending {
                    let reason = "Disconnected when Lodestar went to the background. "
                    if case .failure(let error) = stopped.result {
                        finishSession(lost: reason + Self.stopFailureText(error))
                    } else {
                        finishSession(lost: reason + "The mount was stopped.")
                    }
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
                let outcome = await session.poll()
                guard let self, self.generation == token, !Task.isCancelled else { return }
                let polled = outcome.status
                self.apply(polled, detail: outcome.detail)
                if polled.phase == .disconnected {
                    // The engine does not stop a mount on a dead link, so a slew or a nudge may still be running.
                    let reason = (polled.lastError?.userMessage ?? MountError.connectionLost.userMessage)
                        + " The mount may still be moving if it was slewing. Stop it on its hand controller if it is."
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
    private func apply(_ new: MountStatus, detail: MountDriverDetail? = nil) {
        if let detail, detail != driverDetail { driverDetail = detail }
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
        if session === current { apply(outcome.status, detail: outcome.detail) }
        return outcome.result
    }

    /// Runs `work` on the mount's driver and takes over the status and the detail it leaves.
    private func executeOnDriver<Value: Sendable>(
        _ work: @escaping @Sendable (MountDriver) throws -> Value
    ) async -> Result<Value, MountError> {
        guard let current = session else { return .failure(.notConnected) }
        let outcome = await current.runDriver(work)
        if session === current { apply(outcome.status, detail: outcome.detail) }
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
        let gate = MountCancelFlag()
        motionGate = gate
        let result = await execute { controller in
            // A GoTo that waited in the queue while Stop was tapped must not start a slew.
            guard !gate.isCancelled else { return }
            try controller.goto(place, properMotion: motion)
        }
        if motionGate === gate { motionGate = nil }
        // Stop or Disconnect came first: the person knows, so there is nothing to report, not even a failure that the
        // interruption caused.
        if gate.isCancelled { return }
        switch result {
        case .success: slewTargetName = object.name
        case .failure(let error):
            if usesLodestarAlignment, case .notAligned = error {
                errorText = MountAlignmentText.notAlignedYet
            } else {
                errorText = error.userMessage
            }
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
        let wasEmpty = driverDetail?.alignment?.stars.isEmpty ?? true
        let result = await execute { controller in try controller.sync(place, properMotion: motion) }
        switch result {
        case .success(let synced):
            if usesLodestarAlignment {
                syncedObjects.append(MountSyncedObject(name: object.name, place: place))
                if syncedObjects.count > Self.maximumRememberedObjects { syncedObjects.removeFirst() }
                if wasEmpty { alignmentHomeError = synced.offsetDegrees }
                noticeText = MountAlignmentText.syncNotice(name: object.name, offset: synced.offsetDegrees,
                                                           starCount: driverDetail?.alignment?.stars.count ?? 1)
            } else {
                noticeText = "Synced (was \(AppFormat.separation(synced.offsetDegrees)) off)."
            }
        case .failure(let error):
            if usesLodestarAlignment, case .rejected = error {
                errorText = MountAlignmentText.rejectedText(name: object.name)
            } else {
                errorText = error.userMessage
            }
        }
    }

    /// The simulated Sky-Watcher mount stands where the person would have centred `object`.
    func centreSimulatedMount(on object: CelestialObject, observer: Observer) async {
        guard isConnected, isDemo, let current = session, !isWorking else { return }
        clearMessages()
        let place = MountTargets.resolve(object, observer: observer, date: Date()).j2000
        isWorking = true
        defer { isWorking = false }
        let outcome = await current.centreSimulated(on: place)
        guard session === current else { return }
        apply(outcome.status, detail: outcome.detail)
        if case .failure(let error) = outcome.result { errorText = error.userMessage }
    }

    // MARK: Alignment of a mount that Lodestar aligns

    /// "This is home": the mount stands at its home position now, whatever the start position said.
    func declareHomePosition() async {
        guard isConnected, usesLodestarAlignment, !isWorking else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }
        // Whatever the mount is doing stops first.
        _ = await execute { controller in try controller.abort() }
        let result = await executeOnDriver { driver in
            guard let skyWatcher = driver as? SkyWatcherDriver else { throw MountError.notSupported(feature: .other) }
            try skyWatcher.declareHomePosition()
        }
        switch result {
        case .success:
            syncedObjects = []
            alignmentHomeError = nil
            noticeText = "This is now the mount's home position. The star alignment was cleared."
        case .failure(let error):
            errorText = error.userMessage
        }
    }

    /// Drops one alignment star and fits the model to the others.
    func removeAlignedStar(at index: Int) async {
        guard isConnected, usesLodestarAlignment, !isWorking, status.phase == .idle else { return }
        clearMessages()
        let name = alignedStars.first { $0.index == index }?.name ?? "the star"
        isWorking = true
        defer { isWorking = false }
        let result = await executeOnDriver { driver in
            guard let skyWatcher = driver as? SkyWatcherDriver else { throw MountError.notSupported(feature: .other) }
            try skyWatcher.removeAlignmentPoint(index)
        }
        switch result {
        case .success:
            if driverDetail?.alignment?.stars.isEmpty ?? true {
                syncedObjects = []
                alignmentHomeError = nil
            }
            noticeText = "Removed \(name) from the alignment."
        case .failure(let error):
            errorText = error.userMessage
        }
    }

    /// Forgets the whole alignment, to start over.
    func clearAlignment() async {
        guard isConnected, usesLodestarAlignment, !isWorking, status.phase == .idle else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }
        let result = await executeOnDriver { driver in
            guard let skyWatcher = driver as? SkyWatcherDriver else { throw MountError.notSupported(feature: .other) }
            skyWatcher.clearAlignment()
        }
        switch result {
        case .success:
            syncedObjects = []
            alignmentHomeError = nil
            noticeText = "The star alignment was cleared."
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
        // Before the interruption below: a GoTo that gets past this flag has started, so the interruption reaches it.
        motionGate?.cancel()
        motionGate = nil
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
                // The repeat is timed from the start of the command: on a slow link the command takes a good part of the
                // pulse, and waiting the full repeat after it would let the pulse run out before the next one arrives.
                let began = ContinuousClock.now
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
                let remaining = Self.nudgeRepeat - (ContinuousClock.now - began)
                if remaining > .zero { try? await Task.sleep(for: remaining) }
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
        guard isConnected else { return }
        // The mount that Lodestar aligns points by the phone's location, which its driver is handed again when the phone has
        // moved. The driver forgets the alignment once the place differs by about a quarter of a degree.
        var handsOver = false
        if usesLodestarAlignment, let handed = handedLocation, status.phase != .slewing {
            let latitude = abs(new.location.latitude - handed.latitude)
            let longitude = abs(AstroMath.normalizeSignedDegrees(new.location.longitude - handed.longitude))
            handsOver = latitude > Self.siteToleranceDegrees || longitude > Self.siteToleranceDegrees
        }
        if handsOver { handedLocation = new.location }
        let hadStars = !(driverDetail?.alignment?.stars.isEmpty ?? true)
        let sendsPlace = handsOver
        Task {
            _ = await execute { controller in
                controller.observer = new
                if sendsPlace { _ = try? controller.setSiteAndTime(location: new.location) }
            }
            if sendsPlace && hadStars && (driverDetail?.alignment?.stars.isEmpty ?? true) {
                syncedObjects = []
                alignmentHomeError = nil
                noticeText = "Your location changed, so the star alignment was cleared. Align on a star again."
            }
        }
    }

    /// Rebuilds the controller with new limits once the mount is idle. The old limits stay in force until then, and the
    /// check before each GoTo uses the new altitude limit at once.
    private func scheduleReconfigure() {
        reconfigureTask?.cancel()
        // The altitude limit of a mount that Lodestar aligns is applied in `goTo`; its other limits apply at the next connection.
        guard isConnected, !usesLodestarAlignment else { return }
        reconfigureTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reconfigureDelay)
            for _ in 0..<60 {
                guard let self, !Task.isCancelled, self.isConnected, let current = self.session else { return }
                if self.status.phase == .idle {
                    let result = await current.reconfigure(self.engineSettings(for: self.connectedOption))
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
        guard discoveryState != .searching, let kind = selectedOption.discovery else { return }
        discoveryState = .searching
        discovered = []
        let flag = MountCancelFlag()
        discoveryFlag = flag
        discoveryTask = Task { [weak self] in
            let found = await mountRunBlocking {
                switch kind {
                case .alpaca: return MountAlpacaDiscovery.search(cancel: flag)
                case .skyWatcher: return MountSkyWatcherProbe.search(cancel: flag)
                }
            }
            guard let self, !flag.isCancelled else { return }
            self.discovered = found.devices
            self.discoveryState = .finished(serverCount: found.serverCount, deviceCount: found.devices.count)
        }
    }

    func cancelDiscovery() {
        discoveryFlag?.cancel()
        discoveryFlag = nil
        discoveryTask?.cancel()
        discoveryTask = nil
        if discoveryState == .searching { discoveryState = .idle }
    }

    /// Puts the address and the device of a search result into the form of the selected kind of mount.
    func choose(_ device: MountFoundDevice) {
        updateForm { form in
            form.host = device.host
            form.port = device.port
            form.deviceNumber = device.deviceNumber
            form.deviceName = device.name
        }
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

/// An object the mount was synced to, remembered to name the alignment stars.
struct MountSyncedObject: Hashable, Sendable {
    let name: String
    let place: EquatorialCoordinate
}

/// One star of the alignment with its name and how well the fitted model explains it.
struct MountAlignedStar: Identifiable, Hashable, Sendable {
    /// The star's place in the driver's list, which `MountService.removeAlignedStar(at:)` counts in.
    let index: Int
    let name: String
    let residualDegrees: Double?

    var id: Int { index }
}

/// The words for the alignment of a mount that Lodestar aligns.
enum MountAlignmentText {
    /// What a Sky-Watcher mount says to Go to before the first sync.
    static let notAlignedYet = "Not aligned yet. Centre a star with the nudge pad, then tap Sync."
    /// Said in place of the usual "send location and time" explanation: this mount is sent nothing.
    static let siteAndTime = "Uses your location and the phone's clock for pointing; nothing is sent to the mount."
    /// A sync that moves the mount's idea of its position by more than this is suspicious, degrees.
    private static let suspiciousOffsetDegrees = 0.5

    /// "Aligned on 3 stars, 0.02° residual, ≈ 0.2° accuracy", "Aligned on 1 star, ≈ 1.0° accuracy" or what to do first.
    static func line(_ alignment: MountAlignmentDetail?) -> String {
        guard let alignment, !alignment.stars.isEmpty else { return "Not aligned: centre a star and tap Sync" }
        let count = alignment.stars.count
        var text = "Aligned on \(count) star\(count == 1 ? "" : "s")"
        if count > 1, let residual = alignment.maximumResidualDegrees {
            text += ", \(AngleFormatter.formatDegrees(residual, decimals: 2)) residual"
        }
        if let predicted = alignment.predictedErrorDegrees {
            text += ", \u{2248} \(accuracy(predicted)) accuracy"
        }
        return text
    }

    /// An angle with the digits that mean something: 0.05°, 0.2°, 1.0°, 12°.
    static func accuracy(_ degrees: Double) -> String {
        if degrees < 0.095 { return AngleFormatter.formatDegrees(degrees, decimals: 2) }
        if degrees < 9.5 { return AngleFormatter.formatDegrees(degrees, decimals: 1) }
        return AngleFormatter.formatDegrees(degrees, decimals: 0)
    }

    /// After a sync: the home position error at the first star, the offset at the others.
    static func syncNotice(name: String, offset: Double, starCount: Int) -> String {
        let off = AppFormat.separation(offset)
        if starCount <= 1 { return "Synced to \(name). The mount's home position was \(off) off." }
        if offset > suspiciousOffsetDegrees {
            return "Synced to \(name). The mount was \(off) off, which is a lot: check that you centred the right star "
                + "and that the mount has not been bumped."
        }
        return "Synced to \(name). The mount was \(off) off."
    }

    /// When the alignment refused the star.
    static func rejectedText(name: String) -> String {
        "That does not fit the other stars. Check that you centred \(name)."
    }
}
