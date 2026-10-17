import SwiftUI
import LodestarKit

/// A polar-scope reticle with the pole star drawn where it stands now: a clock face, concentric circles around the
/// pole and the star on its circle. 12 o'clock is straight up (towards the zenith).
struct ToolsPolarReticle: View {
    /// Room outside the dial for the hour numbers.
    private static let labelInset: CGFloat = 22
    /// Radius of the circle the pole star travels on, as a fraction of the dial's radius.
    private static let starCircleFraction: CGFloat = 0.58

    @Environment(\.palette) private var palette
    let reading: PolarScopeReading

    var body: some View {
        Canvas { context, size in
            drawReticle(in: &context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Polar scope reticle")
        .accessibilityValue(
            "\(reading.referenceStarName) at \(ToolsPolarClock.text(angle: reading.angle)) o'clock, "
            + "\(AngleFormatter.formatDegrees(reading.separationFromPole, decimals: 2)) from the pole")
    }

    private func drawReticle(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dial = min(size.width, size.height) / 2 - Self.labelInset
        guard dial > 0 else { return }

        func point(radius: CGFloat, angle degrees: Double) -> CGPoint {
            let radians = AstroMath.radians(degrees)
            return CGPoint(x: center.x + radius * CGFloat(sin(radians)), y: center.y - radius * CGFloat(cos(radians)))
        }
        func circle(radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }

        // The dial and its concentric circles.
        context.fill(circle(radius: dial), with: .color(palette.surface))
        context.stroke(circle(radius: dial), with: .color(palette.stroke), lineWidth: 1.5)
        context.stroke(circle(radius: dial * 0.25), with: .color(palette.stroke), lineWidth: 1)
        let starRadius = dial * Self.starCircleFraction
        context.stroke(circle(radius: starRadius), with: .color(palette.tertiaryText), lineWidth: 1.5)

        // Cross hairs through the pole.
        var crossHairs = Path()
        crossHairs.move(to: CGPoint(x: center.x - dial, y: center.y))
        crossHairs.addLine(to: CGPoint(x: center.x + dial, y: center.y))
        crossHairs.move(to: CGPoint(x: center.x, y: center.y - dial))
        crossHairs.addLine(to: CGPoint(x: center.x, y: center.y + dial))
        context.stroke(crossHairs, with: .color(palette.gridLine), lineWidth: 1)

        // Clock ticks every 6°, longer on the hours, and the hour numbers.
        var ticks = Path()
        for step in 0..<60 {
            let angle = Double(step) * 6
            let isHour = step % 5 == 0
            ticks.move(to: point(radius: dial - (isHour ? 9 : 4), angle: angle))
            ticks.addLine(to: point(radius: dial, angle: angle))
        }
        context.stroke(ticks, with: .color(palette.secondaryText), lineWidth: 1)
        for hour in 1...12 {
            let isQuarter = hour % 3 == 0
            let label = Text("\(hour)")
                .font(isQuarter ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(isQuarter ? palette.primaryText : palette.secondaryText)
            context.draw(label, at: point(radius: dial + Self.labelInset / 2 + 1, angle: Double(hour) * 30))
        }

        // The pole.
        context.stroke(circle(radius: 3.5), with: .color(palette.primaryText), lineWidth: 1.5)

        // The pole star on its circle, joined to the pole by a line.
        let star = point(radius: starRadius, angle: reading.angle)
        var spoke = Path()
        spoke.move(to: center)
        spoke.addLine(to: star)
        context.stroke(spoke, with: .color(palette.guidance.opacity(0.6)), lineWidth: 1)
        let halo = Path(ellipseIn: CGRect(x: star.x - 10, y: star.y - 10, width: 20, height: 20))
        context.stroke(halo, with: .color(palette.guidance), lineWidth: 1.5)
        context.fill(Path(ellipseIn: CGRect(x: star.x - 4.5, y: star.y - 4.5, width: 9, height: 9)),
                     with: .color(palette.guidance))
        let name = Text(reading.referenceStarName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.primaryText)
        context.draw(name, at: point(radius: starRadius * 0.62, angle: reading.angle), anchor: .center)
    }
}
