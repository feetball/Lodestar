import Foundation

/// The border of the picture a camera takes, as directions in the camera's own frame, so that an app can draw any
/// frame (a rectangle, a curved fisheye frame, a circle) as a polygon on the sky.
///
/// The camera frame has x to the right of the picture, y towards its top and z along the optical axis, towards
/// the scene. A world direction follows from a pointing as `right · x + up · y + forward · z`, with the right, up and
/// boresight vectors of the pointing solution. The picture is for a camera held in landscape orientation; turn the
/// camera's right and up vectors for portrait.
///
/// The border of the sensor is mapped through the inverse of the lens's `LensProjection`, so a straight sensor edge
/// becomes a curve for a fisheye lens, and directions can lie behind the sensor's plane (negative z) when the lens
/// sees more than 90° from the axis. A lens with an image circle smaller than the sensor frames that circle, or what
/// is left of it inside the sensor.
///
/// Cost: one pass over `4 · samplesPerEdge` points, each with a few trigonometric calls and one `Vector3`. That is
/// small, but not free; compute the outline when the lens setup changes, keep it, and turn it into world directions
/// each frame.
public enum CameraFrameOutline: Sendable {

    /// The most samples per edge that are used; larger requests are limited to this.
    public static let maximumSamplesPerEdge = 1000

    /// Unit vectors along the border of the frame of `setup`, clockwise as seen by the photographer, in the camera
    /// frame.
    ///
    /// A rectangular frame starts at the top-left corner: top-left, top-right, bottom-right, bottom-left, with
    /// `samplesPerEdge` points per edge (each edge starts at its corner and excludes the next one), so the result has
    /// `4 · samplesPerEdge` points. A circular frame (an image circle that fits inside the sensor) has as many points,
    /// evenly spaced, starting at the top-left, 45° anticlockwise from the top. When the image circle only cuts the
    /// sensor's corners, the points of the rectangular outline are moved onto the circle.
    ///
    /// - Parameters:
    ///   - setup: The camera and lens.
    ///   - samplesPerEdge: The points per edge, at least 1 and limited to `maximumSamplesPerEdge`.
    /// - Returns: The directions, or an empty array if `samplesPerEdge` is less than 1.
    public static func directions(setup: LensSetup, samplesPerEdge: Int) -> [Vector3] {
        guard samplesPerEdge >= 1 else { return [] }
        let samples = min(samplesPerEdge, maximumSamplesPerEdge)
        let halfWidth = setup.sensor.widthMillimeters / 2
        let halfHeight = setup.sensor.heightMillimeters / 2
        let radius = setup.imageCircleDiameterMillimeters.map { $0 / 2 }
        let focalLength = setup.focalLengthMillimeters
        let projection = setup.projection
        var outline: [Vector3] = []
        outline.reserveCapacity(4 * samples)

        if let radius, radius <= min(halfWidth, halfHeight) {
            let count = 4 * samples
            for index in 0..<count {
                let turn = -Double.pi / 4 + 2 * Double.pi * Double(index) / Double(count)
                outline.append(direction(x: radius * sin(turn), y: radius * cos(turn),
                                         focalLength: focalLength, projection: projection))
            }
            return outline
        }

        let cornerRight = [-1.0, 1.0, 1.0, -1.0]
        let cornerUp = [1.0, 1.0, -1.0, -1.0]
        // A circle that does not reach the corners of the sensor trims them.
        let trimRadius = radius.flatMap { $0 < hypot(halfWidth, halfHeight) ? $0 : nil }
        for edge in 0..<4 {
            let next = (edge + 1) % 4
            for step in 0..<samples {
                let t = Double(step) / Double(samples)
                var x = (cornerRight[edge] + (cornerRight[next] - cornerRight[edge]) * t) * halfWidth
                var y = (cornerUp[edge] + (cornerUp[next] - cornerUp[edge]) * t) * halfHeight
                if let trimRadius {
                    let distance = hypot(x, y)
                    if distance > trimRadius {
                        x *= trimRadius / distance
                        y *= trimRadius / distance
                    }
                }
                outline.append(direction(x: x, y: y, focalLength: focalLength, projection: projection))
            }
        }
        return outline
    }

    /// The unit vector, in the camera frame, towards the middle of the top edge of the frame: where a mark that shows
    /// which way is up belongs. For a circular frame this is the top of the circle.
    public static func topMiddle(setup: LensSetup) -> Vector3 {
        let halfHeight = FieldOfView.framedExtent(setup.sensor.heightMillimeters, setup.imageCircleDiameterMillimeters) / 2
        return direction(x: 0, y: halfHeight, focalLength: setup.focalLengthMillimeters, projection: setup.projection)
    }

    /// The direction of the ray that lands at (`x`, `y`) millimetres from the centre of the frame (x to the right, y up)
    /// behind a lens of `focalLength` millimetres.
    private static func direction(x: Double, y: Double, focalLength: Double, projection: LensProjection) -> Vector3 {
        if projection == .rectilinear {
            return Vector3(x / focalLength, y / focalLength, 1).normalized
        }
        let distance = hypot(x, y)
        guard distance > 0 else { return Vector3(0, 0, 1) }
        let angle = projection.angleRadians(imageRadiusMillimeters: distance, focalLength: focalLength)
        let scale = sin(angle) / distance
        return Vector3(x * scale, y * scale, cos(angle))
    }
}
