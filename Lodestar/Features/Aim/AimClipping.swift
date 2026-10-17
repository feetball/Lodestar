import SwiftUI
import Foundation
import LodestarKit

/// Sutherland–Hodgman clipping of rings of world directions against planes through the observer.
///
/// A great-circle arc projects to a straight line in a rectilinear view, and so does the chord between its
/// end points: both lie in the plane through the observer. Clipping the chord polygon with planes through the
/// observer therefore clips the spherical polygon exactly, and the points where it is cut keep the right
/// direction (their length is irrelevant). A ring that spans more than about a hemisphere has closing edges that
/// approach half a circle, which no rectilinear view can represent: cut such rings up first.
enum AimPolygonClip {
    /// The part of `ring` where `normal · v ≥ 0` for every normal; empty when nothing remains.
    static func clip(_ ring: [Vector3], keeping normals: [Vector3]) -> [Vector3] {
        var output = ring
        for normal in normals {
            guard let last = output.last else { return [] }
            let input = output
            output.removeAll(keepingCapacity: true)
            var previous = last
            var previousDistance = normal.dot(previous)
            for current in input {
                let distance = normal.dot(current)
                if distance >= 0 {
                    if previousDistance < 0 { output.append(crossing(previous, current, previousDistance, distance)) }
                    output.append(current)
                } else if previousDistance >= 0 {
                    output.append(crossing(previous, current, previousDistance, distance))
                }
                previous = current
                previousDistance = distance
            }
        }
        return output
    }

    /// The point of the chord from `a` to `b` where the signed distances `da` and `db` change sign.
    static func crossing(_ a: Vector3, _ b: Vector3, _ da: Double, _ db: Double) -> Vector3 {
        a + (b - a) * (da / (da - db))
    }
}

/// A line segment cut to the viewport. `startClipped` and `endClipped` tell whether an end was moved.
struct AimClippedSegment {
    let start: Vector3
    let end: Vector3
    let startClipped: Bool
    let endClipped: Bool
}

/// The viewport, grown by a margin, as a pyramid of four planes through the camera, in world coordinates.
///
/// Everything inside the pyramid is in front of the camera and projects to finite coordinates, so lines and
/// polygons that reach behind the camera can be cut before they are projected.
struct AimFrustum {
    /// Inward normals (left, right, bottom, top): a direction is inside when all four dot products are ≥ 0.
    let planes: [Vector3]

    /// - Parameters:
    ///   - margin: Points by which the viewport is grown on every side, so strokes do not end visibly at the edge.
    init(projection: PinholeProjection, attitude: DeviceAttitude, headingOffset: Double, margin: Double) {
        let halfWidth = (projection.viewportWidth / 2 + margin) / projection.focalLength
        let halfHeight = (projection.viewportHeight / 2 + margin) / projection.focalLength
        let deviceToWorld = attitude.withHeadingOffset(headingOffset).deviceToWorld
        // In device coordinates (x right, y up, the camera looks along −z) the left plane is
        // x + halfWidth · depth ≥ 0 with depth = −z, and so on.
        planes = [
            Vector3(1, 0, -halfWidth), Vector3(-1, 0, -halfWidth),
            Vector3(0, 1, -halfHeight), Vector3(0, -1, -halfHeight),
        ].map { deviceToWorld * $0 }
    }

    /// The part of the chord from `a` to `b` inside the pyramid, or `nil` when none of it is.
    func clip(from a: Vector3, to b: Vector3) -> AimClippedSegment? {
        var enter = 0.0, leave = 1.0
        for plane in planes {
            let da = plane.dot(a), db = plane.dot(b)
            if da < 0 && db < 0 { return nil }
            if da < 0 {
                enter = max(enter, da / (da - db))
            } else if db < 0 {
                leave = min(leave, da / (da - db))
            }
        }
        guard enter < leave else { return nil }
        let delta = b - a
        return AimClippedSegment(start: enter > 0 ? a + delta * enter : a, end: leave < 1 ? a + delta * leave : b,
                                 startClipped: enter > 0, endClipped: leave < 1)
    }

    /// The part of the ring inside the pyramid; empty when none of it is.
    func clip(polygon ring: [Vector3]) -> [Vector3] {
        AimPolygonClip.clip(ring, keeping: planes)
    }
}

/// Projects world directions with the phone's own back camera: the heading offset is applied, the DSLR's
/// device correction is not (see `PinholeProjection`).
struct AimProjector {
    let projection: PinholeProjection
    let attitude: DeviceAttitude
    let headingOffset: Double

    /// Where `direction` appears in the viewport, `nil` behind the camera.
    func point(_ direction: Vector3) -> CGPoint? {
        guard let projected = projection.project(worldDirection: direction, attitude: attitude,
                                                 headingOffset: headingOffset) else { return nil }
        return CGPoint(x: projected.x, y: projected.y)
    }

    /// `point(_:)` for many directions at once; one entry per direction.
    func points(_ directions: [Vector3]) -> [CGPoint?] {
        projection.project(worldDirections: directions, attitude: attitude, headingOffset: headingOffset)
            .map { projected in projected.map { CGPoint(x: $0.x, y: $0.y) } }
    }
}

/// A set of polylines described by world directions: they are cut to the viewport as they are added and
/// projected in one batch when the path is made.
struct AimWorldPath {
    private var vertices: [Vector3] = []
    private var startsSubpath: [Bool] = []

    /// Adds the visible parts of the polyline through `points`; neighbours are joined by great-circle arcs.
    mutating func addPolyline(_ points: [Vector3], closed: Bool = false, frustum: AimFrustum) {
        guard points.count >= 2 else { return }
        var isContinuing = false
        let segmentCount = closed ? points.count : points.count - 1
        for index in 0..<segmentCount {
            addSegment(from: points[index], to: points[(index + 1) % points.count], frustum: frustum,
                       isContinuing: &isContinuing)
        }
    }

    /// Adds the visible part of the single segment from `a` to `b` as its own subpath.
    mutating func addSegment(from a: Vector3, to b: Vector3, frustum: AimFrustum) {
        var isContinuing = false
        addSegment(from: a, to: b, frustum: frustum, isContinuing: &isContinuing)
    }

    private mutating func addSegment(from a: Vector3, to b: Vector3, frustum: AimFrustum, isContinuing: inout Bool) {
        guard let segment = frustum.clip(from: a, to: b) else {
            isContinuing = false
            return
        }
        if !(isContinuing && !segment.startClipped) {
            vertices.append(segment.start)
            startsSubpath.append(true)
        }
        vertices.append(segment.end)
        startsSubpath.append(false)
        isContinuing = !segment.endClipped
    }

    /// The path in screen coordinates.
    func path(projecting projector: AimProjector) -> Path {
        let points = projector.points(vertices)
        var path = Path()
        for (index, point) in points.enumerated() {
            guard let point else { continue }
            if startsSubpath[index] {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
