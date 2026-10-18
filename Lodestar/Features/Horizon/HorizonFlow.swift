import SwiftUI
import LodestarKit

/// What the horizon controls of a screen have asked for: a site to record or a site whose skyline is to be cleared.
struct HorizonFlowState: Equatable {
    var recording: SavedSite?
    var clearing: SavedSite?
}

extension View {
    /// Presents the skyline recorder full screen and the confirmation before a skyline is cleared, for the requests
    /// the horizon controls put into `flow`. Attach it once per screen that has such controls.
    func horizonFlow(_ flow: Binding<HorizonFlowState>) -> some View {
        modifier(HorizonFlowModifier(flow: flow))
    }
}

private struct HorizonFlowModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var flow: HorizonFlowState

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $flow.recording) { site in
                HorizonRecordView(site: site, app: app)
                    .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
            }
            .confirmationDialog("Clear the skyline?", isPresented: isConfirmingClear, titleVisibility: .visible,
                                presenting: flow.clearing) { site in
                Button("Clear Skyline", role: .destructive) { clear(site) }
                Button("Keep Skyline", role: .cancel) {}
            } message: { site in
                Text("The recorded skyline of \u{201C}\(site.name)\u{201D} is removed and the site has an open horizon again.")
            }
    }

    private var isConfirmingClear: Binding<Bool> {
        Binding(get: { flow.clearing != nil }, set: { isPresented in
            if !isPresented { flow.clearing = nil }
        })
    }

    private func clear(_ site: SavedSite) {
        let store = app.settingsStore
        guard var saved = store.settings.savedSites.first(where: { $0.id == site.id }) else { return }
        saved.horizon = nil
        store.updateSite(saved)
    }
}

/// The "Horizon" section of the site editor: the state of the skyline with Record Skyline and Clear.
struct HorizonSiteSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    /// The site being edited, or `nil` for a site that is not saved yet.
    let siteID: UUID?
    @Binding var flow: HorizonFlowState

    var body: some View {
        SettingsSection(
            title: "Horizon",
            footer: "Trees, hills and buildings hide the sky near the horizon. Sweep the phone along the skyline once "
                + "and Lodestar takes it into account for rise and set times, what is up now and tonight\u{2019}s "
                + "plan. The skyline belongs to this place: record it again if you move the site.") {
            if let site = savedSite {
                Text(HorizonText.status(of: site.horizon))
                Button {
                    flow.recording = site
                } label: {
                    Label("Record Skyline\u{2026}", systemImage: "mountain.2")
                }
                if site.horizon != nil {
                    Button {
                        flow.clearing = site
                    } label: {
                        Text("Clear")
                            .foregroundStyle(palette.critical)
                    }
                }
            } else {
                Text(HorizonText.status(of: nil))
                SettingsCaption("Save the site first, then record its skyline.")
            }
        }
    }

    private var savedSite: SavedSite? {
        guard let siteID else { return nil }
        return app.settings.savedSites.first { $0.id == siteID }
    }
}

/// The skyline button on a saved site's row: record a skyline, or clear it.
struct HorizonSiteMenu: View {
    @Environment(\.palette) private var palette
    let site: SavedSite
    @Binding var flow: HorizonFlowState

    var body: some View {
        Menu {
            Button {
                flow.recording = site
            } label: {
                Label("Record Skyline\u{2026}", systemImage: "mountain.2")
            }
            if site.horizon != nil {
                Button(role: .destructive) {
                    flow.clearing = site
                } label: {
                    Label("Clear Skyline", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: site.horizon == nil ? "mountain.2" : "mountain.2.fill")
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skyline of \(site.name)")
        .accessibilityValue(HorizonText.status(of: site.horizon))
    }
}

/// Under "Current Location": a skyline belongs to a saved site, so the place can be saved as one first.
struct HorizonDeviceNote: View {
    let canSave: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCaption("Horizon: open. A recorded skyline belongs to a saved site, not to your current position.")
            Button(action: onSave) {
                Label("Save This Place as a Site\u{2026}", systemImage: "mountain.2")
            }
            .disabled(!canSave)
        }
    }
}
