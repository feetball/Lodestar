import XCTest
@testable import LodestarKit

final class MountSupportTests: XCTestCase {
    func testCalendarFieldsAreExact() throws {
        func fields(_ seconds: Double) throws -> MountDateTime {
            try XCTUnwrap(MountCalendar.fields(for: Date(timeIntervalSince1970: seconds)))
        }
        func expected(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, _ ms: Int) -> MountDateTime {
            MountDateTime(year: y, month: mo, day: d, hour: h, minute: mi, second: s, millisecond: ms)
        }
        XCTAssertEqual(try fields(0.0), expected(1970, 1, 1, 0, 0, 0, 0))
        XCTAssertEqual(try fields(946_728_000.0), expected(2000, 1, 1, 12, 0, 0, 0))
        XCTAssertEqual(try fields(951_868_799.123), expected(2000, 2, 29, 23, 59, 59, 123))
        XCTAssertEqual(try fields(951_868_800.0), expected(2000, 3, 1, 0, 0, 0, 0))
        XCTAssertEqual(try fields(1_792_296_000.0), expected(2026, 10, 18, 4, 0, 0, 0))
        XCTAssertEqual(try fields(2_147_483_648.0), expected(2038, 1, 19, 3, 14, 8, 0))
        XCTAssertEqual(try fields(4_107_542_400.0), expected(2100, 3, 1, 0, 0, 0, 0))
        XCTAssertEqual(try fields(1_735_689_599.9999), expected(2024, 12, 31, 23, 59, 59, 999))
        XCTAssertEqual(try fields(253_402_300_799.0), expected(9999, 12, 31, 23, 59, 59, 0))
        XCTAssertNil(MountCalendar.fields(for: Date(timeIntervalSince1970: -1)))
        XCTAssertNil(MountCalendar.fields(for: Date(timeIntervalSince1970: 253_402_300_800.0)))
    }

    func testCalendarAgainstTheFoundationCalendarOverManyDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var seconds = 0
        while seconds < 4_102_444_800 {
            let date = Date(timeIntervalSince1970: Double(seconds))
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let actual = try XCTUnwrap(MountCalendar.fields(for: date))
            XCTAssertEqual([actual.year, actual.month, actual.day, actual.hour, actual.minute, actual.second],
                           [components.year, components.month, components.day, components.hour, components.minute, components.second],
                           "\(seconds)")
            seconds += 86_399 * 7 + 1_234
        }
    }

    func testSettingsAreClamped() {
        let standard = MountSettings.standard
        XCTAssertEqual(standard.altitudeLimit, 0.0, accuracy: 0.0)
        XCTAssertEqual(standard.horizonLookaheadSeconds, 60.0, accuracy: 0.0)
        XCTAssertEqual(standard.maximumSlewSeconds, 300.0, accuracy: 0.0)
        XCTAssertEqual(standard.maximumConsecutiveFailures, 3)
        let wild = MountSettings(
            altitudeLimit: 500.0, horizonLookaheadSeconds: -5.0, maximumSlewSeconds: 1.0e9, slewStartGraceSeconds: Double.nan,
            arrivalToleranceDegrees: 0.0, pollIntervalSeconds: 0.0, maximumConsecutiveFailures: 0, maximumNudgeSeconds: 1.0e9,
            maximumSyncOffsetDegrees: 1000.0)
        XCTAssertEqual(wild.altitudeLimit, 60.0, accuracy: 0.0)
        XCTAssertEqual(wild.horizonLookaheadSeconds, 0.0, accuracy: 0.0)
        XCTAssertEqual(wild.maximumSlewSeconds, 3600.0, accuracy: 0.0)
        XCTAssertEqual(wild.slewStartGraceSeconds, 5.0, accuracy: 0.0)
        XCTAssertEqual(wild.arrivalToleranceDegrees, 0.01, accuracy: 0.0)
        XCTAssertEqual(wild.pollIntervalSeconds, 0.1, accuracy: 0.0)
        XCTAssertEqual(wild.maximumConsecutiveFailures, 1)
        XCTAssertEqual(wild.maximumNudgeSeconds, 30.0, accuracy: 0.0)
        XCTAssertEqual(wild.maximumSyncOffsetDegrees, 180.0, accuracy: 0.0)
        XCTAssertEqual(MountSettings(altitudeLimit: -50.0).altitudeLimit, -10.0, accuracy: 0.0)
        XCTAssertEqual(MountSettings(maximumConsecutiveFailures: 99).maximumConsecutiveFailures, 10)
    }

    func testDriverConfigurationsAreClamped() {
        XCTAssertEqual(LX200Configuration(exchangeTimeoutSeconds: 1.0e6).exchangeTimeoutSeconds, 30.0, accuracy: 0.0)
        XCTAssertEqual(LX200Configuration(exchangeTimeoutSeconds: 0.0).exchangeTimeoutSeconds, 0.5, accuracy: 0.0)
        XCTAssertEqual(LX200Configuration(exchangeTimeoutSeconds: Double.nan).exchangeTimeoutSeconds, 3.0, accuracy: 0.0)
        XCTAssertEqual(LX200Configuration(busyRetries: 99).busyRetries, 10)
        XCTAssertEqual(LX200Configuration(busyRetries: -3).busyRetries, 0)
        XCTAssertEqual(LX200Configuration.standard.epoch, .meanOfDate)
        XCTAssertNil(NexStarConfiguration.standard.epoch)
        XCTAssertEqual(NexStarConfiguration.standard.exchangeTimeoutSeconds, 5.5, accuracy: 0.0)
        XCTAssertEqual(NexStarConfiguration(preferredTrackingMode: .off).preferredTrackingMode, .altAz)
        XCTAssertEqual(NexStarConfiguration(exchangeTimeoutSeconds: 0.0).exchangeTimeoutSeconds, 1.0, accuracy: 0.0)
        XCTAssertEqual(AlpacaConfiguration(deviceNumber: -4).deviceNumber, 0)
        XCTAssertEqual(AlpacaConfiguration(clientID: 0).clientID, 1)
        XCTAssertEqual(AlpacaConfiguration(exchangeTimeoutSeconds: 1.0e9).exchangeTimeoutSeconds, 60.0, accuracy: 0.0)
    }

    func testErrorsExplainThemselves() {
        let errors: [MountError] = [
            .notConnected, .busy, .slewInProgress, .belowHorizonLimit(altitude: -3.26, limit: 0.0), .mountHorizonLimit,
            .mountOverheadLimit, .outsideMountLimits, .notAligned, .parked, .standby, .notTracking, .notSupported(feature: .sync),
            .hardwareFault(detail: ""), .hardwareFault(detail: "motor 2"), .rejected(detail: ""), .rejected(detail: "tracking"),
            .timeout(operation: "read position"), .slewTimeout(seconds: 300.0), .slewStopped(remainingDegrees: 12.34),
            .syncOffsetTooLarge(offsetDegrees: 45.0, limitDegrees: 30.0), .connectionLost, .transport(detail: "reset"),
            .malformedReply(detail: "position"), .remote(code: 7, detail: ""), .remote(code: 7, detail: "x"),
            .invalidInput(detail: "bad"), .unsupportedCoordinateSystem(code: 4),
        ]
        for error in errors {
            XCTAssertGreaterThan(error.userMessage.count, 10, "\(error)")
            XCTAssertEqual(error.errorDescription, error.userMessage)
            XCTAssertTrue(error.userMessage.hasSuffix("."), error.userMessage)
        }
        XCTAssertEqual(MountError.mountHorizonLimit.userMessage, "The target is below the mount's horizon limit.")
        XCTAssertEqual(MountError.notAligned.userMessage, "The mount is not aligned. Do a star alignment on the mount first, then try again.")
        XCTAssertEqual(MountError.busy.userMessage, "The mount is busy. Try again in a moment.")
        XCTAssertEqual(MountError.belowHorizonLimit(altitude: -3.26, limit: 0.0).userMessage,
                       "The target is at -3.3°, below your altitude limit of 0.0°. Lodestar won't slew there.")
        XCTAssertEqual(MountError.notSupported(feature: .sync).userMessage, "This mount doesn't support syncing to a position.")
        XCTAssertEqual(MountError.slewStopped(remainingDegrees: 12.34).userMessage, "The mount stopped 12.3° short of the target.")
        XCTAssertEqual(MountError.slewTimeout(seconds: 300.0).userMessage, "The slew did not finish within 300 s, so it was stopped.")
        XCTAssertTrue(MountError.timeout(operation: "x").isCommunicationFailure)
        XCTAssertTrue(MountError.transport(detail: "x").isCommunicationFailure)
        XCTAssertTrue(MountError.malformedReply(detail: "x").isCommunicationFailure)
        XCTAssertTrue(MountError.connectionLost.isCommunicationFailure)
        XCTAssertFalse(MountError.busy.isCommunicationFailure)
        XCTAssertFalse(MountError.parked.isCommunicationFailure)
    }

    func testManualClockAndSystemClock() {
        let clock = ManualMountClock(start: Date(timeIntervalSince1970: 1000))
        clock.sleep(seconds: 2.5)
        clock.advance(seconds: 0.5)
        clock.advance(seconds: -10.0)
        clock.advance(seconds: Double.nan)
        clock.advance(seconds: Double.infinity)
        XCTAssertEqual(clock.secondsSince1970, 1003.0, accuracy: 0.0)
        XCTAssertEqual(clock.now(), Date(timeIntervalSince1970: 1003))
        let system = SystemMountClock()
        let before = system.now()
        system.sleep(seconds: 0.01)
        system.sleep(seconds: -1.0)
        system.sleep(seconds: Double.nan)
        XCTAssertGreaterThanOrEqual(system.now(), before)
    }
}
