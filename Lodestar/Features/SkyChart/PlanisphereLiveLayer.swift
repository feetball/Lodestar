import SwiftUI
import LodestarKit

/// Where the camera points, from the phone's attitude, the mount and the star alignment.
struct SkyChartCameraPose {
    /// Azimuth and altitude of the camera's optical axis.
    let horizontal: HorizontalCoordinate
    let boresight: Vector3
    /// The border of the DSLR picture as directions, clockwise as the photographer sees it.
    let footprint: [Vector3]

    /// The pose for the newest motion sample, or `nil` while the sensors deliver none.
    @MainActor
    static func current(from motion: MotionService, mount: MountProfile, alignment: AlignmentModel,
                        frame: FrameSize) -> SkyChartCameraPose? {
        guard let sample = motion.latestSample() else { return nil }
        let solution = PointingSolution.solve(attitude: sample.attitude, mount: mount, alignment: alignment)
        let outline = PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: frame.horizontal,
                                                         verticalFOV: frame.vertical, samplesPerEdge: 6)
        return SkyChartCameraPose(horizontal: solution.boresight, boresight: solution.boresightVector,
                                  footprint: outline)
    }
}

/// Remembers the last well-defined camera heading. Close to the zenith the azimuth of the optical
/// axis is meaningless and jumps about, so a chart that follows the heading keeps its rotation there.
@MainActor
final class SkyChartHeadingHold {
    /// Above this altitude (degrees) the azimuth is too unreliable to follow.
    private static let followLimit = 85.0

    private var rotation = 0.0

    /// The chart rotation in radians that puts the camera's azimuth at the top of the chart.
    func rotation(for pose: SkyChartCameraPose?) -> Double {
        if let pose, pose.horizontal.altitude < Self.followLimit {
            rotation = AstroMath.radians(pose.horizontal.azimuth)
        }
        return rotation
    }
}

/// The camera's crosshair and the footprint of the DSLR picture, drawn over the chart.
///
/// A camera that points below the horizon is shown as an arrow on the horizon circle, towards its azimuth.
struct PlanisphereLiveCanvas: View {
    let pose: SkyChartCameraPose?
    let viewport: PlanisphereViewport
    let palette: Palette
    /// Off while the camera frame is fixed in the middle of the chart: the crosshair alone shows where the phone points.
    var showsFootprint = true

    var body: some View {
        Canvas { context, _ in
            guard let pose else { return }
            var sky = context
            sky.clip(to: Path(ellipseIn: viewport.discRect))
            if showsFootprint { drawFootprint(of: pose, in: &sky) }
            if pose.boresight.z >= 0 {
                drawCrosshair(at: viewport.screen(PlanisphereProjection.chartPoint(pose.boresight)), in: &sky)
            } else {
                context.fill(viewport.rimArrow(towards: pose.horizontal.azimuth), with: .color(palette.dslrFrame))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawFootprint(of pose: SkyChartCameraPose, in context: inout GraphicsContext) {
        guard let first = pose.footprint.first else { return }
        var path = Path()
        for polyline in PlanisphereProjection.visiblePolylines(through: pose.footprint + [first]) {
            path.addPath(PlanisphereShapes.polyline(polyline.map(viewport.screen)))
        }
        context.stroke(path, with: .color(palette.dslrFrame), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private func drawCrosshair(at center: CGPoint, in context: inout GraphicsContext) {
        let radius: CGFloat = 9
        var path = PlanisphereShapes.circle(around: center, radius: radius)
        path.addPath(PlanisphereShapes.axisTicks(around: center, from: radius - 3, to: radius + 7))
        context.stroke(path, with: .color(palette.dslrFrame), lineWidth: 1.5)
        context.fill(PlanisphereShapes.circle(around: center, radius: 1.5), with: .color(palette.dslrFrame))
    }
}

/// The camera's azimuth and altitude as a status chip.
struct SkyChartCameraReadout: View {
    let pose: SkyChartCameraPose

    var body: some View {
        let azimuth = pose.horizontal.azimuth
        let compass = AngleFormatter.compassPoint(azimuth: azimuth)
        let altitude = pose.horizontal.altitude
        let text = "\(AngleFormatter.formatAzimuth(azimuth, decimals: 0)) \(compass.abbreviation) \u{00B7} "
            + AngleFormatter.formatSignedDegrees(altitude, decimals: 0)
        StatusChip(systemImage: "scope", text: text)
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Camera pointing \(compass.fullName), altitude \(Int(altitude.rounded())) degrees")
    }
}
