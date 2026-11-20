import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// What the notice says about a mount that Lodestar let go of in the background (`MountService.backgroundOutcomeText`): the
/// stop of a move halts both axes of a Sky-Watcher mount, so a mount that may have been moving is "stopped", and one that stood
/// still and tracked, in the equatorial set-up, keeps its sidereal tracking.
extension MountServiceTests {
    private func skyWatcherOption(mode: SkyWatcherMountMode) -> MountConnectionOption {
        Self.option(id: "demo-skywatcher-\(mode)", lodestarAligned: true) { _, options in
            let location = options.location ?? GeographicLocation(latitude: 40.0, longitude: -105.0, elevation: 0.0)
            let clock = ManualMountClock(start: Date())
            let simulator = SkyWatcherSimulator(clock: clock, location: location, mode: mode, errors: SkyWatcherPointingErrors(),
                                                version: SkyWatcherVersion(major: 3, minor: 0x40, mountCode: 0x0C))
            simulator.placeAxes(axis1Degrees: 0.0, axis2Degrees: 0.0)
            let driver = SkyWatcherDriver(transport: simulator, clock: clock,
                                          configuration: SkyWatcherConfiguration(location: location, mode: mode))
            return MountDriverBundle(driver: driver, clock: clock, detail: { MountDriverDetail(skyWatcher: driver) })
        }
    }

    private func connectSkyWatcher(mode: SkyWatcherMountMode) async {
        service.connectDemo(skyWatcherOption(mode: mode), context: Self.context(observer))
        await mountServiceExpect("the Sky-Watcher mount") { self.service.connection == .connected }
        XCTAssertEqual(service.driverDetail?.arrangement, mode)
    }

    private static let background = "Disconnected when Lodestar went to the background. "

    func testAnEquatorialMountThatStoodStillAndTracksKeepsTrackingInTheBackground() async throws {
        let helper = try lifecycle()
        await connectSkyWatcher(mode: .equatorial)
        service.setTracking(true)
        await mountServiceExpect("tracking to be on") { self.service.status.isTracking == true }
        helper.simulateBackground()
        await mountServiceExpect("the session to end") { self.service.connection != .connected }
        XCTAssertEqual(service.connection, .lost(Self.background
            + "Tracking continues; Lodestar no longer watches the mount's limits."))
    }

    /// Lodestar's own corrections track it, and they end with the connection.
    func testAnAltAzimuthMountIsStoppedInTheBackground() async throws {
        let helper = try lifecycle()
        await connectSkyWatcher(mode: .altAzimuth)
        service.setTracking(true)
        await mountServiceExpect("tracking to be on") { self.service.status.isTracking == true }
        helper.simulateBackground()
        await mountServiceExpect("the session to end") { self.service.connection != .connected }
        XCTAssertEqual(service.connection, .lost(Self.background + "The mount was stopped."))
    }

    func testAnEquatorialMountThatMayHaveBeenMovingIsStoppedInTheBackground() async throws {
        let helper = try lifecycle()
        await connectSkyWatcher(mode: .equatorial)
        service.setTracking(true)
        await mountServiceExpect("tracking to be on") { self.service.status.isTracking == true }
        // The first pulse of a nudge that is held may already have gone out when the app goes away, and the stop halts both axes.
        service.beginNudge(.north)
        helper.simulateBackground()
        await mountServiceExpect("the session to end") { self.service.connection != .connected }
        XCTAssertEqual(service.connection, .lost(Self.background + "The mount was stopped."))
    }
}
