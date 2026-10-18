import Foundation

/// The words of Settings ▸ Online Data. The Android app uses the same texts.
enum OnlineText {
    static let sectionTitle = "Online Data"

    static let intro = "Lodestar works fully offline. These optional downloads add satellite passes, streak warnings, "
        + "comets and a cloud forecast. Everything is off until you switch it on, and every screen stays usable "
        + "without the data."

    static let footer = "Switching a feed off deletes what it downloaded. A failed download keeps the data you already "
        + "have. Nothing runs in the background: feeds refresh when you open the app. Each request carries only the "
        + "app's name and version."

    static let firstTimeTitle = "Online data is optional"

    static let firstTimeBody = "Lodestar works fully offline, and every screen stays usable without these downloads. "
        + "When you switch a feed on, Lodestar makes an ordinary HTTPS request to the provider named under it. The "
        + "provider sees your IP address and the app's name and version. Only the cloud forecast also sends "
        + "your location, rounded to about 10 km. Switching a feed off deletes what it downloaded."

    static let firstTimeConfirm = "Turn on"
    static let firstTimeCancel = "Not now"
    static let updateNow = "Update now"
    static let updating = "Updating\u{2026}"
    static let never = "Never"

    /// What the feed is for.
    static func purpose(_ feed: OnlineFeed) -> String {
        switch feed {
        case .satellites:
            return "Shows when the ISS and other bright satellites cross your sky, on the Tonight screen and in Aim."
        case .starlink:
            return "Warns in Aim when Starlink satellites are likely to cross your frame during an exposure."
        case .comets:
            return "Adds the current comets to the object list, the sky chart and Aim."
        case .clouds:
            return "Shows tonight's hourly cloud cover on the Tonight screen."
        }
    }

    /// What leaves the phone: the provider, the size and how often.
    static func leavesPhone(_ feed: OnlineFeed) -> String {
        switch feed {
        case .satellites:
            return "Downloads orbit data for the ISS and other bright satellites from CelesTrak (celestrak.org): about "
                + "75 KB, at most every 12 to 24 hours while you use the app. CelesTrak sees your IP address."
        case .starlink:
            return "Downloads orbit data for the Starlink satellites from CelesTrak (celestrak.org): about 4.7 MB, "
                + "once a day, only on an unmetered network such as Wi-Fi. CelesTrak sees your IP address."
        case .comets:
            return "Downloads the comet orbit file from the Minor Planet Center (minorplanetcenter.net): about 164 KB, "
                + "at most once a day. The Minor Planet Center sees your IP address."
        case .clouds:
            return "Requests the forecast from MET Norway (api.met.no) with your location rounded to 0.1\u{00B0} "
                + "(about 10 km): about 64 KB, no more often than MET Norway allows. MET Norway sees your IP address "
                + "and the rounded location."
        }
    }

    /// How long ago the data was confirmed current: "Just now", "5 min ago", "2 h ago", "3 days ago", or "Never".
    static func since(_ last: Date?, now: Date) -> String {
        guard let last else { return never }
        let minutes = Int(max(now.timeIntervalSince(last), 0) / 60)
        switch minutes {
        case ..<1: return "Just now"
        case ..<60: return "\(minutes) min ago"
        case ..<(48 * 60): return "\(minutes / 60) h ago"
        default: return "\(minutes / (24 * 60)) days ago"
        }
    }

    /// "Next update possible after 16:30."
    static func nextUpdate(_ timeText: String) -> String { "Next update possible after \(timeText)." }
}
