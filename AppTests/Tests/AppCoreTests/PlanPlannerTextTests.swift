import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The words and numbers of the star-trail and time-lapse results.
final class PlanPlannerTextTests: XCTestCase {
    /// An error that neither planner throws.
    private struct OtherError: Error {}

    /// Number formats that follow the person's region (pixels, seconds, storage, counts) are only asserted in a region
    /// that writes "1,234.5".
    private func requireEnglishNumberFormat() throws {
        let locale = Locale.autoupdatingCurrent
        try XCTSkipUnless(locale.decimalSeparator == "." && locale.groupingSeparator == ",",
                          "These numbers follow the user's regional format.")
    }

    // MARK: Constants and fixed text

    func testAGapAboveTwoPixelsShowsAsABreak() {
        XCTAssertEqual(ToolsPlannerText.visibleGapPixels, 2)
    }

    func testTheRateNoteNamesTheSiderealRate() {
        XCTAssertEqual(ToolsPlannerText.rateNote,
                       "Stars turn about the celestial pole at 15.041\u{00B0} an hour, the same for every star. "
                       + "A star at declination \u{03B4} draws an arc of that angle \u{00D7} cos \u{03B4} along its circle, "
                       + "so trails shorten towards the pole.")
    }

    func testDegreesUseOneDecimalByDefaultAndThePinnedFormat() {
        XCTAssertEqual(ToolsPlannerText.degrees(15), "15.0\u{00B0}")
        XCTAssertEqual(ToolsPlannerText.degrees(15.041, decimals: 3), "15.041\u{00B0}")
        XCTAssertEqual(ToolsPlannerText.degrees(0, decimals: 0), "0\u{00B0}")
        XCTAssertEqual(ToolsPlannerText.degrees(-12.34), "\u{2212}12.3\u{00B0}")
        XCTAssertEqual(ToolsPlannerText.degrees(.nan), "\u{2014}")
    }

    func testBatteryDemandsHaveTheirOwnWords() {
        XCTAssertEqual(ToolsPlannerText.battery(.light), "Light")
        XCTAssertEqual(ToolsPlannerText.battery(.moderate), "Moderate")
        XCTAssertEqual(ToolsPlannerText.battery(.heavy), "Heavy")
        XCTAssertEqual(ToolsPlannerText.battery(.veryHeavy), "Very heavy")
    }

    func testBatteryWordsCoverEveryDemand() {
        XCTAssertEqual(Set(BatteryDemand.allCases.map { ToolsPlannerText.battery($0) }).count, BatteryDemand.allCases.count)
    }

    // MARK: Pixels

    func testPixelsThatAreNotNumbersShowAsMissing() {
        XCTAssertEqual(ToolsPlannerText.pixels(.nan), "\u{2014}")
        XCTAssertEqual(ToolsPlannerText.pixels(.infinity), "\u{2014}")
        XCTAssertEqual(ToolsPlannerText.pixels(-.infinity), "\u{2014}")
    }

    func testPixelsBelowTenHaveOneDecimal() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.pixels(0), "0.0 px")
        XCTAssertEqual(ToolsPlannerText.pixels(0.8), "0.8 px")
        XCTAssertEqual(ToolsPlannerText.pixels(9.94), "9.9 px")
        XCTAssertEqual(ToolsPlannerText.pixels(5), "5.0 px")
    }

    func testPixelsFromTenAreWholeNumbers() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.pixels(10), "10 px")
        XCTAssertEqual(ToolsPlannerText.pixels(12.4), "12 px")
        XCTAssertEqual(ToolsPlannerText.pixels(12.6), "13 px")
        XCTAssertEqual(ToolsPlannerText.pixels(999), "999 px")
    }

    func testLargePixelCountsHaveAThousandsSeparator() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.pixels(1240), "1,240 px")
        XCTAssertEqual(ToolsPlannerText.pixels(1_234_567), "1,234,567 px")
    }

    // MARK: Seconds

    func testSecondsDropAnUnneededDecimal() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.seconds(1), "1 s")
        XCTAssertEqual(ToolsPlannerText.seconds(0), "0 s")
        XCTAssertEqual(ToolsPlannerText.seconds(2.5), "2.5 s")
        XCTAssertEqual(ToolsPlannerText.seconds(30), "30 s")
    }

    func testSecondsKeepAtMostTheRequestedDecimals() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.seconds(2.25, maximumDigits: 2), "2.25 s")
        XCTAssertEqual(ToolsPlannerText.seconds(3, maximumDigits: 2), "3 s")
        XCTAssertEqual(ToolsPlannerText.seconds(2.5, maximumDigits: 2), "2.5 s")
        XCTAssertEqual(ToolsPlannerText.seconds(2.25, maximumDigits: 0), "2 s")
    }

    // MARK: Storage

    func testStorageBelowAGigabyteIsInWholeMegabytes() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 0), "0 MB")
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 600), "600 MB")
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 999), "999 MB")
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 12.4), "12 MB")
    }

    func testStorageFromAGigabyteIsInGigabytesWithAtMostOneDecimal() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 1000), "1 GB")
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 9000), "9 GB")
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 9500), "9.5 GB")
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 1234), "1.2 GB")
        XCTAssertEqual(ToolsPlannerText.storage(megabytes: 100_000), "100 GB")
    }

    // MARK: Counts

    func testCountsHaveAThousandsSeparator() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.count(0), "0")
        XCTAssertEqual(ToolsPlannerText.count(999), "999")
        XCTAssertEqual(ToolsPlannerText.count(1000), "1,000")
        XCTAssertEqual(ToolsPlannerText.count(100_000), "100,000")
    }

    // MARK: Gap verdict

    func testAGapOfMoreThanTwoPixelsWarnsOfBreaks() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.gapVerdict(pixels: 3),
                       "The stars move 3.0 px between frames, so the stacked trails show breaks. Shorten the gap if you "
                       + "can; stacking software can also bridge small gaps.")
    }

    func testAGapOfTwoPixelsOrLessLooksUnbroken() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.gapVerdict(pixels: 2),
                       "The stars move only 2.0 px between frames, so the stacked trails look unbroken.")
        XCTAssertEqual(ToolsPlannerText.gapVerdict(pixels: 0.5),
                       "The stars move only 0.5 px between frames, so the stacked trails look unbroken.")
    }

    func testTheVerdictSwitchesJustAboveTwoPixels() {
        XCTAssertTrue(ToolsPlannerText.gapVerdict(pixels: 2.0001).hasSuffix("stacking software can also bridge small gaps."))
        XCTAssertTrue(ToolsPlannerText.gapVerdict(pixels: 2).hasSuffix("look unbroken."))
        XCTAssertTrue(ToolsPlannerText.gapVerdict(pixels: 0).hasSuffix("look unbroken."))
    }

    // MARK: Star-trail errors

    func testStarTrailErrorsExplainThemselves() {
        let cases: [(StarTrailError, String)] = [
            (.invalidDuration(seconds: 0), "The time must be longer than zero and at most 24 hours."),
            (.invalidDeclination(degrees: 95), "The declination must be between \u{2212}90\u{00B0} and +90\u{00B0}."),
            (.invalidArc(value: 0), "The trail length must be more than zero (an arc of up to 360\u{00B0})."),
            (.noMotionAtThePole,
             "A star exactly at a celestial pole does not move, so it never draws a trail. Choose a declination away "
             + "from \u{00B1}90\u{00B0}."),
            (.invalidExposure(seconds: 0), "The frame length must be between 0.1 seconds and one hour."),
            (.invalidGap(seconds: 99), "The gap between frames must be between 0 and 60 seconds."),
            (.invalidFrame(horizontal: 0, vertical: 0), "The picture size is not usable."),
        ]
        for (error, expected) in cases {
            XCTAssertEqual(ToolsPlannerText.message(for: error), expected, "\(error)")
        }
    }

    func testATrailThatTakesTooLongNamesTheTimeItWouldTake() {
        // 90,000 seconds is 25 hours exactly; the duration formatter pins its own style.
        XCTAssertEqual(ToolsPlannerText.message(for: StarTrailError.durationTooLong(seconds: 90_000)),
                       "That trail takes 25h 00m at this declination, more than 24 hours. Choose a shorter trail or a "
                       + "declination farther from the pole.")
        XCTAssertTrue(ToolsPlannerText.message(for: StarTrailError.durationTooLong(seconds: 100_000))
            .hasPrefix("That trail takes 27h 47m at this declination"))
    }

    func testAStackWithTooManyFramesNamesTheCountAndTheLimit() throws {
        try requireEnglishNumberFormat()
        XCTAssertEqual(ToolsPlannerText.message(for: StarTrailError.tooManyFrames(count: 250_000, limit: 100_000)),
                       "This stack needs 250,000 frames, more than the 100,000 Lodestar plans. Use a longer frame "
                       + "length, a shorter total time or a longer gap.")
    }

    func testAnErrorThatIsNotAStarTrailErrorGetsAGenericMessage() {
        let generic = "The plan could not be worked out."
        XCTAssertEqual(ToolsPlannerText.message(for: OtherError()), generic)
        XCTAssertEqual(ToolsPlannerText.message(for: TimeLapseError.invalidInterval(seconds: 0)), generic)
    }

    func testTheRealPlannerErrorsReachTheirMessages() {
        XCTAssertThrowsError(try StarTrailPlanner.duration(forArcDegrees: 0, declination: 0)) { error in
            XCTAssertEqual(ToolsPlannerText.message(for: error),
                           "The trail length must be more than zero (an arc of up to 360\u{00B0}).")
        }
        XCTAssertThrowsError(try StarTrailPlanner.duration(forArcDegrees: 10, declination: 90)) { error in
            XCTAssertEqual(error as? StarTrailError, .noMotionAtThePole)
            XCTAssertTrue(ToolsPlannerText.message(for: error).hasPrefix("A star exactly at a celestial pole"))
        }
        XCTAssertThrowsError(try StarTrailPlanner.duration(forArcDegrees: 360, declination: 89.999)) { error in
            XCTAssertTrue(ToolsPlannerText.message(for: error).hasPrefix("That trail takes "))
            XCTAssertTrue(ToolsPlannerText.message(for: error).contains("more than 24 hours."))
        }
    }

    // MARK: Time-lapse errors

    func testTimeLapseErrorsExplainThemselvesWithoutASuggestion() {
        let cases: [(TimeLapseError, String)] = [
            (.invalidInterval(seconds: 0), "The interval must be longer than zero and at most one hour."),
            (.invalidExposure(seconds: 0), "The exposure must be longer than zero and at most one hour."),
            (.invalidFrameRate(framesPerSecond: 0),
             "The playback frame rate must be more than zero and at most 240 frames per second."),
            (.invalidTarget(value: 0), "That gives less than one picture. Make the clip or the shooting time longer."),
            (.invalidMinimumGap(seconds: 99),
             "The time the camera needs to save a picture must be between 0 and 60 seconds."),
            (.invalidFrameSize(megabytes: 0), "The size of a picture must be more than zero and at most 10,000 MB."),
        ]
        for (error, expected) in cases {
            let failure = ToolsPlannerText.failure(for: error)
            XCTAssertEqual(failure.message, expected, "\(error)")
            XCTAssertNil(failure.suggestedInterval, "\(error)")
        }
    }

    func testAnExposureLongerThanTheIntervalSuggestsTheShortestWorkingInterval() throws {
        try requireEnglishNumberFormat()
        // Interval 10 s, exposure 12 s: the gap is -2 s; the camera needs 1 s, so 13 s is the shortest interval.
        let failure = ToolsPlannerText.failure(for: TimeLapseError.gapTooShort(
            gapSeconds: -2, minimumGapSeconds: 1, minimumIntervalSeconds: 13))
        XCTAssertEqual(failure.message,
                       "The exposure is longer than the interval, so the next picture would start before this one ends. "
                       + "Use an interval of at least 13 s, or shorten the exposure.")
        XCTAssertEqual(failure.suggestedInterval, 13)
    }

    func testAGapShorterThanTheWriteTimeNamesTheGapAndTheWriteTime() throws {
        try requireEnglishNumberFormat()
        let failure = ToolsPlannerText.failure(for: TimeLapseError.gapTooShort(
            gapSeconds: 0, minimumGapSeconds: 1, minimumIntervalSeconds: 11))
        XCTAssertEqual(failure.message,
                       "Only 0 s is left between the end of one exposure and the start of the next (interval minus "
                       + "exposure). The camera needs 1 s to save each picture, or it skips frames. Use an interval of at "
                       + "least 11 s, or shorten the exposure.")
        XCTAssertEqual(failure.suggestedInterval, 11)
    }

    func testAGapWithDecimalsKeepsUpToTwoOfThem() throws {
        try requireEnglishNumberFormat()
        let failure = ToolsPlannerText.failure(for: TimeLapseError.gapTooShort(
            gapSeconds: 0.25, minimumGapSeconds: 1.5, minimumIntervalSeconds: 11.5))
        XCTAssertEqual(failure.message,
                       "Only 0.25 s is left between the end of one exposure and the start of the next (interval minus "
                       + "exposure). The camera needs 1.5 s to save each picture, or it skips frames. Use an interval of "
                       + "at least 11.5 s, or shorten the exposure.")
        XCTAssertEqual(failure.suggestedInterval, 11.5)
    }

    func testAGapOfExactlyZeroIsNotTreatedAsAnOverlap() {
        let failure = ToolsPlannerText.failure(for: TimeLapseError.gapTooShort(
            gapSeconds: 0, minimumGapSeconds: 1, minimumIntervalSeconds: 11))
        XCTAssertTrue(failure.message.hasPrefix("Only "))
        let overlap = ToolsPlannerText.failure(for: TimeLapseError.gapTooShort(
            gapSeconds: -0.001, minimumGapSeconds: 1, minimumIntervalSeconds: 11))
        XCTAssertTrue(overlap.message.hasPrefix("The exposure is longer than the interval"))
    }

    func testTooManyPicturesNamesTheCountAndTheLimit() throws {
        try requireEnglishNumberFormat()
        let failure = ToolsPlannerText.failure(for: TimeLapseError.tooManyFrames(count: 250_000, limit: 100_000))
        XCTAssertEqual(failure.message,
                       "This time-lapse needs 250,000 pictures, more than the 100,000 Lodestar plans. Make the clip or "
                       + "the shooting time shorter, or the interval longer.")
        XCTAssertNil(failure.suggestedInterval)
    }

    func testAnErrorThatIsNotATimeLapseErrorGetsAGenericFailure() {
        let generic = "The plan could not be worked out."
        let other = ToolsPlannerText.failure(for: OtherError())
        XCTAssertEqual(other.message, generic)
        XCTAssertNil(other.suggestedInterval)
        let starTrail = ToolsPlannerText.failure(for: StarTrailError.noMotionAtThePole)
        XCTAssertEqual(starTrail.message, generic)
        XCTAssertNil(starTrail.suggestedInterval)
    }

    func testTheRealTimeLapseErrorsSuggestWorkingIntervals() throws {
        try requireEnglishNumberFormat()
        // Exposure and interval equal: no gap at all, so the camera's 1 s write time needs an interval of 11 s.
        XCTAssertThrowsError(try TimeLapsePlanner.plan(interval: 10, exposure: 10, frameRate: 24,
                                                       target: .clipLength(seconds: 10))) { error in
            let failure = ToolsPlannerText.failure(for: error)
            XCTAssertEqual(failure.suggestedInterval, 11)
            XCTAssertTrue(failure.message.hasPrefix("Only 0 s is left between"))
        }
        // Exposure longer than the interval.
        XCTAssertThrowsError(try TimeLapsePlanner.plan(interval: 10, exposure: 12, frameRate: 24,
                                                       target: .clipLength(seconds: 10))) { error in
            let failure = ToolsPlannerText.failure(for: error)
            XCTAssertEqual(failure.suggestedInterval, 13)
            XCTAssertTrue(failure.message.hasPrefix("The exposure is longer than the interval"))
            XCTAssertTrue(failure.message.contains("at least 13 s"))
        }
        // A slower write time asks for a longer interval.
        XCTAssertThrowsError(try TimeLapsePlanner.plan(interval: 12, exposure: 10, frameRate: 24,
                                                       target: .clipLength(seconds: 10), minimumGapSeconds: 5)) { error in
            let failure = ToolsPlannerText.failure(for: error)
            XCTAssertEqual(failure.suggestedInterval, 15)
            XCTAssertTrue(failure.message.hasPrefix("Only 2 s is left between"))
            XCTAssertTrue(failure.message.contains("The camera needs 5 s to save each picture"))
        }
    }

    func testRealPlannerErrorsForBadValuesHaveNoSuggestion() {
        XCTAssertThrowsError(try TimeLapsePlanner.plan(interval: 0, exposure: 1, frameRate: 24,
                                                       target: .clipLength(seconds: 10))) { error in
            XCTAssertEqual(ToolsPlannerText.failure(for: error).message,
                           "The interval must be longer than zero and at most one hour.")
            XCTAssertNil(ToolsPlannerText.failure(for: error).suggestedInterval)
        }
        XCTAssertThrowsError(try TimeLapsePlanner.plan(interval: 5, exposure: 1, frameRate: 24,
                                                       target: .frameCount(frames: 0))) { error in
            XCTAssertEqual(ToolsPlannerText.failure(for: error).message,
                           "That gives less than one picture. Make the clip or the shooting time longer.")
        }
    }
}
