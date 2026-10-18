import XCTest
@testable import LodestarKit

/// A controller wired to a Sky-Watcher simulator, with everything a test wants to look at.
final class SkyWatcherRig {
    let clock: ManualMountClock
    let simulator: SkyWatcherSimulator
    let driver: SkyWatcherDriver
    let controller: MountController

    init(clock: ManualMountClock, simulator: SkyWatcherSimulator, driver: SkyWatcherDriver, controller: MountController) {
        self.clock = clock
        self.simulator = simulator
        self.driver = driver
        self.controller = controller
    }

    func frame() -> SkyFrame { SkyFrame(date: clock.now(), observer: Observer(location: simulator.location)) }

    /// Where the simulated telescope really points now, as J2000.
    func trueJ2000() -> EquatorialCoordinate { MountEpoch.apparentOfDate.toJ2000(simulator.truePlace(), frame: frame()) }

    /// The angle in degrees between the simulated telescope's real pointing and the J2000 place `target`.
    func errorTo(_ target: EquatorialCoordinate) -> Double { trueJ2000().angularSeparation(to: target) }

    /// Centres `star` by hand (the simulated telescope is placed exactly on it through the axes) and syncs.
    @discardableResult
    func syncOn(_ star: EquatorialCoordinate) throws -> MountSyncResult {
        placeOn(star)
        return try controller.sync(star)
    }

    /// Moves the simulated axes so that the real telescope points exactly at `star` now (what a user does with the nudge buttons).
    func placeOn(_ star: EquatorialCoordinate) {
        let frame = frame()
        let place = MountEpoch.apparentOfDate.fromJ2000(star, frame: frame)
        let direction = SkyWatcherSky.localDirection(place, localSiderealTime: frame.localApparentSiderealTime,
                                                     latitude: simulator.location.latitude, mode: simulator.mode)
        let truth = SkyWatcherPointingModel(mode: simulator.mode, isSouthernHemisphere: simulator.location.latitude < 0,
                                            errors: simulator.effectiveErrors)
        let options = truth.solutions(direction, preferredAxis1Degrees: simulator.axis1Degrees)
        var best = options[0]
        var bestCost = Double.greatestFiniteMagnitude
        for option in options {
            let cost = abs(option.axis1 - simulator.axis1Degrees) + abs(option.axis2 - simulator.axis2Degrees)
            let allowed = simulator.mode == .equatorial ? abs(truth.modelAxis1(option.axis1)) <= 95 : option.pierSide == .east
            if allowed && cost < bestCost {
                best = option
                bestCost = cost
            }
        }
        simulator.placeAxes(axis1Degrees: best.axis1, axis2Degrees: best.axis2)
    }
}

/// The error thrown by `body`; nil (after a test failure) if it did not throw a `MountError`.
func skyWatcherThrown<T>(_ body: () throws -> T, file: StaticString = #filePath, line: UInt = #line) -> MountError? {
    do {
        _ = try body()
        XCTFail("expected a MountError", file: file, line: line)
        return nil
    } catch let error as MountError {
        return error
    } catch {
        XCTFail("unexpected error \(error)", file: file, line: line)
        return nil
    }
}

enum SkyWatcherTestSupport {
    static let boulder = MountTestSupport.boulder
    static let start = MountTestSupport.start

    // J2000 places of stars; their position at `start` (2026-10-18 04:00 UTC, local sidereal time 22.76 h) in Boulder.
    static let vega = EquatorialCoordinate(rightAscensionHours: 18.6156, declination: 38.7837)       // hour angle +4.1 h, altitude 43, west
    static let mirfak = EquatorialCoordinate(rightAscensionHours: 3.4054, declination: 49.8612)      // -4.7 h, altitude 41, north-east
    static let enif = EquatorialCoordinate(rightAscensionHours: 21.7364, declination: 9.875)         // +1.0 h, altitude 57, south-west
    static let deneb = MountTestSupport.deneb                                                         // +2.1 h, altitude 67
    static let altair = MountTestSupport.altair                                                       // +2.9 h, altitude 40
    static let andromeda = MountTestSupport.andromeda                                                 // -1.9 h, altitude 68
    static let alpheratz = EquatorialCoordinate(rightAscensionHours: 0.1398, declination: 29.0905)   // -1.4 h, altitude 70
    static let markab = EquatorialCoordinate(rightAscensionHours: 23.0794, declination: 15.2053)     // -0.3 h, altitude 65, on the meridian
    static let hamal = EquatorialCoordinate(rightAscensionHours: 2.1196, declination: 23.4624)       // -3.4 h, altitude 45, east
    static let albireo = EquatorialCoordinate(rightAscensionHours: 19.512, declination: 27.96)       // +3.3 h, altitude 48
    static let capella = EquatorialCoordinate(rightAscensionHours: 5.2782, declination: 45.998)      // -6.5 h, altitude 23, low in the north-east
    static let rasalhague = EquatorialCoordinate(rightAscensionHours: 17.582, declination: 12.56)    // +5.2 h, altitude 17, low in the west
    static let arcturus = EquatorialCoordinate(rightAscensionHours: 14.261, declination: 19.182)     // below the horizon

    static let boulderLocation: GeographicLocation = boulder.location

    /// Sydney: a southern observer. At `start` (local sidereal time 15.86 h) the stars below are up.
    static let sydney = Observer(location: GeographicLocation(latitude: -33.8688, longitude: 151.2093, elevation: 20.0))
    static let acrux = EquatorialCoordinate(rightAscensionHours: 12.4433, declination: -63.0991)     // +3.4 h, altitude 47
    static let nunki = EquatorialCoordinate(rightAscensionHours: 18.9211, declination: -26.2967)     // -3.1 h, altitude 50
    static let peacock = EquatorialCoordinate(rightAscensionHours: 20.4275, declination: -56.7351)   // -4.6 h, altitude 39
    static let spica = EquatorialCoordinate(rightAscensionHours: 13.4199, declination: -11.1613)     // +2.4 h, altitude 50
    static let kaus = EquatorialCoordinate(rightAscensionHours: 18.4029, declination: -34.3846)      // -2.5 h, altitude 59
    static let shaula = EquatorialCoordinate(rightAscensionHours: 17.5601, declination: -37.1038)    // -1.7 h, altitude 69
    static let betaCentauri = EquatorialCoordinate(rightAscensionHours: 14.0637, declination: -60.373) // +1.8 h, altitude 58
    static let arcturusSouth = EquatorialCoordinate(rightAscensionHours: 14.261, declination: 19.182) // +1.6 h, altitude 32
    static let alnair = EquatorialCoordinate(rightAscensionHours: 22.1372, declination: -46.961)     // -6.3 h, altitude 21

    /// Errors of an imperfectly set up equatorial mount.
    static let equatorialErrors = SkyWatcherPointingErrors(axis1Index: 1.3, axis2Index: -0.8, baseTiltX: 0.4, baseTiltY: -0.3,
                                                           orthogonality: 0.15, cone: -0.1)

    /// Errors of an imperfectly set up alt-azimuth mount.
    static let altAzimuthErrors = SkyWatcherPointingErrors(axis1Index: 2.0, axis2Index: 1.1, baseTiltX: 0.5, baseTiltY: -0.4,
                                                           orthogonality: 0.1, cone: 0.12)

    static func rig(mode: SkyWatcherMountMode = .altAzimuth, errors: SkyWatcherPointingErrors = SkyWatcherPointingErrors(),
                    settings: MountSettings = .standard, configuration: SkyWatcherConfiguration? = nil, observer: Observer = boulder,
                    location: GeographicLocation? = nil, version: SkyWatcherVersion? = nil, latencySeconds: Double = 0.05,
                    axis1Inverted: Bool = false, axis2Inverted: Bool = false, chunkSize: Int = 0,
                    configure: (SkyWatcherSimulator) -> Void = { _ in }) -> SkyWatcherRig {
        let siteLocation = location ?? observer.location
        let clock = ManualMountClock(start: start)
        let simulator = SkyWatcherSimulator(
            clock: clock, location: siteLocation, mode: mode, errors: errors,
            version: version ?? (mode == .altAzimuth ? SkyWatcherVersion(major: 3, minor: 0x22, mountCode: 0xA5)
                : SkyWatcherVersion(major: 3, minor: 0x40, mountCode: 0x0C)),
            axis1Inverted: axis1Inverted, axis2Inverted: axis2Inverted, latencySeconds: latencySeconds, chunkSize: chunkSize)
        configure(simulator)
        let driverConfiguration = configuration ?? SkyWatcherConfiguration(location: siteLocation, mode: mode, invertsAxis1: axis1Inverted,
                                                                           invertsAxis2: axis2Inverted)
        let driver = SkyWatcherDriver(transport: simulator, clock: clock, configuration: driverConfiguration)
        let controller = MountController(driver: driver, observer: observer, settings: settings, clock: clock)
        return SkyWatcherRig(clock: clock, simulator: simulator, driver: driver, controller: controller)
    }

    /// Polls once a second for `seconds` (what the apps' background worker does).
    static func poll(_ rig: SkyWatcherRig, seconds: Int) {
        for _ in 0 ..< seconds {
            rig.controller.poll()
            rig.clock.advance(seconds: 1.0)
        }
    }
}
