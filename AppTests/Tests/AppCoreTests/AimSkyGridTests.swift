import LodestarKit
import XCTest
@testable import AppCore

/// The fixed lines of the horizon frame: altitude circles, azimuth lines, the horizon, its ticks and the compass labels.
final class AimSkyGridTests: XCTestCase {
    private func assertUnit(_ vector: Vector3, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(vector.length, 1.0, accuracy: 1e-9, message, file: file, line: line)
    }

    private func assertSame(_ a: Vector3, _ b: Vector3, _ message: String = "", file: StaticString = #filePath,
                            line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: 1e-9, message, file: file, line: line)
    }

    // MARK: Altitude circles

    func testAltitudeCirclesRunEveryTenDegreesExceptTheHorizon() {
        let altitudes = AimSkyGrid.altitudeCircles.map(\.altitude)
        XCTAssertEqual(altitudes, [-80, -70, -60, -50, -40, -30, -20, -10, 10, 20, 30, 40, 50, 60, 70, 80])
        XCTAssertFalse(altitudes.contains(0))
    }

    func testEveryAltitudeCircleStaysAtItsAltitudeAllRoundTheCompass() {
        for circle in AimSkyGrid.altitudeCircles {
            XCTAssertEqual(circle.points.count, 180, "altitude \(circle.altitude)")
            for point in circle.points {
                assertUnit(point)
                XCTAssertEqual(point.z, AstroMath.sinDeg(circle.altitude), accuracy: 1e-12, "altitude \(circle.altitude)")
            }
        }
    }

    func testAnAltitudeCircleStartsDueNorthAndGoesEast() throws {
        let circle = try XCTUnwrap(AimSkyGrid.altitudeCircles.first { $0.altitude == 20 })
        assertSame(circle.points[0], HorizontalCoordinate(azimuth: 0, altitude: 20).unitVector)
        // Every second degree: point 45 is at azimuth 90.
        assertSame(circle.points[45], HorizontalCoordinate(azimuth: 90, altitude: 20).unitVector)
        XCTAssertGreaterThan(circle.points[45].x, 0.9)
    }

    // MARK: Azimuth lines

    func testAzimuthLinesRunEveryTenDegreesFromTheNadirToTheZenith() {
        XCTAssertEqual(AimSkyGrid.azimuthLines.count, 36)
        for (index, line) in AimSkyGrid.azimuthLines.enumerated() {
            XCTAssertEqual(line.count, 37, "line \(index)")
            assertSame(line[0], Vector3(0, 0, -1), "nadir of line \(index)")
            assertSame(line[36], Vector3(0, 0, 1), "zenith of line \(index)")
            assertSame(line[18], HorizontalCoordinate(azimuth: Double(index) * 10, altitude: 0).unitVector,
                       "horizon of line \(index)")
        }
    }

    func testTheFirstAzimuthLineIsTheNorthMeridianAndTheNinthTheEastOne() {
        // On the meridian of north the East component is zero; on the line of azimuth 90 the North component is.
        for point in AimSkyGrid.azimuthLines[0] { XCTAssertEqual(point.x, 0.0, accuracy: 1e-12) }
        for point in AimSkyGrid.azimuthLines[9] {
            XCTAssertEqual(point.y, 0.0, accuracy: 1e-12)
            XCTAssertGreaterThanOrEqual(point.x, -1e-12)
        }
    }

    // MARK: The horizon

    func testTheHorizonIsACircleOfAHundredAndEightyPointsAtAltitudeZero() {
        XCTAssertEqual(AimSkyGrid.horizon.count, 180)
        for point in AimSkyGrid.horizon {
            assertUnit(point)
            XCTAssertEqual(point.z, 0.0, accuracy: 1e-12)
        }
        assertSame(AimSkyGrid.horizon[0], Vector3(0, 1, 0))
        assertSame(AimSkyGrid.horizon[45], Vector3(1, 0, 0))
        assertSame(AimSkyGrid.horizon[90], Vector3(0, -1, 0))
        assertSame(AimSkyGrid.horizon[135], Vector3(-1, 0, 0))
    }

    func testTheHorizonTicksAreFiveDegreesApartAndEverySecondOneIsMajor() {
        let ticks = AimSkyGrid.horizonTicks
        XCTAssertEqual(ticks.count, 72)
        XCTAssertEqual(ticks.filter { $0.isMajor }.count, 36)
        for (index, tick) in ticks.enumerated() {
            XCTAssertEqual(tick.isMajor, index % 2 == 0, "tick \(index)")
            assertSame(tick.base, HorizontalCoordinate(azimuth: Double(index) * 5, altitude: 0).unitVector, "tick \(index)")
        }
        // Ticks at north, east, south and west are major (every 90 degrees is a multiple of 10).
        for index in [0, 18, 36, 54] { XCTAssertTrue(ticks[index].isMajor, "tick \(index)") }
        XCTAssertFalse(ticks[1].isMajor)
    }

    // MARK: The compass

    func testTheCompassLabelsAreTheEightMainDirectionsClockwiseFromNorth() {
        let labels = AimSkyGrid.compassLabels
        XCTAssertEqual(labels.map(\.text), ["N", "NE", "E", "SE", "S", "SW", "W", "NW"])
        XCTAssertEqual(labels.map(\.isCardinal), [true, false, true, false, true, false, true, false])
    }

    func testTheCompassLabelsSitOnTheHorizonAtTheirAzimuth() {
        let labels = AimSkyGrid.compassLabels
        for (index, label) in labels.enumerated() {
            assertSame(label.direction, HorizontalCoordinate(azimuth: Double(index) * 45, altitude: 0).unitVector, label.text)
        }
        assertSame(labels[0].direction, Vector3(0, 1, 0))
        assertSame(labels[2].direction, Vector3(1, 0, 0))
        assertSame(labels[4].direction, Vector3(0, -1, 0))
        assertSame(labels[6].direction, Vector3(-1, 0, 0))
        let half = 0.5.squareRoot()
        assertSame(labels[1].direction, Vector3(half, half, 0))
    }
}
