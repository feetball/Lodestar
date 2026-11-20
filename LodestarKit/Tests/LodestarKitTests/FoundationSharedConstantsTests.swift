import XCTest
@testable import LodestarKit

/// The constants that have one definition each, and the places that used to spell them again.
final class FoundationSharedConstantsTests: XCTestCase {
    // MARK: Sidereal rate

    func testTheSiderealRateIsTheSameNumberEverywhere() {
        XCTAssertEqual(SiderealTime.degreesPerDay, 360.985_647_366_29)
        XCTAssertEqual(SiderealTime.degreesPerSecond, 360.985_647_366_29 / JulianDate.secondsPerDay)
        // The mount's rate was once written out as its own division; it is the same value to the last bit.
        XCTAssertEqual(MountNudgeRate.siderealDegreesPerSecond, 360.98564736629 / 86_400.0)
        XCTAssertEqual(MountNudgeRate.siderealDegreesPerSecond, SiderealTime.degreesPerSecond)
        XCTAssertEqual(SkyWatcherSky.siderealDegreesPerSecond, SiderealTime.degreesPerSecond)
    }

    func testGreenwichSiderealTimeAdvancesAtTheSiderealRate() {
        let start = JulianDate(ut: JulianDate.j2000, deltaT: 64)
        let later = JulianDate(ut: JulianDate.j2000 + 3_600 / JulianDate.secondsPerDay, deltaT: 64)
        XCTAssertEqual(SiderealTime.greenwichMean(later) - SiderealTime.greenwichMean(start),
                       SiderealTime.degreesPerSecond * 3_600, accuracy: 1e-5)
    }

    func testTheFlipWindowRunsAtTheSiderealRate() throws {
        let window = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 0, limitDegrees: 15))
        XCTAssertEqual(window.secondsUntilLimit, 15 / SiderealTime.degreesPerSecond)
    }

    // MARK: Galactic Centre

    func testTheCatalogsMilkyWayCoreIsWhereThePlannersLookForIt() throws {
        let catalog = try CatalogFixture.catalog()
        let center = try XCTUnwrap(catalog.object(id: "special.galacticCenter"))
        guard case .fixed(let coordinate, nil) = center.position else { return XCTFail("fixed position expected") }
        XCTAssertEqual(coordinate, MilkyWayCoreVisibility.galacticCentre)
        // Sagittarius A*, 17h 45m 40.04s and −29° 00′ 28.1″, as the catalog has always spelled it.
        XCTAssertEqual(coordinate, EquatorialCoordinate(rightAscensionHours: 17.0 + 45.0 / 60 + 40.04 / 3600,
                                                        declination: -(29.0 + 28.1 / 3600)))
    }
}
