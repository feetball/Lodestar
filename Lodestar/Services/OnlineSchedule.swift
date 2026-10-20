import Foundation

/// What the schedule knows about one resource.
struct OnlineResourceState: Sendable {
    /// When it was last requested, successful or not.
    var lastAttempt: Date?
    /// Whether that request failed.
    var lastAttemptFailed: Bool
    /// How long to wait after that failed request (`OnlineSchedule.retryWait`); `nil` for the resource's
    /// `retryInterval`, which is also what a failure recorded by an older version of the app gets.
    var retryWait: TimeInterval?
    /// The cached data's metadata, `nil` without data.
    var meta: OnlineCacheMeta?
}

/// The rules for when a resource may be requested and when it is due. Pure.
///
/// - Never two requests closer than `OnlineResource.minimumInterval` (after a success) or the retry wait (after a
///   failure): for CelesTrak 2 hours, which is `ElementSetGroup.minimumDownloadIntervalHours`. "Update now" follows the
///   same rule.
/// - A forecast of the same place also waits for the server's `Expires`, for a day at the most. Only the forecast does:
///   for the other feeds the refresh interval decides.
/// - Data is due when there is none, when it is for another place, when it is older than the refresh interval, when the
///   forecast's `Expires` has passed, or when its newest orbit epoch is older than `OnlineResource.staleDataDays`.
/// - A time stamp from the future (the clock was set back since it was written) counts for nothing, so that a wrong
///   date cannot block the downloads until the clock catches up.
enum OnlineSchedule {
    /// After a request that got no answer (no route, a time-out) the next one may follow after this long at the most:
    /// the provider did not see the request, so none of its allowance was used, and the user should not wait hours.
    static let transportRetryInterval: TimeInterval = 10 * 60
    /// After a 403 or 429 the next request waits at least this long, whatever the resource's own retry interval says.
    static let blockedRetryInterval: TimeInterval = 3600
    /// The longest wait a `Retry-After` header can ask for.
    static let maximumRetryAfter: TimeInterval = 24 * 3600
    /// The longest a server's `Expires` can hold back the next request, counted from when the data was saved or requested.
    static let maximumExpiresDelay: TimeInterval = 24 * 3600
    /// How far in the future a time stamp may be before it is taken as a clock that was set back (a small step of the
    /// clock is normal).
    static let clockSlack: TimeInterval = 5 * 60

    /// How long to wait after a request of `resource` failed with `failure`. `retryAfter` is the server's `Retry-After`
    /// in seconds, if it sent one. The wait is relative to the attempt, so that it does not depend on the clock.
    static func retryWait(_ resource: OnlineResource, after failure: OnlineFailure, retryAfter: TimeInterval?) -> TimeInterval {
        var wait = resource.retryInterval
        switch failure {
        case .network, .timeout: wait = min(wait, transportRetryInterval)
        case .forbidden, .rateLimited: wait = max(wait, blockedRetryInterval)
        default: break
        }
        if let retryAfter, retryAfter.isFinite { wait = max(wait, min(retryAfter, maximumRetryAfter)) }
        return wait
    }

    /// The earliest time a request is allowed; `.distantPast` when there is no restriction. `key` is the wanted copy.
    /// `expiresJitter` is added to a server's `Expires` so that the installations of the app do not all ask at the same
    /// minute (MET Norway asks for that).
    static func earliestRequest(_ resource: OnlineResource, state: OnlineResourceState, now: Date, key: String? = nil,
                                expiresJitter: TimeInterval = 0) -> Date {
        guard let last = state.lastAttempt, last <= now.addingTimeInterval(clockSlack) else { return .distantPast }
        let interval = state.lastAttemptFailed ? (state.retryWait ?? resource.retryInterval) : resource.minimumInterval
        var earliest = last.addingTimeInterval(interval)
        if resource == .forecast, let meta = state.meta, meta.key == key, let expires = meta.expires {
            // A date far in the future (a wrong server, `Expires` in the year 2100) cannot block the forecast for good.
            let ceiling = min(meta.savedAt, last).addingTimeInterval(maximumExpiresDelay)
            earliest = max(earliest, min(expires.addingTimeInterval(expiresJitter), ceiling))
        }
        return earliest
    }

    /// Whether a request is allowed at `now`.
    static func mayRequest(_ resource: OnlineResource, state: OnlineResourceState, now: Date, key: String? = nil,
                           expiresJitter: TimeInterval = 0) -> Bool {
        now >= earliestRequest(resource, state: state, now: now, key: key, expiresJitter: expiresJitter)
    }

    /// Whether the data should be replaced at `now`, ignoring the request rules.
    static func isDue(_ resource: OnlineResource, state: OnlineResourceState, now: Date, key: String? = nil) -> Bool {
        guard let meta = state.meta else { return true }
        if let key, meta.key != key { return true }
        if meta.savedAt > now.addingTimeInterval(clockSlack) { return true }
        if now.timeIntervalSince(meta.savedAt) >= resource.refreshInterval { return true }
        // A server that says when its data expires (MET Norway) decides: the data is due as soon as it has expired.
        if resource == .forecast, let expires = meta.expires, now >= expires { return true }
        if let days = resource.staleDataDays, let epoch = meta.dataEpoch, now.timeIntervalSince(epoch) >= days * 86_400 {
            return true
        }
        return false
    }

    /// Whether the automatic refresh should request now: due and allowed.
    static func shouldRefresh(_ resource: OnlineResource, state: OnlineResourceState, now: Date, key: String? = nil,
                              expiresJitter: TimeInterval = 0) -> Bool {
        isDue(resource, state: state, now: now, key: key)
            && mayRequest(resource, state: state, now: now, key: key, expiresJitter: expiresJitter)
    }
}
