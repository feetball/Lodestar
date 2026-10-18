import SwiftUI
import LodestarKit

/// The geometry of the sky-path drawing: the sky seen from below, north at the top and east on the left, as on a star
/// chart held overhead.
enum SatellitePathModel {
    /// One point of a pass on the sky disc: `x` to the right and `y` up, the horizon on the unit circle, the zenith at 0.
    struct Point: Sendable, Equatable {
        let x: Double
        let y: Double
        let isVisible: Bool
    }

    /// The place on the disc of the direction (`azimuth`, `altitude`) in degrees: the horizon is radius 1, the zenith 0.
    static func project(azimuth: Double, altitude: Double) -> (x: Double, y: Double) {
        let radius = (90 - min(max(altitude, 0), 90)) / 90
        let angle = AstroMath.radians(azimuth)
        return (-sin(angle) * radius, cos(angle) * radius)
    }

    /// The track as points on the disc, each marked visible when the satellite can be seen there.
    static func points(_ looks: [SatelliteLook]) -> [Point] {
        looks.map { look in
            let place = project(azimuth: look.azimuth, altitude: look.altitude)
            return Point(x: place.x, y: place.y, isVisible: look.isVisible())
        }
    }
}

/// The sky path of a pass: rings at 30° and 60° above the horizon, the compass points, the track (solid where the
/// satellite can be seen, dashed where it cannot) and the rise, peak and set. Palette colours only.
struct SatellitePathView: View {
    let looks: [SatelliteLook]
    let peak: SatelliteLook?
    let description: String
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .caption) private var unit: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let margin = 22 * unit
        let radius = min(size.width, size.height) / 2 - margin
        guard radius > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        func place(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: center.x + CGFloat(x) * radius, y: center.y - CGFloat(y) * radius)
        }
        func circle(_ scale: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius * scale, y: center.y - radius * scale,
                                   width: 2 * radius * scale, height: 2 * radius * scale))
        }

        // Rings (30° and 60°), the horizon and the cross.
        for fraction in [CGFloat(2) / 3, CGFloat(1) / 3] {
            context.stroke(circle(fraction), with: .color(palette.gridLine), lineWidth: 1)
        }
        context.stroke(circle(1), with: .color(palette.horizonLine), lineWidth: 1.5)
        var cross = Path()
        cross.move(to: CGPoint(x: center.x, y: center.y - radius))
        cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        cross.move(to: CGPoint(x: center.x - radius, y: center.y))
        cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        context.stroke(cross, with: .color(palette.gridLine), lineWidth: 1)
        let compassFont = Font.system(size: 13 * unit, weight: .semibold)
        let outside = 1 + 14 * unit / radius
        for (name, x, y) in [("N", 0.0, 1.0), ("E", -1.0, 0.0), ("S", 0.0, -1.0), ("W", 1.0, 0.0)] {
            context.draw(Text(name).font(compassFont).foregroundStyle(palette.primaryText),
                         at: place(x * Double(outside), y * Double(outside)), anchor: .center)
        }

        let points = SatellitePathModel.points(looks)
        guard points.count >= 2 else { return }
        var solid = Path()
        var dashed = Path()
        for index in 1..<points.count {
            let from = points[index - 1]
            let to = points[index]
            if from.isVisible && to.isVisible {
                solid.move(to: place(from.x, from.y))
                solid.addLine(to: place(to.x, to.y))
            } else {
                dashed.move(to: place(from.x, from.y))
                dashed.addLine(to: place(to.x, to.y))
            }
        }
        context.stroke(dashed, with: .color(palette.tertiaryText),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
        context.stroke(solid, with: .color(palette.accent), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

        // Rise, peak and set.
        mark("Rise", at: place(points[0].x, points[0].y), center: center, isFilled: false, in: &context)
        if let last = points.last {
            mark("Set", at: place(last.x, last.y), center: center, isFilled: false, in: &context)
        }
        if let peak {
            let spot = SatellitePathModel.project(azimuth: peak.azimuth, altitude: peak.altitude)
            mark("Peak", at: place(spot.x, spot.y), center: center, isFilled: true, in: &context)
        }
    }

    /// A dot at `point` with `label` on the side away from the `center`; the peak is a filled, larger dot.
    private func mark(_ label: String, at point: CGPoint, center: CGPoint, isFilled: Bool, in context: inout GraphicsContext) {
        let dot = (isFilled ? 6 : 4.5) * unit
        let rect = CGRect(x: point.x - dot, y: point.y - dot, width: 2 * dot, height: 2 * dot)
        if isFilled {
            context.fill(Path(ellipseIn: rect), with: .color(palette.accent))
        } else {
            context.fill(Path(ellipseIn: rect), with: .color(palette.background))
            context.stroke(Path(ellipseIn: rect), with: .color(palette.primaryText), lineWidth: 2)
        }
        let away = CGVector(dx: point.x - center.x, dy: point.y - center.y)
        let length = max(hypot(away.dx, away.dy), 1e-3)
        let distance = (12 + 8) * unit
        let text = Text(label).font(.system(size: 11 * unit)).foregroundStyle(palette.secondaryText)
        context.draw(text, at: CGPoint(x: point.x + away.dx / length * distance, y: point.y + away.dy / length * distance),
                     anchor: .center)
    }
}
