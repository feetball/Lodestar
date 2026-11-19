import Foundation
import LodestarKit

/// Where the Moon is, seen from the observer, relative to one object at one instant: the three numbers
/// `MoonImpact.assess` needs besides the filter and the object's kind.
struct ObjectMoonGeometry: Sendable, Equatable {
    /// The Moon's geometric altitude, in degrees.
    let moonAltitude: Double
    /// The angle between the Moon and the object, in degrees.
    let separation: Double
    /// The lit fraction of the Moon's disc, 0…1.
    let illuminatedFraction: Double

    /// The geometry of `object` and the Moon at `date`. It builds one sky frame and asks the Moon's ephemeris twice.
    init(of object: CelestialObject, observer: Observer, at date: Date) {
        let frame = SkyFrame(date: date, observer: observer)
        let moon = frame.horizontal(of: .moon, refraction: false)
        moonAltitude = moon.altitude
        separation = frame.horizontal(of: object, refraction: false).angularSeparation(to: moon)
        illuminatedFraction = frame.state(of: .moon).illuminatedFraction ?? 0
    }

    init(moonAltitude: Double, separation: Double, illuminatedFraction: Double) {
        self.moonAltitude = moonAltitude
        self.separation = separation
        self.illuminatedFraction = illuminatedFraction
    }

    /// What the Moon does to a shot of an object of kind `kind` through `filter`, and what it would do without one.
    func assess(filter: ImagingFilter, kind: ObjectCategory) -> ObjectMoonAssessment {
        ObjectMoonAssessment(
            level: MoonImpact.assess(moonAltitude: moonAltitude, separation: separation,
                                     illuminatedFraction: illuminatedFraction, filter: filter, objectKind: kind),
            broadbandLevel: MoonImpact.assess(moonAltitude: moonAltitude, separation: separation,
                                              illuminatedFraction: illuminatedFraction, filter: .none,
                                              objectKind: kind))
    }
}

/// How much the Moon disturbs a shot of one object: through the filter in use, and without any filter.
struct ObjectMoonAssessment: Sendable, Equatable {
    /// The level with the user's filter.
    let level: MoonImpact.Level
    /// The level without a filter.
    let broadbandLevel: MoonImpact.Level

    /// Whether the filter made the Moon matter less.
    var isRelaxed: Bool { level != broadbandLevel }
}

/// The words for the Moon's effect, the same on every screen.
enum ObjectMoonText {
    /// The filter as it reads in "your narrowband filter". Empty for no filter.
    static func filterName(_ filter: ImagingFilter) -> String {
        switch filter {
        case .none: return ""
        case .lightPollution: return "light-pollution"
        case .dualNarrowband: return "dual narrowband"
        case .narrowband: return "narrowband"
        }
    }

    /// What the Moon does to this target: a sentence, or when `filter` relaxed the level,
    /// "Moderate \u{00B7} fine with your narrowband filter".
    static func advice(_ assessment: ObjectMoonAssessment, filter: ImagingFilter) -> String {
        if assessment.isRelaxed {
            return "\(levelName(assessment.broadbandLevel)) \u{00B7} \(verdict(assessment.level))"
                + " with your \(filterName(filter)) filter"
        }
        switch assessment.level {
        case .moonDown: return "The Moon is down, so the sky stays dark."
        case .minor: return "The Moon has little effect on this target."
        case .moderate: return "Moonlight will brighten the sky around this target."
        case .severe: return "A bright Moon close by will wash out faint detail."
        }
    }

    /// The short label of a Tonight row: "Moon down", "Moon: moderate" or "Moon: fine with your filter".
    static func chip(_ assessment: ObjectMoonAssessment) -> String {
        if assessment.level == .moonDown { return "Moon down" }
        if assessment.isRelaxed { return "Moon: \(verdict(assessment.level)) with your filter" }
        return "Moon: \(levelName(assessment.level).lowercased())"
    }

    /// "Moderate", "Severe": a level as a word.
    private static func levelName(_ level: MoonImpact.Level) -> String {
        switch level {
        case .moonDown: return "Moon down"
        case .minor: return "Minor"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    /// What a filter achieved: "fine" when the Moon is down to minor, "manageable" when it is still moderate.
    private static func verdict(_ level: MoonImpact.Level) -> String {
        switch level {
        case .moonDown, .minor: return "fine"
        case .moderate, .severe: return "manageable"
        }
    }
}
