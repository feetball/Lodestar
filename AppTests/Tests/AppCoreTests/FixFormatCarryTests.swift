import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Text that rounds up to the next unit has to carry into it: 59.994 arcminutes are a degree, not "60′"; 359.9996° of right
/// ascension is the start of the next turn, not "360.000°"; 999.5 m are a kilometre, not "1000 m".
final class FixFormatCarryTests: XCTestCase {
    private let degree = "\u{00B0}"
    private let arcminute = "\u{2032}"
    private let arcsecond = "\u{2033}"
    private let noBreakSpace = "\u{00A0}"
    private let plusMinus = "\u{00B1}"

    private func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    // MARK: Separation

    func testASeparationOfAlmostADegreeCarriesIntoDegrees() {
        // 0.9999 degrees are 59.994 arcminutes, which round to 60: a whole degree, not "60′".
        XCTAssertEqual(AppFormat.separation(0.9999), "1.0" + degree)
        // 59.502 arcminutes round to 60 as well.
        XCTAssertEqual(AppFormat.separation(0.9917), "1.0" + degree)
        // The sign is dropped, as for every separation.
        XCTAssertEqual(AppFormat.separation(-0.9999), "1.0" + degree)
    }

    func testASeparationJustUnderTheCarryStaysInArcminutes() {
        // 59.49 arcminutes round to 59.
        XCTAssertEqual(AppFormat.separation(0.9915), "59" + arcminute)
        XCTAssertEqual(AppFormat.separation(0.99), "59" + arcminute)
    }

    func testASeparationOfAlmostAnArcminuteCarriesIntoArcminutes() {
        // 0.016666 degrees are 59.9976 arcseconds, which round to 60: one arcminute, not "60″".
        XCTAssertEqual(AppFormat.separation(0.016666), "1" + arcminute)
        // 0.01655 degrees are 59.58 arcseconds.
        XCTAssertEqual(AppFormat.separation(0.01655), "1" + arcminute)
        XCTAssertEqual(AppFormat.separation(-0.016666), "1" + arcminute)
    }

    func testASeparationJustUnderTheArcsecondCarryStaysInArcseconds() {
        // 59.472 arcseconds round to 59.
        XCTAssertEqual(AppFormat.separation(0.01652), "59" + arcsecond)
        XCTAssertEqual(AppFormat.separation(0.0165), "59" + arcsecond)
    }

    func testAnAimAngleOfAlmostADegreeCarriesIntoDegrees() {
        // `AimFormat.angle` hands everything below one degree to `AppFormat.separation`.
        XCTAssertEqual(AimFormat.angle(0.9999), "1.0" + degree)
        XCTAssertEqual(AimFormat.angle(-0.9999), "1.0" + degree)
        XCTAssertEqual(AimFormat.angle(0.016666), "1" + arcminute)
    }

    // MARK: Right ascension

    func testADecimalRightAscensionJustBelowAFullTurnWrapsToZero() {
        // 359.9996 degrees are valid (below 360) but round to 360.000 at three decimals.
        let carried = EquatorialCoordinate(rightAscension: 359.9996, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(carried, style: .decimal), "0.000" + degree)
        // 359.9994 degrees do not.
        let notCarried = EquatorialCoordinate(rightAscension: 359.9994, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(notCarried, style: .decimal), "359.999" + degree)
    }

    func testTheTwoRightAscensionStylesAgreeAtTheTurn() {
        // The sexagesimal style already carries 23h 59m 59.99s to 00h.
        let coordinate = EquatorialCoordinate(rightAscension: 359.9996, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(coordinate, style: .sexagesimal), "00h 00m 00.0s")
        XCTAssertEqual(AppFormat.rightAscension(coordinate, style: .decimal), "0.000" + degree)
    }

    // MARK: Accuracy

    func testAnAccuracyThatRoundsToAThousandMetresIsKilometres() {
        // 999.5 m round to 1000 m, which is shown as 1.0 km like 1000 m itself (not "±1000 m").
        let text = SettingsFormat.accuracy(metres: 999.5)
        XCTAssertEqual(text, SettingsFormat.accuracy(metres: 1000))
        XCTAssertTrue(text.hasPrefix(plusMinus))
        XCTAssertTrue(text.hasSuffix("\(noBreakSpace)km"), text)
        XCTAssertEqual(digits(text), "10")
        XCTAssertEqual(SettingsFormat.accuracy(metres: 999.9), text)
    }

    func testAnAccuracyThatRoundsDownStaysInMetres() {
        XCTAssertEqual(SettingsFormat.accuracy(metres: 999.4), "\(plusMinus)999\(noBreakSpace)m")
        XCTAssertEqual(SettingsFormat.accuracy(metres: 999), "\(plusMinus)999\(noBreakSpace)m")
    }
}
