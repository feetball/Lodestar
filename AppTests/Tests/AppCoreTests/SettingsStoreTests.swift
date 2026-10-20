import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `SettingsStore`: loading from and saving to a `UserDefaults` suite, and the convenience mutations.
@MainActor
final class SettingsStoreTests: XCTestCase {
    /// The key the store writes under. A change would orphan every user's saved settings.
    private let storageKey = "lodestar.settings.v1"

    /// A `UserDefaults` suite of its own, removed when the test ends.
    private func makeDefaults() throws -> UserDefaults {
        let name = "AppCoreTests.Settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func makeStore() throws -> (store: SettingsStore, defaults: UserDefaults) {
        let defaults = try makeDefaults()
        return (SettingsStore(defaults: defaults), defaults)
    }

    private func makeSite(_ name: String = "Site", id: UUID = UUID()) throws -> SavedSite {
        try XCTUnwrap(SavedSite(id: id, name: name, latitude: 40, longitude: 20, elevation: 100))
    }

    private func storedSettings(_ defaults: UserDefaults) throws -> AppSettings {
        let data = try XCTUnwrap(defaults.data(forKey: storageKey))
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    // MARK: Loading

    func testAStoreOverEmptyDefaultsHoldsTheDefaultSettings() throws {
        let (store, defaults) = try makeStore()
        XCTAssertEqual(store.settings, AppSettings())
        XCTAssertNil(defaults.data(forKey: storageKey))
    }

    func testAStoreLoadsWhatAnEarlierStoreSaved() throws {
        let (first, defaults) = try makeStore()
        first.settings.hapticsEnabled = false
        first.settings.focalLength = 200
        first.settings.favoriteObjectIDs = ["dso.M31"]
        first.saveNow()

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.settings, first.settings)
        XCTAssertFalse(second.settings.hapticsEnabled)
        XCTAssertEqual(second.settings.focalLength, 200)
        XCTAssertEqual(second.settings.favoriteObjectIDs, ["dso.M31"])
    }

    func testUnreadableStoredDataFallsBackToTheDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("this is not json".utf8), forKey: storageKey)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, AppSettings())
    }

    func testAStoredValueThatIsNotDataFallsBackToTheDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set("settings", forKey: storageKey)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, AppSettings())
    }

    func testStoredJSONOfTheWrongShapeFallsBackToTheDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("[1,2,3]".utf8), forKey: storageKey)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, AppSettings())
    }

    func testStoredPartialSettingsKeepTheirKnownValuesAndAreSanitized() throws {
        let defaults = try makeDefaults()
        defaults.set(Data(#"{"hapticsEnabled":false,"focalLength":99999}"#.utf8), forKey: storageKey)
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.settings.hapticsEnabled)
        XCTAssertEqual(store.settings.focalLength, 2000)
        XCTAssertEqual(store.settings.aperture, 2.8)
    }

    func testDefaultsOfAnotherSuiteAreNotRead() throws {
        let (first, _) = try makeStore()
        first.settings.audioCuesEnabled = true
        first.saveNow()
        let other = try makeDefaults()
        XCTAssertFalse(SettingsStore(defaults: other).settings.audioCuesEnabled)
    }

    // MARK: Saving

    func testSaveNowWritesTheSettingsAsJSONUnderTheVersionedKey() throws {
        let (store, defaults) = try makeStore()
        store.settings.nightMode = .on
        store.settings.coordinateStyle = .decimal
        store.saveNow()
        let stored = try storedSettings(defaults)
        XCTAssertEqual(stored, store.settings)
        XCTAssertEqual(stored.nightMode, .on)
        XCTAssertEqual(stored.coordinateStyle, .decimal)
    }

    func testAChangeIsNotWrittenUntilTheDebounceDelayHasPassed() throws {
        let (store, defaults) = try makeStore()
        store.settings.hapticsEnabled = false
        // The write is a task that sleeps first; this synchronous test never yields to it.
        XCTAssertNil(defaults.data(forKey: storageKey))
        store.saveNow()
        XCTAssertNotNil(defaults.data(forKey: storageKey))
    }

    func testAChangeIsSavedByItselfAfterTheDebounceDelay() async throws {
        let (store, defaults) = try makeStore()
        store.settings.keepScreenAwake = false
        for _ in 0..<100 {
            if defaults.data(forKey: storageKey) != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let stored = try storedSettings(defaults)
        XCTAssertFalse(stored.keepScreenAwake)
        XCTAssertEqual(stored, store.settings)
    }

    func testSavingNowAgainOverwritesTheEarlierSave() throws {
        let (store, defaults) = try makeStore()
        store.settings.focalLength = 50
        store.saveNow()
        store.settings.focalLength = 85
        store.saveNow()
        XCTAssertEqual(try storedSettings(defaults).focalLength, 85)
    }

    // MARK: Favorites

    func testTogglingAnObjectAddsAndThenRemovesItFromTheFavorites() throws {
        let (store, _) = try makeStore()
        store.toggleFavorite("dso.M31")
        store.toggleFavorite("planet.mars")
        XCTAssertEqual(store.settings.favoriteObjectIDs, ["dso.M31", "planet.mars"])
        store.toggleFavorite("dso.M31")
        XCTAssertEqual(store.settings.favoriteObjectIDs, ["planet.mars"])
        store.toggleFavorite("planet.mars")
        XCTAssertTrue(store.settings.favoriteObjectIDs.isEmpty)
    }

    func testNewFavoritesGoToTheEndOfTheList() throws {
        let (store, _) = try makeStore()
        for id in ["a", "b", "c"] { store.toggleFavorite(id) }
        XCTAssertEqual(store.settings.favoriteObjectIDs, ["a", "b", "c"])
    }

    func testAFavoriteIsNotAddedBeyondTheLimit() throws {
        let (store, _) = try makeStore()
        store.settings.favoriteObjectIDs = (0..<AppSettings.maximumFavorites).map { "obj\($0)" }
        store.toggleFavorite("one-too-many")
        XCTAssertEqual(store.settings.favoriteObjectIDs.count, 200)
        XCTAssertFalse(store.settings.favoriteObjectIDs.contains("one-too-many"))
    }

    func testAFavoriteCanBeRemovedFromAFullListAndThenReplaced() throws {
        let (store, _) = try makeStore()
        store.settings.favoriteObjectIDs = (0..<AppSettings.maximumFavorites).map { "obj\($0)" }
        store.toggleFavorite("obj5")
        XCTAssertEqual(store.settings.favoriteObjectIDs.count, 199)
        XCTAssertFalse(store.settings.favoriteObjectIDs.contains("obj5"))
        store.toggleFavorite("replacement")
        XCTAssertEqual(store.settings.favoriteObjectIDs.count, 200)
        XCTAssertEqual(store.settings.favoriteObjectIDs.last, "replacement")
    }

    // MARK: Recents

    func testARecentObjectGoesToTheFront() throws {
        let (store, _) = try makeStore()
        store.noteRecent("a")
        store.noteRecent("b")
        store.noteRecent("c")
        XCTAssertEqual(store.settings.recentObjectIDs, ["c", "b", "a"])
    }

    func testNotingARecentObjectAgainMovesItToTheFrontWithoutDuplicating() throws {
        let (store, _) = try makeStore()
        for id in ["a", "b", "c"] { store.noteRecent(id) }
        store.noteRecent("a")
        XCTAssertEqual(store.settings.recentObjectIDs, ["a", "c", "b"])
        store.noteRecent("a")
        XCTAssertEqual(store.settings.recentObjectIDs, ["a", "c", "b"])
    }

    func testRecentsAreCutToTheLimitDroppingTheOldest() throws {
        let (store, _) = try makeStore()
        for index in 0..<25 { store.noteRecent("obj\(index)") }
        XCTAssertEqual(store.settings.recentObjectIDs.count, AppSettings.maximumRecents)
        XCTAssertEqual(store.settings.recentObjectIDs.first, "obj24")
        XCTAssertEqual(store.settings.recentObjectIDs.last, "obj5")
        XCTAssertFalse(store.settings.recentObjectIDs.contains("obj4"))
    }

    func testReNotingAnObjectInAFullRecentsListDropsNothing() throws {
        let (store, _) = try makeStore()
        for index in 0..<20 { store.noteRecent("obj\(index)") }
        store.noteRecent("obj0")
        XCTAssertEqual(store.settings.recentObjectIDs.count, 20)
        XCTAssertEqual(store.settings.recentObjectIDs.first, "obj0")
        XCTAssertEqual(Set(store.settings.recentObjectIDs).count, 20)
    }

    // MARK: Sites

    func testAddingASiteAppendsItAndReportsSuccess() throws {
        let (store, _) = try makeStore()
        let first = try makeSite("First"), second = try makeSite("Second")
        XCTAssertTrue(store.addSite(first))
        XCTAssertTrue(store.addSite(second))
        XCTAssertEqual(store.settings.savedSites, [first, second])
    }

    func testASiteIsNotAddedBeyondTheLimit() throws {
        let (store, _) = try makeStore()
        for index in 0..<AppSettings.maximumSavedSites {
            XCTAssertTrue(store.addSite(try makeSite("Site \(index)")))
        }
        XCTAssertEqual(store.settings.savedSites.count, 100)
        XCTAssertFalse(store.addSite(try makeSite("One too many")))
        XCTAssertEqual(store.settings.savedSites.count, 100)
        XCTAssertFalse(store.settings.savedSites.contains { $0.name == "One too many" })
    }

    func testUpdatingASiteReplacesTheOneWithTheSameIdentifier() throws {
        let (store, _) = try makeStore()
        let id = UUID()
        store.addSite(try makeSite("Before", id: id))
        let other = try makeSite("Other")
        store.addSite(other)
        store.updateSite(try makeSite("After", id: id))
        XCTAssertEqual(store.settings.savedSites.map(\.name), ["After", "Other"])
        XCTAssertEqual(store.settings.savedSites.first?.id, id)
        XCTAssertEqual(store.settings.savedSites.last, other)
    }

    func testUpdatingAnUnknownSiteChangesNothing() throws {
        let (store, _) = try makeStore()
        let site = try makeSite("Kept")
        store.addSite(site)
        store.updateSite(try makeSite("Stranger"))
        XCTAssertEqual(store.settings.savedSites, [site])
    }

    func testRemovingSitesDeletesExactlyTheOnesNamed() throws {
        let (store, _) = try makeStore()
        let a = try makeSite("A"), b = try makeSite("B"), c = try makeSite("C")
        for site in [a, b, c] { store.addSite(site) }
        store.removeSites(withIDs: [a.id, c.id])
        XCTAssertEqual(store.settings.savedSites, [b])
    }

    func testRemovingNoSitesOrUnknownSitesChangesNothing() throws {
        let (store, _) = try makeStore()
        let a = try makeSite("A")
        store.addSite(a)
        store.removeSites(withIDs: [])
        store.removeSites(withIDs: [UUID()])
        XCTAssertEqual(store.settings.savedSites, [a])
    }

    func testRemovingTheActiveSiteSwitchesBackToTheDeviceLocation() throws {
        let (store, _) = try makeStore()
        let a = try makeSite("A"), b = try makeSite("B")
        store.addSite(a)
        store.addSite(b)
        store.settings.locationSource = .site(a.id)
        store.removeSites(withIDs: [a.id])
        XCTAssertEqual(store.settings.locationSource, .device)
        XCTAssertEqual(store.settings.savedSites, [b])
    }

    func testRemovingAnotherSiteKeepsTheActiveSite() throws {
        let (store, _) = try makeStore()
        let a = try makeSite("A"), b = try makeSite("B")
        store.addSite(a)
        store.addSite(b)
        store.settings.locationSource = .site(b.id)
        store.removeSites(withIDs: [a.id])
        XCTAssertEqual(store.settings.locationSource, .site(b.id))
    }

    func testRemovingEverySiteLeavesTheDeviceLocation() throws {
        let (store, _) = try makeStore()
        let a = try makeSite("A")
        store.addSite(a)
        store.settings.locationSource = .site(a.id)
        store.removeSites(withIDs: [a.id])
        XCTAssertTrue(store.settings.savedSites.isEmpty)
        XCTAssertEqual(store.settings.locationSource, .device)
    }

    func testSitesAndTheActiveSiteSurviveASaveAndReload() throws {
        let (store, defaults) = try makeStore()
        let a = try makeSite("A")
        store.addSite(a)
        store.settings.locationSource = .site(a.id)
        store.saveNow()
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.savedSites, [a])
        XCTAssertEqual(reloaded.settings.locationSource, .site(a.id))
    }
}
