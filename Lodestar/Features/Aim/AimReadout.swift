import SwiftUI
import LodestarKit

/// The panel above the controls: the target and how to reach it, or the offer to choose one. It updates about ten
/// times a second on its own timeline.
struct AimReadout: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isActive)) { _ in
            if model.mosaicSession.isActive {
                AimMosaicReadout(model: model, frame: model.engine.frame())
            } else if let target = model.guidanceTarget {
                let frame = model.engine.frame()
                VStack(spacing: 8) {
                    AimTargetCard(object: target, horizontal: frame?.target?.horizontal,
                                  belowHorizonNote: belowHorizonNote(for: target, frame: frame))
                    if let guidance = frame?.guidance {
                        AimMoveRow(summary: AimGuidanceSummary(guidance))
                    }
                }
            } else {
                AimNoTargetPrompt(model: model, sheet: $sheet)
            }
        }
    }

    /// "Below the horizon · rises 23:41 (in 5h 12m)", "Behind your skyline", or `nil` while the target is in the clear.
    private func belowHorizonNote(for target: CelestialObject, frame: AimFrame?) -> String? {
        guard let altitude = frame?.target?.horizontal.altitude else { return nil }
        if altitude >= 0, let horizontal = frame?.target?.horizontal,
           model.skyContent?.skyline?.mask.isBelow(azimuth: horizontal.azimuth, altitude: altitude) == true {
            return "Behind your skyline"
        }
        guard altitude < 0 else { return nil }
        guard let info = model.riseInfo, info.targetID == target.id,
              let timeZone = model.app.observerContext?.timeZone else { return "Below the horizon" }
        if let rise = info.nextRise {
            return "Below the horizon \u{00B7} rises \(AppFormat.time(rise, in: timeZone)) (\(AppFormat.relative(rise, from: Date())))"
        }
        return "Below the horizon \u{00B7} does not rise in the next 24 hours"
    }
}

/// The target's name, kind and position, with a warning while it is below the horizon.
private struct AimTargetCard: View {
    let object: CelestialObject
    let horizontal: HorizontalCoordinate?
    let belowHorizonNote: String?
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    /// A comet's or asteroid's magnitude estimate and elongation, kept current; unused for other objects.
    @State private var smallBody = SmallBodyLive.pending

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ObjectIcon(category: object.category, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SmallBodyText.displayName(object))
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(object.smallBody == nil ? subtitle : smallBody.subtitle(of: object))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let horizontal {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Alt \(AppFormat.altitude(horizontal.altitude))")
                        Text("Az \(AppFormat.azimuth(horizontal.azimuth))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                }
            }
            if let belowHorizonNote {
                Label(belowHorizonNote, systemImage: "arrow.down.to.line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.warning)
            }
            SmallBodyAimNotes(live: smallBody)
            if object.category == .sun {
                Label("Never point at the Sun without a certified solar filter", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.critical)
            }
        }
        .aimPanel(palette)
        .accessibilityElement(children: .combine)
        .task(id: object.id) {
            await SmallBodyLive.keepCurrent(of: object, clock: app.clock) { smallBody = $0 }
        }
    }

    private var subtitle: String {
        [object.category.displayName, object.constellationName].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

/// The pan and tilt the head has to make, or the state that replaces them.
struct AimMoveRow: View {
    let summary: AimGuidanceSummary
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if summary.isOnTarget {
                banner("In your frame \u{00B7} \(AimFormat.angle(summary.separation)) from center",
                       systemImage: "checkmark.circle.fill", color: palette.positive)
            } else if summary.isNearZenith {
                banner("Near zenith \u{2014} follow the arrow", systemImage: "arrow.up.circle", color: palette.guidance)
            } else {
                HStack(spacing: 8) {
                    AimMovePill(move: summary.pan)
                    AimMovePill(move: summary.tilt)
                }
            }
        }
        // The summary element of the screen speaks the same numbers once a second.
        .accessibilityHidden(true)
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .aimPanel(palette, padding: 6)
    }
}

struct AimMovePill: View {
    let move: AimGuidanceSummary.Move
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Label(move.verb, systemImage: move.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
            Text(AimFormat.angle(move.degrees))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.guidance)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .aimPanel(palette, padding: 4)
    }
}

/// Shown while there is no target: quick picks and a way to search.
private struct AimNoTargetPrompt: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            Text("Choose what to aim at")
                .font(.headline)
                .foregroundStyle(palette.primaryText)
            Text("Lodestar then shows how to turn the camera towards it.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            AimFlowLayout {
                ForEach(AimQuickPicks.picks(catalog: app.catalog, snapshot: model.skyContent?.snapshot, planetLimit: 2)) { pick in
                    AimQuickPickButton(pick: pick) { app.select(target: pick.object) }
                }
            }
            Button {
                sheet = .targetPicker
            } label: {
                Label("Search all objects", systemImage: "magnifyingglass")
            }
            .buttonStyle(.lodestarPrimary)
        }
        .frame(maxWidth: .infinity)
        .aimPanel(palette, padding: 12)
    }
}
