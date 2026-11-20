import SwiftUI
import LodestarKit

/// Works out and stores the terrain horizon of a saved site, and says how it went. One per site editor.
@MainActor
@Observable
final class TerrainHorizonModel {
    /// What the terrain horizon section is doing.
    enum Phase: Equatable {
        case idle
        /// Working; the text is the progress line.
        case working(String)
        case done(TerrainSummary)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    @ObservationIgnored private var task: Task<Void, Never>?

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    /// Downloads the elevation tiles around `site`, works out its terrain horizon off the main thread and stores it with the
    /// site (the stored one, which may have changed since the editor opened).
    func compute(for site: SavedSite, app: AppModel) {
        guard !isWorking else { return }
        let tileCount = min(TerrainHorizon.requiredTiles(at: site.location).count, TerrainHorizonLoader.maximumTiles)
        if let first = TerrainHorizon.requiredTiles(at: site.location).first {
            phase = .working(TerrainText.progress(.downloading(index: 1, count: tileCount, tile: first)))
        } else {
            phase = .working(TerrainText.computing)
        }
        let model = self
        task = Task {
            let outcome = await app.online.computeTerrainHorizon(for: site.location) { progress in
                Task { @MainActor in model.show(progress) }
            }
            model.task = nil
            model.finish(outcome, site: site, app: app)
        }
    }

    private func show(_ progress: TerrainHorizonLoader.Progress) {
        guard isWorking else { return }
        phase = .working(TerrainText.progress(progress))
    }

    /// Stops a download that is under way; nothing is changed.
    func cancel() {
        task?.cancel()
    }

    private func finish(_ outcome: TerrainComputation, site: SavedSite, app: AppModel) {
        switch outcome {
        case .failed(let message):
            phase = .failed(message)
        case .cancelled:
            phase = .failed(TerrainText.cancelled)
        case .done(let result, let tilesUsed, let unavailable):
            // The stored site may have changed while the tiles came in (the editor only keeps a draft), so build on that one.
            guard var saved = app.settings.savedSites.first(where: { $0.id == site.id }) else {
                phase = .failed(TerrainText.unreadable)
                return
            }
            saved.terrainHorizon = result.profile
            app.settingsStore.updateSite(saved)
            phase = .done(TerrainText.summary(of: result, tilesUsed: tilesUsed, unavailable: unavailable))
        }
    }

    /// Forgets the last result (the terrain horizon was removed).
    func reset() {
        if !isWorking { phase = .idle }
    }
}

/// The Terrain Horizon section of the site editor: the state of the site's terrain horizon, "Compute from Elevation Data..."
/// (which asks first, then downloads the elevation tiles, works out the skyline off the main thread, stores it with the site
/// and offers the ground elevation) and "Remove Terrain Horizon...". Needs the Terrain horizons switch in Settings ▸ Online
/// Data.
struct HorizonTerrainSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    /// The site being edited, or `nil` for a site that is not saved yet.
    let siteID: UUID?
    /// Whether the position being edited is not where the site was stored; the terrain horizon is computed for the stored
    /// place only.
    let movedAway: Bool
    /// The elevation in the editor; "Use ... as the Site Elevation" puts the elevation of the data into it.
    @Binding var elevation: Double
    /// The model of the editor, which stops it when the editor closes.
    let model: TerrainHorizonModel
    @State private var asksToDownload = false
    @State private var asksToRemove = false

    var body: some View {
        SettingsSection(title: TerrainText.sectionTitle, footer: TerrainText.footer) {
            if let site = savedSite {
                content(for: site)
            } else {
                SettingsCaption(TerrainText.saveFirst)
            }
        }
    }

    @ViewBuilder
    private func content(for site: SavedSite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(site.terrainHorizon.map(TerrainText.status) ?? TerrainText.notComputed)
            if movedAway {
                SettingsCaption(site.terrainHorizon != nil ? TerrainText.movedStored : TerrainText.moved)
            }
            if !isOn {
                SettingsCaption(TerrainText.switchedOff)
            }
        }
        switch model.phase {
        case .idle:
            EmptyView()
        case .working(let text):
            HStack(spacing: 10) {
                ProgressView()
                    .tint(palette.accent)
                Text(text)
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityElement(children: .combine)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .done(let summary):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(summary.lines, id: \.self) { line in
                    SettingsCaption(line)
                }
            }
            if let ground = summary.groundElevationMeters, ground != Int(elevation.rounded()) {
                Button(TerrainText.useElevation(ground)) { elevation = Double(ground) }
            }
        }
        if model.isWorking {
            Button(TerrainText.cancel) { model.cancel() }
        } else {
            Button {
                asksToDownload = true
            } label: {
                Label(TerrainText.compute, systemImage: "icloud.and.arrow.down")
            }
            .disabled(!isOn || movedAway)
            // The question hangs on the button that asks it, a row that is certainly alive when it is tapped.
            .alert(TerrainText.confirmTitle, isPresented: $asksToDownload) {
                Button(TerrainText.confirmButton) { model.compute(for: site, app: app) }
                Button(TerrainText.cancel, role: .cancel) {}
            } message: {
                Text(TerrainText.confirmMessage(tileCount: tileCount))
            }
        }
        if site.terrainHorizon != nil, !model.isWorking {
            Button {
                asksToRemove = true
            } label: {
                Text(TerrainText.remove)
                    .foregroundStyle(palette.critical)
            }
            .confirmationDialog(TerrainText.removeTitle, isPresented: $asksToRemove, titleVisibility: .visible) {
                Button(TerrainText.removeButton, role: .destructive) { remove() }
                Button(TerrainText.keepButton, role: .cancel) {}
            } message: {
                Text(TerrainText.removeMessage)
            }
        }
    }

    private var isOn: Bool { app.online.isEnabled(.terrain) }

    /// The site as stored now: computing saves at once, outside the editor's draft, like recording a skyline.
    private var savedSite: SavedSite? {
        guard let siteID else { return nil }
        return app.settings.savedSites.first { $0.id == siteID }
    }

    private var tileCount: Int {
        guard let site = savedSite else { return 0 }
        return min(TerrainHorizon.requiredTiles(at: site.location).count, TerrainHorizonLoader.maximumTiles)
    }

    private func remove() {
        // The stored site may have changed since the question was asked.
        if var saved = savedSite {
            saved.terrainHorizon = nil
            app.settingsStore.updateSite(saved)
        }
        model.reset()
    }
}
