import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The lists of bright comets and asteroids (`SmallBodyBrightLists`), the favourites whose orbit is gone
/// (`SmallBodyFavorites`), the planner behind the Tonight screen (`SmallBodyTonightPlanner`) and the markers a sky view
/// draws (`SmallBodySkyMarkers`, `SmallBodyMarkerStyle`).
///
/// The catalog is the bundled sky with the comets of the review fixtures and the asteroids Ceres and Vesta added: real MPC
/// orbit lines of 2026-10-18. On 2026-10-18T12:00:00Z the only comet brighter than magnitude 10 is 161P/Hartley-IRAS (9.7),
/// and Vesta, at opposition, leads the asteroids (6.4).
final class TonightSmallBodyListsTests: XCTestCase {
    private static let fixtureCatalog = Result {
        try Catalog.loadBundled().withSmallBodies(TonightSmallBodyListsTests.fixtureBodies())
    }
    private static let bundledCatalog = Result { try Catalog.loadBundled() }

    /// 2026-10-18T12:00:00Z.
    private let noon = Date(timeIntervalSince1970: 1_792_324_800)
    /// 2026-10-19T02:00:00Z, an evening in Colorado.
    private let evening = Date(timeIntervalSince1970: 1_792_375_200)
    private let boulder = Observer(location: GeographicLocation(latitude: 40.0, longitude: -105.27, elevation: 1650))
    private let tromso = Observer(location: GeographicLocation(latitude: 69.65, longitude: 18.96, elevation: 0))

    private func loadedCatalog() throws -> Catalog { try Self.fixtureCatalog.get() }

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier), identifier)
    }

    private func nightSummary(_ observer: Observer, _ identifier: String, _ year: Int, _ month: Int, _ day: Int) throws
        -> NightSummary {
        let timeZone = try zone(identifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        return NightPlanner.summary(nightStartingOn: noon, observer: observer, timeZone: timeZone)
    }

    // MARK: Choices

    func testThePeriodsOfAList() {
        XCTAssertEqual(SmallBodyListPeriod.allCases, [.now, .thisMonth])
        XCTAssertEqual(SmallBodyListPeriod.allCases.map(\.id), ["now", "thisMonth"])
        XCTAssertEqual(SmallBodyListPeriod.allCases.map(\.title), ["Now", "This month"])
    }

    func testTheKindsOfBodyAListShows() {
        XCTAssertEqual(SmallBodyListKind.allCases, [.comets, .asteroids, .both])
        XCTAssertEqual(SmallBodyListKind.allCases.map(\.id), ["comets", "asteroids", "both"])
        XCTAssertEqual(SmallBodyListKind.allCases.map(\.title), ["Comets", "Asteroids", "Both"])
        XCTAssertEqual(SmallBodyListKind.comets.kind, .comet)
        XCTAssertEqual(SmallBodyListKind.asteroids.kind, .asteroid)
        XCTAssertNil(SmallBodyListKind.both.kind)
        XCTAssertEqual(SmallBodyListKind.allCases.map(\.noun), ["comet", "asteroid", "comet or asteroid"])
    }

    func testTheMagnitudeLimitsAListOffers() {
        XCTAssertEqual(SmallBodyMagnitudeLimit.allCases, [.nakedEye, .binoculars, .camera])
        XCTAssertEqual(SmallBodyMagnitudeLimit.allCases.map(\.value), [6, 8, 10])
        XCTAssertEqual(SmallBodyMagnitudeLimit.allCases.map(\.id), [6, 8, 10])
        XCTAssertEqual(SmallBodyMagnitudeLimit.allCases.map(\.title), ["Mag 6", "Mag 8", "Mag 10"])
        XCTAssertEqual(SmallBodyMagnitudeLimit.allCases.map(\.caption), [
            "Naked-eye brightness", "Binoculars or a wide-field camera", "A camera on a tripod",
        ])
        XCTAssertEqual(SmallBodyMagnitudeLimit.default, .camera)
        XCTAssertEqual(SmallBodyMagnitudeLimit.default.value, 10)
    }

    func testTheSizesOfAList() {
        XCTAssertEqual(SmallBodyBrightLists.monthDays, 31)
        XCTAssertEqual(SmallBodyBrightLists.maximumCount, 50)
    }

    // MARK: The empty state

    func testTheEmptyMessageOfCometsRightNow() {
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .now, limit: 10, kind: .comets),
                       "No comet is brighter than magnitude 10 right now. That is normal; bright comets are rare.")
    }

    func testTheEmptyMessageOfThisMonthNamesTheDays() {
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .thisMonth, limit: 8, kind: .comets),
                       "No comet is brighter than magnitude 8 in the next 31 days. That is normal; bright comets are rare.")
    }

    func testTheEmptyMessageOfAsteroidsDoesNotSayBrightCometsAreRare() {
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .now, limit: 6, kind: .asteroids),
                       "No asteroid is brighter than magnitude 6 right now.")
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .thisMonth, limit: 6, kind: .asteroids),
                       "No asteroid is brighter than magnitude 6 in the next 31 days.")
    }

    func testTheEmptyMessageOfBothNamesBoth() {
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .now, limit: 10, kind: .both),
                       "No comet or asteroid is brighter than magnitude 10 right now. That is normal; bright comets are rare.")
    }

    // MARK: The bodies of a catalog

    func testTheBodiesOfACatalogAreItsCometsAndAsteroids() throws {
        let bodies = SmallBodyBrightLists.bodies(in: try loadedCatalog())
        XCTAssertEqual(bodies.count, 16)
        XCTAssertEqual(Set(bodies.map(\.id)).count, 16)
        XCTAssertEqual(bodies.filter { $0.kind == .asteroid }.map(\.id).sorted(), ["asteroid.1", "asteroid.4"])
        XCTAssertTrue(bodies.contains { $0.id == "comet.161P" })
    }

    func testACatalogWithoutSmallBodiesHasNoBodies() throws {
        XCTAssertTrue(SmallBodyBrightLists.bodies(in: try Self.bundledCatalog.get()).isEmpty)
    }

    // MARK: Selecting

    func testTheCometsBrighterThanMagnitudeTenRightNow() throws {
        let bodies = SmallBodyBrightLists.bodies(in: try loadedCatalog())
        let found = SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: 10, kind: .comets)
        XCTAssertEqual(found.map(\.body.id), ["comet.161P"])
        XCTAssertEqual(found[0].peakMagnitude, 9.72, accuracy: 0.05)
        XCTAssertEqual(found[0].peak.elongation, 110.3, accuracy: 0.5)
        XCTAssertEqual(found[0].peakDate.timeIntervalSince1970, noon.timeIntervalSince1970, accuracy: 1)
    }

    func testAHigherLimitAddsFainterCometsBrightestFirst() throws {
        let bodies = SmallBodyBrightLists.bodies(in: try loadedCatalog())
        let found = SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: 14, kind: .comets)
        XCTAssertEqual(found.map(\.body.id), ["comet.161P", "comet.P/2026 R2", "comet.78P"])
        XCTAssertEqual(found.map(\.peakMagnitude), found.map(\.peakMagnitude).sorted())
    }

    func testTheKindFiltersTheList() throws {
        let bodies = SmallBodyBrightLists.bodies(in: try loadedCatalog())
        let asteroids = SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: 10, kind: .asteroids)
        XCTAssertEqual(asteroids.first?.body.id, "asteroid.4")
        XCTAssertTrue(asteroids.allSatisfy { $0.body.kind == .asteroid })
        let both = SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: 10, kind: .both)
        XCTAssertEqual(both.first?.body.id, "asteroid.4")
        XCTAssertTrue(both.contains { $0.body.id == "comet.161P" })
        XCTAssertEqual(both.map(\.peakMagnitude), both.map(\.peakMagnitude).sorted())
    }

    func testAnArrayOfBodiesSelectedAtMagnitudeEightLeavesOutTheComet() throws {
        let bodies = SmallBodyBrightLists.bodies(in: try loadedCatalog())
        let found = SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: 8, kind: .both)
        XCTAssertTrue(found.contains { $0.body.id == "asteroid.4" })
        XCTAssertFalse(found.contains { $0.body.id == "comet.161P" })
        XCTAssertTrue(found.allSatisfy { $0.peakMagnitude <= 8 })
    }

    func testTheNumberOfRowsCanBeCapped() throws {
        let bodies = SmallBodyBrightLists.bodies(in: try loadedCatalog())
        let capped = SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: 14, kind: .comets,
                                                 maximumCount: 2)
        XCTAssertEqual(capped.map(\.body.id), ["comet.161P", "comet.P/2026 R2"])
        XCTAssertTrue(SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: 14, kind: .comets,
                                                  maximumCount: 0).isEmpty)
    }

    func testNothingIsBrighterThanAVeryLowLimit() throws {
        let bodies = SmallBodyBrightLists.bodies(in: try loadedCatalog())
        XCTAssertTrue(SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: -5, kind: .both).isEmpty)
    }

    func testThisMonthFindsEachBodyAtItsBrightestWithinThirtyOneDays() throws {
        let bodies = SmallBodyBrightLists.bodies(in: try loadedCatalog())
        let month = SmallBodyBrightLists.select(bodies, at: noon, period: .thisMonth, limit: 10, kind: .both)
        let monthEnd = noon.addingTimeInterval(31 * 86_400)
        XCTAssertEqual(month.first?.body.id, "asteroid.4")
        XCTAssertLessThan(try XCTUnwrap(month.first).peakMagnitude, 6.6)
        XCTAssertTrue(month.allSatisfy { $0.peakMagnitude <= 10 })
        XCTAssertTrue(month.allSatisfy { $0.peakDate >= noon.addingTimeInterval(-1) && $0.peakDate <= monthEnd.addingTimeInterval(1) })
        XCTAssertEqual(month.map(\.peakMagnitude), month.map(\.peakMagnitude).sorted())
        let now = SmallBodyBrightLists.select(bodies, at: noon, period: .now, limit: 10, kind: .both)
        let comet = try XCTUnwrap(month.first { $0.body.id == "comet.161P" })
        let cometNow = try XCTUnwrap(now.first { $0.body.id == "comet.161P" })
        XCTAssertLessThanOrEqual(comet.peakMagnitude, cometNow.peakMagnitude + 1e-9)
    }

    // MARK: Entries

    func testAnEntryPairsTheBodyWithItsCatalogObjectAndItsStateAtThePeak() throws {
        let entries = SmallBodyBrightLists.entries(in: try loadedCatalog(), at: noon, period: .now, limit: 10, kind: .comets)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, "comet.161P")
        XCTAssertEqual(entry.object.id, "comet.161P")
        XCTAssertEqual(entry.object.smallBody, entry.bright.body)
        XCTAssertEqual(entry.peakDate, entry.bright.peakDate)
        XCTAssertEqual(try XCTUnwrap(entry.info.magnitude), entry.bright.peakMagnitude, accuracy: 1e-12)
        XCTAssertEqual(entry.info.elongation, entry.bright.peak.elongation, accuracy: 1e-12)
        XCTAssertEqual(entry.info.body, entry.bright.body)
    }

    func testEntriesKeepTheOrderOfTheSelection() throws {
        let catalog = try loadedCatalog()
        let entries = SmallBodyBrightLists.entries(in: catalog, at: noon, period: .now, limit: 14, kind: .comets)
        XCTAssertEqual(entries.map(\.id), ["comet.161P", "comet.P/2026 R2", "comet.78P"])
        let selected = SmallBodyBrightLists.select(SmallBodyBrightLists.bodies(in: catalog), at: noon, period: .now,
                                                   limit: 14, kind: .comets)
        XCTAssertEqual(entries.map(\.peakDate), selected.map(\.peakDate))
    }

    func testAnEntryAtThePeakOfTheMonthHasThePeakDate() throws {
        let entries = SmallBodyBrightLists.entries(in: try loadedCatalog(), at: noon, period: .thisMonth, limit: 10,
                                                   kind: .comets)
        let entry = try XCTUnwrap(entries.first { $0.id == "comet.161P" })
        XCTAssertGreaterThanOrEqual(entry.peakDate, noon.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(entry.peakDate, noon.addingTimeInterval(31 * 86_400 + 1))
        XCTAssertEqual(try XCTUnwrap(entry.info.magnitude), entry.bright.peakMagnitude, accuracy: 1e-12)
    }

    // MARK: Favourites whose orbit is gone

    func testFavouritesWithoutAnOrbitAreTheSmallBodiesTheCatalogLacks() throws {
        let favourites = ["comet.12P", "dso.M31", "asteroid.4", "comet.C/2023 A3", "star.hip32349", "asteroid.2024 YR4"]
        let gone = SmallBodyFavorites.withoutOrbit(favoriteIDs: favourites, catalog: try loadedCatalog())
        // 12P and C/2023 A3 are in the fixture catalog; so is Vesta. Only the asteroid 2024 YR4 is missing.
        XCTAssertEqual(gone, ["asteroid.2024 YR4"])
    }

    func testFavouritesWithoutAnOrbitKeepTheirOrderAndLoseRepeats() throws {
        let favourites = ["comet.C/2022 E3", "dso.M31", "comet.C/2019 Y4", "comet.C/2022 E3", "asteroid.99999", "comet.C/2019 Y4"]
        let gone = SmallBodyFavorites.withoutOrbit(favoriteIDs: favourites, catalog: try loadedCatalog())
        XCTAssertEqual(gone, ["comet.C/2022 E3", "comet.C/2019 Y4", "asteroid.99999"])
    }

    func testNoFavouritesMeansNoneWithoutAnOrbit() throws {
        XCTAssertEqual(SmallBodyFavorites.withoutOrbit(favoriteIDs: [], catalog: try loadedCatalog()), [])
    }

    func testOtherObjectsAreNeverReportedAsLackingAnOrbit() throws {
        let gone = SmallBodyFavorites.withoutOrbit(favoriteIDs: ["dso.NOTHING", "star.hip1", "custom.abc", "planet.mars"],
                                                   catalog: try loadedCatalog())
        XCTAssertEqual(gone, [])
    }

    func testTheNameOfAFavouriteWithoutAnOrbitIsItsDesignation() {
        XCTAssertEqual(SmallBodyFavorites.name(ofID: "comet.C/2023 A3"), "C/2023 A3")
        XCTAssertEqual(SmallBodyFavorites.name(ofID: "comet.12P"), "12P")
        XCTAssertEqual(SmallBodyFavorites.name(ofID: "asteroid.2024 YR4"), "2024 YR4")
    }

    func testTheCategoryOfAFavouriteWithoutAnOrbit() {
        XCTAssertEqual(SmallBodyFavorites.category(ofID: "comet.12P"), .comet)
        XCTAssertEqual(SmallBodyFavorites.category(ofID: "asteroid.4"), .asteroid)
    }

    func testTheSubtitleAndTheSpokenTextOfAFavouriteWithoutAnOrbit() {
        XCTAssertEqual(SmallBodyFavorites.subtitle(ofID: "comet.12P"), "Comet \u{00B7} no current orbit")
        XCTAssertEqual(SmallBodyFavorites.subtitle(ofID: "asteroid.2024 YR4"), "Asteroid \u{00B7} no current orbit")
        XCTAssertEqual(SmallBodyFavorites.spoken(ofID: "comet.12P"), "12P, Comet, no current orbit, Favorite")
        XCTAssertEqual(SmallBodyFavorites.spoken(ofID: "asteroid.2024 YR4"),
                       "2024 YR4, Asteroid, no current orbit, Favorite")
    }

    // MARK: The planner behind the Tonight screen

    func testThePlannersLimits() {
        XCTAssertEqual(SmallBodyTonightPlanner.cardCount, 3)
        XCTAssertEqual(SmallBodyTonightPlanner.cardMagnitudeLimit, 10)
        XCTAssertEqual(SmallBodyTonightPlanner.targetCount, 3)
        XCTAssertEqual(SmallBodyTonightPlanner.targetMagnitudeLimit, 8)
        XCTAssertEqual(SmallBodyTonightPlanner.minimumHours, 1)
        XCTAssertTrue(SmallBodyTonight.none.bright.isEmpty)
        XCTAssertTrue(SmallBodyTonight.none.targets.isEmpty)
    }

    func testACatalogWithoutSmallBodiesPlansNothing() throws {
        let summary = try nightSummary(boulder, "America/Denver", 2026, 10, 18)
        let plan = SmallBodyTonightPlanner.plan(catalog: try Self.bundledCatalog.get(), summary: summary, skyline: nil)
        XCTAssertTrue(plan.bright.isEmpty)
        XCTAssertTrue(plan.targets.isEmpty)
    }

    func testTheCardHoldsTheBrightCometsOfTheNight() throws {
        let summary = try nightSummary(boulder, "America/Denver", 2026, 10, 18)
        let plan = SmallBodyTonightPlanner.plan(catalog: try loadedCatalog(), summary: summary, skyline: nil)
        XCTAssertEqual(plan.bright.map(\.id), ["comet.161P"])
        XCTAssertLessThanOrEqual(plan.bright.count, SmallBodyTonightPlanner.cardCount)
        XCTAssertTrue(plan.bright.allSatisfy { $0.object.category == .comet })
        XCTAssertEqual(try XCTUnwrap(plan.bright.first?.info.magnitude), 9.7, accuracy: 0.15)
    }

    func testABrightAsteroidIsATargetOnTheNightOfItsOpposition() throws {
        let summary = try nightSummary(boulder, "America/Denver", 2026, 10, 18)
        let plan = SmallBodyTonightPlanner.plan(catalog: try loadedCatalog(), summary: summary, skyline: nil)
        let first = try XCTUnwrap(plan.targets.first)
        XCTAssertEqual(first.object.id, "asteroid.4")
        XCTAssertLessThanOrEqual(plan.targets.count, SmallBodyTonightPlanner.targetCount)
        // The comet is fainter than the targets' limit of magnitude 8.
        XCTAssertFalse(plan.targets.contains { $0.object.id == "comet.161P" })
    }

    func testEveryTargetIsHighLongEnoughAndDescribedByANote() throws {
        let summary = try nightSummary(boulder, "America/Denver", 2026, 10, 18)
        let plan = SmallBodyTonightPlanner.plan(catalog: try loadedCatalog(), summary: summary, skyline: nil)
        let dark = summary.astronomicalDarknessIntervals
        XCTAssertFalse(plan.targets.isEmpty)
        for target in plan.targets {
            let label = target.object.id
            XCTAssertGreaterThanOrEqual(target.peakAltitude, TonightCalculator.minimumTargetAltitude, label)
            XCTAssertGreaterThanOrEqual(target.hoursAboveMinimum, SmallBodyTonightPlanner.minimumHours, label)
            XCTAssertTrue(dark.contains { $0.start <= target.peakTime && target.peakTime <= $0.end }, label)
            XCTAssertNotNil(target.object.smallBody, label)
            let note = target.note ?? ""
            XCTAssertTrue(note.hasPrefix(target.object.category.displayName), note)
            XCTAssertTrue(note.hasSuffix("from\u{00A0}the\u{00A0}Sun"), note)
        }
    }

    func testAMildSkylineLeavesTheTargetsAlone() throws {
        let summary = try nightSummary(boulder, "America/Denver", 2026, 10, 18)
        let open = SmallBodyTonightPlanner.plan(catalog: try loadedCatalog(), summary: summary, skyline: nil)
        let low = SmallBodyTonightPlanner.plan(catalog: try loadedCatalog(), summary: summary,
                                               skyline: HorizonProfile.constant(10))
        // A skyline below the 20 degree minimum changes nothing for the brightest target, nor for the card.
        XCTAssertEqual(open.targets.first?.object.id, "asteroid.4")
        XCTAssertEqual(low.targets.first?.object.id, "asteroid.4")
        XCTAssertEqual(low.bright.map(\.id), open.bright.map(\.id))
    }

    func testATargetOverASkylineIsHighEnoughToClearIt() throws {
        let summary = try nightSummary(boulder, "America/Denver", 2026, 10, 18)
        let plan = SmallBodyTonightPlanner.plan(catalog: try loadedCatalog(), summary: summary,
                                                skyline: HorizonProfile.constant(60))
        for target in plan.targets {
            XCTAssertGreaterThanOrEqual(target.peakAltitude, 59.9, target.object.id)
        }
    }

    func testWithoutAstronomicalDarknessThereAreNoTargetsButTheCardStillHasItsComets() throws {
        // Tromsø at the midsummer: the Sun never gets 18 degrees below the horizon.
        let summary = try nightSummary(tromso, "Europe/Oslo", 2026, 6, 21)
        XCTAssertFalse(summary.hasAstronomicalDarkness)
        let plan = SmallBodyTonightPlanner.plan(catalog: try loadedCatalog(), summary: summary, skyline: nil)
        XCTAssertTrue(plan.targets.isEmpty)
        XCTAssertLessThanOrEqual(plan.bright.count, SmallBodyTonightPlanner.cardCount)
        XCTAssertTrue(plan.bright.allSatisfy { $0.object.category == .comet })
    }

    // MARK: Markers on a sky view

    private func syntheticComets(_ count: Int) throws -> [CelestialObject] {
        let orbit = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: 1, eccentricity: 0.5, inclination: 20,
                                                    argumentOfPerihelion: 30, longitudeOfAscendingNode: 40,
                                                    perihelionJulianDayTT: 2_461_000, epochJulianDayTT: 2_461_200.5))
        let magnitudes = try XCTUnwrap(CometMagnitudes(totalMagnitude: 0, totalSlope: 10))
        return try (0..<count).map { index -> CelestialObject in
            let body = try XCTUnwrap(SmallBody(designation: "C/2030 X\(index)", name: "", kind: .comet, number: nil,
                                               orbit: orbit, photometry: .comet(magnitudes)))
            return CelestialObject(smallBody: body)
        }
    }

    private func markerFrame() -> SkyFrame { SkyFrame(date: evening, observer: boulder) }

    func testMarkersAreTheBodiesBrighterThanTheLimitBrightestFirst() throws {
        let objects = try loadedCatalog().smallBodies
        XCTAssertEqual(objects.count, 16)
        let markers = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: nil,
                                                magnitudeLimit: 8)
        XCTAssertTrue(markers.contains { $0.object.id == "asteroid.4" })
        XCTAssertFalse(markers.contains { $0.object.id == "comet.161P" }, "magnitude 9.7 is fainter than the limit")
        XCTAssertTrue(markers.allSatisfy { ($0.magnitude ?? .infinity) <= 8 })
        let magnitudes = markers.map { $0.magnitude ?? .infinity }
        XCTAssertEqual(magnitudes, magnitudes.sorted())
    }

    func testAHigherLimitDrawsMoreBodies() throws {
        let objects = try loadedCatalog().smallBodies
        let few = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: nil, magnitudeLimit: 8)
        let more = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: nil, magnitudeLimit: 10)
        XCTAssertGreaterThan(more.count, few.count)
        XCTAssertTrue(more.contains { $0.object.id == "comet.161P" })
        XCTAssertEqual(SmallBodySkyMarkers.defaultMagnitudeLimit, 9)
        XCTAssertEqual(SmallBodySkyMarkers.maximumCount, 80)
    }

    func testTheTargetIsAlwaysDrawnAndComesFirstWhateverItsBrightness() throws {
        let objects = try loadedCatalog().smallBodies
        let target = try XCTUnwrap(objects.first { $0.id == "comet.161P" })
        let markers = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: target,
                                                magnitudeLimit: 8)
        XCTAssertEqual(markers.first?.object.id, "comet.161P")
        XCTAssertEqual(markers.filter { $0.object.id == "comet.161P" }.count, 1, "the target is not drawn twice")
        XCTAssertEqual(markers.first.flatMap { $0.magnitude }.map { $0 > 8 }, true)
        XCTAssertTrue(markers.contains { $0.object.id == "asteroid.4" })
    }

    func testATargetThatIsNotInTheListIsAddedFirst() throws {
        let objects = try loadedCatalog().smallBodies.filter { $0.id != "comet.161P" }
        let target = try XCTUnwrap(try loadedCatalog().smallBodies.first { $0.id == "comet.161P" })
        let markers = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: target,
                                                magnitudeLimit: 8)
        XCTAssertEqual(markers.first?.object.id, "comet.161P")
        XCTAssertEqual(markers.filter { $0.object.id == "comet.161P" }.count, 1)
    }

    func testWithoutAnythingToDrawThereAreNoMarkers() throws {
        let frame = markerFrame()
        XCTAssertTrue(SmallBodySkyMarkers.build(smallBodies: [], frame: frame, target: nil, magnitudeLimit: 20).isEmpty)
        // A target that is not a comet or an asteroid is not a small body to draw.
        let custom = CelestialObject.custom(name: "Spot", j2000: EquatorialCoordinate(rightAscension: 10, declination: 20))
        XCTAssertTrue(SmallBodySkyMarkers.build(smallBodies: [], frame: frame, target: custom, magnitudeLimit: 20).isEmpty)
    }

    func testATargetAloneIsDrawnEvenWithoutAList() throws {
        let target = try XCTUnwrap(try loadedCatalog().smallBodies.first { $0.id == "asteroid.4" })
        let markers = SmallBodySkyMarkers.build(smallBodies: [], frame: markerFrame(), target: target, magnitudeLimit: 1)
        XCTAssertEqual(markers.map(\.object.id), ["asteroid.4"])
    }

    func testAnotherKindOfTargetDoesNotChangeTheMarkers() throws {
        let objects = try loadedCatalog().smallBodies
        let custom = CelestialObject.custom(name: "Spot", j2000: EquatorialCoordinate(rightAscension: 10, declination: 20))
        let plain = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: nil, magnitudeLimit: 10)
        let withTarget = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: custom,
                                                   magnitudeLimit: 10)
        XCTAssertEqual(withTarget.map(\.object.id), plain.map(\.object.id))
    }

    func testABodyWithoutMagnitudeParametersIsDrawnOnlyAsTheTarget() throws {
        let line = "J91T00T 99.99  0.15 K2669 176.22907  218.04073  192.31551   14.79902  0.1614954  0.75483638   1.1946321  7 E2026-TC5     6   1    3 days 0.86 M-v 3Ek Pan        2804          1991 TT            19911009"
        let object = CelestialObject(smallBody: try MinorPlanetElementsParser.parseLine(line))
        let frame = markerFrame()
        XCTAssertTrue(SmallBodySkyMarkers.build(smallBodies: [object], frame: frame, target: nil,
                                                magnitudeLimit: 99).isEmpty)
        let asTarget = SmallBodySkyMarkers.build(smallBodies: [object], frame: frame, target: object, magnitudeLimit: 5)
        XCTAssertEqual(asTarget.count, 1)
        XCTAssertNil(asTarget[0].magnitude)
    }

    func testACometMarkerHasATailAndAnAsteroidMarkerDoesNot() throws {
        let objects = try loadedCatalog().smallBodies
        let markers = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: nil, magnitudeLimit: 12)
        let comet = try XCTUnwrap(markers.first { $0.object.id == "comet.161P" })
        let asteroid = try XCTUnwrap(markers.first { $0.object.id == "asteroid.4" })
        XCTAssertTrue(comet.isComet)
        XCTAssertFalse(asteroid.isComet)
        let tail = try XCTUnwrap(comet.tailEnd)
        XCTAssertNil(asteroid.tailEnd)
        // The tail end is one degree from the body on the sky.
        XCTAssertEqual(tail.length, 1, accuracy: 1e-9)
        XCTAssertEqual(comet.direction.angle(to: tail), 1, accuracy: 1e-6)
    }

    func testAMarkerCarriesTheRefractedDirectionOfTheBody() throws {
        let objects = try loadedCatalog().smallBodies
        let frame = markerFrame()
        let marker = try XCTUnwrap(SmallBodySkyMarkers.build(smallBodies: objects, frame: frame, target: nil,
                                                             magnitudeLimit: 8).first { $0.object.id == "asteroid.4" })
        let body = try XCTUnwrap(marker.object.smallBody)
        let state = try XCTUnwrap(frame.state(of: body))
        let expected = frame.horizontal(geocentricJ2000: state.geocentricJ2000, refraction: true)
        XCTAssertEqual(marker.horizontal, expected)
        XCTAssertEqual(marker.direction, expected.unitVector)
        XCTAssertEqual(marker.magnitude, state.apparentMagnitude)
        XCTAssertEqual(marker.id, "asteroid.4")
    }

    func testNoMoreMarkersThanTheMaximumAreKeptAndTiesAreBrokenByIdentifier() throws {
        let objects = try syntheticComets(100)
        let markers = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: nil,
                                                magnitudeLimit: 9)
        XCTAssertEqual(markers.count, SmallBodySkyMarkers.maximumCount)
        // All the comets have the same orbit, so the same magnitude: the identifiers decide.
        let expected = Array(objects.map(\.id).sorted().prefix(SmallBodySkyMarkers.maximumCount))
        XCTAssertEqual(markers.map(\.object.id), expected)
    }

    func testTheTargetSurvivesTheCapOnTheNumberOfMarkers() throws {
        let objects = try syntheticComets(100)
        let target = try XCTUnwrap(objects.last)
        let markers = SmallBodySkyMarkers.build(smallBodies: objects, frame: markerFrame(), target: target,
                                                magnitudeLimit: 9)
        XCTAssertEqual(markers.count, SmallBodySkyMarkers.maximumCount)
        XCTAssertEqual(markers.first?.object.id, target.id)
    }

    // MARK: The end of a comet's tail

    private let east = Vector3(1, 0, 0)

    func testATailPointingStraightUpEndsOneDegreeHigher() throws {
        let end = try XCTUnwrap(SmallBodySkyMarkers.tailEnd(from: east, angleFromVertical: 0))
        let place = HorizontalCoordinate(vector: end)
        XCTAssertEqual(place.altitude, 1, accuracy: 1e-9)
        XCTAssertEqual(place.azimuth, 90, accuracy: 1e-9)
        XCTAssertEqual(end.length, 1, accuracy: 1e-12)
    }

    func testATailPointingStraightDownEndsOneDegreeLower() throws {
        let place = HorizontalCoordinate(vector: try XCTUnwrap(SmallBodySkyMarkers.tailEnd(from: east, angleFromVertical: 180)))
        XCTAssertEqual(place.altitude, -1, accuracy: 1e-9)
        XCTAssertEqual(place.azimuth, 90, accuracy: 1e-9)
    }

    func testAPositiveAngleLeansToTheObserversRightWhenFacingTheBody() throws {
        // Facing east, the observer's right hand is south, so the azimuth grows.
        let right = HorizontalCoordinate(vector: try XCTUnwrap(SmallBodySkyMarkers.tailEnd(from: east, angleFromVertical: 90)))
        XCTAssertEqual(right.altitude, 0, accuracy: 1e-9)
        XCTAssertEqual(right.azimuth, 91, accuracy: 1e-9)
        let left = HorizontalCoordinate(vector: try XCTUnwrap(SmallBodySkyMarkers.tailEnd(from: east, angleFromVertical: -90)))
        XCTAssertEqual(left.azimuth, 89, accuracy: 1e-9)
        // Facing north, the right hand is east.
        let north = Vector3(0, 1, 0)
        let facingNorth = HorizontalCoordinate(vector: try XCTUnwrap(SmallBodySkyMarkers.tailEnd(from: north, angleFromVertical: 90)))
        XCTAssertEqual(facingNorth.azimuth, 1, accuracy: 1e-9)
    }

    func testAtTheZenithUpHasNoDirection() {
        XCTAssertNil(SmallBodySkyMarkers.tailEnd(from: Vector3(0, 0, 1), angleFromVertical: 0))
        XCTAssertNil(SmallBodySkyMarkers.tailEnd(from: Vector3(0, 0, -1), angleFromVertical: 45))
    }

    func testNearTheZenithUpStillHasADirection() throws {
        let nearZenith = HorizontalCoordinate(azimuth: 0, altitude: 89.9).unitVector
        XCTAssertNotNil(SmallBodySkyMarkers.tailEnd(from: nearZenith, angleFromVertical: 0))
    }

    // MARK: How the markers look

    private func radius(_ magnitude: Double?, comet: Bool) -> Double {
        Double(SmallBodyMarkerStyle.dotRadius(magnitude: magnitude, isComet: comet))
    }

    func testCometDotsGrowWithBrightnessBetweenTwoAndAHalfAndFourAndAHalfPoints() {
        XCTAssertEqual(radius(4, comet: true), 4.5, accuracy: 1e-9)
        XCTAssertEqual(radius(-2, comet: true), 4.5, accuracy: 1e-9, "brighter than magnitude 4 is capped")
        XCTAssertEqual(radius(6, comet: true), 3.8, accuracy: 1e-9)
        XCTAssertEqual(radius(8, comet: true), 3.1, accuracy: 1e-9)
        XCTAssertEqual(radius(10, comet: true), 2.5, accuracy: 1e-9, "fainter than about magnitude 9.7 is floored")
        XCTAssertEqual(radius(20, comet: true), 2.5, accuracy: 1e-9)
    }

    func testAsteroidDotsGrowWithBrightnessBetweenTwoAndThreePointFourPoints() {
        XCTAssertEqual(radius(5, asteroid: true), 3.4, accuracy: 1e-9)
        XCTAssertEqual(radius(0, asteroid: true), 3.4, accuracy: 1e-9, "brighter than magnitude 5 is capped")
        XCTAssertEqual(radius(7, asteroid: true), 2.8, accuracy: 1e-9)
        XCTAssertEqual(radius(9, asteroid: true), 2.2, accuracy: 1e-9)
        XCTAssertEqual(radius(12, asteroid: true), 2.0, accuracy: 1e-9, "fainter than about magnitude 9.7 is floored")
    }

    private func radius(_ magnitude: Double?, asteroid: Bool) -> Double {
        radius(magnitude, comet: !asteroid)
    }

    func testABodyOfUnknownMagnitudeIsASmallDot() {
        XCTAssertEqual(radius(nil, comet: true), 2.5, accuracy: 1e-9)
        XCTAssertEqual(radius(nil, comet: false), 2.5, accuracy: 1e-9)
        XCTAssertEqual(radius(Double.nan, comet: true), 2.5, accuracy: 1e-9)
        XCTAssertEqual(radius(Double.infinity, comet: false), 2.5, accuracy: 1e-9)
    }

    func testTheTailLineIsLongerForBrighterComets() {
        func length(_ magnitude: Double?) -> Double { Double(SmallBodyMarkerStyle.tailLength(magnitude: magnitude)) }
        XCTAssertEqual(length(nil), 12, accuracy: 1e-9)
        XCTAssertEqual(length(Double.nan), 12, accuracy: 1e-9)
        XCTAssertEqual(length(9), 12, accuracy: 1e-9)
        XCTAssertEqual(length(8), 12, accuracy: 1e-9)
        XCTAssertEqual(length(7), 14, accuracy: 1e-9)
        XCTAssertEqual(length(4), 20, accuracy: 1e-9)
        XCTAssertEqual(length(3), 22, accuracy: 1e-9)
        XCTAssertEqual(length(-4), 22, accuracy: 1e-9, "the extra length stops at 10 points")
    }

    func testTheBrightestBodiesAreNamedAtOnce() {
        func zoom(_ magnitude: Double?) -> Double { Double(SmallBodyMarkerStyle.labelZoom(magnitude: magnitude)) }
        XCTAssertEqual(zoom(nil), 3, accuracy: 1e-9)
        XCTAssertEqual(zoom(Double.nan), 3, accuracy: 1e-9)
        XCTAssertEqual(zoom(2), 1, accuracy: 1e-9)
        XCTAssertEqual(zoom(6.5), 1, accuracy: 1e-9)
        XCTAssertEqual(zoom(6.6), 1.8, accuracy: 1e-9)
        XCTAssertEqual(zoom(8), 1.8, accuracy: 1e-9)
        XCTAssertEqual(zoom(8.1), 3, accuracy: 1e-9)
    }

    func testTheAimOverlayNamesBodiesByMagnitudeAndFieldOfView() {
        XCTAssertEqual(SmallBodyMarkerStyle.nameMagnitude, 8)
        XCTAssertEqual(SmallBodyMarkerStyle.narrowNameMagnitude, 9)
        XCTAssertEqual(SmallBodyMarkerStyle.narrowView, 40)
        // Up to magnitude 8 in any view.
        XCTAssertTrue(SmallBodyMarkerStyle.isNamed(magnitude: 8, fieldOfView: 90))
        XCTAssertTrue(SmallBodyMarkerStyle.isNamed(magnitude: -1, fieldOfView: 90))
        XCTAssertFalse(SmallBodyMarkerStyle.isNamed(magnitude: 8.5, fieldOfView: 90))
        // Up to magnitude 9 in a view narrower than 40 degrees.
        XCTAssertTrue(SmallBodyMarkerStyle.isNamed(magnitude: 8.5, fieldOfView: 39.9))
        XCTAssertTrue(SmallBodyMarkerStyle.isNamed(magnitude: 9, fieldOfView: 20))
        XCTAssertFalse(SmallBodyMarkerStyle.isNamed(magnitude: 8.5, fieldOfView: 40))
        XCTAssertFalse(SmallBodyMarkerStyle.isNamed(magnitude: 9.1, fieldOfView: 20))
    }

    func testABodyOfUnknownMagnitudeIsNeverNamed() {
        XCTAssertFalse(SmallBodyMarkerStyle.isNamed(magnitude: nil, fieldOfView: 10))
        XCTAssertFalse(SmallBodyMarkerStyle.isNamed(magnitude: Double.nan, fieldOfView: 10))
        XCTAssertFalse(SmallBodyMarkerStyle.isNamed(magnitude: Double.infinity, fieldOfView: 10))
    }

    // MARK: Fixtures

    /// The comets of the review fixtures and the two brightest asteroids: real MPC lines of 2026-10-18.
    private static func fixtureBodies() throws -> [SmallBody] {
        let cometLines = [
            "    CJ95O010  1997 03 29.0284  0.925995  0.994895  130.7313  281.8097   89.7335  20261017  -2.0  4.0  C/1995 O1 (Hale-Bopp)                                    MPC194091",
            "    CK23A030  2024 09 27.8337  0.391312  1.000180  308.5842   21.6759  139.0991  20261017   6.5  3.2  C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2026-O98",
            "0012P         2024 04 21.2066  0.781920  0.954748  199.0355  255.8678   74.1469  20261017   5.0  6.0  12P/Pons-Brooks                                          MPEC 2026-TI5",
            "0001P         2061 08  1.5218  0.570945  0.968030  112.1616   59.2610  162.1917  20261017   5.5  3.2  1P/Halley                                                MPC191592",
            "0002P         2027 02 10.2276  0.338603  0.847319  187.2873  334.0197   11.3480  20261017  14.4  4.0  2P/Encke                                                 MPC xxxxx",
            "0073P     bt  2027 12 25.1036  0.915911  0.700909  214.4932   52.3435    6.1794  20261017  11.5  6.0  73P-BT/Schwassmann-Wachmann                              MPC106348",
            "    CK13A010  2014 10 26.8227  1.391249  1.000073    2.5353  301.1848  128.6857  20261017   8.2  2.4  C/2013 A1 (SidingSpring)                                 MPC194130",
            "    PK26N020  2026 09 25.7701  2.422069  0.212174  218.8645   96.3812    2.2496  20261017  17.4  4.0  P/2026 N2                                                MPEC 2026-Q95",
            "0161P         2026 11 27.1783  1.265109  0.836180   47.0652    1.4736   95.7919  20261017   8.5  6.0  161P/Hartley-IRAS                                        MPEC 2026-TP0",
            "0078P         2026 06 25.1355  2.004570  0.462933  192.8100  210.4913    6.2574  20261017   5.5  8.0  78P/Gehrels                                              MPEC 2026-TP0",
            "0029P         2034 03 15.1855  5.797924  0.042915   51.2459  312.3998    9.3549  20261017   4.0  4.0  29P/Schwassmann-Wachmann                                 MPEC 2026-RA1",
            "    CK14UR1N  2031 01 16.6692 10.959316  1.004054  326.0949  190.0073   95.4457  20261017   2.5  3.2  C/2014 UN271 (Bernardinelli-Bernstein)                   MPEC 2026-TP0",
            "    CK24E010  2026 01 20.8145  0.565779  1.000381  243.6172  108.0685   75.1999  20261017   7.0  4.0  C/2024 E1 (Wierzchos)                                    MPEC 2026-O98",
            "    PK26R020  2026 10 25.2362  0.789531  0.898740  205.5263  179.2306   78.0993  20261017  16.0  4.0  P/2026 R2 (Leonard)                                      MPC xxxxx",
        ]
        let asteroidLines = [
            "00001    3.34  0.15 K2669 274.41935   73.29420   80.24863   10.58803  0.0796923  0.21430445   2.7655526  0 E2026-SD4  7376 127 1801-2026 0.82 M-v 30k MPCORBFIT  4000      (1) Ceres              20260922",
            "00004    3.25  0.15 K2669  81.19019  151.46856  103.70135    7.14393  0.0902037  0.27161836   2.3613660  0 E2026-T23  7610 112 1821-2025 0.84 M-p 18k Pan        4000      (4) Vesta              20250624",
        ]
        return try cometLines.map { try CometElementsParser.parseLine($0) }
            + asteroidLines.map { try MinorPlanetElementsParser.parseLine($0) }
    }
}
