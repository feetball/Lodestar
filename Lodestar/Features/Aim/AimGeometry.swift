import CoreGraphics
import Foundation
import LodestarKit

/// Builds the pinhole projection that lays the sky over the screen.
enum AimProjectionFactory {
    /// The range of the virtual lens, as the field of view along the screen's long side in degrees.
    static let virtualFieldOfViewRange: ClosedRange<Double> = 20...100
    static let defaultVirtualFieldOfView = 60.0
    /// The fields of view the zoom button steps through, widest first.
    static let virtualFieldOfViewPresets: [Double] = [100, 60, 40, 20]

    /// The projection for a viewport. With the optics of a running camera the focal length makes the overlay
    /// match the aspect-filled picture exactly; without one a virtual lens of `virtualFieldOfView` is used.
    /// `nil` when the viewport is empty.
    static func projection(viewport: CGSize, camera: CameraGeometry?, virtualFieldOfView: Double) -> PinholeProjection? {
        let width = Double(viewport.width), height = Double(viewport.height)
        if let camera, let focalLength = focalLength(filling: viewport, camera: camera) {
            return PinholeProjection(viewportWidth: width, viewportHeight: height, focalLength: focalLength)
        }
        let fieldOfView = AstroMath.clamp(virtualFieldOfView, virtualFieldOfViewRange.lowerBound,
                                          virtualFieldOfViewRange.upperBound)
        return PinholeProjection(viewportWidth: width, viewportHeight: height, longSideFieldOfView: fieldOfView)
    }

    /// The focal length, in points, of a picture that is scaled to cover `viewport` (aspect fill).
    ///
    /// The picture grows until both of its sides reach the viewport; the side with the larger ratio then fits
    /// exactly and the other one is cropped. The focal length follows from the field of view across the side
    /// that fits: `f = scale · pixels / 2 / tan(fov / 2)`.
    static func focalLength(filling viewport: CGSize, camera: CameraGeometry) -> Double? {
        guard camera.imageWidth > 0, camera.imageHeight > 0, viewport.width > 0, viewport.height > 0 else { return nil }
        let imageWidth = Double(camera.imageWidth), imageHeight = Double(camera.imageHeight)
        let widthScale = Double(viewport.width) / imageWidth
        let heightScale = Double(viewport.height) / imageHeight
        let fitsWidth = widthScale >= heightScale
        let scale = fitsWidth ? widthScale : heightScale
        let pixels = fitsWidth ? imageWidth : imageHeight
        let fieldOfView = fitsWidth ? camera.portraitHorizontalFOV : camera.portraitVerticalFOV
        guard fieldOfView.isFinite, fieldOfView > 0, fieldOfView < 180 else { return nil }
        return scale * pixels / 2 / AstroMath.tanDeg(fieldOfView / 2)
    }
}

extension AimProjectionFactory {
    /// The attitude of a virtual device whose back camera looks along the lens, with the screen axes the guidance uses.
    ///
    /// The phone's own back camera sees what the lens sees only when the phone is clamped with its camera towards the
    /// scene. A phone lying on top of the camera looks at the ground instead, so the sky is drawn as seen from the
    /// lens: `PointingSolution` gives the lens direction and the world directions that the phone's screen draws as
    /// right and up, which are the axes the arrow and the off-screen indicator use as well. `nil` if they do not
    /// form a rotation.
    static func lensViewAttitude(for pointing: PointingSolution) -> DeviceAttitude? {
        let worldToScreen = Matrix3(rows: pointing.screenRightVector, pointing.screenUpVector, pointing.boresightVector * -1)
        // `worldToDevice` is the matrix times the reference transform, so undo that to get the matrix.
        let matrix = worldToScreen * DeviceAttitude.referenceTransform(azimuth: 0).transposed
        return DeviceAttitude(matrix: matrix, referenceAzimuth: 0, timestamp: 0)
    }
}

/// How far the HUD is turned, clockwise in quarter turns, so that it reads upright when the phone is clamped
/// sideways (or upside down) on the camera.
enum AimHUDRotation: Int, Sendable {
    case upright = 0
    case clockwise = 90
    case upsideDown = 180
    case counterclockwise = 270

    /// Below this length of gravity's component in the screen plane the phone counts as lying flat and its
    /// orientation is undefined.
    private static let flatThreshold = 0.3
    /// The HUD follows the phone only once the phone is turned more than this many degrees from the HUD's current
    /// rotation. A quarter-turn boundary lies at 45°, so the margin beyond it keeps the HUD from flipping back and
    /// forth.
    private static let hysteresis = 55.0

    var degrees: Double { Double(rawValue) }

    /// `true` when the HUD's width and height trade places.
    var swapsAxes: Bool { self == .clockwise || self == .counterclockwise }

    /// The rotation for a gravity vector in device coordinates (unit g).
    ///
    /// World-up seen on the screen is `(−g.x, −g.y)`; the HUD turns clockwise by that direction's angle from
    /// the screen's top. The current rotation is kept while the phone lies (nearly) flat and while it stays
    /// within the hysteresis band, so the HUD does not flip back and forth near a boundary. Without a current
    /// rotation a flat phone gets the rotation that suits the mount.
    static func updated(from current: AimHUDRotation?, gravity: Vector3, mount: MountProfile) -> AimHUDRotation {
        let inPlane = (gravity.x * gravity.x + gravity.y * gravity.y).squareRoot()
        guard inPlane >= flatThreshold else { return current ?? restingRotation(for: mount) }
        let angle = AstroMath.atan2Deg(-gravity.x, -gravity.y)
        if let current, abs(AstroMath.normalizeSignedDegrees(angle - current.degrees)) <= hysteresis {
            return current
        }
        let quarterTurns = ((Int((angle / 90).rounded()) % 4) + 4) % 4
        return AimHUDRotation(rawValue: quarterTurns * 90) ?? .upright
    }

    /// A phone lying on the camera is read from behind it: with the top edge towards the photographer the
    /// text is upside down.
    private static func restingRotation(for mount: MountProfile) -> AimHUDRotation {
        mount.cameraAxis.y < -0.7 ? .upsideDown : .upright
    }

    /// `offset`, given as seen by the reader, turned to where it lies on the screen.
    func rotated(_ offset: CGSize) -> CGSize {
        let angle = AstroMath.radians(degrees)
        let cosine = CGFloat(cos(angle)), sine = CGFloat(sin(angle))
        return CGSize(width: offset.width * cosine - offset.height * sine,
                      height: offset.width * sine + offset.height * cosine)
    }
}

/// Text for the angles on the Aim screen.
enum AimFormat {
    /// An angle for the readouts: one decimal from 1°, arcminutes or arcseconds below.
    static func angle(_ degrees: Double) -> String {
        guard degrees.isFinite else { return AppFormat.missing }
        let magnitude = abs(degrees)
        if magnitude >= 1 { return AngleFormatter.formatDegrees(magnitude, decimals: 1) }
        return AppFormat.separation(magnitude)
    }

    /// An angle as spoken by VoiceOver: "23 degrees", "1 degree", "under one degree".
    static func spoken(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "unknown" }
        let whole = Int(min(abs(degrees), 360).rounded())
        switch whole {
        case 0: return "under one degree"
        case 1: return "1 degree"
        default: return "\(whole) degrees"
        }
    }
}
