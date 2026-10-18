import XCTest
@testable import LodestarKit

final class EarthShadowTests: XCTestCase {
    private let sun = Vector3(149_597_870.7, 0.0, 0.0)

    /// A satellite at radius `radius` km, `angle` radians from the Sun direction in the equatorial plane.
    private func satellite(_ radius: Double, _ angle: Double) -> Vector3 {
        Vector3(radius * cos(angle), radius * sin(angle), 0.0)
    }

    private func fraction(_ position: Vector3, _ sunPosition: Vector3? = nil) -> Double {
        EarthShadow.illuminatedFraction(satellite: position, sun: sunPosition ?? sun)
    }

    func testFullSunlightAndUmbra() {
        XCTAssertEqual(fraction(satellite(6778.0, 0.0)), 1.0, accuracy: 0.0)
        XCTAssertEqual(fraction(satellite(6778.0, Double.pi / 2)), 1.0, accuracy: 0.0)
        XCTAssertEqual(fraction(satellite(6778.0, Double.pi)), 0.0, accuracy: 0.0)
        XCTAssertEqual(fraction(satellite(42164.0, Double.pi)), 0.0, accuracy: 0.0)
        XCTAssertEqual(fraction(satellite(42164.0, Double.pi / 2)), 1.0, accuracy: 0.0)
        XCTAssertTrue(EarthShadow.isSunlit(satellite: satellite(6778.0, 0.3), sun: sun))
        XCTAssertFalse(EarthShadow.isSunlit(satellite: satellite(6778.0, Double.pi - 0.1), sun: sun))
        // Inside the Earth, or with the Sun at the satellite, the fraction is 0 or 1.
        XCTAssertEqual(fraction(Vector3(1000.0, 0.0, 0.0)), 0.0, accuracy: 0.0)
        XCTAssertEqual(fraction(.zero), 0.0, accuracy: 0.0)
    }

    func testHalfIlluminationIsTheEdgeOfThePointSourceShadow() {
        // The satellite is on the tangent line from the centre of the Sun's disc to the Earth when the Earth's
        // limb passes through the Sun's centre. Find that angle by bisection and check its neighbours.
        for radius in [6778.0, 7500.0, 12_000.0, 42_164.0] {
            var low = Double.pi / 2
            var high = Double.pi
            while high - low > 1e-13 {
                let middle = 0.5 * (low + high)
                if fraction(satellite(radius, middle)) >= 0.5 { low = middle } else { high = middle }
            }
            let edge = 0.5 * (low + high)
            // Geometry: the tangent point of the shadow cone is where sin(angle from the antisolar axis) = Re/r (Sun at infinity).
            let limb = Double.pi - asin(SatelliteFrames.earthEquatorialRadiusKilometers / radius)
            XCTAssertEqual(edge, limb, accuracy: 1e-4 * (1 + 3000.0 / radius), "radius \(radius)")
            XCTAssertTrue(EarthShadow.isSunlit(satellite: satellite(radius, edge - 1e-6), sun: sun))
            XCTAssertFalse(EarthShadow.isSunlit(satellite: satellite(radius, edge + 1e-6), sun: sun))
            // Across the penumbra the Sun's disc is a straight edge's worth of area: symmetric about the half point.
            let spread = 0.2 * Double.pi / 180 * 6778.0 / radius
            let before = fraction(satellite(radius, edge - spread))
            let after = fraction(satellite(radius, edge + spread))
            XCTAssertEqual(before + after, 1.0, accuracy: 2e-3, "radius \(radius)")
            XCTAssertTrue((0.5...1.0).contains(before) && (0.0...0.5).contains(after))
        }
    }

    func testTheFractionFallsMonotonicallyAcrossThePenumbra() {
        let radius = 6778.0
        let limb = Double.pi - asin(SatelliteFrames.earthEquatorialRadiusKilometers / radius)
        var previous = 1.0
        var steps = 0
        var angle = limb - 0.01
        while angle < limb + 0.01 {
            let value = fraction(satellite(radius, angle))
            XCTAssertLessThanOrEqual(value, previous + 1e-12, "not monotonic at \(angle)")
            XCTAssertTrue((0.0...1.0).contains(value))
            if (0.001...0.999).contains(value) { steps += 1 }
            previous = value
            angle += 1e-5
        }
        // The Sun's disc is 0.53 degrees across; seen from the orbit that is 0.0093 radians of orbital angle
        // times the ratio of the distances; the penumbra takes a few hundred of the 1e-5 radian steps.
        XCTAssertTrue((100...1500).contains(steps), "penumbra spans \(steps) steps")
        XCTAssertEqual(previous, 0.0, accuracy: 1e-12)
    }

    func testTheSunLargerThanTheEarthLeavesARing() {
        // Far from the Earth (here: 20 million km behind it) the Earth covers only part of the Sun's disc.
        let value = fraction(Vector3(-2.0e7, 0.0, 0.0))
        let earth = asin(SatelliteFrames.earthEquatorialRadiusKilometers / 2.0e7)
        let sunRadius = asin(EarthShadow.sunRadiusKilometers / (sun.x + 2.0e7))
        XCTAssertEqual(value, 1.0 - earth * earth / (sunRadius * sunRadius), accuracy: 1e-6)
        XCTAssertTrue((0.9...1.0).contains(value))
    }

    func testShadowDoesNotDependOnTheFrame() {
        let a = satellite(7000.0, 2.9)
        let b = Vector3(a.x, a.z, a.y)  // the same geometry in another orientation of the axes
        let sunB = Vector3(sun.x, sun.z, sun.y)
        XCTAssertEqual(fraction(a), fraction(b, sunB), accuracy: 1e-12)
        XCTAssertEqual(EarthShadow.isSunlit(satellite: a, sun: sun), fraction(a) >= EarthShadow.sunlitThreshold)
        XCTAssertEqual(EarthShadow.sunlitThreshold, 0.5, accuracy: 0.0)
    }
}
