import LodestarKit
import XCTest
@testable import AppCore

/// The recorded skyline prepared for the overlay: the line, the wedges of ground below it and the mask.
final class AimSkylineTests: XCTestCase {
    private let nadir = Vector3(0, 0, -1)

    /// A skyline at `base` degrees with the given bins raised to `altitude`.
    private func profile(raising bins: [Int], to altitude: Double, base: Double = 0) throws -> HorizonProfile {
        var values = [Double](repeating: base, count: HorizonProfile.binCount)
        for bin in bins { values[bin] = altitude }
        return try XCTUnwrap(HorizonProfile(altitudes: values))
    }

    private func assertSame(_ a: Vector3, _ b: Vector3, _ message: String = "", file: StaticString = #filePath,
                            line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: 1e-9, message, file: file, line: line)
    }

    // MARK: The line

    func testTheLineHasAPointForEveryDegreeAndClosesOnItself() {
        let skyline = AimSkyline(profile: .flat)
        XCTAssertEqual(skyline.line.count, 361)
        XCTAssertEqual(skyline.line.first, skyline.line.last)
        for point in skyline.line {
            XCTAssertEqual(point.length, 1.0, accuracy: 1e-9)
            XCTAssertEqual(point.z, 0.0, accuracy: 1e-12)
        }
        assertSame(skyline.line[0], Vector3(0, 1, 0))
        assertSame(skyline.line[90], Vector3(1, 0, 0))
        assertSame(skyline.line[180], Vector3(0, -1, 0))
        assertSame(skyline.line[270], Vector3(-1, 0, 0))
    }

    func testTheLineFollowsTheRecordedAltitudes() throws {
        let east = try profile(raising: [90], to: 14)
        let skyline = AimSkyline(profile: east)
        XCTAssertEqual(skyline.line[90].z, AstroMath.sinDeg(14), accuracy: 1e-12)
        assertSame(skyline.line[90], HorizontalCoordinate(azimuth: 90, altitude: 14).unitVector)
        XCTAssertEqual(skyline.line[89].z, 0.0, accuracy: 1e-12)
        XCTAssertEqual(skyline.line[91].z, 0.0, accuracy: 1e-12)
    }

    func testASkylineAtOneAltitudeAllRoundIsALevelLine() {
        let skyline = AimSkyline(profile: .constant(5))
        for point in skyline.line {
            XCTAssertEqual(point.z, AstroMath.sinDeg(5), accuracy: 1e-12)
        }
        XCTAssertEqual(skyline.highestAltitude, 5.0)
    }

    func testTheHighestAltitudeIsTheHighestPointOfTheProfile() throws {
        XCTAssertEqual(AimSkyline(profile: .flat).highestAltitude, 0.0)
        let hill = try profile(raising: [200, 201, 202], to: 23.5, base: 2)
        XCTAssertEqual(AimSkyline(profile: hill).highestAltitude, 23.5)
        XCTAssertEqual(AimSkyline(profile: .constant(-4)).highestAltitude, -4.0)
    }

    func testTheSkylineKeepsItsProfile() throws {
        let hill = try profile(raising: [10, 11], to: 8)
        let skyline = AimSkyline(profile: hill)
        XCTAssertEqual(skyline.profile, hill)
        XCTAssertEqual(skyline.mask.profile, hill)
    }

    // MARK: Wrapping round at north

    func testTheLineIsTheSameAtZeroAndThreeHundredSixtyDegrees() throws {
        let tree = try profile(raising: [0], to: 20)
        let skyline = AimSkyline(profile: tree)
        XCTAssertEqual(skyline.line[0].z, AstroMath.sinDeg(20), accuracy: 1e-12)
        XCTAssertEqual(skyline.line[360].z, AstroMath.sinDeg(20), accuracy: 1e-12)
        XCTAssertEqual(skyline.line[0], skyline.line[360])
        XCTAssertEqual(skyline.line[1].z, 0.0, accuracy: 1e-12)
        XCTAssertEqual(skyline.line[359].z, 0.0, accuracy: 1e-12)
    }

    func testAPeakAtNorthIsTheEndOfTheLastWedgeAndTheStartOfTheFirst() throws {
        let tree = try profile(raising: [0], to: 20)
        let skyline = AimSkyline(profile: tree)
        let first = try XCTUnwrap(skyline.wedges.first)
        let last = try XCTUnwrap(skyline.wedges.last)
        XCTAssertEqual(first.vertices[0].z, AstroMath.sinDeg(20), accuracy: 1e-12)
        XCTAssertEqual(last.vertices[5].z, AstroMath.sinDeg(20), accuracy: 1e-12)
        XCTAssertEqual(first.vertices[0], last.vertices[5])
    }

    func testTheMaskWrapsFromThreeHundredFiftyNineToZeroDegrees() throws {
        let tree = try profile(raising: [0], to: 20)
        let mask = AimSkyline(profile: tree).mask
        // Half a degree either side of north the skyline is half way between 0 and 20 degrees: 10 degrees.
        for azimuth in [359.5, 0.5] {
            XCTAssertTrue(mask.isBelow(azimuth: azimuth, altitude: 9), "azimuth \(azimuth)")
            XCTAssertFalse(mask.isBelow(azimuth: azimuth, altitude: 11), "azimuth \(azimuth)")
            XCTAssertTrue(mask.isBelow(HorizontalCoordinate(azimuth: azimuth, altitude: 9).unitVector), "azimuth \(azimuth)")
            XCTAssertFalse(mask.isBelow(HorizontalCoordinate(azimuth: azimuth, altitude: 11).unitVector), "azimuth \(azimuth)")
        }
        // The peak itself and a place far from it.
        XCTAssertTrue(mask.isBelow(azimuth: 0, altitude: 19))
        XCTAssertFalse(mask.isBelow(azimuth: 0, altitude: 21))
        XCTAssertFalse(mask.isBelow(azimuth: 180, altitude: 1))
        XCTAssertTrue(mask.isBelow(azimuth: 180, altitude: -1))
    }

    // MARK: The ground

    func testTheGroundIsCutIntoSeventyTwoWedgesOfFiveDegrees() {
        let skyline = AimSkyline(profile: .flat)
        XCTAssertEqual(AimSkyline.wedgeWidth, 5)
        XCTAssertEqual(skyline.wedges.count, 72)
        for (index, wedge) in skyline.wedges.enumerated() {
            // Six points of the skyline and the nadir.
            XCTAssertEqual(wedge.vertices.count, 7, "wedge \(index)")
            XCTAssertEqual(wedge.vertices.last, nadir, "wedge \(index)")
            assertSame(wedge.vertices[0], skyline.line[index * 5], "wedge \(index)")
            assertSame(wedge.vertices[5], skyline.line[index * 5 + 5], "wedge \(index)")
        }
    }

    func testNeighbouringWedgesShareAnEdgeAndTheLastOneClosesTheCircle() throws {
        let hill = try profile(raising: Array(100...140), to: 12, base: 3)
        let skyline = AimSkyline(profile: hill)
        for index in 0..<(skyline.wedges.count - 1) {
            XCTAssertEqual(skyline.wedges[index].vertices[5], skyline.wedges[index + 1].vertices[0], "wedge \(index)")
        }
        XCTAssertEqual(skyline.wedges[71].vertices[5], skyline.wedges[0].vertices[0])
    }

    func testAWedgeKnowsItsCentreAndTheAngleToItsFarthestVertex() {
        let skyline = AimSkyline(profile: .flat)
        for (index, wedge) in skyline.wedges.enumerated() {
            XCTAssertEqual(wedge.center.length, 1.0, accuracy: 1e-9, "wedge \(index)")
            for vertex in wedge.vertices {
                XCTAssertLessThanOrEqual(wedge.center.angle(to: vertex), wedge.radius + 1e-9, "wedge \(index)")
            }
            // The nadir is the farthest vertex of a flat skyline's wedge: the centre is weighted towards the six
            // points on the horizon, 80.5 degrees from the point straight down.
            XCTAssertEqual(wedge.radius, 80.54, accuracy: 0.05, "wedge \(index)")
        }
    }

    func testTheWedgesOfAHighSkylineReachTheSameDepth() throws {
        // A wedge always ends in the nadir, so the ground is closed below whatever the skyline does.
        let hill = try profile(raising: Array(0...359), to: 40)
        let skyline = AimSkyline(profile: hill)
        XCTAssertEqual(skyline.wedges.count, 72)
        for wedge in skyline.wedges {
            XCTAssertEqual(wedge.vertices.last, nadir)
            XCTAssertEqual(wedge.vertices[0].z, AstroMath.sinDeg(40), accuracy: 1e-12)
        }
    }

    // MARK: The mask

    func testTheMaskHidesWhatIsBelowTheRecordedSkyline() throws {
        let hill = try profile(raising: Array(80...100), to: 15)
        let mask = AimSkyline(profile: hill).mask
        XCTAssertTrue(mask.isBelow(azimuth: 90, altitude: 14))
        XCTAssertFalse(mask.isBelow(azimuth: 90, altitude: 16))
        XCTAssertFalse(mask.isBelow(azimuth: 200, altitude: 1))
        XCTAssertTrue(mask.isBelow(HorizontalCoordinate(azimuth: 90, altitude: 14).unitVector))
        XCTAssertFalse(mask.isBelow(HorizontalCoordinate(azimuth: 90, altitude: 16).unitVector))
    }
}
