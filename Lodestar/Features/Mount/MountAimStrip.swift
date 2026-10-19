import SwiftUI
import LodestarKit

/// The mount's card in the Aim screen's heads-up display: where the mount points, how far it is from the target, what it
/// is doing, and the buttons for GoTo, Sync, Stop and the nudge pad. It appears while a mount is connecting, connected
/// or lost, and not at all otherwise.
struct MountAimStrip: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var confirmation: MountConfirmation?

    private var service: MountService { MountService.shared }

    var body: some View {
        content
            .onChange(of: app.observerContext?.observer, initial: true) { _, observer in
                service.updateObserver(observer)
            }
            .sheet(item: $confirmation) { confirmation in
                MountConfirmationSheet(confirmation: confirmation)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch service.connection {
        case .disconnected:
            EmptyView()
        case .connecting:
            connectingCard
        case .connected:
            connectedCard
        case .lost(let reason):
            lostCard(reason)
        }
    }

    // MARK: Cards

    private var connectingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(palette.accent)
            Text("Connecting to \(service.displayName)\u{2026}")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Button("Cancel") { service.cancelConnect() }
                .buttonStyle(.lodestarSecondary)
        }
        .aimPanel(palette, padding: 8)
        .accessibilityElement(children: .contain)
    }

    private func lostCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connection lost", systemImage: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.critical)
            Text(reason)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    service.reconnect(observer: app.observerContext?.observer)
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarPrimary)
                Button("Dismiss") { service.disconnect() }
                    .buttonStyle(.lodestarSecondary)
            }
        }
        .aimPanel(palette, padding: 10)
        .accessibilityElement(children: .contain)
    }

    private var connectedCard: some View {
        let status = service.status
        let target = model.guidanceTarget
        return VStack(spacing: 8) {
            header(status)
            if let warning = service.alignmentWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            progress(status, target: target)
            skyWatcherLines
            messageLine
            actions(target: target)
        }
        .aimPanel(palette, padding: 8)
        .accessibilityElement(children: .contain)
    }

    /// The alignment, the tracking state and the pier side of a mount that Lodestar aligns, and what stands in the way.
    @ViewBuilder
    private var skyWatcherLines: some View {
        if service.usesLodestarAlignment, let line = service.alignmentLine {
            VStack(alignment: .leading, spacing: 2) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(service.needsFirstSync ? palette.warning : palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let state = service.trackingAndPierLine {
                    Text(state)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if service.needsFirstSync {
                Label(MountAlignmentText.notAlignedYet, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let stop = service.trackingStopText {
                Label(stop, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func header(_ status: MountStatus) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(palette.positive)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(service.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if let position = status.position {
                Text(MountStatusText.pointing(position, style: app.settings.coordinateStyle))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(service.displayName), connected")
        .accessibilityValue(status.position.map { "Points at \(MountStatusText.spokenPointing($0))" } ?? "No position yet")
    }

    /// The distance to the target, the phase of the slew and its progress.
    private func progress(_ status: MountStatus, target: CelestialObject?) -> some View {
        let distance = distanceToTarget(status, target: target)
        let phase = MountStatusText.phaseLine(status, targetName: service.slewTargetName)
        let fraction = MountStatusText.progress(status, startSeparation: service.slewStartSeparation)
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let distance {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(AimFormat.angle(distance.degrees))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(palette.guidance)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("to \(distance.name)")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Text(phase)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(phaseColor(status))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fraction {
                ProgressBar(fraction: fraction)
                    .frame(height: 5)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func phaseColor(_ status: MountStatus) -> Color {
        switch status.phase {
        case .slewing, .nudging: return palette.guidance
        case .idle:
            switch status.outcome {
            case .arrived?: return palette.positive
            case .failed?: return palette.warning
            case .aborted?, nil: return palette.secondaryText
            }
        case .disconnected: return palette.secondaryText
        }
    }

    /// How far the mount is from the target: from the slew's own target while it runs, else from the Aim target.
    private func distanceToTarget(_ status: MountStatus, target: CelestialObject?) -> (degrees: Double, name: String)? {
        if status.phase == .slewing, let separation = status.separation {
            return (separation, service.slewTargetName ?? "target")
        }
        guard let target, let position = status.position, let observer = app.observerContext?.observer else { return nil }
        let resolved = MountTargets.resolve(target, observer: observer, date: Date())
        return (position.angularSeparation(to: resolved.j2000), target.name)
    }

    @ViewBuilder
    private var messageLine: some View {
        if let text = service.errorText {
            messageRow(text, systemImage: "exclamationmark.triangle.fill", color: palette.warning) {
                service.dismissError()
            }
        } else if let error = service.status.lastError {
            messageRow("\(error.userMessage) Trying again\u{2026}", systemImage: "wifi.exclamationmark",
                       color: palette.warning, dismiss: nil)
        } else if let text = service.noticeText {
            messageRow(text, systemImage: "checkmark.circle.fill", color: palette.positive) {
                service.dismissNotice()
            }
        }
    }

    private func messageRow(_ text: String, systemImage: String, color: Color, dismiss: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Label(text, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 44, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
            }
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private func actions(target: CelestialObject?) -> some View {
        if service.isMoving || service.isStopping {
            HStack(spacing: 6) {
                MountStopButton(minHeight: 56)
                moreButton
                    .frame(width: 66)
            }
        } else {
            let observer = app.observerContext?.observer
            let goToReason = service.goToUnavailableReason(for: target, observer: observer)
            let syncReason = service.syncUnavailableReason(for: target)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    control("Go to", systemImage: "location.north.line.fill") {
                        if let target { confirmation = MountConfirmation(kind: .goTo, object: target) }
                    }
                    .disabled(goToReason != nil || service.isWorking)
                    .accessibilityLabel("Go to target")
                    .accessibilityValue(target?.name ?? "No target")
                    .accessibilityHint(goToReason ?? "Asks for confirmation, then slews the mount to the target.")
                    control("Sync", systemImage: "arrow.triangle.2.circlepath") {
                        if let target { confirmation = MountConfirmation(kind: .sync, object: target) }
                    }
                    .disabled(syncReason != nil || service.isWorking)
                    .accessibilityLabel("Sync mount to target")
                    .accessibilityHint(syncReason ?? "Use after centring the target. Asks for confirmation.")
                    MountStopButton(isCompact: true, minHeight: 50)
                    moreButton
                }
                // "Not aligned yet" is already said above, in the card.
                if target != nil, let goToReason, goToReason != MountAlignmentText.notAlignedYet {
                    Text(goToReason)
                        .font(.caption2)
                        .foregroundStyle(palette.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var moreButton: some View {
        control("Nudge", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
            sheet = .mount
        }
        .accessibilityLabel("Nudge and mount settings")
    }

    private func control(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(AimControlButtonStyle(minHeight: 50))
    }
}

/// A thin bar from empty to full in the accent colour.
private struct ProgressBar: View {
    let fraction: Double
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.stroke)
                Capsule()
                    .fill(palette.guidance)
                    .frame(width: max(geometry.size.width * fraction, 0))
            }
        }
    }
}
