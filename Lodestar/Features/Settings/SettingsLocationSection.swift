import SwiftUI
import UIKit
import LodestarKit

/// What Settings ▸ Location has asked to be presented: the site editor, and the skyline recorder or the confirmation
/// before a skyline is cleared. The rows only set it; the sheets themselves hang on the Settings form
/// (`settingsLocationSheets`), because a presentation attached to one row is lost when that row has scrolled out of view
/// and a list of sites can be long.
struct SettingsLocationPresentation {
    var editorTarget: SiteEditorTarget?
    var horizonFlow = HorizonFlowState()
    /// A place saved from "Current Location" to record its skyline: record it once the editor has closed.
    var recordsAfterSaving = false
    var siteToRecord: UUID?
}

extension View {
    /// Presents what `presentation` asks for. Attach it once, to the Settings form, which is always on screen.
    func settingsLocationSheets(_ presentation: Binding<SettingsLocationPresentation>) -> some View {
        modifier(SettingsLocationSheets(presentation: presentation))
    }
}

private struct SettingsLocationSheets: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var presentation: SettingsLocationPresentation

    func body(content: Content) -> some View {
        content
            .horizonFlow($presentation.horizonFlow)
            .sheet(item: $presentation.editorTarget, onDismiss: recordPendingSkyline) { target in
                SettingsSheetRoot {
                    SiteEditor(target: target) { site in
                        // A newly added site becomes the observing location, as in onboarding.
                        if case .new = target {
                            app.settingsStore.settings.locationSource = .site(site.id)
                            if presentation.recordsAfterSaving { presentation.siteToRecord = site.id }
                        }
                    }
                }
            }
    }

    /// After the editor has closed, records the skyline of a place that was saved for it.
    private func recordPendingSkyline() {
        presentation.recordsAfterSaving = false
        guard let id = presentation.siteToRecord else { return }
        presentation.siteToRecord = nil
        if let site = app.settings.savedSites.first(where: { $0.id == id }) {
            presentation.horizonFlow.recording = site
        }
    }
}

/// Settings ▸ Location: where the sky is computed for. The device's position or one of the saved observing sites,
/// with the status of location access, and adding, editing and deleting sites.
struct SettingsLocationSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Binding var presentation: SettingsLocationPresentation

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
            if settings.locationSource == .device {
                accessPrompt
                HorizonDeviceRow(blocker: skylineBlocker(isFull: isFull)) {
                    if let fix = app.location.fix {
                        presentation.recordsAfterSaving = true
                        presentation.editorTarget = .new(SiteDraft(name: "Current Location", fix: fix))
                    }
                }
            }
            ForEach(settings.savedSites) { site in
                SettingsSavedSiteRow(
                    site: site,
                    isSelected: settings.locationSource == .site(site.id),
                    horizonFlow: $presentation.horizonFlow,
                    onSelect: { store.settings.locationSource = .site(site.id) },
                    onEdit: { presentation.editorTarget = .existing(site) })
            }
            Button {
                presentation.editorTarget = .new(SiteDraft(name: "Site \(settings.savedSites.count + 1)"))
            } label: {
                Label("Add Site\u{2026}", systemImage: "plus.circle")
            }
            .disabled(isFull)
            if let fix = app.location.fix {
                Button {
                    presentation.editorTarget = .new(SiteDraft(name: "Current Location", fix: fix))
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let site: SavedSite
    let isSelected: Bool
    @Binding var horizonFlow: HorizonFlowState
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // At the largest text sizes the two icon buttons would leave the text a column of a few letters, so they
            // move to their own line under the text.
            VStack(alignment: .leading, spacing: 4) {
                selectButton
                HStack(spacing: 12) {
                    HorizonSiteMenu(site: site, flow: $horizonFlow)
                    editButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(spacing: 12) {
                selectButton
                HorizonSiteMenu(site: site, flow: $horizonFlow)
                editButton
            }
        }
    }

    private var selectButton: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                SettingsSelectionMark(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if site.horizon != nil {
                        Text("Horizon: \(HorizonText.status(of: site))")
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var editButton: some View {
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

    private var subtitle: String {
        var parts = [SettingsFormat.coordinates(of: site.location), SettingsFormat.elevation(site.elevation)]
        if let zone = site.timeZone {
            // An estimate from the longitude has no daylight saving time; it is replaced by the real zone once the
            // app is online (see `AppModel.upgradeEstimatedTimeZones`).
            let offset = SettingsFormat.utcOffset(of: zone, at: Date())
            parts.append(SettingsFormat.isNominal(zone) ? "\(offset) (estimated)" : offset)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
