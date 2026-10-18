import XCTest
@testable import LodestarKit

final class HorizonRecorderTests: XCTestCase {
    private typealias Support = HorizonTestSupport
    private typealias Rejection = HorizonRecorder.Rejection
    private typealias UnrecordedFill = HorizonRecorder.UnrecordedFill

    // MARK: Complete sweeps

    func testACleanSweepRecordsTheSkyline() {
        var recorder = HorizonRecorder()
        Support.sweep(&recorder, from: 0, to: 359.5, rate: 15, hertz: 50)
        XCTAssertEqual(recorder.coverage, 1, accuracy: 1e-12)
        XCTAssertEqual(recorder.recordedBinCount, 360)
        XCTAssertTrue(recorder.gaps.isEmpty)
        let recording = recorder.finish()
        XCTAssertTrue(recording.isComplete)
        XCTAssertEqual(recording.interpolatedBinCount, 0)
        XCTAssertEqual(recording.coverage, 1, accuracy: 1e-12)
        XCTAssertLessThan(Support.largestError(recording.profile), 0.35, "\(Support.largestError(recording.profile))")
        XCTAssertEqual(recording.profile.maximumAltitude, 30, accuracy: 0.35)
        XCTAssertEqual(recording.profile, recorder.profile())
        // The ridge, the building and the trees are where they should be.
        XCTAssertEqual(recording.profile.altitude(at: 90), 30, accuracy: 0.35)
        XCTAssertEqual(recording.profile.altitude(at: 190), 12, accuracy: 0.35)
        XCTAssertEqual(recording.profile.altitude(at: 300), 2, accuracy: 0.35)
    }

    func testNoiseAndWildReadingsAreSuppressedByTheMedian() {
        var recorder = HorizonRecorder()
        let random = Support.SeededGenerator(seed: 7)
        // Ten readings per bin, each off by up to ±1°, and 3 % of them 15° too high.
        Support.sweep(&recorder, from: 0, to: 359.5, rate: 5, hertz: 50, noise: 1, outliers: 0.03, random: random)
        let profile = recorder.profile()
        XCTAssertLessThan(Support.largestError(profile), 1.3, "largest \(Support.largestError(profile))")
        XCTAssertLessThan(Support.meanError(profile), 0.35, "mean \(Support.meanError(profile))")
        XCTAssertEqual(recorder.coverage, 1, accuracy: 1e-12)
    }

    func testHandJitterAndBacktrackingWithinAPassKeepTheMedian() {
        var recorder = HorizonRecorder()
        let random = Support.SeededGenerator(seed: 11)
        // A slow sweep whose azimuth wobbles back and forth by ±2° (a hand that shakes and backs up).
        var time = 0.0
        var step = 0
        var azimuth = 0.0
        while azimuth < 359 {
            let wobble = 2.0 * sin(Double(step) * 0.07)
            let reported = azimuth + wobble
            recorder.add(azimuth: reported, altitude: Support.truth(reported) + 0.6 * random.nextSigned(), timestamp: time)
            time += 0.02
            step += 1
            azimuth += 0.08
        }
        XCTAssertEqual(recorder.coverage, 1, accuracy: 1e-12)
        let profile = recorder.profile()
        // A hand that dwells at one side of a bin shifts its median by the skyline's slope over half a degree, so the
        // steep sides of the building (2.5° per degree) are left out of the strict check.
        XCTAssertLessThan(Support.largestError(profile, 3...170), 0.8, "\(Support.largestError(profile, 3...170))")
        XCTAssertLessThan(Support.largestError(profile, 210...356), 0.8, "\(Support.largestError(profile, 210...356))")
        XCTAssertLessThan(Support.meanError(profile, 3...356), 0.35, "\(Support.meanError(profile, 3...356))")
        XCTAssertEqual(recorder.rejectedCount(for: .tooFast), 0)
    }

    // MARK: Gaps

    func testSmallGapsAreInterpolatedAndLargeOnesAreReported() {
        var recorder = HorizonRecorder()
        // Bins 101…104 are missing (a small gap) and bins 221…250 (a large one).
        Support.sweep(&recorder, from: 0, to: 359.5, rate: 15, hertz: 50,
                      skip: { ($0 >= 100.5 && $0 < 104.5) || ($0 >= 220.5 && $0 < 250.5) })
        let gaps = recorder.gaps
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps[0].start, 220.5, accuracy: 1e-9)
        XCTAssertEqual(gaps[0].length, 30, accuracy: 1e-9)
        XCTAssertTrue(gaps[0].contains(235))
        XCTAssertFalse(gaps[0].contains(102))
        XCTAssertTrue(recorder.coverage < 1 && recorder.coverage > 0.9)
        XCTAssertFalse(recorder.isRecorded(235))
        XCTAssertTrue(recorder.isRecorded(150))

        let recording = recorder.finish()
        XCTAssertFalse(recording.isComplete)
        XCTAssertEqual(recording.gaps, gaps)
        // The small gap follows the line between its recorded neighbours.
        let before = recording.profile.altitude(at: 100)
        let after = recording.profile.altitude(at: 105)
        for azimuth in 101...104 {
            let expected = before + (after - before) * Double(azimuth - 100) / 5
            XCTAssertEqual(recording.profile.altitude(at: Double(azimuth)), expected, accuracy: 0.11, "\(azimuth)")
            XCTAssertEqual(recording.profile.altitude(at: Double(azimuth)), Support.truth(Double(azimuth)),
                           accuracy: 0.4, "\(azimuth)")
        }
        XCTAssertEqual(recording.interpolatedBinCount, 4)
        // Without a base the large gap is flat, with one it keeps the base.
        XCTAssertEqual(recording.profile.altitude(at: 235), 0)
        let kept = recorder.finish(base: .constant(7)).profile
        XCTAssertEqual(kept.altitude(at: 235), 7)
        XCTAssertEqual(kept.altitude(at: 150), Support.truth(150), accuracy: 0.35)
    }

    func testALargeGapCanBeInterpolatedInstead() {
        var recorder = HorizonRecorder()
        // Bins 61…90 are missing: the ridge's slope up to its peak.
        Support.sweep(&recorder, from: 0, to: 359.5, rate: 15, hertz: 50, skip: { $0 >= 60.5 && $0 < 90.5 })
        let filled = recorder.finish(fill: .interpolate)
        // Still reported as a gap, but the profile runs straight between the two ends.
        XCTAssertEqual(filled.gaps.count, 1)
        XCTAssertEqual(filled.gaps[0].length, 30, accuracy: 1e-9)
        let left = filled.profile.altitude(at: 60)
        let right = filled.profile.altitude(at: 91)
        XCTAssertEqual(left, Support.truth(60), accuracy: 0.35)
        XCTAssertEqual(right, Support.truth(91), accuracy: 0.35)
        for azimuth in [61, 75, 90] {
            let expected = left + (right - left) * Double(azimuth - 60) / 31
            XCTAssertEqual(filled.profile.altitude(at: Double(azimuth)), expected, accuracy: 0.16, "\(azimuth)")
        }
        XCTAssertEqual(filled.interpolatedBinCount, 30)
        // Without the policy the gap is flat.
        XCTAssertEqual(recorder.finish().profile.altitude(at: 75), 0)
    }

    func testSweepAcrossNorthWrapsAround() {
        var recorder = HorizonRecorder()
        Support.sweep(&recorder, from: 330, to: 390, rate: 12, hertz: 50)
        XCTAssertEqual(recorder.coverage, 61.0 / 360.0, accuracy: 1e-9)
        for azimuth in [330.0, 355, 359, 0, 5, 30] { XCTAssertTrue(recorder.isRecorded(azimuth), "\(azimuth)") }
        for azimuth in [329.0, 31, 180] { XCTAssertFalse(recorder.isRecorded(azimuth), "\(azimuth)") }
        let mask = recorder.recordedMask
        XCTAssertEqual(mask.count, 360)
        XCTAssertEqual(mask.filter { $0 }.count, 61)
        XCTAssertTrue(mask[359] && mask[0])
        let gaps = recorder.gaps
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps[0].start, 30.5, accuracy: 1e-9)
        XCTAssertEqual(gaps[0].length, 299, accuracy: 1e-9)
        let profile = recorder.profile()
        for azimuth in [335, 358, 359, 0, 1, 20] {
            XCTAssertEqual(profile.altitude(at: Double(azimuth)), Support.truth(Double(azimuth)), accuracy: 0.3, "\(azimuth)")
        }
        // The profile is continuous through north.
        XCTAssertEqual(profile.altitude(at: 359), profile.altitude(at: 360), accuracy: 0.3)
    }

    // MARK: Partial sweeps

    func testAPartialSweepLeavesTheRestFlatOrKeepsTheBaseOrInterpolates() {
        var recorder = HorizonRecorder()
        Support.sweep(&recorder, from: 40, to: 160, rate: 15, hertz: 50)
        XCTAssertEqual(recorder.coverage, 121.0 / 360.0, accuracy: 1e-9)
        XCTAssertEqual(recorder.gaps.count, 1)
        XCTAssertEqual(recorder.gaps[0].length, 239, accuracy: 1e-9)
        XCTAssertEqual(recorder.gaps[0].start, 160.5, accuracy: 1e-9)

        // Unrecorded azimuths stay at 0°…
        let flat = recorder.finish()
        for azimuth in [0, 20, 39, 161, 200, 300, 359] { XCTAssertEqual(flat.profile.altitudes[azimuth], 0, "\(azimuth)") }
        XCTAssertEqual(flat.profile.altitude(at: 90), Support.truth(90), accuracy: 0.35)
        XCTAssertEqual(flat.interpolatedBinCount, 0)

        // …or keep the profile that was there before…
        let base = HorizonProfile.constant(5).setting(to: 18, in: AzimuthRange(from: 250, to: 290))
        let merged = recorder.finish(fill: .keepBase, base: base).profile
        for azimuth in [0, 20, 39, 161, 200, 300, 359] {
            XCTAssertEqual(merged.altitudes[azimuth], base.altitudes[azimuth], "\(azimuth)")
        }
        XCTAssertEqual(merged.altitude(at: 270), 18)
        XCTAssertEqual(merged.altitude(at: 100), Support.truth(100), accuracy: 0.35)

        // …or run straight from the end of the sweep back to its start through north.
        let line = recorder.finish(fill: .interpolate)
        let atEnd = line.profile.altitude(at: 160)
        let atStart = line.profile.altitude(at: 40)
        // 160° → 40° through north is 240° of azimuth; 280° is halfway.
        XCTAssertEqual(line.profile.altitude(at: 280), (atEnd + atStart) / 2, accuracy: 0.2)
        XCTAssertEqual(line.profile.altitude(at: 220), atEnd + (atStart - atEnd) * (60.0 / 240.0), accuracy: 0.2)
        XCTAssertEqual(line.interpolatedBinCount, 239)
    }

    func testNothingRecordedGivesTheBaseAndTheWholeCircleAsGap() {
        let recorder = HorizonRecorder()
        XCTAssertEqual(recorder.coverage, 0)
        XCTAssertEqual(recorder.gaps, [.full])
        XCTAssertTrue(recorder.profile().isFlat)
        let base = Support.truthProfile
        let recording = recorder.finish(fill: .interpolate, base: base)
        XCTAssertEqual(recording.profile, base)
        XCTAssertEqual(recording.coverage, 0)
        XCTAssertEqual(recording.gaps, [.full])
        XCTAssertFalse(recording.isComplete)
        XCTAssertFalse(recorder.isRecorded(10))
        XCTAssertNil(recorder.lastAzimuth)
        XCTAssertNil(recorder.sweepRate)
    }

    func testASingleBinFillsTheCircleWhenInterpolating() {
        var recorder = HorizonRecorder()
        recorder.add(azimuth: 10, altitude: 8, timestamp: 0)
        XCTAssertEqual(recorder.recordedBinCount, 1)
        let line = recorder.finish(fill: .interpolate).profile
        XCTAssertEqual(line, HorizonProfile.constant(8))
        XCTAssertEqual(recorder.finish().profile.altitude(at: 10), 8)
        XCTAssertEqual(recorder.finish().profile.altitude(at: 100), 0)
    }

    // MARK: Backtracking

    func testSweepingBackOverAStretchReplacesTheOldPass() {
        var recorder = HorizonRecorder()
        // The first pass was held 6° too high.
        var time = Support.sweep(&recorder, from: 0, to: 120, rate: 15, hertz: 50, bias: 6)
        let firstPass = recorder.profile()
        XCTAssertEqual(firstPass.altitude(at: 30), Support.truth(30) + 6, accuracy: 0.4)
        // After a pause the user sweeps 120° back to 60° and forward again over the stretch they got wrong.
        time += 5
        time = Support.sweep(&recorder, from: 120, to: 60, rate: 15, hertz: 50, start: time)
        let profile = recorder.profile()
        for azimuth in 62...118 {
            XCTAssertEqual(profile.altitude(at: Double(azimuth)), Support.truth(Double(azimuth)), accuracy: 0.4, "\(azimuth)")
        }
        // What was not swept again keeps the first pass.
        for azimuth in 5...55 {
            XCTAssertEqual(profile.altitude(at: Double(azimuth)), Support.truth(Double(azimuth)) + 6, accuracy: 0.4, "\(azimuth)")
        }
        XCTAssertEqual(recorder.coverage, 121.0 / 360.0, accuracy: 1e-9)
        XCTAssertGreaterThan(time, 0)
    }

    func testSamplesWithinAPassOfTheSameBinAreMergedNotReplaced() {
        // Two readings 1 s apart in one bin are the same pass: the median of three is the middle one.
        var recorder = HorizonRecorder()
        recorder.add(azimuth: 50, altitude: 10, timestamp: 0)
        recorder.add(azimuth: 50.1, altitude: 20, timestamp: 1)
        recorder.add(azimuth: 49.9, altitude: 12, timestamp: 2)
        XCTAssertEqual(recorder.profile().altitude(at: 50), 12)
        // With an even number the two middle values are averaged.
        recorder.add(azimuth: 50, altitude: 16, timestamp: 2.5)
        XCTAssertEqual(recorder.profile().altitude(at: 50), 14)
        // After more than the pass interval the bin starts over.
        recorder.add(azimuth: 50, altitude: 3, timestamp: 20)
        XCTAssertEqual(recorder.profile().altitude(at: 50), 3)
        XCTAssertEqual(recorder.recordedBinCount, 1)
    }

    func testABinKeepsOnlyTheMostRecentSamples() {
        var recorder = HorizonRecorder(configuration: HorizonRecorder.Configuration(maximumSamplesPerBin: 3))
        // Old values 40, 41, 42 are pushed out by 10, 11, 12.
        for (index, value) in [40.0, 41, 42, 10, 11, 12].enumerated() {
            XCTAssertNil(recorder.add(azimuth: 70, altitude: value, timestamp: Double(index)))
        }
        XCTAssertEqual(recorder.profile().altitude(at: 70), 11)
    }

    // MARK: Rejected samples

    func testRejectedSamplesAreCountedByReason() {
        var recorder = HorizonRecorder()
        XCTAssertNil(recorder.add(azimuth: 10, altitude: 5, timestamp: 0))
        XCTAssertEqual(recorder.add(azimuth: .nan, altitude: 5, timestamp: 0.1), .invalid)
        XCTAssertEqual(recorder.add(azimuth: 10, altitude: .infinity, timestamp: 0.1), .invalid)
        XCTAssertEqual(recorder.add(azimuth: 10, altitude: 5, timestamp: .nan), .invalid)
        XCTAssertEqual(recorder.add(azimuth: 10, altitude: 5, timestamp: 0.1, quality: 0.1), .lowQuality)
        XCTAssertNil(recorder.add(azimuth: 10, altitude: 5, timestamp: 0.2, quality: 0.25))
        XCTAssertNil(recorder.add(azimuth: 10, altitude: 5, timestamp: 0.3, quality: nil))
        XCTAssertNil(recorder.add(azimuth: 10, altitude: 5, timestamp: 0.4, quality: .nan))
        XCTAssertEqual(recorder.add(azimuth: 10, altitude: 61, timestamp: 0.5), .outOfRange)
        XCTAssertEqual(recorder.add(azimuth: 10, altitude: -10.5, timestamp: 0.6), .outOfRange)
        XCTAssertNil(recorder.add(azimuth: 10, altitude: 60, timestamp: 10)) // the edge of the range is allowed
        XCTAssertEqual(recorder.acceptedCount, 5)
        XCTAssertEqual(recorder.rejectedCount(for: .invalid), 3)
        XCTAssertEqual(recorder.rejectedCount(for: .lowQuality), 1)
        XCTAssertEqual(recorder.rejectedCount(for: .outOfRange), 2)
        XCTAssertEqual(recorder.rejectedCount(for: .tooFast), 0)
        // The first reason that applies is reported: invalid before quality before range.
        XCTAssertEqual(recorder.add(azimuth: .nan, altitude: 99, timestamp: 1, quality: 0), .invalid)
        XCTAssertEqual(recorder.add(azimuth: 10, altitude: 99, timestamp: 1, quality: 0), .lowQuality)
    }

    func testTooFastSamplesAreRejectedAndTheSweepRateIsReported() throws {
        var recorder = HorizonRecorder()
        XCTAssertNil(recorder.add(azimuth: 0, altitude: 0, timestamp: 0))
        XCTAssertNil(recorder.sweepRate)
        XCTAssertNil(recorder.add(azimuth: 1, altitude: 0, timestamp: 0.1)) // 10°/s
        XCTAssertEqual(try XCTUnwrap(recorder.sweepRate), 10, accuracy: 1e-6)
        // 30° in 0.1 s is 300°/s: the camera was whipped round.
        XCTAssertEqual(recorder.add(azimuth: 31, altitude: 0, timestamp: 0.2), .tooFast)
        XCTAssertEqual(try XCTUnwrap(recorder.sweepRate), 300, accuracy: 1e-6)
        XCTAssertEqual(recorder.rejectedCount(for: .tooFast), 1)
        XCTAssertFalse(recorder.isRecorded(31))
        // The next reading, close to the one that was rejected, is accepted at once.
        XCTAssertNil(recorder.add(azimuth: 31.5, altitude: 0, timestamp: 0.3))
        XCTAssertTrue(recorder.isRecorded(31.5))
        XCTAssertEqual(try XCTUnwrap(recorder.lastAzimuth), 31.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(recorder.lastAltitude), 0, accuracy: 1e-12)
        // Altitude jitter does not count, and a sample at the same time or earlier is not judged.
        XCTAssertNil(recorder.add(azimuth: 31.5, altitude: 45, timestamp: 0.4))
        XCTAssertNil(recorder.add(azimuth: 32.5, altitude: 44, timestamp: 0.4))
        XCTAssertNil(recorder.add(azimuth: 32.5, altitude: 44, timestamp: 0))
        XCTAssertEqual(recorder.rejectedCount(for: .tooFast), 1)
    }

    func testTheSweepRateAcrossNorthIsTheShortWayRound() throws {
        var recorder = HorizonRecorder()
        recorder.add(azimuth: 359, altitude: 0, timestamp: 0)
        XCTAssertNil(recorder.add(azimuth: 1, altitude: 0, timestamp: 0.5)) // 4°/s through north, not 716°/s
        XCTAssertEqual(try XCTUnwrap(recorder.sweepRate), 4, accuracy: 1e-6)
    }

    func testAHighCameraShortensTheAzimuthTravel() throws {
        // At 60° altitude a turn of 10° of azimuth moves the picture by 10° · cos 60° = 5°.
        var recorder = HorizonRecorder(configuration: HorizonRecorder.Configuration(maximumSweepRate: 6))
        recorder.add(azimuth: 0, altitude: 60, timestamp: 0)
        XCTAssertNil(recorder.add(azimuth: 10, altitude: 60, timestamp: 1)) // 5°/s
        XCTAssertEqual(try XCTUnwrap(recorder.sweepRate), 5, accuracy: 0.01)
        XCTAssertEqual(recorder.add(azimuth: 22, altitude: 60, timestamp: 2), .tooFast) // 6.0…
    }

    // MARK: Editing and configuration

    func testClearForgetsAStretchSoItCanBeSweptAgain() {
        var recorder = HorizonRecorder()
        Support.sweep(&recorder, from: 0, to: 359.5, rate: 15, hertz: 50)
        recorder.clear(AzimuthRange(from: 100, to: 140))
        XCTAssertEqual(recorder.recordedBinCount, 360 - 41)
        XCTAssertFalse(recorder.isRecorded(120))
        XCTAssertTrue(recorder.isRecorded(99) && recorder.isRecorded(141))
        XCTAssertEqual(recorder.gaps.count, 1)
        XCTAssertEqual(recorder.gaps[0].length, 41, accuracy: 1e-9)
        // Sweeping it again right away (the bins are empty, so there is no old pass) fills it.
        Support.sweep(&recorder, from: 100, to: 140, rate: 15, hertz: 50, start: 30)
        XCTAssertEqual(recorder.coverage, 1, accuracy: 1e-12)
        XCTAssertTrue(recorder.gaps.isEmpty)
        XCTAssertLessThan(Support.largestError(recorder.profile()), 0.35)
    }

    func testResetStartsOver() {
        var recorder = HorizonRecorder()
        Support.sweep(&recorder, from: 0, to: 90, rate: 15, hertz: 50)
        recorder.add(azimuth: .nan, altitude: 0, timestamp: 0)
        XCTAssertGreaterThan(recorder.acceptedCount, 0)
        recorder.reset()
        XCTAssertEqual(recorder.acceptedCount, 0)
        XCTAssertEqual(recorder.rejectedCount(for: .invalid), 0)
        XCTAssertEqual(recorder.recordedBinCount, 0)
        XCTAssertNil(recorder.lastAzimuth)
        XCTAssertNil(recorder.sweepRate)
        XCTAssertTrue(recorder.profile().isFlat)
        // After a reset the first sample is not compared with anything.
        XCTAssertNil(recorder.add(azimuth: 200, altitude: 5, timestamp: 1))
    }

    func testFinishDoesNotChangeTheRecorder() {
        var recorder = HorizonRecorder()
        Support.sweep(&recorder, from: 0, to: 100, rate: 15, hertz: 50)
        let first = recorder.finish()
        let second = recorder.finish()
        XCTAssertEqual(first, second)
        Support.sweep(&recorder, from: 100, to: 359.5, rate: 15, hertz: 50, start: 7)
        XCTAssertTrue(recorder.finish().isComplete)
        XCTAssertFalse(first.isComplete)
    }

    func testConfigurationFallsBackToDefaultsAndClamps() {
        let defaults = HorizonRecorder.Configuration.standard
        XCTAssertEqual(defaults.minimumQuality, 0.25)
        XCTAssertEqual(defaults.maximumSweepRate, 60)
        XCTAssertEqual(defaults.maximumSamplesPerBin, 25)
        XCTAssertEqual(defaults.newPassInterval, 3)
        XCTAssertEqual(defaults.maximumInterpolatedGap, 6)
        XCTAssertEqual(defaults, HorizonRecorder.Configuration())
        let odd = HorizonRecorder.Configuration(minimumQuality: .nan, maximumSweepRate: -5, maximumSamplesPerBin: 1_000,
                                                newPassInterval: .infinity, maximumInterpolatedGap: 99)
        XCTAssertEqual(odd.minimumQuality, 0.25)
        XCTAssertEqual(odd.maximumSweepRate, 60)
        XCTAssertEqual(odd.maximumSamplesPerBin, 100)
        XCTAssertEqual(odd.newPassInterval, 3)
        XCTAssertEqual(odd.maximumInterpolatedGap, 30)
        let low = HorizonRecorder.Configuration(minimumQuality: -1, maximumSamplesPerBin: 0, maximumInterpolatedGap: -3)
        XCTAssertEqual(low.minimumQuality, 0)
        XCTAssertEqual(low.maximumSamplesPerBin, 1)
        XCTAssertEqual(low.maximumInterpolatedGap, 0)
        XCTAssertEqual(HorizonRecorder.Configuration(minimumQuality: 4).minimumQuality, 1)
    }

    func testTheInterpolationLimitDecidesWhatIsAGap() {
        var tight = HorizonRecorder(configuration: HorizonRecorder.Configuration(maximumInterpolatedGap: 2))
        Support.sweep(&tight, from: 0, to: 359.5, rate: 15, hertz: 50, skip: { $0 >= 100.5 && $0 < 104.5 })
        XCTAssertEqual(tight.gaps.count, 1)
        XCTAssertEqual(tight.gaps[0].length, 4, accuracy: 1e-9)
        var loose = HorizonRecorder(configuration: HorizonRecorder.Configuration(maximumInterpolatedGap: 10))
        Support.sweep(&loose, from: 0, to: 359.5, rate: 15, hertz: 50, skip: { $0 >= 100.5 && $0 < 104.5 })
        XCTAssertTrue(loose.gaps.isEmpty)
        XCTAssertTrue(loose.finish().isComplete)
    }

    func testRejectionAndFillRawValues() {
        XCTAssertEqual(Rejection.allCases.map(\.rawValue), ["invalid", "lowQuality", "outOfRange", "tooFast"])
        XCTAssertEqual(Rejection(rawValue: "tooFast"), .tooFast)
        XCTAssertNil(Rejection(rawValue: "slow"))
        XCTAssertEqual(UnrecordedFill.allCases.map(\.rawValue), ["keepBase", "interpolate"])
        XCTAssertEqual(UnrecordedFill(rawValue: "interpolate"), .interpolate)
        XCTAssertNil(UnrecordedFill(rawValue: "zero"))
    }
}
