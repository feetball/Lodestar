import Foundation

/// A position in the phone's viewport, in UIKit points.
public struct ProjectedPoint: Hashable, Sendable {
    /// Distance from the left edge of the viewport; grows towards the right.
    public let x: Double
    /// Distance from the top edge of the viewport; grows downwards.
    public let y: Double
    /// Cosine of the angle between the direction and the optical axis, in (0, 1]; 1 at the centre of
    /// the viewport. Small values are far off-axis (and far outside the viewport).
    public let depth: Double
}

/// A pinhole model of the phone's own back camera, used to draw celestial objects over the live
/// preview. The preview is assumed to fill the viewport of a phone held in portrait: device +x is
/// to the right, device +y up the screen, and the camera looks along device −z.
///
/// The overlay follows the phone, not the DSLR: the heading offset (compass correction) is applied,
/// the DSLR device correction is not. Pass `AlignmentModel.headingOffset(for:)` as the offset, or 0
/// when there is no alignment.
public struct PinholeProjection: Hashable, Sendable {
    private static let minimumDepth = 1e-6
    private static let maximumSamplesPerEdge = 1000

    /// Viewport width in points.
    public let viewportWidth: Double
    /// Viewport height in points.
    public let viewportHeight: Double
    /// Focal length in points.
    public let focalLength: Double

    /// A projection from an explicit focal length in points; `nil` unless all values are finite and positive.
    public init?(viewportWidth: Double, viewportHeight: Double, focalLength: Double) {
        guard [viewportWidth, viewportHeight, focalLength].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.focalLength = focalLength
    }

    /// A projection whose viewport shows `longSideFieldOfView` degrees along its longer side;
    /// `nil` unless the sizes are finite and positive and the field of view is in (0°, 180°). For an
    /// aspect-fill camera preview in a viewport that is not wider than the camera image (any tall
    /// phone screen) this is the camera's own field of view along its long side.
    public init?(viewportWidth: Double, viewportHeight: Double, longSideFieldOfView: Double) {
        guard longSideFieldOfView.isFinite, longSideFieldOfView > 0, longSideFieldOfView < 180,
              viewportWidth.isFinite, viewportHeight.isFinite else { return nil }
        let focalLength = max(viewportWidth, viewportHeight) / 2 / AstroMath.tanDeg(longSideFieldOfView / 2)
        self.init(viewportWidth: viewportWidth, viewportHeight: viewportHeight, focalLength: focalLength)
    }

    /// Field of view along the longer side of the viewport, degrees.
    public var longSideFieldOfView: Double { fieldOfView(spanning: max(viewportWidth, viewportHeight)) }
    /// Field of view across the viewport width, degrees.
    public var horizontalFieldOfView: Double { fieldOfView(spanning: viewportWidth) }
    /// Field of view across the viewport height, degrees.
    public var verticalFieldOfView: Double { fieldOfView(spanning: viewportHeight) }

    /// Where a world direction (any non-zero ENU vector) appears in the viewport. `nil` when the
    /// direction is behind the camera (or not finite). The point may lie outside the viewport; see
    /// `contains(_:margin:)`.
    public func project(worldDirection: Vector3, attitude: DeviceAttitude, headingOffset: Double) -> ProjectedPoint? {
        project(worldDirection, worldToDevice: attitude.withHeadingOffset(headingOffset).worldToDevice)
    }

    /// `project(worldDirection:attitude:headingOffset:)` for many directions at once (the attitude
    /// is converted only once). The result has one entry per input direction.
    public func project(worldDirections: [Vector3], attitude: DeviceAttitude, headingOffset: Double) -> [ProjectedPoint?] {
        let worldToDevice = attitude.withHeadingOffset(headingOffset).worldToDevice
        return worldDirections.map { project($0, worldToDevice: worldToDevice) }
    }

    /// The world direction (ENU unit vector) seen at a viewport position; the inverse of `project`.
    /// `nil` when a coordinate is not finite.
    public func unproject(x: Double, y: Double, attitude: DeviceAttitude, headingOffset: Double) -> Vector3? {
        guard x.isFinite, y.isFinite else { return nil }
        let ray = Vector3((x - viewportWidth / 2) / focalLength, -(y - viewportHeight / 2) / focalLength, -1)
        return attitude.withHeadingOffset(headingOffset).deviceToWorld * ray.normalized
    }

    /// `true` when the point lies inside the viewport, grown by `margin` points on every side.
    public func contains(_ point: ProjectedPoint, margin: Double = 0) -> Bool {
        point.x >= -margin && point.x <= viewportWidth + margin
            && point.y >= -margin && point.y <= viewportHeight + margin
    }

    /// World directions (ENU unit vectors) along the border of the DSLR's picture, for drawing the
    /// framing rectangle on the phone view or a sky chart. The loop runs clockwise as seen by the
    /// photographer — top-left, top-right, bottom-right, bottom-left — with `samplesPerEdge` points
    /// per edge (each edge starts at its corner and excludes the next one). The picture's width
    /// follows `cameraRightVector`, its height `cameraUpVector`; swap the field-of-view values for a
    /// camera turned to portrait. Straight picture edges are great-circle arcs, which a rectilinear
    /// view such as `PinholeProjection` draws as straight lines.
    ///
    /// Returns an empty array unless both fields of view are in (0°, 180°) and `samplesPerEdge` ≥ 1.
    public static func dslrFrameOutline(solution: PointingSolution, horizontalFOV: Double, verticalFOV: Double,
                                        samplesPerEdge: Int) -> [Vector3] {
        guard horizontalFOV.isFinite, verticalFOV.isFinite, samplesPerEdge >= 1,
              (0.0..<180.0).contains(horizontalFOV), (0.0..<180.0).contains(verticalFOV),
              horizontalFOV > 0, verticalFOV > 0 else { return [] }
        let halfWidth = AstroMath.tanDeg(horizontalFOV / 2)
        let halfHeight = AstroMath.tanDeg(verticalFOV / 2)
        let samples = min(samplesPerEdge, maximumSamplesPerEdge)
        let corners = [(-1.0, 1.0), (1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)]
        var outline = [Vector3]()
        outline.reserveCapacity(4 * samples)
        for edge in 0..<4 {
            let start = corners[edge], end = corners[(edge + 1) % 4]
            for step in 0..<samples {
                let t = Double(step) / Double(samples)
                let right = (start.0 + (end.0 - start.0) * t) * halfWidth
                let up = (start.1 + (end.1 - start.1) * t) * halfHeight
                outline.append((solution.boresightVector + solution.cameraRightVector * right
                    + solution.cameraUpVector * up).normalized)
            }
        }
        return outline
    }

    private func project(_ direction: Vector3, worldToDevice: Matrix3) -> ProjectedPoint? {
        guard direction.isFinite else { return nil }
        let unit = direction.normalized
        guard unit != .zero else { return nil }
        let device = worldToDevice * unit
        let depth = -device.z
        guard depth > Self.minimumDepth else { return nil }
        return ProjectedPoint(x: viewportWidth / 2 + focalLength * device.x / depth,
                              y: viewportHeight / 2 - focalLength * device.y / depth,
                              depth: depth)
    }

    private func fieldOfView(spanning length: Double) -> Double {
        2 * AstroMath.degrees(atan(length / 2 / focalLength))
    }
}
