import XCTest
import LodestarKit
@testable import AppCore

final class ObjectsListOptionsTests: XCTestCase {
    // MARK: Grouping

    func testGroupingCasesAreInMenuOrderWithTheirRawValuesAsIdentifiers() {
        XCTAssertEqual(ObjectsGrouping.allCases, [.type, .prominence, ObjectsGrouping.none])
        XCTAssertEqual(ObjectsGrouping.allCases.map(\.rawValue), ["type", "prominence", "none"])
        XCTAssertEqual(ObjectsGrouping.allCases.map(\.id), ["type", "prominence", "none"])
    }

    func testGroupingTitlesAndImages() {
        XCTAssertEqual(ObjectsGrouping.allCases.map(\.title), ["Object Type", "Prominence", "No Grouping"])
        XCTAssertEqual(ObjectsGrouping.allCases.map(\.systemImage), ["square.grid.2x2", "star.circle", "list.bullet"])
    }

    func testGroupingCanBeRestoredFromItsRawValue() {
        XCTAssertEqual(ObjectsGrouping(rawValue: "prominence"), .prominence)
        XCTAssertEqual(ObjectsGrouping(rawValue: "none"), ObjectsGrouping.none)
        XCTAssertNil(ObjectsGrouping(rawValue: "Prominence"))
        XCTAssertNil(ObjectsGrouping(rawValue: ""))
    }

    // MARK: Sort order

    func testSortOrdersAreInMenuOrderWithTheirRawValuesAsIdentifiers() {
        XCTAssertEqual(ObjectsSortOrder.allCases, [.name, .number, .brightness, .prominence, .altitude, .riseTime])
        XCTAssertEqual(ObjectsSortOrder.allCases.map(\.rawValue),
                       ["name", "number", "brightness", "prominence", "altitude", "riseTime"])
        XCTAssertEqual(ObjectsSortOrder.allCases.map(\.id), ObjectsSortOrder.allCases.map(\.rawValue))
    }

    func testSortOrderTitles() {
        XCTAssertEqual(ObjectsSortOrder.allCases.map(\.title),
                       ["Name", "Catalogue Number", "Brightness", "Prominence", "Altitude Now", "Rise Time"])
    }

    func testSortOrderImages() {
        XCTAssertEqual(ObjectsSortOrder.allCases.map(\.systemImage),
                       ["textformat", "number", "sparkle", "star.circle", "arrow.up.to.line", "sunrise"])
    }

    func testOnlyAltitudeAndRiseTimeNeedSkyPositions() {
        XCTAssertEqual(ObjectsSortOrder.allCases.filter(\.needsSkyPositions), [.altitude, .riseTime])
        XCTAssertFalse(ObjectsSortOrder.name.needsSkyPositions)
        XCTAssertFalse(ObjectsSortOrder.number.needsSkyPositions)
        XCTAssertFalse(ObjectsSortOrder.brightness.needsSkyPositions)
        XCTAssertFalse(ObjectsSortOrder.prominence.needsSkyPositions)
    }

    func testSortOrderCanBeRestoredFromItsRawValue() {
        XCTAssertEqual(ObjectsSortOrder(rawValue: "riseTime"), .riseTime)
        XCTAssertNil(ObjectsSortOrder(rawValue: "rise time"))
    }

    // MARK: Options

    func testTheDefaultOptionsGroupByTypeInNameOrderWithNoFilters() {
        let options = ObjectsListOptions()
        XCTAssertEqual(options.grouping, .type)
        XCTAssertEqual(options.sortOrder, .name)
        XCTAssertFalse(options.showsOnlyAboveHorizon)
        XCTAssertFalse(options.hidesFaintObjects)
        XCTAssertFalse(options.showsOnlyPopular)
        XCTAssertEqual(options.catalogue, .all)
        XCTAssertFalse(options.isCustomized)
    }

    func testTheFilterLimits() {
        XCTAssertEqual(ObjectsListOptions.faintMagnitudeLimit, 10.0)
        XCTAssertEqual(ObjectsListOptions.popularProminence, .prominent)
    }

    func testEachMenuOptionMakesTheListCustomized() {
        var grouping = ObjectsListOptions()
        grouping.grouping = .prominence
        XCTAssertTrue(grouping.isCustomized)

        var noGrouping = ObjectsListOptions()
        noGrouping.grouping = ObjectsGrouping.none
        XCTAssertTrue(noGrouping.isCustomized)

        var sort = ObjectsListOptions()
        sort.sortOrder = .brightness
        XCTAssertTrue(sort.isCustomized)

        var above = ObjectsListOptions()
        above.showsOnlyAboveHorizon = true
        XCTAssertTrue(above.isCustomized)

        var faint = ObjectsListOptions()
        faint.hidesFaintObjects = true
        XCTAssertTrue(faint.isCustomized)

        var popular = ObjectsListOptions()
        popular.showsOnlyPopular = true
        XCTAssertTrue(popular.isCustomized)
    }

    func testTheCatalogueChoiceAloneDoesNotCustomizeTheMenu() {
        for catalogue in ObjectsCatalogueFilter.allCases {
            var options = ObjectsListOptions()
            options.catalogue = catalogue
            XCTAssertFalse(options.isCustomized, catalogue.title)
        }
    }

    func testACatalogueDoesNotHideAnotherCustomOption() {
        var options = ObjectsListOptions()
        options.catalogue = .messier
        options.showsOnlyPopular = true
        XCTAssertTrue(options.isCustomized)
    }

    func testChangingAnOptionBackRestoresTheDefault() {
        var options = ObjectsListOptions()
        options.sortOrder = .altitude
        XCTAssertTrue(options.isCustomized)
        options.sortOrder = .name
        XCTAssertFalse(options.isCustomized)
    }

    func testOptionsAreEquatable() {
        XCTAssertEqual(ObjectsListOptions(), ObjectsListOptions())
        var changed = ObjectsListOptions()
        changed.catalogue = .caldwell
        XCTAssertNotEqual(changed, ObjectsListOptions())
        var other = ObjectsListOptions()
        other.hidesFaintObjects = true
        XCTAssertNotEqual(other, ObjectsListOptions())
        XCTAssertNotEqual(other, changed)
    }
}
