import Foundation
import XCTest
@testable import AppCore

/// `FeedbackTone`, `FeedbackTickSchedule` and `FeedbackSynthesizer`: how the distance to the target sounds.
final class SettingsFeedbackToneTests: XCTestCase {
    // MARK: Constants

    func testTheDocumentedEndpointsAreTheConstants() {
        XCTAssertEqual(FeedbackTone.farSeparation, 60)
        XCTAssertEqual(FeedbackTone.nearSeparation, 0.5)
        XCTAssertEqual(FeedbackTone.slowestInterval, 1.2)
        XCTAssertEqual(FeedbackTone.fastestInterval, 0.08)
        XCTAssertEqual(FeedbackTone.lowestFrequency, 440)
        XCTAssertEqual(FeedbackTone.highestFrequency, 1320)
        XCTAssertEqual(FeedbackTone.pitchCount, 48)
    }

    // MARK: The tone for a separation

    func testOnTargetIsTheFastestAndHighestTone() {
        let tone = FeedbackTone(separation: 0.5)
        XCTAssertEqual(tone.interval, 0.08, accuracy: 1e-12)
        XCTAssertEqual(tone.pitchIndex, 47)
    }

    func testFarAwayIsTheSlowestAndLowestTone() {
        let tone = FeedbackTone(separation: 60)
        XCTAssertEqual(tone.interval, 1.2, accuracy: 1e-9)
        XCTAssertEqual(tone.pitchIndex, 0)
    }

    func testSeparationsBeyondTheEndpointsAreClamped() {
        XCTAssertEqual(FeedbackTone(separation: 0), FeedbackTone(separation: 0.5))
        XCTAssertEqual(FeedbackTone(separation: 0.01), FeedbackTone(separation: 0.5))
        XCTAssertEqual(FeedbackTone(separation: -20), FeedbackTone(separation: 0.5))
        XCTAssertEqual(FeedbackTone(separation: 120), FeedbackTone(separation: 60))
        XCTAssertEqual(FeedbackTone(separation: 180), FeedbackTone(separation: 60))
    }

    func testAnInvalidSeparationSoundsLikeFar() {
        XCTAssertEqual(FeedbackTone(separation: .nan), FeedbackTone(separation: 60))
        XCTAssertEqual(FeedbackTone(separation: .infinity), FeedbackTone(separation: 60))
        XCTAssertEqual(FeedbackTone(separation: -.infinity), FeedbackTone(separation: 60))
        XCTAssertEqual(FeedbackTone(separation: .nan).pitchIndex, 0)
    }

    func testIntermediateSeparationsFollowTheGeometricScale() {
        let one = FeedbackTone(separation: 1)
        XCTAssertEqual(one.interval, 0.118404, accuracy: 1e-5)
        XCTAssertEqual(one.pitchIndex, 40)
        let ten = FeedbackTone(separation: 10)
        XCTAssertEqual(ten.interval, 0.435531, accuracy: 1e-5)
        XCTAssertEqual(ten.pitchIndex, 18)
        let thirty = FeedbackTone(separation: 30)
        XCTAssertEqual(thirty.interval, 0.810780, accuracy: 1e-5)
        XCTAssertEqual(thirty.pitchIndex, 7)
    }

    func testEveryHalvingOfTheDistanceIsTheSameStep() {
        let ladder = [0.5, 1, 2, 4, 8, 16, 32].map { FeedbackTone(separation: $0).interval }
        let ratios = zip(ladder.dropFirst(), ladder).map { $0 / $1 }
        for ratio in ratios {
            XCTAssertEqual(ratio, ratios[0], accuracy: 1e-9)
            XCTAssertGreaterThan(ratio, 1)
        }
        let pitches = [0.5, 1, 2, 4, 8, 16, 32].map { Double(FeedbackTone(separation: $0).pitchIndex) }
        let steps = zip(pitches, pitches.dropFirst()).map { $0 - $1 }
        for step in steps {
            XCTAssertEqual(step, 6.8, accuracy: 1.0)
        }
    }

    func testTheCloserTheFasterAndTheHigher() {
        let separations = [0.5, 0.8, 1, 2, 3, 5, 10, 20, 30, 45, 60]
        let tones = separations.map { FeedbackTone(separation: $0) }
        for (nearer, farther) in zip(tones, tones.dropFirst()) {
            XCTAssertLessThan(nearer.interval, farther.interval)
            XCTAssertGreaterThanOrEqual(nearer.pitchIndex, farther.pitchIndex)
        }
    }

    func testEveryToneStaysInsideItsRanges() {
        for index in 0...1000 {
            let separation = Double(index) * 0.1
            let tone = FeedbackTone(separation: separation)
            XCTAssertGreaterThanOrEqual(tone.interval, 0.08 - 1e-12)
            XCTAssertLessThanOrEqual(tone.interval, 1.2 + 1e-9)
            XCTAssertTrue((0...47).contains(tone.pitchIndex), "pitch \(tone.pitchIndex) for \(separation)")
        }
    }

    // MARK: Pitch frequencies

    func testThePitchRangeSpansTheLowestToTheHighestFrequency() {
        XCTAssertEqual(FeedbackTone.frequency(ofPitch: 0), 440, accuracy: 1e-9)
        XCTAssertEqual(FeedbackTone.frequency(ofPitch: 47), 1320, accuracy: 1e-9)
    }

    func testPitchesRiseByAConstantRatio() {
        let frequencies = (0..<48).map { FeedbackTone.frequency(ofPitch: $0) }
        let ratio = frequencies[1] / frequencies[0]
        XCTAssertEqual(ratio, pow(3.0, 1.0 / 47.0), accuracy: 1e-12)
        for (lower, higher) in zip(frequencies, frequencies.dropFirst()) {
            XCTAssertEqual(higher / lower, ratio, accuracy: 1e-9)
        }
        XCTAssertEqual(FeedbackTone.frequency(ofPitch: 24), 771.0616, accuracy: 1e-3)
    }

    func testPitchIndicesOutsideTheRangeAreClamped() {
        XCTAssertEqual(FeedbackTone.frequency(ofPitch: -5), 440, accuracy: 1e-9)
        XCTAssertEqual(FeedbackTone.frequency(ofPitch: Int.min), 440, accuracy: 1e-9)
        XCTAssertEqual(FeedbackTone.frequency(ofPitch: 48), 1320, accuracy: 1e-9)
        XCTAssertEqual(FeedbackTone.frequency(ofPitch: 1_000), 1320, accuracy: 1e-9)
    }

    // MARK: The tick schedule

    private func assertTick(_ action: FeedbackTickSchedule.Action, pitch: Int, wait: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case let .tick(pitchIndex, actualWait) = action else {
            return XCTFail("expected a tick, got \(action)", file: file, line: line)
        }
        XCTAssertEqual(pitchIndex, pitch, file: file, line: line)
        XCTAssertEqual(actualWait, wait, accuracy: 1e-9, file: file, line: line)
    }

    private func assertWait(_ action: FeedbackTickSchedule.Action, _ seconds: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case let .wait(actual) = action else {
            return XCTFail("expected a wait, got \(action)", file: file, line: line)
        }
        XCTAssertEqual(actual, seconds, accuracy: 1e-9, file: file, line: line)
    }

    private func report(_ degrees: Double, at time: Double) -> FeedbackTickSchedule.Report {
        FeedbackTickSchedule.Report(degrees: degrees, time: time)
    }

    func testTheScheduleLimitsAreTheDocumentedOnes() {
        XCTAssertEqual(FeedbackTickSchedule.reportTimeout, 0.75)
        XCTAssertEqual(FeedbackTickSchedule.maximumWait, 0.1)
    }

    func testTheFirstFreshReportTicksAtOnce() {
        var schedule = FeedbackTickSchedule()
        let action = schedule.next(now: 10, report: report(0.5, at: 10), chimeEndsAt: nil)
        assertTick(action, pitch: 47, wait: 0.08)
    }

    func testTheWaitBetweenDecisionsIsCappedAtTheMaximum() {
        var schedule = FeedbackTickSchedule()
        let action = schedule.next(now: 0, report: report(60, at: 0), chimeEndsAt: nil)
        assertTick(action, pitch: 0, wait: 0.1)
    }

    func testTheNextTickWaitsForTheRestOfTheIntervalOfTheLatestReport() {
        var schedule = FeedbackTickSchedule()
        _ = schedule.next(now: 10, report: report(0.5, at: 10), chimeEndsAt: nil)
        // Interval 0.08: 0.03 s after the tick, 0.05 s are left.
        assertWait(schedule.next(now: 10.03, report: report(0.5, at: 10.03), chimeEndsAt: nil), 0.05)
        // After the interval has passed the tick is due.
        assertTick(schedule.next(now: 10.1, report: report(0.5, at: 10.1), chimeEndsAt: nil), pitch: 47, wait: 0.08)
    }

    func testAFarTargetWaitsInSlicesOfTheMaximumWait() {
        var schedule = FeedbackTickSchedule()
        _ = schedule.next(now: 0, report: report(60, at: 0), chimeEndsAt: nil)
        // 1.2 s interval, 0.5 s in: 0.7 s left, but the schedule asks again after 0.1 s.
        assertWait(schedule.next(now: 0.5, report: report(60, at: 0.4), chimeEndsAt: nil), 0.1)
        // Only 0.05 s left: wait just that.
        assertWait(schedule.next(now: 1.15, report: report(60, at: 1.1), chimeEndsAt: nil), 0.05)
        assertTick(schedule.next(now: 1.2000001, report: report(60, at: 1.2), chimeEndsAt: nil), pitch: 0, wait: 0.1)
    }

    func testApproachingTheTargetSpeedsTheRhythmUpAtOnce() {
        var schedule = FeedbackTickSchedule()
        // A slow tick while far away.
        assertTick(schedule.next(now: 0, report: report(60, at: 0), chimeEndsAt: nil), pitch: 0, wait: 0.1)
        // 0.2 s later the target is nearly centered: the old 1.2 s interval is not waited out.
        assertTick(schedule.next(now: 0.2, report: report(0.5, at: 0.2), chimeEndsAt: nil), pitch: 47, wait: 0.08)
    }

    func testMovingAwayFromTheTargetSlowsTheRhythmDown() {
        var schedule = FeedbackTickSchedule()
        assertTick(schedule.next(now: 0, report: report(0.5, at: 0), chimeEndsAt: nil), pitch: 47, wait: 0.08)
        // The next tick was due at 0.08 s, but the new separation needs 1.2 s.
        assertWait(schedule.next(now: 0.2, report: report(60, at: 0.2), chimeEndsAt: nil), 0.1)
    }

    func testAReportExactlyAtTheTimeoutIsStillFresh() {
        var schedule = FeedbackTickSchedule()
        let action = schedule.next(now: 1.0, report: report(0.5, at: 0.25), chimeEndsAt: nil)
        assertTick(action, pitch: 47, wait: 0.08)
    }

    func testAStaleReportEndsTheTicks() {
        var schedule = FeedbackTickSchedule()
        XCTAssertEqual(schedule.next(now: 1.01, report: report(0.5, at: 0.25), chimeEndsAt: nil), .finished)
    }

    func testWithoutAReportAndWithoutAChimeThereIsNothingLeft() {
        var schedule = FeedbackTickSchedule()
        XCTAssertEqual(schedule.next(now: 5, report: nil, chimeEndsAt: nil), .finished)
    }

    func testAChimeThatIsStillPlayingIsWaitedOut() {
        var schedule = FeedbackTickSchedule()
        XCTAssertEqual(schedule.next(now: 1.0, report: nil, chimeEndsAt: 2.0), .wait(1.0))
        XCTAssertEqual(schedule.next(now: 1.5, report: report(1, at: 0), chimeEndsAt: 2.0), .wait(0.5))
    }

    func testAChimeThatHasEndedIsNotWaitedFor() {
        var schedule = FeedbackTickSchedule()
        XCTAssertEqual(schedule.next(now: 2.0, report: nil, chimeEndsAt: 2.0), .finished)
        XCTAssertEqual(schedule.next(now: 3.0, report: nil, chimeEndsAt: 2.0), .finished)
    }

    func testAFreshReportTakesPriorityOverAChime() {
        var schedule = FeedbackTickSchedule()
        let action = schedule.next(now: 1.0, report: report(0.5, at: 1.0), chimeEndsAt: 2.0)
        assertTick(action, pitch: 47, wait: 0.08)
    }

    func testResettingForgetsTheLastTick() {
        var schedule = FeedbackTickSchedule()
        _ = schedule.next(now: 10, report: report(0.5, at: 10), chimeEndsAt: nil)
        assertWait(schedule.next(now: 10.02, report: report(0.5, at: 10.02), chimeEndsAt: nil), 0.06)
        schedule.reset()
        assertTick(schedule.next(now: 10.03, report: report(0.5, at: 10.03), chimeEndsAt: nil), pitch: 47, wait: 0.08)
    }

    func testTheReportsAreValuesThatCompare() {
        XCTAssertEqual(FeedbackTickSchedule.Report(degrees: 1, time: 2), FeedbackTickSchedule.Report(degrees: 1, time: 2))
        XCTAssertNotEqual(FeedbackTickSchedule.Report(degrees: 1, time: 2), FeedbackTickSchedule.Report(degrees: 1, time: 3))
        XCTAssertNotEqual(FeedbackTickSchedule.Action.finished, FeedbackTickSchedule.Action.wait(0))
    }

    // MARK: The synthesizer

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    /// How often consecutive non-zero samples change sign.
    private func signChanges(_ samples: [Float]) -> Int {
        var count = 0
        var previous: Float = 0
        for sample in samples where sample != 0 {
            if previous != 0, (previous < 0) != (sample < 0) { count += 1 }
            previous = sample
        }
        return count
    }

    func testATickLastsTwentyFiveMillisecondsAtTheSampleRate() {
        XCTAssertEqual(FeedbackSynthesizer.sampleRate, 44_100)
        XCTAssertEqual(FeedbackSynthesizer.tick(frequency: 880).count, 1102)
    }

    func testATickStartsAndEndsAtSilenceWithoutAClick() throws {
        let tick = FeedbackSynthesizer.tick(frequency: 880)
        XCTAssertEqual(try XCTUnwrap(tick.first), 0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(tick.last), 0, accuracy: 1e-4)
    }

    func testATickIsSoftAndAudible() {
        let tick = FeedbackSynthesizer.tick(frequency: 880)
        XCTAssertLessThanOrEqual(peak(tick), 0.8 + 1e-6)
        XCTAssertGreaterThan(peak(tick), 0.4)
        XCTAssertTrue(tick.allSatisfy { $0.isFinite })
    }

    func testATickHasThePitchItWasAskedFor() {
        let low = signChanges(FeedbackSynthesizer.tick(frequency: 440))
        let middle = signChanges(FeedbackSynthesizer.tick(frequency: 880))
        let high = signChanges(FeedbackSynthesizer.tick(frequency: 1320))
        XCTAssertLessThan(low, middle)
        XCTAssertLessThan(middle, high)
        // 880 Hz for 25 ms is 22 cycles, so about 44 zero crossings.
        XCTAssertEqual(Double(middle), 44, accuracy: 4)
    }

    func testTheChimeLastsAboutAsLongAsItSays() {
        XCTAssertEqual(FeedbackSynthesizer.chimeDuration, 0.46, accuracy: 1e-12)
        let chime = FeedbackSynthesizer.chime()
        let expected = Int(FeedbackSynthesizer.chimeDuration * FeedbackSynthesizer.sampleRate)
        XCTAssertEqual(Double(chime.count), Double(expected), accuracy: 2)
    }

    func testTheChimeIsNormalizedToItsPeakAmplitude() {
        let chime = FeedbackSynthesizer.chime()
        XCTAssertEqual(peak(chime), 0.7, accuracy: 1e-4)
        XCTAssertTrue(chime.allSatisfy { $0.isFinite })
    }

    func testTheChimeStartsAndEndsQuietly() throws {
        let chime = FeedbackSynthesizer.chime()
        XCTAssertEqual(try XCTUnwrap(chime.first), 0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(chime.last), 0, accuracy: 1e-3)
    }

    func testTheChimeIsRenderedTheSameEveryTime() {
        XCTAssertEqual(FeedbackSynthesizer.chime(), FeedbackSynthesizer.chime())
        XCTAssertEqual(FeedbackSynthesizer.tick(frequency: 700), FeedbackSynthesizer.tick(frequency: 700))
    }
}
