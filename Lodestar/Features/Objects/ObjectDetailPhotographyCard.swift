import SwiftUI
import LodestarKit

/// How the object fits the user's lens, how long to expose, and what the Moon will do to the shot.
struct ObjectDetailPhotographyCard: View {
    @Environment(\.palette) private var palette

    let object: CelestialObject
    let snapshot: ObjectDetailSnapshot?
    let lens: LensSetup
    let timeZone: TimeZone

    var body: some View {
        let photography = ObjectDetailCalculator.photography(
            of: object,
            size: snapshot?.current.angularSize ?? object.angularSize,
            declination: snapshot?.current.equatorial.declination ?? object.j2000?.declination,
            lens: lens)
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Photography", systemImage: "camera")
            lensRows(for: photography)
            if let framing = photography.framing {
                framingRow(framing, in: photography.frame)
            }
            exposureRows(for: photography)
            if let moon = snapshot?.moon {
                moonRows(for: moon)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    // MARK: Lens and framing

    @ViewBuilder
    private func lensRows(for photography: ObjectDetailPhotography) -> some View {
        let focalLength = trimmed(lens.focalLengthMillimeters)
        let setup = "\(focalLength) mm f/\(trimmed(lens.aperture)) \u{00B7} \(lens.sensor.name)"
        let horizontal = AngleFormatter.formatDegrees(photography.frame.horizontal)
        let vertical = AngleFormatter.formatDegrees(photography.frame.vertical)
        InfoRow(label: "Your lens", value: setup)
        InfoRow(label: "Field of view", value: "\(horizontal) \u{00D7} \(vertical)")
    }

    /// A number with at most one decimal, such as "24" or "2.8".
    private func trimmed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func framingRow(_ framing: ObjectDetailFraming, in frame: FrameSize) -> some View {
        HStack(spacing: 12) {
            ObjectDetailFramingDiagram(framing: framing, aspectRatio: frame.longSide / frame.shortSide)
                .frame(width: 110)
            Text(framingDescription(framing))
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func framingDescription(_ framing: ObjectDetailFraming) -> String {
        if framing.fitsInFrame {
            return framing.fillFraction < 0.01
                ? "Fills under 1% of the frame"
                : "Fills \(AppFormat.percent(framing.fillFraction)) of the frame"
        }
        let panels = "\(framing.longSidePanels) \u{00D7} \(framing.shortSidePanels)"
        return "Larger than the frame: needs a mosaic of about \(panels) panels"
    }

    // MARK: Exposure

    @ViewBuilder
    private func exposureRows(for photography: ObjectDetailPhotography) -> some View {
        if let npf = photography.npf, let rule500 = photography.rule500 {
            Text("Longest exposure before stars trail")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
            InfoRow(label: "NPF rule", value: AngleFormatter.formatExposure(seconds: npf.seconds))
            InfoRow(label: "500 rule", value: AngleFormatter.formatExposure(seconds: rule500.seconds))
            if !npf.notes.isEmpty {
                Text(npf.notes.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryText)
            }
        }
    }

    // MARK: Moon

    @ViewBuilder
    private func moonRows(for moon: ObjectDetailMoonConditions) -> some View {
        let advice = moonAdvice(for: moon.impact)
        InfoRow(label: moon.isNow ? "Moon now" : "Moon at \(AppFormat.time(moon.date, in: timeZone))",
                value: moonSummary(moon))
        Label(advice.text, systemImage: advice.symbol)
            .font(.footnote)
            .foregroundStyle(advice.color)
    }

    private func moonSummary(_ moon: ObjectDetailMoonConditions) -> String {
        guard moon.impact != .moonDown else { return "Below the horizon" }
        let separation = AppFormat.separation(moon.separation)
        return "\(separation) away \u{00B7} \(AppFormat.percent(moon.illuminatedFraction)) lit"
    }

    private func moonAdvice(for impact: ObjectDetailMoonConditions.Impact)
        -> (text: String, symbol: String, color: Color) {
        switch impact {
        case .moonDown:
            return ("The Moon is down, so the sky stays dark.", "moon.zzz", palette.positive)
        case .minor:
            return ("The Moon has little effect on this target.", "moon", palette.secondaryText)
        case .moderate:
            return ("Moonlight will brighten the sky around this target.", "moon.fill", palette.warning)
        case .severe:
            return ("A bright Moon close by will wash out faint detail.", "exclamationmark.triangle",
                    palette.critical)
        }
    }
}

/// A sketch of the camera frame with the object drawn to scale along its long side.
struct ObjectDetailFramingDiagram: View {
    @Environment(\.palette) private var palette

    let framing: ObjectDetailFraming
    /// The frame's long side divided by its short side.
    let aspectRatio: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                palette.background
                Ellipse()
                    .fill(palette.accent.opacity(0.35))
                    .overlay { Ellipse().strokeBorder(palette.accent, lineWidth: 1) }
                    .frame(width: max(proxy.size.width * min(framing.majorFraction, 1), 4),
                           height: max(proxy.size.height * min(framing.minorFraction, 1), 4))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.stroke, lineWidth: 1)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
