import Foundation
import XCTest
@testable import AppCore

/// A server's `Expires` holds the next forecast request back for a day at the most, counted from when the data was saved
/// or requested, whatever date the server names.
final class FixOnlineScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_300_000)
    private let place = "32.8,-96.8"
    private let day = 86_400.0
    /// `Expires: Fri, 01 Jan 2100 00:00:00 GMT`, in seconds after the tests' `now`.
    private var year2100: TimeInterval { 4_102_444_800 - 1_792_300_000 }

    private func state(attempt: TimeInterval, failed: Bool = false, meta: OnlineCacheMeta?) -> OnlineResourceState {
        OnlineResourceState(lastAttempt: now.addingTimeInterval(attempt), lastAttemptFailed: failed, retryWait: nil, meta: meta)
    }

    private func meta(saved: TimeInterval, expires: TimeInterval?) -> OnlineCacheMeta {
        OnlineCacheMeta(savedAt: now.addingTimeInterval(saved), etag: nil, lastModified: nil,
                        expires: expires.map { now.addingTimeInterval($0) }, dataEpoch: nil, key: place)
    }

    func testTheCapIsADay() {
        XCTAssertEqual(OnlineSchedule.maximumExpiresDelay, 86_400)
    }

    func testAnExpiresInTheYear2100BlocksTheForecastForADayOnly() {
        let forecast = state(attempt: -60, meta: meta(saved: -60, expires: year2100))
        let earliest = OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place)
        XCTAssertEqual(earliest, now.addingTimeInterval(-60 + day))
        XCTAssertFalse(OnlineSchedule.mayRequest(.forecast, state: forecast, now: now.addingTimeInterval(day - 61), key: place))
        XCTAssertTrue(OnlineSchedule.mayRequest(.forecast, state: forecast, now: now.addingTimeInterval(day - 60), key: place))
    }

    func testTheNextUpdateShownInSettingsIsNotInTheYear2100() {
        // `OnlineDataService.publishStatus` shows `earliestRequest`, with a jitter of up to five minutes.
        let forecast = state(attempt: -60, meta: meta(saved: -60, expires: year2100))
        let earliest = OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place, expiresJitter: 299)
        XCTAssertLessThanOrEqual(earliest.timeIntervalSince(now), day)
    }

    func testAnExpiresWithinTheDayIsFollowedAsBefore() {
        for hours in [1.0, 6.0, 23.0] {
            let forecast = state(attempt: -60, meta: meta(saved: -60, expires: hours * 3600))
            XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                           now.addingTimeInterval(hours * 3600), "\(hours) h")
        }
    }

    func testAnExpiresJustBeyondTheCapIsCut() {
        let forecast = state(attempt: -60, meta: meta(saved: -60, expires: -60 + day + 1))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                       now.addingTimeInterval(-60 + day))
    }

    func testTheJitterCannotPushAnExpiresPastTheCap() {
        let forecast = state(attempt: -60, meta: meta(saved: -60, expires: -60 + day - 60))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place, expiresJitter: 120),
                       now.addingTimeInterval(-60 + day))
    }

    func testTheCapCountsFromTheSaveNotFromALaterFailedRequest() {
        // Saved two hours ago, and a request ten minutes ago failed: the cap does not slide with the failed attempt.
        let forecast = state(attempt: -600, failed: true, meta: meta(saved: -7200, expires: year2100))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                       now.addingTimeInterval(-7200 + day))
    }

    func testASavedTimeFromTheFutureDoesNotLiftTheCap() {
        // The clock was set back after the data was saved: the saved time is a month ahead, the attempt is not.
        let forecast = state(attempt: -60, meta: meta(saved: 30 * day, expires: year2100))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                       now.addingTimeInterval(-60 + day))
    }

    func testTheCapDoesNotMakeTheRequestRulesShorter() {
        // A retry wait that is longer than the cap still holds.
        let forecast = OnlineResourceState(lastAttempt: now.addingTimeInterval(-60), lastAttemptFailed: true,
                                           retryWait: 2 * day, meta: meta(saved: -60, expires: year2100))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                       now.addingTimeInterval(-60 + 2 * day))
    }

    func testOtherFeedsStillIgnoreExpires() {
        let stations = OnlineResourceState(lastAttempt: now.addingTimeInterval(-60), lastAttemptFailed: false, retryWait: nil,
                                           meta: meta(saved: -60, expires: year2100))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.stations, state: stations, now: now),
                       now.addingTimeInterval(-60 + 7200))
    }
}
