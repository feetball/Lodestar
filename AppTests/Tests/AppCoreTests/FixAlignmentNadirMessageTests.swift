import LodestarKit
import XCTest
@testable import AppCore

/// The words for a camera that is too close to the zenith or the nadir to align: up for a positive altitude, down for a
/// negative one.
final class FixAlignmentNadirMessageTests: XCTestCase {
    func testACameraPointingAlmostStraightDownIsToldSo() {
        let message = AlignmentError.boresightTooHigh(altitude: -85.6).aimMessage(forObject: "Vega")
        XCTAssertTrue(message.hasPrefix("The camera points almost straight down (\u{2212}86\u{00B0})."), message)
        XCTAssertFalse(message.contains("straight up"), message)
        XCTAssertTrue(AlignmentError.boresightTooHigh(altitude: -90).aimMessage(forObject: "Vega")
            .hasPrefix("The camera points almost straight down (\u{2212}90\u{00B0})."))
    }

    func testACameraPointingAlmostStraightUpIsStillToldSo() {
        let message = AlignmentError.boresightTooHigh(altitude: 85.4).aimMessage(forObject: "Vega")
        XCTAssertTrue(message.hasPrefix("The camera points almost straight up (85\u{00B0})."), message)
        XCTAssertFalse(message.contains("straight down"), message)
        XCTAssertTrue(AlignmentError.boresightTooHigh(altitude: 90).aimMessage(forObject: "Vega")
            .hasPrefix("The camera points almost straight up (90\u{00B0})."))
    }
}
