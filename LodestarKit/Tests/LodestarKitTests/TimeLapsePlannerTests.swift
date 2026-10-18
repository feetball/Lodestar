import XCTest
@testable import LodestarKit

final class TimeLapsePlannerTests: XCTestCase {
    // MARK: Arithmetic

    func testPlanFromAClipLength() throws {
        // 10 s of video at 24 frames per second is 240 frames; one every 10 s is 40 minutes of shooting.
        let plan = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .clipLength(seconds: 10))
        XCTAssertEqual(plan.frameCount, 240)
        XCTAssertEqual(plan.shootingTime, 2400.0)
        XCTAssertEqual(plan.clipLength, 10.0)
        XCTAssertEqual(plan.gap, 5.0)
        XCTAssertEqual(plan.speedUp, 240.0)
        XCTAssertEqual(plan.interval, 10.0)
        XCTAssertEqual(plan.exposure, 5.0)
        XCTAssertEqual(plan.frameRate, 24.0)
        XCTAssertEqual(plan.exposureCount, 240)
    }

    func testPlanFromAShootingTime() throws {
        // An hour at one frame every 10 s is 360 frames, 15 s of video at 24 frames per second.
        let plan = try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .shootingTime(seconds: 3600))
        XCTAssertEqual(plan.frameCount, 360)
        XCTAssertEqual(plan.shootingTime, 3600.0)
        XCTAssertEqual(plan.clipLength, 15.0)
        XCTAssertEqual(plan.speedUp, 240.0)
        // Only whole intervals fit.
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .shootingTime(seconds: 3599)).frameCount, 359)
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .shootingTime(seconds: 3609.9)).frameCount, 360)
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .shootingTime(seconds: 3599)).shootingTime, 3590.0)
        // Seven hours of night at one frame every 15 s.
        let night = try TimeLapsePlanner.plan(interval: 15, exposure: 10, frameRate: 30, target: .shootingTime(seconds: 7 * 3600))
        XCTAssertEqual(night.frameCount, 1680)
        XCTAssertEqual(night.clipLength, 56.0, accuracy: 1e-12)
        XCTAssertEqual(night.speedUp, 450.0)
    }

    func testPlanFromAFrameCount() throws {
        let plan = try TimeLapsePlanner.plan(interval: 30, exposure: 20, frameRate: 25, target: .frameCount(frames: 100))
        XCTAssertEqual(plan.frameCount, 100)
        XCTAssertEqual(plan.shootingTime, 3000.0)
        XCTAssertEqual(plan.clipLength, 4.0)
        XCTAssertEqual(plan.gap, 10.0)
        XCTAssertEqual(plan.speedUp, 750.0)
    }

    func testClipLengthRoundsToWholeFrames() throws {
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 5, exposure: 2, frameRate: 24, target: .clipLength(seconds: 1.02)).frameCount, 24)
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 5, exposure: 2, frameRate: 24, target: .clipLength(seconds: 1.03)).frameCount, 25)
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 5, exposure: 2, frameRate: 24, target: .clipLength(seconds: 0.03)).frameCount, 1)
        // 29.97 frames per second, a common video rate.
        let ntsc = try TimeLapsePlanner.plan(interval: 5, exposure: 2, frameRate: 29.97, target: .clipLength(seconds: 20))
        XCTAssertEqual(ntsc.frameCount, 599)
        XCTAssertEqual(ntsc.clipLength, 599 / 29.97, accuracy: 1e-12)
    }

    func testStorageEstimate() throws {
        // 360 raw files of 25 MB are 9000 MB, 9 GB.
        let plan = try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .shootingTime(seconds: 3600), frameSizeMegabytes: 25)
        XCTAssertEqual(plan.frameSizeMegabytes, 25.0)
        XCTAssertEqual(plan.storageMegabytes, 9000.0)
        XCTAssertEqual(plan.storageGigabytes, 9.0)
        let small = try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .frameCount(frames: 7), frameSizeMegabytes: 7.5)
        XCTAssertEqual(try XCTUnwrap(small.storageMegabytes), 52.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(small.storageGigabytes), 0.0525, accuracy: 1e-12)
        let unknown = try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .frameCount(frames: 7))
        XCTAssertNil(unknown.frameSizeMegabytes)
        XCTAssertNil(unknown.storageMegabytes)
        XCTAssertNil(unknown.storageGigabytes)
    }

    // MARK: Gap

    func testGapMustCoverTheWriteTime() throws {
        // Exposing 4.5 s every 5 s leaves 0.5 s, less than the default 1 s the camera needs.
        let error = MosaicTestSupport.thrown { _ = try TimeLapsePlanner.plan(interval: 5, exposure: 4.5, frameRate: 24, target: .frameCount(frames: 10)) }
        XCTAssertEqual(error as? TimeLapseError, .gapTooShort(gapSeconds: 0.5, minimumGapSeconds: 1.0, minimumIntervalSeconds: 5.5))
        // A camera that writes faster is fine with it, and exactly the minimum passes.
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 5, exposure: 4.5, frameRate: 24, target: .frameCount(frames: 10), minimumGapSeconds: 0.5).gap, 0.5)
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 10, exposure: 9, frameRate: 24, target: .frameCount(frames: 10)).gap, 1.0)
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 10, exposure: 10, frameRate: 24, target: .frameCount(frames: 10), minimumGapSeconds: 0).gap, 0.0)
        // An exposure as long as the interval, or longer, never works with a write time.
        MosaicTestSupport.assertThrowsKind("gapTooShort") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 10, frameRate: 24, target: .frameCount(frames: 10)) }
        let longer = MosaicTestSupport.thrown { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 12, frameRate: 24, target: .frameCount(frames: 10)) }
        XCTAssertEqual(longer as? TimeLapseError, .gapTooShort(gapSeconds: -2.0, minimumGapSeconds: 1.0, minimumIntervalSeconds: 13.0))
    }

    func testMinimumInterval() throws {
        XCTAssertEqual(try TimeLapsePlanner.minimumInterval(exposure: 30), 31.0)
        XCTAssertEqual(try TimeLapsePlanner.minimumInterval(exposure: 30, minimumGapSeconds: 2.5), 32.5)
        XCTAssertEqual(try TimeLapsePlanner.minimumInterval(exposure: 5, minimumGapSeconds: 0.5), 5.5)
        XCTAssertEqual(try TimeLapsePlanner.minimumInterval(exposure: 30, minimumGapSeconds: 0), 30.0)
        MosaicTestSupport.assertThrows(TimeLapseError.invalidExposure(seconds: 0)) { _ = try TimeLapsePlanner.minimumInterval(exposure: 0) }
        MosaicTestSupport.assertThrowsKind("invalidExposure") { _ = try TimeLapsePlanner.minimumInterval(exposure: .nan) }
        MosaicTestSupport.assertThrowsKind("invalidExposure") { _ = try TimeLapsePlanner.minimumInterval(exposure: 4000) }
        MosaicTestSupport.assertThrowsKind("invalidMinimumGap") { _ = try TimeLapsePlanner.minimumInterval(exposure: 10, minimumGapSeconds: -1) }
        MosaicTestSupport.assertThrowsKind("invalidMinimumGap") { _ = try TimeLapsePlanner.minimumInterval(exposure: 10, minimumGapSeconds: 61) }
        // The shortest interval that it names plans.
        let interval = try TimeLapsePlanner.minimumInterval(exposure: 30)
        _ = try TimeLapsePlanner.plan(interval: interval, exposure: 30, frameRate: 24, target: .frameCount(frames: 3))
    }

    // MARK: Battery

    func testBatteryDemandFollowsTheNumberOfExposures() throws {
        XCTAssertEqual(TimeLapsePlanner.batteryDemand(exposureCount: 1), .light)
        XCTAssertEqual(TimeLapsePlanner.batteryDemand(exposureCount: 300), .light)
        XCTAssertEqual(TimeLapsePlanner.batteryDemand(exposureCount: 301), .moderate)
        XCTAssertEqual(TimeLapsePlanner.batteryDemand(exposureCount: 1000), .moderate)
        XCTAssertEqual(TimeLapsePlanner.batteryDemand(exposureCount: 1001), .heavy)
        XCTAssertEqual(TimeLapsePlanner.batteryDemand(exposureCount: 2500), .heavy)
        XCTAssertEqual(TimeLapsePlanner.batteryDemand(exposureCount: 2501), .veryHeavy)
        let plan = try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .shootingTime(seconds: 3600))
        XCTAssertEqual(plan.batteryDemand, .moderate)
        XCTAssertTrue(plan.batteryNote.hasPrefix("About 360 exposures"), plan.batteryNote)
        XCTAssertEqual(plan.batteryNote, TimeLapsePlanner.batteryNote(exposureCount: 360))
        XCTAssertTrue(TimeLapsePlanner.batteryNote(exposureCount: 50).contains("one charged battery"))
        XCTAssertTrue(TimeLapsePlanner.batteryNote(exposureCount: 2000).contains("spare battery"))
        XCTAssertTrue(TimeLapsePlanner.batteryNote(exposureCount: 5000).contains("external power"))
        XCTAssertTrue(TimeLapsePlanner.batteryNote(exposureCount: 5000).hasPrefix("About 5000 exposures"))
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 10, exposure: 8, frameRate: 24, target: .frameCount(frames: 4000)).batteryDemand, .veryHeavy)
        XCTAssertEqual(BatteryDemand(rawValue: "veryHeavy"), .veryHeavy)
        XCTAssertNil(BatteryDemand(rawValue: "flat"))
    }

    // MARK: Validation

    func testInvalidInputIsRejected() throws {
        let target = TimeLapseTarget.frameCount(frames: 10)
        MosaicTestSupport.assertThrows(TimeLapseError.invalidInterval(seconds: 0)) { _ = try TimeLapsePlanner.plan(interval: 0, exposure: 1, frameRate: 24, target: target) }
        MosaicTestSupport.assertThrowsKind("invalidInterval") { _ = try TimeLapsePlanner.plan(interval: -5, exposure: 1, frameRate: 24, target: target) }
        MosaicTestSupport.assertThrowsKind("invalidInterval") { _ = try TimeLapsePlanner.plan(interval: .nan, exposure: 1, frameRate: 24, target: target) }
        MosaicTestSupport.assertThrowsKind("invalidInterval") { _ = try TimeLapsePlanner.plan(interval: 3601, exposure: 1, frameRate: 24, target: target) }
        MosaicTestSupport.assertThrows(TimeLapseError.invalidExposure(seconds: 0)) { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 0, frameRate: 24, target: target) }
        MosaicTestSupport.assertThrowsKind("invalidExposure") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: .infinity, frameRate: 24, target: target) }
        MosaicTestSupport.assertThrows(TimeLapseError.invalidFrameRate(framesPerSecond: 0)) { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 0, target: target) }
        MosaicTestSupport.assertThrowsKind("invalidFrameRate") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 241, target: target) }
        MosaicTestSupport.assertThrowsKind("invalidFrameRate") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: .nan, target: target) }
        _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 240, target: target)
        MosaicTestSupport.assertThrowsKind("invalidMinimumGap") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: target, minimumGapSeconds: -0.1) }
        MosaicTestSupport.assertThrowsKind("invalidMinimumGap") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: target, minimumGapSeconds: .nan) }
        MosaicTestSupport.assertThrows(TimeLapseError.invalidFrameSize(megabytes: 0)) { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: target, frameSizeMegabytes: 0) }
        MosaicTestSupport.assertThrowsKind("invalidFrameSize") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: target, frameSizeMegabytes: 20_000) }
        MosaicTestSupport.assertThrowsKind("invalidFrameSize") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: target, frameSizeMegabytes: .nan) }
        MosaicTestSupport.assertThrowsKind("invalidTarget") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .clipLength(seconds: 0)) }
        MosaicTestSupport.assertThrowsKind("invalidTarget") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .clipLength(seconds: -3)) }
        MosaicTestSupport.assertThrowsKind("invalidTarget") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .clipLength(seconds: .nan)) }
        MosaicTestSupport.assertThrowsKind("invalidTarget") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .clipLength(seconds: 0.01)) }
        MosaicTestSupport.assertThrowsKind("invalidTarget") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .shootingTime(seconds: 9)) }
        MosaicTestSupport.assertThrowsKind("invalidTarget") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .shootingTime(seconds: .infinity)) }
        MosaicTestSupport.assertThrows(TimeLapseError.invalidTarget(value: 0)) { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .frameCount(frames: 0)) }
        MosaicTestSupport.assertThrowsKind("invalidTarget") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .frameCount(frames: -4)) }
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .shootingTime(seconds: 10)).frameCount, 1)
    }

    func testTooManyFramesIsAnError() throws {
        let error = MosaicTestSupport.thrown { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .frameCount(frames: 100_001)) }
        XCTAssertEqual(error as? TimeLapseError, .tooManyFrames(count: 100_001, limit: TimeLapsePlanner.maximumFrameCount))
        MosaicTestSupport.assertThrowsKind("tooManyFrames") { _ = try TimeLapsePlanner.plan(interval: 2, exposure: 1, frameRate: 24, target: .shootingTime(seconds: 1e7)) }
        MosaicTestSupport.assertThrowsKind("tooManyFrames") { _ = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 30, target: .clipLength(seconds: 5000)) }
        XCTAssertEqual(try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .frameCount(frames: 100_000)).frameCount, 100_000)
    }

    func testPlansAreValues() throws {
        let a = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .clipLength(seconds: 10), frameSizeMegabytes: 30)
        let b = try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 24, target: .frameCount(frames: 240), frameSizeMegabytes: 30)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, try TimeLapsePlanner.plan(interval: 10, exposure: 5, frameRate: 25, target: .frameCount(frames: 240), frameSizeMegabytes: 30))
    }
}
