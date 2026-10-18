import Foundation
import LodestarKit

/// Turns what an event points at into something the Aim screen can guide to.
enum EventsAiming {
    /// How close, in degrees, a catalog star has to be to a reference place to stand for it.
    static let matchRadius = 1.0

    /// The catalog object for the Sun, the Moon or a planet; a catalog star or cluster that is at the place of a
    /// reference star; otherwise a custom target at the place. `nil` only for a solar-system body while the catalog is
    /// not loaded.
    static func object(for subject: EventsCalculator.AimSubject, in catalog: Catalog?) -> CelestialObject? {
        switch subject {
        case .body(let body):
            return catalog?.object(id: identifier(of: body))
        case .fixed(let name, let position):
            if let catalog, let known = nearest(named: name, at: position, in: catalog) {
                return known
            }
            return CelestialObject.custom(name: name, j2000: position)
        case .radiant(let name, let position):
            return CelestialObject.custom(name: name, j2000: position)
        }
    }

    /// The catalog identifier of a solar-system body: `"sun"`, `"moon"` or `"planet.mars"`.
    static func identifier(of body: SolarSystemBody) -> String {
        switch body {
        case .sun: return "sun"
        case .moon: return "moon"
        default: return "planet.\(body.rawValue)"
        }
    }

    /// The first search result for `name` that stands within `matchRadius` of `position`.
    private static func nearest(named name: String, at position: EquatorialCoordinate,
                                in catalog: Catalog) -> CelestialObject? {
        for result in catalog.search(name, limit: 5) {
            guard case .fixed(let place, _) = result.object.position else { continue }
            if separation(place, position) <= matchRadius { return result.object }
        }
        return nil
    }

    /// The angle between two J2000 places, in degrees.
    static func separation(_ first: EquatorialCoordinate, _ second: EquatorialCoordinate) -> Double {
        let cosine = first.unitVector.dot(second.unitVector)
        return acos(min(max(cosine, -1), 1)) * 180 / Double.pi
    }
}
