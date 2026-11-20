import Foundation
import LodestarKit

/// What the app lends to its App Intents: the running app model (an intent that runs while the app is alive reads it),
/// the commands that reach it, and the place "tonight" is worked out for. Set once in `LodestarApp`.
@MainActor
enum LodestarIntentHost {
    /// Objects the picker offers before anything is typed, after the favourites and recents: the Moon, the bright planets
    /// and a few showpieces. One that the catalog does not have is left out.
    static let suggestedObjectIDs = [
        "moon", "planet.venus", "planet.mars", "planet.jupiter", "planet.saturn",
        "dso.M31", "dso.M42", "dso.M45", "dso.M13", "dso.M8",
    ]

    /// The most objects a search returns.
    static let searchLimit = 20

    private(set) static weak var model: AppModel?

    /// Connects the app model: commands from intents are carried out by it, and its catalog answers the entity queries.
    static func attach(_ model: AppModel) {
        self.model = model
        LodestarCommandCenter.shared.attach { [weak model] command in
            model?.perform(command)
        }
    }

    /// The objects with these identifiers, once the catalog is loaded; unknown identifiers are skipped.
    static func objects(withIDs ids: [String]) async -> [CelestialObjectEntity] {
        guard let catalog = await loadedCatalog() else { return [] }
        return ids.compactMap { catalog.object(id: $0) }.map(CelestialObjectEntity.init)
    }

    /// The objects the picker offers first: the favourites, the recents, then the suggestions, without repeats.
    static func suggestions() async -> [CelestialObjectEntity] {
        guard let model, let catalog = await loadedCatalog() else { return [] }
        let settings = model.settings
        var seen = Set<String>()
        let ids = (settings.favoriteObjectIDs + settings.recentObjectIDs + suggestedObjectIDs).filter { seen.insert($0).inserted }
        return ids.compactMap { catalog.object(id: $0) }.prefix(searchLimit).map(CelestialObjectEntity.init)
    }

    /// The objects whose names or designations match `query`, best first.
    static func objects(matching query: String) async -> [CelestialObjectEntity] {
        guard let catalog = await loadedCatalog() else { return [] }
        return catalog.search(query, limit: searchLimit).map { CelestialObjectEntity($0.object) }
    }

    /// Where "tonight" is worked out: the observer the app uses now (the Tonight tab's), else the one it remembered the
    /// last time it ran. The widgets measure their own place in their own process and keep it in their own defaults (there
    /// is no App Group), so the app cannot read it.
    static func tonightPlace() -> TonightPlace? {
        if let context = model?.observerContext, let place = TonightPlace(observer: context) { return place }
        return TonightPlaceStore.load(.phone)
    }

    /// Remembers the observer for a time when the app is not running (an intent starts the process without the UI).
    /// It uses the store's `phone` slot, the one the iPhone app's own observer goes to.
    static func remember(_ context: ObserverContext?) {
        guard let context, let place = TonightPlace(observer: context) else { return }
        TonightPlaceStore.save(place, as: .phone)
    }

    private static func loadedCatalog() async -> Catalog? {
        guard let model else { return nil }
        await model.catalog.load()
        return model.catalog.catalog
    }
}

extension TonightPlace {
    /// The place of an observer: its coordinates and the time zone its clocks follow (the device's, for the device's own
    /// location).
    init?(observer context: ObserverContext) {
        let location = context.location
        let zone: String
        if case .device = context.source {
            zone = TimeZone.current.identifier
        } else {
            zone = context.timeZone.identifier
        }
        self.init(latitude: location.latitude, longitude: location.longitude, elevation: location.elevation,
                  timeZoneIdentifier: zone)
    }
}
