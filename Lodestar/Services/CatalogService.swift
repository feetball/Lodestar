import Foundation
import LodestarKit
import Observation

/// Loads the bundled sky catalog and answers lookups and searches.
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
    private(set) var catalog: Catalog?

    @ObservationIgnored private var loadTask: Task<Void, Never>?

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
            let loaded = try await Task.detached(priority: .userInitiated) { try Catalog.loadBundled() }.value
            catalog = loaded
            loadState = .loaded
        } catch {
            loadState = .failed("The sky catalog could not be loaded. \(error.localizedDescription)")
        }
        loadTask = nil
    }
}
