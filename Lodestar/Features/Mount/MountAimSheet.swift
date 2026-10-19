import SwiftUI
import LodestarKit

/// The mount sheet of the Aim screen: the controls of a connected mount, or the connection screen while there is none.
/// It is small by default and leaves the sky behind it usable.
struct MountAimSheet: View {
    let model: AimViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    private var service: MountService { MountService.shared }

    var body: some View {
        NavigationStack {
            Group {
                if service.isConnected {
                    MountControlPanel(model: model)
                } else {
                    MountConnectionView()
                }
            }
            .sheetToolbar(confirm: "Done", onConfirm: { dismiss() })
        }
        .background(palette.background)
        .foregroundStyle(palette.primaryText)
        .presentationBackground(palette.background)
    }
}

/// What a connected mount offers: the state, GoTo and Sync for the chosen target, Stop, the nudge pad and the tracking switch.
private struct MountControlPanel: View {
    let model: AimViewModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var confirmation: MountConfirmation?
    private var service: MountService { MountService.shared }

    private static let syncExplanation = """
        After the target is centred in your camera, a sync tells the mount where it points. \
        It improves every later GoTo nearby.
        """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                if service.usesLodestarAlignment {
                    MountSkyWatcherSetupCard(onSync: syncOnTarget)
                }
                targetCard
                MountStopButton(minHeight: 56)
                nudgeCard
                NavigationLink {
                    MountConnectionView()
                } label: {
                    HStack {
                        Label("Connection, limits and safety", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.tertiaryText)
                    }
                    .foregroundStyle(palette.primaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card(palette)
            }
            .padding(16)
        }
        .screenBackground(palette)
        .navigationTitle("Mount")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $confirmation) { confirmation in
            MountConfirmationSheet(confirmation: confirmation)
                .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        // The visual review opens the sync confirmation once the target is chosen (`screen=mount-sw-sync`).
        .task(id: model.guidanceTarget?.id) {
            if ScreenshotMode.current?.screen == .mountSkyWatcherSync, let target = model.guidanceTarget {
                confirmation = MountConfirmation(kind: .sync, object: target)
            }
        }
        #endif
    }

    // MARK: Cards

    /// Opens the sync confirmation for the Aim target, from the set-up card.
    private var syncOnTarget: (() -> Void)? {
        guard let target = model.guidanceTarget else { return nil }
        return { confirmation = MountConfirmation(kind: .sync, object: target) }
    }

    private var statusCard: some View {
        let status = service.status
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(palette.positive)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(service.displayName)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 6)
                Text(MountStatusText.phaseLine(status, targetName: service.slewTargetName))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
            if let position = status.position {
                Text(MountStatusText.pointing(position, style: app.settings.coordinateStyle))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }
            if let warning = service.alignmentWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = service.alignmentLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(service.needsFirstSync ? palette.warning : palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let state = service.trackingAndPierLine, service.usesLodestarAlignment {
                Text(state)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            if service.needsFirstSync {
                Label(MountAlignmentText.notAlignedYet, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let stop = service.trackingStopText {
                Label(stop, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MountMessages()
            if service.capabilities?.canSetTracking == true {
                Toggle("Tracking", isOn: Binding(
                    get: { status.isTracking ?? false },
                    set: { service.setTracking($0) }))
                    .disabled(status.phase == .slewing)
            }
        }
        .card(palette)
        .accessibilityElement(children: .contain)
    }

    private var targetCard: some View {
        let target = model.guidanceTarget
        let observer = app.observerContext?.observer
        let goToReason = service.goToUnavailableReason(for: target, observer: observer)
        let syncReason = service.syncUnavailableReason(for: target)
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Target", systemImage: "scope")
            if let target {
                HStack(spacing: 10) {
                    ObjectIcon(category: target.category, size: 16)
                    Text(target.name)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
            } else {
                Text("Choose a target with the Target button on the Aim screen.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            if let target {
                Button {
                    confirmation = MountConfirmation(kind: .goTo, object: target)
                } label: {
                    Label("Go to \(target.name)", systemImage: "location.north.line.fill")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .buttonStyle(.lodestarPrimary)
                .disabled(goToReason != nil || service.isWorking)
                if let goToReason {
                    Text(goToReason)
                        .font(.footnote)
                        .foregroundStyle(palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    confirmation = MountConfirmation(kind: .sync, object: target)
                } label: {
                    Label("Centered \u{2014} sync mount to \(target.name)", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .lineLimit(2)
                }
                .buttonStyle(.lodestarSecondary)
                .disabled(syncReason != nil || service.isWorking)
                Text(syncReason ?? Self.syncExplanation)
                    .font(.footnote)
                    .foregroundStyle(syncReason == nil ? palette.secondaryText : palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(palette)
    }

    private var nudgeCard: some View {
        MountNudgeCard()
            .card(palette)
    }
}

/// The error or notice of the mount service as one dismissible line.
struct MountMessages: View {
    @Environment(\.palette) private var palette
    private var service: MountService { MountService.shared }

    var body: some View {
        if let text = service.errorText {
            line(text, systemImage: "exclamationmark.triangle.fill", color: palette.warning) {
                service.dismissError()
            }
        } else if let error = service.status.lastError {
            line("\(error.userMessage) Trying again\u{2026}", systemImage: "wifi.exclamationmark",
                 color: palette.warning, dismiss: nil)
        } else if let text = service.noticeText {
            line(text, systemImage: "checkmark.circle.fill", color: palette.positive) {
                service.dismissNotice()
            }
        }
    }

    private func line(_ text: String, systemImage: String, color: Color, dismiss: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Label(text, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
            }
        }
    }
}
