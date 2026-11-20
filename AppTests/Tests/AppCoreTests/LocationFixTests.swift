import CoreLocation
import LodestarKit
import XCTest
@testable import AppCore

final class LocationFixTests: XCTestCase {
    private func fix(_ latitude: Double, _ longitude: Double, accuracy: Double = 10.0, altitude: Double = 1600.0,
                     verticalAccuracy: Double = 5.0) -> LocationFix {
        LocationFix(latitude: latitude, longitude: longitude, altitude: altitude, horizontalAccuracy: accuracy,
                    verticalAccuracy: verticalAccuracy, timestamp: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: Distance

    func testADegreeOfLatitudeIsAbout111Kilometres() {
        XCTAssertEqual(fix(40.0, -105.0).distance(to: fix(41.0, -105.0)), 111_195.0, accuracy: 100.0)
    }

    func testDistanceIsSymmetricAndZeroToItself() {
        let a = fix(39.7, -105.0), b = fix(-33.9, 151.2)
        XCTAssertEqual(a.distance(to: a), 0.0, accuracy: 1e-9)
        XCTAssertEqual(a.distance(to: b), b.distance(to: a), accuracy: 1e-6)
    }

    func testDistanceAcrossTheDateLineIsShort() {
        XCTAssertEqual(fix(0.0, 179.5).distance(to: fix(0.0, -179.5)), 111_195.0, accuracy: 100.0)
    }

    // MARK: Core Location samples

    func testACoreLocationSampleBecomesAFix() throws {
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 39.7, longitude: -105.0), altitude: 1600.0,
                                  horizontalAccuracy: 12.0, verticalAccuracy: 8.0, timestamp: Date(timeIntervalSince1970: 5))
        let converted = try XCTUnwrap(LocationFix(location))
        XCTAssertEqual(converted.latitude, 39.7, accuracy: 1e-9)
        XCTAssertEqual(converted.longitude, -105.0, accuracy: 1e-9)
        XCTAssertEqual(converted.altitude, 1600.0, accuracy: 1e-9)
        XCTAssertEqual(converted.horizontalAccuracy, 12.0, accuracy: 1e-9)
        XCTAssertEqual(converted.verticalAccuracy, 8.0, accuracy: 1e-9)
        XCTAssertEqual(converted.timestamp, Date(timeIntervalSince1970: 5))
    }

    func testASampleWithoutAPositionIsRejected() {
        let invalid = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 39.7, longitude: -105.0), altitude: 0.0,
                                 horizontalAccuracy: -1.0, verticalAccuracy: -1.0, timestamp: Date())
        XCTAssertNil(LocationFix(invalid))
    }

    // MARK: The stable location

    func testTheFirstFixIsAdopted() throws {
        var filter = StableLocationFilter()
        let location = try XCTUnwrap(filter.accept(fix(39.7, -105.0)))
        XCTAssertEqual(location.latitude, 39.7, accuracy: 1e-9)
        XCTAssertEqual(location.longitude, -105.0, accuracy: 1e-9)
        XCTAssertEqual(location.elevation, 1600.0, accuracy: 1e-9)
    }

    func testJitterIsIgnored() {
        var filter = StableLocationFilter()
        XCTAssertNotNil(filter.accept(fix(39.7, -105.0)))
        // 0.0005 degrees of latitude are about 55 m, well under the 250 m threshold.
        XCTAssertNil(filter.accept(fix(39.7005, -105.0)))
    }

    func testMovingFartherThanTheThresholdReplacesTheLocation() throws {
        var filter = StableLocationFilter()
        XCTAssertNotNil(filter.accept(fix(39.7, -105.0)))
        // 0.005 degrees of latitude are about 555 m.
        let moved = try XCTUnwrap(filter.accept(fix(39.705, -105.0)))
        XCTAssertEqual(moved.latitude, 39.705, accuracy: 1e-9)
    }

    func testTheThresholdIsMeasuredFromTheLastAdoptedFix() {
        var filter = StableLocationFilter()
        XCTAssertNotNil(filter.accept(fix(39.7, -105.0)))
        // Each step is about 100 m, so no single step passes the threshold, but the third is 300 m from the adopted fix.
        XCTAssertNil(filter.accept(fix(39.7009, -105.0)))
        XCTAssertNil(filter.accept(fix(39.7018, -105.0)))
        XCTAssertNotNil(filter.accept(fix(39.7027, -105.0)))
    }

    func testAMuchMoreAccurateFixReplacesTheLocationEvenInTheSamePlace() {
        var filter = StableLocationFilter()
        XCTAssertNotNil(filter.accept(fix(39.7, -105.0, accuracy: 3_000.0)))
        // Half the radius would not be enough (it must also gain 500 m), but this fix is a third of it and 2 km better.
        XCTAssertNotNil(filter.accept(fix(39.7, -105.0, accuracy: 1_000.0)))
    }

    func testASlightlyMoreAccurateFixIsIgnored() {
        var filter = StableLocationFilter()
        XCTAssertNotNil(filter.accept(fix(39.7, -105.0, accuracy: 3_000.0)))
        XCTAssertNil(filter.accept(fix(39.7, -105.0, accuracy: 2_500.0)))
    }

    func testAnImprovementOfLessThan500MetresIsIgnoredEvenWhenItIsAFactorOfTwo() {
        var filter = StableLocationFilter()
        XCTAssertNotNil(filter.accept(fix(39.7, -105.0, accuracy: 800.0)))
        XCTAssertNil(filter.accept(fix(39.7, -105.0, accuracy: 350.0)))
    }

    func testAnInvalidAltitudeGivesElevationZero() throws {
        var filter = StableLocationFilter()
        let location = try XCTUnwrap(filter.accept(fix(39.7, -105.0, altitude: 1600.0, verticalAccuracy: -1.0)))
        XCTAssertEqual(location.elevation, 0.0, accuracy: 1e-9)
    }

    func testAnAltitudeOutOfRangeIsClamped() throws {
        var filter = StableLocationFilter()
        let location = try XCTUnwrap(filter.accept(fix(39.7, -105.0, altitude: 50_000.0, verticalAccuracy: 3.0)))
        XCTAssertEqual(location.elevation, GeographicLocation.elevationRange.upperBound, accuracy: 1e-9)
    }

    func testAFixWithAnImpossiblePositionIsNotAdoptedAndDoesNotBecomeTheAnchor() throws {
        var filter = StableLocationFilter()
        XCTAssertNil(filter.accept(fix(95.0, -105.0)))
        // The bad fix did not count as the first one, so the next valid fix is adopted.
        XCTAssertNotNil(filter.accept(fix(39.7, -105.0)))
    }
}
