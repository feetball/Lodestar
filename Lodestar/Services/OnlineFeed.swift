import Foundation
import LodestarKit

/// The optional online data feeds (Settings ▸ Online Data). Every feed is off until the user switches it on, and every
/// screen works without it.
enum OnlineFeed: String, CaseIterable, Identifiable, Sendable {
    /// CelesTrak `stations` and `visual`: the ISS and the other bright satellites.
    case satellites
    /// CelesTrak `starlink`: the streak warning in Aim.
    case starlink
    /// MPC `CometEls.txt`: the comets that join the object catalog.
    case comets
    /// MET Norway Locationforecast 2.0 `complete`: hourly cloud cover.
    case clouds

    var id: String { rawValue }

    /// The name in Settings.
    var title: String {
        switch self {
        case .satellites: return "Satellite passes"
        case .starlink: return "Starlink streak warnings"
        case .comets: return "Comets"
        case .clouds: return "Cloud forecast"
        }
    }

    /// The files this feed downloads.
    var resources: [OnlineResource] { OnlineResource.allCases.filter { $0.feed == self } }
}

/// One downloadable file, with the rules every request for it follows.
enum OnlineResource: String, CaseIterable, Sendable {
    /// Space stations: 21 records, about 9 KB.
    case stations
    /// The brightest satellites: about 160 records, 65 KB.
    case visual
    /// The Starlink constellation: about 11,000 records, 4.7 MB.
    case starlink
    /// The Minor Planet Center's comet elements: about 960 lines, 164 KB, at most once a day.
    case comets
    /// MET Norway's forecast for one grid point: about 64 KB. The server's `Expires` header sets the next request.
    case forecast

    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 24 * 3600
    /// CelesTrak's rule: never download a group more often than this.
    private static let celestrakMinimum = ElementSetGroup.minimumDownloadIntervalHours * hour

    var feed: OnlineFeed {
        switch self {
        case .stations, .visual: return .satellites
        case .starlink: return .starlink
        case .comets: return .comets
        case .forecast: return .clouds
        }
    }

    /// Names the cache file and the bookkeeping entries.
    var key: String {
        switch self {
        case .stations: return "celestrak-stations"
        case .visual: return "celestrak-visual"
        case .starlink: return "celestrak-starlink"
        case .comets: return "mpc-comets"
        case .forecast: return "met-forecast"
        }
    }

    /// The provider's host name, for messages.
    var host: String {
        switch self {
        case .stations, .visual, .starlink: return "celestrak.org"
        case .comets: return "www.minorplanetcenter.net"
        case .forecast: return "api.met.no"
        }
    }

    /// The most bytes a response may have (the download is abandoned beyond it).
    var maximumBytes: Int {
        switch self {
        case .stations: return 512 * 1024
        case .visual: return 1024 * 1024
        case .starlink: return 16 * 1024 * 1024
        case .comets: return 2 * 1024 * 1024
        case .forecast: return 1024 * 1024
        }
    }

    /// How old the data may get before it is downloaded again when the app is used.
    var refreshInterval: TimeInterval {
        switch self {
        case .stations: return ElementSetGroup.stations.refreshIntervalHours * Self.hour
        case .visual: return ElementSetGroup.visual.refreshIntervalHours * Self.hour
        case .starlink: return ElementSetGroup.starlink.refreshIntervalHours * Self.hour
        case .comets: return Self.day
        case .forecast: return Self.hour
        }
    }

    /// The shortest time between two requests after a successful one, for the automatic refresh and for "Update now"
    /// alike.
    var minimumInterval: TimeInterval {
        switch self {
        case .stations, .visual, .starlink: return Self.celestrakMinimum
        case .comets: return Self.day
        case .forecast: return 10 * 60
        }
    }

    /// The shortest time between a failed request and the next one, for a failure the provider answered. See
    /// `OnlineSchedule.retryWait` for the failures that wait less (no answer at all) or more (403, 429, `Retry-After`).
    var retryInterval: TimeInterval {
        switch self {
        case .stations, .visual, .starlink: return Self.celestrakMinimum
        case .comets: return Self.hour
        case .forecast: return 10 * 60
        }
    }

    /// Whether the download waits for a network that is neither expensive (cellular, a personal hotspot) nor in Low
    /// Data Mode.
    var requiresUnmetered: Bool { self == .starlink }

    /// Older data than this (days since its newest element set) is replaced as soon as the request rules allow,
    /// whatever `refreshInterval` says; `nil` for none.
    var staleDataDays: Double? { self == .stations ? 2 : nil }

    /// The CelesTrak group of a satellite resource, or `nil`.
    var group: ElementSetGroup? {
        switch self {
        case .stations: return .stations
        case .visual: return .visual
        case .starlink: return .starlink
        case .comets, .forecast: return nil
        }
    }

    /// The HTTPS address. `latitude` and `longitude` are used by the forecast only and are rounded to
    /// `OnlineCoordinates.stepDegrees` here, whatever the caller passes. `nil` for a forecast without a place.
    func url(latitude: Double? = nil, longitude: Double? = nil) -> URL? {
        switch self {
        case .stations, .visual, .starlink:
            guard let group else { return nil }
            return URL(string: "https://celestrak.org/NORAD/elements/gp.php?\(group.query)")
        case .comets:
            return URL(string: "https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt")
        case .forecast:
            guard let latitude, let longitude else { return nil }
            return URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/complete?"
                       + OnlineCoordinates.query(latitude: latitude, longitude: longitude))
        }
    }
}

/// The coordinates the cloud forecast sends: rounded to 0.1° (about 10 km), which is also MET Norway's cache key.
enum OnlineCoordinates {
    /// The rounding step in degrees.
    static let stepDegrees = 0.1

    /// `degrees` rounded to the step, as text with one decimal and no "-0.0".
    static func rounded(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "0.0" }
        // Half rounds up, as on Android (`Math.round`), so both apps ask for the same grid point.
        let value = (degrees * 10 + 0.5).rounded(.down)
        let text = String(format: "%.1f", value / 10)
        return text == "-0.0" ? "0.0" : text
    }

    /// `lat=..&lon=..` for the request, with the latitude kept within ±90° and the longitude within ±180°.
    static func query(latitude: Double, longitude: Double) -> String {
        let latitude = min(max(latitude, -90), 90)
        var longitude = longitude.truncatingRemainder(dividingBy: 360)
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return "lat=\(rounded(latitude))&lon=\(rounded(longitude))"
    }

    /// Tells two places apart exactly as far as the request does: "32.8,-96.8".
    static func key(latitude: Double, longitude: Double) -> String {
        "\(rounded(latitude)),\(rounded(longitude))"
    }
}

/// What Lodestar says about itself in every request: the app and its version, and where to read about it.
enum OnlineUserAgent {
    /// The support page the User-Agent points to. Never an email address.
    static let supportURL = "https://feetball.github.io/Lodestar/support.html"

    /// `Lodestar/1.0 (+https://feetball.github.io/Lodestar/support.html)`.
    static func make(version: String) -> String {
        "Lodestar/\(version) (+\(supportURL))"
    }

    /// The User-Agent of this build, from `CFBundleShortVersionString`.
    static var current: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return make(version: version ?? "1.0")
    }
}
