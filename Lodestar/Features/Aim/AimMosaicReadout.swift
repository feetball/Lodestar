import SwiftUI
import LodestarKit

/// The panel over the controls while a mosaic is being shot: which panel is next and where it is, how to reach it, how
/// far to rotate the camera, and the buttons that move on through the mosaic.
struct AimMosaicReadout: View {
    let model: AimViewModel
    let frame: AimFrame?

    var body: some View {
        let session = model.mosaicSession
        VStack(spacing: 8) {
            AimMosaicCard(session: session, frame: frame, mask: model.skyContent?.skyline?.mask)
            if session.isComplete {
                AimMosaicDoneBanner(count: session.panelCount)
            } else {
                if let guidance = frame?.guidance {
                    AimMoveRow(summary: AimGuidanceSummary(guidance))
                }
                if let mosaic = frame?.mosaic {
                    AimMosaicRollRow(delta: mosaic.rollDelta)
                }
            }
            AimMosaicButtons(model: model)
        }
    }
}

/// The mosaic's title, the panel to shoot and where it is in the sky.
private struct AimMosaicCard: View {
    let session: MosaicSession
    let frame: AimFrame?
    let mask: HorizonMask?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 29)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.progressText)
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let horizontal = frame?.mosaic?.aim.horizontal {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Alt \(AppFormat.altitude(horizontal.altitude))")
                        Text("Az \(AppFormat.azimuth(horizontal.azimuth))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                }
            }
            if let note {
                Label(note, systemImage: "arrow.down.to.line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.warning)
            }
        }
        .aimPanel(palette)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        [session.title, session.positionText].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// A warning while the panel is not fully in the clear.
    private var note: String? {
        guard let aim = frame?.mosaic?.aim else { return nil }
        if !aim.isAboveHorizon { return "This panel is below the horizon" }
        if mask?.isBelow(azimuth: aim.horizontal.azimuth, altitude: aim.horizontal.altitude) == true {
            return "This panel is behind your skyline"
        }
        return aim.lowestAltitude < 0 ? "Part of this panel is below the horizon" : nil
    }
}

/// The advice on turning the camera about its axis so that the panel's edges line up with the plan.
enum AimMosaicRoll {
    /// Turns up to this size, in degrees, count as matching.
    static let tolerance = 1.0

    static func matches(_ delta: Double) -> Bool { abs(delta) <= tolerance }

    private static func direction(_ delta: Double) -> String {
        delta > 0 ? "clockwise" : "counterclockwise"
    }

    /// "Rotate the camera 12° clockwise", or the note that nothing is left to do.
    static func text(delta: Double) -> String {
        guard !matches(delta) else { return "Camera roll matches the panel" }
        return "Rotate the camera \(AngleFormatter.formatDegrees(abs(delta), decimals: 0)) \(direction(delta))"
    }

    /// The same advice for VoiceOver.
    static func spokenText(delta: Double) -> String {
        guard !matches(delta) else { return "Camera roll matches the panel" }
        return "Rotate the camera \(AimFormat.spoken(delta)) \(direction(delta))"
    }
}

private struct AimMosaicRollRow: View {
    let delta: Double
    @Environment(\.palette) private var palette

    var body: some View {
        let matches = AimMosaicRoll.matches(delta)
        Label(AimMosaicRoll.text(delta: delta),
              systemImage: matches ? "checkmark" : (delta > 0 ? "arrow.clockwise" : "arrow.counterclockwise"))
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(matches ? palette.positive : palette.guidance)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 40)
            .aimPanel(palette, padding: 4)
            // The summary element of the screen speaks the same advice once a second.
            .accessibilityHidden(true)
    }
}

/// Shown once every panel has been shot.
private struct AimMosaicDoneBanner: View {
    let count: Int
    @Environment(\.palette) private var palette

    var body: some View {
        Label("All \(count) panels shot", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(palette.positive)
            .frame(maxWidth: .infinity, minHeight: 44)
            .aimPanel(palette, padding: 6)
    }
}

/// Previous, "Shot taken → Next" and Finish.
private struct AimMosaicButtons: View {
    let model: AimViewModel

    var body: some View {
        let session = model.mosaicSession
        let shotTitle = session.isLastPanel ? "Shot taken" : "Shot taken \u{2192} Next"
        HStack(spacing: 8) {
            Button {
                model.mosaicPrevious()
            } label: {
                Text("Previous")
            }
            .buttonStyle(AimMosaicButtonStyle(isPrimary: false))
            .disabled(!session.canGoBack)
            .accessibilityLabel("Previous panel")
            if !session.isComplete {
                Button {
                    model.mosaicShotTaken()
                } label: {
                    Text(shotTitle)
                }
                .buttonStyle(AimMosaicButtonStyle(isPrimary: true))
                .layoutPriority(1)
                .accessibilityLabel(session.isLastPanel ? "Shot taken" : "Shot taken, go to the next panel")
            }
            Button {
                model.finishMosaic()
            } label: {
                Text("Finish")
            }
            .buttonStyle(AimMosaicButtonStyle(isPrimary: session.isComplete))
            .accessibilityLabel("Finish mosaic")
        }
    }
}

/// A compact capsule button for the mosaic's three steps, drawn with palette colours only.
private struct AimMosaicButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isPrimary ? palette.onAccent : palette.accent)
            .background(Capsule().fill(isPrimary ? palette.accent : palette.surface.opacity(0.88)))
            .overlay(Capsule().strokeBorder(isPrimary ? Color.clear : palette.stroke, lineWidth: 0.75))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}
