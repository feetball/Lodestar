import XCTest
@testable import LodestarKit

final class SatelliteBrightnessTests: XCTestCase {
    private func magnitude(_ intrinsic: Double, _ range: Double, _ phase: Double, _ fraction: Double = 1.0) -> Double? {
        SatelliteBrightness.apparentMagnitude(intrinsicMagnitude: intrinsic, rangeKilometers: range, phaseAngle: phase, illuminatedFraction: fraction)
    }

    func testTheIntrinsicMagnitudeIsTheMagnitudeAt1000KilometresAndNinetyDegrees() throws {
        XCTAssertEqual(try XCTUnwrap(magnitude(-1.8, 1000.0, 90.0)), -1.8, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(magnitude(5.3, 1000.0, 90.0)), 5.3, accuracy: 1e-12)
    }

    func testRangeScalesAsFiveLogRange() throws {
        let near = try XCTUnwrap(magnitude(-1.8, 500.0, 90.0))
        let far = try XCTUnwrap(magnitude(-1.8, 2000.0, 90.0))
        XCTAssertEqual(near + 1.8, 5.0 * log10(0.5), accuracy: 1e-12)
        XCTAssertEqual(far + 1.8, 5.0 * log10(2.0), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(magnitude(0.0, 10_000.0, 90.0)), 5.0, accuracy: 1e-12)
    }

    func testPhaseFollowsTheDiffuseSphereLaw() throws {
        // Full phase is 2.5 log10(pi) = 1.243 magnitudes brighter than 90 degrees.
        XCTAssertEqual(try XCTUnwrap(magnitude(-1.8, 1000.0, 0.0)), -1.8 - 2.5 * log10(Double.pi), accuracy: 1e-12)
        // 60 degrees: sin 60 + (pi - pi/3) cos 60.
        let bracket = sin(Double.pi / 3) + (Double.pi - Double.pi / 3) * cos(Double.pi / 3)
        XCTAssertEqual(try XCTUnwrap(magnitude(-1.8, 1000.0, 60.0)), -1.8 - 2.5 * log10(bracket), accuracy: 1e-12)
        // Fainter towards new phase, monotonically.
        var previous = -100.0
        for phase in stride(from: 0, through: 175, by: 5) {
            let value = try XCTUnwrap(magnitude(0.0, 1000.0, Double(phase)))
            XCTAssertGreaterThan(value, previous)
            previous = value
        }
        XCTAssertNil(magnitude(0.0, 1000.0, 180.0))
    }

    func testPenumbraDimsTheSatellite() throws {
        let full = try XCTUnwrap(magnitude(0.0, 1000.0, 90.0, 1.0))
        let half = try XCTUnwrap(magnitude(0.0, 1000.0, 90.0, 0.5))
        XCTAssertEqual(half - full, 2.5 * log10(2.0), accuracy: 1e-12)
        XCTAssertNil(magnitude(0.0, 1000.0, 90.0, 0.0))
    }

    func testInvalidInputsGiveNoMagnitude() {
        XCTAssertNil(magnitude(.nan, 1000.0, 90.0))
        XCTAssertNil(magnitude(0.0, .infinity, 90.0))
        XCTAssertNil(magnitude(0.0, 0.5, 90.0))
        XCTAssertNil(magnitude(0.0, 1000.0, -1.0))
        XCTAssertNil(magnitude(0.0, 1000.0, 180.5))
        XCTAssertNil(magnitude(0.0, 1000.0, 90.0, 1.5))
        XCTAssertNil(magnitude(0.0, 1000.0, 90.0, .nan))
    }

    func testKnownIntrinsicMagnitudes() throws {
        XCTAssertEqual(SatelliteBrightness.issIntrinsicMagnitude, -1.8, accuracy: 0.0)
        XCTAssertEqual(SatelliteBrightness.intrinsicMagnitude(catalogNumber: 25544), -1.8)
        XCTAssertEqual(SatelliteBrightness.intrinsicMagnitude(catalogNumber: 48274), 0.0)
        XCTAssertEqual(SatelliteBrightness.intrinsicMagnitude(catalogNumber: 20580), 2.2)
        XCTAssertNil(SatelliteBrightness.intrinsicMagnitude(catalogNumber: 44714))
        XCTAssertNil(SatelliteBrightness.intrinsicMagnitude(catalogNumber: -1))
        // A bright ISS pass: 450 km range, 60 degrees phase.
        XCTAssertEqual(try XCTUnwrap(magnitude(-1.8, 450.0, 60.0)), -4.24, accuracy: 0.01)
    }
}
