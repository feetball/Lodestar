import XCTest
import LodestarKit
@testable import AppCore

// MARK: - Fixture

/// A small synthetic catalog with known names, magnitudes, prominences and catalogue numbers, built from the JSON of the
/// real data files (so every object goes through the engine's own loading code).
///
/// Listed objects (browse list, 28 of them): the nine solar-system bodies, the three special objects, the stars
/// "Alpha Test" (0.5), "Beta Test" (2.5), "Gamma Test" (4.5) and "Faint Named" (10.5), and the deep-sky objects M 31, M 42,
/// M 13, NGC 7000, B 33, NGC 891, NGC 2000, NGC 2001, Cl 399, the LMC (no catalogue number) and the twins NGC 100 and
/// NGC 101 (both named "Twin Cluster", magnitude 7). Not listed: the unnamed stars HIP 1005 and HIP 1007 (both 6.0),
/// Mel 20, Tr 14, Sh2-155, Sh2-129 and LDN 1622.
private enum ObjectsBuilderFixture {
    static let reference = Date(timeIntervalSince1970: 1_800_000_000)

    private static let plain: Result<Catalog, Error> = Result { try ObjectsBuilderFixture.makeCatalog(includingSmallBodies: false) }
    private static let small: Result<Catalog, Error> = Result { try ObjectsBuilderFixture.makeCatalog(includingSmallBodies: true) }

    /// The names of the browse list in name order.
    static let browseNames = [
        "Alpha Test", "Andromeda Galaxy", "Beta Test", "Coathanger", "Faint Named", "Galactic Center", "Gamma Test",
        "Hercules Cluster", "Horsehead Nebula", "Jupiter", "Large Magellanic Cloud", "Mars", "Mercury", "Moon", "Neptune",
        "NGC 891", "NGC 2000", "NGC 2001", "North America Nebula", "North Celestial Pole", "Orion Nebula", "Saturn",
        "South Celestial Pole", "Sun", "Twin Cluster", "Twin Cluster", "Uranus", "Venus",
    ]

    static func catalog(smallBodies: Bool = false) throws -> Catalog {
        try (smallBodies ? small : plain).get()
    }

    private static func file(_ key: String, _ records: [String]) -> Data {
        Data(#"{"schema":1,"\#(key)":[\#(records.joined(separator: ","))]}"#.utf8)
    }

    private static let stars = [
        #"{"hip":1001,"n":"Alpha Test","c":"Ori","ra":10.0,"de":20.0,"m":0.5}"#,
        #"{"hip":1002,"n":"Beta Test","c":"Ori","ra":11.0,"de":20.0,"m":2.5}"#,
        #"{"hip":1003,"n":"Gamma Test","c":"Ori","ra":12.0,"de":20.0,"m":4.5}"#,
        #"{"hip":1005,"c":"Ori","ra":13.0,"de":20.0,"m":6.0}"#,
        #"{"hip":1006,"n":"Faint Named","c":"Ori","ra":14.0,"de":20.0,"m":10.5}"#,
        #"{"hip":1007,"c":"Ori","ra":15.0,"de":20.0,"m":6.0}"#,
    ]

    private static let deepSky = [
        #"{"id":"M31","m":31,"ngc":[224],"names":["Andromeda Galaxy"],"t":"G","ra":10.68,"de":41.27,"c":"And","vm":3.4,"maj":178,"min":63,"p":1}"#,
        #"{"id":"M42","m":42,"ngc":[1976],"names":["Orion Nebula"],"t":"HII","ra":83.82,"de":-5.39,"c":"Ori","vm":4.0,"maj":65,"min":60,"p":1}"#,
        #"{"id":"M13","m":13,"ngc":[6205],"names":["Hercules Cluster"],"t":"GCl","ra":250.42,"de":36.46,"c":"Her","vm":5.8,"maj":20,"p":2}"#,
        #"{"id":"NGC7000","ngc":[7000],"cat":["C20"],"names":["North America Nebula"],"t":"HII","ra":314.7,"de":44.3,"c":"Cyg","vm":4.0,"maj":120,"min":100,"p":2}"#,
        #"{"id":"B33","names":["Horsehead Nebula"],"t":"DrkN","ra":85.25,"de":-2.46,"c":"Ori","maj":6,"min":4,"p":2}"#,
        #"{"id":"NGC891","ngc":[891],"t":"G","ra":35.64,"de":42.35,"c":"And","vm":10.8,"maj":13,"min":3,"p":3}"#,
        #"{"id":"NGC2000","ngc":[2000],"t":"OCl","ra":100.0,"de":10.0,"c":"Ori","vm":10.0,"p":3}"#,
        #"{"id":"NGC2001","ngc":[2001],"t":"OCl","ra":101.0,"de":10.0,"c":"Ori","vm":10.1,"p":3}"#,
        #"{"id":"Cl399","names":["Coathanger"],"t":"OCl","ra":291.0,"de":20.0,"c":"Cyg","vm":3.6,"maj":60,"p":3}"#,
        #"{"id":"Mel20","names":["Alpha Persei Cluster"],"t":"OCl","ra":51.0,"de":49.0,"c":"And","vm":1.2,"maj":300,"p":4}"#,
        #"{"id":"Tr14","t":"OCl","ra":160.0,"de":-59.0,"c":"Ori","vm":5.5,"p":4}"#,
        #"{"id":"Sh2-155","names":["Cave Nebula"],"t":"HII","ra":340.0,"de":62.0,"c":"Cyg","maj":50,"p":4}"#,
        #"{"id":"Sh2-129","t":"HII","ra":320.0,"de":59.0,"c":"Cyg","maj":170,"p":4}"#,
        #"{"id":"LDN1622","t":"DrkN","ra":88.0,"de":2.0,"c":"Ori","maj":30,"p":4}"#,
        #"{"id":"ESO56-115","names":["Large Magellanic Cloud"],"t":"G","ra":80.0,"de":-69.0,"c":"Dor","vm":0.4,"maj":600,"p":1}"#,
        #"{"id":"NGC100","ngc":[100],"names":["Twin Cluster"],"t":"OCl","ra":5.0,"de":5.0,"c":"And","vm":7.0,"p":3}"#,
        #"{"id":"NGC101","ngc":[101],"names":["Twin Cluster"],"t":"OCl","ra":6.0,"de":5.0,"c":"And","vm":7.0,"p":3}"#,
    ]

    private static let constellations = [
        #"{"abbr":"And","name":"Andromeda","genitive":"Andromedae","label":[10.0,40.0],"lines":[[[10.0,30.0],[20.0,40.0]]]}"#,
        #"{"abbr":"Ori","name":"Orion","genitive":"Orionis","label":[83.0,5.0],"lines":[[[80.0,0.0],[85.0,10.0]]]}"#,
        #"{"abbr":"Cyg","name":"Cygnus","genitive":"Cygni","label":[310.0,40.0],"lines":[[[300.0,30.0],[320.0,50.0]]]}"#,
        #"{"abbr":"Her","name":"Hercules","genitive":"Herculis","label":[255.0,30.0],"lines":[[[250.0,25.0],[260.0,35.0]]]}"#,
    ]

    private static let milkyWayLevel = #"{"level":1,"polygons":[[[10,10],[20,10],[20,20]]],"holes":[]}"#

    private static func makeCatalog(includingSmallBodies: Bool) throws -> Catalog {
        let base = try Catalog(starsData: file("stars", stars), dsosData: file("objects", deepSky),
                               constellationsData: file("constellations", constellations),
                               milkyWayData: file("levels", [milkyWayLevel]))
        if includingSmallBodies {
            let bodies = try smallBodyList()
            return base.withSmallBodies(bodies)
        }
        return base
    }

    // MARK: Comets and asteroids

    private static func elements(perihelion: Double, eccentricity: Double) throws -> SmallBodyElements {
        try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: perihelion, eccentricity: eccentricity, inclination: 20,
                                        argumentOfPerihelion: 30, longitudeOfAscendingNode: 40,
                                        perihelionJulianDayTT: 2_461_000, epochJulianDayTT: 2_461_200.5))
    }

    /// A comet whose peak magnitude estimate is `peak` (perihelion at 1 AU, where the estimate is M1 + 5 log10 of the
    /// square root of 2).
    private static func comet(_ designation: String, _ name: String, peak: Double) throws -> SmallBody {
        let orbit = try elements(perihelion: 1, eccentricity: 0.5)
        let magnitudes = try XCTUnwrap(CometMagnitudes(totalMagnitude: peak - 0.752574989159953, totalSlope: 10))
        return try XCTUnwrap(SmallBody(designation: designation, name: name, kind: .comet, number: nil, orbit: orbit,
                                       photometry: .comet(magnitudes)))
    }

    private static func smallBodyList() throws -> [SmallBody] {
        let orbit = try elements(perihelion: 2, eccentricity: 0.1)
        let magnitudes = try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 5))
        let asteroid = try XCTUnwrap(SmallBody(designation: "9999", name: "Testrock", kind: .asteroid, number: 9999,
                                               orbit: orbit, photometry: .asteroid(magnitudes)))
        return [
            try comet("C/2099 A1", "Test Comet", peak: 5.0),
            try comet("C/2099 B2", "Dim Comet", peak: 9.0),
            try comet("C/2099 C3", "Faint Comet", peak: 13.0),
            asteroid,
        ]
    }

    // MARK: Building lists

    static func options(grouping: ObjectsGrouping = ObjectsGrouping.none, sort: ObjectsSortOrder = .name,
                        catalogue: ObjectsCatalogueFilter = .all, aboveHorizon: Bool = false, hideFaint: Bool = false,
                        popular: Bool = false) -> ObjectsListOptions {
        var options = ObjectsListOptions()
        options.grouping = grouping
        options.sortOrder = sort
        options.catalogue = catalogue
        options.showsOnlyAboveHorizon = aboveHorizon
        options.hidesFaintObjects = hideFaint
        options.showsOnlyPopular = popular
        return options
    }

    static func sections(_ options: ObjectsListOptions, favorites: [String] = [], recents: [String] = [],
                         positions: [String: ObjectSkyPosition] = [:],
                         smallBodies: Bool = false) throws -> [ObjectsListSection] {
        let catalog = try self.catalog(smallBodies: smallBodies)
        return ObjectsListBuilder.sections(options: options, catalog: catalog, index: ObjectsCatalogIndex(catalog: catalog),
                                           favoriteIDs: favorites, recentIDs: recents, positions: positions)
    }

    /// The ids of every row of the list, section by section.
    static func rows(_ options: ObjectsListOptions, favorites: [String] = [], recents: [String] = [],
                     positions: [String: ObjectSkyPosition] = [:], smallBodies: Bool = false) throws -> [String] {
        try sections(options, favorites: favorites, recents: recents, positions: positions, smallBodies: smallBodies)
            .flatMap(\.objects).map(\.id)
    }

    static func position(_ altitude: Double, magnitude: Double? = nil, rise: Date? = nil,
                         isAbove: Bool? = nil) -> ObjectSkyPosition {
        ObjectSkyPosition(altitude: altitude, azimuth: 180, nextRise: rise, neverRises: false, noRiseInWindow: false,
                          magnitude: magnitude, computedAt: reference, isAboveHorizon: isAbove ?? (altitude > 0),
                          isBehindSkyline: false, usesSkyline: false)
    }

    /// Positions that give the Sun, the Moon and the planets a current magnitude, as the position model does.
    static func solarSystemPositions() -> [String: ObjectSkyPosition] {
        let magnitudes: [String: Double] = [
            "sun": -26.7, "moon": -12.7, "planet.venus": -4.4, "planet.jupiter": -2.7, "planet.saturn": 0.2,
            "planet.mars": 1.2, "planet.mercury": 2.0, "planet.uranus": 5.7, "planet.neptune": 7.8,
        ]
        return magnitudes.mapValues { position(10, magnitude: $0) }
    }

    /// Positions for the NGC/IC objects: three up (M 31 at 55, M 13 and NGC 100 at 30), five down with rising times,
    /// M 42 down without a rising and NGC 2000 without a position.
    static func ngcPositions() -> [String: ObjectSkyPosition] {
        [
            "dso.M31": position(55),
            "dso.M13": position(30),
            "dso.NGC100": position(30),
            "dso.NGC891": position(-10, rise: reference.addingTimeInterval(3_600)),
            "dso.NGC2001": position(-20, rise: reference.addingTimeInterval(3_600)),
            "dso.NGC101": position(-5, rise: reference.addingTimeInterval(7_200)),
            "dso.NGC7000": position(-40, rise: reference.addingTimeInterval(10_800)),
            "dso.M42": position(-15),
        ]
    }
}

// MARK: - Sections and titles

final class ObjectsListBuilderSectionTests: XCTestCase {
    func testObjectTypeGroupingMakesOneSectionPerGroupInTheOrderOfTheGroups() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsListOptions())
        XCTAssertEqual(sections.map(\.kind), [.group(.solarSystem), .group(.stars), .group(.galaxies), .group(.nebulae),
                                              .group(.clusters), .group(.special)])
        XCTAssertEqual(sections.map(\.title), ["Solar System", "Stars", "Galaxies", "Nebulae", "Star Clusters", "Special"])
        XCTAssertEqual(sections.map(\.systemImage), ["sun.max", "star", "hurricane", "cloud", "sparkles", "scope"])
        XCTAssertEqual(sections[0].objects.map(\.name),
                       ["Jupiter", "Mars", "Mercury", "Moon", "Neptune", "Saturn", "Sun", "Uranus", "Venus"])
        XCTAssertEqual(sections[1].objects.map(\.name), ["Alpha Test", "Beta Test", "Faint Named", "Gamma Test"])
        XCTAssertEqual(sections[2].objects.map(\.name), ["Andromeda Galaxy", "Large Magellanic Cloud", "NGC 891"])
        XCTAssertEqual(sections[3].objects.map(\.name), ["Horsehead Nebula", "North America Nebula", "Orion Nebula"])
        XCTAssertEqual(sections[4].objects.map(\.name),
                       ["Coathanger", "Hercules Cluster", "NGC 2000", "NGC 2001", "Twin Cluster", "Twin Cluster"])
        XCTAssertEqual(sections[5].objects.map(\.name), ["Galactic Center", "North Celestial Pole", "South Celestial Pole"])
    }

    func testProminenceGroupingMakesOneSectionPerLevelFromShowpieceToObscure() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(grouping: .prominence))
        XCTAssertEqual(sections.map(\.kind), [.prominence(.showpiece), .prominence(.prominent), .prominence(.notable),
                                              .prominence(.obscure)])
        XCTAssertEqual(sections.map(\.title), ["Showpieces", "Prominent", "Notable", "Obscure"])
        XCTAssertEqual(sections.map(\.systemImage), ["sparkles", "sparkle", "circle.dotted", "circle.dashed"])
        XCTAssertEqual(sections[0].objects.map(\.name),
                       ["Alpha Test", "Andromeda Galaxy", "Galactic Center", "Jupiter", "Large Magellanic Cloud", "Mars",
                        "Mercury", "Moon", "Neptune", "North Celestial Pole", "Orion Nebula", "Saturn",
                        "South Celestial Pole", "Sun", "Uranus", "Venus"])
        XCTAssertEqual(sections[1].objects.map(\.name),
                       ["Beta Test", "Hercules Cluster", "Horsehead Nebula", "North America Nebula"])
        XCTAssertEqual(sections[2].objects.map(\.name),
                       ["Coathanger", "Gamma Test", "NGC 891", "NGC 2000", "NGC 2001", "Twin Cluster", "Twin Cluster"])
        XCTAssertEqual(sections[3].objects.map(\.name), ["Faint Named"])
    }

    func testProminenceSectionsAreSkippedWhenTheyHaveNoObjects() throws {
        // Only showpieces and prominent objects remain.
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(grouping: .prominence, popular: true))
        XCTAssertEqual(sections.map(\.kind), [.prominence(.showpiece), .prominence(.prominent)])
        // Only a notable and an obscure object are left among the Collinder/Melotte/Trumpler/Stock clusters.
        let clusters = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(grouping: .prominence, sort: .number, catalogue: .clusters))
        XCTAssertEqual(clusters.map(\.kind), [.prominence(.notable), .prominence(.obscure)])
        XCTAssertEqual(clusters[0].objects.map(\.id), ["dso.Cl399"])
        XCTAssertEqual(clusters[1].objects.map(\.id), ["dso.Mel20", "dso.Tr14"])
    }

    func testNoGroupingGivesOneSectionWithEveryListedObject() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options())
        XCTAssertEqual(sections.map(\.kind), [.all])
        XCTAssertEqual(sections[0].title, "All Objects")
        XCTAssertEqual(sections[0].systemImage, "list.bullet")
        XCTAssertEqual(sections[0].objects.map(\.name), ObjectsBuilderFixture.browseNames)
        let catalog = try ObjectsBuilderFixture.catalog()
        XCTAssertEqual(Set(sections[0].objects.map(\.id)), Set(catalog.listedObjects.map(\.id)))
        XCTAssertEqual(sections[0].objects.count, 28)
    }

    func testCometsAndAsteroidsGetASectionEachInsideTheSolarSystemGroup() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsListOptions(), smallBodies: true)
        XCTAssertEqual(sections.map(\.kind),
                       [.group(.solarSystem), .smallBodies(.comet), .smallBodies(.asteroid), .group(.stars), .group(.galaxies),
                        .group(.nebulae), .group(.clusters), .group(.special)])
        XCTAssertEqual(sections.map(\.title), ["Solar System", "Comets", "Asteroids", "Stars", "Galaxies", "Nebulae",
                                               "Star Clusters", "Special"])
        XCTAssertEqual(sections[1].systemImage, "sparkle")
        XCTAssertEqual(sections[2].systemImage, "circle.fill")
        // The Solar System section keeps the Sun, the Moon and the planets only.
        XCTAssertEqual(sections[0].objects.count, 9)
        XCTAssertTrue(sections[0].objects.allSatisfy { $0.smallBody == nil })
        XCTAssertEqual(sections[1].objects.map(\.name), ["C/2099 A1 (Test Comet)", "C/2099 B2 (Dim Comet)"])
        XCTAssertEqual(sections[2].objects.map(\.name), ["(9999) Testrock"])
    }

    func testSmallBodiesThatAreNotListedStayOutOfTheBrowseList() throws {
        let rows = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(), smallBodies: true)
        XCTAssertFalse(rows.contains("comet.C/2099 C3"))
        XCTAssertTrue(rows.contains("comet.C/2099 A1"))
        XCTAssertTrue(rows.contains("comet.C/2099 B2"))
        XCTAssertTrue(rows.contains("asteroid.9999"))
        XCTAssertEqual(rows.count, 28 + 3)
    }

    func testTheSolarSystemSectionIsLeftOutWhenOnlyCometsRemain() throws {
        let positions = ["comet.C/2099 A1": ObjectsBuilderFixture.position(20)]
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(grouping: .type, aboveHorizon: true),
                                                          positions: positions, smallBodies: true)
        XCTAssertEqual(sections.map(\.kind), [.smallBodies(.comet)])
        XCTAssertEqual(sections[0].objects.map(\.id), ["comet.C/2099 A1"])
    }

    func testSmallBodiesJoinTheProminenceSectionsOfTheirRating() throws {
        // Peak magnitude estimates: Test Comet 5.0 (showpiece), Testrock about 6.5 (prominent), Dim Comet 9.0 (notable).
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(grouping: .prominence),
                                                          smallBodies: true)
        func ids(_ prominence: Prominence) -> [String] {
            sections.first { $0.kind == .prominence(prominence) }?.objects.map(\.id) ?? []
        }
        XCTAssertTrue(ids(.showpiece).contains("comet.C/2099 A1"))
        XCTAssertTrue(ids(.prominent).contains("asteroid.9999"))
        XCTAssertTrue(ids(.notable).contains("comet.C/2099 B2"))
        XCTAssertFalse(sections.flatMap(\.objects).map(\.id).contains("comet.C/2099 C3"))
    }

    func testSectionIdentifiersAreTheirKinds() {
        let kinds: [ObjectsListSection.Kind] = [.favorites, .recent, .group(.stars), .smallBodies(.comet),
                                                .prominence(.notable), .all, .results]
        for kind in kinds {
            XCTAssertEqual(ObjectsListSection(kind: kind, objects: []).id, kind)
        }
        XCTAssertEqual(Set(kinds).count, kinds.count)
        XCTAssertNotEqual(ObjectsListSection.Kind.smallBodies(.comet), ObjectsListSection.Kind.smallBodies(.asteroid))
    }

    func testTitlesAndImagesOfTheSpecialSections() {
        let favorites = ObjectsListSection(kind: .favorites, objects: [])
        XCTAssertEqual(favorites.title, "Favorites")
        XCTAssertEqual(favorites.systemImage, "star.fill")
        let recent = ObjectsListSection(kind: .recent, objects: [])
        XCTAssertEqual(recent.title, "Recent")
        XCTAssertEqual(recent.systemImage, "clock")
        let results = ObjectsListSection(kind: .results, objects: [])
        XCTAssertEqual(results.title, "Results")
        XCTAssertEqual(results.systemImage, "magnifyingglass")
        let all = ObjectsListSection(kind: .all, objects: [])
        XCTAssertEqual(all.title, "All Objects")
        XCTAssertEqual(all.systemImage, "list.bullet")
    }

    func testEverySmallBodyAndProminenceSectionHasATitleAndAnImage() {
        XCTAssertEqual(ObjectsListSection(kind: .smallBodies(.comet), objects: []).title, "Comets")
        XCTAssertEqual(ObjectsListSection(kind: .smallBodies(.asteroid), objects: []).title, "Asteroids")
        XCTAssertEqual(ObjectsListSection(kind: .prominence(.showpiece), objects: []).title, "Showpieces")
        XCTAssertEqual(ObjectsListSection(kind: .prominence(.prominent), objects: []).systemImage, "sparkle")
        XCTAssertEqual(ObjectsListSection(kind: .prominence(.notable), objects: []).systemImage, "circle.dotted")
        XCTAssertEqual(ObjectsListSection(kind: .prominence(.obscure), objects: []).systemImage, "circle.dashed")
        for group in ObjectGroup.allCases {
            let section = ObjectsListSection(kind: .group(group), objects: [])
            XCTAssertEqual(section.title, group.displayName)
            XCTAssertEqual(section.systemImage, group.systemImageName)
        }
    }

    func testASectionHasNoUnavailableFavoritesByDefault() {
        XCTAssertEqual(ObjectsListSection(kind: .all, objects: []).unavailable, [])
    }

    // MARK: Empty states

    func testNothingMatchesALyndsListLimitedToPopularObjects() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(catalogue: .lynds, popular: true))
        XCTAssertTrue(sections.isEmpty)
    }

    func testNothingIsShownWhenNoObjectIsAboveTheHorizon() throws {
        let positions = ["sun": ObjectsBuilderFixture.position(-30), "dso.M31": ObjectsBuilderFixture.position(-5)]
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(aboveHorizon: true),
                                                          positions: positions)
        XCTAssertTrue(sections.isEmpty)
    }

    func testABarnardListLimitedToPopularObjectsKeepsTheHorsehead() throws {
        // B 33 is prominent and has no magnitude, so neither filter removes it.
        let options = ObjectsBuilderFixture.options(catalogue: .barnard, hideFaint: true, popular: true)
        XCTAssertEqual(try ObjectsBuilderFixture.rows(options), ["dso.B33"])
    }

    func testFavoritesAndRecentsOutsideTheChosenCatalogueDoNotMakeSections() throws {
        // None of the Lynds objects is popular; the favorite and the recent are not Lynds objects either.
        let options = ObjectsBuilderFixture.options(catalogue: .lynds, popular: true)
        let sections = try ObjectsBuilderFixture.sections(options, favorites: ["sun"], recents: ["dso.M31"])
        XCTAssertTrue(sections.isEmpty)
    }
}

// MARK: - Filters

final class ObjectsListBuilderFilterTests: XCTestCase {
    private func names(_ options: ObjectsListOptions, positions: [String: ObjectSkyPosition] = [:]) throws -> [String] {
        try ObjectsBuilderFixture.sections(options, positions: positions).flatMap(\.objects).map(\.name)
    }

    func testWithoutFiltersEveryListedObjectIsShown() throws {
        XCTAssertEqual(try names(ObjectsBuilderFixture.options()), ObjectsBuilderFixture.browseNames)
    }

    func testHideFaintRemovesObjectsFainterThanMagnitudeTen() throws {
        let shown = try names(ObjectsBuilderFixture.options(hideFaint: true))
        let removed = ["NGC 891", "NGC 2001", "Faint Named"]
        XCTAssertEqual(shown, ObjectsBuilderFixture.browseNames.filter { !removed.contains($0) })
        XCTAssertEqual(shown.count, 25)
    }

    func testHideFaintKeepsAnObjectExactlyAtTheLimit() throws {
        // NGC 2000 is magnitude 10.0, NGC 2001 is 10.1.
        let shown = try names(ObjectsBuilderFixture.options(hideFaint: true))
        XCTAssertTrue(shown.contains("NGC 2000"))
        XCTAssertFalse(shown.contains("NGC 2001"))
        XCTAssertEqual(ObjectsListOptions.faintMagnitudeLimit, 10.0)
    }

    func testHideFaintKeepsObjectsWithoutAMagnitude() throws {
        let shown = try names(ObjectsBuilderFixture.options(hideFaint: true))
        // A dark nebula, the planets, the Sun and the Moon have no catalog magnitude.
        for name in ["Horsehead Nebula", "Sun", "Moon", "Jupiter", "Galactic Center", "North Celestial Pole"] {
            XCTAssertTrue(shown.contains(name), name)
        }
    }

    func testHideFaintJudgesACometByItsCurrentMagnitude() throws {
        let positions = [
            "comet.C/2099 A1": ObjectsBuilderFixture.position(20, magnitude: 6.0),
            "comet.C/2099 B2": ObjectsBuilderFixture.position(20, magnitude: 12.5),
            "asteroid.9999": ObjectsBuilderFixture.position(20, magnitude: 10.0),
        ]
        let rows = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(hideFaint: true), positions: positions,
                                                  smallBodies: true)
        XCTAssertTrue(rows.contains("comet.C/2099 A1"))
        XCTAssertFalse(rows.contains("comet.C/2099 B2"))
        XCTAssertTrue(rows.contains("asteroid.9999"), "magnitude 10.0 is not fainter than the limit")
    }

    func testHideFaintKeepsACometWhoseMagnitudeIsNotKnownYet() throws {
        // Positions exist for another object only.
        let positions = ["sun": ObjectsBuilderFixture.position(10)]
        let rows = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(hideFaint: true), positions: positions,
                                                  smallBodies: true)
        XCTAssertTrue(rows.contains("comet.C/2099 B2"))
    }

    func testPopularOnlyKeepsShowpieceAndProminentObjects() throws {
        let shown = try names(ObjectsBuilderFixture.options(popular: true))
        let removed = ["Coathanger", "Faint Named", "Gamma Test", "NGC 891", "NGC 2000", "NGC 2001", "Twin Cluster",
                       "Twin Cluster"]
        XCTAssertEqual(shown, ObjectsBuilderFixture.browseNames.filter { !removed.contains($0) })
        XCTAssertEqual(shown.count, 20)
        XCTAssertEqual(ObjectsListOptions.popularProminence, .prominent)
    }

    func testPopularOnlyKeepsAProminentObjectAndDropsANotableOne() throws {
        let shown = try names(ObjectsBuilderFixture.options(popular: true))
        XCTAssertTrue(shown.contains("Beta Test"))
        XCTAssertFalse(shown.contains("Gamma Test"))
    }

    func testPopularAndHideFaintTogetherApplyBothFilters() throws {
        let shown = try names(ObjectsBuilderFixture.options(hideFaint: true, popular: true))
        let popular = try names(ObjectsBuilderFixture.options(popular: true))
        let notFaint = try names(ObjectsBuilderFixture.options(hideFaint: true))
        XCTAssertEqual(shown, popular.filter { notFaint.contains($0) })
        XCTAssertEqual(shown, ObjectsBuilderFixture.browseNames.filter {
            !["Coathanger", "Faint Named", "Gamma Test", "NGC 891", "NGC 2000", "NGC 2001", "Twin Cluster"].contains($0)
        })
    }

    func testAboveHorizonKeepsOnlyObjectsThatAreUp() throws {
        let positions = [
            "sun": ObjectsBuilderFixture.position(30),
            "moon": ObjectsBuilderFixture.position(-12),
            "dso.M31": ObjectsBuilderFixture.position(0.5),
            "dso.M42": ObjectsBuilderFixture.position(-0.5),
            "star.hip1001": ObjectsBuilderFixture.position(75),
        ]
        let shown = try names(ObjectsBuilderFixture.options(aboveHorizon: true), positions: positions)
        XCTAssertEqual(shown, ["Alpha Test", "Andromeda Galaxy", "Sun"])
    }

    func testAboveHorizonDropsObjectsThatHaveNoPositionWhileOthersDo() throws {
        let positions = ["sun": ObjectsBuilderFixture.position(30)]
        let shown = try names(ObjectsBuilderFixture.options(aboveHorizon: true), positions: positions)
        XCTAssertEqual(shown, ["Sun"])
    }

    func testAboveHorizonTrustsTheFlagAndNotTheAltitude() throws {
        // An object above the geometric horizon but behind the recorded skyline is not up.
        let positions = [
            "sun": ObjectsBuilderFixture.position(5, isAbove: false),
            "moon": ObjectsBuilderFixture.position(-1, isAbove: true),
        ]
        let shown = try names(ObjectsBuilderFixture.options(aboveHorizon: true), positions: positions)
        XCTAssertEqual(shown, ["Moon"])
    }

    func testAboveHorizonIsIgnoredUntilPositionsArrive() throws {
        let filtered = try names(ObjectsBuilderFixture.options(aboveHorizon: true), positions: [:])
        XCTAssertEqual(filtered, ObjectsBuilderFixture.browseNames)
    }

    func testAboveHorizonAlsoFiltersFavoritesAndRecents() throws {
        let positions = ["sun": ObjectsBuilderFixture.position(30), "moon": ObjectsBuilderFixture.position(-30)]
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(aboveHorizon: true),
                                                          favorites: ["sun", "moon"], recents: ["moon", "sun"],
                                                          positions: positions)
        XCTAssertEqual(sections.map(\.kind), [.favorites, .recent, .all])
        XCTAssertEqual(sections[0].objects.map(\.id), ["sun"])
        XCTAssertEqual(sections[1].objects.map(\.id), ["sun"])
        XCTAssertEqual(sections[2].objects.map(\.id), ["sun"])
    }

    func testAboveHorizonCombinesWithPopularAndHideFaint() throws {
        var positions: [String: ObjectSkyPosition] = [:]
        for id in ["dso.M31", "star.hip1003", "dso.NGC891", "dso.B33", "star.hip1006"] {
            positions[id] = ObjectsBuilderFixture.position(20)
        }
        let shown = try ObjectsBuilderFixture.rows(
            ObjectsBuilderFixture.options(aboveHorizon: true, hideFaint: true, popular: true), positions: positions)
        // Gamma Test is notable, NGC 891 and Faint Named are notable and obscure (and faint); M 31 and B 33 pass every test.
        XCTAssertEqual(shown, ["dso.M31", "dso.B33"])
    }

    func testEveryCombinationOfTheThreeFiltersKeepsTheObjectsThatPassEachOfThem() throws {
        // Every other object of the browse list is up.
        let everything = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options())
        var positions: [String: ObjectSkyPosition] = [:]
        for (index, id) in everything.enumerated() {
            positions[id] = ObjectsBuilderFixture.position(index.isMultiple(of: 2) ? 30 : -30)
        }
        let up = Set(try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(aboveHorizon: true), positions: positions))
        let sharp = Set(try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(hideFaint: true), positions: positions))
        let popular = Set(try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(popular: true), positions: positions))
        XCTAssertEqual(up.count, 14)
        XCTAssertEqual(sharp.count, 25)
        XCTAssertEqual(popular.count, 20)
        for useUp in [false, true] {
            for useSharp in [false, true] {
                for usePopular in [false, true] {
                    let options = ObjectsBuilderFixture.options(aboveHorizon: useUp, hideFaint: useSharp, popular: usePopular)
                    let shown = try ObjectsBuilderFixture.rows(options, positions: positions)
                    let expected = everything.filter {
                        (!useUp || up.contains($0)) && (!useSharp || sharp.contains($0)) && (!usePopular || popular.contains($0))
                    }
                    XCTAssertEqual(shown, expected, "above \(useUp), hide faint \(useSharp), popular \(usePopular)")
                }
            }
        }
    }

    func testEveryCombinationOfTheFiltersAlsoWorksInACatalogueList() throws {
        let everything = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options())
        var positions: [String: ObjectSkyPosition] = [:]
        for (index, id) in everything.enumerated() {
            positions[id] = ObjectsBuilderFixture.position(index.isMultiple(of: 2) ? 30 : -30)
        }
        func ids(_ above: Bool, _ faint: Bool, _ popular: Bool) throws -> [String] {
            let options = ObjectsBuilderFixture.options(sort: .number, catalogue: .ngcIC, aboveHorizon: above,
                                                        hideFaint: faint, popular: popular)
            return try ObjectsBuilderFixture.rows(options, positions: positions)
        }
        let list = try ids(false, false, false)
        XCTAssertEqual(list.count, 9)
        let up = Set(try ids(true, false, false)), sharp = Set(try ids(false, true, false))
        let popular = Set(try ids(false, false, true))
        XCTAssertEqual(sharp, Set(list).subtracting(["dso.NGC891", "dso.NGC2001"]))
        XCTAssertEqual(popular, ["dso.M31", "dso.M42", "dso.M13", "dso.NGC7000"])
        for useUp in [false, true] {
            for useSharp in [false, true] {
                for usePopular in [false, true] {
                    let expected = list.filter {
                        (!useUp || up.contains($0)) && (!useSharp || sharp.contains($0)) && (!usePopular || popular.contains($0))
                    }
                    XCTAssertEqual(try ids(useUp, useSharp, usePopular), expected,
                                   "above \(useUp), hide faint \(useSharp), popular \(usePopular)")
                }
            }
        }
    }

    // MARK: Catalogue lists

    private func catalogueIDs(_ catalogue: ObjectsCatalogueFilter, sort: ObjectsSortOrder = .number,
                              grouping: ObjectsGrouping = ObjectsGrouping.none) throws -> [String] {
        try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(grouping: grouping, sort: sort, catalogue: catalogue))
    }

    func testTheMessierListIsInCatalogueOrder() throws {
        XCTAssertEqual(try catalogueIDs(.messier), ["dso.M13", "dso.M31", "dso.M42"])
    }

    func testTheMessierListInNameOrderFollowsTheNames() throws {
        // Andromeda Galaxy, Hercules Cluster, Orion Nebula.
        XCTAssertEqual(try catalogueIDs(.messier, sort: .name), ["dso.M31", "dso.M13", "dso.M42"])
    }

    func testTheCaldwellListHoldsObjectsThatAlsoHaveAnNGCNumber() throws {
        XCTAssertEqual(try catalogueIDs(.caldwell), ["dso.NGC7000"])
    }

    func testTheSharplessListHoldsTheObjectsTheBrowseListLeavesOut() throws {
        XCTAssertEqual(try catalogueIDs(.sharpless), ["dso.Sh2-129", "dso.Sh2-155"])
        let browse = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options())
        XCTAssertFalse(browse.contains("dso.Sh2-129"))
        XCTAssertFalse(browse.contains("dso.Sh2-155"))
    }

    func testTheSharplessListInNameOrderPutsTheNamedRegionFirst() throws {
        // "Cave Nebula" before "Sh2-129".
        XCTAssertEqual(try catalogueIDs(.sharpless, sort: .name), ["dso.Sh2-155", "dso.Sh2-129"])
    }

    func testTheBarnardAndLyndsLists() throws {
        XCTAssertEqual(try catalogueIDs(.barnard), ["dso.B33"])
        XCTAssertEqual(try catalogueIDs(.lynds), ["dso.LDN1622"])
    }

    func testTheNGCAndICListIsInNumberOrderAcrossBothCatalogues() throws {
        // NGC 100, 101, 224 (M 31), 891, 1976 (M 42), 2000, 2001, 6205 (M 13), 7000.
        XCTAssertEqual(try catalogueIDs(.ngcIC),
                       ["dso.NGC100", "dso.NGC101", "dso.M31", "dso.NGC891", "dso.M42", "dso.NGC2000", "dso.NGC2001",
                        "dso.M13", "dso.NGC7000"])
    }

    func testTheClustersListFollowsCollinderMelotteTrumplerStock() throws {
        XCTAssertEqual(try catalogueIDs(.clusters), ["dso.Cl399", "dso.Mel20", "dso.Tr14"])
        // By name: Alpha Persei Cluster, Coathanger, Trumpler 14.
        XCTAssertEqual(try catalogueIDs(.clusters, sort: .name), ["dso.Mel20", "dso.Cl399", "dso.Tr14"])
    }

    func testACatalogueListHoldsOnlyObjectsOfThatCatalogue() throws {
        let catalog = try ObjectsBuilderFixture.catalog()
        for catalogue in ObjectsCatalogueFilter.allCases where catalogue != .all {
            let ids = try catalogueIDs(catalogue)
            XCTAssertFalse(ids.isEmpty, catalogue.title)
            for id in ids {
                let object = try XCTUnwrap(catalog.object(id: id))
                XCTAssertTrue(catalogue.contains(object), "\(id) in \(catalogue.title)")
            }
        }
    }

    func testACatalogueListIsGroupedByTypeLikeTheBrowseList() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(grouping: .type, sort: .number, catalogue: .ngcIC))
        XCTAssertEqual(sections.map(\.kind), [.group(.galaxies), .group(.nebulae), .group(.clusters)])
        XCTAssertEqual(sections[0].objects.map(\.id), ["dso.M31", "dso.NGC891"])
        XCTAssertEqual(sections[1].objects.map(\.id), ["dso.M42", "dso.NGC7000"])
        XCTAssertEqual(sections[2].objects.map(\.id), ["dso.NGC100", "dso.NGC101", "dso.NGC2000", "dso.NGC2001", "dso.M13"])
    }

    func testACatalogueListAlsoTakesThePopularFilter() throws {
        let rows = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(sort: .number, catalogue: .ngcIC, popular: true))
        // M 31, M 42, M 13 and NGC 7000 are showpiece or prominent; the NGC 100 to 2001 objects are notable.
        XCTAssertEqual(rows, ["dso.M31", "dso.M42", "dso.M13", "dso.NGC7000"])
        XCTAssertEqual(try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(catalogue: .clusters, popular: true)), [])
    }

    func testACatalogueListAlsoTakesTheHideFaintFilter() throws {
        let rows = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(sort: .number, catalogue: .ngcIC, hideFaint: true))
        // NGC 891 (10.8) and NGC 2001 (10.1) are too faint.
        XCTAssertEqual(rows, ["dso.NGC100", "dso.NGC101", "dso.M31", "dso.M42", "dso.NGC2000", "dso.M13", "dso.NGC7000"])
    }

    func testACatalogueListAlsoTakesTheAboveHorizonFilter() throws {
        let rows = try ObjectsBuilderFixture.rows(
            ObjectsBuilderFixture.options(sort: .number, catalogue: .ngcIC, aboveHorizon: true),
            positions: ObjectsBuilderFixture.ngcPositions())
        XCTAssertEqual(rows, ["dso.NGC100", "dso.M31", "dso.M13"])
    }

    func testFavoritesAndRecentsFollowTheCatalogueChoice() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(sort: .number, catalogue: .messier),
            favorites: ["sun", "dso.M31", "dso.NGC891"], recents: ["dso.M42", "planet.mars"])
        XCTAssertEqual(sections.map(\.kind), [.favorites, .recent, .all])
        XCTAssertEqual(sections[0].objects.map(\.id), ["dso.M31"])
        XCTAssertEqual(sections[1].objects.map(\.id), ["dso.M42"])
    }
}

// MARK: - Order

final class ObjectsListBuilderOrderTests: XCTestCase {
    private func rows(_ sort: ObjectsSortOrder, positions: [String: ObjectSkyPosition] = [:],
                      catalogue: ObjectsCatalogueFilter = .all, favorites: [String] = []) throws -> [String] {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(sort: sort, catalogue: catalogue),
                                                          favorites: favorites, positions: positions)
        return sections.flatMap(\.objects).map(\.id)
    }

    func testNameOrderIsAlphabeticalWithNumbersInNumericOrder() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options())
        XCTAssertEqual(sections[0].objects.map(\.name), ObjectsBuilderFixture.browseNames)
        // The twins have the same name: the identifier decides.
        let twins = sections[0].objects.filter { $0.name == "Twin Cluster" }.map(\.id)
        XCTAssertEqual(twins, ["dso.NGC100", "dso.NGC101"])
    }

    func testNumberOrderPutsMessierFirstThenCaldwellNGCBarnardAndTheClusters() throws {
        let expected = [
            "dso.M13", "dso.M31", "dso.M42", "dso.NGC7000", "dso.NGC100", "dso.NGC101", "dso.NGC891", "dso.NGC2000",
            "dso.NGC2001", "dso.B33", "dso.Cl399",
            // No catalogue number: last, in name order.
            "star.hip1001", "star.hip1002", "star.hip1006", "special.galacticCenter", "star.hip1003", "planet.jupiter",
            "dso.ESO56-115", "planet.mars", "planet.mercury", "moon", "planet.neptune", "special.ncp", "planet.saturn",
            "special.scp", "sun", "planet.uranus", "planet.venus",
        ]
        XCTAssertEqual(try rows(.number), expected)
        XCTAssertEqual(expected.count, 28)
    }

    func testNumberOrderUsesTheFirstCatalogueInTheNumberingOrder() throws {
        // NGC 7000 is also Caldwell 20: Caldwell comes before NGC, so it follows the Messier objects and precedes NGC 100.
        let ids = try rows(.number)
        let caldwell = try XCTUnwrap(ids.firstIndex(of: "dso.NGC7000"))
        XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: "dso.M42")), caldwell)
        XCTAssertLessThan(caldwell, try XCTUnwrap(ids.firstIndex(of: "dso.NGC100")))
    }

    func testBrightnessOrderPutsTheBrightestFirstAndObjectsWithoutAMagnitudeLast() throws {
        // The Sun, the Moon and the planets have a current magnitude once positions are known.
        let expected = [
            "sun", "moon", "planet.venus", "planet.jupiter", "planet.saturn", "dso.ESO56-115", "star.hip1001",
            "planet.mars", "planet.mercury", "star.hip1002", "dso.M31", "dso.Cl399",
            // M 42 and NGC 7000 are both 4.0: name order decides.
            "dso.NGC7000", "dso.M42", "star.hip1003", "planet.uranus", "dso.M13",
            // The twins are both 7.0: name, then identifier.
            "dso.NGC100", "dso.NGC101", "planet.neptune", "dso.NGC2000", "dso.NGC2001", "star.hip1006", "dso.NGC891",
            // Without a magnitude: last, in name order.
            "special.galacticCenter", "dso.B33", "special.ncp", "special.scp",
        ]
        XCTAssertEqual(try rows(.brightness, positions: ObjectsBuilderFixture.solarSystemPositions()), expected)
        XCTAssertEqual(expected.count, 28)
    }

    func testBrightnessOrderOfTheObjectsWithCatalogMagnitudesDoesNotNeedPositions() throws {
        let ids = try rows(.brightness)
        let withMagnitude = [
            "dso.ESO56-115", "star.hip1001", "star.hip1002", "dso.M31", "dso.Cl399", "dso.NGC7000", "dso.M42",
            "star.hip1003", "dso.M13", "dso.NGC100", "dso.NGC101", "dso.NGC2000", "dso.NGC2001", "star.hip1006",
            "dso.NGC891",
        ]
        XCTAssertEqual(ids.filter { withMagnitude.contains($0) }, withMagnitude)
        // They come before the dark nebula, which has no magnitude at all.
        let lastWithMagnitude = try XCTUnwrap(ids.firstIndex(of: "dso.NGC891"))
        XCTAssertLessThan(lastWithMagnitude, try XCTUnwrap(ids.firstIndex(of: "dso.B33")))
        XCTAssertEqual(ids.count, 28)
    }

    func testBrightnessOrderUsesThePositionsMagnitudeOfACometInsteadOfNone() throws {
        let positions = [
            "comet.C/2099 A1": ObjectsBuilderFixture.position(20, magnitude: 1.0),
            "comet.C/2099 B2": ObjectsBuilderFixture.position(20, magnitude: 9.0),
        ]
        let ids = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(sort: .brightness), positions: positions,
                                                 smallBodies: true)
        let first = try XCTUnwrap(ids.firstIndex(of: "comet.C/2099 A1"))
        let second = try XCTUnwrap(ids.firstIndex(of: "comet.C/2099 B2"))
        XCTAssertEqual(first, 2, "after the LMC (0.4) and Alpha Test (0.5)")
        XCTAssertEqual(ids[first - 2], "dso.ESO56-115")
        XCTAssertEqual(ids[first - 1], "star.hip1001")
        XCTAssertLessThan(first, second)
        XCTAssertGreaterThan(second, try XCTUnwrap(ids.firstIndex(of: "dso.NGC101")))
        XCTAssertLessThan(second, try XCTUnwrap(ids.firstIndex(of: "dso.NGC2000")))
    }

    func testBrightnessOrderUsesTheCurrentMagnitudeOfTheSunAndThePlanets() throws {
        let positions = [
            "sun": ObjectsBuilderFixture.position(10, magnitude: -26.7),
            "planet.venus": ObjectsBuilderFixture.position(20, magnitude: -4.4),
            "planet.jupiter": ObjectsBuilderFixture.position(30, magnitude: -2.5),
        ]
        let ids = try rows(.brightness, positions: positions)
        XCTAssertEqual(Array(ids.prefix(5)), ["sun", "planet.venus", "planet.jupiter", "dso.ESO56-115", "star.hip1001"])
        XCTAssertEqual(ids.count, 28)
    }

    func testProminenceOrderStartsWithShowpiecesAndSortsEachLevelByBrightness() throws {
        let expected = [
            // Showpieces: by magnitude, then name for those without one.
            "sun", "moon", "planet.venus", "planet.jupiter", "planet.saturn", "dso.ESO56-115", "star.hip1001",
            "planet.mars", "planet.mercury", "dso.M31", "dso.M42", "planet.uranus", "planet.neptune",
            "special.galacticCenter", "special.ncp", "special.scp",
            // Prominent: Beta Test 2.5, NGC 7000 4.0, M 13 5.8, then the dark nebula without a magnitude.
            "star.hip1002", "dso.NGC7000", "dso.M13", "dso.B33",
            // Notable.
            "dso.Cl399", "star.hip1003", "dso.NGC100", "dso.NGC101", "dso.NGC2000", "dso.NGC2001", "dso.NGC891",
            // Obscure.
            "star.hip1006",
        ]
        XCTAssertEqual(try rows(.prominence, positions: ObjectsBuilderFixture.solarSystemPositions()), expected)
        XCTAssertEqual(expected.count, 28)
    }

    func testProminenceOrderKeepsLevelsApartWhateverTheMagnitudes() throws {
        let ids = try rows(.prominence)
        let levels = try ids.map { id -> Int in
            let catalog = try ObjectsBuilderFixture.catalog()
            return try XCTUnwrap(catalog.object(id: id)).prominence.rawValue
        }
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertEqual(ids.count, 28)
    }

    func testSortingIsWithinASectionWhenObjectsAreGrouped() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(grouping: .type, sort: .brightness))
        // The stars by magnitude, not by name.
        XCTAssertEqual(sections[1].objects.map(\.name), ["Alpha Test", "Beta Test", "Gamma Test", "Faint Named"])
        // The galaxies: the LMC (0.4), Andromeda (3.4), NGC 891 (10.8).
        XCTAssertEqual(sections[2].objects.map(\.name), ["Large Magellanic Cloud", "Andromeda Galaxy", "NGC 891"])
    }

    func testAltitudeOrderPutsTheHighestFirstAndObjectsWithoutAPositionLast() throws {
        let ids = try rows(.altitude, positions: ObjectsBuilderFixture.ngcPositions(), catalogue: .ngcIC)
        // M 13 and NGC 100 are both at 30 degrees: name order (Hercules Cluster, Twin Cluster).
        XCTAssertEqual(ids, ["dso.M31", "dso.M13", "dso.NGC100", "dso.NGC101", "dso.NGC891", "dso.M42", "dso.NGC2001",
                             "dso.NGC7000", "dso.NGC2000"])
    }

    func testRiseTimeOrderIsHighestUpFirstThenSoonestRisingThenTheRest() throws {
        let ids = try rows(.riseTime, positions: ObjectsBuilderFixture.ngcPositions(), catalogue: .ngcIC)
        // Up: M 31 (55), M 13 and NGC 100 (30, name order). Rising: NGC 891 and NGC 2001 (in 1 h, "NGC 891" first by the
        // numeric name order), NGC 101 (2 h), NGC 7000 (3 h). No rising: NGC 2000 (no position), M 42 (never rises).
        XCTAssertEqual(ids, ["dso.M31", "dso.M13", "dso.NGC100", "dso.NGC891", "dso.NGC2001", "dso.NGC101", "dso.NGC7000",
                             "dso.NGC2000", "dso.M42"])
    }

    func testRiseTimeTreatsAnObjectBehindTheSkylineAsNotUp() throws {
        var positions = ObjectsBuilderFixture.ngcPositions()
        // M 31 is above the geometric horizon but hidden by the skyline, rising in 30 minutes.
        positions["dso.M31"] = ObjectsBuilderFixture.position(
            20, rise: ObjectsBuilderFixture.reference.addingTimeInterval(1_800), isAbove: false)
        let ids = try rows(.riseTime, positions: positions, catalogue: .ngcIC)
        XCTAssertEqual(Array(ids.prefix(2)), ["dso.M13", "dso.NGC100"])
        XCTAssertEqual(ids[2], "dso.M31", "rises before NGC 891 and NGC 2001")
    }

    func testAltitudeAndRiseTimeOrdersFallBackToNameOrderWithoutAnyPositions() throws {
        let byName = try rows(.name)
        XCTAssertEqual(try rows(.altitude), byName)
        XCTAssertEqual(try rows(.riseTime), byName)
        let catalogueByName = try rows(.name, catalogue: .ngcIC)
        XCTAssertEqual(try rows(.altitude, catalogue: .ngcIC), catalogueByName)
        XCTAssertEqual(try rows(.riseTime, catalogue: .ngcIC), catalogueByName)
    }

    func testAltitudeOrderIsNotAFallbackOnceSomePositionExists() throws {
        let positions = ["planet.mars": ObjectsBuilderFixture.position(10)]
        let ids = try rows(.altitude, positions: positions)
        XCTAssertEqual(ids.first, "planet.mars")
        XCTAssertNotEqual(ids, try rows(.name))
    }

    func testTheOrderDoesNotDependOnTheOrderOfTheFavorites() throws {
        let favorites = ["dso.NGC891", "dso.M42", "planet.mars", "dso.M31", "star.hip1002", "dso.NGC100"]
        for sort in [ObjectsSortOrder.name, .number, .brightness, .prominence] {
            let forward = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(sort: sort), favorites: favorites)
            let backward = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(sort: sort),
                                                              favorites: favorites.reversed())
            XCTAssertEqual(forward[0].objects.map(\.id), backward[0].objects.map(\.id), "\(sort)")
        }
    }

    func testEqualBrightnessAmongObjectsOutsideTheIndexIsDecidedByIdentifier() throws {
        // Two unnamed 6.0 stars: neither is in the browse list, so they have no place in the name order.
        let one = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(sort: .brightness),
                                                     favorites: ["star.hip1007", "star.hip1005"])
        XCTAssertEqual(one[0].objects.map(\.id), ["star.hip1005", "star.hip1007"])
        let two = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(sort: .brightness),
                                                     favorites: ["star.hip1005", "star.hip1007"])
        XCTAssertEqual(two[0].objects.map(\.id), ["star.hip1005", "star.hip1007"])
    }

    func testFavoritesInNumberOrderPutObjectsWithoutANumberLast() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(sort: .number),
            favorites: ["dso.NGC891", "dso.M42", "planet.mars", "dso.M31"])
        XCTAssertEqual(sections[0].kind, .favorites)
        XCTAssertEqual(sections[0].objects.map(\.id), ["dso.M31", "dso.M42", "dso.NGC891", "planet.mars"])
    }

    func testFavoritesInProminenceOrderGoByLevelThenMagnitude() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(sort: .prominence),
            favorites: ["star.hip1003", "star.hip1002", "dso.M42", "star.hip1001"])
        XCTAssertEqual(sections[0].objects.map(\.id), ["star.hip1001", "dso.M42", "star.hip1002", "star.hip1003"])
    }
}

// MARK: - Favorites and recents

final class ObjectsListBuilderFavoritesTests: XCTestCase {
    func testFavoritesComeFirstInTheSortOrderWithoutRepeatsOrUnknownIdentifiers() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(),
            favorites: ["planet.venus", "dso.M31", "sun", "dso.M31", "dso.NOPE"])
        XCTAssertEqual(sections.map(\.kind), [.favorites, .all])
        XCTAssertEqual(sections[0].objects.map(\.id), ["dso.M31", "sun", "planet.venus"])
        XCTAssertEqual(sections[0].unavailable, [])
    }

    func testAnObjectThatIsAFavoriteStaysInTheMainListToo() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(), favorites: ["sun"])
        XCTAssertTrue(sections[1].objects.contains { $0.id == "sun" })
    }

    func testFavoritesIncludeObjectsThatTheBrowseListLeavesOutAndPlaceThemAfterTheOthers() throws {
        // HIP 1005 and HIP 1007 are not listed, so the name order does not know them.
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(),
            favorites: ["star.hip1005", "dso.M31", "star.hip1007", "dso.M13", "dso.Sh2-155"])
        // Sh2-155 is a deep-sky object, so it has a place in the order (Cave Nebula, between Andromeda and Hercules).
        XCTAssertEqual(sections[0].objects.map(\.id),
                       ["dso.M31", "dso.Sh2-155", "dso.M13", "star.hip1005", "star.hip1007"])
    }

    func testFiltersApplyToFavorites() throws {
        let favorites = ["dso.M31", "star.hip1003", "dso.NGC891", "star.hip1006"]
        let popular = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(popular: true), favorites: favorites)
        XCTAssertEqual(popular[0].objects.map(\.id), ["dso.M31"])
        let sharp = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(hideFaint: true), favorites: favorites)
        XCTAssertEqual(sharp[0].objects.map(\.id), ["dso.M31", "star.hip1003"])
    }

    func testNoFavoritesSectionAppearsWhenEveryFavoriteIsFilteredOut() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(popular: true),
                                                          favorites: ["star.hip1006"])
        XCTAssertEqual(sections.map(\.kind), [.all])
    }

    // MARK: Favorites without an orbit

    func testAFavoriteCometWithoutAnOrbitStaysAsUnavailable() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(), favorites: ["comet.12P", "dso.M31", "asteroid.4", "comet.12P"])
        XCTAssertEqual(sections.map(\.kind), [.favorites, .all])
        XCTAssertEqual(sections[0].objects.map(\.id), ["dso.M31"])
        XCTAssertEqual(sections[0].unavailable, ["comet.12P", "asteroid.4"])
    }

    func testAFavoritesSectionCanHoldOnlyUnavailableBodies() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(), favorites: ["comet.12P"])
        XCTAssertEqual(sections.first?.kind, .favorites)
        XCTAssertEqual(sections.first?.objects.count, 0)
        XCTAssertEqual(sections.first?.unavailable, ["comet.12P"])
    }

    func testACometTheCatalogKnowsIsNotUnavailable() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(), favorites: ["comet.C/2099 A1"], smallBodies: true)
        XCTAssertEqual(sections[0].objects.map(\.id), ["comet.C/2099 A1"])
        XCTAssertEqual(sections[0].unavailable, [])
    }

    func testUnavailableBodiesVanishWhenAFilterIsOn() throws {
        let favorites = ["comet.12P"]
        let popular = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(popular: true), favorites: favorites)
        XCTAssertFalse(popular.contains { $0.kind == .favorites })
        let catalogue = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(catalogue: .messier),
                                                           favorites: favorites)
        XCTAssertFalse(catalogue.contains { $0.kind == .favorites })
        let above = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(aboveHorizon: true), favorites: favorites,
                                                       positions: ["sun": ObjectsBuilderFixture.position(10)])
        XCTAssertFalse(above.contains { $0.kind == .favorites })
    }

    func testUnavailableBodiesStayWhenAboveHorizonHasNoPositionsToApply() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(aboveHorizon: true),
                                                          favorites: ["comet.12P"])
        XCTAssertEqual(sections.first?.kind, .favorites)
        XCTAssertEqual(sections.first?.unavailable, ["comet.12P"])
    }

    func testUnavailableBodiesStayWhenOnlyHideFaintIsOn() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(hideFaint: true),
                                                          favorites: ["asteroid.4"])
        XCTAssertEqual(sections.first?.unavailable, ["asteroid.4"])
    }

    func testOnlyCometAndAsteroidIdentifiersCanBeUnavailable() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(),
                                                          favorites: ["dso.NOPE", "star.hip999", "custom.1234"])
        XCTAssertEqual(sections.map(\.kind), [.all])
    }

    // MARK: Recents

    func testRecentsKeepTheirOrderWhateverTheSortOrderIs() throws {
        for sort in [ObjectsSortOrder.name, .brightness, .number, .prominence] {
            let sections = try ObjectsBuilderFixture.sections(
                ObjectsBuilderFixture.options(sort: sort), recents: ["planet.venus", "dso.M31", "sun", "planet.venus"])
            XCTAssertEqual(sections.map(\.kind), [.recent, .all], "\(sort)")
            XCTAssertEqual(sections[0].objects.map(\.id), ["planet.venus", "dso.M31", "sun"], "\(sort)")
        }
    }

    func testRecentsSkipUnknownIdentifiersAndAreFiltered() throws {
        let sections = try ObjectsBuilderFixture.sections(
            ObjectsBuilderFixture.options(popular: true), recents: ["dso.NOPE", "dso.NGC891", "dso.M42", "star.hip1003"])
        XCTAssertEqual(sections[0].kind, .recent)
        XCTAssertEqual(sections[0].objects.map(\.id), ["dso.M42"])
        XCTAssertEqual(sections[0].unavailable, [])
    }

    func testFavoritesPrecedeRecentsWhichPrecedeTheList() throws {
        let sections = try ObjectsBuilderFixture.sections(ObjectsBuilderFixture.options(grouping: .type),
                                                          favorites: ["sun"], recents: ["moon"])
        XCTAssertEqual(sections.map(\.kind), [.favorites, .recent, .group(.solarSystem), .group(.stars), .group(.galaxies),
                                              .group(.nebulae), .group(.clusters), .group(.special)])
    }

    // MARK: Positions not available yet

    func testNothingIsLostWhenPositionsHaveNotArrivedYet() throws {
        let withFilter = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(aboveHorizon: true),
                                                        favorites: ["sun"], recents: ["moon"])
        let without = try ObjectsBuilderFixture.rows(ObjectsBuilderFixture.options(), favorites: ["sun"], recents: ["moon"])
        XCTAssertEqual(withFilter, without)
    }
}

// MARK: - The index

final class ObjectsCatalogIndexTests: XCTestCase {
    func testTheListedObjectsAreInNameOrder() throws {
        let catalog = try ObjectsBuilderFixture.catalog()
        let index = ObjectsCatalogIndex(catalog: catalog)
        XCTAssertEqual(index.listed.map(\.name), ObjectsBuilderFixture.browseNames)
        XCTAssertEqual(index.listed.map(\.id), catalog.sorted(catalog.listedObjects, by: .name).map(\.id))
    }

    func testRanksFollowTheListedOrderAndAreDistinct() throws {
        let index = ObjectsCatalogIndex(catalog: try ObjectsBuilderFixture.catalog())
        let ranks = index.listed.map { index.rank(of: $0.id) }
        XCTAssertEqual(ranks, ranks.sorted())
        XCTAssertEqual(Set(ranks).count, ranks.count)
        XCTAssertTrue(ranks.allSatisfy { $0 < Int.max })
    }

    func testObscureDeepSkyObjectsHaveARankButAreNotListed() throws {
        let index = ObjectsCatalogIndex(catalog: try ObjectsBuilderFixture.catalog())
        for id in ["dso.Mel20", "dso.Tr14", "dso.Sh2-155", "dso.Sh2-129", "dso.LDN1622"] {
            XCTAssertLessThan(index.rank(of: id), Int.max, id)
            XCTAssertFalse(index.listed.contains { $0.id == id }, id)
        }
        // They sit where their names put them: Alpha Persei Cluster < Alpha Test, Beta Test < Cave Nebula < Coathanger.
        XCTAssertLessThan(index.rank(of: "dso.Mel20"), index.rank(of: "star.hip1001"))
        XCTAssertLessThan(index.rank(of: "star.hip1002"), index.rank(of: "dso.Sh2-155"))
        XCTAssertLessThan(index.rank(of: "dso.Sh2-155"), index.rank(of: "dso.Cl399"))
    }

    func testObjectsOutsideTheIndexComeLast() throws {
        let index = ObjectsCatalogIndex(catalog: try ObjectsBuilderFixture.catalog())
        XCTAssertEqual(index.rank(of: "star.hip1005"), Int.max, "an unlisted star")
        XCTAssertEqual(index.rank(of: "no.such.object"), Int.max)
        XCTAssertEqual(index.rank(of: ""), Int.max)
    }

    func testUnlistedSmallBodiesAreOutsideTheIndexAndListedOnesAreInIt() throws {
        let index = ObjectsCatalogIndex(catalog: try ObjectsBuilderFixture.catalog(smallBodies: true))
        XCTAssertEqual(index.rank(of: "comet.C/2099 C3"), Int.max)
        XCTAssertLessThan(index.rank(of: "comet.C/2099 A1"), Int.max)
        XCTAssertEqual(index.listed.count, 28 + 3)
    }
}
