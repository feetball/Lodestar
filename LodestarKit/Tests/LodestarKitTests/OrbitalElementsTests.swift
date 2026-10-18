import XCTest
@testable import LodestarKit

final class OrbitalElementsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_792_294_095.076416)

    private func make(
        name: String? = "TEST",
        catalogNumber: Int = 12345,
        classification: Character = "U",
        epoch: Date? = nil,
        meanMotion: Double = 15.5,
        eccentricity: Double = 0.001,
        inclination: Double = 51.6,
        node: Double = 10.0,
        argument: Double = 20.0,
        anomaly: Double = 30.0,
        ephemerisType: Int = 0,
        elementSetNumber: Int = 1,
        revolutions: Int = 2,
        bstar: Double = 0.0001,
        ndot: Double = 0.0,
        nddot: Double = 0.0
    ) throws -> OrbitalElements {
        try OrbitalElements(
            name: name, catalogNumber: catalogNumber, classification: classification, epoch: epoch ?? self.epoch,
            meanMotion: meanMotion, eccentricity: eccentricity, inclination: inclination,
            rightAscensionOfAscendingNode: node, argumentOfPericenter: argument, meanAnomaly: anomaly,
            ephemerisType: ephemerisType, elementSetNumber: elementSetNumber, revolutionNumberAtEpoch: revolutions,
            bstar: bstar, meanMotionDot: ndot, meanMotionDdot: nddot
        )
    }

    private func outOfRangeField(_ body: () throws -> OrbitalElements) -> String? {
        do {
            _ = try body()
            return nil
        } catch ElementSetError.valueOutOfRange(let field, _) {
            return field
        } catch {
            return nil
        }
    }

    private func invalidField(_ body: () throws -> OrbitalElements) -> String? {
        do {
            _ = try body()
            return nil
        } catch ElementSetError.invalidField(let field, _) {
            return field
        } catch {
            return nil
        }
    }

    func testCreateKeepsTheValuesAndComputesTheEpochLikeTheReference() throws {
        let elements = try make()
        XCTAssertEqual(elements.name, "TEST")
        XCTAssertEqual(elements.catalogNumber, 12345)
        XCTAssertEqual(elements.meanMotion, 15.5, accuracy: 0.0)
        XCTAssertEqual(elements.epoch.timeIntervalSince1970, epoch.timeIntervalSince1970, accuracy: 1e-6)
        // Days since 1949-12-31T00:00Z: 1970-01-01T00:00Z is day 7306 of that scale.
        XCTAssertEqual(elements.sgp4EpochDays, 1_792_294_095.076416 / 86_400.0 + 7_306.0, accuracy: 1e-9)
        XCTAssertEqual(2_433_281.5 + elements.sgp4EpochDays, elements.epochJulianDay + elements.epochJulianDayFraction, accuracy: 1e-9)
        XCTAssertEqual(try make(), try make())
        XCTAssertEqual(try make().hashValue, try make().hashValue)
    }

    func testEveryFieldIsValidated() {
        XCTAssertEqual(outOfRangeField { try make(catalogNumber: -1) }, "NORAD_CAT_ID")
        XCTAssertEqual(outOfRangeField { try make(catalogNumber: 1_000_000_000) }, "NORAD_CAT_ID")
        XCTAssertEqual(outOfRangeField { try make(meanMotion: 0.0) }, "MEAN_MOTION")
        XCTAssertEqual(outOfRangeField { try make(meanMotion: 100.0) }, "MEAN_MOTION")
        XCTAssertEqual(outOfRangeField { try make(meanMotion: .nan) }, "MEAN_MOTION")
        XCTAssertEqual(outOfRangeField { try make(eccentricity: 1.0) }, "ECCENTRICITY")
        XCTAssertEqual(outOfRangeField { try make(eccentricity: -0.1) }, "ECCENTRICITY")
        XCTAssertEqual(outOfRangeField { try make(inclination: 180.1) }, "INCLINATION")
        XCTAssertEqual(outOfRangeField { try make(inclination: .infinity) }, "INCLINATION")
        XCTAssertEqual(outOfRangeField { try make(node: -0.1) }, "RA_OF_ASC_NODE")
        XCTAssertEqual(outOfRangeField { try make(argument: 360.1) }, "ARG_OF_PERICENTER")
        XCTAssertEqual(outOfRangeField { try make(anomaly: .nan) }, "MEAN_ANOMALY")
        XCTAssertEqual(outOfRangeField { try make(bstar: 10.5) }, "BSTAR")
        XCTAssertEqual(outOfRangeField { try make(ndot: 101.0) }, "MEAN_MOTION_DOT")
        XCTAssertEqual(outOfRangeField { try make(nddot: .nan) }, "MEAN_MOTION_DDOT")
        XCTAssertEqual(outOfRangeField { try make(ephemerisType: 10) }, "EPHEMERIS_TYPE")
        XCTAssertEqual(outOfRangeField { try make(elementSetNumber: 100_000) }, "ELEMENT_SET_NO")
        XCTAssertEqual(outOfRangeField { try make(revolutions: -1) }, "REV_AT_EPOCH")
        XCTAssertEqual(outOfRangeField { try make(epoch: Date(timeIntervalSince1970: -600_000_000.0)) }, "EPOCH")  // 1951
    }

    func testBoundaryValuesAreAccepted() throws {
        _ = try make(meanMotion: 99.99999999, eccentricity: 0.0, inclination: 180.0, node: 360.0, argument: 360.0, anomaly: 360.0)
        _ = try make(ephemerisType: 9, elementSetNumber: 99_999, revolutions: 9_999_999, bstar: -10.0, ndot: -100.0, nddot: 100.0)
        _ = try make(catalogNumber: 999_999_999, classification: "Z")
    }

    func testClassificationMustBeAnUpperCaseLetter() {
        for bad in Array("u1 \u{00dc}") {
            XCTAssertEqual(invalidField { try make(classification: bad) }, "CLASSIFICATION_TYPE", String(bad))
        }
    }

    func testEpochsMustBeInTheSupportedYears() throws {
        _ = try make(epoch: Date(timeIntervalSince1970: -400_000_000.0))  // 1957-05
        _ = try make(epoch: Date(timeIntervalSince1970: 4_070_000_000.0))  // 2098
        for seconds in [-500_000_000.0, 4_200_000_000.0, 1.0e12] {
            XCTAssertEqual(outOfRangeField { try make(epoch: Date(timeIntervalSince1970: seconds)) }, "EPOCH")
        }
    }

    func testNamesAndDesignatorsAreSanitized() throws {
        XCTAssertNil(try make(name: nil).name)
        XCTAssertNil(try make(name: "\u{00}\u{01}  ").name)
        XCTAssertEqual(try make(name: " A\u{03}B ").name, "AB")
        XCTAssertEqual(try make(name: String(repeating: "N", count: 81)).name?.utf16.count, 80)
        let designator = try OrbitalElements(
            objectId: "1998-067A\n", catalogNumber: 1, epoch: epoch, meanMotion: 15.0, eccentricity: 0.0,
            inclination: 1.0, rightAscensionOfAscendingNode: 1.0, argumentOfPericenter: 1.0, meanAnomaly: 1.0
        )
        XCTAssertEqual(designator.objectId, "1998-067A")
    }

    func testAgeIsSignedAndInDays() throws {
        let elements = try make()
        XCTAssertEqual(elements.ageDays(epoch), 0.0, accuracy: 1e-9)
        XCTAssertEqual(elements.ageDays(epoch.addingTimeInterval(129_600.0)), 1.5, accuracy: 1e-9)
        XCTAssertEqual(elements.ageDays(epoch.addingTimeInterval(-172_800.0)), -2.0, accuracy: 1e-9)
    }

    func testCalendarArithmetic() {
        XCTAssertEqual(ElementCalendar.daysFromCivil(year: 1970, month: 1, day: 1), 0)
        XCTAssertEqual(ElementCalendar.daysFromCivil(year: 2000, month: 3, day: 1), 11_017)
        XCTAssertEqual(ElementCalendar.daysFromCivil(year: 1969, month: 12, day: 31), -1)
        XCTAssertEqual(ElementCalendar.daysFromCivil(year: 2025, month: 10, day: 18), 20_379)
        var day: Int64 = -20_000
        while day < 30_000 {
            let civil = ElementCalendar.civilFromDays(day)
            XCTAssertEqual(day, ElementCalendar.daysFromCivil(year: civil.year, month: civil.month, day: civil.day))
            XCTAssertTrue((1...ElementCalendar.daysInMonth(year: civil.year, month: civil.month)).contains(civil.day))
            day += 7
        }
        XCTAssertTrue(ElementCalendar.isLeapYear(2000))
        XCTAssertFalse(ElementCalendar.isLeapYear(1900))
        XCTAssertTrue(ElementCalendar.isLeapYear(2024))
        XCTAssertFalse(ElementCalendar.isLeapYear(2026))
        XCTAssertEqual(ElementCalendar.daysInMonth(year: 2024, month: 2), 29)
        XCTAssertEqual(ElementCalendar.daysInMonth(year: 2026, month: 2), 28)
        XCTAssertEqual(ElementCalendar.daysInMonth(year: 2026, month: 11), 30)
    }

    func testJulianDayAndDayOfYearFollowTheReference() {
        let noon = ElementCalendar.julianDay(year: 2000, month: 1, day: 1, hour: 12, minute: 0, second: 0.0)
        XCTAssertEqual(noon.day, 2_451_544.5, accuracy: 0.0)
        XCTAssertEqual(noon.fraction, 0.5, accuracy: 0.0)
        let monthDayTime = ElementCalendar.monthDayTime(year: 2000, days: 60.5)
        XCTAssertEqual([monthDayTime.month, monthDayTime.day, monthDayTime.hour, monthDayTime.minute], [2, 29, 12, 0])
        let first = ElementCalendar.monthDayTime(year: 2026, days: 1.0)
        XCTAssertEqual([first.month, first.day, first.hour, first.minute], [1, 1, 0, 0])
        let last = ElementCalendar.monthDayTime(year: 2026, days: 365.75)
        XCTAssertEqual([last.month, last.day, last.hour, last.minute], [12, 31, 18, 0])
        let leapEnd = ElementCalendar.monthDayTime(year: 2024, days: 366.25)
        XCTAssertEqual([leapEnd.month, leapEnd.day, leapEnd.hour], [12, 31, 6])
    }
}
