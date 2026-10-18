import Foundation
import LodestarKit

/// The period a list of bright comets covers.
enum SmallBodyListPeriod: String, CaseIterable, Identifiable, Sendable {
    /// Bright at this moment.
    case now
    /// Brightest at some point in the next 31 days, with the date it is brightest.
    case thisMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Now"
        case .thisMonth: return "This month"
        }
    }
}

/// Which bodies a list shows.
enum SmallBodyListKind: String, CaseIterable, Identifiable, Sendable {
    case comets, asteroids, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comets: return "Comets"
        case .asteroids: return "Asteroids"
        case .both: return "Both"
        }
    }

    /// The kind the engine filters by; `nil` for both.
    var kind: SmallBodyKind? {
        switch self {
        case .comets: return .comet
        case .asteroids: return .asteroid
        case .both: return nil
        }
    }

    /// "comet", "asteroid" or "comet or asteroid", for the empty state.
    var noun: String {
        switch self {
        case .comets: return "comet"
        case .asteroids: return "asteroid"
        case .both: return "comet or asteroid"
        }
    }
}

/// A magnitude limit the lists offer, and what it is good for.
enum SmallBodyMagnitudeLimit: Double, CaseIterable, Identifiable, Sendable {
    case nakedEye = 6
    case binoculars = 8
    case camera = 10

    /// Ten, for a camera on a tripod.
    static let `default` = SmallBodyMagnitudeLimit.camera

    var id: Double { rawValue }

    var value: Double { rawValue }

    var title: String { "Mag \(Int(rawValue))" }

    var caption: String {
        switch self {
        case .nakedEye: return "Naked-eye brightness"
        case .binoculars: return "Binoculars or a wide-field camera"
        case .camera: return "A camera on a tripod"
        }
    }
}

/// One row of a list: the catalog object, how bright it gets and where it stands then.
struct SmallBodyListEntry: Sendable, Identifiable, Equatable {
    let object: CelestialObject
    let bright: BrightSmallBody
    /// The state at the moment of the peak: for `SmallBodyListPeriod.now` that is now.
    let info: SmallBodyInfo

    init(object: CelestialObject, bright: BrightSmallBody) {
        self.object = object
        self.bright = bright
        info = SmallBodyInfo.of(bright.peak)
    }

    var id: String { object.id }
    var peakDate: Date { bright.peakDate }
}

/// Which comets and asteroids are bright now and this month (`SmallBodySelection`, 1–2 ms for the whole file).
enum SmallBodyBrightLists {
    /// The days "this month" covers.
    static let monthDays = 31
    /// The most rows a list holds.
    static let maximumCount = 50

    /// The comets and asteroids of `catalog`: the bodies the lists choose from.
    static func bodies(in catalog: Catalog) -> [SmallBody] {
        catalog.smallBodies.compactMap(\.smallBody)
    }

    /// The bright bodies of `period` starting at `date`, brightest first. A body is bright when it reaches `limit`
    /// magnitude while at least 25° from the Sun.
    static func select(_ bodies: [SmallBody], at date: Date, period: SmallBodyListPeriod, limit: Double,
                       kind: SmallBodyListKind, maximumCount: Int = maximumCount) -> [BrightSmallBody] {
        switch period {
        case .now:
            return SmallBodySelection.brightNow(in: bodies, at: date, magnitudeLimit: limit, kind: kind.kind,
                                                maximumCount: maximumCount)
        case .thisMonth:
            let interval = DateInterval(start: date, duration: Double(monthDays) * 86_400)
            return SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: limit, kind: kind.kind,
                                                maximumCount: maximumCount)
        }
    }

    /// `select` with the bodies of `catalog`, each with its catalog object (a body the catalog lost is left out).
    static func entries(in catalog: Catalog, at date: Date, period: SmallBodyListPeriod, limit: Double,
                        kind: SmallBodyListKind, maximumCount: Int = maximumCount) -> [SmallBodyListEntry] {
        select(bodies(in: catalog), at: date, period: period, limit: limit, kind: kind, maximumCount: maximumCount)
            .compactMap { bright in
                catalog.object(id: bright.body.id).map { SmallBodyListEntry(object: $0, bright: bright) }
            }
    }

    /// "No comet is brighter than magnitude 10 right now. That is normal; bright comets are rare."
    static func emptyMessage(period: SmallBodyListPeriod, limit: Double, kind: SmallBodyListKind) -> String {
        let timing = period == .now ? "right now" : "in the next \(monthDays) days"
        let first = "No \(kind.noun) is brighter than magnitude \(Int(limit)) \(timing)."
        return kind == .asteroids ? first : "\(first) That is normal; bright comets are rare."
    }
}
