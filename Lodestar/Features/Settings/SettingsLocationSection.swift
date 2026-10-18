import SwiftUI
import UIKit
import LodestarKit

/// Settings ▸ Location: where the sky is computed for. The device's position or one of the saved observing sites,
/// with the status of location access, and adding, editing and deleting sites.
struct SettingsLocationSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var editorTarget: SiteEditorTarget?
    @State private var horizonFlow = HorizonFlowState()
    /// A place saved from "Current Location" to record its skyline: record it once the editor has closed.
    @State private var recordsAfterSaving = false
    @State private var siteToRecord: UUID?

    var body: some View {
        let store = app.settingsStore
        let settings = store.settings
        let isFull = settings.savedSites.count >= AppSettings.maximumSavedSites
        SettingsSection(
            title: "Location",
            footer: "Sky positions are worked out for this place. A saved site lets you plan a dark-sky trip before "
                + "you get there.") {
            if let context = app.observerContext {
                InfoRow(label: "Observing from", value: context.name)
                InfoRow(label: "Time zone", value: SettingsFormat.describe(context.timeZone, at: Date()))
            }
            SettingsDeviceLocationRow(isSelected: settings.locationSource == .device) {
                store.settings.locationSource = .device
                app.location.requestAuthorization()
            }
            .horizonFlow($horizonFlow)
            if settings.locationSource == .device {
                accessPrompt
                HorizonDeviceRow(blocker: skylineBlocker(isFull: isFull)) {
                    if let fix = app.location.fix {
                        recordsAfterSaving = true
                        editorTarget = .new(SiteDraft(name: "Current Location", fix: fix))
                    }
                }
            }
            ForEach(settings.savedSites) { site in
                SettingsSavedSiteRow(
                    site: site,
                    isSelected: settings.locationSource == .site(site.id),
                    horizonFlow: $horizonFlow,
                    onSelect: { store.settings.locationSource = .site(site.id) },
                    onEdit: { editorTarget = .existing(site) })
            }
            Button {
                editorTarget = .new(SiteDraft(name: "Site \(settings.savedSites.count + 1)"))
            } label: {
                Label("Add Site\u{2026}", systemImage: "plus.circle")
            }
            .disabled(isFull)
            .sheet(item: $editorTarget, onDismiss: recordPendingSkyline) { target in
                SettingsSheetRoot {
                    SiteEditor(target: target) { site in
                        // A newly added site becomes the observing location, as in onboarding.
                        if case .new = target {
                            app.settingsStore.settings.locationSource = .site(site.id)
                            if recordsAfterSaving { siteToRecord = site.id }
                        }
                    }
                }
            }
            if let fix = app.location.fix {
                Button {
                    editorTarget = .new(SiteDraft(name: "Current Location", fix: fix))
                } label: {
                    Label("Save Current Location as Site\u{2026}", systemImage: "location")
                }
                .disabled(isFull)
            }
            if isFull {
                SettingsCaption("You have reached the limit of \(AppSettings.maximumSavedSites) saved sites.")
            }
        }
    }

    /// Why the current place cannot be saved as a site to record its skyline right now, or `nil`.
    private func skylineBlocker(isFull: Bool) -> String? {
        if app.location.fix == nil { return "Lodestar does not have your position yet." }
        if isFull { return "You have reached the limit of \(AppSettings.maximumSavedSites) saved sites. Delete one first." }
        return nil
    }

    /// After the editor has closed, records the skyline of a place that was saved for it.
    private func recordPendingSkyline() {
        recordsAfterSaving = false
        guard let id = siteToRecord else { return }
        siteToRecord = nil
        if let site = app.settings.savedSites.first(where: { $0.id == id }) {
            horizonFlow.recording = site
        }
    }

    /// What to do when the device location is the source but it cannot be used yet.
    @ViewBuilder private var accessPrompt: some View {
        if app.location.isDenied {
            VStack(alignment: .leading, spacing: 8) {
                SettingsCaption("Location access is turned off for Lodestar. Allow it in the iOS Settings app, or "
                                + "choose a saved site.")
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.lodestarSecondary)
            }
        } else if !app.location.isAuthorized {
            VStack(alignment: .leading, spacing: 8) {
                SettingsCaption("Lodestar uses your location only while it is open, only to work out the sky. An "
                                + "approximate location is enough.")
                Button("Allow Location Access") {
                    app.location.requestAuthorization()
                }
                .buttonStyle(.lodestarSecondary)
            }
        }
    }
}

/// A round selection mark: filled with a check when chosen.
private struct SettingsSelectionMark: View {
    @Environment(\.palette) private var palette
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
            .accessibilityHidden(true)
    }
}

/// The "Current Location" choice with the state of location access and accuracy.
private struct SettingsDeviceLocationRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                SettingsSelectionMark(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Location")
                        .foregroundStyle(palette.primaryText)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 8)
                if app.location.isAuthorized && app.location.isReducedAccuracy {
                    StatusChip(systemImage: "location.circle", text: "Approximate", tone: .warning)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var statusText: String {
        let location = app.location
        if location.isDenied { return "Location access is off" }
        if !location.isAuthorized { return "Tap to allow location access" }
        guard let position = location.stableLocation else {
            return location.lastErrorDescription ?? "Waiting for a location fix\u{2026}"
        }
        var text = SettingsFormat.coordinates(of: position)
        if let fix = location.fix {
            text += " \u{00B7} " + SettingsFormat.accuracy(metres: fix.horizontalAccuracy)
        }
        return text
    }
}

/// A saved site: tap the name to observe from it, tap the pencil to edit it.
private struct SettingsSavedSiteRow: View {
    @Environment(\.palette) private var palette
    let site: SavedSite
    let isSelected: Bool
    @Binding var horizonFlow: HorizonFlowState
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    SettingsSelectionMark(isSelected: isSelected)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.name)
                            .foregroundStyle(palette.primaryText)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                        if site.horizon != nil {
                            Text("Horizon: \(HorizonText.status(of: site))")
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            HorizonSiteMenu(site: site, flow: $horizonFlow)
            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(site.name)")
        }
    }

    private var subtitle: String {
        var parts = [SettingsFormat.coordinates(of: site.location), SettingsFormat.elevation(site.elevation)]
        if let zone = site.timeZone {
            parts.append(SettingsFormat.utcOffset(of: zone, at: Date()))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
