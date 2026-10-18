import XCTest
@testable import LodestarKit

final class HorizonMaskTests: XCTestCase {
    private typealias Support = HorizonTestSupport

    private let mask = HorizonMask(profile: HorizonTestSupport.truthProfile)

    func testMaskAgreesWithTheProfileForRandomDirections() {
        let generator = Support.SeededGenerator(seed: 5_000)
        var below = 0
        var above = 0
        var skipped = 0
        for _ in 0..<20_000 {
            let x = generator.nextSigned()
            let y = generator.nextSigned()
            let z = 0.35 * generator.nextSigned()
            let vector = Vector3(x, y, z) * (0.5 + 100 * generator.nextDouble())
            let direction = HorizontalCoordinate(vector: vector)
            let skyline = Support.truthProfile.altitude(at: direction.azimuth)
            // The table is a quarter of a degree fine; directions on the skyline itself may go either way.
            if abs(direction.altitude - skyline) < 0.01 {
                skipped += 1
                continue
            }
            let expected = direction.altitude < skyline
            XCTAssertEqual(mask.isBelow(vector), expected, "\(direction) against \(skyline)")
            XCTAssertEqual(mask.isBelow(x: vector.x, y: vector.y, z: vector.z), expected)
            XCTAssertEqual(mask.isBelow(azimuth: direction.azimuth, altitude: direction.altitude), expected)
            if expected { below += 1 } else { above += 1 }
        }
        XCTAssertLessThan(skipped, 100)
        XCTAssertTrue(below > 1_000 && above > 1_000, "\(below) below and \(above) above")
    }

    func testTheSkylineItselfIsNotBelow() {
        // Nodes: azimuth 90° at 30°, azimuth 190° at 12°.
        XCTAssertFalse(mask.isBelow(azimuth: 90, altitude: 30))
        XCTAssertTrue(mask.isBelow(azimuth: 90, altitude: 29.99))
        XCTAssertFalse(mask.isBelow(azimuth: 90, altitude: 30.01))
        XCTAssertFalse(mask.isBelow(azimuth: 190, altitude: 12))
        XCTAssertTrue(mask.isBelow(azimuth: 190, altitude: 11.9))
        XCTAssertTrue(mask.isBelow(HorizontalCoordinate(azimuth: 90, altitude: 29.5).unitVector))
        XCTAssertFalse(mask.isBelow(HorizontalCoordinate(azimuth: 90, altitude: 30.5).unitVector))
        // Between nodes the skyline is the line: at 100° it is 30 · (1 − 10/40) = 22.5°.
        XCTAssertTrue(mask.isBelow(HorizontalCoordinate(azimuth: 100, altitude: 22.3).unitVector))
        XCTAssertFalse(mask.isBelow(HorizontalCoordinate(azimuth: 100, altitude: 22.7).unitVector))
    }

    func testMaskIsIndependentOfTheLengthOfTheVector() {
        for scale in [1e-6, 0.3, 1.0, 5_000.0, 1e9] {
            let inside = HorizontalCoordinate(azimuth: 90, altitude: 25).unitVector * scale
            let outside = HorizontalCoordinate(azimuth: 90, altitude: 35).unitVector * scale
            XCTAssertTrue(mask.isBelow(inside), "\(scale)")
            XCTAssertFalse(mask.isBelow(outside), "\(scale)")
        }
    }

    func testMaskWrapsThroughNorth() {
        let skyline = HorizonProfile.flat.setting(to: 20, in: AzimuthRange(start: 359, length: 0))
            .setting(to: 10, in: AzimuthRange(start: 0, length: 0))
        let wrapped = HorizonMask(profile: skyline)
        // Between node 359 (20°) and node 0 (10°) the skyline is 15° at 359.5°.
        XCTAssertTrue(wrapped.isBelow(HorizontalCoordinate(azimuth: 359.5, altitude: 14.8).unitVector))
        XCTAssertFalse(wrapped.isBelow(HorizontalCoordinate(azimuth: 359.5, altitude: 15.2).unitVector))
        XCTAssertTrue(wrapped.isBelow(HorizontalCoordinate(azimuth: -0.25, altitude: 12.3).unitVector)) // 359.75°: skyline 12.5°
        XCTAssertFalse(wrapped.isBelow(HorizontalCoordinate(azimuth: -0.25, altitude: 12.7).unitVector))
        XCTAssertTrue(wrapped.isBelow(HorizontalCoordinate(azimuth: 0, altitude: 9.9).unitVector))
        XCTAssertFalse(wrapped.isBelow(HorizontalCoordinate(azimuth: 0, altitude: 10.1).unitVector))
    }

    func testFlatMaskHidesTheDirectionsBelowTheHorizon() {
        let flat = HorizonMask(profile: .flat)
        XCTAssertTrue(flat.isBelow(x: 1, y: 0, z: -0.001))
        XCTAssertFalse(flat.isBelow(x: 1, y: 0, z: 0))
        XCTAssertFalse(flat.isBelow(x: 1, y: 0, z: 0.001))
        XCTAssertTrue(flat.isBelow(HorizontalCoordinate(azimuth: 200, altitude: -3).unitVector))
        XCTAssertFalse(flat.isBelow(HorizontalCoordinate(azimuth: 200, altitude: 3).unitVector))
        XCTAssertEqual(flat.profile, HorizonProfile.flat)
    }

    func testZenithNadirAndInvalidDirections() {
        XCTAssertFalse(mask.isBelow(x: 0, y: 0, z: 1)) // the zenith is above any skyline
        XCTAssertTrue(mask.isBelow(x: 0, y: 0, z: -1)) // and the nadir below
        XCTAssertFalse(mask.isBelow(x: 0, y: 0, z: 0))
        XCTAssertFalse(mask.isBelow(x: .nan, y: 0, z: 0))
        XCTAssertFalse(mask.isBelow(x: 1, y: .nan, z: -1))
        XCTAssertFalse(mask.isBelow(x: .infinity, y: 0, z: -1))
        XCTAssertFalse(mask.isBelow(Vector3.zero))
        XCTAssertFalse(mask.isBelow(azimuth: .nan, altitude: 10))
        XCTAssertFalse(mask.isBelow(azimuth: 10, altitude: .infinity))
    }

    func testMaskOfAConstantSkylineIsAnAltitudeTest() {
        let ridge = HorizonMask(profile: .constant(15))
        for azimuth in [0.0, 37.3, 90, 271.5, 359.9] {
            XCTAssertTrue(ridge.isBelow(HorizontalCoordinate(azimuth: azimuth, altitude: 14.9).unitVector), "\(azimuth)")
            XCTAssertFalse(ridge.isBelow(HorizontalCoordinate(azimuth: azimuth, altitude: 15.1).unitVector), "\(azimuth)")
        }
    }

    /// Seconds allowed for a million tests. A release build needs a few hundredths of a second; an unoptimised
    /// debug build is an order of magnitude slower, so its bound only catches a calculation that has gone badly wrong.
    private static let millionTestsLimit: Double = {
        #if DEBUG
        return 30
        #else
        return 1.5
        #endif
    }()

    func testTestingAFrameOfStarsIsFast() {
        let generator = Support.SeededGenerator(seed: 9)
        var vectors = [Double]()
        vectors.reserveCapacity(3 * 20_000)
        for _ in 0..<20_000 {
            let azimuth = 360 * generator.nextDouble()
            let altitude = AstroMath.asinDeg(generator.nextDouble())
            let direction = HorizontalCoordinate(azimuth: azimuth, altitude: altitude).unitVector
            vectors.append(contentsOf: [direction.x, direction.y, direction.z])
        }
        var hidden = 0
        for _ in 0..<3 {
            hidden = 0
            for index in 0..<20_000 where mask.isBelow(x: vectors[3 * index], y: vectors[3 * index + 1], z: vectors[3 * index + 2]) {
                hidden += 1
            }
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<50 {
                for index in 0..<20_000 where mask.isBelow(x: vectors[3 * index], y: vectors[3 * index + 1], z: vectors[3 * index + 2]) {
                    hidden += 1
                }
            }
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        // A million tests, about fifty frames of twenty thousand stars each.
        XCTAssertLessThan(seconds, Self.millionTestsLimit, "took \(seconds) s")
        XCTAssertGreaterThan(hidden, 0)
    }
}
