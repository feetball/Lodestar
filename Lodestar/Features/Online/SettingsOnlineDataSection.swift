import SwiftUI

/// Settings ▸ Online Data: one switch per optional download with what it is for, what leaves the phone, when it was last
/// updated, an "Update now" button and the last error. The first switch asks for confirmation once.
struct SettingsOnlineDataSection: View {
    @Environment(AppModel.self) private var app
    @State private var pending: OnlineFeed?

    var body: some View {
        SettingsSection(title: OnlineText.sectionTitle, footer: OnlineText.footer) {
            SettingsCaption(OnlineText.intro)
                .sheet(item: $pending) { feed in
                    OnlineFirstTimeSheet(feed: feed)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
                }
            ForEach(OnlineFeed.allCases) { feed in
                OnlineFeedRows(feed: feed) { pending = feed }
            }
        }
    }
}

/// The rows of one feed.
private struct OnlineFeedRows: View {
    let feed: OnlineFeed
    /// Called when the first feed is switched on before the explanation has been read.
    let askFirst: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let online = app.online
        let status = online.status(feed)
        VStack(alignment: .leading, spacing: 4) {
            Toggle(feed.title, isOn: Binding(
                get: { online.isEnabled(feed) },
                set: { newValue in
                    if newValue && !online.hasExplained {
                        askFirst()
                    } else {
                        online.setEnabled(feed, newValue)
                    }
                }))
            SettingsCaption(OnlineText.purpose(feed))
            Text(OnlineText.leavesPhone(feed))
                .font(.footnote)
                .foregroundStyle(palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if status.isEnabled {
            // The "ago" text and the button's availability move on without any change to the status.
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                updatedRow(status, now: timeline.date)
            }
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                updateNowRow(status, now: timeline.date)
            }
        }
    }

    private func updatedRow(_ status: OnlineFeedStatus, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            InfoRow(label: "Updated", value: status.isUpdating ? OnlineText.updating : OnlineText.since(status.lastUpdate, now: now))
            if let error = status.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func updateNowRow(_ status: OnlineFeedStatus, now: Date) -> some View {
        let next = status.nextRequest.flatMap { $0 > now ? $0 : nil }
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                app.online.updateNow(feed)
            } label: {
                Label(OnlineText.updateNow, systemImage: "arrow.clockwise")
            }
            .disabled(status.isUpdating || next != nil)
            .accessibilityLabel("\(OnlineText.updateNow), \(feed.title)")
            if let next {
                SettingsCaption(OnlineText.nextUpdate(AppFormat.time(next, in: app.observerContext?.timeZone ?? .autoupdatingCurrent)))
            }
        }
    }
}

/// The explanation before the first feed is switched on.
private struct OnlineFirstTimeSheet: View {
    let feed: OnlineFeed
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(OnlineText.firstTimeTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(OnlineText.firstTimeBody)
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(OnlineText.firstTimeConfirm) {
                    app.online.markExplained()
                    app.online.setEnabled(feed, true)
                    dismiss()
                }
                .buttonStyle(.lodestarPrimary)
                .frame(maxWidth: .infinity)
                Button(OnlineText.firstTimeCancel) { dismiss() }
                    .buttonStyle(.lodestarSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .screenBackground(palette)
    }
}
