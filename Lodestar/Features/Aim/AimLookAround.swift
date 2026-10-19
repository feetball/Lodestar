import Foundation
import LodestarKit

/// What lies under the reticle while there is no target, so the sky can be explored by pointing the camera around.
enum AimLookAround {
    /// The object nearest the centre of the picture.
    struct Nearby: Equatable {
        let id: String
        let name: String
        /// Degrees from the centre.
        let separation: Double
    }

    /// Stars brighter than this are named; fainter ones are too many to pick from.
    private static let starMagnitudeLimit = 3.0
    /// Deep-sky objects brighter than this are named.
    private static let deepSkyMagnitudeLimit = 9.0

    /// How far from the centre an object may be and still be named: a tenth of the field of view, at least 2° and at
    /// most 8°.
    static func radius(fieldOfView: Double) -> Double {
        AstroMath.clamp(fieldOfView / 10, 2, 8)
    }

    /// The Sun, Moon, planet, bright named star or bright deep-sky object nearest `direction` (an ENU unit vector),
    /// or `nil` if none lies within `radius` degrees. Planets and the Moon win over stars a little farther in, as they
    /// are what people usually point at.
    static func nearest(to direction: Vector3, in snapshot: SkySnapshot, within radius: Double) -> Nearby? {
        var best: (nearby: Nearby, score: Double)?
        func consider(id: String, name: String, at target: Vector3, weight: Double) {
            let separation = direction.angle(to: target)
            guard separation <= radius else { return }
            let score = separation * weight
            if best == nil || score < best!.score {
                best = (Nearby(id: id, name: name, separation: separation), score)
            }
        }
        for body in snapshot.bodies {
            consider(id: body.object.id, name: body.object.name, at: body.direction, weight: 0.5)
        }
        for star in snapshot.stars where star.magnitude <= starMagnitudeLimit {
            guard let name = star.name else { continue }
            consider(id: star.id, name: name, at: star.direction, weight: 1)
        }
        for deepSky in snapshot.deepSky {
            guard let magnitude = deepSky.object.magnitude, magnitude <= deepSkyMagnitudeLimit else { continue }
            consider(id: deepSky.object.id, name: deepSky.object.name, at: deepSky.direction, weight: 1)
        }
        return best?.nearby
    }
}
