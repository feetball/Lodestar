import Foundation

/// Field-of-view calculations for a rectilinear lens on a given sensor.
///
/// The angle subtended by a sensor dimension `d` at focal length `f` is `2 · atan(d / 2f)`.
/// Fisheye and other non-rectilinear projections are not modelled. The horizontal and vertical
/// angles refer to the sensor's width and height, that is, a camera held in landscape orientation;
/// use `FrameSize.rotated` for portrait.
///
/// The functions accept any positive focal length. A focal length that is not a positive finite
/// number is replaced by `LensSetup.defaultFocalLengthMillimeters`, so the result is always a
/// valid angle.
public enum FieldOfView: Sendable {

    /// The horizontal field of view, in degrees, across the sensor width.
    public static func horizontal(sensor: SensorFormat, focalLength: Double) -> Double {
        angleDegrees(extent: sensor.widthMillimeters, focalLength: usable(focalLength))
    }

    /// The vertical field of view, in degrees, across the sensor height.
    public static func vertical(sensor: SensorFormat, focalLength: Double) -> Double {
        angleDegrees(extent: sensor.heightMillimeters, focalLength: usable(focalLength))
    }

    /// The diagonal field of view, in degrees, corner to corner.
    public static func diagonal(sensor: SensorFormat, focalLength: Double) -> Double {
        angleDegrees(extent: sensor.diagonalMillimeters, focalLength: usable(focalLength))
    }

    /// The horizontal, vertical and diagonal fields of view at once.
    public static func of(sensor: SensorFormat, focalLength: Double) -> FrameSize {
        FrameSize(sensor: sensor, focalLength: usable(focalLength))
    }

    private static func usable(_ focalLength: Double) -> Double {
        focalLength.isFinite && focalLength > 0 ? focalLength : LensSetup.defaultFocalLengthMillimeters
    }

    /// `2 · atan(extent / 2f)` in degrees. The caller guarantees a positive, finite focal length.
    fileprivate static func angleDegrees(extent: Double, focalLength: Double) -> Double {
        2 * atan(extent / (2 * focalLength)) * 180 / .pi
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
    init(sensor: SensorFormat, focalLength: Double) {
        self.init(
            horizontal: FieldOfView.angleDegrees(extent: sensor.widthMillimeters, focalLength: focalLength),
            vertical: FieldOfView.angleDegrees(extent: sensor.heightMillimeters, focalLength: focalLength),
            diagonal: FieldOfView.angleDegrees(extent: sensor.diagonalMillimeters, focalLength: focalLength)
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
