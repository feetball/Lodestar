import Foundation
import LodestarKit

/// What the finder looks for: the Milky Way core, the Moon, the Sun or an object of the catalog.
enum AlignmentFinderWhat: String, CaseIterable, Identifiable, Sendable {
    case milkyWayCore, moon, sun, object

    var id: String { rawValue }

    var title: String {
        switch self {
        case .milkyWayCore: return "Milky Way core"
        case .moon: return "Moon"
        case .sun: return "Sun"
        case .object: return "Choose object\u{2026}"
        }
    }
}

/// Where it should stand: over a point of the recorded skyline, or in a window given by numbers.
enum AlignmentFinderPlace: String, CaseIterable, Identifiable, Sendable {
    case skyline, window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skyline: return "On my skyline"
        case .window: return "Azimuth & altitude"
        }
    }
}

/// How far ahead to search, from tonight.
enum AlignmentFinderRange: Int, CaseIterable, Identifiable, Sendable {
    case month = 30, quarter = 90, year = 365

    var id: Int { rawValue }

    var days: Int { rawValue }

    var title: String { "\(rawValue) days" }
}

/// How dark the sky has to be.
enum AlignmentFinderDarkness: String, CaseIterable, Identifiable, Sendable {
    case astronomical, nautical, anyDarkness, anyTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .astronomical: return "Astronomical"
        case .nautical: return "Nautical"
        case .anyDarkness: return "Any darkness"
        case .anyTime: return "Any time"
        }
    }

    /// The engine's setting: "any darkness" is the Sun below 6°.
    var kind: SkyWindowDarkness {
        switch self {
        case .astronomical: return .astronomical
        case .nautical: return .nautical
        case .anyDarkness: return .civil
        case .anyTime: return .anyTime
        }
    }
}

/// What the Moon has to do.
enum AlignmentFinderMoon: String, CaseIterable, Identifiable, Sendable {
    case any, belowHorizon, dim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .belowHorizon: return "Below the horizon"
        case .dim: return "Dim"
        }
    }
}

/// The inputs of the screen, kept while it is on the navigation stack (the Sky chart is another tab). Changing the
/// target also resets the darkness to what suits it: any time for the Sun and the Moon, astronomical darkness for
/// the rest.
struct AlignmentFinderInputs: Equatable {
    static let skylineToleranceDefault = 3
    static let skylineToleranceMaximum = 10
    static let windowToleranceDefault = 10
    static let windowToleranceMaximum = 90
    static let dimPercentDefault = 25
    static let secondsPerDay = 86_400.0

    private(set) var what = AlignmentFinderWhat.milkyWayCore
    private(set) var chosenObject: CelestialObject?
    var place = AlignmentFinderPlace.skyline
    var skylineAzimuth = 180
    var skylineTolerance = Self.skylineToleranceDefault
    var windowAzimuth = 180
    var windowTolerance = Self.windowToleranceDefault
    var minimumAltitude = 0
    var maximumAltitude = 30
    var range = AlignmentFinderRange.month
    var darkness = AlignmentFinderDarkness.astronomical
    var moon = AlignmentFinderMoon.any
    var dimPercent = Self.dimPercentDefault

    /// Chooses the Milky Way core, the Moon or the Sun; `.object` needs `choose(_:)` with an object first.
    mutating func choose(_ what: AlignmentFinderWhat) {
        if what == .object && chosenObject == nil { return }
        self.what = what
        darkness = Self.defaultDarkness(for: target)
    }

    /// Chooses an object of the catalog.
    mutating func choose(_ object: CelestialObject) {
        chosenObject = object
        what = .object
        darkness = Self.defaultDarkness(for: target)
    }

    /// What the finder follows, or `nil` while "Choose object…" has no object yet.
    var target: SkyWindowTarget? {
        switch what {
        case .milkyWayCore: return .milkyWayCore
        case .moon: return .body(.moon)
        case .sun: return .body(.sun)
        case .object: return chosenObject.map { .catalogObject($0) }
        }
    }

    /// Whether the finder follows the Sun, for which there is no Aim button.
    var followsSun: Bool {
        what == .sun || (what == .object && chosenObject?.category == .sun)
    }

    /// The object that Aim takes for the target (`lookup` finds the catalog's Milky Way core and Moon by identifier);
    /// `nil` for the Sun and while "Choose object…" has no object.
    func aimObject(lookup: (String) -> CelestialObject?) -> CelestialObject? {
        if followsSun { return nil }
        switch what {
        case .milkyWayCore: return lookup("special.galacticCenter")
        case .moon: return lookup("moon")
        case .sun, .object: return chosenObject
        }
    }

    /// The search these inputs ask for at `context` and `now`; `nil` while they cannot ask for one.
    func request(for context: ObserverContext, now: Date) -> AlignmentFinderRequest? {
        guard let target else { return nil }
        let skyline = AlignmentFinderRequest.skyline(of: context)
        let window: SkyWindow?
        switch place {
        case .skyline:
            window = skyline.flatMap {
                SkyWindow.skylinePoint(azimuth: Double(skylineAzimuth), horizon: $0,
                                       azimuthTolerance: Double(skylineTolerance))
            }
        case .window:
            window = SkyWindow.around(azimuth: Double(windowAzimuth), tolerance: Double(windowTolerance),
                                      minimumAltitude: Double(minimumAltitude), maximumAltitude: Double(maximumAltitude))
        }
        guard let window else { return nil }
        let from = AlignmentFinderRequest.nightStart(containing: now, in: context.timeZone)
        let rule: SkyWindowMoonRule
        switch moon {
        case .any: rule = .unrestricted
        case .belowHorizon: rule = .belowHorizon
        case .dim: rule = .illuminatedAtMost(Double(dimPercent) / 100)
        }
        return AlignmentFinderRequest(target: target, window: window, observer: context.observer,
                                      timeZone: context.timeZone, horizon: skyline, from: from,
                                      to: from.addingTimeInterval(Double(range.days) * Self.secondsPerDay),
                                      darkness: darkness.kind, moon: rule, isAtSkyline: place == .skyline)
    }

    private static func defaultDarkness(for target: SkyWindowTarget?) -> AlignmentFinderDarkness {
        let body: SolarSystemBody?
        switch target {
        case .body(let value): body = value
        case .catalogObject(let object):
            if case .solarSystem(let value) = object.position { body = value } else { body = nil }
        default: body = nil
        }
        return body == .sun || body == .moon ? .anyTime : .astronomical
    }
}

/// One search: everything the engine needs and the screen's wording of the question. Equal requests give equal results.
struct AlignmentFinderRequest: Equatable, Sendable {
    var target: SkyWindowTarget
    var window: SkyWindow
    var observer: Observer
    var timeZone: TimeZone
    var horizon: HorizonProfile?
    var from: Date
    var to: Date
    var darkness: SkyWindowDarkness
    var moon: SkyWindowMoonRule
    /// Whether the window was cut from the skyline (for the wording of an empty result).
    var isAtSkyline: Bool

    /// The recorded skyline of the site, or `nil` for none; a flat one counts as none.
    static func skyline(of context: ObserverContext) -> HorizonProfile? {
        guard let horizon = context.horizon, !horizon.isFlat else { return nil }
        return horizon
    }

    /// The start (local noon) of the night that contains `now`.
    static func nightStart(containing now: Date, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        if now >= noon { return noon }
        return calendar.date(byAdding: .day, value: -1, to: noon) ?? noon.addingTimeInterval(-86_400)
    }
}

/// Why a search found nothing, as far as can be told.
enum AlignmentFinderEmptyReason: Sendable {
    /// The Sun never gets low enough in the period.
    case neverDark
    /// There are matches, but only with the Moon up or too bright for the Moon setting.
    case onlyWithMoon
    /// There are matches, but only when the sky is lighter than the darkness setting allows.
    case onlyInLight
    /// The target does not pass through the window in the period.
    case neverInWindow
}

/// What a search came to.
enum AlignmentFinderOutcome: Sendable {
    /// The matches in time order; `isCutShort` when the engine stopped at its limit.
    case found([SkyWindowMatch], isCutShort: Bool)
    /// No match, and the likely reason.
    case empty(AlignmentFinderEmptyReason)
    /// The engine refused the search.
    case failed(String)
}

/// Runs searches and explains empty results. Pure: call it off the main thread.
enum AlignmentFinderSearch {
    /// Days between the nights checked for darkness when a search finds nothing.
    private static let darknessSampleDays = 10

    /// The matches of `request`, or `nil` when the task running the search was cancelled: the engine then stops at its
    /// next night and no relaxed search is started. A search that finds nothing is repeated with the Moon rule and
    /// then the darkness relaxed, which tells which setting is in the way; a year of searching takes under a second,
    /// so that is cheap.
    static func run(_ request: AlignmentFinderRequest) -> AlignmentFinderOutcome? {
        let found: [SkyWindowMatch]
        do {
            found = try matches(request)
        } catch is CancellationError {
            return nil
        } catch let error as SkyWindowError {
            return .failed(failure(error))
        } catch {
            return .failed("The search could not run.")
        }
        if !found.isEmpty {
            return .found(found, isCutShort: found.count >= SkyWindowFinder.maximumMatchCount)
        }
        do {
            return .empty(try reason(for: request))
        } catch {
            return nil
        }
    }

    private static func matches(_ request: AlignmentFinderRequest) throws -> [SkyWindowMatch] {
        try SkyWindowFinder.matches(target: request.target, window: request.window, observer: request.observer,
                                    horizon: request.horizon, from: request.from, to: request.to,
                                    darkness: request.darkness, moon: request.moon, timeZone: request.timeZone)
    }

    /// Throws `CancellationError` when the task is cancelled during one of the relaxed searches.
    private static func reason(for request: AlignmentFinderRequest) throws -> AlignmentFinderEmptyReason {
        if request.darkness != .anyTime && isNeverDark(request) { return .neverDark }
        var anyMoon = request
        anyMoon.moon = .unrestricted
        if try request.moon != .unrestricted && hasMatches(anyMoon) { return .onlyWithMoon }
        var anyTime = anyMoon
        anyTime.darkness = .anyTime
        if try request.darkness != .anyTime && hasMatches(anyTime) { return .onlyInLight }
        return .neverInWindow
    }

    /// Whether `request` has any match; a search the engine refuses counts as none. Throws `CancellationError` when
    /// the task is cancelled, so that a stale search does not go on to the next relaxed pass.
    private static func hasMatches(_ request: AlignmentFinderRequest) throws -> Bool {
        do {
            return try !matches(request).isEmpty
        } catch let cancelled as CancellationError {
            throw cancelled
        } catch {
            return false
        }
    }

    /// Whether the Sun stays above the darkness limit at every sampled night of the range, as in a polar summer.
    private static func isNeverDark(_ request: AlignmentFinderRequest) -> Bool {
        guard let limit = request.darkness.sunAltitudeLimit else { return false }
        let days = Int(request.to.timeIntervalSince(request.from) / AlignmentFinderInputs.secondsPerDay)
        for day in stride(from: 0, through: days, by: darknessSampleDays) {
            let date = request.from.addingTimeInterval(Double(day) * AlignmentFinderInputs.secondsPerDay + 1)
            let twilight = TwilightCalculator.night(startingOn: date, observer: request.observer,
                                                    timeZone: request.timeZone)
            if twilight.sunAltitudeAtMidnight < limit { return false }
        }
        return true
    }

    private static func failure(_ error: SkyWindowError) -> String {
        switch error {
        case .rangeTooLong: return "That is too many nights to search. Choose a shorter period."
        case .invalidRange: return "The dates cannot be searched."
        case .invalidTarget: return "This object has no position to search for."
        case .invalidMoonRule: return "The Moon setting is not a usable percentage."
        }
    }
}
