import Foundation

/// The CelesTrak GP groups the satellite features use, with the freshness limits the app should apply. The engine
/// itself never downloads anything: the app fetches `https://celestrak.org/NORAD/elements/gp.php?<query>` and hands
/// the bytes to `ElementSetParser.parseJson`.
///
/// CelesTrak refreshes each group about every two hours and answers a request for unchanged data with HTTP 403,
/// so do not download a group more often than `minimumDownloadIntervalHours`.
public enum ElementSetGroup: String, CaseIterable, Hashable, Sendable {
    /// Space stations (ISS, Tiangong and visiting vehicles): the bright, predictable targets.
    case stations
    /// The brightest satellites and rocket bodies (about 150): the "visual" group.
    case visual
    /// The Starlink constellation: for the streak warning.
    case starlink

    /// The shortest sensible time between two downloads of the same group, in hours.
    public static let minimumDownloadIntervalHours = 2.0

    /// The `GROUP=` value of the CelesTrak query (same as `rawValue`).
    public var groupName: String { rawValue }

    /// Elements older than this (days from epoch to now) are too old for predictions that must be right to a few
    /// seconds; show a warning or refresh.
    public var maximumAgeDays: Double {
        switch self {
        case .stations: 3.0
        case .visual: 7.0
        case .starlink: 3.0
        }
    }

    /// How often to download a fresh copy while the screen is in use.
    public var refreshIntervalHours: Double {
        switch self {
        case .stations: 12.0
        case .visual: 24.0
        case .starlink: 24.0
        }
    }

    /// About how many element sets the group holds (2026), for sizing the cache.
    public var typicalRecordCount: Int {
        switch self {
        case .stations: 25
        case .visual: 160
        case .starlink: 11_000
        }
    }

    /// The query string for the GP endpoint, e.g. `GROUP=stations&FORMAT=json`.
    public var query: String { "GROUP=\(rawValue)&FORMAT=json" }

    /// `true` when `elements` is at most `maximumAgeDays` old at `date` (a future epoch counts as fresh).
    public func isFresh(_ elements: OrbitalElements, at date: Date) -> Bool {
        elements.ageDays(date) <= maximumAgeDays
    }
}
