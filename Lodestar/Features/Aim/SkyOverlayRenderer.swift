import SwiftUI
import LodestarKit

/// Paints one frame of the sky overlay: Milky Way, grid, constellations, horizon, deep-sky objects, stars, planets,
/// the ground below the recorded skyline, the panels of a mosaic, the DSLR frame, the target (or the panel being
/// aimed at) and the reticle, followed by their labels.
///
/// Everything is projected with the phone's own back camera, the heading offset applied and the DSLR's device
/// correction not; only the DSLR frame itself comes from the corrected pointing. (A phone that lies on top of the
/// camera cannot see the sky through its back camera: then the sky is drawn as seen from the lens.) The renderer is a
/// plain value made for each frame, so it can be reasoned about (and tested) without a view.
struct SkyOverlayRenderer {
    /// The altitude/azimuth grid appears when the long side of the screen shows no more than this many degrees.
    static let gridMaximumFieldOfView = 50.0
    /// Margin in points by which strokes may run past the screen edge before they are cut.
    static let clipMargin = 12.0

    let frame: AimFrame
    let content: AimSkyContent?
    let configuration: AimConfiguration
    let palette: Palette
    let size: CGSize
    /// Seconds on a continuous clock; drives the pulse of the target ring.
    let time: TimeInterval
    let hudRotation: AimHUDRotation
    /// The step of the mosaic being shot, or `nil` without one.
    let mosaic: MosaicDisplay?

    let projector: AimProjector
    let frustum: AimFrustum
    let viewport: CGRect
    /// The optical axis of the eye the sky is seen from, in world coordinates.
    let boresight: Vector3
    /// Rotation from world directions to the eye's axes: x right, y up, z backwards (the eye looks along −z).
    let worldToDevice: Matrix3
    /// Screen points per degree at the centre of the view.
    let pointsPerDegree: Double
    /// Field of view along the screen's long side, degrees.
    let fieldOfView: Double
    /// Angle in degrees from the centre of the view to just beyond a corner.
    let viewRadius: Double

    var labels = AimLabelQueue()

    /// - Parameters:
    ///   - camera: The optics of the running camera picture, or `nil` to use the virtual lens.
    /// - Returns: `nil` when the screen is empty.
    init?(frame: AimFrame, content: AimSkyContent?, configuration: AimConfiguration, palette: Palette,
          camera: CameraGeometry?, virtualFieldOfView: Double, hudRotation: AimHUDRotation, time: TimeInterval,
          mosaic: MosaicDisplay?, size: CGSize) {
        guard let projection = AimProjectionFactory.projection(viewport: size, camera: camera,
                                                               virtualFieldOfView: virtualFieldOfView) else {
            return nil
        }
        // The phone's camera is the eye while the picture runs (the overlay has to match it) and whenever it looks along
        // the lens; otherwise the lens is.
        let eye: DeviceAttitude
        let headingOffset: Double
        if camera != nil || configuration.phoneCameraFollowsLens {
            eye = frame.sample.attitude
            headingOffset = configuration.headingOffset
        } else if let lensView = AimProjectionFactory.lensViewAttitude(for: frame.pointing) {
            eye = lensView
            headingOffset = 0
        } else {
            return nil
        }
        let attitude = eye.withHeadingOffset(headingOffset)
        self.frame = frame
        self.content = content
        self.configuration = configuration
        self.palette = palette
        self.size = size
        self.time = time
        self.hudRotation = hudRotation
        self.mosaic = mosaic
        projector = AimProjector(projection: projection, attitude: eye, headingOffset: headingOffset)
        frustum = AimFrustum(projection: projection, attitude: eye, headingOffset: headingOffset,
                             margin: Self.clipMargin)
        viewport = CGRect(origin: .zero, size: size)
        boresight = attitude.deviceToWorld * DeviceAttitude.backCameraAxis
        worldToDevice = attitude.worldToDevice
        pointsPerDegree = projection.focalLength * AstroMath.radiansPerDegree
        fieldOfView = projection.longSideFieldOfView
        viewRadius = AstroMath.degrees(atan(hypot(projection.viewportWidth, projection.viewportHeight) / 2
            / projection.focalLength)) + 3
    }

    mutating func draw(in context: GraphicsContext) {
        drawMilkyWay(in: context)
        drawGrid(in: context)
        drawConstellations(in: context)
        drawHorizon(in: context)
        drawDeepSky(in: context)
        drawStars(in: context)
        drawBodies(in: context)
        drawSkyline(in: context)
        drawMosaic(in: context)
        drawDSLRFrame(in: context)
        drawTarget(in: context)
        drawReticle(in: context)
        labels.draw(in: context, bounds: viewport, rotation: hudRotation)
    }

    // MARK: Helpers

    /// `true` when `point` is on the screen, grown by `margin` points on every side.
    func isVisible(_ point: CGPoint, margin: CGFloat = 4) -> Bool {
        viewport.insetBy(dx: -margin, dy: -margin).contains(point)
    }

    /// Queues `text` next to `point`; `offset` is given as the reader sees it and follows the HUD's rotation.
    mutating func addLabel(_ text: String, near point: CGPoint, offset: CGSize = .zero, style: AimLabelStyle,
                           priority: Int) {
        let shift = hudRotation.rotated(offset)
        labels.add(text, at: CGPoint(x: point.x + shift.width, y: point.y + shift.height), style: style,
                   priority: priority)
    }

    func ellipse(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
