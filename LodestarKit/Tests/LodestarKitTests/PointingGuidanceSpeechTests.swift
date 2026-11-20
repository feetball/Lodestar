import XCTest
@testable import LodestarKit

final class PointingGuidanceSpeechTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// The guidance for a camera at `boresight` (azimuth 100°, altitude 20° unless given) and a target `pan` degrees of
    /// azimuth and `tilt` degrees of altitude away from it.
    private func guidance(pan: Double, tilt: Double, boresightAltitude: Double = 20,
                          threshold: Double = 0.5) throws -> Guidance {
        let boresight = HorizontalCoordinate(azimuth: 100, altitude: boresightAltitude)
        let mount = MountProfile.backCameraPortrait
        let frame = Support.cameraFrame(boresight: boresight, rollDegrees: 0)
        let solution = PointingSolution.solve(attitude: try Support.attitude(mount: mount, frame: frame), mount: mount)
        let target = HorizontalCoordinate(azimuth: AstroMath.normalizeDegrees(100 + pan), altitude: boresightAltitude + tilt)
        var tracker = GuidanceTracker(onTargetThreshold: threshold)
        return try XCTUnwrap(tracker.update(solution: solution, target: target))
    }

    private func speak(_ guidance: Guidance, previous: SpokenState? = nil, at time: Date? = nil) -> SpokenPhrase? {
        GuidanceSpeech.phrase(current: guidance, previous: previous, now: time ?? start)
    }

    private func after(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    // MARK: Wording

    func testTheFirstPhraseNamesTheUnitOnce() throws {
        let first = try XCTUnwrap(speak(try guidance(pan: 12, tilt: 3)))
        XCTAssertEqual(first.text, "Pan right 12, tilt up 3 degrees")
        XCTAssertEqual(first.state.kind, .guidance)
        XCTAssertTrue(first.state.hasSaidDegrees)
        XCTAssertEqual(first.state.pan, 12, accuracy: 1e-12)
        XCTAssertEqual(first.state.tilt, 3, accuracy: 1e-12)
        XCTAssertEqual(first.state.time, start)

        let later = try XCTUnwrap(speak(try guidance(pan: -8.4, tilt: -2.6), previous: first.state, at: after(6)))
        XCTAssertEqual(later.text, "Pan left 8, tilt down 3")
        XCTAssertTrue(later.state.hasSaidDegrees)
    }

    func testOneDegreeIsSingular() throws {
        XCTAssertEqual(speak(try guidance(pan: 12, tilt: 1.2))?.text, "Pan right 12, tilt up 1 degree")
        XCTAssertEqual(speak(try guidance(pan: -12, tilt: -1))?.text, "Pan left 12, tilt down 1 degree")
    }

    func testAComponentThatRoundsToZeroIsLeftOut() throws {
        XCTAssertEqual(speak(try guidance(pan: 12.2, tilt: 0.4))?.text, "Pan right 12 degrees")
        XCTAssertEqual(speak(try guidance(pan: 0.3, tilt: 6))?.text, "Tilt up 6 degrees")
        XCTAssertEqual(speak(try guidance(pan: -6, tilt: -0.49))?.text, "Pan left 6 degrees")
    }

    func testDegreesRoundHalfAwayFromZero() throws {
        XCTAssertEqual(speak(try guidance(pan: 12.5, tilt: -2.5))?.text, "Pan right 13, tilt down 3 degrees")
        XCTAssertEqual(speak(try guidance(pan: -12.5, tilt: 2.5))?.text, "Pan left 13, tilt up 3 degrees")
        XCTAssertEqual(speak(try guidance(pan: 12.49, tilt: 2.4))?.text, "Pan right 12, tilt up 2 degrees")
    }

    func testNearTheZenithOnlyTheTiltIsSpoken() throws {
        let g = try guidance(pan: 30, tilt: -3, boresightAltitude: 88)
        XCTAssertTrue(g.isNearZenith)
        XCTAssertEqual(speak(g)?.text, "Tilt down 3 degrees")
        // Without a tilt to make, the pan is all there is to say.
        let level = try guidance(pan: 80, tilt: 0.2, boresightAltitude: 88)
        XCTAssertTrue(level.isNearZenith)
        XCTAssertEqual(speak(level)?.text, "Pan right 80 degrees")
    }

    // MARK: Almost there, on target, below the horizon

    func testAlmostThereUnderTwoDegrees() throws {
        let g = try guidance(pan: 1, tilt: 0.5)
        XCTAssertLessThan(g.separation, GuidanceSpeech.almostThereSeparation)
        XCTAssertEqual(g.state, .close)
        let phrase = try XCTUnwrap(speak(g))
        XCTAssertEqual(phrase.text, "Almost there")
        XCTAssertEqual(phrase.state.kind, .almostThere)
        XCTAssertFalse(phrase.state.hasSaidDegrees)
    }

    func testAlmostThereIsRepeatedOnlyAfterFiveSeconds() throws {
        let g = try guidance(pan: 1, tilt: 0.5)
        let first = try XCTUnwrap(speak(g))
        XCTAssertNil(speak(g, previous: first.state, at: after(4.9)))
        XCTAssertEqual(speak(g, previous: first.state, at: after(5))?.text, "Almost there")
    }

    func testAlmostThereIsLeftOnlyBeyondThreeDegrees() throws {
        let almost = try XCTUnwrap(speak(try guidance(pan: 1, tilt: 0.5)))
        // 2.5° is beyond the limit for entering "Almost there" but within the limit for leaving it.
        XCTAssertEqual(speak(try guidance(pan: 0, tilt: 2.5))?.text, "Tilt up 3 degrees")
        XCTAssertNil(speak(try guidance(pan: 0, tilt: 2.5), previous: almost.state, at: after(1)))
        XCTAssertEqual(speak(try guidance(pan: 0, tilt: 3.5), previous: almost.state, at: after(1))?.text,
                       "Tilt up 4 degrees")
    }

    func testOnTargetIsSaidOnceThenSilence() throws {
        let g = try guidance(pan: 0, tilt: 0)
        XCTAssertEqual(g.state, .onTarget)
        let phrase = try XCTUnwrap(speak(g))
        XCTAssertEqual(phrase.text, "On target")
        XCTAssertEqual(phrase.state.kind, .onTarget)
        XCTAssertNil(speak(g, previous: phrase.state, at: after(1)))
        XCTAssertNil(speak(g, previous: phrase.state, at: after(600)))
    }

    func testDriftingOffTargetIsSpokenAtOnce() throws {
        let onTarget = try XCTUnwrap(speak(try guidance(pan: 0, tilt: 0)))
        let drifted = try XCTUnwrap(speak(try guidance(pan: 5, tilt: 0), previous: onTarget.state, at: after(0.1)))
        XCTAssertEqual(drifted.text, "Pan right 5 degrees")
        // Then it is on target again, which is worth saying again.
        let again = try XCTUnwrap(speak(try guidance(pan: 0, tilt: 0), previous: drifted.state, at: after(2)))
        XCTAssertEqual(again.text, "On target")
    }

    func testBelowTheHorizonIsSaidOnceAndNothingElse() throws {
        let g = try guidance(pan: 20, tilt: -25)
        XCTAssertTrue(g.targetBelowHorizon)
        let phrase = try XCTUnwrap(speak(g))
        XCTAssertEqual(phrase.text, "Target is below the horizon")
        XCTAssertEqual(phrase.state.kind, .belowHorizon)
        XCTAssertNil(speak(g, previous: phrase.state, at: after(1)))
        XCTAssertNil(speak(g, previous: phrase.state, at: after(600)))
        // Once it has risen, the guidance is spoken at once.
        XCTAssertEqual(speak(try guidance(pan: 20, tilt: -10), previous: phrase.state, at: after(601))?.text,
                       "Pan right 20, tilt down 10 degrees")
    }

    func testBelowTheHorizonComesBeforeOnTarget() throws {
        let boresight = try guidance(pan: 0, tilt: 0, boresightAltitude: -5)
        XCTAssertEqual(boresight.state, .onTarget)
        XCTAssertEqual(speak(boresight)?.text, "Target is below the horizon")
    }

    // MARK: Repeating

    func testSmallChangesAreNotRepeatedBeforeFiveSeconds() throws {
        let first = try XCTUnwrap(speak(try guidance(pan: 12, tilt: 3)))
        XCTAssertNil(speak(try guidance(pan: 12, tilt: 3), previous: first.state, at: after(1)))
        XCTAssertNil(speak(try guidance(pan: 12.9, tilt: 3.5), previous: first.state, at: after(2)))
        XCTAssertNil(speak(try guidance(pan: 11.1, tilt: 2.2), previous: first.state, at: after(4.9)))
    }

    func testAChangeOfOneDegreeIsRepeated() throws {
        let first = try XCTUnwrap(speak(try guidance(pan: 12, tilt: 3)))
        XCTAssertEqual(speak(try guidance(pan: 13, tilt: 3), previous: first.state, at: after(1))?.text,
                       "Pan right 13, tilt up 3")
        XCTAssertEqual(speak(try guidance(pan: 12, tilt: 4), previous: first.state, at: after(1))?.text,
                       "Pan right 12, tilt up 4")
        XCTAssertEqual(speak(try guidance(pan: 11, tilt: 3), previous: first.state, at: after(1))?.text,
                       "Pan right 11, tilt up 3")
    }

    func testChangesAreCountedFromTheLastPhraseSpoken() throws {
        let first = try XCTUnwrap(speak(try guidance(pan: 12, tilt: 3)))
        // Drifting by 0.6° twice is a change of 1.2° from what was said.
        XCTAssertNil(speak(try guidance(pan: 12.6, tilt: 3), previous: first.state, at: after(1)))
        XCTAssertNotNil(speak(try guidance(pan: 13.2, tilt: 3), previous: first.state, at: after(2)))
    }

    func testUnchangedGuidanceIsRepeatedAfterFiveSeconds() throws {
        let first = try XCTUnwrap(speak(try guidance(pan: 12, tilt: 3)))
        XCTAssertNil(speak(try guidance(pan: 12, tilt: 3), previous: first.state, at: after(4.9)))
        let repeated = try XCTUnwrap(speak(try guidance(pan: 12, tilt: 3), previous: first.state, at: after(5)))
        XCTAssertEqual(repeated.text, "Pan right 12, tilt up 3")
        XCTAssertEqual(repeated.state.time, after(5))
    }

    func testThePanChangeTakesTheShortWayRoundTheCircle() throws {
        // 179.5° and −179.8° are 0.7° apart.
        let first = try XCTUnwrap(speak(try guidance(pan: 179.5, tilt: 0)))
        XCTAssertEqual(first.text, "Pan right 180 degrees")
        XCTAssertNil(speak(try guidance(pan: 180.2, tilt: 0), previous: first.state, at: after(1)))
        XCTAssertEqual(speak(try guidance(pan: 181, tilt: 0), previous: first.state, at: after(1))?.text, "Pan left 179")
    }

    func testAClockThatWentBackwardsRepeats() throws {
        let first = try XCTUnwrap(speak(try guidance(pan: 12, tilt: 3), at: after(100)))
        XCTAssertNotNil(speak(try guidance(pan: 12, tilt: 3), previous: first.state, at: start))
    }

    func testChangesOfPanAreIgnoredWhereOnlyTheTiltIsSpoken() throws {
        let first = try XCTUnwrap(speak(try guidance(pan: 30, tilt: -3, boresightAltitude: 88)))
        let swung = try guidance(pan: 45, tilt: -3, boresightAltitude: 88)
        XCTAssertNil(speak(swung, previous: first.state, at: after(1)))
    }

    // MARK: A session

    func testASessionFromFarToOnTarget() throws {
        let steps: [(guidance: Guidance, seconds: Double, expected: String?)] = [
            (try guidance(pan: 40, tilt: 15), 0, "Pan right 40, tilt up 15 degrees"),
            (try guidance(pan: 39.5, tilt: 14.8), 0.5, nil),
            (try guidance(pan: 25, tilt: 9), 1, "Pan right 25, tilt up 9"),
            (try guidance(pan: 24.7, tilt: 8.9), 1.5, nil),
            (try guidance(pan: 6, tilt: 2), 3, "Pan right 6, tilt up 2"),
            (try guidance(pan: 1.2, tilt: 0.4), 4, "Almost there"),
            (try guidance(pan: 1, tilt: 0.3), 6, nil),
            (try guidance(pan: 0, tilt: 0), 7, "On target"),
            (try guidance(pan: 0, tilt: 0), 9, nil),
            (try guidance(pan: 0.2, tilt: -0.1), 20, nil),
            (try guidance(pan: -5, tilt: 1), 21, "Pan left 5, tilt up 1"),
            (try guidance(pan: -0.2, tilt: 0), 23, "On target"),
        ]
        var state: SpokenState?
        for step in steps {
            let phrase = speak(step.guidance, previous: state, at: after(step.seconds))
            XCTAssertEqual(phrase?.text, step.expected, "at \(step.seconds) s")
            if let phrase { state = phrase.state }
        }
    }
}
