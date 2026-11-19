import XCTest
@testable import LodestarKit

final class AlignmentHygieneTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private let mount = MountProfile.backCameraPortrait
    private let alignedAt = Date(timeIntervalSince1970: 1_800_000_000)

    /// A sample looking at the given place at `time` seconds.
    private func sample(_ time: Double, azimuth: Double = 0, altitude: Double = 30) throws -> SteadinessSample {
        try XCTUnwrap(SteadinessSample(timestamp: time, boresight: HorizontalCoordinate(azimuth: azimuth, altitude: altitude)))
    }

    /// The detector after samples every 1/8 s from `from` to `through` (both included, exact binary fractions).
    private func feed(_ detector: SteadinessDetector, from: Double, through: Double,
                      azimuth: Double = 0, altitude: Double = 30) throws -> SteadinessDetector {
        var result = detector
        var step = Int(from * 8)
        while step <= Int(through * 8) {
            result = result.adding(try sample(Double(step) / 8, azimuth: azimuth, altitude: altitude))
            step += 1
        }
        return result
    }

    /// An alignment point whose recorded target is the given place.
    private func point(azimuth: Double, altitude: Double, name: String? = nil, index: Int = 0) throws -> AlignmentPoint {
        let target = HorizontalCoordinate(azimuth: azimuth, altitude: altitude)
        let attitude = try Support.attitude(mount: mount, frame: Support.cameraFrame(boresight: target, rollDegrees: 0))
        return AlignmentPoint(attitude: attitude, target: target,
                              timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), name: name)
    }

    /// Great-circle distance in degrees from the haversine formula (Sinnott, Sky & Telescope 68, 159, 1984), which
    /// shares no code with the unit-vector angle the engine uses.
    private func haversine(_ azimuth1: Double, _ altitude1: Double, _ azimuth2: Double, _ altitude2: Double) -> Double {
        let phi1 = altitude1 * Double.pi / 180
        let phi2 = altitude2 * Double.pi / 180
        let lambda = (azimuth2 - azimuth1) * Double.pi / 180
        let a = sin((phi2 - phi1) / 2) * sin((phi2 - phi1) / 2) + cos(phi1) * cos(phi2) * sin(lambda / 2) * sin(lambda / 2)
        return 2 * asin(a.squareRoot()) * 180 / Double.pi
    }

    // MARK: Steadiness window

    func testNotEnoughHistoryIsNeverSteady() throws {
        var detector = SteadinessDetector()
        XCTAssertFalse(detector.isSteady)
        XCTAssertEqual(detector.progress, 0)
        XCTAssertEqual(detector.sampleCount, 0)
        detector = detector.adding(try sample(5))
        XCTAssertFalse(detector.isSteady)
        XCTAssertEqual(detector.progress, 0)
        XCTAssertEqual(detector.sampleCount, 1)
        // 1.375 s of samples is short of the 1.5 s window, however still the phone was.
        detector = try feed(SteadinessDetector(), from: 0, through: 1.375)
        XCTAssertFalse(detector.isSteady)
        XCTAssertEqual(detector.progress, 1.375 / 1.5, accuracy: 1e-12)
        // A longer window needs longer.
        XCTAssertFalse(try feed(SteadinessDetector(windowSeconds: 3), from: 0, through: 2.875).isSteady)
        XCTAssertTrue(try feed(SteadinessDetector(windowSeconds: 3), from: 0, through: 3).isSteady)
    }

    func testAFullWindowOfStillSamplesIsSteady() throws {
        let half = try feed(SteadinessDetector(), from: 0, through: 0.75)
        XCTAssertEqual(half.progress, 0.5, accuracy: 1e-12)
        let detector = try feed(SteadinessDetector(), from: 0, through: 1.5)
        XCTAssertTrue(detector.isSteady)
        XCTAssertEqual(detector.progress, 1)
        XCTAssertEqual(detector.sampleCount, 13)
        // And it stays so.
        XCTAssertTrue(try feed(detector, from: 1.625, through: 4).isSteady)
    }

    func testOneOutlierBreaksSteadinessUntilItLeavesTheWindow() throws {
        var detector = try feed(SteadinessDetector(), from: 0, through: 2)
        XCTAssertTrue(detector.isSteady)
        // One sample a degree off, as when the tripod is bumped.
        detector = detector.adding(try sample(2.125, altitude: 31))
        XCTAssertFalse(detector.isSteady)
        XCTAssertEqual(detector.progress, 0)
        // Back in place: the outlier is still in the window (inclusive at its start) until 3.625.
        var time = 2.25
        while time <= 3.625 {
            detector = detector.adding(try sample(time))
            XCTAssertFalse(detector.isSteady, "at \(time)")
            if time == 2.5 { XCTAssertEqual(detector.progress, 0.25 / 1.5, accuracy: 1e-12) }
            time += 0.125
        }
        // One step later it has left the window.
        detector = detector.adding(try sample(3.75))
        XCTAssertTrue(detector.isSteady)
        XCTAssertEqual(detector.progress, 1)
    }

    func testSampleExactlyAtToleranceCounts() throws {
        let still = try sample(0)
        let off = try sample(1.5, altitude: 30.35)
        // The tolerance is the angle the detector measures between the newest sample and the others.
        let tolerance = off.direction.angle(to: still.direction)
        XCTAssertEqual(tolerance, 0.35, accuracy: 1e-9)
        for (toleranceDegrees, expected) in [(tolerance, true), (tolerance.nextDown, false)] {
            var detector = SteadinessDetector(toleranceDegrees: toleranceDegrees)
            detector = try feed(detector, from: 0, through: 1.375)
            detector = detector.adding(off)
            XCTAssertEqual(detector.isSteady, expected, "tolerance \(toleranceDegrees)")
        }
    }

    func testSlowDriftWithinToleranceIsSteady() throws {
        // 0.2° per second: 0.3° across the 1.5 s window, inside the 0.35° tolerance; 0.5° per second: 0.75°.
        var slow = SteadinessDetector()
        var fast = SteadinessDetector()
        var step = 0
        while step <= 24 {
            let time = Double(step) / 8
            slow = slow.adding(try sample(time, altitude: 30 + 0.2 * time))
            fast = fast.adding(try sample(time, altitude: 30 + 0.5 * time))
            step += 1
        }
        XCTAssertTrue(slow.isSteady)
        XCTAssertFalse(fast.isSteady)
        // Only the last 0.625 s stayed within the tolerance of the newest sample (5 steps of 0.0625°).
        XCTAssertEqual(fast.progress, 0.625 / 1.5, accuracy: 1e-9)
    }

    func testAGapStartsTheWindowOver() throws {
        let steady = try feed(SteadinessDetector(), from: 0, through: 2)
        XCTAssertTrue(steady.isSteady)
        // A pause of exactly the maximum gap is not a gap.
        XCTAssertTrue(steady.adding(try sample(2.5)).isSteady)
        // A longer one is: nothing is known about the time in between.
        var detector = steady.adding(try sample(2.75))
        XCTAssertFalse(detector.isSteady)
        XCTAssertEqual(detector.progress, 0)
        XCTAssertEqual(detector.sampleCount, 1)
        detector = try feed(detector, from: 2.875, through: 4.125)
        XCTAssertFalse(detector.isSteady)
        detector = detector.adding(try sample(4.25))
        XCTAssertTrue(detector.isSteady)
    }

    func testSamplesThatAreNotLaterThanTheNewestOne() throws {
        let steady = try feed(SteadinessDetector(), from: 0, through: 2)
        // The same instant again is ignored, whatever it says.
        XCTAssertEqual(steady.adding(try sample(2, azimuth: 40, altitude: 10)), steady)
        // An earlier one means the clock restarted: start over.
        let restarted = steady.adding(try sample(1))
        XCTAssertFalse(restarted.isSteady)
        XCTAssertEqual(restarted.progress, 0)
        XCTAssertEqual(restarted.sampleCount, 1)
    }

    func testProgressFollowsTheTimeTheCameraHasBeenStill() throws {
        var detector = try feed(SteadinessDetector(), from: 0, through: 1.5)
        XCTAssertEqual(detector.progress, 1)
        // The camera is moved a degree up and held there.
        detector = try feed(detector, from: 1.625, through: 2.125, altitude: 31)
        XCTAssertFalse(detector.isSteady)
        XCTAssertEqual(detector.progress, 0.5 / 1.5, accuracy: 1e-12)
        detector = try feed(detector, from: 2.25, through: 3.125, altitude: 31)
        XCTAssertTrue(detector.isSteady)
    }

    func testTheWindowKeepsOnlyRecentSamples() throws {
        var detector = SteadinessDetector()
        for index in 0..<1000 { detector = detector.adding(try sample(Double(index) / 64)) }
        XCTAssertTrue(detector.isSteady)
        // 1.5 s at 64 Hz is 96 intervals: 97 samples, the oldest exactly at the start of the window.
        XCTAssertEqual(detector.sampleCount, 97)
    }

    func testInvalidConfigurationFallsBackToTheDefaults() {
        let defaults = SteadinessDetector()
        XCTAssertEqual(defaults.windowSeconds, 1.5)
        XCTAssertEqual(defaults.toleranceDegrees, 0.35)
        XCTAssertEqual(defaults.maximumGapSeconds, 0.5)
        for bad in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertEqual(SteadinessDetector(windowSeconds: bad, toleranceDegrees: bad, maximumGapSeconds: bad), defaults)
        }
        let custom = SteadinessDetector(windowSeconds: 2, toleranceDegrees: 0.1, maximumGapSeconds: 0.25)
        XCTAssertEqual(custom.windowSeconds, 2)
        XCTAssertEqual(custom.toleranceDegrees, 0.1)
        XCTAssertEqual(custom.maximumGapSeconds, 0.25)
    }

    // MARK: Samples

    func testInvalidSamplesAreRejected() throws {
        let direction = Vector3(0, 1, 0)
        XCTAssertNil(SteadinessSample(timestamp: .nan, direction: direction))
        XCTAssertNil(SteadinessSample(timestamp: .infinity, direction: direction))
        XCTAssertNil(SteadinessSample(timestamp: 1, direction: .zero))
        XCTAssertNil(SteadinessSample(timestamp: 1, direction: Vector3(.nan, 0, 1)))
        XCTAssertNil(SteadinessSample(timestamp: 1, direction: Vector3(0, .infinity, 1)))
        XCTAssertNil(SteadinessSample(timestamp: 1, direction: Vector3(1e200, 1e200, 1e200)))
        XCTAssertNil(SteadinessSample(timestamp: .nan, boresight: HorizontalCoordinate(azimuth: 10, altitude: 20)))
        XCTAssertNil(SteadinessSample(timestamp: 1, boresight: HorizontalCoordinate(azimuth: .nan, altitude: 20)))
        // Any length is accepted and normalised.
        let sample = try XCTUnwrap(SteadinessSample(timestamp: 1, direction: Vector3(0, 0, 5)))
        XCTAssertEqual(sample.timestamp, 1)
        Support.assertVector(sample.direction, Vector3(0, 0, 1), accuracy: 1e-15)
    }

    func testSampleFromAnAttitudeLooksAlongTheMountsCameraAxis() throws {
        let boresight = HorizontalCoordinate(azimuth: 123, altitude: 35)
        for preset in MountProfile.presets {
            let attitude = try Support.attitude(mount: preset, frame: Support.cameraFrame(boresight: boresight, rollDegrees: 0),
                                                timestamp: 42.5)
            let sample = try XCTUnwrap(SteadinessSample(attitude: attitude, mount: preset), preset.id)
            XCTAssertEqual(sample.timestamp, 42.5)
            Support.assertVector(sample.direction, boresight.unitVector, accuracy: 1e-12, preset.id)
        }
        // The same attitude seen through a mount whose camera axis is another one looks elsewhere (here 90° away).
        let attitude = try Support.attitude(mount: mount, frame: Support.cameraFrame(boresight: boresight, rollDegrees: 0))
        let other = try XCTUnwrap(SteadinessSample(attitude: attitude, mount: .flatOnTopTopEdgeForward))
        XCTAssertEqual(other.direction.angle(to: boresight.unitVector), 90, accuracy: 1e-9)
    }

    // MARK: Point separation

    func testMinimumPointSeparation() {
        XCTAssertEqual(AlignmentHygiene.minimumPointSeparationDegrees, 20)
    }

    func testNoExistingPointsMeansNoWarning() {
        let candidate = HorizontalCoordinate(azimuth: 100, altitude: 40)
        XCTAssertNil(AlignmentHygiene.bestSeparation(candidate: candidate, existing: []))
        XCTAssertNil(AlignmentHygiene.separationWarning(candidate: candidate, existing: []))
    }

    func testSeparationAcrossTheAzimuthSeam() throws {
        // 2° of azimuth apart, one on each side of north: not 358°.
        let existing = [try point(azimuth: 359, altitude: 30)]
        let expected = haversine(359, 30, 1, 30)
        XCTAssertEqual(expected, 1.7320288, accuracy: 1e-6)
        let best = try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 1, altitude: 30), existing: existing))
        XCTAssertEqual(best.degrees, expected, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(AlignmentHygiene.separationWarning(candidate: HorizontalCoordinate(azimuth: 1, altitude: 30), existing: existing)),
                       expected, accuracy: 1e-9)
        // A candidate whose azimuth is given beyond 360° is the same place.
        XCTAssertEqual(try XCTUnwrap(AlignmentHygiene.separationWarning(candidate: HorizontalCoordinate(azimuth: 361, altitude: 30), existing: existing)),
                       expected, accuracy: 1e-9)
        // 20° of azimuth at 30° altitude is only 17.3° of sky.
        let wide = try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 10, altitude: 30),
                                                                 existing: [try point(azimuth: 350, altitude: 30)]))
        XCTAssertEqual(wide.degrees, haversine(350, 30, 10, 30), accuracy: 1e-9)
        XCTAssertEqual(wide.degrees, 17.2983302, accuracy: 1e-6)
        // Opposite sides of the sky are 180° apart.
        let opposite = try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 180, altitude: 0),
                                                                     existing: [try point(azimuth: 0, altitude: 0)]))
        XCTAssertEqual(opposite.degrees, 180, accuracy: 1e-9)
        XCTAssertNil(AlignmentHygiene.separationWarning(candidate: HorizontalCoordinate(azimuth: 180, altitude: 0),
                                                        existing: [try point(azimuth: 0, altitude: 0)]))
    }

    func testSeparationNearTheZenith() throws {
        // Azimuths 180° apart at 89° altitude are 2° apart over the zenith.
        let north = [try point(azimuth: 0, altitude: 89)]
        XCTAssertEqual(try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 180, altitude: 89), existing: north)).degrees,
                       2, accuracy: 1e-9)
        let east = [try point(azimuth: 90, altitude: 89)]
        XCTAssertEqual(try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 270, altitude: 89), existing: east)).degrees,
                       2, accuracy: 1e-9)
        // At the zenith itself the azimuth means nothing: 1° from a star at 89° altitude whatever its azimuth.
        for azimuth in [0.0, 123.0, 359.9] {
            let best = AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 0, altitude: 90),
                                                       existing: [try point(azimuth: azimuth, altitude: 89)])
            XCTAssertEqual(try XCTUnwrap(best).degrees, 1, accuracy: 1e-9)
        }
        // Over the zenith from altitude 80° to altitude 80° on the far side: 20°.
        let over = AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 180, altitude: 80),
                                                   existing: [try point(azimuth: 0, altitude: 80)])
        XCTAssertEqual(try XCTUnwrap(over).degrees, 20, accuracy: 1e-9)
    }

    func testWarningOnlyBelowTheMinimum() throws {
        let existing = [try point(azimuth: 100, altitude: 40, name: "Vega")]
        // 8° above it.
        let close = HorizontalCoordinate(azimuth: 100, altitude: 48)
        XCTAssertEqual(try XCTUnwrap(AlignmentHygiene.separationWarning(candidate: close, existing: existing)), 8, accuracy: 1e-9)
        // 19.9° and 20.1° along the horizon.
        let below = [try point(azimuth: 0, altitude: 0)]
        XCTAssertEqual(try XCTUnwrap(AlignmentHygiene.separationWarning(candidate: HorizontalCoordinate(azimuth: 19.9, altitude: 0), existing: below)),
                       19.9, accuracy: 1e-9)
        XCTAssertNil(AlignmentHygiene.separationWarning(candidate: HorizontalCoordinate(azimuth: 20.1, altitude: 0), existing: below))
        // Far enough: no warning, but the nearest point and its distance are still known.
        let far = HorizontalCoordinate(azimuth: 160, altitude: 40)
        XCTAssertNil(AlignmentHygiene.separationWarning(candidate: far, existing: existing))
        let best = try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: far, existing: existing))
        XCTAssertEqual(best.degrees, haversine(100, 40, 160, 40), accuracy: 1e-9)
        XCTAssertEqual(best.degrees, 45.0420242, accuracy: 1e-6)
        XCTAssertEqual(best, AlignmentPointSeparation(degrees: best.degrees, pointIndex: 0, pointName: "Vega"))
    }

    func testBestSeparationPicksTheNearestPointAndItsName() throws {
        let existing = [
            try point(azimuth: 40, altitude: 50, name: "Vega", index: 0),
            try point(azimuth: 200, altitude: 40, name: "Arcturus", index: 1),
            try point(azimuth: 300, altitude: 20, index: 2),
        ]
        let nearArcturus = try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 190, altitude: 45), existing: existing))
        XCTAssertEqual(nearArcturus.pointIndex, 1)
        XCTAssertEqual(nearArcturus.pointName, "Arcturus")
        XCTAssertEqual(nearArcturus.degrees, haversine(190, 45, 200, 40), accuracy: 1e-9)
        XCTAssertEqual(nearArcturus.degrees, 8.8979375, accuracy: 1e-6)
        // A point without a name is reported without one.
        let nearUnnamed = try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 305, altitude: 22), existing: existing))
        XCTAssertEqual(nearUnnamed.pointIndex, 2)
        XCTAssertNil(nearUnnamed.pointName)
        XCTAssertEqual(nearUnnamed.degrees, 5.0778285, accuracy: 1e-6)
        // The warning reports the smallest separation, however far the others are.
        XCTAssertEqual(try XCTUnwrap(AlignmentHygiene.separationWarning(candidate: HorizontalCoordinate(azimuth: 305, altitude: 22), existing: existing)),
                       nearUnnamed.degrees)
        // Two points at the same place: the earlier one is reported.
        let twins = [try point(azimuth: 10, altitude: 30, name: "First"), try point(azimuth: 10, altitude: 30, name: "Second", index: 1)]
        XCTAssertEqual(try XCTUnwrap(AlignmentHygiene.bestSeparation(candidate: HorizontalCoordinate(azimuth: 12, altitude: 30), existing: twins)).pointIndex, 0)
    }

    // MARK: Staleness

    func testStaleThresholds() {
        XCTAssertEqual(AlignmentHygiene.compassStaleAfterSeconds, 10_800)
        XCTAssertEqual(AlignmentHygiene.gyroLockStaleAfterSeconds, 5_400)
        XCTAssertEqual(AlignmentHygiene.staleAfterSeconds(gyroLock: false), 10_800)
        XCTAssertEqual(AlignmentHygiene.staleAfterSeconds(gyroLock: true), 5_400)
        func stale(_ afterSeconds: Double, gyroLock: Bool) -> Bool {
            AlignmentHygiene.isStale(alignedAt: alignedAt, now: alignedAt.addingTimeInterval(afterSeconds), gyroLock: gyroLock)
        }
        // Compass: 3 hours.
        XCTAssertFalse(stale(0, gyroLock: false))
        XCTAssertFalse(stale(10_799, gyroLock: false))
        XCTAssertTrue(stale(10_800, gyroLock: false))
        XCTAssertTrue(stale(86_400, gyroLock: false))
        // Gyro lock: 90 minutes.
        XCTAssertFalse(stale(5_399, gyroLock: true))
        XCTAssertTrue(stale(5_400, gyroLock: true))
        XCTAssertTrue(stale(10_799, gyroLock: true))
        // 90 minutes old is fine for the compass.
        XCTAssertFalse(stale(5_400, gyroLock: false))
        XCTAssertFalse(stale(7_200, gyroLock: false))
    }

    func testAnAlignmentFromTheFutureIsNotStale() {
        // The clock was set back after aligning.
        XCTAssertFalse(AlignmentHygiene.isStale(alignedAt: alignedAt, now: alignedAt.addingTimeInterval(-3_600), gyroLock: true))
        XCTAssertFalse(AlignmentHygiene.isStale(alignedAt: alignedAt, now: alignedAt.addingTimeInterval(-86_400), gyroLock: false))
    }
}
