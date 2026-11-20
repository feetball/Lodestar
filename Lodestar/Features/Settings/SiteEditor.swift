import SwiftUI
import LodestarKit

/// What the site editor starts from.
enum SiteEditorTarget: Identifiable {
    /// A new site, starting from the draft.
    case new(SiteDraft)
    /// A saved site.
    case existing(SavedSite)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let site): return site.id.uuidString
        }
    }
}

/// Adds or edits a saved observing site: its name, its position (typed, picked on the map or taken from the
/// device), its elevation and the time zone found for that position.
///
/// Present it in a sheet wrapped in `SettingsSheetRoot`; it brings its own navigation stack.
struct SiteEditor: View {
    /// Wait after the last change to the position before the time zone is looked up (typing, map picks).
    private static let lookupDelay: Duration = .milliseconds(600)
    /// A site counts as moved, for its skyline, when its position changed by more than this many degrees (about 100 m).
    private static let movedPositionDegrees = 0.001
    /// A site that was moved by at least this many metres loses its terrain horizon when it is saved: the hills around
    /// the new place are not the ones the old horizon was computed from.
    private static let movedFarMeters = 1_000.0

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let existingSite: SavedSite?
    private let onSaved: ((SavedSite) -> Void)?
    @State private var draft: SiteDraft
    @State private var timeZoneStatus: SiteTimeZoneStatus
    @State private var lookupAttempt = 0
    @State private var isSaving = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingMove = false
    @State private var failureMessage: String?
    @State private var horizonFlow = HorizonFlowState()
    @State private var terrainModel = TerrainHorizonModel()

    /// - Parameters:
    ///   - target: The new site's starting point, or the site to edit.
    ///   - onSaved: Called with the site after it was added or updated, just before the editor closes.
    init(target: SiteEditorTarget, onSaved: ((SavedSite) -> Void)? = nil) {
        self.onSaved = onSaved
        switch target {
        case .new(let draft):
            existingSite = nil
            _draft = State(initialValue: draft)
            _timeZoneStatus = State(initialValue: .waitingForCoordinates)
        case .existing(let site):
            existingSite = site
            _draft = State(initialValue: SiteDraft(site: site))
            let status: SiteTimeZoneStatus
            if let zone = site.timeZone {
                status = SettingsFormat.isNominal(zone) ? .approximate(zone) : .resolved(zone)
            } else {
                status = .waitingForCoordinates
            }
            _timeZoneStatus = State(initialValue: status)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                positionSection
                timeZoneSection
                HorizonSiteSection(siteID: existingSite?.id, movedAway: hasMovedAway, flow: $horizonFlow)
                HorizonTerrainSection(siteID: existingSite?.id, movedAway: hasMovedAway, elevation: $draft.elevation,
                                      model: terrainModel)
                if existingSite != nil {
                    deleteSection
                }
            }
            .horizonFlow($horizonFlow)
            .alert("Save the Moved Site?", isPresented: $isConfirmingMove) {
                Button("Save") { startSaving() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(movedSiteMessage)
            }
            .themedList(palette)
            .scrollDismissesKeyboard(.interactively)
            .disabled(isSaving)
            .navigationTitle(existingSite == nil ? "New Site" : "Edit Site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .tint(palette.accent)
                    } else {
                        Button("Save") { save() }
                            .disabled(draft.location == nil)
                    }
                }
            }
            .task(id: lookupKey) {
                await lookUpTimeZone()
            }
            .onChange(of: timeZoneStatus) { _, _ in
                finishSavingIfReady()
            }
            .onChange(of: draft.name) { _, name in
                if name.count > SavedSite.maximumNameLength {
                    draft.name = String(name.prefix(SavedSite.maximumNameLength))
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        // Closing the editor stops a download that is still running.
        .onDisappear { terrainModel.cancel() }
    }

    // MARK: Sections

    private var nameSection: some View {
        SettingsSection(title: "Name") {
            TextField("Site name", text: $draft.name, prompt: Text("Site name").foregroundStyle(palette.tertiaryText))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            if let failureMessage {
                Text(failureMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.critical)
            }
        }
    }

    private var positionSection: some View {
        SettingsSection(
            title: "Position",
            footer: "Type decimal degrees (40.015 or \u{2212}105.27) or degrees, minutes and seconds with N, S, E or "
                + "W. The map cannot tell the elevation, so enter it if you know it.") {
            SiteCoordinateField(title: "Latitude", prompt: "40.0150\u{00B0} N", text: $draft.latitudeText,
                                isValid: draft.isLatitudeValid,
                                errorMessage: "Not a latitude between 90\u{00B0} S and 90\u{00B0} N.")
            SiteCoordinateField(title: "Longitude", prompt: "105.2705\u{00B0} W", text: $draft.longitudeText,
                                isValid: draft.isLongitudeValid,
                                errorMessage: "Not a longitude between 180\u{00B0} W and 180\u{00B0} E.")
            SettingsNumberField(title: "Elevation", unit: "m", value: $draft.elevation,
                                range: GeographicLocation.elevationRange, fractionDigits: 0)
            SkyQualityLine(location: draft.location)
            NavigationLink {
                MapSitePicker(initialLocation: draft.location,
                              fallbackCenter: app.observerContext?.location) { picked in
                    draft.setPosition(picked)
                }
            } label: {
                Label("Choose on Map", systemImage: "map")
            }
            if let fix = app.location.fix {
                Button {
                    useDevicePosition(fix)
                } label: {
                    Label("Use My Current Position", systemImage: "location")
                }
            }
        }
    }

    private var timeZoneSection: some View {
        SettingsSection(
            title: "Time Zone",
            footer: "Rise, set and twilight times at this site are shown in its local time.") {
            SiteTimeZoneRow(status: timeZoneStatus, date: Date())
            if case .approximate = timeZoneStatus {
                Button("Look Up Again") { lookupAttempt += 1 }
            }
        }
    }

    private var deleteSection: some View {
        SettingsSection(title: "Delete") {
            if isConfirmingDelete {
                SettingsCaption("Delete \u{201C}\(existingSite?.name ?? "this site")\u{201D}? This cannot be undone.")
                Button {
                    deleteSite()
                } label: {
                    Text("Delete Site")
                        .foregroundStyle(palette.critical)
                }
                Button("Keep Site") { isConfirmingDelete = false }
            } else {
                Button {
                    isConfirmingDelete = true
                } label: {
                    Text("Delete Site\u{2026}")
                        .foregroundStyle(palette.critical)
                }
            }
        }
    }

    /// Whether the position being edited is more than about 100 m from where the saved site was: its skyline then
    /// belongs to another spot.
    private var hasMovedAway: Bool {
        guard let existingSite, let location = draft.location else { return false }
        return abs(existingSite.latitude - location.latitude) > Self.movedPositionDegrees
            || abs(existingSite.longitude - location.longitude) > Self.movedPositionDegrees
    }

    /// The site as stored now: the skyline and the terrain horizon are saved on their own while the editor is open.
    private var storedSite: SavedSite? {
        guard let existingSite else { return nil }
        return app.settings.savedSites.first { $0.id == existingSite.id }
    }

    /// Whether the position being edited is at least `movedFarMeters` from where the saved site was.
    private var hasMovedFar: Bool {
        guard let existingSite, let location = draft.location else { return false }
        return HorizonText.distanceMetres(existingSite.location, location) >= Self.movedFarMeters
    }

    /// What saving a site that moved far does to its skylines: the terrain horizon, which can be computed again, is
    /// removed; the recorded skyline, which cannot, is kept.
    private var movedSiteMessage: String {
        guard let stored = storedSite, let existingSite, let location = draft.location, hasMovedFar else { return "" }
        let kilometres = max(1, Int((HorizonText.distanceMetres(existingSite.location, location) / 1000).rounded()))
        var lines = ["You moved this site by about \(kilometres) km."]
        if stored.terrainHorizon != nil {
            lines.append("Its terrain horizon belongs to the old place, so it is removed: compute it again for the new "
                         + "one.")
        }
        if stored.horizon != nil {
            lines.append("Its recorded skyline is kept: record it again if the new place is different.")
        }
        return lines.joined(separator: " ")
    }

    /// Whether the site moved far and has a skyline of the old place, so the user is told what saving does to it first.
    private var needsMoveConfirmation: Bool {
        guard hasMovedFar, let stored = storedSite else { return false }
        return stored.horizon != nil || stored.terrainHorizon != nil
    }

    // MARK: Time zone

    /// Restarts the time zone lookup when the position (not the name or elevation) or the attempt changes.
    private struct LookupKey: Equatable {
        var position: GeographicLocation?
        var attempt: Int
    }

    private var lookupKey: LookupKey {
        LookupKey(position: draft.location.map { GeographicLocation(latitude: $0.latitude, longitude: $0.longitude) },
                  attempt: lookupAttempt)
    }

    /// Finds the zone of the drafted position. A saved site whose position did not change keeps its real zone;
    /// otherwise the geocoder is asked after a short pause, and the longitude-based estimate stands in when it
    /// cannot answer. The task is cancelled when the position changes or the editor closes.
    private func lookUpTimeZone() async {
        guard let location = draft.location else {
            timeZoneStatus = .waitingForCoordinates
            return
        }
        if let site = existingSite, let zone = site.timeZone, !SettingsFormat.isNominal(zone),
           abs(site.latitude - location.latitude) < 1e-6, abs(site.longitude - location.longitude) < 1e-6,
           lookupAttempt == 0 {
            timeZoneStatus = .resolved(zone)
            return
        }
        timeZoneStatus = .resolving
        try? await Task.sleep(for: Self.lookupDelay)
        guard !Task.isCancelled else { return }
        let zone = await TimeZoneResolver.timeZone(for: location)
        guard !Task.isCancelled else { return }
        if let zone {
            timeZoneStatus = .resolved(zone)
        } else {
            timeZoneStatus = .approximate(TimeZoneResolver.nominalTimeZone(longitude: location.longitude))
        }
    }

    private var isTimeZoneLookupPending: Bool {
        switch timeZoneStatus {
        case .resolving: return true
        case .waitingForCoordinates: return draft.location != nil
        case .resolved, .approximate: return false
        }
    }

    // MARK: Actions

    private func useDevicePosition(_ fix: LocationFix) {
        let current = SiteDraft(name: draft.name, fix: fix)
        draft.latitudeText = current.latitudeText
        draft.longitudeText = current.longitudeText
        // A fix without a valid altitude (an approximate location) leaves the elevation the user typed alone.
        if SiteDraft.hasUsableAltitude(fix) {
            draft.elevation = current.elevation
        }
    }

    /// Saves, after the user was told what a move far away does to the skyline of the site.
    private func save() {
        guard draft.location != nil else { return }
        if needsMoveConfirmation {
            isConfirmingMove = true
        } else {
            startSaving()
        }
    }

    /// Saves now, or as soon as the time zone lookup that is under way has an answer.
    private func startSaving() {
        guard draft.location != nil else { return }
        failureMessage = nil
        if isTimeZoneLookupPending {
            isSaving = true
        } else {
            commit()
        }
    }

    private func finishSavingIfReady() {
        if isSaving, !isTimeZoneLookupPending {
            commit()
        }
    }

    private func commit() {
        isSaving = false
        guard let location = draft.location else { return }
        let zone = timeZoneStatus.timeZone ?? TimeZoneResolver.nominalTimeZone(longitude: location.longitude)
        // The skyline is recorded and saved on its own while the editor is open, so the stored one is the current one.
        let stored = storedSite
        let horizon = stored?.horizon
        // The terrain horizon is computed and saved on its own as well, like the skyline. It belongs to the old place
        // once the site moved far.
        let terrainHorizon = hasMovedFar ? nil : stored?.terrainHorizon
        guard let site = SavedSite(id: existingSite?.id ?? UUID(), name: draft.name, latitude: location.latitude,
                                   longitude: location.longitude, elevation: location.elevation,
                                   timeZoneIdentifier: zone.identifier, horizon: horizon,
                                   terrainHorizon: terrainHorizon) else {
            failureMessage = "This position cannot be saved. Check the latitude, longitude and elevation."
            return
        }
        let store = app.settingsStore
        if existingSite != nil {
            store.updateSite(site)
            if site.terrainHorizon == nil { TerrainTileMemory.forget(siteID: site.id) }
        } else if !store.addSite(site) {
            failureMessage = "You can keep up to \(AppSettings.maximumSavedSites) sites. Delete one to add another."
            return
        }
        onSaved?(site)
        dismiss()
    }

    private func deleteSite() {
        guard let existingSite else { return }
        app.settingsStore.removeSites(withIDs: [existingSite.id])
        HorizonCoverageMemory.store(siteID: existingSite.id, horizon: nil, coverage: 0)
        TerrainTileMemory.forget(siteID: existingSite.id)
        dismiss()
    }
}

/// A latitude or longitude text field with an inline message when the text cannot be read.
private struct SiteCoordinateField: View {
    @Environment(\.palette) private var palette
    let title: String
    let prompt: String
    @Binding var text: String
    let isValid: Bool
    let errorMessage: String

    private var showsError: Bool {
        !isValid && !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
            TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(palette.tertiaryText))
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .submitLabel(.done)
                .foregroundStyle(showsError ? palette.critical : palette.primaryText)
            if showsError {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.critical)
            }
        }
    }
}

/// The result of the time zone lookup for the site being edited.
private struct SiteTimeZoneRow: View {
    @Environment(\.palette) private var palette
    let status: SiteTimeZoneStatus
    let date: Date

    var body: some View {
        switch status {
        case .waitingForCoordinates:
            SettingsCaption("Enter a valid latitude and longitude to find the time zone.")
        case .resolving:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(palette.accent)
                Text("Looking up the time zone\u{2026}")
                    .foregroundStyle(palette.secondaryText)
            }
        case .resolved(let zone):
            Text(SettingsFormat.describe(zone, at: date))
        case .approximate(let zone):
            VStack(alignment: .leading, spacing: 4) {
                Text(SettingsFormat.describe(zone, at: date))
                SettingsCaption("The time zone could not be looked up, perhaps because there is no network. "
                                + "Times at this site may be off by an hour.")
            }
        }
    }
}
