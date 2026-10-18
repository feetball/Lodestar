import Foundation
import LodestarKit

extension SkySnapshot {
    /// A comet or an asteroid, drawn as a dot (a comet with a ring and a short line along its ion tail).
    struct SmallBodyMarker: Sendable, Identifiable {
        let object: CelestialObject
        /// The apparent (refracted) direction in the local East–North–Up frame.
        let direction: Vector3
        let horizontal: HorizontalCoordinate
        /// The current magnitude, an estimate; `nil` without magnitude parameters.
        let magnitude: Double?
        /// A point one degree from `direction` along the ion tail of a comet (apparent, East–North–Up); otherwise `nil`.
        let tailEnd: Vector3?

        var id: String { object.id }
        var isComet: Bool { object.category == .comet }
    }
}

/// Which comets and asteroids a sky view draws, and where: the target always, otherwise the ones brighter than a
/// magnitude limit (a view with all 216 bundled asteroids and every comet of the file would be a rash of dots). Each
/// comet also gets the direction of its ion tail on the sky. Pure, so it runs on any thread.
enum SmallBodySkyMarkers {
    /// Bodies fainter than this (and not the target) are not drawn: faint dots cannot be photographed and clutter.
    static let defaultMagnitudeLimit = 9.0
    /// The most markers a snapshot carries, brightest first.
    static let maximumCount = 80
    /// The tail direction is the body's direction moved this far (tangent of one degree) along the tail.
    private static let tailStep = AstroMath.tanDeg(1)

    /// The markers of the small bodies in `smallBodies` (the comets and asteroids of the catalog) for `frame`: the
    /// `target` and everything brighter than `magnitudeLimit`, the target first and then the brightest first. A body
    /// without magnitude parameters is drawn only as the target.
    static func build(smallBodies: [CelestialObject], frame: SkyFrame, target: CelestialObject?,
                      magnitudeLimit: Double) -> [SkySnapshot.SmallBodyMarker] {
        let targetBody = target?.smallBody
        guard !smallBodies.isEmpty || targetBody != nil else { return [] }
        var candidates = smallBodies
        if let target, targetBody != nil, !smallBodies.contains(where: { $0.id == target.id }) {
            candidates.append(target)
        }
        var markers: [SkySnapshot.SmallBodyMarker] = []
        for object in candidates {
            guard let body = object.smallBody, let state = frame.state(of: body) else { continue }
            let magnitude = state.apparentMagnitude
            let isTarget = object.id == target?.id
            if !isTarget {
                guard let magnitude, magnitude <= magnitudeLimit else { continue }
            }
            let horizontal = frame.horizontal(geocentricJ2000: state.geocentricJ2000, refraction: true)
            let direction = horizontal.unitVector
            var tail: Vector3?
            if body.kind == .comet, let angle = SmallBodyEphemeris.tailAngleFromVertical(of: state, in: frame) {
                tail = Self.tailEnd(from: direction, angleFromVertical: angle)
            }
            markers.append(SkySnapshot.SmallBodyMarker(object: object, direction: direction, horizontal: horizontal,
                                                       magnitude: magnitude, tailEnd: tail))
        }
        markers.sort { lhs, rhs in
            let lhsIsTarget = lhs.object.id == target?.id, rhsIsTarget = rhs.object.id == target?.id
            if lhsIsTarget != rhsIsTarget { return lhsIsTarget }
            let (lhsMagnitude, rhsMagnitude) = (lhs.magnitude ?? .infinity, rhs.magnitude ?? .infinity)
            if lhsMagnitude != rhsMagnitude { return lhsMagnitude < rhsMagnitude }
            return lhs.object.id < rhs.object.id
        }
        return markers.count > maximumCount ? Array(markers.prefix(maximumCount)) : markers
    }

    /// A point one degree from `direction` along the tail, which lies `angleFromVertical` degrees from straight up
    /// (positive to the observer's right when facing the body). `nil` at the zenith, where "up" has no direction.
    static func tailEnd(from direction: Vector3, angleFromVertical: Double) -> Vector3? {
        let upRaw = Vector3(0, 0, 1) - direction * direction.z
        let upLength = upRaw.length
        guard upLength > 1e-9 else { return nil }
        let up = upRaw / upLength
        let right = direction.cross(up)
        let along = up * AstroMath.cosDeg(angleFromVertical) + right * AstroMath.sinDeg(angleFromVertical)
        return (direction + along * tailStep).normalized
    }
}

/// How the dots and tails of comets and asteroids look, in points; the chart and the Aim overlay share them.
enum SmallBodyMarkerStyle {
    /// The radius of the dot: bright ones are bigger, an unknown magnitude is a small dot.
    static func dotRadius(magnitude: Double?, isComet: Bool) -> CGFloat {
        guard let magnitude, magnitude.isFinite else { return 2.5 }
        let radius = isComet ? 4.5 - 0.35 * (magnitude - 4) : 3.4 - 0.3 * (magnitude - 5)
        return CGFloat(max(isComet ? 2.5 : 2.0, min(radius, isComet ? 4.5 : 3.4)))
    }

    /// The length of the line along a comet's tail: a little longer for the brighter comets.
    static func tailLength(magnitude: Double?) -> CGFloat {
        guard let magnitude, magnitude.isFinite else { return 12 }
        return CGFloat(12 + max(0, min((8 - magnitude) * 2, 10)))
    }

    /// The zoom from which the chart writes the name of a body of `magnitude`: the brightest are named at once.
    static func labelZoom(magnitude: Double?) -> CGFloat {
        guard let magnitude, magnitude.isFinite else { return 3 }
        if magnitude <= 6.5 { return 1 }
        return magnitude <= 8 ? 1.8 : 3
    }

    /// The faintest magnitude whose name the Aim overlay writes in any view.
    static let nameMagnitude = 8.0
    /// Fainter ones are named in views narrower than `narrowView` degrees, up to this magnitude.
    static let narrowNameMagnitude = 9.0
    static let narrowView = 40.0

    /// Whether a body of `magnitude` is named in a view `fieldOfView` degrees wide.
    static func isNamed(magnitude: Double?, fieldOfView: Double) -> Bool {
        guard let magnitude, magnitude.isFinite else { return false }
        return magnitude <= nameMagnitude || (fieldOfView < narrowView && magnitude <= narrowNameMagnitude)
    }
}
