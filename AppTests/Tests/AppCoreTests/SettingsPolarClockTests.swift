import Foundation
import XCTest
@testable import AppCore

/// `ToolsPolarClock.text(angle:)`: a direction as a clock position on a polar-scope reticle (30 degrees per hour).
final class SettingsPolarClockTests: XCTestCase {
    func testStraightUpIsTwelveOClock() {
        XCTAssertEqual(ToolsPolarClock.text(angle: 0), "12:00")
    }

    func testEveryThirtyDegreesIsOneHour() {
        let expected = ["12:00", "1:00", "2:00", "3:00", "4:00", "5:00", "6:00", "7:00", "8:00", "9:00", "10:00", "11:00"]
        for hour in 0..<12 {
            XCTAssertEqual(ToolsPolarClock.text(angle: Double(hour) * 30), expected[hour], "\(hour * 30) degrees")
        }
    }

    func testHalfHoursAreFifteenDegrees() {
        XCTAssertEqual(ToolsPolarClock.text(angle: 15), "12:30")
        XCTAssertEqual(ToolsPolarClock.text(angle: 45), "1:30")
        XCTAssertEqual(ToolsPolarClock.text(angle: 315), "10:30")
        XCTAssertEqual(ToolsPolarClock.text(angle: 345), "11:30")
    }

    func testOneMinuteIsHalfADegree() {
        XCTAssertEqual(ToolsPolarClock.text(angle: 0.5), "12:01")
        XCTAssertEqual(ToolsPolarClock.text(angle: 2.5), "12:05")
        XCTAssertEqual(ToolsPolarClock.text(angle: 5), "12:10")
        XCTAssertEqual(ToolsPolarClock.text(angle: 90.5), "3:01")
        XCTAssertEqual(ToolsPolarClock.text(angle: 29.5), "12:59")
    }

    func testMinutesBelowTenAreZeroPadded() {
        XCTAssertEqual(ToolsPolarClock.text(angle: 182), "6:04")
        XCTAssertEqual(ToolsPolarClock.text(angle: 120.5), "4:01")
    }

    func testTheAngleIsRoundedToTheNearestMinute() {
        XCTAssertEqual(ToolsPolarClock.text(angle: 0.2), "12:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: 0.3), "12:01")
        XCTAssertEqual(ToolsPolarClock.text(angle: 179.8), "6:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: 180.2), "6:00")
    }

    func testJustBelowAFullTurnRoundsUpToTwelveNeverTwelveSixty() {
        XCTAssertEqual(ToolsPolarClock.text(angle: 359.9), "12:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: 359.8), "12:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: 359.5), "11:59")
        XCTAssertEqual(ToolsPolarClock.text(angle: 359.76), "12:00")
    }

    func testAnglesAreWrappedIntoOneTurn() {
        XCTAssertEqual(ToolsPolarClock.text(angle: 360), "12:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: 390), "1:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: 720), "12:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: -30), "11:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: -90), "9:00")
        XCTAssertEqual(ToolsPolarClock.text(angle: -360), "12:00")
    }

    func testAnAngleThatIsNotFiniteIsThePlaceholder() {
        XCTAssertEqual(ToolsPolarClock.text(angle: .nan), AppFormat.missing)
        XCTAssertEqual(ToolsPolarClock.text(angle: .infinity), AppFormat.missing)
        XCTAssertEqual(ToolsPolarClock.text(angle: -.infinity), AppFormat.missing)
    }

    func testEveryHalfDegreeGivesAValidClockTime() {
        for step in 0..<720 {
            let text = ToolsPolarClock.text(angle: Double(step) * 0.5)
            let parts = text.split(separator: ":")
            XCTAssertEqual(parts.count, 2, text)
            let hour = Int(parts[0]) ?? -1
            let minute = Int(parts[1]) ?? -1
            XCTAssertTrue((1...12).contains(hour), text)
            XCTAssertTrue((0...59).contains(minute), text)
            XCTAssertEqual(parts[1].count, 2, text)
        }
    }

    func testTheClockAdvancesOneMinuteForEveryHalfDegree() {
        for step in 1..<720 {
            let previous = ToolsPolarClock.text(angle: Double(step - 1) * 0.5)
            let current = ToolsPolarClock.text(angle: Double(step) * 0.5)
            XCTAssertNotEqual(previous, current)
        }
    }
}
