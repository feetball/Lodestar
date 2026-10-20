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
            .confirmationDialog("Clear the Skyline?", isPresented: isConfirmingClear, titleVisibility: .visible,
                                presenting: flow.clearing) { site in
                Button("Clear Skyline", role: .destructive) { clear(site) }
                Button("Keep", role: .cancel) {}
            } message: { site in
                Text("\u{201C}\(site.name)\u{201D} goes back to an open horizon. You can record the skyline again, but "
                     + "this one cannot be brought back.")
            }
    }

    private var isConfirmingClear: Binding<Bool> {
        Binding(get: { flow.clearing != nil }, set: { isPresented in
            if !isPresented { flow.clearing = nil }
        })
    }

    private func clear(_ site: SavedSite) {
        let store = app.settingsStore
        // The stored site may have changed since the confirmation was asked for.
        if var saved = store.settings.savedSites.first(where: { $0.id == site.id }) {
            saved.horizon = nil
            store.updateSite(saved)
        }
        HorizonCoverageMemory.store(siteID: site.id, horizon: nil, coverage: 0)
    }
}

/// The "Horizon" section of the site editor: the state of the skyline with Record Skyline and Clear Skyline.
struct HorizonSiteSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    /// The width of the "Record Skyline" icon: the mountain symbol is much wider than the other rows' icons, so it is
    /// scaled into the same slot instead of sticking out to the left.
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 22
    /// The site being edited, or `nil` for a site that is not saved yet.
    let siteID: UUID?
    /// Whether the position being edited is not where the site was stored.
    let movedAway: Bool
    @Binding var flow: HorizonFlowState

    var body: some View {
        SettingsSection(
            title: "Horizon",
            footer: "Record the outline of trees, hills and buildings by turning slowly all the way round with the "
                + "camera on the skyline. Planning then counts what is behind it as hidden.") {
            if let site = savedSite {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HorizonText.status(of: site))
                    if movedAway, site.horizon != nil {
                        SettingsCaption("You moved this site. A skyline belongs to one spot: record it again if the "
                                        + "new place is different.")
                    }
                }
                Button {
                    flow.recording = site
                } label: {
                    Label {
                        Text("Record Skyline\u{2026}")
                    } icon: {
                        Image(systemName: "mountain.2")
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconWidth, height: iconWidth)
                    }
                }
                if site.horizon != nil {
                    Button {
                        flow.clearing = site
                    } label: {
                        Text("Clear Skyline\u{2026}")
                            .foregroundStyle(palette.critical)
                    }
                }
            } else {
                SettingsCaption("Save the site first, then record its skyline here.")
            }
        }
    }

    /// The site as stored now: recording and clearing save at once, outside the editor's draft.
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
                    Label("Clear Skyline\u{2026}", systemImage: "trash")
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
        .accessibilityLabel("Skyline options for \(site.name)")
        .accessibilityValue(HorizonText.status(of: site))
    }
}

/// The row under "Current Location": the device position has no skyline, because a skyline belongs to a place that can
/// be visited again. Tapping it explains that and offers to save the place as a site first.
struct HorizonDeviceRow: View {
    @Environment(\.palette) private var palette
    /// Why the place cannot be saved right now, or `nil`.
    let blocker: String?
    let onSave: () -> Void
    @State private var isAsking = false

    var body: some View {
        Button {
            isAsking = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mountain.2")
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record Skyline\u{2026}")
                        .foregroundStyle(palette.primaryText)
                    Text("\(HorizonText.openHorizon). Skylines belong to saved sites.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .alert("Save This Place First", isPresented: $isAsking) {
            if blocker == nil {
                Button("Save This Place as a Site\u{2026}", action: onSave)
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("A skyline belongs to a place you can come back to, so Lodestar keeps it with a saved site. Save "
                 + "this place as a site, then record its skyline." + (blocker.map { " \($0)" } ?? ""))
        }
    }
}
