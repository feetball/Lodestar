import XCTest
@testable import LodestarKit

/// End-to-end tests of the Sky-Watcher Wi-Fi driver with the `MountController` against the `SkyWatcherSimulator`: connection,
/// alignment on one to three stars with synthetic mis-pointing, GoTo accuracy, pier side and meridian handling, tracking, nudges,
/// abort, and recovery from lost and damaged datagrams.
final class SkyWatcherMountTests: XCTestCase {
    private typealias Support = SkyWatcherTestSupport

    private let altAz = SkyWatcherMountMode.altAzimuth
    private let equatorial = SkyWatcherMountMode.equatorial

    private var altAzimuthAlignmentStars: [EquatorialCoordinate] { [Support.vega, Support.mirfak, Support.enif] }
    private var equatorialAlignmentStars: [EquatorialCoordinate] { [Support.vega, Support.mirfak, Support.enif] }
    private var gotoTargets: [EquatorialCoordinate] {
        [Support.deneb, Support.altair, Support.andromeda, Support.markab, Support.alpheratz, Support.albireo, Support.hamal,
         Support.capella, Support.rasalhague]
    }

    private func connected(_ mode: SkyWatcherMountMode, _ errors: SkyWatcherPointingErrors = SkyWatcherPointingErrors(),
                           configure: (SkyWatcherSimulator) -> Void = { _ in }) throws -> SkyWatcherRig {
        let rig = Support.rig(mode: mode, errors: errors, configure: configure)
        try rig.controller.connect()
        return rig
    }

    @discardableResult
    private func aligned(_ rig: SkyWatcherRig, _ stars: [EquatorialCoordinate]) throws -> SkyWatcherRig {
        for star in stars { try rig.syncOn(star) }
        return rig
    }

    private func arrived(_ outcome: MountSlewOutcome?) -> Bool {
        if case .arrived? = outcome { return true }
        return false
    }

    private func aborted(_ outcome: MountSlewOutcome?) -> Bool {
        if case .aborted? = outcome { return true }
        return false
    }

    /// Goes to `target`, waits for the end of the slew and returns how far the real telescope is from it.
    @discardableResult
    private func goto(_ rig: SkyWatcherRig, _ target: EquatorialCoordinate, file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        try rig.controller.goto(target)
        let status = rig.controller.awaitSettled()
        XCTAssertTrue(arrived(status.outcome), "\(String(describing: status.outcome))", file: file, line: line)
        return rig.errorTo(target)
    }

    private func east(_ place: EquatorialCoordinate) -> Vector3 {
        let ra = AstroMath.radians(place.rightAscension)
        return Vector3(-sin(ra), cos(ra), 0.0)
    }

    private func north(_ place: EquatorialCoordinate) -> Vector3 {
        let ra = AstroMath.radians(place.rightAscension)
        let dec = AstroMath.radians(place.declination)
        return Vector3(-sin(dec) * cos(ra), -sin(dec) * sin(ra), cos(dec))
    }

    // MARK: Connecting

    func testConnectInitializesTheMountAndReportsWhatItIs() throws {
        let rig = Support.rig(mode: altAz)
        XCTAssertFalse(rig.simulator.isInitialized)
        let capabilities = try rig.controller.connect()
        XCTAssertTrue(rig.simulator.isInitialized)
        XCTAssertEqual(capabilities.kind, .skywatcher)
        XCTAssertEqual(capabilities.name, "Sky-Watcher AZ-GTi 3.22")
        XCTAssertEqual(capabilities.firmware, "3.22")
        XCTAssertTrue(capabilities.canSlew && capabilities.canSync && capabilities.canAbort)
        XCTAssertTrue(capabilities.canSetTracking && capabilities.canNudge && capabilities.canSetSiteAndTime)
        XCTAssertTrue(capabilities.gotoNeedsAlignment)
        XCTAssertEqual(capabilities.isAligned, false)
        XCTAssertEqual(rig.controller.status.phase, .idle)
        XCTAssertEqual(rig.driver.epoch, .apparentOfDate)
        XCTAssertEqual(rig.driver.kind, .skywatcher)
        XCTAssertEqual(rig.driver.version, SkyWatcherVersion(major: 3, minor: 0x22, mountCode: 0xA5))
        XCTAssertEqual(rig.driver.mountMode, altAz)
        XCTAssertEqual(rig.driver.trackingStrategy, .servo)
        XCTAssertEqual(rig.driver.startupAxisAngles, SkyWatcherAxisAngles(axis1Degrees: 0.0, axis2Degrees: 0.0))
        XCTAssertEqual(SkyWatcherDriver.menuTitle, "Sky-Watcher Wi-Fi (AZ-GTi, Star Adventurer GTi)")
        // Home: level, pointing north.
        let position = try XCTUnwrap(rig.controller.status.position)
        let horizontal = rig.frame().horizontal(j2000: position, properMotion: nil, refraction: false)
        XCTAssertEqual(horizontal.altitude, 0.0, accuracy: 0.01)
        XCTAssertTrue(horizontal.azimuth < 0.01 || horizontal.azimuth > 359.99, "\(horizontal.azimuth)")
        XCTAssertEqual(try rig.controller.connect(), capabilities)
        // The datagrams of the handshake: version, 2 x counts, timer, 2 x ratio, status (twice: init), init, position.
        XCTAssertTrue((10 ... 20).contains(rig.driver.datagramsSent), "\(rig.driver.datagramsSent)")
        XCTAssertEqual(rig.driver.retries, 0)
    }

    func testTheMountModelPicksTheArrangement() throws {
        let location = Support.boulderLocation
        func mode(_ code: Int, _ configuredMode: SkyWatcherMountMode? = nil) throws -> SkyWatcherMountMode? {
            let rig = Support.rig(mode: altAz, configuration: SkyWatcherConfiguration(location: location, mode: configuredMode),
                                  version: SkyWatcherVersion(major: 3, minor: 0x10, mountCode: code))
            try rig.controller.connect()
            return rig.driver.mountMode
        }
        XCTAssertEqual(try mode(0xA5), altAz)
        XCTAssertEqual(try mode(0xA2), altAz)
        XCTAssertEqual(try mode(0x0C), equatorial)
        XCTAssertEqual(try mode(0x23), equatorial)
        XCTAssertEqual(try mode(0x00), equatorial)
        XCTAssertEqual(try mode(0x77), equatorial)
        XCTAssertEqual(try mode(0xA5, .equatorial), equatorial)
        XCTAssertEqual(try mode(0x0C, .altAzimuth), altAz)
        let eq = Support.rig(mode: equatorial)
        try eq.controller.connect()
        XCTAssertEqual(eq.driver.trackingStrategy, .sidereal)
        XCTAssertEqual(eq.controller.capabilities?.name, "Sky-Watcher Star Adventurer GTi 3.40")
        // An alt-azimuth mount cannot track at the sidereal rate on one axis, whatever is asked for.
        let forced = Support.rig(mode: altAz, configuration: SkyWatcherConfiguration(location: location, mode: altAz, trackingStrategy: .sidereal))
        try forced.controller.connect()
        XCTAssertEqual(forced.driver.trackingStrategy, .servo)
    }

    func testConnectStopsAMountThatIsMovingAndReportsItsStartPosition() throws {
        let rig = Support.rig(mode: altAz)
        // Somebody left the mount turned and running.
        rig.simulator.placeAxes(axis1Degrees: 40.0, axis2Degrees: 10.0)
        for command in [":F3\r", ":G110\r", ":G210\r", ":I11C3600\r", ":I21C3600\r", ":J3\r"] {
            try rig.simulator.send(MountText.latin1Bytes(command))
            try rig.simulator.discardPendingInput()
        }
        XCTAssertTrue(rig.simulator.isMoving)
        try rig.controller.connect()
        XCTAssertFalse(rig.simulator.isMoving)
        let start = try XCTUnwrap(rig.driver.startupAxisAngles)
        XCTAssertEqual(start.axis1Degrees, 40.0, accuracy: 0.01)
        XCTAssertEqual(start.axis2Degrees, 10.0, accuracy: 0.01)
    }

    func testDeclaringHomeRedefinesTheEncoderZero() throws {
        // The mount was switched on 40° and 10° away from its home position; the user brought it home with the nudge pad (here: the
        // simulated mount really is at home, and its encoders say 40° and 10°).
        let rig = Support.rig(mode: altAz, errors: SkyWatcherPointingErrors(axis1Index: -40.0, axis2Index: -10.0))
        rig.simulator.placeAxes(axis1Degrees: 40.0, axis2Degrees: 10.0)
        try rig.controller.connect()
        let start = try XCTUnwrap(rig.driver.startupAxisAngles)
        XCTAssertEqual(start.axis1Degrees, 40.0, accuracy: 0.01)
        try rig.syncOn(Support.vega)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 1)
        // (The mount went to Vega for that sync and is now brought back home: its encoders read 40° and 10° again.)
        rig.simulator.placeAxes(axis1Degrees: 40.0, axis2Degrees: 10.0)
        try rig.driver.declareHomePosition()
        // The encoders read zero, the alignment is gone, the telescope did not move and points where the ideal geometry says.
        XCTAssertEqual(rig.driver.startupAxisAngles, SkyWatcherAxisAngles(axis1Degrees: 0.0, axis2Degrees: 0.0))
        XCTAssertEqual(rig.driver.alignmentPoints.count, 0)
        XCTAssertEqual(rig.simulator.axis1Degrees, 0.0, accuracy: 1e-3)
        XCTAssertEqual(try rig.driver.readTracking(), false)
        XCTAssertFalse(rig.simulator.isMoving)
        let place = try rig.driver.readPosition()
        XCTAssertTrue(rig.simulator.truePlace().angularSeparation(to: place) < 1e-3)
        // With the home position known, one star finds next to no home error.
        try rig.syncOn(Support.vega)
        let fit = try XCTUnwrap(rig.driver.alignmentFit)
        XCTAssertTrue(abs(fit.model.errors.axis1Index) < 0.01 && abs(fit.model.errors.axis2Index) < 0.01, "\(fit.model.errors)")
        XCTAssertTrue(try goto(rig, Support.deneb) < 0.05)
        XCTAssertEqual(skyWatcherThrown { try Support.rig(mode: altAz).driver.declareHomePosition() }, .notConnected)
    }

    func testConnectFailuresAreReported() {
        let silent = Support.rig(mode: altAz)
        silent.simulator.inject("e", .silence, times: 10)
        let before = silent.clock.secondsSince1970
        let error = skyWatcherThrown { try silent.controller.connect() }
        XCTAssertTrue(error?.isTimeout == true)
        XCTAssertTrue(error?.isCommunicationFailure == true)
        // Three attempts of 0.6 s each.
        XCTAssertEqual(silent.clock.secondsSince1970 - before, 1.8, accuracy: 0.2)
        XCTAssertEqual(silent.controller.status.phase, .disconnected)
        let garbled = Support.rig(mode: altAz)
        garbled.simulator.inject("a", .replace(text: "=000000\r"), times: 10)
        XCTAssertTrue(skyWatcherThrown { try garbled.controller.connect() }?.isMalformedReply == true)
        let refused = Support.rig(mode: altAz)
        refused.simulator.inject("e", .replace(text: "!5\r"), times: 10)
        XCTAssertEqual(skyWatcherThrown { try refused.controller.connect() }, .standby)
        XCTAssertEqual(skyWatcherThrown { try silent.driver.readPosition() }, .notConnected)
        XCTAssertEqual(skyWatcherThrown { try silent.driver.slew(to: Support.deneb) }, .notConnected)
    }

    // MARK: Alignment and GoTo accuracy

    func testGotoNeedsAnAlignment() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.goto(Support.deneb) }, .notAligned)
        XCTAssertEqual(rig.simulator.gotosStarted, 0)
        XCTAssertFalse(rig.controller.poll().isAligned == true)
        try rig.syncOn(Support.vega)
        XCTAssertEqual(rig.controller.poll().isAligned, true)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 1)
        // With the permission, the mount goes by the ideal geometry: accurate only as far as the mount was set up.
        let perfect = Support.rig(mode: altAz, configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: altAz,
                                                                                      allowsGotoWithoutAlignment: true))
        let capabilities = try perfect.controller.connect()
        XCTAssertFalse(capabilities.gotoNeedsAlignment)
        XCTAssertTrue(try goto(perfect, Support.deneb) < 0.05)
    }

    func testOneStarFindsTheHomeError() throws {
        for mode in [altAz, equatorial] {
            let errors = SkyWatcherPointingErrors(axis1Index: 3.1, axis2Index: -2.2)
            let rig = try connected(mode, errors)
            // The home position was off: the mount believes it points at the pole / north, it really is a few degrees away.
            let result = try rig.syncOn(Support.vega)
            XCTAssertTrue(result.offsetDegrees > 2.0, "\(mode) \(result.offsetDegrees)")
            let fit = try XCTUnwrap(rig.driver.alignmentFit)
            XCTAssertTrue(fit.maximumResidualDegrees < 1e-6)
            // The star moved a little between the placing and the sync (the mount does not track yet): 0.15 s of sky.
            XCTAssertEqual(fit.model.errors.axis1Index, 3.1, accuracy: 1e-3, "\(mode)")
            XCTAssertEqual(fit.model.errors.axis2Index, -2.2, accuracy: 1e-3, "\(mode)")
            XCTAssertEqual(fit.model.errors.baseTiltX, 0.0, accuracy: 1e-6)
            XCTAssertEqual(try XCTUnwrap(rig.controller.status.position).angularSeparation(to: Support.vega), 0.0, accuracy: 0.002)
            // The index offsets are all that is wrong, so every target is hit.
            for target in gotoTargets {
                let error = try goto(rig, target)
                XCTAssertTrue(error < 0.05, "\(mode) \(target) \(error)")
            }
        }
    }

    func testThreeStarsGotoWithinATenthOfADegree() throws {
        for mode in [altAz, equatorial] {
            let errors = mode == altAz ? Support.altAzimuthErrors : Support.equatorialErrors
            let rig = try connected(mode, errors)
            let stars = mode == altAz ? altAzimuthAlignmentStars : equatorialAlignmentStars
            try aligned(rig, stars)
            let fit = try XCTUnwrap(rig.driver.alignmentFit)
            XCTAssertEqual(rig.driver.alignmentPoints.count, 3)
            XCTAssertTrue(fit.maximumResidualDegrees < 0.05, "\(mode) \(fit.residualsDegrees)")
            var worst = 0.0
            for target in gotoTargets {
                let error = try goto(rig, target)
                worst = max(worst, error)
                XCTAssertTrue(error < 0.1, "\(mode) \(target) \(error)")
            }
            XCTAssertTrue(worst < 0.1, "\(mode) worst \(worst)")
        }
    }

    func testMoreStarsGiveABetterModel() throws {
        // The errors that one star cannot see: base tilt, orthogonality and cone. Each added star improves the worst error over the sky
        // (two stars cannot always separate them on an equatorial mount, but never make things much worse).
        for mode in [altAz, equatorial] {
            let errors = SkyWatcherPointingErrors(axis1Index: 2.0, axis2Index: -1.0, baseTiltX: 0.6, baseTiltY: -0.5, orthogonality: 0.2, cone: 0.1)
            var worstByStars: [Double] = []
            var predictedByStars: [Double] = []
            for count in 1 ... 3 {
                let rig = try connected(mode, errors)
                try aligned(rig, Array(equatorialAlignmentStars.prefix(count)))
                var worst = 0.0
                for target in gotoTargets { worst = max(worst, try goto(rig, target)) }
                worstByStars.append(worst)
                predictedByStars.append(try XCTUnwrap(rig.driver.alignmentFit).predictedErrorDegrees)
            }
            XCTAssertTrue(worstByStars[0] > 0.2, "\(mode) \(worstByStars)")
            XCTAssertTrue(worstByStars[1] < worstByStars[0] * 1.3, "\(mode) \(worstByStars)")
            XCTAssertTrue(worstByStars[2] < worstByStars[0] / 4, "\(mode) \(worstByStars)")
            XCTAssertTrue(worstByStars[2] < 0.1, "\(mode) \(worstByStars)")
            if mode == altAz { XCTAssertTrue(worstByStars[1] < worstByStars[0] * 0.5, "\(mode) \(worstByStars)") }
            XCTAssertTrue(predictedByStars[0] > predictedByStars[1] && predictedByStars[1] > predictedByStars[2], "\(mode) \(predictedByStars)")
        }
    }

    func testSouthernHemisphereEquatorialMount() throws {
        let observer = Support.sydney
        let rig = Support.rig(mode: equatorial, errors: Support.equatorialErrors, observer: observer)
        try rig.controller.connect()
        for star in [Support.acrux, Support.nunki, Support.peacock] { try rig.syncOn(star) }
        XCTAssertTrue(try XCTUnwrap(rig.driver.alignmentFit).maximumResidualDegrees < 0.05)
        XCTAssertTrue(try XCTUnwrap(rig.driver.pointingModel).isSouthernHemisphere)
        for target in [Support.kaus, Support.shaula, Support.betaCentauri, Support.alnair] {
            let error = try goto(rig, target)
            XCTAssertTrue(error < 0.1, "\(target) \(error)")
        }
        // Tracking runs the other way round in the southern hemisphere, and keeps the target.
        let target = Support.betaCentauri
        try goto(rig, target)
        Support.poll(rig, seconds: 300)
        XCTAssertTrue(rig.errorTo(target) < 0.05, "\(rig.errorTo(target))")
    }

    func testSouthernHemisphereAltAzimuthMount() throws {
        let rig = Support.rig(mode: altAz, errors: Support.altAzimuthErrors, observer: Support.sydney)
        try rig.controller.connect()
        for star in [Support.acrux, Support.nunki, Support.peacock] { try rig.syncOn(star) }
        for target in [Support.kaus, Support.shaula, Support.betaCentauri, Support.alnair] {
            let error = try goto(rig, target)
            XCTAssertTrue(error < 0.1, "\(target) \(error)")
        }
        XCTAssertTrue(worstTrackingDrift(rig, 10) < 0.03)
    }

    func testSyncResidualsAreExposedAndTheSameStarReplacesItsPoint() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        let fit = try XCTUnwrap(rig.driver.alignmentFit)
        XCTAssertEqual(fit.residualsDegrees.count, 3)
        XCTAssertTrue(fit.residualsDegrees.allSatisfy { $0 < 0.01 })
        XCTAssertTrue(fit.rmsDegrees < 0.01)
        XCTAssertTrue(rig.driver.alignmentPoints.allSatisfy { $0.timestamp >= Support.start })
        // Syncing a star again, ten minutes later, replaces its point (a better centring), it does not add a fourth.
        rig.clock.advance(seconds: 600.0)
        try rig.syncOn(Support.vega)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 3)
        XCTAssertEqual(try XCTUnwrap(rig.driver.alignmentFit).residualsDegrees.count, 3)
        // Syncing the same place again right away changes next to nothing.
        let again = try rig.controller.sync(Support.vega)
        XCTAssertTrue(again.offsetDegrees < 0.01, "\(again.offsetDegrees)")
    }

    func testAWrongStarIsRejected() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try rig.syncOn(Support.vega)
        try rig.syncOn(Support.mirfak)
        let modelBefore = try XCTUnwrap(rig.driver.pointingModel)
        // The user centred Enif but tells the app it was Hamal.
        rig.placeOn(Support.enif)
        let error = skyWatcherThrown { try rig.controller.sync(Support.hamal) }
        if case let .rejected(detail)? = error {
            XCTAssertTrue(detail.contains("right star"), detail)
        } else {
            XCTFail("expected a rejection, got \(String(describing: error))")
        }
        XCTAssertEqual(rig.driver.alignmentPoints.count, 2)
        XCTAssertEqual(rig.driver.pointingModel, modelBefore)
        // The right one is accepted.
        try rig.controller.sync(Support.enif)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 3)
        // And a mount that was not at home at all (home error of 70°) cannot be aligned with a plausible model.
        let lost = try connected(equatorial, SkyWatcherPointingErrors(axis1Index: 70.0))
        lost.placeOn(Support.vega)
        XCTAssertTrue(skyWatcherThrown { try lost.controller.sync(Support.vega) }?.isRejected == true)
        XCTAssertEqual(lost.driver.alignmentPoints.count, 0)
    }

    func testAlignmentCanBeManagedByTheApp() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        let points = rig.driver.alignmentPoints
        let predictedBefore = try XCTUnwrap(rig.driver.alignmentFit).predictedErrorDegrees
        var worstBefore = 0.0
        for target in gotoTargets { worstBefore = max(worstBefore, try goto(rig, target)) }
        XCTAssertTrue(worstBefore < 0.1)
        try rig.driver.removeAlignmentPoint(2)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 2)
        XCTAssertTrue(try XCTUnwrap(rig.driver.alignmentFit).predictedErrorDegrees > predictedBefore)
        XCTAssertTrue(skyWatcherThrown { try rig.driver.removeAlignmentPoint(5) }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try rig.driver.removeAlignmentPoint(-1) }?.isInvalidInput == true)
        try rig.driver.removeAlignmentPoint(1)
        try rig.driver.removeAlignmentPoint(0)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 0)
        XCTAssertNil(rig.driver.alignmentFit)
        XCTAssertEqual(try rig.driver.readAligned(), false)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.goto(Support.deneb) }, .notAligned)
        try rig.driver.restoreAlignment(points)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 3)
        XCTAssertTrue(try goto(rig, Support.deneb) < 0.1)
        rig.driver.clearAlignment()
        XCTAssertEqual(skyWatcherThrown { try rig.controller.goto(Support.altair) }, .notAligned)
        XCTAssertTrue(skyWatcherThrown { try rig.driver.restoreAlignment([]) }?.isInvalidInput == true)
        // At most eight points are kept: the oldest go first.
        let many = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        for step in 0 ..< 11 {
            try many.syncOn(EquatorialCoordinate(rightAscension: Support.vega.rightAscension + Double(step) * 3.0,
                                                 declination: Support.vega.declination - Double(step)))
        }
        XCTAssertEqual(many.driver.alignmentPoints.count, SkyWatcherAlignmentSolver.maximumPoints)
    }

    func testSiteChangesKeepOrDropTheAlignment() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        let here = Support.boulderLocation
        // The same place with a better GPS fix: the alignment stays.
        try rig.controller.setSiteAndTime(location: GeographicLocation(latitude: here.latitude + 0.01, longitude: here.longitude - 0.01,
                                                                       elevation: here.elevation))
        XCTAssertEqual(rig.driver.alignmentPoints.count, 3)
        XCTAssertEqual(rig.driver.location.latitude, here.latitude + 0.01, accuracy: 1e-12)
        // A different place: the points no longer describe the sky, the alignment is dropped.
        try rig.controller.setSiteAndTime(location: GeographicLocation(latitude: here.latitude + 1.0, longitude: here.longitude,
                                                                       elevation: here.elevation))
        XCTAssertEqual(rig.driver.alignmentPoints.count, 0)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.goto(Support.deneb) }, .notAligned)
        // Crossing the equator drops it as well (and mirrors the model).
        let south = try connected(equatorial, Support.equatorialErrors)
        try south.syncOn(Support.vega)
        try south.controller.setSiteAndTime(location: GeographicLocation(latitude: -here.latitude, longitude: here.longitude, elevation: 0.0))
        XCTAssertEqual(south.driver.alignmentPoints.count, 0)
        XCTAssertTrue(try XCTUnwrap(south.driver.pointingModel).isSouthernHemisphere)
        let disconnected = Support.rig(mode: altAz)
        XCTAssertEqual(skyWatcherThrown { try disconnected.controller.setSiteAndTime(location: here) }, .notConnected)
    }

    // MARK: Slewing

    func testGotoSlewsAtAFiniteSpeedAndArrivesTracking() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        let before = rig.clock.secondsSince1970
        let startAxis1 = rig.simulator.axis1Degrees
        try rig.controller.goto(Support.altair)
        XCTAssertEqual(rig.controller.status.phase, .slewing)
        let status = rig.controller.awaitSettled()
        let seconds = rig.clock.secondsSince1970 - before
        XCTAssertEqual(status.phase, .idle)
        XCTAssertTrue(arrived(status.outcome))
        // The mount cannot be faster than its maximum speed: the azimuth change takes at least that long.
        let travelled = abs(rig.simulator.axis1Degrees - startAxis1)
        XCTAssertTrue(travelled > 20.0, "\(travelled)")
        XCTAssertTrue(seconds >= travelled / 3.0, "\(seconds) s for \(travelled)°")
        XCTAssertTrue(rig.simulator.peakSpeedDegreesPerSecond <= 3.0 + 1e-6, "\(rig.simulator.peakSpeedDegreesPerSecond)")
        XCTAssertTrue(rig.simulator.peakSpeedDegreesPerSecond > 2.0)
        XCTAssertTrue(rig.errorTo(Support.altair) < 0.05)
        rig.controller.poll()
        XCTAssertEqual(rig.controller.status.isTracking, true)
        XCTAssertEqual(rig.controller.status.target, Support.altair)
        XCTAssertTrue((rig.controller.status.separation ?? 9.0) < 0.05)
        XCTAssertNil(rig.controller.status.slewElapsedSeconds)
    }

    func testGotoRefusalsAndMountLimits() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        let moves = rig.simulator.gotosStarted
        // Below the user's altitude limit: the controller refuses before anything is sent.
        if case .belowHorizonLimit? = skyWatcherThrown({ try rig.controller.goto(MountTestSupport.orionNebula) }) {} else { XCTFail("below the limit") }
        // Near the zenith of an alt-azimuth mount: the mount's own overhead limit.
        let frame = rig.frame()
        let zenith = MountEpoch.apparentOfDate.toJ2000(
            EquatorialCoordinate(rightAscension: frame.localApparentSiderealTime, declination: Support.boulderLocation.latitude - 0.3), frame: frame)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.goto(zenith) }, .mountOverheadLimit)
        XCTAssertEqual(rig.simulator.gotosStarted, moves)
        XCTAssertEqual(rig.controller.status.phase, .idle)
        // The mount's horizon limit is configurable: Rasalhague (altitude 17) is too low for a limit of 30.
        let limited = Support.rig(mode: altAz, errors: Support.altAzimuthErrors,
                                  configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: altAz,
                                                                         limits: SkyWatcherLimits(minimumAltitudeDegrees: 30.0)))
        try limited.controller.connect()
        try aligned(limited, altAzimuthAlignmentStars)
        XCTAssertEqual(skyWatcherThrown { try limited.controller.goto(Support.rasalhague) }, .mountHorizonLimit)
        XCTAssertTrue(try goto(limited, Support.deneb) < 0.1)
        // Cable wrap: with the azimuth axis limited to +-130° Markab (azimuth 169°) cannot be reached, Alpheratz (116°) can.
        let wrapped = Support.rig(mode: altAz, errors: Support.altAzimuthErrors,
                                  configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: altAz,
                                                                         limits: SkyWatcherLimits(azimuthMinimumDegrees: -130.0,
                                                                                                  azimuthMaximumDegrees: 130.0)))
        try wrapped.controller.connect()
        try aligned(wrapped, [Support.andromeda, Support.mirfak, Support.hamal])
        XCTAssertEqual(skyWatcherThrown { try wrapped.controller.goto(Support.markab) }, .outsideMountLimits)
        XCTAssertTrue(try goto(wrapped, Support.alpheratz) < 0.1)
        // The way round: vega at azimuth 290° is axis angle -70°, inside the limits, the short way.
        XCTAssertTrue(try goto(wrapped, Support.vega) < 0.1)
        XCTAssertTrue(wrapped.simulator.axis1Degrees < -60.0 && wrapped.simulator.axis1Degrees > -80.0, "\(wrapped.simulator.axis1Degrees)")
    }

    func testAzimuthTakesTheShortWayWithinTheCableWrapLimits() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        // Vega is at azimuth 290° (axis angle -70° or 290°), Mirfak at 54°: going between them never turns the long way.
        try goto(rig, Support.vega)
        let atVega = rig.simulator.axis1Degrees
        XCTAssertTrue(abs(atVega) < 200.0, "\(atVega)")
        try goto(rig, Support.mirfak)
        let atMirfak = rig.simulator.axis1Degrees
        XCTAssertTrue(abs(atMirfak - atVega) < 180.0, "\(atVega) -> \(atMirfak)")
    }

    func testASecondGotoIsRefusedAndAbortStopsTheSlew() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        try rig.controller.goto(Support.capella)
        rig.clock.advance(seconds: 3.0)
        rig.controller.poll()
        XCTAssertEqual(rig.controller.status.phase, .slewing)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.goto(Support.deneb) }, .slewInProgress)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.sync(Support.vega) }, .slewInProgress)
        try rig.controller.abort()
        XCTAssertEqual(rig.controller.status.phase, .idle)
        XCTAssertTrue(aborted(rig.controller.status.outcome))
        rig.clock.advance(seconds: 2.0)
        // The mount decelerated and did not arrive; it stands (or resumes tracking, which is far slower than a slew).
        XCTAssertTrue(rig.simulator.peakSpeedDegreesPerSecond > 1.0)
        let position = rig.controller.poll().position
        XCTAssertTrue(try XCTUnwrap(position).angularSeparation(to: Support.capella) > 1.0)
        rig.clock.advance(seconds: 5.0)
        rig.controller.poll()
        // Tracking resumes at the place where the mount was stopped.
        let first = rig.trueJ2000()
        Support.poll(rig, seconds: 60)
        XCTAssertTrue(rig.trueJ2000().angularSeparation(to: first) < 0.05, "\(rig.trueJ2000().angularSeparation(to: first))")
        // A new goto works after an abort.
        XCTAssertTrue(try goto(rig, Support.deneb) < 0.1)
    }

    func testLongSlewsAreCorrectedForTheMovingSky() throws {
        // A planner that believes the mount is ten times slower aims far behind the target; the correction slews fix it.
        let slow = Support.rig(mode: altAz, errors: Support.altAzimuthErrors,
                               configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: altAz, assumedSlewDegreesPerSecond: 0.25))
        try slow.controller.connect()
        try aligned(slow, altAzimuthAlignmentStars)
        let gotosBefore = slow.simulator.gotosStarted
        XCTAssertTrue(try goto(slow, Support.altair) < 0.05)
        XCTAssertTrue(slow.simulator.gotosStarted - gotosBefore > 2, "corrections: \(slow.simulator.gotosStarted - gotosBefore)")
        let good = try connected(altAz, Support.altAzimuthErrors)
        try aligned(good, altAzimuthAlignmentStars)
        let goodBefore = good.simulator.gotosStarted
        XCTAssertTrue(try goto(good, Support.altair) < 0.05)
        XCTAssertTrue(good.simulator.gotosStarted - goodBefore <= slow.simulator.gotosStarted - gotosBefore)
    }

    // MARK: Equatorial mounts: pier side and meridian

    private func hourAnglePlace(_ rig: SkyWatcherRig, _ hourAngle: Double, _ declination: Double) -> EquatorialCoordinate {
        let frame = rig.frame()
        return MountEpoch.apparentOfDate.toJ2000(EquatorialCoordinate(rightAscension: frame.localApparentSiderealTime - hourAngle,
                                                                      declination: declination), frame: frame)
    }

    func testEquatorialMountKeepsTheCounterweightDown() throws {
        let rig = try connected(equatorial, Support.equatorialErrors)
        try aligned(rig, equatorialAlignmentStars)
        let index = Support.equatorialErrors.axis1Index
        var side: SkyWatcherPierSide?
        for target in [Support.altair, Support.hamal, Support.deneb, Support.capella, Support.andromeda, Support.rasalhague, Support.alpheratz] {
            try rig.controller.goto(target)
            var worstAxis = 0.0
            while rig.controller.status.phase == .slewing {
                rig.controller.poll()
                worstAxis = max(worstAxis, abs(rig.simulator.axis1Degrees + index))
                rig.clock.advance(seconds: 1.0)
            }
            XCTAssertTrue(rig.errorTo(target) < 0.1, "\(target) \(rig.errorTo(target))")
            // Along the whole slew and afterwards: the counterweight stays within a few degrees of horizontal or lower.
            worstAxis = max(worstAxis, abs(rig.simulator.axis1Degrees + index))
            XCTAssertTrue(worstAxis <= 95.0 + 1e-6, "\(target) \(worstAxis)")
            side = rig.driver.pierSide
            let frame = rig.frame()
            let hourAngle = AstroMath.normalizeSignedDegrees(
                frame.localApparentSiderealTime - MountEpoch.apparentOfDate.fromJ2000(target, frame: frame).rightAscension)
            // West of the meridian the telescope is on the east side of the mount (normal), east of it on the west side.
            if hourAngle > 6.0 { XCTAssertEqual(side, .east, "\(target) H=\(hourAngle)") }
            if hourAngle < -6.0 { XCTAssertEqual(side, .west, "\(target) H=\(hourAngle)") }
        }
        XCTAssertNotNil(side)
    }

    func testTheCurrentSideIsKeptNearTheMeridian() throws {
        let rig = try connected(equatorial, Support.equatorialErrors)
        try aligned(rig, equatorialAlignmentStars)
        // Right on the meridian either side works (within the 5° overlap): the mount stays on the side it is on.
        let onMeridian = hourAnglePlace(rig, 2.0, 25.0)
        try goto(rig, Support.hamal)
        XCTAssertEqual(rig.driver.pierSide, .west)
        XCTAssertTrue(try goto(rig, onMeridian) < 0.1)
        XCTAssertEqual(rig.driver.pierSide, .west)
        try goto(rig, Support.altair)
        XCTAssertEqual(rig.driver.pierSide, .east)
        XCTAssertTrue(try goto(rig, hourAnglePlace(rig, -2.0, 25.0)) < 0.1)
        XCTAssertEqual(rig.driver.pierSide, .east)
        // Past the overlap the side must change: the meridian flip is a goto to the same star.
        let east = hourAnglePlace(rig, -20.0, 25.0)
        XCTAssertTrue(try goto(rig, east) < 0.1)
        XCTAssertEqual(rig.driver.pierSide, .west)
    }

    func testTrackingStopsAtTheMeridianLimitAndAGotoFlipsTheMount() throws {
        let configuration = SkyWatcherConfiguration(location: Support.boulderLocation, mode: equatorial,
                                                    limits: SkyWatcherLimits(meridianOverlapDegrees: 0.0))
        let rig = Support.rig(mode: equatorial, errors: SkyWatcherPointingErrors(axis1Index: 1.0), configuration: configuration)
        try rig.controller.connect()
        try aligned(rig, equatorialAlignmentStars)
        // Two degrees east of the meridian: on the west side of the mount, the counterweight 2° from horizontal.
        let target = hourAnglePlace(rig, -2.0, 30.0)
        XCTAssertTrue(try goto(rig, target) < 0.1)
        XCTAssertEqual(rig.driver.pierSide, .west)
        XCTAssertEqual(rig.controller.poll().isTracking, true)
        // The sky carries the star across the meridian in 8 minutes; the mount stops there instead of turning the counterweight up.
        Support.poll(rig, seconds: 120)
        XCTAssertEqual(rig.controller.poll().isTracking, true)
        Support.poll(rig, seconds: 600)
        let status = rig.controller.poll()
        XCTAssertEqual(status.isTracking, false)
        XCTAssertEqual(rig.driver.trackingStopReason, .outsideMountLimits)
        XCTAssertFalse(rig.simulator.isMoving)
        XCTAssertTrue(rig.simulator.axis1Degrees + 1.0 < 90.5)
        // The meridian flip: a goto to the same star now chooses the other side, and tracking runs again.
        XCTAssertTrue(try goto(rig, target) < 0.1)
        XCTAssertEqual(rig.driver.pierSide, .east)
        XCTAssertNil(rig.driver.trackingStopReason)
        Support.poll(rig, seconds: 300)
        XCTAssertEqual(rig.controller.poll().isTracking, true)
        XCTAssertTrue(rig.errorTo(target) < 0.05, "\(rig.errorTo(target))")
    }

    /// The altitude of where the real telescope points.
    private func realAltitude(_ rig: SkyWatcherRig) -> Double {
        SkyWatcherSky.altitude(rig.simulator.truePlace(), localSiderealTime: rig.frame().localApparentSiderealTime,
                               latitude: rig.simulator.location.latitude)
    }

    /// Slews to `end` and returns the lowest altitude the real telescope had on the way (sampled every tenth of a second).
    private func lowestAltitudeOnTheWayTo(_ rig: SkyWatcherRig, _ end: EquatorialCoordinate) throws -> Double {
        try rig.controller.goto(end)
        var lowest = realAltitude(rig)
        while rig.controller.status.phase == .slewing {
            for _ in 0 ..< 8 {
                rig.clock.advance(seconds: 0.1)
                lowest = min(lowest, realAltitude(rig))
            }
            rig.controller.poll()
        }
        XCTAssertTrue(arrived(rig.controller.status.outcome), "\(String(describing: rig.controller.status.outcome))")
        return lowest
    }

    func testSlewsThatWouldDipBelowTheHorizonAreSplit() throws {
        func rigFor(_ limits: SkyWatcherLimits) throws -> SkyWatcherRig {
            let configuration = SkyWatcherConfiguration(location: Support.boulderLocation, mode: equatorial, limits: limits)
            let rig = Support.rig(mode: equatorial, settings: MountSettings(altitudeLimit: 10.0), configuration: configuration)
            try rig.controller.connect()
            return rig
        }
        // From a star near the lower pole to one on the other side of the meridian: moving both axes at once sweeps the telescope down to
        // 10° above the horizon, moving the right ascension axis first keeps it above 20°.
        let direct = try rigFor(SkyWatcherLimits())
        let begin = hourAnglePlace(direct, 164.6, 84.2)
        let end = hourAnglePlace(direct, 39.1, -7.7)
        try direct.syncOn(begin)
        XCTAssertTrue(realAltitude(direct) > 20.0)
        let lowestDirect = try lowestAltitudeOnTheWayTo(direct, end)
        XCTAssertTrue(lowestDirect < 15.0, "\(lowestDirect)")
        let split = try rigFor(SkyWatcherLimits(minimumAltitudeDegrees: 20.0, pathMarginDegrees: 0.0))
        try split.syncOn(begin)
        let lowestSplit = try lowestAltitudeOnTheWayTo(split, end)
        XCTAssertTrue(lowestSplit > 19.0, "\(lowestSplit)")
        XCTAssertTrue(split.errorTo(end) < 0.1)
        // Both ways dip below the limit: refused, and the mount does not move.
        let blocked = try rigFor(SkyWatcherLimits(minimumAltitudeDegrees: 20.0, pathMarginDegrees: 0.0))
        let from = hourAnglePlace(blocked, 54.4, -4.3)
        let to = hourAnglePlace(blocked, -29.9, -8.7)
        try blocked.syncOn(from)
        let before = blocked.simulator.gotosStarted
        XCTAssertEqual(skyWatcherThrown { try blocked.controller.goto(to) }, .outsideMountLimits)
        XCTAssertEqual(blocked.simulator.gotosStarted, before)
        XCTAssertEqual(blocked.controller.status.phase, .idle)
    }

    // MARK: Tracking

    /// Polls once a second for `minutes` minutes and returns how far the real telescope drifted from where it was at the start.
    private func worstTrackingDrift(_ rig: SkyWatcherRig, _ minutes: Int) -> Double {
        let start = rig.trueJ2000()
        var worst = 0.0
        for _ in 0 ..< minutes {
            Support.poll(rig, seconds: 60)
            worst = max(worst, rig.trueJ2000().angularSeparation(to: start))
        }
        return worst
    }

    func testAltAzimuthTrackingKeepsTheTarget() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        for target in [Support.deneb, Support.hamal, Support.rasalhague] {
            XCTAssertTrue(try goto(rig, target) < 0.1)
            let worst = worstTrackingDrift(rig, 20)
            XCTAssertTrue(worst < 0.03, "\(target) \(worst)")
        }
        // Both axes run in speed mode the whole time, with rates that follow the sky.
        XCTAssertEqual(rig.controller.status.isTracking, true)
        XCTAssertTrue(rig.simulator.isMoving)
        XCTAssertTrue(rig.simulator.speedStarts > 5, "\(rig.simulator.speedStarts)")
    }

    func testEquatorialTrackingKeepsTheTargetAndAServoCompensatesThePolarError() throws {
        let errors = SkyWatcherPointingErrors(axis1Index: 1.5, axis2Index: -1.0)
        let rig = try connected(equatorial, errors)
        try aligned(rig, equatorialAlignmentStars)
        XCTAssertTrue(try goto(rig, Support.deneb) < 0.05)
        XCTAssertTrue(worstTrackingDrift(rig, 20) < 0.03)
        // Sidereal tracking on one axis: it was started once, after the slew, and never restarted.
        XCTAssertEqual(rig.simulator.speedStarts, 1)
        // A polar alignment error makes the target drift while the mount tracks at the sidereal rate; the servo strategy, which knows
        // the error from the alignment, removes that drift.
        let tilted = SkyWatcherPointingErrors(axis1Index: 1.5, axis2Index: -1.0, baseTiltX: 0.8, baseTiltY: -0.6)
        let sidereal = try connected(equatorial, tilted)
        try aligned(sidereal, equatorialAlignmentStars)
        try goto(sidereal, Support.altair)
        let drifting = worstTrackingDrift(sidereal, 30)
        let servo = Support.rig(mode: equatorial, errors: tilted,
                                configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: equatorial, trackingStrategy: .servo))
        try servo.controller.connect()
        try aligned(servo, equatorialAlignmentStars)
        try goto(servo, Support.altair)
        let compensated = worstTrackingDrift(servo, 30)
        XCTAssertTrue(drifting > 0.05, "sidereal drift \(drifting)")
        XCTAssertTrue(compensated < 0.03, "servo \(compensated)")
        XCTAssertTrue(compensated < drifting / 2)
    }

    func testAltAzimuthTrackingStopsAtTheCableWrapLimit() throws {
        let configuration = SkyWatcherConfiguration(location: Support.boulderLocation, mode: altAz,
                                                    limits: SkyWatcherLimits(azimuthMinimumDegrees: -20.0, azimuthMaximumDegrees: 100.0))
        let rig = Support.rig(mode: altAz, errors: SkyWatcherPointingErrors(axis1Index: 1.0), configuration: configuration)
        try rig.controller.connect()
        try aligned(rig, [Support.altair, Support.mirfak, Support.enif])
        // Hamal is at azimuth 96° and rises: the azimuth axis reaches the limit of 100° after a while and tracking stops there.
        XCTAssertTrue(try goto(rig, Support.hamal) < 0.1)
        XCTAssertEqual(rig.controller.poll().isTracking, true)
        XCTAssertTrue((90.0 ... 99.0).contains(rig.simulator.axis1Degrees), "\(rig.simulator.axis1Degrees)")
        Support.poll(rig, seconds: 3000)
        let status = rig.controller.poll()
        XCTAssertEqual(status.isTracking, false)
        XCTAssertEqual(rig.driver.trackingStopReason, .outsideMountLimits)
        XCTAssertFalse(rig.simulator.isMoving)
        XCTAssertEqual(rig.simulator.axis1Degrees, 100.0, accuracy: 1.0)
        // Tracking can be switched on again, but the cause is still there: the mount refuses and stays where it is.
        XCTAssertEqual(skyWatcherThrown { try rig.controller.setTracking(true) }, .outsideMountLimits)
        Support.poll(rig, seconds: 5)
        XCTAssertEqual(rig.controller.poll().isTracking, false)
        XCTAssertFalse(rig.simulator.isMoving)
    }

    func testServoUpdatesAreRateLimited() throws {
        // The app may poll as often as it likes: the rates of the axes are updated at most once per update interval.
        func updates(_ intervalSeconds: Double) throws -> Int {
            let rig = Support.rig(mode: altAz, errors: Support.altAzimuthErrors,
                                  configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: altAz,
                                                                         trackingUpdateIntervalSeconds: intervalSeconds))
            try rig.controller.connect()
            try aligned(rig, altAzimuthAlignmentStars)
            try goto(rig, Support.deneb)
            rig.simulator.clearLog()
            let begin = rig.clock.secondsSince1970
            while rig.clock.secondsSince1970 - begin < 60.0 {
                rig.controller.poll()
                rig.clock.advance(seconds: 0.1)
            }
            return rig.simulator.commandLog.filter { $0 == "I1" }.count
        }
        let fast = try updates(1.0)
        let slow = try updates(5.0)
        XCTAssertTrue((40 ... 70).contains(fast), "\(fast)")
        XCTAssertTrue((8 ... 16).contains(slow), "\(slow)")
    }

    func testTrackingCanBeSwitchedOffAndOn() throws {
        for mode in [altAz, equatorial] {
            let rig = try connected(mode, SkyWatcherPointingErrors(axis1Index: 1.0, axis2Index: 0.5))
            try aligned(rig, [Support.vega, Support.mirfak, Support.enif])
            XCTAssertTrue(try goto(rig, Support.deneb) < 0.1)
            try rig.controller.setTracking(false)
            Support.poll(rig, seconds: 2)
            XCTAssertFalse(rig.simulator.isMoving, "\(mode)")
            XCTAssertEqual(rig.controller.poll().isTracking, false)
            let start = rig.trueJ2000()
            Support.poll(rig, seconds: 60)
            // The sky moves 15 arcseconds per second: a minute of drift is a quarter of a degree (cos δ = 0.7 for Deneb).
            let drift = rig.trueJ2000().angularSeparation(to: start)
            XCTAssertTrue((0.15 ... 0.30).contains(drift), "\(mode) \(drift)")
            try rig.controller.setTracking(true)
            XCTAssertEqual(rig.controller.poll().isTracking, true)
            let resumed = rig.trueJ2000()
            Support.poll(rig, seconds: 120)
            XCTAssertTrue(rig.trueJ2000().angularSeparation(to: resumed) < 0.05, "\(mode)")
            // Switching it off twice is harmless.
            try rig.controller.setTracking(false)
            try rig.controller.setTracking(false)
        }
    }

    func testDisconnectStopsAServoButLeavesSiderealTrackingRunning() throws {
        let altAzRig = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(altAzRig, altAzimuthAlignmentStars)
        try goto(altAzRig, Support.deneb)
        Support.poll(altAzRig, seconds: 3)
        XCTAssertTrue(altAzRig.simulator.isMoving)
        altAzRig.controller.disconnect()
        altAzRig.clock.advance(seconds: 2.0)
        XCTAssertFalse(altAzRig.simulator.isMoving)
        XCTAssertEqual(altAzRig.controller.status.phase, .disconnected)
        let equatorialRig = try connected(equatorial, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(equatorialRig, equatorialAlignmentStars)
        try goto(equatorialRig, Support.deneb)
        equatorialRig.controller.disconnect()
        equatorialRig.clock.advance(seconds: 2.0)
        XCTAssertTrue(equatorialRig.simulator.isMoving)
        // Connecting again stops the mount: the session starts from rest.
        try equatorialRig.controller.connect()
        XCTAssertFalse(equatorialRig.simulator.isMoving)
        XCTAssertEqual(equatorialRig.controller.poll().isTracking, false)
    }

    func testGotoByAbsoluteTargetsWorksToo() throws {
        // `S` (absolute target) instead of `H` (increment) and `M` (brake point).
        for mode in [altAz, equatorial] {
            let errors = mode == altAz ? Support.altAzimuthErrors : Support.equatorialErrors
            let rig = Support.rig(mode: mode, errors: errors,
                                  configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: mode, usesAbsoluteGotoTarget: true))
            try rig.controller.connect()
            try aligned(rig, [Support.vega, Support.mirfak, Support.enif])
            for target in [Support.deneb, Support.hamal] { XCTAssertTrue(try goto(rig, target) < 0.1, "\(mode) \(target)") }
            XCTAssertTrue(rig.simulator.commandLog.contains { $0.hasPrefix("S") })
            XCTAssertFalse(rig.simulator.commandLog.contains { $0.hasPrefix("H") || $0.hasPrefix("M") })
        }
    }

    // MARK: Nudges

    private func skyOffset(_ from: EquatorialCoordinate, _ to: EquatorialCoordinate) -> (Double, Double) {
        let delta = to.unitVector - from.unitVector
        return (delta.dot(east(from)), delta.dot(north(from)))
    }

    func testNudgesMoveTheViewAcrossTheSky() throws {
        for mode in [altAz, equatorial] {
            let rig = try connected(mode, SkyWatcherPointingErrors(axis1Index: 1.0, axis2Index: -0.5))
            try aligned(rig, [Support.vega, Support.mirfak, Support.enif])
            try goto(rig, Support.deneb)
            let sidereal = MountNudgeRate.siderealDegreesPerSecond
            for direction in MountNudgeDirection.allCases {
                let before = rig.trueJ2000()
                try rig.controller.nudge(direction, rate: .find, durationSeconds: 3.0)
                XCTAssertEqual(rig.controller.status.phase, .nudging)
                // Hold for about three seconds, polling every half second as the app does while a button is down.
                let begin = rig.clock.secondsSince1970
                while rig.clock.secondsSince1970 - begin < 3.0 {
                    rig.clock.advance(seconds: 0.5)
                    rig.controller.poll()
                }
                try rig.controller.stopNudge()
                XCTAssertEqual(rig.controller.status.phase, .idle)
                let after = rig.trueJ2000()
                let (eastward, northward) = skyOffset(before, after)
                let seconds = rig.clock.secondsSince1970 - begin
                let expected = 32.0 * sidereal * seconds * AstroMath.radians(1.0)
                let moved = hypot(eastward, northward)
                XCTAssertTrue(moved >= expected * 0.7 && moved <= expected * 1.4, "\(mode) \(direction) moved \(moved) expected \(expected)")
                switch direction {
                case .east: XCTAssertTrue(eastward > 0 && abs(northward) < 0.2 * eastward, "\(mode) east \(eastward) \(northward)")
                case .west: XCTAssertTrue(eastward < 0 && abs(northward) < 0.2 * -eastward, "\(mode) west \(eastward) \(northward)")
                case .north: XCTAssertTrue(northward > 0 && abs(eastward) < 0.2 * northward, "\(mode) north \(eastward) \(northward)")
                case .south: XCTAssertTrue(northward < 0 && abs(eastward) < 0.2 * -northward, "\(mode) south \(eastward) \(northward)")
                }
                try goto(rig, Support.deneb)
            }
            // After a nudge tracking resumes at the new place.
            let place = rig.trueJ2000()
            Support.poll(rig, seconds: 60)
            XCTAssertTrue(rig.trueJ2000().angularSeparation(to: place) < 0.05)
        }
    }

    func testANudgeIntoTheOverheadLimitEndsAndTrackingContinues() throws {
        let rig = Support.rig(mode: altAz, errors: SkyWatcherPointingErrors(axis1Index: 1.0), settings: MountSettings(maximumNudgeSeconds: 30.0))
        try rig.controller.connect()
        try aligned(rig, altAzimuthAlignmentStars)
        // Scheat is 77° up, south of the zenith: north is straight up, towards the mount's overhead limit of 88°.
        let scheat = EquatorialCoordinate(rightAscensionHours: 23.0629, declination: 28.0828)
        XCTAssertTrue(try goto(rig, scheat) < 0.1)
        try rig.controller.nudge(.north, rate: .slew, durationSeconds: 30.0)
        for _ in 0 ..< 60 {
            rig.clock.advance(seconds: 0.5)
            rig.controller.poll()
        }
        try rig.controller.stopNudge()
        let altitude = realAltitude(rig)
        // It went up from 78° and ended before the limit: a fast nudge is stopped about a second early, because the mount needs
        // that long to come to a halt (near the zenith a fraction of a degree of the axis is several degrees of the sky).
        XCTAssertTrue((80.0 ... 88.0).contains(altitude), "\(altitude)")
        XCTAssertNil(rig.driver.trackingStopReason)
        // The mount tracks at the place where the nudge ended.
        let place = rig.trueJ2000()
        Support.poll(rig, seconds: 60)
        XCTAssertTrue(rig.trueJ2000().angularSeparation(to: place) < 0.05)
        XCTAssertEqual(rig.controller.poll().isTracking, true)
    }

    func testANudgeIntoTheAzimuthLimitEndsInsteadOfUnwinding() throws {
        let rig = Support.rig(mode: altAz, settings: MountSettings(maximumNudgeSeconds: 30.0))
        try rig.controller.connect()
        // Three degrees short of the cable limit of 270°, in the west and 40° up: a nudge to the west turns the azimuth axis on.
        rig.simulator.placeAxes(axis1Degrees: 267.0, axis2Degrees: 40.0)
        try rig.controller.nudge(.west, rate: .slew, durationSeconds: 20.0)
        var highest = rig.simulator.axis1Degrees
        for _ in 0 ..< 30 {
            rig.clock.advance(seconds: 0.5)
            rig.controller.poll()
            highest = max(highest, rig.simulator.axis1Degrees)
        }
        // The axis went towards the limit and stopped there; it did not run back the other way round at full speed.
        XCTAssertTrue(highest > 268.0 && highest < 271.0, "\(highest)")
        XCTAssertTrue(rig.simulator.axis1Degrees > 268.0, "\(rig.simulator.axis1Degrees)")
        XCTAssertFalse(rig.simulator.isMoving)
    }

    func testLosingTheLinkDuringANudgeStopsTheAxes() throws {
        let rig = Support.rig(mode: altAz, errors: SkyWatcherPointingErrors(axis1Index: 1.0), settings: MountSettings(maximumNudgeSeconds: 30.0))
        try rig.controller.connect()
        try aligned(rig, altAzimuthAlignmentStars)
        try goto(rig, Support.deneb)
        try rig.controller.nudge(.east, rate: .find, durationSeconds: 30.0)
        rig.clock.advance(seconds: 1.0)
        XCTAssertTrue(rig.simulator.isMoving)
        rig.simulator.inject("j1", .silence, times: 100)
        rig.controller.poll()
        rig.controller.poll()
        let ended = rig.controller.poll()
        XCTAssertEqual(ended.phase, .disconnected)
        XCTAssertEqual(ended.lastError, .connectionLost)
        // The nudge was running when the session ended: the axes were told to stop, tracking or not.
        rig.clock.advance(seconds: 2.0)
        XCTAssertFalse(rig.simulator.isMoving)
    }

    func testNudgeRatesFollowTheSiderealMultiples() throws {
        let rig = try connected(equatorial, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(rig, equatorialAlignmentStars)
        try goto(rig, Support.deneb)
        for rate in [MountNudgeRate.guide, MountNudgeRate.center, MountNudgeRate.find] {
            let before = rig.trueJ2000()
            try rig.controller.nudge(.north, rate: rate, durationSeconds: 4.0)
            let begin = rig.clock.secondsSince1970
            while rig.clock.secondsSince1970 - begin < 4.0 {
                rig.clock.advance(seconds: 0.5)
                rig.controller.poll()
            }
            try rig.controller.stopNudge()
            let moved = rig.trueJ2000().angularSeparation(to: before)
            let expected = rate.degreesPerSecond * (rig.clock.secondsSince1970 - begin)
            XCTAssertTrue(moved >= expected * 0.7 && moved <= expected * 1.3, "\(rate) moved \(moved) expected \(expected)")
            try goto(rig, Support.deneb)
        }
    }

    func testFastNudgesUseTheHighSpeedMode() throws {
        let rig = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(rig, altAzimuthAlignmentStars)
        // Markab is high on the meridian: east is the azimuth direction there, and the azimuth axis must run fast to carry 0.53°/s.
        try goto(rig, Support.markab)
        let slewPeak = rig.simulator.peakSpeedDegreesPerSecond
        try rig.controller.nudge(.east, rate: .slew, durationSeconds: 2.0)
        // The view moves at 128 times sidereal (0.53°/s); the azimuth axis carries it at 0.53/cos(65°) and runs in the fast mode.
        var fast = false
        for axis in [1, 2] {
            try rig.simulator.send(MountText.latin1Bytes(":f\(axis)\r"))
            let reply = Array(MountText.latin1(try rig.simulator.receive(maxCount: 64, timeoutSeconds: 1.0)))
            if "4567".contains(reply[1]) { fast = true }
        }
        XCTAssertTrue(fast)
        rig.clock.advance(seconds: 1.0)
        rig.controller.poll()
        XCTAssertTrue(rig.simulator.peakSpeedDegreesPerSecond > 0.5)
        XCTAssertTrue(rig.simulator.peakSpeedDegreesPerSecond <= max(slewPeak, 3.0))
        try rig.controller.stopNudge()
    }

    func testANudgeNobodyStopsEndsByItself() throws {
        let rig = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(rig, altAzimuthAlignmentStars)
        try goto(rig, Support.deneb)
        try rig.driver.startNudge(direction: .west, rate: .find, durationSeconds: 1.0)
        rig.clock.advance(seconds: 6.0)
        // The app is gone: the next call of the driver ends the nudge after its duration plus a grace period.
        XCTAssertFalse(try rig.driver.readSlewing())
        let stopped = rig.trueJ2000()
        Support.poll(rig, seconds: 30)
        XCTAssertTrue(rig.trueJ2000().angularSeparation(to: stopped) < 0.05)
    }

    func testAbortStopsANudgeAndNudgesAreRefusedWhileSlewing() throws {
        let rig = try connected(equatorial, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(rig, equatorialAlignmentStars)
        try goto(rig, Support.deneb)
        try rig.controller.nudge(.east, rate: .center, durationSeconds: 5.0)
        rig.clock.advance(seconds: 1.0)
        try rig.controller.abort()
        XCTAssertEqual(rig.controller.status.phase, .idle)
        rig.clock.advance(seconds: 2.0)
        rig.controller.poll()
        // Stopped nudging, tracking continues.
        let place = rig.trueJ2000()
        Support.poll(rig, seconds: 30)
        XCTAssertTrue(rig.trueJ2000().angularSeparation(to: place) < 0.05)
        try rig.controller.goto(Support.altair)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.nudge(.east) }, .slewInProgress)
        try rig.controller.abort()
    }

    // MARK: Axis senses

    func testInvertedAxesWork() throws {
        for mode in [altAz, equatorial] {
            let errors = mode == altAz ? Support.altAzimuthErrors : Support.equatorialErrors
            let rig = Support.rig(mode: mode, errors: errors, axis1Inverted: true, axis2Inverted: true)
            try rig.controller.connect()
            try aligned(rig, [Support.vega, Support.mirfak, Support.enif])
            for target in [Support.deneb, Support.altair, Support.hamal] { XCTAssertTrue(try goto(rig, target) < 0.1, "\(mode) \(target)") }
            XCTAssertTrue(worstTrackingDrift(rig, 10) < 0.03)
            let before = rig.trueJ2000()
            try rig.controller.nudge(.north, rate: .find, durationSeconds: 2.0)
            for _ in 0 ..< 4 {
                rig.clock.advance(seconds: 0.5)
                rig.controller.poll()
            }
            try rig.controller.stopNudge()
            let (eastward, northward) = skyOffset(before, rig.trueJ2000())
            XCTAssertTrue(northward > 0.1 * 1.0 * AstroMath.radians(1.0) && abs(eastward) < 0.3 * northward, "\(mode) \(eastward) \(northward)")
        }
        // A driver that does not know about the inverted axes aims the wrong way and cannot be aligned plausibly.
        let wrong = Support.rig(mode: equatorial, errors: Support.equatorialErrors,
                                configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: equatorial), axis1Inverted: true)
        try wrong.controller.connect()
        try wrong.syncOn(Support.vega)
        var rejected = false
        do {
            try wrong.syncOn(Support.mirfak)
            try wrong.syncOn(Support.enif)
        } catch let error as MountError {
            rejected = error.isRejected
        }
        XCTAssertTrue(rejected)
    }

    // MARK: Link

    func testPollingCostsAFewDatagrams() throws {
        let rig = try connected(equatorial, Support.equatorialErrors)
        try aligned(rig, equatorialAlignmentStars)
        try goto(rig, Support.deneb)
        rig.controller.poll()
        let before = rig.driver.datagramsSent
        rig.controller.poll()
        // Two positions and two statuses.
        XCTAssertEqual(rig.driver.datagramsSent - before, 4)
        let idle = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        idle.controller.poll()
        let idleBefore = idle.driver.datagramsSent
        idle.controller.poll()
        XCTAssertEqual(idle.driver.datagramsSent - idleBefore, 4)
        // A servo tick (alt-azimuth tracking) reads the position again and sets the speed of both axes: eight datagrams, and more only
        // while an axis changes its direction (stop, mode, period and start).
        let servo = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(servo, altAzimuthAlignmentStars)
        try goto(servo, Support.deneb)
        var worst = 0
        var total = 0
        for _ in 0 ..< 30 {
            servo.clock.advance(seconds: 1.0)
            let sent = servo.driver.datagramsSent
            servo.controller.poll()
            worst = max(worst, servo.driver.datagramsSent - sent)
            total += servo.driver.datagramsSent - sent
        }
        XCTAssertTrue(worst <= 20, "\(worst)")
        XCTAssertTrue(total <= 30 * 8 + 12, "\(total)")
    }

    func testALostOrGarbledReplyIsRepeated() throws {
        let rig = try connected(equatorial, Support.equatorialErrors)
        try aligned(rig, equatorialAlignmentStars)
        let faults: [(String, MountSimulatedFault)] = [
            ("j1", .silence),
            ("j2", .replace(text: "=12\r")),
            ("f1", .replace(text: "=00000G\r")),
            ("f2", .truncate(keep: 2)),
            ("j", .replace(text: "!1\r")),
            ("f", .replace(text: "!0\r")),
            ("j", .replace(text: "!3\r")),
            ("f", .replace(text: "garbage\r")),
            ("j2", .replace(text: "=\r")),
            ("f1", .replace(text: "=1234567\r")),
        ]
        for (label, fault) in faults {
            rig.simulator.inject(label, fault)
            let before = rig.driver.retries
            let timeBefore = rig.clock.secondsSince1970
            let status = rig.controller.poll()
            XCTAssertNil(status.lastError, "\(label) \(fault) \(String(describing: status.lastError))")
            XCTAssertEqual(rig.driver.retries - before, 1, "\(label) \(fault)")
            var needsTimeout = fault == .silence
            if case .truncate = fault { needsTimeout = true }
            if needsTimeout { XCTAssertTrue(rig.clock.secondsSince1970 - timeBefore >= 0.6) }
        }
        // The mount's own refusals are not repeated: !2 (not stopped) is the answer.
        rig.simulator.inject("K", .replace(text: "!2\r"))
        let retries = rig.driver.retries
        XCTAssertEqual(skyWatcherThrown { try rig.controller.abort() }, .busy)
        XCTAssertEqual(rig.driver.retries, retries)
    }

    func testAllAttemptsLostFailsThePollAndThreeFailuresEndTheSession() throws {
        let rig = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        rig.simulator.inject("j1", .silence, times: 100)
        let before = rig.clock.secondsSince1970
        let status = rig.controller.poll()
        XCTAssertTrue(status.lastError?.isTimeout == true, "\(String(describing: status.lastError))")
        XCTAssertEqual(rig.clock.secondsSince1970 - before, 1.8, accuracy: 0.3)
        rig.controller.poll()
        let ended = rig.controller.poll()
        XCTAssertEqual(ended.phase, .disconnected)
        XCTAssertEqual(ended.lastError, .connectionLost)
        let dropped = try connected(altAz)
        dropped.simulator.inject("f", .disconnect)
        let failed = dropped.controller.poll()
        XCTAssertTrue(failed.lastError?.isTransport == true, "\(String(describing: failed.lastError))")
    }

    func testALostStartReplyDoesNotStartTheMotionTwice() throws {
        let rig = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(rig, altAzimuthAlignmentStars)
        let before = rig.simulator.gotosStarted
        rig.simulator.inject("J1", .silence)
        try rig.controller.goto(Support.altair)
        // The reply to the start of axis 1 was lost, yet the axis runs: the driver looked at the status instead of sending it again.
        XCTAssertEqual(rig.simulator.gotosStarted - before, 2)
        let status = rig.controller.awaitSettled()
        XCTAssertTrue(arrived(status.outcome))
        XCTAssertTrue(rig.errorTo(Support.altair) < 0.05)
        // The same for the start of axis 2.
        let lost = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(lost, altAzimuthAlignmentStars)
        lost.simulator.inject("J2", .silence)
        try lost.controller.goto(Support.altair)
        XCTAssertTrue(arrived(lost.controller.awaitSettled().outcome))
    }

    func testALostStartReplyOfAShortGotoDoesNotRunTheAxisAway() throws {
        // The declination axis of an equatorial mount stands still while tracking. A GOTO of a few counts is over before the status is
        // read; if the reply to its start was lost, sending the start again would run the axis at its last speed.
        let rig = try connected(equatorial, SkyWatcherPointingErrors(axis1Index: 1.0))
        try aligned(rig, equatorialAlignmentStars)
        try goto(rig, Support.deneb)
        let place = rig.trueJ2000()
        let nearby = EquatorialCoordinate(rightAscension: place.rightAscension, declination: place.declination + 0.004)
        let starts = rig.simulator.speedStarts
        rig.simulator.inject("J2", .silence)
        try rig.controller.goto(nearby)
        XCTAssertTrue(arrived(rig.controller.awaitSettled().outcome))
        Support.poll(rig, seconds: 30)
        XCTAssertTrue(rig.errorTo(nearby) < 0.03, "\(rig.errorTo(nearby))")
        // Axis 2 was not started in speed mode (axis 1 resumes sidereal tracking once).
        XCTAssertEqual(rig.simulator.speedStarts - starts, 1)
    }

    func testTheWholeFlowSurvivesLostAndDamagedDatagrams() throws {
        let configuration = SkyWatcherConfiguration(location: Support.boulderLocation, mode: altAz, attempts: 6)
        let rig = Support.rig(mode: altAz, errors: Support.altAzimuthErrors, configuration: configuration) { simulator in
            simulator.requestLossProbability = 0.08
            simulator.replyLossProbability = 0.08
            simulator.garbleProbability = 0.08
        }
        try rig.controller.connect()
        try aligned(rig, altAzimuthAlignmentStars)
        for target in [Support.deneb, Support.hamal] {
            try rig.controller.goto(target)
            XCTAssertTrue(arrived(rig.controller.awaitSettled().outcome))
            XCTAssertTrue(rig.errorTo(target) < 0.1, "\(target) \(rig.errorTo(target))")
        }
        var worst = 0.0
        for _ in 0 ..< 5 {
            Support.poll(rig, seconds: 60)
            worst = max(worst, rig.errorTo(Support.hamal))
        }
        XCTAssertTrue(worst < 0.1, "\(worst)")
        let sent = rig.driver.datagramsSent
        let retries = rig.driver.retries
        XCTAssertTrue(retries > sent / 20, "\(retries) of \(sent)")
        XCTAssertTrue(retries < sent / 2, "\(retries) of \(sent)")
        XCTAssertEqual(rig.controller.poll().isTracking, true)
    }

    func testSlowAndChoppedLinksStillWork() throws {
        // A quarter of a second per reply and replies that arrive one byte at a time.
        let rig = Support.rig(mode: altAz, errors: Support.altAzimuthErrors, latencySeconds: 0.25, chunkSize: 1)
        try rig.controller.connect()
        try aligned(rig, altAzimuthAlignmentStars)
        XCTAssertTrue(try goto(rig, Support.deneb) < 0.1)
        XCTAssertTrue(worstTrackingDrift(rig, 5) < 0.05)
        XCTAssertEqual(rig.driver.retries, 0)
    }

    func testReconnectingStartsANewSession() throws {
        let rig = try connected(altAz, Support.altAzimuthErrors)
        try aligned(rig, altAzimuthAlignmentStars)
        try goto(rig, Support.deneb)
        rig.controller.disconnect()
        XCTAssertEqual(rig.controller.status.phase, .disconnected)
        XCTAssertEqual(skyWatcherThrown { try rig.driver.readPosition() }, .notConnected)
        XCTAssertEqual(skyWatcherThrown { try rig.driver.slew(to: Support.altair) }, .notConnected)
        XCTAssertEqual(skyWatcherThrown { try rig.driver.sync(to: Support.altair) }, .notConnected)
        XCTAssertEqual(skyWatcherThrown { try rig.driver.abort() }, .notConnected)
        XCTAssertEqual(skyWatcherThrown { try rig.driver.setTracking(true) }, .notConnected)
        XCTAssertEqual(skyWatcherThrown { try rig.driver.startNudge(direction: .north, rate: .guide, durationSeconds: 1.0) }, .notConnected)
        XCTAssertNil(rig.driver.pointingModel)
        let capabilities = try rig.controller.connect()
        XCTAssertEqual(capabilities.isAligned, false)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 0)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.goto(Support.altair) }, .notAligned)
        // The axes are still where they were; the new session begins from there.
        XCTAssertTrue(rig.driver.startupAxisAngles?.axis1Degrees != 0.0)
        try aligned(rig, altAzimuthAlignmentStars)
        XCTAssertTrue(try goto(rig, Support.altair) < 0.1)
    }

    func testNudgesRefuseUnusableDurations() throws {
        let rig = try connected(altAz, SkyWatcherPointingErrors(axis1Index: 1.0))
        for duration in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertTrue(skyWatcherThrown { try rig.driver.startNudge(direction: .north, rate: .guide, durationSeconds: duration) }?.isInvalidInput == true,
                          "\(duration)")
        }
        XCTAssertTrue(skyWatcherThrown { try rig.controller.nudge(.north, rate: .guide, durationSeconds: 11.0) }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try rig.controller.goto(EquatorialCoordinate(rightAscensionHours: Double.nan, declination: 10.0)) }?.isInvalidInput == true)
    }

    func testTheSimulationIsDeterministic() throws {
        func run() throws -> [Double] {
            let rig = Support.rig(mode: equatorial, errors: Support.equatorialErrors,
                                  configuration: SkyWatcherConfiguration(location: Support.boulderLocation, mode: equatorial, attempts: 6)) { simulator in
                simulator.requestLossProbability = 0.05
                simulator.replyLossProbability = 0.05
                simulator.garbleProbability = 0.05
            }
            try rig.controller.connect()
            try aligned(rig, equatorialAlignmentStars)
            try goto(rig, Support.altair)
            Support.poll(rig, seconds: 100)
            return [Double(rig.driver.datagramsSent), Double(rig.driver.retries), rig.simulator.axis1Degrees, rig.simulator.axis2Degrees,
                    rig.errorTo(Support.altair), rig.clock.secondsSince1970 - Support.start.timeIntervalSince1970.rounded(.down)]
        }
        XCTAssertEqual(try run(), try run())
    }
}
