import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Tests of `MountService` (Services/MountService.swift): the connection state machine, disconnecting, the background,
/// the loss of the link. The commands, the nudge loop, the observer and the alignment live in extensions of this class
/// (MountServiceCommandTests.swift, MountServiceNudgeTests.swift, MountServiceAlignmentTests.swift) because they share
/// the fixtures below.
///
/// `MountService` is a singleton with a private initializer, so every test works on `MountService.shared` and leaves it
/// disconnected (see `setUp` and `tearDown`). The mount underneath is never real: `connectDemo` takes any
/// `MountConnectionOption` whose id starts with "demo", and the option's `makeDriver` hands the service a scripted driver
/// (`Fake`) behind the in-memory `.simulated` channel, so no socket is ever opened. A few tests use the app's own
/// simulated mounts (`MountConnectionOption.demo`, `.demoSkyWatcher`).
///
/// The service stores its limits and its last address in `UserDefaults.standard` (it has no other store, see
/// `MountPreferences`): the tests put back what they found, and the first successful connection also writes the
/// "connected before" flag there. The test process has a defaults domain of its own.
@MainActor
final class MountServiceTests: XCTestCase {
    // MARK: - Fixtures

    /// Blocks the mount's worker thread inside the scripted driver while it is closed. A test closes it, waits until
    /// `isWaiting`, does something while the worker is stuck, and opens it again.
    final class Gate: @unchecked Sendable {
        private let condition = NSCondition()
        private var closed = false
        private var waiting = false

        func close() {
            condition.lock()
            closed = true
            condition.unlock()
        }

        func open() {
            condition.lock()
            closed = false
            condition.broadcast()
            condition.unlock()
        }

        /// Whether a thread is stuck in `pass` right now.
        var isWaiting: Bool {
            condition.lock()
            defer { condition.unlock() }
            return waiting
        }

        /// Called on the worker thread. Gives up after 30 seconds, so that a test that failed halfway cannot hang the run.
        func pass() {
            condition.lock()
            defer { condition.unlock() }
            let deadline = Date(timeIntervalSinceNow: 30.0)
            while closed {
                waiting = true
                if !condition.wait(until: deadline) { closed = false }
            }
            waiting = false
        }
    }

    /// A thread-safe list of strings that jobs on the worker thread add to.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        func add(_ item: String) {
            lock.lock()
            items.append(item)
            lock.unlock()
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }

        var count: Int { all.count }
    }

    struct Boom: Error {}

    /// A mount driver that the test scripts and whose calls it records. Every method is safe to call from the worker thread
    /// while the test changes the script on the main thread.
    final class Fake: MountDriver, @unchecked Sendable {
        enum Event: Equatable {
            case connect
            case disconnect
            case slew(EquatorialCoordinate)
            case sync(EquatorialCoordinate)
            case abort
            case tracking(Bool)
            case nudgeStart(MountNudgeDirection, MountNudgeRate, Double)
            case nudgeStop(MountNudgeDirection)
            case siteAndTime(GeographicLocation)
        }

        struct Script {
            var capabilities = Fake.makeCapabilities()
            var position = EquatorialCoordinate(rightAscension: 100.0, declination: 20.0)
            var goal: EquatorialCoordinate?
            var slewing = false
            var tracking: Bool? = true
            var aligned: Bool?
            var connectError: MountError?
            /// Makes every read (position, slewing, tracking, aligned) fail.
            var readError: MountError?
            var slewError: MountError?
            var syncError: MountError?
            var abortError: MountError?
            var trackingError: MountError?
            var nudgeError: MountError?
            var siteError: MountError?
        }

        static func makeCapabilities(name: String = "Fake Mount", canSlew: Bool = true, canSync: Bool = true,
                                     canAbort: Bool = true, canSetTracking: Bool = true, canNudge: Bool = true,
                                     canSetSiteAndTime: Bool = true, gotoNeedsAlignment: Bool = false,
                                     isAligned: Bool? = true) -> MountCapabilities {
            MountCapabilities(kind: .lx200, name: name, firmware: nil, canSlew: canSlew, canSync: canSync,
                              canAbort: canAbort, canSetTracking: canSetTracking, canNudge: canNudge,
                              canSetSiteAndTime: canSetSiteAndTime, gotoNeedsAlignment: gotoNeedsAlignment,
                              isAligned: isAligned)
        }

        /// Closed by a test, this stops the next `readPosition` (a poll, for one) until it is opened.
        let readGate = Gate()
        /// Closed by a test, this stops `connect` until it is opened.
        let connectGate = Gate()

        private let lock = NSLock()
        private var script = Script()
        private var log: [Event] = []
        private var slewingReadCount = 0

        func configure(_ change: (inout Script) -> Void) {
            lock.lock()
            change(&script)
            lock.unlock()
        }

        private var current: Script {
            lock.lock()
            defer { lock.unlock() }
            return script
        }

        private func record(_ event: Event) {
            lock.lock()
            log.append(event)
            lock.unlock()
        }

        /// The mount reaches its target and stops.
        func finishSlew() {
            configure { script in
                if let goal = script.goal { script.position = goal }
                script.slewing = false
            }
        }

        /// The mount stops where it stands, short of the target, without being told to.
        func stopShort() {
            configure { $0.slewing = false }
        }

        func releaseAll() {
            readGate.open()
            connectGate.open()
        }

        // MARK: What the driver was asked

        var events: [Event] {
            lock.lock()
            defer { lock.unlock() }
            return log
        }

        var connectCount: Int { events.filter { $0 == .connect }.count }
        var disconnectCount: Int { events.filter { $0 == .disconnect }.count }
        var abortCount: Int { events.filter { $0 == .abort }.count }

        var slews: [EquatorialCoordinate] {
            events.compactMap { event -> EquatorialCoordinate? in
                if case .slew(let place) = event { return place }
                return nil
            }
        }

        var syncs: [EquatorialCoordinate] {
            events.compactMap { event -> EquatorialCoordinate? in
                if case .sync(let place) = event { return place }
                return nil
            }
        }

        var trackingCalls: [Bool] {
            events.compactMap { event -> Bool? in
                if case .tracking(let enabled) = event { return enabled }
                return nil
            }
        }

        var nudgeStarts: [(direction: MountNudgeDirection, rate: MountNudgeRate, seconds: Double)] {
            events.compactMap { event -> (direction: MountNudgeDirection, rate: MountNudgeRate, seconds: Double)? in
                if case .nudgeStart(let direction, let rate, let seconds) = event {
                    return (direction: direction, rate: rate, seconds: seconds)
                }
                return nil
            }
        }

        var nudgeStopCount: Int {
            events.filter { event in
                if case .nudgeStop = event { return true }
                return false
            }.count
        }

        var siteLocations: [GeographicLocation] {
            events.compactMap { event -> GeographicLocation? in
                if case .siteAndTime(let location) = event { return location }
                return nil
            }
        }

        /// How many times the controller asked whether the mount is slewing: once per poll.
        var slewingReads: Int {
            lock.lock()
            defer { lock.unlock() }
            return slewingReadCount
        }

        // MARK: MountDriver

        var kind: MountProtocol { .lx200 }
        var epoch: MountEpoch { .j2000 }

        func connect() throws -> MountCapabilities {
            record(.connect)
            connectGate.pass()
            let snapshot = current
            if let error = snapshot.connectError { throw error }
            return snapshot.capabilities
        }

        func disconnect() {
            record(.disconnect)
        }

        func readPosition() throws -> EquatorialCoordinate {
            readGate.pass()
            let snapshot = current
            if let error = snapshot.readError { throw error }
            return snapshot.position
        }

        func readSlewing() throws -> Bool {
            lock.lock()
            slewingReadCount += 1
            lock.unlock()
            let snapshot = current
            if let error = snapshot.readError { throw error }
            return snapshot.slewing
        }

        func readTracking() throws -> Bool? {
            let snapshot = current
            if let error = snapshot.readError { throw error }
            return snapshot.tracking
        }

        func readAligned() throws -> Bool? {
            let snapshot = current
            if let error = snapshot.readError { throw error }
            return snapshot.aligned
        }

        func slew(to target: EquatorialCoordinate) throws {
            if let error = current.slewError { throw error }
            record(.slew(target))
            configure { script in
                script.goal = target
                script.slewing = true
            }
        }

        func sync(to target: EquatorialCoordinate) throws {
            if let error = current.syncError { throw error }
            record(.sync(target))
            configure { $0.position = target }
        }

        func abort() throws {
            record(.abort)
            if let error = current.abortError { throw error }
            configure { $0.slewing = false }
        }

        func setTracking(_ enabled: Bool) throws {
            if let error = current.trackingError { throw error }
            record(.tracking(enabled))
            configure { $0.tracking = enabled }
        }

        func startNudge(direction: MountNudgeDirection, rate: MountNudgeRate, durationSeconds: Double) throws {
            if let error = current.nudgeError { throw error }
            record(.nudgeStart(direction, rate, durationSeconds))
        }

        func stopNudge(direction: MountNudgeDirection) throws {
            record(.nudgeStop(direction))
        }

        func setSiteAndTime(location: GeographicLocation, date: Date) throws {
            if let error = current.siteError { throw error }
            record(.siteAndTime(location))
        }
    }

    // MARK: Options, observers, targets

    /// A connection option for `makeDriver`. Its id starts with "demo", so the service treats it as a simulated mount and
    /// uses the in-memory channel.
    static func option(id: String = "demo-test", title: String = "Test mount", lodestarAligned: Bool = false,
                       makeDriver: @escaping @Sendable (MountChannel, MountDriverOptions) throws -> MountDriverBundle)
        -> MountConnectionOption {
        MountConnectionOption(
            id: id, title: title, summary: "A scripted mount for the tests.", defaultHost: "", defaultPort: 0,
            links: [.tcp], presets: [], discovery: nil, advancedFields: [], usesLodestarAlignment: lodestarAligned,
            addressNote: "", makeDriver: makeDriver)
    }

    /// A connection option whose driver is `fake`.
    static func option(for fake: Fake, id: String = "demo-test", title: String = "Test mount",
                       lodestarAligned: Bool = false,
                       centre: (@Sendable (EquatorialCoordinate) -> Void)? = nil) -> MountConnectionOption {
        option(id: id, title: title, lodestarAligned: lodestarAligned) { _, _ in
            MountDriverBundle(driver: fake, clock: SystemMountClock(), centreSimulated: centre)
        }
    }

    /// A place on Earth where the Sun is as high (`sunUp`) or as low as it gets right now, 24 meridians apart.
    /// At latitude 35 the Sun is then above 28 degrees, or below -25 degrees, on any day of the year.
    static func placeOnEarth(sunUp: Bool, latitude: Double = 35.0) -> Observer {
        let now = Date()
        var best = Observer(location: GeographicLocation(latitude: latitude, longitude: 0.0, elevation: 0.0))
        var bestAltitude = sunUp ? -Double.infinity : Double.infinity
        for step in 0..<24 {
            let longitude = -180.0 + 15.0 * Double(step)
            let place = Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: 0.0))
            let altitude = SkyFrame(date: now, observer: place).horizontal(of: .sun, refraction: false).altitude
            let better = sunUp ? altitude > bestAltitude : altitude < bestAltitude
            if better {
                best = place
                bestAltitude = altitude
            }
        }
        return best
    }

    /// A custom target that stands at `altitude` degrees in the direction `azimuth` for `place`, now.
    static func target(altitude: Double, azimuth: Double = 180.0, name: String = "Test Target",
                       seenFrom place: Observer) -> CelestialObject {
        let frame = SkyFrame(date: Date(), observer: place)
        let j2000 = frame.j2000(fromHorizontal: HorizontalCoordinate(azimuth: azimuth, altitude: altitude), refracted: false)
        return CelestialObject.custom(name: name, j2000: j2000)
    }

    /// The Sun, from the bundled catalog (the only way to get an object that `MountTargets.isSun` accepts).
    static let sun: CelestialObject? = (try? Catalog.loadBundled())?.object(id: "sun")

    // MARK: - Set-up

    /// The place of most tests: night, the Sun far below the horizon, so that no target is near it.
    var observer: Observer!
    var fakes: [Fake] = []
    var savedSettings = MountUserSettings()
    var savedMemory = MountConnectionMemory()

    var service: MountService { MountService.shared }

    override func setUp() async throws {
        try await super.setUp()
        await resetService()
        savedSettings = service.settings
        savedMemory = service.memory
        service.settings = MountUserSettings()
        service.memory = MountConnectionMemory()
        observer = Self.placeOnEarth(sunUp: false)
        fakes = []
    }

    override func tearDown() async throws {
        for fake in fakes {
            fake.releaseAll()
            fake.configure { script in
                script.abortError = nil
                script.readError = nil
            }
        }
        await resetService()
        service.settings = savedSettings
        service.memory = savedMemory
        fakes = []
        try await super.tearDown()
    }

    /// Brings the shared service back to "disconnected", whatever a test left behind.
    func resetService() async {
        let current = service
        switch current.connection {
        case .disconnected: break
        case .connecting: current.cancelConnect()
        case .connected, .lost: current.disconnect()
        }
        let done = await waitUntil { current.connection == .disconnected }
        if !done { XCTFail("the shared MountService did not return to the disconnected state") }
        current.dismissError()
        current.dismissNotice()
    }

    // MARK: Waiting

    /// Polls `condition` every few milliseconds until it holds or `timeout` seconds have passed.
    @discardableResult
    func waitUntil(timeout: TimeInterval = 20.0, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }

    /// Fails the test unless `condition` holds before `timeout`.
    func expect(_ what: String, timeout: TimeInterval = 20.0, file: StaticString = #filePath, line: UInt = #line,
                _ condition: () -> Bool) async {
        let reached = await waitUntil(timeout: timeout, condition)
        if !reached { XCTFail("timed out waiting for \(what)", file: file, line: line) }
    }

    /// A short pause for work that cannot be observed: either something stray would have happened by now or it would not.
    func settle(_ seconds: TimeInterval = 0.5) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000.0))
    }

    /// Connects the service to a new scripted mount and waits for the connection.
    @discardableResult
    func connectFake(lodestar: Bool = false, id: String = "demo-test", title: String = "Test mount",
                     seenFrom place: Observer? = nil, _ configure: (Fake) -> Void = { _ in }) async -> Fake {
        let fake = Fake()
        configure(fake)
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake, id: id, title: title, lodestarAligned: lodestar),
                            observer: place ?? observer)
        await expect("the connection to \(id)") { service.connection == .connected }
        return fake
    }

    /// A target high in the south for `observer`, far from the Sun.
    func highTarget(_ name: String = "High Target") -> CelestialObject {
        Self.target(altitude: 60.0, name: name, seenFrom: observer)
    }

    /// The lifecycle helper the service keeps in a private property. The shim in the test package has no other way to
    /// reach it, so it is found by reflection; the test is skipped if that fails.
    func lifecycle() throws -> MountLifecycle {
        for child in Mirror(reflecting: service).children where child.label == "lifecycle" {
            if let helper = child.value as? MountLifecycle { return helper }
        }
        throw XCTSkip("MountService keeps its lifecycle helper in a private property and reflection did not find it.")
    }

    // MARK: - A service that is not connected

    func testAServiceThatIsNotConnectedSaysSo() {
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertEqual(service.status, MountStatus.disconnected)
        XCTAssertNil(service.capabilities)
        XCTAssertFalse(service.isConnected)
        XCTAssertFalse(service.isMoving)
        XCTAssertFalse(service.isWorking)
        XCTAssertFalse(service.isStopping)
        XCTAssertFalse(service.isDemo)
        XCTAssertNil(service.connectedOption)
        XCTAssertNil(service.connectedAddress)
        XCTAssertNil(service.errorText)
        XCTAssertNil(service.noticeText)
        XCTAssertNil(service.connectError)
        XCTAssertEqual(service.summaryText, "Not connected")
        XCTAssertEqual(service.displayName, "LX200 / OnStep")
        XCTAssertEqual(service.displayedOption, MountConnectionOption.lx200)
        XCTAssertEqual(service.showsAimButton, service.hasConnectedBefore)
    }

    func testNothingIsReportedAboutAnAlignmentWithoutAConnection() {
        XCTAssertFalse(service.usesLodestarAlignment)
        XCTAssertFalse(service.needsFirstSync)
        XCTAssertFalse(service.startsAwayFromHome)
        XCTAssertNil(service.alignmentWarning)
        XCTAssertNil(service.alignmentLine)
        XCTAssertNil(service.startPositionLine)
        XCTAssertNil(service.trackingLine)
        XCTAssertNil(service.pierSideLine)
        XCTAssertNil(service.trackingAndPierLine)
        XCTAssertNil(service.trackingStopText)
        XCTAssertTrue(service.alignedStars.isEmpty)
        XCTAssertTrue(service.syncedObjects.isEmpty)
        XCTAssertNil(service.alignmentHomeError)
        XCTAssertNil(service.driverDetail)
    }

    // MARK: - Choosing the kind of mount

    func testTheSelectedKindOfMountComesFromTheMemory() {
        service.selectedOptionID = "nexstar"
        XCTAssertEqual(service.selectedOption.id, "nexstar")
        XCTAssertEqual(service.selectedOptionID, "nexstar")
        XCTAssertEqual(service.memory.selectedOptionID, "nexstar")
        XCTAssertEqual(service.displayedOption.id, "nexstar")
        XCTAssertEqual(service.displayName, MountConnectionOption.nexstar.title)
    }

    func testAnUnknownKindOfMountFallsBackToLX200() {
        service.selectedOptionID = "no-such-mount"
        XCTAssertEqual(service.selectedOption.id, "lx200")
        XCTAssertEqual(service.selectedOptionID, "lx200")
        XCTAssertEqual(service.memory.selectedOptionID, "no-such-mount")
    }

    func testTheSimulatedMountsAreNotInThePicker() {
        service.selectedOptionID = "demo"
        XCTAssertEqual(service.selectedOption, MountConnectionOption.demo)
        XCTAssertFalse(MountConnectionOption.all.contains(MountConnectionOption.demo))
    }

    func testTheAddressFormBelongsToTheSelectedKindOfMount() {
        XCTAssertEqual(service.form.host, "192.168.0.1")
        XCTAssertEqual(service.form.port, 9999)
        XCTAssertEqual(service.form.link, .tcp)
        service.updateForm { form in
            form.host = "10.1.2.3"
            form.port = 4030
        }
        XCTAssertEqual(service.form.host, "10.1.2.3")
        XCTAssertEqual(service.form.port, 4030)
        XCTAssertEqual(service.memory.forms["lx200"]?.port, 4030)
        service.selectedOptionID = "nexstar"
        XCTAssertEqual(service.form.host, "192.168.4.1")
        XCTAssertEqual(service.form.port, 11880)
        XCTAssertEqual(service.form.link, .udp)
        service.selectedOptionID = "lx200"
        XCTAssertEqual(service.form.host, "10.1.2.3")
    }

    func testChoosingASearchResultFillsTheAddressForm() {
        service.selectedOptionID = "alpaca"
        service.choose(MountFoundDevice(host: "192.168.1.20", port: 11111, deviceNumber: 2, name: "Dome Telescope"))
        XCTAssertEqual(service.form.host, "192.168.1.20")
        XCTAssertEqual(service.form.port, 11111)
        XCTAssertEqual(service.form.deviceNumber, 2)
        XCTAssertEqual(service.form.deviceName, "Dome Telescope")
        XCTAssertEqual(service.form.addressText, "192.168.1.20:11111")
    }

    func testKindsOfMountThatCannotSearchIgnoreASearchRequest() {
        XCTAssertNil(service.selectedOption.discovery)
        service.startDiscovery()
        XCTAssertEqual(service.discoveryState, .idle)
        XCTAssertTrue(service.discovered.isEmpty)
        service.cancelDiscovery()
        XCTAssertEqual(service.discoveryState, .idle)
    }

    func testChangingTheKindOfMountResetsTheSearch() {
        service.selectedOptionID = "alpaca"
        service.selectedOptionID = "skywatcher"
        XCTAssertEqual(service.discoveryState, .idle)
        XCTAssertTrue(service.discovered.isEmpty)
    }

    // MARK: - Refusing to connect

    func testConnectingNeedsAPlace() {
        let fake = Fake()
        service.connectDemo(Self.option(for: fake), observer: nil)
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertEqual(service.errorText, "Lodestar needs to know where you are to check targets against your altitude "
            + "limit. Allow location access or choose an observing site first.")
        XCTAssertNil(service.connectedOption)
        XCTAssertTrue(fake.events.isEmpty)
    }

    func testConnectingNeedsAnAddress() {
        service.selectedOptionID = "alpaca"
        service.connect(observer: observer)
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertEqual(service.errorText, "Enter the mount's address first.")
        service.dismissError()
        service.updateForm { $0.host = "   " }
        service.connect(observer: observer)
        XCTAssertEqual(service.errorText, "Enter the mount's address first.")
        XCTAssertEqual(service.connection, .disconnected)
    }

    func testAnAddressOrPortThatCannotBeUsedIsExplained() {
        let expected = "That address or port can't be used. Enter an IP address such as 192.168.0.1 and a port "
            + "from 1 to 65535."
        for port in [0, 65_536, -1] {
            service.updateForm { form in
                form.host = "192.168.0.1"
                form.port = port
            }
            service.connect(observer: observer)
            XCTAssertEqual(service.errorText, expected, "port \(port)")
            XCTAssertEqual(service.connection, .disconnected, "port \(port)")
        }
        // A port typed behind the host wins over the port field.
        service.updateForm { form in
            form.host = "192.168.0.1:70000"
            form.port = 9999
        }
        service.connect(observer: observer)
        XCTAssertEqual(service.errorText, expected)
        XCTAssertNil(service.connectedOption)
    }

    // MARK: - Connecting

    func testConnectingToAMountReachesTheConnectedState() async {
        let fake = Fake()
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake, title: "Scripted Mount"), observer: observer)
        // The state changes at once; the handshake runs on the worker thread.
        XCTAssertEqual(service.connection, .connecting)
        XCTAssertEqual(service.summaryText, "Connecting\u{2026}")
        XCTAssertTrue(service.showsAimButton)
        XCTAssertEqual(service.connectedOption?.id, "demo-test")
        XCTAssertEqual(service.displayedOption.id, "demo-test")
        XCTAssertEqual(service.displayName, "Scripted Mount")
        XCTAssertTrue(service.isDemo)
        XCTAssertNil(service.connectedAddress)
        XCTAssertFalse(service.isConnected)
        await expect("the connection") { service.connection == .connected }
        XCTAssertEqual(service.capabilities, Fake.makeCapabilities())
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertEqual(service.status.position, EquatorialCoordinate(rightAscension: 100.0, declination: 20.0))
        XCTAssertEqual(service.status.isTracking, true)
        XCTAssertEqual(service.trackingLine, "Tracking")
        XCTAssertTrue(service.isConnected)
        XCTAssertFalse(service.isMoving)
        XCTAssertEqual(service.displayName, "Fake Mount (simulated)")
        XCTAssertEqual(service.summaryText, "Fake Mount (simulated)")
        XCTAssertEqual(fake.connectCount, 1)
        XCTAssertNil(service.errorText)
        XCTAssertNil(service.connectError)
    }

    func testTheFirstConnectionMakesTheAimButtonStay() async {
        await connectFake()
        XCTAssertTrue(service.hasConnectedBefore)
        XCTAssertTrue(service.showsAimButton)
        service.disconnect()
        await expect("the disconnection") { service.connection == .disconnected }
        XCTAssertTrue(service.hasConnectedBefore)
        XCTAssertTrue(service.showsAimButton)
    }

    func testAMountWithoutANameIsCalledByItsKind() async {
        await connectFake(title: "Nameless Mount") { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(name: "") }
        }
        XCTAssertEqual(service.displayName, "Nameless Mount")
        XCTAssertEqual(service.summaryText, "Nameless Mount")
    }

    func testAConnectionAttemptWhileConnectingIsIgnored() async {
        let first = Fake()
        first.connectGate.close()
        fakes.append(first)
        service.connectDemo(Self.option(for: first, id: "demo-first"), observer: observer)
        await expect("the handshake to start") { first.connectGate.isWaiting }
        let second = Fake()
        fakes.append(second)
        service.connectDemo(Self.option(for: second, id: "demo-second"), observer: observer)
        XCTAssertEqual(service.connectedOption?.id, "demo-first")
        first.connectGate.open()
        await expect("the connection") { service.connection == .connected }
        XCTAssertEqual(service.connectedOption?.id, "demo-first")
        XCTAssertEqual(first.connectCount, 1)
        XCTAssertEqual(second.connectCount, 0)
    }

    func testAConnectionAttemptWhileConnectedIsIgnored() async {
        let first = await connectFake(id: "demo-first")
        let second = Fake()
        fakes.append(second)
        service.connectDemo(Self.option(for: second, id: "demo-second"), observer: observer)
        await settle()
        XCTAssertEqual(service.connection, .connected)
        XCTAssertEqual(service.connectedOption?.id, "demo-first")
        XCTAssertEqual(second.connectCount, 0)
        XCTAssertEqual(first.disconnectCount, 0)
    }

    // MARK: Cancelling a connection

    func testCancellingAConnectionGoesBackToDisconnected() async {
        let fake = Fake()
        fake.connectGate.close()
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake), observer: observer)
        await expect("the handshake to start") { fake.connectGate.isWaiting }
        service.cancelConnect()
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertNil(service.connectedOption)
        XCTAssertNil(service.connectedAddress)
        XCTAssertFalse(service.isDemo)
        XCTAssertNil(service.errorText)
        XCTAssertEqual(service.summaryText, "Not connected")
        fake.connectGate.open()
        await expect("the abandoned session to be let go") { fake.disconnectCount >= 1 }
        await settle()
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertNil(service.capabilities)
        XCTAssertEqual(service.status, MountStatus.disconnected)
    }

    func testTheResultOfACancelledConnectionDoesNotTouchTheNextConnection() async {
        let stale = Fake()
        stale.connectGate.close()
        fakes.append(stale)
        service.connectDemo(Self.option(for: stale, id: "demo-stale"), observer: observer)
        await expect("the first handshake to start") { stale.connectGate.isWaiting }
        service.cancelConnect()
        XCTAssertEqual(service.connection, .disconnected)
        // Another mount is connected while the first handshake is still stuck.
        let fresh = await connectFake(id: "demo-fresh") { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(name: "Fresh Mount") }
        }
        stale.connectGate.open()
        await expect("the stale session to be let go") { stale.disconnectCount >= 1 }
        await settle()
        XCTAssertEqual(service.connection, .connected)
        XCTAssertEqual(service.connectedOption?.id, "demo-fresh")
        XCTAssertEqual(service.capabilities?.name, "Fresh Mount")
        XCTAssertEqual(fresh.disconnectCount, 0)
        XCTAssertNil(service.errorText)
    }

    func testCancelConnectDoesNothingOnAnEstablishedConnection() async {
        await connectFake()
        service.cancelConnect()
        XCTAssertEqual(service.connection, .connected)
        XCTAssertNotNil(service.capabilities)
    }

    func testStopWhileConnectingCancelsTheConnection() async {
        let fake = Fake()
        fake.connectGate.close()
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake), observer: observer)
        await expect("the handshake to start") { fake.connectGate.isWaiting }
        service.stop()
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertFalse(service.isStopping)
    }

    func testStopWithoutAConnectionDoesNothing() {
        service.stop()
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertFalse(service.isStopping)
        XCTAssertNil(service.noticeText)
        XCTAssertNil(service.errorText)
    }

    // MARK: Failed connections

    func testAHandshakeThatFailsIsReportedAndLeavesTheServiceDisconnected() async {
        let fake = Fake()
        fake.configure { $0.connectError = .timeout(operation: "handshake") }
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake), observer: observer)
        await expect("the failure") { service.connection == .disconnected }
        XCTAssertEqual(service.errorText, "The mount didn't answer in time (handshake).")
        XCTAssertEqual(service.connectError, .timeout(operation: "handshake"))
        XCTAssertNil(service.connectedOption)
        XCTAssertNil(service.connectedAddress)
        XCTAssertFalse(service.isDemo)
        XCTAssertNil(service.capabilities)
        XCTAssertEqual(service.status, MountStatus.disconnected)
        XCTAssertEqual(fake.connectCount, 1)
        service.dismissError()
        XCTAssertNil(service.errorText)
        XCTAssertNil(service.connectError)
    }

    func testAMountThatRefusesTheHandshakeIsExplained() async {
        let fake = Fake()
        fake.configure { $0.connectError = .rejected(detail: "wrong firmware") }
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake), observer: observer)
        await expect("the failure") { service.errorText != nil }
        XCTAssertEqual(service.errorText, "The mount rejected the command: wrong firmware.")
        XCTAssertEqual(service.connection, .disconnected)
    }

    func testADriverThatCannotBeMadeIsReported() async {
        let option = Self.option(id: "demo-broken") { _, _ in
            throw MountError.invalidInput(detail: "this mount needs a TCP connection")
        }
        service.connectDemo(option, observer: observer)
        await expect("the failure") { service.connection == .disconnected }
        XCTAssertEqual(service.errorText, "That value can't be used: this mount needs a TCP connection.")
        XCTAssertEqual(service.connectError, .invalidInput(detail: "this mount needs a TCP connection"))
        XCTAssertNil(service.connectedOption)
    }

    func testAnUnexpectedFailureBecomesATransportError() async {
        let option = Self.option(id: "demo-boom") { _, _ in throw Boom() }
        service.connectDemo(option, observer: observer)
        await expect("the failure") { service.connection == .disconnected }
        XCTAssertEqual(service.errorText, "Could not talk to the mount: unexpected failure.")
        XCTAssertEqual(service.connectError, .transport(detail: "unexpected failure"))
    }

    func testAConnectionCanBeMadeAfterAFailedOne() async {
        let broken = Fake()
        broken.configure { $0.connectError = .busy }
        fakes.append(broken)
        service.connectDemo(Self.option(for: broken), observer: observer)
        await expect("the failure") { service.connection == .disconnected }
        XCTAssertNotNil(service.errorText)
        await connectFake()
        XCTAssertEqual(service.connection, .connected)
        XCTAssertNil(service.errorText, "a new attempt starts without the old message")
        XCTAssertNil(service.connectError)
    }

    // MARK: Site and time at connection

    func testTheSiteAndTimeAreSentOnceWhenAMountIsConnected() async {
        let fake = await connectFake()
        await expect("the location to be sent") { !fake.siteLocations.isEmpty }
        XCTAssertEqual(fake.siteLocations, [observer.location])
        XCTAssertNil(service.noticeText, "the automatic send is silent")
        XCTAssertNil(service.errorText)
    }

    func testSendingTheSiteAndTimeCanBeSwitchedOff() async {
        service.settings.sendsSiteAndTime = false
        let fake = await connectFake()
        await settle()
        XCTAssertTrue(fake.siteLocations.isEmpty)
    }

    func testAMountThatCannotTakeTheSiteAndTimeIsSentNothing() async {
        let fake = await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(canSetSiteAndTime: false) }
        }
        await settle()
        XCTAssertTrue(fake.siteLocations.isEmpty)
        XCTAssertNil(service.errorText)
    }

    func testAMountThatLodestarAlignsIsSentNothingAtConnection() async {
        let fake = await connectFake(lodestar: true)
        await settle()
        XCTAssertTrue(fake.siteLocations.isEmpty)
    }

    func testRefusedSiteAndTimeAreReportedButTheConnectionStays() async {
        let fake = Fake()
        fake.configure { $0.siteError = .rejected(detail: "clock") }
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake), observer: observer)
        await expect("the report") { service.errorText != nil }
        XCTAssertEqual(service.errorText, "Could not send the location and time. The mount rejected the command: clock.")
        XCTAssertEqual(service.connection, .connected)
    }

    // MARK: - The app's own simulated mount

    func testTheSimulatedMountConnectsAndStartsHighInTheSouthernSky() async {
        service.connectDemo(observer: observer)
        await expect("the simulated mount") { service.connection == .connected }
        XCTAssertTrue(service.isDemo)
        XCTAssertEqual(service.connectedOption?.id, "demo")
        XCTAssertNil(service.connectedAddress)
        XCTAssertEqual(service.capabilities?.kind, .lx200)
        XCTAssertTrue(service.displayName.hasSuffix(" (simulated)"), service.displayName)
        XCTAssertEqual(service.status.phase, .idle)
        guard let position = service.status.position else { return XCTFail("the simulated mount reports no position") }
        let altitude = SkyFrame(date: Date(), observer: observer).horizontal(j2000: position, refraction: false).altitude
        // The simulated mount takes the J2000 place for its own (mean of date) frame, which shifts it by the precession, 0.4 degrees.
        XCTAssertEqual(altitude, 60.0, accuracy: 1.0)
        XCTAssertTrue(service.hasConnectedBefore)
    }

    func testAGoToOnTheSimulatedMountSlewsAndArrives() async {
        service.connectDemo(observer: observer)
        await expect("the simulated mount") { service.connection == .connected }
        let announced = MountLifecycle.announcements.count
        // Eight degrees higher than where the simulated mount starts: about two seconds of slewing at 4 degrees a second.
        let target = Self.target(altitude: 68.0, name: "Simulated Target", seenFrom: observer)
        await service.goTo(target, observer: observer)
        XCTAssertNil(service.errorText)
        XCTAssertEqual(service.slewTargetName, "Simulated Target")
        XCTAssertEqual(service.status.phase, .slewing)
        XCTAssertTrue(service.isMoving)
        await expect("the slew to end", timeout: 40.0) { service.status.phase == .idle }
        if case .arrived(let separation)? = service.status.outcome {
            XCTAssertLessThan(separation, 0.25)
        } else {
            XCTFail("the slew did not arrive: \(String(describing: service.status.outcome))")
        }
        XCTAssertEqual(Array(MountLifecycle.announcements.dropFirst(announced)), ["Slewing", "Arrived"])
        XCTAssertFalse(service.isMoving)
    }

    // MARK: - Polling

    func testPollingKeepsTheStatusUpToDate() async {
        let fake = await connectFake()
        let moved = EquatorialCoordinate(rightAscension: 150.0, declination: -10.0)
        fake.configure { script in
            script.position = moved
            script.tracking = false
        }
        await expect("the poll to bring the new reading") { service.status.position == moved }
        await expect("the new tracking state") { service.status.isTracking == false }
        XCTAssertEqual(service.trackingLine, "Tracking is off")
        XCTAssertEqual(service.status.phase, .idle)
    }

    func testPollingReportsAMountThatStartsToSlewByItself() async {
        let fake = await connectFake()
        fake.configure { $0.slewing = true }
        await expect("the poll to see the slew") { service.status.isMoving == true }
        // The controller itself did not start it, so its phase stays idle.
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertFalse(service.isMoving)
    }

    // MARK: - Losing the link

    func testALinkThatDiesEndsTheSessionAsLost() async {
        let fake = await connectFake()
        fake.configure { $0.readError = .timeout(operation: "position") }
        let reason = "The connection to the mount was lost. The mount may still be moving if it was slewing. "
            + "Stop it on its hand controller if it is."
        await expect("the loss of the connection", timeout: 30.0) { service.connection != .connected }
        XCTAssertEqual(service.connection, .lost(reason))
        XCTAssertFalse(service.isConnected)
        XCTAssertNil(service.capabilities)
        XCTAssertEqual(service.status, MountStatus.disconnected)
        XCTAssertEqual(service.summaryText, "Connection lost")
        XCTAssertTrue(service.showsAimButton)
        XCTAssertEqual(service.displayedOption, MountConnectionOption.lx200, "the picker is back")
        XCTAssertEqual(service.connectedOption?.id, "demo-test", "the lost mount is remembered for reconnecting")
        XCTAssertEqual(service.displayName, "Test mount")
        XCTAssertFalse(service.isWorking)
        XCTAssertFalse(service.isStopping)
        XCTAssertGreaterThanOrEqual(fake.disconnectCount, 1)
    }

    func testReconnectingAfterALossReturnsToTheSameSimulatedMount() async {
        let fake = await connectFake()
        fake.configure { $0.readError = .timeout(operation: "position") }
        await expect("the loss of the connection", timeout: 30.0) { service.connection != .connected }
        fake.configure { $0.readError = nil }
        service.reconnect(observer: observer)
        XCTAssertEqual(service.connection, .connecting)
        XCTAssertNil(service.errorText)
        await expect("the new connection") { service.connection == .connected }
        XCTAssertEqual(service.connectedOption?.id, "demo-test")
        XCTAssertEqual(fake.connectCount, 2)
        XCTAssertEqual(service.status.phase, .idle)
    }

    func testLosingTheLinkDuringASlewAnnouncesTheFailure() async {
        let fake = await connectFake()
        let announced = MountLifecycle.announcements.count
        await service.goTo(highTarget(), observer: observer)
        XCTAssertEqual(service.status.phase, .slewing)
        fake.configure { $0.readError = .timeout(operation: "position") }
        await expect("the loss of the connection", timeout: 30.0) { service.connection != .connected }
        XCTAssertEqual(service.connection, .lost("The connection to the mount was lost. The mount may still be moving if "
            + "it was slewing. Stop it on its hand controller if it is."))
        XCTAssertEqual(Array(MountLifecycle.announcements.dropFirst(announced)), ["Slewing", "Slew failed"])
        XCTAssertNil(service.slewStartSeparation)
        XCTAssertNil(service.slewTargetName)
        XCTAssertFalse(service.isMoving)
        // The controller tried to stop the mount on its way out.
        XCTAssertGreaterThanOrEqual(fake.abortCount, 1)
    }

    func testALostConnectionCanBeDismissedByDisconnecting() async {
        let fake = await connectFake()
        fake.configure { $0.readError = .timeout(operation: "position") }
        await expect("the loss of the connection", timeout: 30.0) { service.connection != .connected }
        service.disconnect()
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertNil(service.connectedOption)
        XCTAssertFalse(service.isDemo)
        XCTAssertEqual(service.summaryText, "Not connected")
    }

    // MARK: - Disconnecting

    func testDisconnectingWhileDisconnectedDoesNothing() {
        service.disconnect()
        XCTAssertEqual(service.connection, .disconnected)
    }

    func testDisconnectingAnIdleMountEndsTheSession() async {
        let fake = await connectFake()
        service.disconnect()
        await expect("the disconnection") { service.connection == .disconnected }
        XCTAssertNil(service.capabilities)
        XCTAssertEqual(service.status, MountStatus.disconnected)
        XCTAssertNil(service.connectedOption)
        XCTAssertNil(service.connectedAddress)
        XCTAssertFalse(service.isDemo)
        XCTAssertEqual(service.summaryText, "Not connected")
        await expect("the driver to be let go") { fake.disconnectCount == 1 }
        XCTAssertEqual(fake.abortCount, 0, "an idle mount needs no stop")
    }

    func testDisconnectingAMovingMountStopsItFirst() async {
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        XCTAssertTrue(service.isMoving)
        service.disconnect()
        await expect("the disconnection") { service.connection == .disconnected }
        XCTAssertEqual(fake.abortCount, 1)
        await expect("the driver to be let go") { fake.disconnectCount == 1 }
        XCTAssertNil(service.slewTargetName)
        XCTAssertNil(service.slewStartSeparation)
        XCTAssertFalse(service.isWorking)
    }

    func testAMountThatCannotBeStoppedStaysConnectedSoStopCanBeTriedAgain() async {
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        fake.configure { $0.abortError = .rejected(detail: "jammed") }
        service.disconnect()
        await expect("the failure message") { service.errorText != nil }
        XCTAssertEqual(service.errorText, "The mount may still be moving. The mount rejected the command: jammed. "
            + "Stop it on its hand controller or switch it off.")
        XCTAssertEqual(service.connection, .connected)
        XCTAssertTrue(service.isMoving)
        fake.configure { $0.abortError = nil }
        service.disconnect()
        await expect("the disconnection") { service.connection == .disconnected }
    }

    func testDisconnectingWhileACommandIsBeingSetUpStillStopsTheMount() async {
        let fake = await connectFake()
        fake.readGate.close()
        await expect("a poll to be stuck") { fake.readGate.isWaiting }
        let goTo = Task { await self.service.goTo(self.highTarget(), observer: self.observer) }
        await expect("the GoTo to be under way") { service.isWorking }
        service.disconnect()
        // Give the disconnect time to call off the queued GoTo and to queue the stop, while the worker is still stuck.
        await settle()
        fake.readGate.open()
        await goTo.value
        await expect("the disconnection") { service.connection == .disconnected }
        XCTAssertEqual(fake.abortCount, 1, "the GoTo may have started, so the mount is stopped anyway")
        XCTAssertTrue(fake.slews.isEmpty, "a GoTo that was still queued does not start after the disconnect")
        XCTAssertNil(service.errorText, "the person knows, so a cancelled GoTo reports nothing")
        XCTAssertFalse(service.isWorking)
    }

    func testDisconnectingWhileConnectingCancelsTheConnection() async {
        let fake = Fake()
        fake.connectGate.close()
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake), observer: observer)
        await expect("the handshake to start") { fake.connectGate.isWaiting }
        service.disconnect()
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertNil(service.connectedOption)
    }

    // MARK: - The background

    func testGoingToTheBackgroundEndsTheSessionOfAnIdleMount() async throws {
        let helper = try lifecycle()
        let fake = await connectFake()
        let begun = helper.backgroundTasksBegun
        let ended = helper.backgroundTasksEnded
        helper.simulateBackground()
        XCTAssertEqual(helper.backgroundTasksBegun, begun + 1, "iOS is asked for time to stop the mount")
        await expect("the session to end") { service.connection != .connected }
        XCTAssertEqual(service.connection, .lost("Disconnected when Lodestar went to the background. The mount was stopped."))
        await expect("the background task to be ended") { helper.backgroundTasksEnded == ended + 1 }
        XCTAssertEqual(fake.abortCount, 0)
        XCTAssertNil(service.capabilities)
        XCTAssertEqual(service.status, MountStatus.disconnected)
        XCTAssertEqual(service.summaryText, "Connection lost")
        XCTAssertFalse(service.isConnected)
        await expect("the driver to be let go") { fake.disconnectCount == 1 }
    }

    func testGoingToTheBackgroundStopsASlewingMount() async throws {
        let helper = try lifecycle()
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        XCTAssertEqual(service.status.phase, .slewing)
        let ended = helper.backgroundTasksEnded
        helper.simulateBackground()
        await expect("the session to end") { service.connection != .connected }
        XCTAssertEqual(service.connection, .lost("Disconnected when Lodestar went to the background. The mount was stopped."))
        XCTAssertEqual(fake.abortCount, 1)
        await expect("the background task to be ended") { helper.backgroundTasksEnded == ended + 1 }
        XCTAssertNil(service.slewTargetName)
    }

    func testGoingToTheBackgroundWithAMountThatCannotBeStoppedSaysSo() async throws {
        let helper = try lifecycle()
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        fake.configure { $0.abortError = .rejected(detail: "stuck") }
        helper.simulateBackground()
        await expect("the session to end") { service.connection != .connected }
        XCTAssertEqual(service.connection, .lost("Disconnected when Lodestar went to the background. The mount may still be "
            + "moving. The mount rejected the command: stuck. Stop it on its hand controller or switch it off."))
    }

    func testGoingToTheBackgroundWhileConnectingCancelsTheConnection() async throws {
        let helper = try lifecycle()
        let fake = Fake()
        fake.connectGate.close()
        fakes.append(fake)
        service.connectDemo(Self.option(for: fake), observer: observer)
        await expect("the handshake to start") { fake.connectGate.isWaiting }
        let begun = helper.backgroundTasksBegun
        helper.simulateBackground()
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertEqual(helper.backgroundTasksBegun, begun, "nothing has to be stopped, so no background time is asked for")
    }

    func testGoingToTheBackgroundWithoutAConnectionDoesNothing() throws {
        let helper = try lifecycle()
        let begun = helper.backgroundTasksBegun
        helper.simulateBackground()
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertEqual(helper.backgroundTasksBegun, begun)
    }

    func testGoingToTheBackgroundWithALostConnectionDoesNothing() async throws {
        let helper = try lifecycle()
        let fake = await connectFake()
        fake.configure { $0.readError = .timeout(operation: "position") }
        await expect("the loss of the connection", timeout: 30.0) { service.connection != .connected }
        let lost = service.connection
        let begun = helper.backgroundTasksBegun
        helper.simulateBackground()
        XCTAssertEqual(service.connection, lost)
        XCTAssertEqual(helper.backgroundTasksBegun, begun)
    }
}
