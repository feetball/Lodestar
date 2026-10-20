import SwiftUI
import LodestarKit

/// The panel above the controls while Aim follows a satellite or waits for the peak of its pass: the name, where it is
/// now, what to read off (range, angular speed and light for a followed satellite; the countdown for the peak), a button to
/// stop, and how to reach it. It updates about ten times a second with the readout's timeline.
struct SatelliteAimReadout: View {
    let model: AimViewModel
    let source: SatelliteAimSource

    var body: some View {
        let frame = model.engine.frame()
        VStack(spacing: 8) {
            SatelliteAimCard(source: source, fix: frame?.satellite) { model.app.satelliteAim.stop() }
            if let guidance = frame?.guidance {
                AimMoveRow(summary: AimGuidanceSummary(guidance))
            }
        }
    }
}

private struct SatelliteAimCard: View {
    let source: SatelliteAimSource
    let fix: SatelliteAimFix?
    let onStop: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    private var timeZone: TimeZone { app.observerContext?.timeZone ?? .autoupdatingCurrent }

    private var subtitle: String {
        if let peak = source.peakDate {
            return "Waiting for the peak \u{00B7} \(SatelliteText.timeWithSeconds(peak, in: timeZone))"
        }
        return "Satellite \u{00B7} following"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let horizontal = fix?.horizontal {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Alt \(AppFormat.altitude(horizontal.altitude))")
                        Text("Az \(AppFormat.azimuth(horizontal.azimuth))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .layoutPriority(1)
                }
                Button(action: onStop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(source.isPeak ? "Stop waiting for the peak" : "Stop following")
            }
            details
        }
        .aimPanel(palette, opacity: 0.97)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var details: some View {
        if let fix {
            if let seconds = fix.secondsToPeak {
                Text(SatelliteText.peakCountdown(seconds))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.guidance)
            }
            if let look = fix.look {
                Text(SatelliteText.followInfo(rangeKilometers: look.rangeKilometers, angularSpeed: look.angularSpeed,
                                              isSunlit: look.isSunlit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }
            if fix.horizontal.altitude < 0 {
                note(SatelliteText.rideAlongBelow)
            }
            if let pass = source.pass, let text = SatelliteText.passNote(
                now: Date(), rise: pass.pass.rise.date, set: pass.pass.set.date,
                timeText: { AppFormat.time($0, in: timeZone) }) {
                note(text)
            }
        } else {
            Text("Locating the satellite\u{2026}")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "arrow.down.to.line")
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.warning)
    }
}

/// What a screen reader says for the Aim screen while a satellite is the target.
enum SatelliteAimText {
    static func spoken(_ source: SatelliteAimSource, frame: AimFrame) -> String {
        guard let fix = frame.satellite else { return "Locating \(source.title)." }
        let way = frame.guidance.map { " \(AimGuidanceSummary($0).spokenText)." } ?? ""
        let below = fix.horizontal.altitude < 0 ? " Below the horizon." : ""
        if source.isPeak {
            let countdown = fix.secondsToPeak.map { " \(SatelliteText.peakCountdown($0))." } ?? ""
            return "Waiting for the peak of the \(source.title) pass.\(countdown)\(way)"
        }
        return "Following \(source.title).\(way)\(below)"
    }
}
