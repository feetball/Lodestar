import SwiftUI
import LodestarKit

/// The camera's frame held in the middle of the chart, for planning a picture: the chart is moved under the frame
/// instead of the frame following the phone, as on the Aim screen.
///
/// The frame is kept on the sky, not on the chart: its centre as a J2000 position and its rotation as a position angle,
/// the angle of the picture's top edge from celestial north counted through east. Both stay the same as the sky turns,
/// as they do for a camera on a star tracker, so the frame holds the same stars at any time of the night; the chart is
/// placed so that the centre is in the middle of the view. `roll`, the tilt of the frame against the horizon, is what a
/// camera on a plain tripod needs.
struct SkyChartFraming {
    /// A turn of the frame snaps to the multiples of this angle (degrees) that it comes within `snapTolerance` of.
    static let snapStep = 90.0
    static let snapTolerance = 2.0
    /// The length (degrees) of the small step on the sky that finds the picture's up direction.
    private static let probeStep = 0.1
    /// Points along each edge of the picture's border.
    private static let samplesPerEdge = 8

    /// The direction of the frame's centre at the chart's instant, apparent, as an East–North–Up unit vector.
    let center: Vector3
    let horizontal: HorizontalCoordinate
    /// The J2000 position of the frame's centre.
    let equatorial: EquatorialCoordinate
    /// The angle of the picture's top edge from celestial north through east, in degrees.
    let positionAngle: Double
    /// The tilt of the picture against the horizon in degrees, positive when it is turned clockwise as the photographer
    /// sees it (its right side lower); `nil` at the zenith, where the horizon gives no direction.
    let roll: Double?
    /// The position angle that levels the frame with the horizon here, keeping it as near as it is now; `nil` close to
    /// the zenith.
    let levelledPositionAngle: Double?
    /// The border of the picture as directions, clockwise as the photographer sees it, from the top-left corner.
    let outline: [Vector3]
    /// The middle of the picture's top edge, where the mark that shows which way is up goes.
    let topMiddle: Vector3

    /// The frame of a camera with the field of view `size` (landscape), centred on the J2000 position `equatorial`
    /// with the position angle `positionAngle`, at the instant of `frame`; `nil` when the field of view cannot be drawn.
    init?(center equatorial: EquatorialCoordinate, frame: SkyFrame, size: FrameSize, positionAngle: Double) {
        guard size.horizontal > 0, size.vertical > 0, size.horizontal < 180, size.vertical < 180 else { return nil }
        let center = frame.horizontal(j2000: equatorial).unitVector
        let horizontal = HorizontalCoordinate(vector: center)
        guard let up = Self.upDirection(at: center, equatorial: equatorial, positionAngle: positionAngle,
                                        frame: frame) else { return nil }
        // As for a camera: right is forward × up.
        let right = center.cross(up)
        let halfWidth = AstroMath.tanDeg(size.horizontal / 2)
        let halfHeight = AstroMath.tanDeg(size.vertical / 2)

        // The same border as `PinholeProjection.dslrFrameOutline` draws for a pointing of the phone.
        let corners = [(-1.0, 1.0), (1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)]
        var outline: [Vector3] = []
        outline.reserveCapacity(4 * Self.samplesPerEdge)
        for edge in 0..<4 {
            let start = corners[edge], end = corners[(edge + 1) % 4]
            for step in 0..<Self.samplesPerEdge {
                let t = Double(step) / Double(Self.samplesPerEdge)
                let x = (start.0 + (end.0 - start.0) * t) * halfWidth
                let y = (start.1 + (end.1 - start.1) * t) * halfHeight
                outline.append((center + right * x + up * y).normalized)
            }
        }

        self.center = center
        self.horizontal = horizontal
        self.equatorial = equatorial
        self.positionAngle = AstroMath.normalizeDegrees(positionAngle)
        self.roll = Self.roll(of: up, at: center)
        self.levelledPositionAngle = Self.levelledPositionAngle(at: horizontal, equatorial: equatorial,
                                                                positionAngle: positionAngle, frame: frame)
        self.outline = outline
        self.topMiddle = (center + up * halfHeight).normalized
    }

    // MARK: Placing the chart

    /// The pan that puts `center` (J2000) in the middle of a view of `size` at `zoom` and `rotation`, at the instant
    /// of `frame`. A centre below the horizon is held on the horizon circle, towards its azimuth.
    static func pan(centering center: EquatorialCoordinate, frame: SkyFrame, size: CGSize, zoom: CGFloat,
                    rotation: Double) -> CGSize {
        let direction = frame.horizontal(j2000: center).unitVector
        let point = direction.z >= 0
            ? PlanisphereProjection.chartPoint(direction)
            : PlanisphereProjection.unitVector(towardsAzimuth: HorizontalCoordinate(vector: direction).azimuth)
        // The inverse of `PlanisphereViewport.screen(_:)` for the middle: centre + radius × rotated(point) = middle.
        let radius = PlanisphereViewport.baseRadius(in: size) * zoom
        let cosine = CGFloat(cos(rotation)), sine = CGFloat(sin(rotation))
        return CGSize(width: -radius * (point.x * cosine - point.y * sine),
                      height: -radius * (point.x * sine + point.y * cosine))
    }

    /// The J2000 position at `position` (a point of the view) in `viewport`, at the instant of `frame`. A point outside
    /// the horizon circle counts as the horizon in its direction, so a frame dragged off the sky stops at the horizon.
    static func skyPosition(atScreen position: CGPoint, in viewport: PlanisphereViewport,
                            frame: SkyFrame) -> EquatorialCoordinate {
        var point = viewport.chartPoint(atScreen: position)
        let length = hypot(point.x, point.y)
        if length > 1 { point = CGPoint(x: point.x / length, y: point.y / length) }
        let direction = PlanisphereProjection.direction(ofChartPoint: point)
        return frame.j2000(fromHorizontal: HorizontalCoordinate(vector: direction), refracted: true)
    }

    // MARK: Keeping the centre

    /// The centre as text for saving: "RA,Dec" in degrees, or empty without one.
    static func encode(_ center: EquatorialCoordinate?) -> String {
        guard let center else { return "" }
        return "\(center.rightAscension),\(center.declination)"
    }

    /// The centre saved by `encode(_:)`, or `nil` for anything else.
    static func decode(_ text: String) -> EquatorialCoordinate? {
        let parts = text.split(separator: ",")
        guard parts.count == 2, let rightAscension = Double(parts[0]), let declination = Double(parts[1]),
              rightAscension.isFinite, declination.isFinite, abs(declination) <= 90 else { return nil }
        return EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
    }

    /// `angle` in [0, 360), moved onto a multiple of `snapStep` when it lies within `snapTolerance` of one.
    static func snapped(_ angle: Double) -> Double {
        let normalized = AstroMath.normalizeDegrees(angle)
        let nearest = (normalized / snapStep).rounded() * snapStep
        return abs(normalized - nearest) <= snapTolerance ? AstroMath.normalizeDegrees(nearest) : normalized
    }

    // MARK: Geometry

    /// The unit vectors towards celestial north and east on the sky at `equatorial`, in J2000 coordinates.
    private static func northAndEast(at equatorial: EquatorialCoordinate) -> (north: Vector3, east: Vector3) {
        let alpha = equatorial.rightAscension
        let delta = equatorial.declination
        let north = Vector3(-AstroMath.sinDeg(delta) * AstroMath.cosDeg(alpha),
                            -AstroMath.sinDeg(delta) * AstroMath.sinDeg(alpha),
                            AstroMath.cosDeg(delta))
        return (north, Vector3(-AstroMath.sinDeg(alpha), AstroMath.cosDeg(alpha), 0))
    }

    /// The picture's up direction at `center`: where a short step on the sky at `positionAngle` from celestial north
    /// lands, as a unit vector at right angles to `center`. Stepping in J2000 coordinates and taking the step's end
    /// through the frame keeps refraction and precession out of the way.
    private static func upDirection(at center: Vector3, equatorial: EquatorialCoordinate, positionAngle: Double,
                                    frame: SkyFrame) -> Vector3? {
        let axes = northAndEast(at: equatorial)
        let heading = axes.north * AstroMath.cosDeg(positionAngle) + axes.east * AstroMath.sinDeg(positionAngle)
        let probe = EquatorialCoordinate(vector: equatorial.unitVector * AstroMath.cosDeg(probeStep)
            + heading * AstroMath.sinDeg(probeStep))
        let step = frame.horizontal(j2000: probe).unitVector - center
        let tangent = step - center * step.dot(center)
        let length = tangent.length
        guard length > 1e-12 else { return nil }
        return tangent / length
    }

    /// The position angle nearest to `positionAngle` at which the frame's edges run level with the horizon or upright:
    /// the J2000 direction of a short step upwards from `horizontal` gives the upright frame, and its quarter turns
    /// the others, so a frame in portrait stays in portrait. Solved through the inverse transformation because
    /// refraction lifts the sky more than it shifts it sideways, so a turn by the roll alone does not quite level a
    /// frame near the horizon.
    private static func levelledPositionAngle(at horizontal: HorizontalCoordinate, equatorial: EquatorialCoordinate,
                                              positionAngle: Double, frame: SkyFrame) -> Double? {
        guard horizontal.altitude + probeStep < 90 else { return nil }
        let raised = HorizontalCoordinate(azimuth: horizontal.azimuth, altitude: horizontal.altitude + probeStep)
        let step = frame.j2000(fromHorizontal: raised, refracted: true).unitVector - equatorial.unitVector
        let axes = northAndEast(at: equatorial)
        let north = step.dot(axes.north), east = step.dot(axes.east)
        guard north * north + east * east > 1e-24 else { return nil }
        let upright = AstroMath.atan2Deg(east, north)
        // The quarter turn of `upright` nearest to the present angle.
        let turns = (AstroMath.normalizeSignedDegrees(positionAngle - upright) / 90).rounded()
        return AstroMath.normalizeDegrees(upright + 90 * turns)
    }

    /// The angle from the level up direction at `center` to `up`, clockwise as the photographer sees it, in degrees.
    private static func roll(of up: Vector3, at center: Vector3) -> Double? {
        let towardsZenith = Vector3(0, 0, 1) - center * center.z
        let length = towardsZenith.length
        guard length > 1e-6 else { return nil }
        let levelUp = towardsZenith / length
        let levelRight = center.cross(levelUp)
        return AstroMath.atan2Deg(up.dot(levelRight), up.dot(levelUp))
    }
}

/// The fixed camera frame on the chart: the picture's border, a mark outside the middle of its top edge, and a small
/// cross in the middle of the view.
struct SkyChartFramingCanvas: View {
    let framing: SkyChartFraming
    let viewport: PlanisphereViewport
    let palette: Palette

    var body: some View {
        Canvas { context, _ in
            var sky = context
            sky.clip(to: Path(ellipseIn: viewport.discRect))
            let color = GraphicsContext.Shading.color(palette.dslrFrame)
            if let first = framing.outline.first {
                var border = Path()
                for polyline in PlanisphereProjection.visiblePolylines(through: framing.outline + [first]) {
                    border.addPath(PlanisphereShapes.polyline(polyline.map(viewport.screen)))
                }
                sky.stroke(border, with: color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            if let mark = topMark() {
                sky.fill(mark, with: color)
            }
            sky.stroke(PlanisphereShapes.axisTicks(around: viewport.middle, from: 3, to: 9), with: color, lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A small triangle just outside the top edge, pointing away from the middle; `nil` when the frame is too small
    /// on the screen for it to tell anything, or the top edge is below the horizon.
    private func topMark() -> Path? {
        guard framing.topMiddle.z >= 0 else { return nil }
        let middle = viewport.middle
        let top = viewport.screen(PlanisphereProjection.chartPoint(framing.topMiddle))
        let dx = top.x - middle.x, dy = top.y - middle.y
        let distance = hypot(dx, dy)
        guard distance >= 8 else { return nil }
        let along = CGPoint(x: dx / distance, y: dy / distance)
        let across = CGPoint(x: -along.y, y: along.x)
        var mark = Path()
        mark.move(to: CGPoint(x: top.x + along.x * 10, y: top.y + along.y * 10))
        mark.addLine(to: CGPoint(x: top.x + along.x * 3 + across.x * 6, y: top.y + along.y * 3 + across.y * 6))
        mark.addLine(to: CGPoint(x: top.x + along.x * 3 - across.x * 6, y: top.y + along.y * 3 - across.y * 6))
        mark.closeSubpath()
        return mark
    }
}

/// The panel under the fixed camera frame: the lens, where the frame is and how it is turned, and buttons to turn
/// it, to level it and to aim at its middle.
struct SkyChartFramingBar: View {
    @Environment(\.palette) private var palette
    /// `nil` while the middle of the view is off the sky.
    let framing: SkyChartFraming?
    let lens: LensSetup
    let coordinateStyle: CoordinateStyle
    /// Whether the chart shows the present; if not, the altitude and azimuth are those of the chart's time.
    let isLive: Bool
    @Binding var positionAngle: Double
    let onAim: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(lensText, systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer(minLength: 4)
                Text(rotationText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette.dslrFrame)
                    .accessibilityLabel("Frame rotation")
                    .accessibilityValue(spokenRotation)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: positionAngle = SkyChartFraming.snapped(positionAngle + 5)
                        case .decrement: positionAngle = SkyChartFraming.snapped(positionAngle - 5)
                        @unknown default: break
                        }
                    }
            }
            if let framing {
                VStack(alignment: .leading, spacing: 1) {
                    Text("RA \(AppFormat.rightAscension(framing.equatorial, style: coordinateStyle)) \u{00B7} "
                         + "Dec \(AppFormat.declination(framing.equatorial, style: coordinateStyle))")
                    Text("Az \(AppFormat.azimuth(framing.horizontal.azimuth)) \u{00B7} "
                         + "Alt \(AppFormat.altitude(framing.horizontal.altitude))"
                         + (isLive ? "" : " at the chart's time"))
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(palette.secondaryText)
                .accessibilityElement(children: .combine)
                if framing.horizontal.altitude < 0 {
                    Label("Below the horizon", systemImage: "arrow.down.to.line")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.warning)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
            Text("Drag the sky under the frame. Hold, then drag, to turn it.")
                .font(.caption)
                .foregroundStyle(palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(palette, padding: 12)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            positionAngle = AstroMath.normalizeDegrees(positionAngle + 90)
        } label: {
            Label("90\u{00B0}", systemImage: "rotate.left")
        }
        .buttonStyle(.lodestarSecondary)
        .accessibilityLabel("Turn the frame a quarter turn")
        Button {
            if let levelled = framing?.levelledPositionAngle { positionAngle = levelled }
        } label: {
            Label("Level", systemImage: "level")
        }
        .buttonStyle(.lodestarSecondary)
        .disabled(framing?.levelledPositionAngle == nil)
        .accessibilityLabel("Level the frame with the horizon")
        Button("Aim here", action: onAim)
            .buttonStyle(.lodestarPrimary)
            .disabled(framing == nil)
            .accessibilityLabel("Aim at the middle of the frame")
    }

    /// "24 mm · 74° × 53°".
    private var lensText: String {
        let size = lens.fieldOfView
        let focal = lens.focalLengthMillimeters.formatted(.number.precision(.fractionLength(0)))
        return "\(focal) mm \u{00B7} \(degrees(size.horizontal)) \u{00D7} \(degrees(size.vertical))"
    }

    /// "PA 32° · roll −12°", with only the position angle at the zenith.
    private var rotationText: String {
        // Wrapped after rounding, so 359.6° reads "0°", not "360°".
        let angle = "PA \(AngleFormatter.formatAzimuth(positionAngle, decimals: 0))"
        guard let roll = framing?.roll else { return angle }
        return "\(angle) \u{00B7} roll \(AngleFormatter.formatSignedDegrees(roll, decimals: 0))"
    }

    private var spokenRotation: String {
        var text = "position angle \(Int(positionAngle.rounded()) % 360) degrees"
        if let roll = framing?.roll {
            text += ", tilted \(Int(abs(roll).rounded())) degrees \(roll < 0 ? "anticlockwise" : "clockwise") from level"
        }
        return text
    }

    /// An angle with one decimal below 10°, as "6.8°" or "74°".
    private func degrees(_ value: Double) -> String {
        AngleFormatter.formatDegrees(value, decimals: value < 10 ? 1 : 0)
    }
}
