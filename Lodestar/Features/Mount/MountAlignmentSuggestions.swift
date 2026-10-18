import Foundation
import LodestarKit

/// A bright star that could be used to align a mount, with where it stands now.
struct MountStarCandidate: Identifiable, Sendable {
    let object: CelestialObject
    let j2000: EquatorialCoordinate
    /// Where the star stands in the sky now (refraction included).
    let horizontal: HorizontalCoordinate
    let magnitude: Double

    var id: String { object.id }
}

/// A candidate recommended as the next alignment star.
struct MountStarSuggestion: Identifiable, Sendable {
    let candidate: MountStarCandidate
    /// The distance in degrees to the nearest star already used; `nil` for the first star.
    let separationDegrees: Double?

    var id: String { candidate.id }
}

/// Chooses stars for aligning a Sky-Watcher mount. The fit needs stars that are bright enough to centre, high enough to be
/// clear of the haze but not so high that an alt-azimuth mount struggles, away from the pole (where right ascension means
/// little), and far apart: the first anywhere, the next ones at least 30° from each other and from the first, on other
/// sides of the sky.
enum MountAlignmentSuggestions {
    /// Stars lower than this are in the haze and hard to centre.
    static let minimumAltitude = 25.0
    /// Stars higher than this are close to the zenith, where an alt-azimuth mount turns fast.
    static let maximumAltitude = 75.0
    /// Stars closer to the celestial pole than this are a poor reference for an equatorial mount.
    static let maximumDeclination = 80.0
    /// Stars at least this bright are offered.
    static let starMagnitudeLimit = 2.5
    /// The next star is at least this far from every star already used.
    static let minimumSeparation = 30.0
    /// How many stars the list shows.
    static let count = 3

    private static let brightnessWeight = 8.0
    private static let preferredAltitude = 50.0
    private static let altitudeDivisor = 5.0
    private static let farEnough = 90.0

    /// The bright stars that are in a good part of the sky at `date`. Searches the catalog, so run it off the main actor.
    static func candidates(catalog: Catalog, observer: Observer, date: Date) -> [MountStarCandidate] {
        let frame = SkyFrame(date: date, observer: observer)
        var result: [MountStarCandidate] = []
        for star in catalog.renderStars.prefix(while: { $0.magnitude <= starMagnitudeLimit }) {
            guard let object = catalog.object(id: star.id), let place = object.j2000,
                  abs(place.declination) <= maximumDeclination else { continue }
            let horizontal = frame.horizontal(of: object, refraction: true)
            guard (minimumAltitude...maximumAltitude).contains(horizontal.altitude) else { continue }
            result.append(MountStarCandidate(object: object, j2000: place, horizontal: horizontal, magnitude: star.magnitude))
        }
        return result
    }

    /// The best candidates for the next star, best first, given the places of the stars already used. With none used the
    /// brightest high stars come first; after that the stars farthest from all used ones, each at least `minimumSeparation`
    /// away, the brighter first among equals.
    static func suggest(_ candidates: [MountStarCandidate], used: [EquatorialCoordinate],
                        count: Int = MountAlignmentSuggestions.count) -> [MountStarSuggestion] {
        var scored: [(score: Double, suggestion: MountStarSuggestion)] = []
        for candidate in candidates {
            let separation = used.map { $0.angularSeparation(to: candidate.j2000) }.min()
            if let separation, separation < minimumSeparation { continue }
            let score: Double
            if let separation {
                score = min(separation, farEnough) - brightnessWeight * candidate.magnitude
            } else {
                score = -brightnessWeight * candidate.magnitude
                    - abs(candidate.horizontal.altitude - preferredAltitude) / altitudeDivisor
            }
            scored.append((score, MountStarSuggestion(candidate: candidate, separationDegrees: separation)))
        }
        return scored.sorted { $0.score > $1.score }.prefix(count).map(\.suggestion)
    }
}
