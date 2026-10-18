import Foundation
import LodestarKit
import Observation

/// Loads the bundled sky catalog, with the bundled bright asteroids and any comets and asteroids downloaded since
/// (see `setDownloadedSmallBodies(_:)`), and answers lookups and searches.
@MainActor
@Observable
final class CatalogService {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    /// The catalog in use; a new value whenever the downloaded small bodies change.
    private(set) var catalog: Catalog?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var base: Catalog?
    @ObservationIgnored private var bundledSmallBodies: [SmallBody] = []
    @ObservationIgnored private var downloadedSmallBodies: [SmallBody] = []

    /// Decodes the catalog off the main actor. Safe to call repeatedly and from several places: callers that
    /// arrive while a load is running wait for it, a loaded catalog is kept, and a failed load is retried.
    func load() async {
        if loadState == .loaded { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
    }

    /// Replaces the downloaded comets and asteroids (an empty array removes them). They join the bundled asteroids; a
    /// downloaded body replaces a bundled one with the same identifier. Costs a few milliseconds.
    func setDownloadedSmallBodies(_ bodies: [SmallBody]) {
        downloadedSmallBodies = bodies
        guard let base else { return }
        catalog = base.withSmallBodies(bundledSmallBodies + bodies)
    }

    /// The object with a stable identifier such as `"dso.M31"`, or `nil` while the catalog is not loaded.
    func object(id: String) -> CelestialObject? {
        catalog?.object(id: id)
    }

    /// The best matches for `query` (names, designations, constellations), at most `limit`; empty until loaded.
    func search(_ query: String, limit: Int) -> [CatalogSearchResult] {
        catalog?.search(query, limit: limit) ?? []
    }

    // MARK: Private

    private func performLoad() async {
        loadState = .loading
        do {
            let (loaded, asteroids) = try await Task.detached(priority: .userInitiated) {
                let loaded = try Catalog.loadBundled()
                // The bundled asteroids are a convenience: the catalog works without them.
                let asteroids = (try? BundledAsteroids.load().bodies) ?? []
                return (loaded, asteroids)
            }.value
            base = loaded
            bundledSmallBodies = asteroids
            // On the main actor, so a download that arrived during the load is included.
            catalog = loaded.withSmallBodies(asteroids + downloadedSmallBodies)
            loadState = .loaded
        } catch {
            loadState = .failed("The sky catalog could not be loaded. \(error.localizedDescription)")
        }
        loadTask = nil
    }
}
