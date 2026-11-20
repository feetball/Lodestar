import Foundation

/// Field-of-view calculations for a lens on a given sensor.
///
/// The angle across a sensor dimension `d` is `2 · θ(d / 2)`, where `θ(r)` is the inverse of the lens's
/// `LensProjection`: for a rectilinear lens of focal length `f` that is `2 · atan(d / 2f)`, and a fisheye
/// mapping is inverted the same way. No angle exceeds 180°. The horizontal and vertical angles refer to the
/// sensor's width and height, that is, a camera held in landscape orientation; use `FrameSize.rotated` for
/// portrait.
///
/// A circular fisheye whose image circle is smaller than the sensor only fills that circle: every extent is
/// limited to the circle's diameter (`imageCircleDiameterMillimeters`), so a circle that fits inside the
/// frame gives the same angle in all three directions.
///
/// The functions accept any positive focal length. A focal length that is not a positive finite
/// number is replaced by `LensSetup.defaultFocalLengthMillimeters`, so the result is always a
/// valid angle. An image circle that is not a positive finite number is ignored.
public enum FieldOfView: Sendable {

    /// The horizontal field of view, in degrees, across the sensor width.
    public static func horizontal(
        sensor: SensorFormat,
        focalLength: Double,
        projection: LensProjection = .rectilinear,
        imageCircleDiameterMillimeters: Double? = nil
    ) -> Double {
        angleDegrees(
            extent: framedExtent(sensor.widthMillimeters, imageCircleDiameterMillimeters),
            focalLength: usable(focalLength),
            projection: projection
        )
    }

    /// The vertical field of view, in degrees, across the sensor height.
    public static func vertical(
        sensor: SensorFormat,
        focalLength: Double,
        projection: LensProjection = .rectilinear,
        imageCircleDiameterMillimeters: Double? = nil
    ) -> Double {
        angleDegrees(
            extent: framedExtent(sensor.heightMillimeters, imageCircleDiameterMillimeters),
            focalLength: usable(focalLength),
            projection: projection
        )
    }

    /// The diagonal field of view, in degrees, corner to corner.
    public static func diagonal(
        sensor: SensorFormat,
        focalLength: Double,
        projection: LensProjection = .rectilinear,
        imageCircleDiameterMillimeters: Double? = nil
    ) -> Double {
        angleDegrees(
            extent: framedExtent(sensor.diagonalMillimeters, imageCircleDiameterMillimeters),
            focalLength: usable(focalLength),
            projection: projection
        )
    }

    /// The horizontal, vertical and diagonal fields of view at once.
    public static func of(
        sensor: SensorFormat,
        focalLength: Double,
        projection: LensProjection = .rectilinear,
        imageCircleDiameterMillimeters: Double? = nil
    ) -> FrameSize {
        FrameSize(
            sensor: sensor,
            focalLength: usable(focalLength),
            projection: projection,
            imageCircleDiameterMillimeters: imageCircleDiameterMillimeters
        )
    }

    private static func usable(_ focalLength: Double) -> Double {
        focalLength.isFinite && focalLength > 0 ? focalLength : LensSetup.defaultFocalLengthMillimeters
    }

    /// The part of a sensor extent that the lens images: `extent` limited to the image circle's diameter, when there
    /// is a usable one (a positive finite number).
    static func framedExtent(_ extent: Double, _ imageCircleDiameterMillimeters: Double?) -> Double {
        guard let circle = imageCircleDiameterMillimeters, circle.isFinite, circle > 0 else { return extent }
        return min(extent, circle)
    }

    /// The angle across `extent` in degrees, at most 180: `2 · θ(extent / 2)` for the projection's inverse mapping `θ`.
    /// The caller guarantees a positive, finite focal length.
    fileprivate static func angleDegrees(extent: Double, focalLength: Double, projection: LensProjection) -> Double {
        min(180, 2 * projection.angleDegrees(imageRadiusMillimeters: extent / 2, focalLength: focalLength))
    }
}

/// The angular size of the camera frame on the sky, in degrees.
public struct FrameSize: Hashable, Sendable {
    /// The angle across the frame's width, in degrees.
    public let horizontal: Double

    /// The angle across the frame's height, in degrees.
    public let vertical: Double

    /// The angle across the frame's diagonal, in degrees.
    public let diagonal: Double

    /// Creates a frame size from angles in degrees.
    public init(horizontal: Double, vertical: Double, diagonal: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.diagonal = diagonal
    }

    /// Computes the frame size of a sensor behind a lens. The caller guarantees that
    /// `focalLength` is a positive, finite number of millimetres.
    init(
        sensor: SensorFormat,
        focalLength: Double,
        projection: LensProjection = .rectilinear,
        imageCircleDiameterMillimeters: Double? = nil
    ) {
        self.init(
            horizontal: FieldOfView.angleDegrees(
                extent: FieldOfView.framedExtent(sensor.widthMillimeters, imageCircleDiameterMillimeters),
                focalLength: focalLength, projection: projection
            ),
            vertical: FieldOfView.angleDegrees(
                extent: FieldOfView.framedExtent(sensor.heightMillimeters, imageCircleDiameterMillimeters),
                focalLength: focalLength, projection: projection
            ),
            diagonal: FieldOfView.angleDegrees(
                extent: FieldOfView.framedExtent(sensor.diagonalMillimeters, imageCircleDiameterMillimeters),
                focalLength: focalLength, projection: projection
            )
        )
    }

    /// The longer side of the frame, in degrees.
    public var longSide: Double { max(horizontal, vertical) }

    /// The shorter side of the frame, in degrees.
    public var shortSide: Double { min(horizontal, vertical) }

    /// The frame of the same camera turned a quarter turn, with width and height exchanged.
    public var rotated: FrameSize {
        FrameSize(horizontal: vertical, vertical: horizontal, diagonal: diagonal)
    }

    /// Measures how much of the frame an extended object covers, for a "fits in frame" display.
    ///
    /// The object is assumed to be turned so that its major axis lies along the frame's long side,
    /// which the photographer can arrange by rotating the camera; the fractions therefore describe
    /// the best case. Angular sizes are compared directly (a flat-sky approximation), which is
    /// accurate for objects well inside the frame.
    ///
    /// - Parameters:
    ///   - objectMajorArcmin: The object's larger angular dimension, in arcminutes.
    ///   - minorArcmin: The object's smaller angular dimension, in arcminutes. The two values may be
    ///     given in either order.
    /// - Returns: The framing, or nil if a dimension is negative or not finite, the larger
    ///   dimension is zero, or the frame has no area.
    public func framing(objectMajorArcmin: Double, minorArcmin: Double) -> ObjectFraming? {
        guard objectMajorArcmin.isFinite, minorArcmin.isFinite,
              objectMajorArcmin >= 0, minorArcmin >= 0,
              max(objectMajorArcmin, minorArcmin) > 0,
              longSide > 0, shortSide > 0 else { return nil }
        let major = max(objectMajorArcmin, minorArcmin)
        let minor = min(objectMajorArcmin, minorArcmin)
        return ObjectFraming(
            majorAxisFraction: major / (longSide * 60),
            minorAxisFraction: minor / (shortSide * 60)
        )
    }
}

/// How much of the camera frame an extended object covers.
public struct ObjectFraming: Hashable, Sendable {
    /// The object's major axis divided by the frame's long side; 1.0 spans the whole long side.
    public let majorAxisFraction: Double

    /// The object's minor axis divided by the frame's short side; 1.0 spans the whole short side.
    public let minorAxisFraction: Double

    /// The larger of the two fractions: how full the frame is along the object's tightest
    /// dimension. 0.25 means the object fills a quarter of the frame, and anything above 1.0
    /// does not fit.
    public var fillFraction: Double { max(majorAxisFraction, minorAxisFraction) }

    /// Whether the object fits inside the frame when oriented along it.
    public var fitsInFrame: Bool { fillFraction <= 1 }
}
