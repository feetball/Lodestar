import SwiftUI
import LodestarKit

/// The site's skyline round the whole circle, north at both ends, with the picked direction marked and the window
/// that the finder searches (the tolerance either side, from the skyline up to 10° above it) shaded. Tapping or
/// dragging picks an azimuth, snapped to whole degrees.
struct AlignmentFinderSkylinePicker: View {
    /// The labelled directions along the bottom edge.
    private static let labels: [(azimuth: Double, text: String)] = [
        (0, "N"), (90, "E"), (180, "S"), (270, "W"), (360, "N"),
    ]
    /// How far the window rises above the skyline, in degrees (the finder's "just above the skyline").
    private static let windowAboveSkyline = 10.0

    /// The room under the plot for the direction labels, which grow with the text size.
    @ScaledMetric(relativeTo: .caption2) private var labelBand: CGFloat = 16
    @Environment(\.palette) private var palette

    let profile: HorizonProfile
    /// The picked azimuth in whole degrees, 0…359.
    @Binding var azimuth: Int
    /// The tolerance either side of it in whole degrees.
    let tolerance: Int

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                pick(at: value.location.x, width: geometry.size.width)
            })
        }
        .frame(height: 88 + labelBand)
        .accessibilityElement()
        .accessibilityLabel("Skyline round the whole circle")
        .accessibilityHint("Adjust to pick a direction")
        .accessibilityValue("\(AlignmentFinderText.direction(azimuth)), skyline "
                            + "\(AlignmentFinderText.altitude(profile.altitude(at: Double(azimuth)))) high")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: azimuth = (azimuth + 1) % HorizonProfile.binCount
            case .decrement: azimuth = (azimuth + HorizonProfile.binCount - 1) % HorizonProfile.binCount
            @unknown default: break
            }
        }
    }

    private func pick(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let degrees = Int((Double(x / width) * Double(HorizonProfile.binCount)).rounded())
        azimuth = min(max(degrees, 0), HorizonProfile.binCount) % HorizonProfile.binCount
    }

    // MARK: Drawing

    /// The altitude range shown: at least −5…30°, taller when the skyline needs it.
    private var altitudeRange: ClosedRange<Double> {
        let top = max(30, ((profile.maximumAltitude + Self.windowAboveSkyline + 2) / 10).rounded(.up) * 10)
        let bottom = ((min(0, profile.minimumAltitude) - 2) / 5).rounded(.down) * 5
        return bottom...top
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let plot = CGRect(x: 0, y: 0, width: size.width, height: max(size.height - labelBand, 1))
        let range = altitudeRange
        let count = HorizonProfile.binCount

        func x(_ degrees: Double) -> CGFloat { plot.minX + plot.width * CGFloat(degrees / Double(count)) }
        func y(_ altitude: Double) -> CGFloat {
            plot.maxY - plot.height * CGFloat((altitude - range.lowerBound) / (range.upperBound - range.lowerBound))
        }

        context.fill(Path(plot), with: .color(palette.surface.opacity(0.6)))

        // The ground and the skyline.
        var ground = Path()
        var line = Path()
        ground.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        for node in 0...count {
            let point = CGPoint(x: x(Double(node)), y: y(profile.altitudes[node % count]))
            ground.addLine(to: point)
            if node == 0 { line.move(to: point) } else { line.addLine(to: point) }
        }
        ground.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        ground.closeSubpath()
        context.fill(ground, with: .color(palette.accent.opacity(0.28)))

        var horizon = Path()
        horizon.move(to: CGPoint(x: plot.minX, y: y(0)))
        horizon.addLine(to: CGPoint(x: plot.maxX, y: y(0)))
        context.stroke(horizon, with: .color(palette.horizonLine), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        context.stroke(line, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        // The window above the picked point, in one or two pieces when it runs through north.
        let skyline = profile.altitude(at: Double(azimuth))
        let windowTop = y(min(skyline + Self.windowAboveSkyline, range.upperBound))
        let windowBottom = y(skyline)
        let first = Double(azimuth - tolerance)
        let last = Double(azimuth + tolerance)
        var spans = [(first, last)]
        if first < 0 {
            spans = [(0, last), (first + Double(count), Double(count))]
        } else if last > Double(count) {
            spans = [(first, Double(count)), (0, last - Double(count))]
        }
        for (from, to) in spans {
            let rect = CGRect(x: x(from), y: windowTop, width: max(x(to) - x(from), 1),
                              height: max(windowBottom - windowTop, 1))
            context.fill(Path(rect), with: .color(palette.guidance.opacity(0.35)))
        }

        // The picked direction.
        let at = x(Double(azimuth))
        var marker = Path()
        marker.move(to: CGPoint(x: at, y: plot.minY))
        marker.addLine(to: CGPoint(x: at, y: plot.maxY))
        context.stroke(marker, with: .color(palette.guidance), lineWidth: 1.5)
        context.fill(Path(ellipseIn: CGRect(x: at - 4, y: y(skyline) - 4, width: 8, height: 8)),
                     with: .color(palette.guidance))

        context.stroke(Path(plot), with: .color(palette.stroke), lineWidth: 0.75)
        for label in Self.labels {
            let anchor: UnitPoint = label.azimuth == 0 ? .topLeading : (label.azimuth == 360 ? .topTrailing : .top)
            context.draw(Text(label.text).font(.caption2.weight(.semibold)).foregroundStyle(palette.secondaryText),
                         at: CGPoint(x: x(label.azimuth), y: plot.maxY + 2), anchor: anchor)
        }
    }
}
