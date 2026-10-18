import Foundation

/// What the schedule knows about one resource.
struct OnlineResourceState: Sendable {
    /// When it was last requested, successful or not.
    var lastAttempt: Date?
    /// Whether that request failed.
    var lastAttemptFailed: Bool
    /// The cached data's metadata, `nil` without data.
    var meta: OnlineCacheMeta?
}

/// The rules for when a resource may be requested and when it is due. Pure.
///
/// - Never two requests closer than `OnlineResource.minimumInterval` (after a success) or `retryInterval` (after a
///   failure): for CelesTrak 2 hours, which is `ElementSetGroup.minimumDownloadIntervalHours`. "Update now" follows the
///   same rule.
/// - A forecast of the same place also waits for the server's `Expires`.
/// - Data is due when there is none, when it is for another place, when it is older than the refresh interval, when the
///   server's `Expires` has passed, or when its newest orbit epoch is older than `OnlineResource.staleDataDays`.
enum OnlineSchedule {
    /// The earliest time a request is allowed; `.distantPast` when there is no restriction. `key` is the wanted copy.
    /// `expiresJitter` is added to a server's `Expires` so that the installations of the app do not all ask at the same
    /// minute (MET Norway asks for that).
    static func earliestRequest(_ resource: OnlineResource, state: OnlineResourceState, key: String? = nil,
                                expiresJitter: TimeInterval = 0) -> Date {
        guard let last = state.lastAttempt else { return .distantPast }
        let interval = state.lastAttemptFailed ? resource.retryInterval : resource.minimumInterval
        var earliest = last.addingTimeInterval(interval)
        if let meta = state.meta, meta.key == key, let expires = meta.expires {
            earliest = max(earliest, expires.addingTimeInterval(expiresJitter))
        }
        return earliest
    }

    /// Whether a request is allowed at `now`.
    static func mayRequest(_ resource: OnlineResource, state: OnlineResourceState, now: Date, key: String? = nil,
                           expiresJitter: TimeInterval = 0) -> Bool {
        now >= earliestRequest(resource, state: state, key: key, expiresJitter: expiresJitter)
    }

    /// Whether the data should be replaced at `now`, ignoring the request rules.
    static func isDue(_ resource: OnlineResource, state: OnlineResourceState, now: Date, key: String? = nil) -> Bool {
        guard let meta = state.meta else { return true }
        if let key, meta.key != key { return true }
        if now.timeIntervalSince(meta.savedAt) >= resource.refreshInterval { return true }
        // A server that says when its data expires (MET Norway) decides: the data is due as soon as it has expired.
        if let expires = meta.expires, now >= expires { return true }
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
