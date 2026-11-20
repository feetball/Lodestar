import Foundation
import XCTest
@testable import AppCore

/// When a resource may be requested and when its data is due (`OnlineSchedule`), with a fixed "now".
final class OnlineScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_300_000)
    private let place = "32.8,-96.8"

    /// A state whose last attempt was `attempt` seconds after `now` (negative: before), without data unless `meta` is given.
    private func state(attempt: TimeInterval? = nil, failed: Bool = false, wait: TimeInterval? = nil,
                       meta: OnlineCacheMeta? = nil) -> OnlineResourceState {
        OnlineResourceState(lastAttempt: attempt.map { now.addingTimeInterval($0) }, lastAttemptFailed: failed,
                            retryWait: wait, meta: meta)
    }

    /// Cache metadata saved `saved` seconds after `now`.
    private func meta(saved: TimeInterval, expires: TimeInterval? = nil, epoch: TimeInterval? = nil,
                      key: String? = nil) -> OnlineCacheMeta {
        OnlineCacheMeta(savedAt: now.addingTimeInterval(saved), etag: nil, lastModified: nil,
                        expires: expires.map { now.addingTimeInterval($0) },
                        dataEpoch: epoch.map { now.addingTimeInterval($0) }, key: key)
    }

    // MARK: Constants

    func testTheConstantsOfTheRules() {
        XCTAssertEqual(OnlineSchedule.transportRetryInterval, 600)
        XCTAssertEqual(OnlineSchedule.blockedRetryInterval, 3600)
        XCTAssertEqual(OnlineSchedule.maximumRetryAfter, 86_400)
        XCTAssertEqual(OnlineSchedule.clockSlack, 300)
    }

    // MARK: Retry wait

    func testAnAnsweredFailureWaitsTheResourcesOwnRetryInterval() {
        for failure in [OnlineFailure.httpError, .tooLarge, .empty, .unreadable, .storage, .interrupted] {
            XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: failure, retryAfter: nil), 7200, "\(failure)")
            XCTAssertEqual(OnlineSchedule.retryWait(.starlink, after: failure, retryAfter: nil), 7200, "\(failure)")
            XCTAssertEqual(OnlineSchedule.retryWait(.comets, after: failure, retryAfter: nil), 3600, "\(failure)")
            XCTAssertEqual(OnlineSchedule.retryWait(.forecast, after: failure, retryAfter: nil), 600, "\(failure)")
        }
    }

    func testNoAnswerAtAllWaitsTenMinutesAtTheMost() {
        for failure in [OnlineFailure.network, .timeout] {
            XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: failure, retryAfter: nil), 600, "\(failure)")
            XCTAssertEqual(OnlineSchedule.retryWait(.visual, after: failure, retryAfter: nil), 600, "\(failure)")
            XCTAssertEqual(OnlineSchedule.retryWait(.comets, after: failure, retryAfter: nil), 600, "\(failure)")
            XCTAssertEqual(OnlineSchedule.retryWait(.forecast, after: failure, retryAfter: nil), 600, "\(failure)")
        }
    }

    func testABlockedRequestWaitsAnHourAtLeast() {
        for failure in [OnlineFailure.forbidden, .rateLimited] {
            XCTAssertEqual(OnlineSchedule.retryWait(.forecast, after: failure, retryAfter: nil), 3600, "\(failure)")
            XCTAssertEqual(OnlineSchedule.retryWait(.comets, after: failure, retryAfter: nil), 3600, "\(failure)")
            // The CelesTrak interval is already longer than an hour.
            XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: failure, retryAfter: nil), 7200, "\(failure)")
        }
    }

    func testRetryAfterLengthensTheWait() {
        XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: .httpError, retryAfter: 10_800), 10_800)
        XCTAssertEqual(OnlineSchedule.retryWait(.forecast, after: .rateLimited, retryAfter: 7200), 7200)
        // It also overrides the short wait after a failure without an answer.
        XCTAssertEqual(OnlineSchedule.retryWait(.forecast, after: .network, retryAfter: 1800), 1800)
    }

    func testRetryAfterNeverShortensTheWait() {
        XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: .httpError, retryAfter: 1000), 7200)
        XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: .httpError, retryAfter: 0), 7200)
        XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: .httpError, retryAfter: -50), 7200)
        XCTAssertEqual(OnlineSchedule.retryWait(.comets, after: .forbidden, retryAfter: 60), 3600)
    }

    func testRetryAfterIsCappedAtADay() {
        XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: .rateLimited, retryAfter: 86_400), 86_400)
        XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: .rateLimited, retryAfter: 86_401), 86_400)
        XCTAssertEqual(OnlineSchedule.retryWait(.forecast, after: .rateLimited, retryAfter: 1e12), 86_400)
    }

    func testANonFiniteRetryAfterIsIgnored() {
        XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: .httpError, retryAfter: .infinity), 7200)
        XCTAssertEqual(OnlineSchedule.retryWait(.stations, after: .httpError, retryAfter: .nan), 7200)
        XCTAssertEqual(OnlineSchedule.retryWait(.forecast, after: .network, retryAfter: .infinity), 600)
    }

    // MARK: Earliest request

    func testWithoutAnAttemptThereIsNoRestriction() {
        XCTAssertEqual(OnlineSchedule.earliestRequest(.stations, state: state(), now: now), .distantPast)
        XCTAssertTrue(OnlineSchedule.mayRequest(.stations, state: state(), now: now))
    }

    func testAfterASuccessTheMinimumIntervalApplies() {
        let last = -100.0
        XCTAssertEqual(OnlineSchedule.earliestRequest(.stations, state: state(attempt: last), now: now),
                       now.addingTimeInterval(last + 7200))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.visual, state: state(attempt: last), now: now),
                       now.addingTimeInterval(last + 7200))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.starlink, state: state(attempt: last), now: now),
                       now.addingTimeInterval(last + 7200))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.comets, state: state(attempt: last), now: now),
                       now.addingTimeInterval(last + 86_400))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: state(attempt: last), now: now),
                       now.addingTimeInterval(last + 600))
    }

    func testAfterAFailureTheRetryIntervalApplies() {
        let last = -100.0
        XCTAssertEqual(OnlineSchedule.earliestRequest(.comets, state: state(attempt: last, failed: true), now: now),
                       now.addingTimeInterval(last + 3600))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: state(attempt: last, failed: true), now: now),
                       now.addingTimeInterval(last + 600))
    }

    func testARecordedRetryWaitReplacesTheRetryInterval() {
        let last = -100.0
        XCTAssertEqual(OnlineSchedule.earliestRequest(.comets, state: state(attempt: last, failed: true, wait: 1234), now: now),
                       now.addingTimeInterval(last + 1234))
        // A recorded wait is only used after a failure.
        XCTAssertEqual(OnlineSchedule.earliestRequest(.comets, state: state(attempt: last, failed: false, wait: 1234), now: now),
                       now.addingTimeInterval(last + 86_400))
    }

    func testMayRequestIsTrueFromTheEarliestSecondOn() {
        let attempt = state(attempt: -7200)
        // Allowed exactly 7200 seconds after the attempt, which is now.
        XCTAssertTrue(OnlineSchedule.mayRequest(.stations, state: attempt, now: now))
        XCTAssertFalse(OnlineSchedule.mayRequest(.stations, state: attempt, now: now.addingTimeInterval(-1)))
        XCTAssertTrue(OnlineSchedule.mayRequest(.stations, state: attempt, now: now.addingTimeInterval(1)))
    }

    func testTwoHourRuleHoldsForEveryCelesTrakGroup() {
        for resource in [OnlineResource.stations, .visual, .starlink] {
            let attempt = state(attempt: -7199)
            XCTAssertFalse(OnlineSchedule.mayRequest(resource, state: attempt, now: now), "\(resource)")
            XCTAssertTrue(OnlineSchedule.mayRequest(resource, state: state(attempt: -7200), now: now), "\(resource)")
        }
    }

    func testAnAttemptFromTheFutureCountsForNothing() {
        // 301 s ahead is more than the slack of 300 s: the clock was set back.
        let future = state(attempt: 301)
        XCTAssertEqual(OnlineSchedule.earliestRequest(.stations, state: future, now: now), .distantPast)
        XCTAssertTrue(OnlineSchedule.mayRequest(.stations, state: future, now: now))
        let farFuture = state(attempt: 86_400 * 30, failed: true)
        XCTAssertTrue(OnlineSchedule.mayRequest(.comets, state: farFuture, now: now))
    }

    func testAnAttemptWithinTheClockSlackStillCounts() {
        let slightlyAhead = state(attempt: 300)
        XCTAssertEqual(OnlineSchedule.earliestRequest(.stations, state: slightlyAhead, now: now),
                       now.addingTimeInterval(300 + 7200))
        XCTAssertFalse(OnlineSchedule.mayRequest(.stations, state: slightlyAhead, now: now))
    }

    // MARK: Forecast Expires

    func testTheForecastWaitsForExpiresOfTheSamePlace() {
        let forecast = state(attempt: -60, meta: meta(saved: -60, expires: 3000, key: place))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                       now.addingTimeInterval(3000))
        XCTAssertFalse(OnlineSchedule.mayRequest(.forecast, state: forecast, now: now.addingTimeInterval(2999), key: place))
        XCTAssertTrue(OnlineSchedule.mayRequest(.forecast, state: forecast, now: now.addingTimeInterval(3000), key: place))
    }

    func testTheJitterIsAddedToExpires() {
        let forecast = state(attempt: -60, meta: meta(saved: -60, expires: 3000, key: place))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place, expiresJitter: 120),
                       now.addingTimeInterval(3120))
        XCTAssertFalse(OnlineSchedule.mayRequest(.forecast, state: forecast, now: now.addingTimeInterval(3119), key: place,
                                                 expiresJitter: 120))
    }

    func testAnExpiresBeforeTheMinimumIntervalChangesNothing() {
        let forecast = state(attempt: -60, meta: meta(saved: -60, expires: 100, key: place))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                       now.addingTimeInterval(-60 + 600))
    }

    func testTheExpiresOfAnotherPlaceIsIgnored() {
        let forecast = state(attempt: -60, meta: meta(saved: -60, expires: 3000, key: "10.0,20.0"))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                       now.addingTimeInterval(-60 + 600))
        // Without a wanted key the cached copy is not the wanted one either.
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now),
                       now.addingTimeInterval(-60 + 600))
    }

    func testAForecastWithoutExpiresFollowsTheMinimumInterval() {
        let forecast = state(attempt: -60, meta: meta(saved: -60, key: place))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place),
                       now.addingTimeInterval(-60 + 600))
    }

    func testOtherFeedsIgnoreExpires() {
        let stations = state(attempt: -60, meta: meta(saved: -60, expires: 99_999))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.stations, state: stations, now: now),
                       now.addingTimeInterval(-60 + 7200))
        let comets = state(attempt: -60, meta: meta(saved: -60, expires: 99_999))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.comets, state: comets, now: now),
                       now.addingTimeInterval(-60 + 86_400))
    }

    func testAnExpiresWithoutAnAttemptDoesNotBlock() {
        let forecast = state(meta: meta(saved: -60, expires: 3000, key: place))
        XCTAssertEqual(OnlineSchedule.earliestRequest(.forecast, state: forecast, now: now, key: place), .distantPast)
    }

    // MARK: Due

    func testWithoutDataTheResourceIsDue() {
        for resource in OnlineResource.allCases {
            XCTAssertTrue(OnlineSchedule.isDue(resource, state: state(), now: now), "\(resource)")
        }
    }

    func testDataIsDueOnceItIsAsOldAsTheRefreshInterval() {
        let cases: [(OnlineResource, TimeInterval)] = [
            (.stations, 12 * 3600), (.visual, 24 * 3600), (.starlink, 24 * 3600), (.comets, 24 * 3600), (.forecast, 3600),
        ]
        for (resource, interval) in cases {
            let justFresh = state(meta: meta(saved: -(interval - 1)))
            let justDue = state(meta: meta(saved: -interval))
            XCTAssertFalse(OnlineSchedule.isDue(resource, state: justFresh, now: now), "\(resource)")
            XCTAssertTrue(OnlineSchedule.isDue(resource, state: justDue, now: now), "\(resource)")
        }
    }

    func testDataForAnotherPlaceIsDue() {
        let cached = state(meta: meta(saved: -10, key: "10.0,20.0"))
        XCTAssertTrue(OnlineSchedule.isDue(.forecast, state: cached, now: now, key: place))
        XCTAssertFalse(OnlineSchedule.isDue(.forecast, state: cached, now: now, key: "10.0,20.0"))
    }

    func testAKeylessCopyIsDueWhenAKeyIsWanted() {
        XCTAssertTrue(OnlineSchedule.isDue(.forecast, state: state(meta: meta(saved: -10)), now: now, key: place))
    }

    func testWithoutAWantedKeyTheCopyIsNotCompared() {
        XCTAssertFalse(OnlineSchedule.isDue(.forecast, state: state(meta: meta(saved: -10, key: place)), now: now))
    }

    func testSavedTimeFromTheFutureIsDue() {
        // More than the slack ahead: the clock was set back since it was written.
        XCTAssertTrue(OnlineSchedule.isDue(.comets, state: state(meta: meta(saved: 301)), now: now))
        XCTAssertTrue(OnlineSchedule.isDue(.comets, state: state(meta: meta(saved: 86_400 * 100)), now: now))
        // Within the slack the data is as fresh as it looks.
        XCTAssertFalse(OnlineSchedule.isDue(.comets, state: state(meta: meta(saved: 300)), now: now))
        XCTAssertFalse(OnlineSchedule.isDue(.comets, state: state(meta: meta(saved: 1)), now: now))
    }

    func testAForecastIsDueOnceItsExpiresHasPassed() {
        let before = state(meta: meta(saved: -100, expires: 1, key: place))
        let at = state(meta: meta(saved: -100, expires: 0, key: place))
        let after = state(meta: meta(saved: -100, expires: -1, key: place))
        XCTAssertFalse(OnlineSchedule.isDue(.forecast, state: before, now: now, key: place))
        XCTAssertTrue(OnlineSchedule.isDue(.forecast, state: at, now: now, key: place))
        XCTAssertTrue(OnlineSchedule.isDue(.forecast, state: after, now: now, key: place))
    }

    func testOnlyTheForecastIsDueByExpires() {
        let expired = state(meta: meta(saved: -100, expires: -50))
        XCTAssertFalse(OnlineSchedule.isDue(.comets, state: expired, now: now))
        XCTAssertFalse(OnlineSchedule.isDue(.stations, state: expired, now: now))
    }

    func testStationsWithOldOrbitsAreDueWhateverTheirSavedTime() {
        let twoDays = 2 * 86_400.0
        let old = state(meta: meta(saved: -100, epoch: -twoDays))
        let nearlyOld = state(meta: meta(saved: -100, epoch: -(twoDays - 1)))
        XCTAssertTrue(OnlineSchedule.isDue(.stations, state: old, now: now))
        XCTAssertFalse(OnlineSchedule.isDue(.stations, state: nearlyOld, now: now))
    }

    func testStationsWithoutAnEpochAreNotDueByTheStaleLimit() {
        XCTAssertFalse(OnlineSchedule.isDue(.stations, state: state(meta: meta(saved: -100)), now: now))
    }

    func testOtherResourcesHaveNoStaleDataLimit() {
        let ancient = meta(saved: -100, epoch: -86_400 * 365)
        XCTAssertFalse(OnlineSchedule.isDue(.visual, state: state(meta: ancient), now: now))
        XCTAssertFalse(OnlineSchedule.isDue(.starlink, state: state(meta: ancient), now: now))
    }

    // MARK: Should refresh

    func testRefreshNeedsDataThatIsDueAndARequestThatIsAllowed() {
        // Due (12 hours old) and allowed (last request three hours ago).
        let dueAndAllowed = state(attempt: -3 * 3600, meta: meta(saved: -12 * 3600))
        XCTAssertTrue(OnlineSchedule.shouldRefresh(.stations, state: dueAndAllowed, now: now))
        // Due, but the last request was 10 minutes ago.
        let dueButTooSoon = state(attempt: -600, meta: meta(saved: -12 * 3600))
        XCTAssertFalse(OnlineSchedule.shouldRefresh(.stations, state: dueButTooSoon, now: now))
        // Allowed, but the data is one hour old.
        let allowedButFresh = state(attempt: -3 * 3600, meta: meta(saved: -3600))
        XCTAssertFalse(OnlineSchedule.shouldRefresh(.stations, state: allowedButFresh, now: now))
    }

    func testFirstUseRefreshesAtOnce() {
        XCTAssertTrue(OnlineSchedule.shouldRefresh(.comets, state: state(), now: now))
    }

    func testAFailedRequestIsRetriedAfterItsWaitEvenWithoutData() {
        let failed = state(attempt: -3601, failed: true)
        XCTAssertTrue(OnlineSchedule.shouldRefresh(.comets, state: failed, now: now))
        let tooSoon = state(attempt: -3599, failed: true)
        XCTAssertFalse(OnlineSchedule.shouldRefresh(.comets, state: tooSoon, now: now))
    }

    func testTheForecastIsNotRefreshedBeforeExpiresEvenWhenAnHourOld() {
        // Saved an hour ago, last asked an hour ago, but the server said "not before 10 minutes from now".
        let forecast = state(attempt: -3600, meta: meta(saved: -3600, expires: 600, key: place))
        XCTAssertFalse(OnlineSchedule.shouldRefresh(.forecast, state: forecast, now: now, key: place))
        XCTAssertTrue(OnlineSchedule.shouldRefresh(.forecast, state: forecast, now: now.addingTimeInterval(600), key: place))
    }

    func testTheForecastJitterDelaysTheRefresh() {
        let forecast = state(attempt: -3600, meta: meta(saved: -3600, expires: -10, key: place))
        XCTAssertTrue(OnlineSchedule.shouldRefresh(.forecast, state: forecast, now: now, key: place))
        XCTAssertFalse(OnlineSchedule.shouldRefresh(.forecast, state: forecast, now: now, key: place, expiresJitter: 11))
        XCTAssertTrue(OnlineSchedule.shouldRefresh(.forecast, state: forecast, now: now, key: place, expiresJitter: 10))
    }

    func testAWrongClockCannotBlockTheDownloads() {
        // Both time stamps were written while the clock was a month ahead.
        let month = 86_400.0 * 30
        let forecast = state(attempt: month, meta: meta(saved: month, expires: month + 3600, key: place))
        XCTAssertTrue(OnlineSchedule.shouldRefresh(.forecast, state: forecast, now: now, key: place))
        let stations = state(attempt: month, meta: meta(saved: month))
        XCTAssertTrue(OnlineSchedule.shouldRefresh(.stations, state: stations, now: now))
    }

    // MARK: Resource state

    func testTheStateKeepsWhatItWasGiven() {
        let value = OnlineResourceState(lastAttempt: now, lastAttemptFailed: true, retryWait: 42, meta: nil)
        XCTAssertEqual(value.lastAttempt, now)
        XCTAssertTrue(value.lastAttemptFailed)
        XCTAssertEqual(value.retryWait, 42)
        XCTAssertNil(value.meta)
    }
}
