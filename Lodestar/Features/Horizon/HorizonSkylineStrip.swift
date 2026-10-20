import SwiftUI
import LodestarKit

/// The skyline recorded so far as a 360° strip, north at both ends: the swept stretches as a solid line over the
/// ground, the stretches still to sweep dimmed and dashed (they show the previous skyline, if there is one), and a
/// marker where the camera points now.
struct HorizonSkylineStrip: View {
    /// The labelled directions along the bottom edge.
    private static let labels: [(azimuth: Double, text: String)] = [
        (0, "N"), (90, "E"), (180, "S"), (270, "W"), (360, "N"),
    ]
    /// The room under the plot for the direction labels, which grow with the text size.
    @ScaledMetric(relativeTo: .caption2) private var labelBand: CGFloat = 16
    /// The stretches still to sweep are listed once this much of the circle is recorded.
    static let showGapsFrom = 0.5

    @Environment(\.palette) private var palette
    let reading: HorizonReading

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: 80 + labelBand)
        .accessibilityElement()
        .accessibilityLabel("Skyline recorded so far")
        .accessibilityValue(summary)
    }

    private var summary: String {
        var text = "\(AppFormat.percent(reading.coverage)) covered."
        if reading.coverage >= HorizonSkylineStrip.showGapsFrom, !reading.gaps.isEmpty {
            text += " Still to sweep: \(HorizonText.gapsText(reading.gaps))."
        }
        return text
    }

    // MARK: Drawing

    /// The altitude range shown: at least 0…30°, taller when the skyline needs it.
    private var altitudeRange: ClosedRange<Double> {
        let skyline = reading.skyline
        let top = max(30, (skyline.maximumAltitude / 10).rounded(.up) * 10)
        let bottom = min(-5, (skyline.minimumAltitude / 5).rounded(.down) * 5)
        return bottom...top
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let plot = CGRect(x: 0, y: 0, width: size.width, height: max(size.height - labelBand, 1))
        let range = altitudeRange
        let altitudes = reading.skyline.altitudes
        let isGap = gapMask()

        func x(_ azimuth: Double) -> CGFloat { plot.minX + plot.width * CGFloat(azimuth / 360) }
        func y(_ altitude: Double) -> CGFloat {
            plot.maxY - plot.height * CGFloat((altitude - range.lowerBound) / (range.upperBound - range.lowerBound))
        }

        context.fill(Path(plot), with: .color(palette.surface.opacity(0.6)))

        // The stretches still to sweep.
        for gap in reading.gaps {
            let end = gap.start + gap.length
            if end <= 360 {
                context.fill(Path(CGRect(x: x(gap.start), y: plot.minY, width: x(end) - x(gap.start), height: plot.height)),
                             with: .color(palette.gridLine))
            } else {
                context.fill(Path(CGRect(x: x(gap.start), y: plot.minY, width: plot.maxX - x(gap.start), height: plot.height)),
                             with: .color(palette.gridLine))
                context.fill(Path(CGRect(x: plot.minX, y: plot.minY, width: x(end - 360), height: plot.height)),
                             with: .color(palette.gridLine))
            }
        }

        // The ground under the swept skyline and the horizon line.
        var ground = Path()
        var swept = Path()
        var unswept = Path()
        var isDrawingSwept = false
        ground.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        for node in 0...HorizonProfile.binCount {
            let bin = node % HorizonProfile.binCount
            let point = CGPoint(x: x(Double(node)), y: y(altitudes[bin]))
            ground.addLine(to: isGap[bin] ? CGPoint(x: point.x, y: y(range.lowerBound)) : point)
            guard node > 0 else { continue }
            let previous = CGPoint(x: x(Double(node - 1)), y: y(altitudes[node - 1]))
            if isGap[node - 1] || isGap[bin] {
                unswept.move(to: previous)
                unswept.addLine(to: point)
                isDrawingSwept = false
            } else {
                if !isDrawingSwept { swept.move(to: previous) }
                swept.addLine(to: point)
                isDrawingSwept = true
            }
        }
        ground.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        ground.closeSubpath()
        context.fill(ground, with: .color(palette.accent.opacity(0.28)))

        var horizon = Path()
        horizon.move(to: CGPoint(x: plot.minX, y: y(0)))
        horizon.addLine(to: CGPoint(x: plot.maxX, y: y(0)))
        context.stroke(horizon, with: .color(palette.horizonLine), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        context.stroke(unswept, with: .color(palette.tertiaryText), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        context.stroke(swept, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        // Where the camera points.
        if let azimuth = reading.azimuth {
            var marker = Path()
            marker.move(to: CGPoint(x: x(azimuth), y: plot.minY))
            marker.addLine(to: CGPoint(x: x(azimuth), y: plot.maxY))
            context.stroke(marker, with: .color(palette.guidance), lineWidth: 1.5)
            if let altitude = reading.altitude {
                let at = CGPoint(x: x(azimuth), y: min(max(y(altitude), plot.minY + 3), plot.maxY - 3))
                context.fill(Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)),
                             with: .color(palette.guidance))
            }
        }

        context.stroke(Path(plot), with: .color(palette.stroke), lineWidth: 0.75)

        for label in Self.labels {
            let anchor: UnitPoint = label.azimuth == 0 ? .topLeading : (label.azimuth == 360 ? .topTrailing : .top)
            context.draw(Text(label.text).font(.caption2.weight(.semibold)).foregroundStyle(palette.secondaryText),
                         at: CGPoint(x: x(label.azimuth), y: plot.maxY + 2), anchor: anchor)
        }
    }

    /// For each whole degree of azimuth, whether it lies in a stretch still to be swept.
    private func gapMask() -> [Bool] {
        var mask = [Bool](repeating: false, count: HorizonProfile.binCount)
        for gap in reading.gaps {
            for bin in mask.indices where gap.contains(Double(bin)) {
                mask[bin] = true
            }
        }
        return mask
    }
}
