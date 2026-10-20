import XCTest
@testable import LodestarKit

/// A controller wired to a simulator, with everything a test wants to look at.
final class MountRig {
    let name: String
    let clock: ManualMountClock
    let mount: MountSimulatorModel
    let controller: MountController
    let driver: MountDriver
    let streamSimulator: MountSimulatedStreamTransport?
    let alpacaSimulator: AlpacaSimulator?

    init(name: String, clock: ManualMountClock, mount: MountSimulatorModel, controller: MountController, driver: MountDriver,
         streamSimulator: MountSimulatedStreamTransport?, alpacaSimulator: AlpacaSimulator?) {
        self.name = name
        self.clock = clock
        self.mount = mount
        self.controller = controller
        self.driver = driver
        self.streamSimulator = streamSimulator
        self.alpacaSimulator = alpacaSimulator
    }

    /// The frame of the coordinates the simulated mount works in.
    var epoch: MountEpoch { driver.epoch }

    func frame() -> SkyFrame { SkyFrame(date: clock.now(), observer: MountTestSupport.boulder) }

    /// The place the simulated mount points at, as J2000.
    func mountJ2000() -> EquatorialCoordinate { epoch.toJ2000(mount.position, frame: frame()) }
}

enum MountTestSupport {
    static let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))

    /// 2026-10-18 04:00 UTC, about 22:04 the evening before in Colorado: right ascension 22.7 h is near the meridian.
    static let start = Date(timeIntervalSince1970: 1_792_296_000)

    /// 2026-10-18 19:00 UTC, 13:00 in Colorado (local apparent noon is at 18:47 UTC): the Sun stands about 40 degrees up in
    /// the south, at right ascension 13.5 h and declination -9.6 degrees.
    static let midday = Date(timeIntervalSince1970: 1_792_350_000)

    /// The Andromeda galaxy's centre (J2000): high in the east at `start`.
    static let andromeda = EquatorialCoordinate(rightAscensionHours: 0.7123, declination: 41.2689)

    /// Deneb (J2000): high in the west at `start`.
    static let deneb = EquatorialCoordinate(rightAscensionHours: 20.6905, declination: 45.2803)

    /// Altair (J2000): about 40 degrees up in the west at `start` and setting.
    static let altair = EquatorialCoordinate(rightAscensionHours: 19.8464, declination: 8.8683)

    /// The Orion nebula (J2000): below the horizon at `start`.
    static let orionNebula = EquatorialCoordinate(rightAscensionHours: 5.5881, declination: -5.3911)

    /// Where the mounts start: a place in the mount's own frame, not far from Deneb.
    static let parkPosition = EquatorialCoordinate(rightAscensionHours: 20.0, declination: 30.0)

    static let rigNames = ["lx200-onstep", "lx200-meade-low", "nexstar-celestron", "nexstar-synscan", "alpaca-topocentric", "alpaca-j2000"]

    static func rig(_ name: String, settings: MountSettings = .standard, chunkSize: Int = 0, slewRate: Double = 4.0,
                    begin: Date = MountTestSupport.start, configure: (MountRig) -> Void = { _ in }) -> MountRig {
        let clock = ManualMountClock(start: begin)
        let mount = MountSimulatorModel(clock: clock, start: parkPosition, slewRateDegreesPerSecond: slewRate)
        let driver: MountDriver
        var stream: MountSimulatedStreamTransport?
        var alpaca: AlpacaSimulator?
        switch name {
        case "lx200-onstep":
            let simulator = LX200Simulator(clock: clock, mount: mount, dialect: .onstep, chunkSize: chunkSize)
            stream = simulator
            driver = LX200Driver(transport: simulator, clock: clock)
        case "lx200-meade-low":
            let simulator = LX200Simulator(clock: clock, mount: mount, dialect: .meade, highPrecision: false, chunkSize: chunkSize)
            stream = simulator
            driver = LX200Driver(transport: simulator, clock: clock)
        case "nexstar-celestron":
            let simulator = NexStarSimulator(clock: clock, mount: mount, flavor: .celestron, major: 5, minor: 28, patch: 0,
                                             model: 12, chunkSize: chunkSize)
            stream = simulator
            driver = NexStarDriver(transport: simulator, clock: clock)
        case "nexstar-synscan":
            let simulator = NexStarSimulator(clock: clock, mount: mount, flavor: .synscan, major: 4, minor: 38, patch: 6,
                                             model: 128, chunkSize: chunkSize)
            stream = simulator
            driver = NexStarDriver(transport: simulator, clock: clock)
        case "alpaca-topocentric":
            let simulator = AlpacaSimulator(clock: clock, mount: mount, equatorialSystem: 1)
            alpaca = simulator
            driver = AlpacaDriver(transport: simulator)
        case "alpaca-j2000":
            let simulator = AlpacaSimulator(clock: clock, mount: mount, equatorialSystem: 2)
            alpaca = simulator
            driver = AlpacaDriver(transport: simulator)
        default:
            preconditionFailure("unknown rig \(name)")
        }
        let controller = MountController(driver: driver, observer: boulder, settings: settings, clock: clock)
        let rig = MountRig(name: name, clock: clock, mount: mount, controller: controller, driver: driver,
                           streamSimulator: stream, alpacaSimulator: alpaca)
        configure(rig)
        return rig
    }

    /// The altitude of `target` at the clock's time, geometric.
    static func altitude(of target: EquatorialCoordinate, clock: ManualMountClock) -> Double {
        SkyFrame(date: clock.now(), observer: boulder).horizontal(j2000: target, properMotion: nil, refraction: false).altitude
    }
}

extension MountError {
    var isTimeout: Bool { if case .timeout = self { return true }; return false }
    var isTransport: Bool { if case .transport = self { return true }; return false }
    var isMalformedReply: Bool { if case .malformedReply = self { return true }; return false }
    var isRejected: Bool { if case .rejected = self { return true }; return false }
    var isRemote: Bool { if case .remote = self { return true }; return false }
    var isInvalidInput: Bool { if case .invalidInput = self { return true }; return false }
    var isHardwareFault: Bool { if case .hardwareFault = self { return true }; return false }
    var isSlewStopped: Bool { if case .slewStopped = self { return true }; return false }
    var isNotSupported: Bool { if case .notSupported = self { return true }; return false }
}

/// Runs `body`, which must throw a `MountError`, and returns it (nil, after a test failure, if it did not).
func mountError(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) -> MountError? {
    do {
        try body()
        XCTFail("expected a MountError", file: file, line: line)
        return nil
    } catch let error as MountError {
        return error
    } catch {
        XCTFail("unexpected error \(error)", file: file, line: line)
        return nil
    }
}

/// Fails the test unless `body` throws `MountError.malformedReply`.
func assertMalformed<T>(_ body: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try body()
        XCTFail("expected a malformed reply error: \(message)", file: file, line: line)
    } catch let error as MountError {
        XCTAssertTrue(error.isMalformedReply, "\(message): \(error)", file: file, line: line)
    } catch {
        XCTFail("unexpected error \(error): \(message)", file: file, line: line)
    }
}

/// Fails the test unless `body` throws `MountError.invalidInput`.
func assertInvalidInput<T>(_ body: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try body()
        XCTFail("expected an invalid input error: \(message)", file: file, line: line)
    } catch let error as MountError {
        XCTAssertTrue(error.isInvalidInput, "\(message): \(error)", file: file, line: line)
    } catch {
        XCTFail("unexpected error \(error): \(message)", file: file, line: line)
    }
}
