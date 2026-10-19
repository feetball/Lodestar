import SwiftUI
import LodestarKit

// Pieces shared by the mount screens: the Stop button, status texts, and the confirmation sheet.

/// The big red button that stops the mount. It is never disabled and always acts at once.
struct MountStopButton: View {
    /// A square button with the symbol over the word, for a row of controls; else a wide button with a long label.
    var isCompact = false
    var minHeight: CGFloat = 52
    private var service: MountService { MountService.shared }

    var body: some View {
        Button {
            service.stop()
        } label: {
            if isCompact {
                VStack(spacing: 3) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 20, weight: .bold))
                    Text("Stop")
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                }
            } else {
                Label(service.isStopping ? "Stopping\u{2026}" : "Stop mount", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(MountStopButtonStyle(minHeight: minHeight))
        .accessibilityLabel("Stop mount")
        .accessibilityHint("Stops the mount at once.")
    }
}

/// Filled with the palette's critical colour, so it is the loudest thing on the screen, in night mode as well.
struct MountStopButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    var minHeight: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.critical))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.primaryText.opacity(0.7), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Words and numbers for the state of the mount.
enum MountStatusText {
    /// "RA 12h 30m 14.0s \u{00B7} Dec +45\u{00B0} 30\u{2032} 15\u{2033}".
    static func pointing(_ position: EquatorialCoordinate, style: CoordinateStyle) -> String {
        "RA \(AppFormat.rightAscension(position, style: style)) \u{00B7} Dec \(AppFormat.declination(position, style: style))"
    }

    /// The same for VoiceOver: "Right ascension 12 hours 30 minutes".
    static func spokenPointing(_ position: EquatorialCoordinate) -> String {
        let hours = position.rightAscensionHours
        let wholeHours = Int(hours)
        let minutes = Int(((hours - Double(wholeHours)) * 60).rounded(.down))
        return "Right ascension \(wholeHours) hours \(minutes) minutes, declination \(AimFormat.spoken(position.declination))"
    }

    /// "Slewing\u{2026} 42 s", "Arrived at M 31 \u{2014} 0.02\u{00B0} from target", "Stopped" or the reason a slew failed.
    static func phaseLine(_ status: MountStatus, targetName: String?) -> String {
        switch status.phase {
        case .disconnected:
            return "Not connected"
        case .slewing:
            return "Slewing\u{2026} \(Int((status.slewElapsedSeconds ?? 0).rounded())) s"
        case .nudging:
            return "Nudging\u{2026}"
        case .idle:
            let place = targetName.map { " at \($0)" } ?? ""
            switch status.outcome {
            case .arrived(let separation)?:
                return "Arrived\(place) \u{2014} \(AngleFormatter.formatDegrees(separation, decimals: 2)) from target"
            case .aborted?:
                return "Stopped"
            case .failed(let error)?:
                return error.userMessage
            case nil:
                return status.isTracking == false ? "Ready \u{00B7} tracking is off" : "Ready"
            }
        }
    }

    /// How far a slew has come, 0 to 1; `nil` when it is not under way.
    static func progress(_ status: MountStatus, startSeparation: Double?) -> Double? {
        guard status.phase == .slewing, let start = startSeparation, start > 0.05, let separation = status.separation else {
            return nil
        }
        return min(max(1 - separation / start, 0), 1)
    }

    /// What the mount can do, in words: "GoTo, Sync, Nudge, Tracking, Site and time".
    static func capabilities(_ capabilities: MountCapabilities) -> String {
        var items: [String] = []
        if capabilities.canSlew { items.append("GoTo") }
        if capabilities.canSync { items.append("Sync") }
        if capabilities.canNudge { items.append("Nudge") }
        if capabilities.canSetTracking { items.append("Tracking") }
        if capabilities.canSetSiteAndTime { items.append("Site and time") }
        return items.isEmpty ? "Nothing Lodestar can control" : items.joined(separator: ", ")
    }

    /// What to try when a connection did not work.
    static func connectionAdvice(for error: MountError) -> String? {
        switch error {
        case .timeout, .transport, .malformedReply, .connectionLost:
            return """
                Is the iPhone on the mount's Wi-Fi network? Is the right address and port selected? iOS shows a refused \
                Local Network permission as a timeout as well: allow Lodestar under Settings \u{25B8} Privacy & Security \u{25B8} \
                Local Network.
                """
        case .unsupportedCoordinateSystem:
            return "Set the telescope to JNow or J2000 in its driver and connect again."
        case .notAligned:
            return "Do a star alignment on the mount's hand controller first."
        default:
            return nil
        }
    }
}

// MARK: - Confirmation

/// A GoTo or a sync waiting for the person's yes.
struct MountConfirmation: Identifiable {
    enum Kind: String {
        case goTo, sync
    }

    let kind: Kind
    let object: CelestialObject

    var id: String { "\(kind.rawValue)-\(object.id)" }
}

/// Asks before the mount moves or changes its idea of where it points: the target, its altitude, how the mount will
/// swing, and the reminder to keep clear. It has its own colours, so it is red at night like the rest of the app.
struct MountConfirmationSheet: View {
    let confirmation: MountConfirmation
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    private var service: MountService { MountService.shared }

    var body: some View {
        SettingsSheetRoot {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        details
                        centreSimulated
                        notice
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                buttons
            }
            .foregroundStyle(palette.primaryText)
        }
    }

    private var observer: Observer? { app.observerContext?.observer }

    private var title: String {
        switch confirmation.kind {
        case .goTo: return "Slew to \(confirmation.object.name)?"
        case .sync: return "Sync the mount to \(confirmation.object.name)?"
        }
    }

    @ViewBuilder
    private var details: some View {
        if let observer {
            let target = MountTargets.resolve(confirmation.object, observer: observer, date: Date())
            let plan = MountSlewPlan(target: target, mountPosition: service.status.position, observer: observer,
                                     date: Date())
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Target", value: confirmation.object.name)
                InfoRow(label: "Altitude now", value: AppFormat.altitude(target.altitude))
                InfoRow(label: "Your altitude limit", value: AppFormat.altitude(service.settings.altitudeLimit))
                if let start = plan.start {
                    InfoRow(label: "Mount points at",
                            value: "\(AppFormat.azimuth(start.azimuth)), \(AppFormat.altitude(start.altitude))")
                }
                if confirmation.kind == .goTo {
                    Text(plan.distanceText + (plan.directionText.map { " " + $0 } ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(service.usesLodestarAlignment ? Self.alignmentSyncText(confirmation.object.name)
                         : "Tells the mount that it points at \(confirmation.object.name) right now.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let separation = plan.separation {
                        InfoRow(label: "Mount believes it is", value: "\(AppFormat.separation(separation)) away")
                    }
                    if service.usesLodestarAlignment {
                        InfoRow(label: "Stars in the alignment",
                                value: "\(service.driverDetail?.alignment?.stars.count ?? 0)")
                    }
                }
            }
            .card(palette)
        } else {
            Text("Lodestar needs your location first.")
                .foregroundStyle(palette.warning)
        }
    }

    private static func alignmentSyncText(_ name: String) -> String {
        """
        Adds \(name) to the star alignment: Lodestar learns from it where the mount really points. The first star also \
        shows how far off the home position was.
        """
    }

    /// The simulated Sky-Watcher can be put on the target, in place of the nudge arrows.
    @ViewBuilder
    private var centreSimulated: some View {
        if confirmation.kind == .sync, service.connectedOption?.id == MountConnectionOption.demoSkyWatcher.id, let observer {
            Button {
                let object = confirmation.object
                Task { await service.centreSimulatedMount(on: object, observer: observer) }
            } label: {
                Text("Centre the simulated mount on \(confirmation.object.name)")
                    .frame(maxWidth: .infinity)
                    .lineLimit(2)
            }
            .buttonStyle(.lodestarSecondary)
            .disabled(service.isWorking)
        }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(confirmation.kind == .goTo ? "Before the mount moves" : "Before you sync",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.warning)
            Text(noticeText)
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(palette)
    }

    private var noticeText: String {
        switch confirmation.kind {
        case .goTo:
            return "Keep people, hands and cables clear of the mount and of everything it carries. It can swing through "
                + "a wide arc and does not stop for obstacles. Tap Stop at any time. Make sure the telescope or camera "
                + "cannot end up pointing at the Sun."
        case .sync:
            return """
                Sync only when \(confirmation.object.name) is in the middle of your camera's frame. Syncing on the wrong \
                star makes later slews miss.
                """
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button {
                perform()
            } label: {
                Text(confirmation.kind == .goTo ? "Slew to \(confirmation.object.name)" : "Sync mount")
                    .frame(maxWidth: .infinity)
                    .lineLimit(2)
            }
            .buttonStyle(.lodestarPrimary)
            .disabled(observer == nil)
            Button("Cancel") { dismiss() }
                .buttonStyle(.lodestarSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
    }

    private func perform() {
        guard let observer else { return }
        let object = confirmation.object
        let kind = confirmation.kind
        dismiss()
        Task {
            switch kind {
            case .goTo: await service.goTo(object, observer: observer)
            case .sync: await service.syncMount(to: object, observer: observer)
            }
        }
    }
}
