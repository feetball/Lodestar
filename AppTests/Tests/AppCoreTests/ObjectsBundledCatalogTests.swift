import XCTest
import LodestarKit
@testable import AppCore

/// The Objects logic on the real bundled catalog (about 11 000 objects). The expectations are properties that hold for
/// any correct catalog (every listed object appears once, in its group, in name order; a catalogue list holds exactly the
/// catalogue's objects) and the counts that the LodestarKit tests pin down.
private enum ObjectsBundledFixture {
    static let loaded: Result<Catalog, Error> = Result { try Catalog.loadBundled() }

    static let boulder = Observer(location: GeographicLocation(latitude: 40, longitude: -105, elevation: 1600))
    /// 2026-10-21 03:00 UTC: 21:00 on the 20th in Colorado.
    static let evening = Date(timeIntervalSince1970: 1_792_551_600)

    static func options(grouping: ObjectsGrouping = ObjectsGrouping.none, sort: ObjectsSortOrder = .name,
                        catalogue: ObjectsCatalogueFilter = .all) -> ObjectsListOptions {
        var options = ObjectsListOptions()
        options.grouping = grouping
        options.sortOrder = sort
        options.catalogue = catalogue
        return options
    }
}

final class ObjectsBundledCatalogTests: XCTestCase {
    private func catalog() throws -> Catalog {
        switch ObjectsBundledFixture.loaded {
        case .success(let catalog): return catalog
        case .failure(let error): throw XCTSkip("The bundled catalog could not be loaded: \(error)")
        }
    }

    private func sections(_ options: ObjectsListOptions, in catalog: Catalog) -> [ObjectsListSection] {
        ObjectsListBuilder.sections(options: options, catalog: catalog, index: ObjectsCatalogIndex(catalog: catalog),
                                    favoriteIDs: [], recentIDs: [], positions: [:])
    }

    // MARK: Catalogue lists

    func testTheMessierListHoldsAll110ObjectsInCatalogueOrder() throws {
        let catalog = try catalog()
        let list = ObjectsCatalogueFilter.messier.objects(in: catalog)
        XCTAssertEqual(list.count, 110)
        XCTAssertEqual(list.first?.id, "dso.M1")
        XCTAssertEqual(list.map(\.id), catalog.objects(in: .messier).map(\.id))
        // M 1 to M 110.
        let numbers = list.map { object in object.catalogNumbers.first { $0.catalogue == .messier }?.number ?? 0 }
        XCTAssertEqual(numbers, Array(1...110))
    }

    func testTheBuilderListsTheMessierObjectsByNumberOrByName() throws {
        let catalog = try catalog()
        let list = ObjectsCatalogueFilter.messier.objects(in: catalog)
        let byNumber = sections(ObjectsBundledFixture.options(sort: .number, catalogue: .messier), in: catalog)
        XCTAssertEqual(byNumber.map(\.kind), [.all])
        XCTAssertEqual(byNumber[0].objects.map(\.id), list.map(\.id))
        let byName = sections(ObjectsBundledFixture.options(sort: .name, catalogue: .messier), in: catalog)
        XCTAssertEqual(byName[0].objects.map(\.id), catalog.sorted(list, by: .name).map(\.id))
    }

    func testTheCaldwellAndSharplessListsAreInNumberOrder() throws {
        let catalog = try catalog()
        for (filter, count) in [(ObjectsCatalogueFilter.caldwell, 109), (ObjectsCatalogueFilter.sharpless, 313)] {
            let list = filter.objects(in: catalog)
            XCTAssertEqual(list.count, count, filter.title)
            let rows = sections(ObjectsBundledFixture.options(sort: .number, catalogue: filter), in: catalog)
            XCTAssertEqual(rows.first?.objects.map(\.id), list.map(\.id), filter.title)
        }
    }

    func testEveryCatalogueListHoldsExactlyTheObjectsOfItsCatalogue() throws {
        let catalog = try catalog()
        for filter in ObjectsCatalogueFilter.allCases where filter != .all {
            let expected = filter.objects(in: catalog).map(\.id)
            XCTAssertFalse(expected.isEmpty, filter.title)
            let rows = sections(ObjectsBundledFixture.options(sort: .number, catalogue: filter), in: catalog)
                .flatMap(\.objects).map(\.id)
            XCTAssertEqual(rows.count, expected.count, filter.title)
            XCTAssertEqual(Set(rows), Set(expected), filter.title)
            XCTAssertEqual(Set(rows).count, rows.count, "\(filter.title): no object twice")
        }
    }

    func testTheCatalogueListsHoldObjectsThatTheBrowseListLeavesOut() throws {
        let catalog = try catalog()
        let browse = Set(sections(ObjectsBundledFixture.options(), in: catalog).flatMap(\.objects).map(\.id))
        for filter in [ObjectsCatalogueFilter.sharpless, .barnard, .lynds] {
            let unlisted = filter.objects(in: catalog).filter { !browse.contains($0.id) }
            XCTAssertFalse(unlisted.isEmpty, "\(filter.title) has obscure objects")
        }
    }

    // MARK: The browse list

    func testTheBrowseListHoldsEveryListedObjectOnceInItsGroupInNameOrder() throws {
        let catalog = try catalog()
        let result = sections(ObjectsListOptions(), in: catalog)
        let groups = ObjectGroup.allCases.filter { group in catalog.listedObjects.contains { $0.group == group } }
        XCTAssertEqual(result.map(\.kind), groups.map { ObjectsListSection.Kind.group($0) })
        let ids = result.flatMap(\.objects).map(\.id)
        XCTAssertEqual(ids.count, catalog.listedObjects.count)
        XCTAssertEqual(Set(ids), Set(catalog.listedObjects.map(\.id)))
        XCTAssertEqual(Set(ids).count, ids.count)
        for (section, group) in zip(result, groups) {
            XCTAssertTrue(section.objects.allSatisfy { $0.group == group }, section.title)
            XCTAssertEqual(section.objects.map(\.id), catalog.sorted(section.objects, by: .name).map(\.id), section.title)
        }
        XCTAssertEqual(result.first?.title, "Solar System")
    }

    func testTheIndexIsTheCatalogsNameOrderOfTheListedObjects() throws {
        let catalog = try catalog()
        let index = ObjectsCatalogIndex(catalog: catalog)
        XCTAssertEqual(index.listed.map(\.id), catalog.sorted(catalog.listedObjects, by: .name).map(\.id))
        // Every deep-sky object, listed or not, has a rank; the ranks of the listed objects follow the name order.
        for object in catalog.deepSkyObjects {
            XCTAssertLessThan(index.rank(of: object.id), Int.max, object.id)
        }
        let ranks = index.listed.map { index.rank(of: $0.id) }
        XCTAssertEqual(ranks, ranks.sorted())
    }

    func testThePopularListHoldsOnlyShowpiecesAndProminentObjects() throws {
        let catalog = try catalog()
        var options = ObjectsBundledFixture.options()
        options.showsOnlyPopular = true
        let rows = sections(options, in: catalog).flatMap(\.objects)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.prominence <= .prominent })
        let expected = catalog.listedObjects.filter { $0.prominence <= .prominent }
        XCTAssertEqual(rows.count, expected.count)
    }

    func testTheHideFaintListHoldsNoObjectFainterThanMagnitudeTen() throws {
        let catalog = try catalog()
        var options = ObjectsBundledFixture.options()
        options.hidesFaintObjects = true
        let rows = sections(options, in: catalog).flatMap(\.objects)
        XCTAssertTrue(rows.allSatisfy { ($0.magnitude ?? 0) <= 10.0 })
        let faint = catalog.listedObjects.filter { ($0.magnitude ?? 0) > 10.0 }
        XCTAssertEqual(rows.count, catalog.listedObjects.count - faint.count)
    }

    // MARK: Positions

    func testPositionsOfTheFirstListedObjectsAgreeWithTheirDeclinations() throws {
        let catalog = try catalog()
        let objects = Array(catalog.listedObjects.prefix(300))
        let positions = ObjectsPositionCalculator.positions(for: objects, observer: ObjectsBundledFixture.boulder,
                                                            date: ObjectsBundledFixture.evening)
        XCTAssertEqual(positions.count, objects.count)
        for object in objects {
            let position = try XCTUnwrap(positions[object.id], object.id)
            XCTAssertEqual(position.computedAt, ObjectsBundledFixture.evening)
            XCTAssertEqual(position.isAboveHorizon, position.altitude > 0, object.id)
            if position.neverRises {
                XCTAssertNil(position.nextRise, object.id)
                XCTAssertFalse(position.isAboveHorizon, object.id)
                XCTAssertFalse(position.noRiseInWindow, object.id)
            }
            guard case .fixed(let coordinate, _) = object.position else { continue }
            // A fixed object has a rising in the window or never rises; it is never "no rising in the window".
            XCTAssertFalse(position.noRiseInWindow, object.id)
            let declination = coordinate.declination
            if declination < -52 {
                XCTAssertTrue(position.neverRises, "\(object.id) at \(declination)")
            } else if declination > 52 {
                XCTAssertTrue(position.isAboveHorizon, "\(object.id) at \(declination)")
                XCTAssertNil(position.nextRise, object.id)
                XCTAssertFalse(position.neverRises, object.id)
            } else if abs(declination) < 45 {
                XCTAssertFalse(position.neverRises, "\(object.id) at \(declination)")
                XCTAssertNotNil(position.nextRise, "\(object.id) at \(declination)")
            }
        }
    }

    // MARK: A well-known object

    func testAndromedaAtDusk() throws {
        let catalog = try catalog()
        let andromeda = try XCTUnwrap(catalog.object(id: "dso.M31"))
        let point = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(ObjectsFormat.subtitle(of: andromeda, magnitude: nil), "Galaxy \u{00B7} Andromeda \u{00B7} mag 3\(point)4")
        XCTAssertEqual(ObjectsFormat.extraDesignation(of: andromeda), "M 31")
        XCTAssertEqual(ObjectsFormat.designationsLine(of: andromeda)?.hasPrefix("M 31 \u{00B7} NGC 224"), true)

        let current = ObjectDetailCalculator.current(of: andromeda, observer: ObjectsBundledFixture.boulder,
                                                     at: ObjectsBundledFixture.evening)
        let frame = SkyFrame(date: ObjectsBundledFixture.evening, observer: ObjectsBundledFixture.boulder)
        XCTAssertEqual(current.horizontal, frame.horizontal(of: andromeda, refraction: true))
        XCTAssertGreaterThan(current.horizontal.altitude, 10, "Andromeda is up at 21:00 in October")
        XCTAssertEqual(current.angularSize, andromeda.angularSize)
    }

    func testAndromedaCulminatesNearTheZenithAtNightFromColorado() throws {
        let catalog = try catalog()
        let andromeda = try XCTUnwrap(catalog.object(id: "dso.M31"))
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let context = ObserverContext(observer: ObjectsBundledFixture.boulder, timeZone: zone, name: "Test",
                                      source: .device, horizontalAccuracy: nil, timestamp: nil, horizon: nil)
        let night = ObjectDetailCalculator.night(of: andromeda, context: context, containing: ObjectsBundledFixture.evening)
        // M 31 is at declination +41.3 degrees, 1.3 degrees north of the zenith of latitude 40: it culminates at about
        // 88.7 degrees.
        let transitAltitude = try XCTUnwrap(night.transitAltitude)
        XCTAssertEqual(transitAltitude, 88.7, accuracy: 0.5)
        let best = try XCTUnwrap(night.bestInDarkness)
        XCTAssertEqual(best.altitude, transitAltitude, accuracy: 0.01)
        let darkness = try XCTUnwrap(night.darkness)
        XCTAssertTrue(darkness.contains(best.date))
        XCTAssertEqual(night.events.circumstance, .normal)
    }
}
