import SwiftUI
import LodestarKit

/// The panel above the controls: the target and how to reach it, or, without a target, what lies under the reticle.
/// It updates about ten times a second on its own timeline.
struct AimReadout: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    let isActive: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isActive)) { _ in
            let frame = model.engine.frame()
            if model.mosaicSession.isActive {
                AimMosaicReadout(model: model, frame: frame)
            } else if let source = model.satelliteSource {
                SatelliteAimReadout(model: model, source: source)
            } else if let target = model.guidanceTarget {
                VStack(spacing: 8) {
                    AimTargetCard(object: target, horizontal: frame?.target?.horizontal,
                                  belowHorizonNote: belowHorizonNote(for: target, frame: frame),
                                  onClear: model.alignmentTarget == nil ? { app.clearTarget() } : nil)
                    if let guidance = frame?.guidance {
                        AimMoveRow(summary: AimGuidanceSummary(guidance))
                    }
                }
            } else {
                AimLookAroundPanel(model: model, sheet: $sheet, frame: frame)
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
    /// Drops the target, to look around freely; `nil` hides the button.
    let onClear: (() -> Void)?
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
                if let onClear {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(palette.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -8)
                    .padding(.trailing, -8)
                    // Offered as an action of the combined card instead.
                    .accessibilityHidden(true)
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
        .accessibilityActions {
            if let onClear {
                Button("Clear target", action: onClear)
            }
        }
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

/// Shown while there is no target, for exploring the sky by pointing the camera around: the object under the
/// reticle, where the camera points, and ways to aim at the object or choose another target.
private struct AimLookAroundPanel: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    let frame: AimFrame?
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let nearby = frame.flatMap { model.nearbyObject(in: $0) }
        let object = nearby.flatMap { app.catalog.object(id: $0.id) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let object {
                    ObjectIcon(category: object.category, size: 16)
                } else {
                    Image(systemName: "binoculars")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(nearby?.name ?? "Looking around")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle(nearby: nearby, object: object))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                if let boresight = frame?.pointing.boresight {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Alt \(AppFormat.altitude(boresight.altitude))")
                        Text("Az \(AppFormat.azimuth(boresight.azimuth))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityLabel("Pointing at altitude \(AppFormat.altitude(boresight.altitude)),"
                                        + " azimuth \(AppFormat.azimuth(boresight.azimuth))")
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                if let object {
                    Button {
                        app.select(target: object)
                    } label: {
                        Label("Aim here", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.lodestarPrimary)
                    .accessibilityLabel("Aim at \(object.name)")
                }
                Button {
                    sheet = .targetPicker
                } label: {
                    Label("Choose target", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .aimPanel(palette)
    }

    private func subtitle(nearby: AimLookAround.Nearby?, object: CelestialObject?) -> String {
        guard let nearby else { return "Point at a planet or bright star to name it" }
        let distance = "\(AimFormat.angle(nearby.separation)) from center"
        return [object?.category.displayName, distance].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}
