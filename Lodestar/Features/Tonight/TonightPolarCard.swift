import SwiftUI
import LodestarKit

/// Where the pole star stands against the celestial pole right now, as a clock position, with a way into the full
/// Polar Alignment tool.
struct TonightPolarCard: View {
    @Environment(\.palette) private var palette
    @State private var showsInvertedView = false

    let observer: Observer
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Polar Alignment", systemImage: "location.north.line")
            // The star moves a quarter of a degree a minute, so the reading is refreshed twice a minute.
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let frame = SkyFrame(date: timeline.date, observer: observer)
                let reading = PolarAlignment.polarScopeReading(frame: frame,
                                                               view: showsInvertedView ? .inverted : .naked)
                HStack(spacing: 16) {
                    TonightPolarReticle(reading: reading)
                        .frame(width: 128, height: 128)
                    readout(reading: reading, date: timeline.date)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spokenReading(reading))
            }
            Toggle("Polar scope view (inverted)", isOn: $showsInvertedView)
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
            NavigationLink {
                PolarAlignmentView()
            } label: {
                Label("Open Polar Alignment", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func readout(reading: PolarScopeReading, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(TonightFormat.clockPosition(angle: reading.angle))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
            Text("\(reading.referenceStarName) on its circle")
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
            Text("\(AngleFormatter.formatDegrees(reading.separationFromPole, decimals: 2)) from the pole")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
            Text("Right now, \(AppFormat.time(date, in: timeZone))")
                .font(.footnote)
                .foregroundStyle(palette.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spokenReading(_ reading: PolarScopeReading) -> String {
        "\(reading.referenceStarName) is at \(TonightFormat.clockPosition(angle: reading.angle)) o'clock on the"
            + " polar scope circle, \(AngleFormatter.formatDegrees(reading.separationFromPole, decimals: 2))"
            + " from the pole"
    }
}

/// A small polar-scope reticle with the pole star drawn at its clock position; 12 o'clock is straight up.
private struct TonightPolarReticle: View {
    /// Room outside the dial for the hour numbers.
    private static let labelInset: CGFloat = 14
    /// Radius of the circle the pole star travels on, as a fraction of the dial's radius.
    private static let starCircleFraction: CGFloat = 0.6

    @Environment(\.palette) private var palette
    let reading: PolarScopeReading

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dial = min(size.width, size.height) / 2 - Self.labelInset
        guard dial > 0 else { return }

        func point(radius: CGFloat, degrees: Double) -> CGPoint {
            let radians = AstroMath.radians(degrees)
            return CGPoint(x: center.x + radius * CGFloat(sin(radians)), y: center.y - radius * CGFloat(cos(radians)))
        }
        func circle(radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }

        // The dial, the circle the star travels on and the cross hairs through the pole.
        context.fill(circle(radius: dial), with: .color(palette.surfaceRaised))
        context.stroke(circle(radius: dial), with: .color(palette.stroke), lineWidth: 1.5)
        let starRadius = dial * Self.starCircleFraction
        context.stroke(circle(radius: starRadius), with: .color(palette.tertiaryText), lineWidth: 1)
        var crossHairs = Path()
        crossHairs.move(to: CGPoint(x: center.x - dial, y: center.y))
        crossHairs.addLine(to: CGPoint(x: center.x + dial, y: center.y))
        crossHairs.move(to: CGPoint(x: center.x, y: center.y - dial))
        crossHairs.addLine(to: CGPoint(x: center.x, y: center.y + dial))
        context.stroke(crossHairs, with: .color(palette.gridLine), lineWidth: 1)

        // Ticks on the hours, and the numbers at the quarters.
        var ticks = Path()
        for hour in 0..<12 {
            let angle = Double(hour) * 30
            ticks.move(to: point(radius: dial - 6, degrees: angle))
            ticks.addLine(to: point(radius: dial, degrees: angle))
        }
        context.stroke(ticks, with: .color(palette.secondaryText), lineWidth: 1)
        for hour in [12, 3, 6, 9] {
            let label = Text("\(hour)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.primaryText)
            context.draw(label, at: point(radius: dial + Self.labelInset / 2 + 1, degrees: Double(hour) * 30))
        }

        // The pole, and the star on its circle joined to it by a line.
        context.stroke(circle(radius: 2.5), with: .color(palette.primaryText), lineWidth: 1.5)
        let star = point(radius: starRadius, degrees: reading.angle)
        var spoke = Path()
        spoke.move(to: center)
        spoke.addLine(to: star)
        context.stroke(spoke, with: .color(palette.guidance.opacity(0.6)), lineWidth: 1)
        context.stroke(Path(ellipseIn: CGRect(x: star.x - 8, y: star.y - 8, width: 16, height: 16)),
                       with: .color(palette.guidance), lineWidth: 1.5)
        context.fill(Path(ellipseIn: CGRect(x: star.x - 3.5, y: star.y - 3.5, width: 7, height: 7)),
                     with: .color(palette.guidance))
    }
}
