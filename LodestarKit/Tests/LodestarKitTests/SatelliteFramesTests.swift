import XCTest
@testable import LodestarKit

final class SatelliteFramesTests: XCTestCase {
    private typealias Support = SatelliteTestSupport

    func testSiderealTimeMatchesValladosExample() {
        // Vallado, Fundamentals of Astrodynamics and Applications, example 3-5: 1992 August 20, 12:14 UT1.
        let time = Support.iso("1992-08-20T12:14:00Z")
        XCTAssertEqual(AstroMath.degrees(SatelliteFrames.greenwichMeanSiderealTime(at: time)), 152.578787810, accuracy: 1e-6)
        let value = SatelliteFrames.greenwichMeanSiderealTime(at: Support.iso("2026-10-18T12:00:00Z"))
        XCTAssertTrue(value >= 0.0 && value < 2 * Double.pi)
    }

    func testSiderealTimeAndSunMatchSkyfield() throws {
        let frames = Support.list(try Support.jsonObject("satellite_reference.json"), "frames")
        XCTAssertEqual(frames.count, 6)
        for entry in frames {
            let time = Support.date(Support.number(entry, "time"))
            // Skyfield uses UT1 = UTC + 0.09 s; LodestarKit takes UT1 = UTC: 0.09 s is 0.0004 degrees of rotation.
            let expected = Support.number(entry, "greenwichMeanSiderealTimeDegrees")
            let ours = AstroMath.degrees(SatelliteFrames.greenwichMeanSiderealTime(at: time))
            let difference = abs(AstroMath.normalizeSignedDegrees(ours - expected))
            XCTAssertLessThan(difference, 0.001, "GMST differs by \(difference) degrees at \(time)")

            let sun = Support.numbers(entry, "sunTemeKilometers")
            let reference = Vector3(sun[0], sun[1], sun[2])
            let position = SatelliteFrames.sunPosition(at: time)
            XCTAssertLessThan(position.angle(to: reference), 0.002, "Sun direction differs by \(position.angle(to: reference)) degrees at \(time)")
            XCTAssertEqual(position.length / reference.length, 1.0, accuracy: 2e-5)
            XCTAssertTrue((1.46e8...1.53e8).contains(position.length))
        }
    }

    func testGeodeticPositions() {
        let equator = SatelliteFrames.earthFixedPosition(of: GeographicLocation(latitude: 0, longitude: 0, elevation: 0))
        XCTAssertEqual(equator.x, 6378.137, accuracy: 1e-9)
        XCTAssertEqual(equator.y, 0.0, accuracy: 1e-9)
        XCTAssertEqual(equator.z, 0.0, accuracy: 1e-9)
        let pole = SatelliteFrames.earthFixedPosition(of: GeographicLocation(latitude: 90, longitude: 0, elevation: 0))
        XCTAssertEqual(pole.z, 6356.752314245, accuracy: 1e-6)
        XCTAssertEqual(pole.x, 0.0, accuracy: 1e-6)
        let middle = SatelliteFrames.earthFixedPosition(of: GeographicLocation(latitude: 45, longitude: 0, elevation: 0))
        XCTAssertEqual(middle.x, 4517.590878849, accuracy: 1e-6)
        XCTAssertEqual(middle.z, 4487.348408866, accuracy: 1e-6)
        let boulder = SatelliteFrames.earthFixedPosition(of: GeographicLocation(latitude: 40.015, longitude: -105.2705, elevation: 1655))
        XCTAssertEqual(boulder.x, -1288.6754988503, accuracy: 1e-6)
        XCTAssertEqual(boulder.y, -4720.1513475913, accuracy: 1e-6)
        XCTAssertEqual(boulder.z, 4080.3254410207, accuracy: 1e-6)
        // Height is measured along the ellipsoid normal.
        let high = SatelliteFrames.earthFixedPosition(of: GeographicLocation(latitude: 0, longitude: 90, elevation: 1000))
        XCTAssertEqual(high.y, 6379.137, accuracy: 1e-9)
    }

    func testEarthFixedStateOfAGeostationaryOrbitIsAtRest() {
        let time = Support.iso("2026-10-18T00:00:00Z")
        let angle = SatelliteFrames.greenwichMeanSiderealTime(at: time)
        let radius = 42164.0
        // The position over longitude 30 degrees east, moving with the Earth's rotation.
        let longitude = 30.0 * Double.pi / 180
        let inertial = Vector3(radius * cos(angle + longitude), radius * sin(angle + longitude), 0.0)
        let velocity = Vector3(-SatelliteFrames.earthRotationRate * inertial.y, SatelliteFrames.earthRotationRate * inertial.x, 0.0)
        let fixed = SatelliteFrames.earthFixedState(of: TemeState(position: inertial, velocity: velocity), at: time)
        XCTAssertEqual(fixed.position.x, radius * cos(longitude), accuracy: 1e-6)
        XCTAssertEqual(fixed.position.y, radius * sin(longitude), accuracy: 1e-6)
        XCTAssertEqual(fixed.velocity.length, 0.0, accuracy: 1e-9)
        // A satellite at rest in inertial space moves backwards over the ground at the Earth's rotation speed.
        let still = SatelliteFrames.earthFixedState(of: TemeState(position: inertial, velocity: .zero), at: time)
        XCTAssertEqual(still.velocity.length, SatelliteFrames.earthRotationRate * radius, accuracy: 1e-9)
    }

    /// The TEME state of a point given in the Earth-fixed frame, at rest relative to the ground plus `relativeVelocity`.
    private func temeState(_ fixed: Vector3, _ relativeVelocity: Vector3, _ time: Date) -> TemeState {
        let angle = SatelliteFrames.greenwichMeanSiderealTime(at: time)
        let c = cos(angle)
        let s = sin(angle)
        // Inverse of the rotation to the Earth-fixed frame.
        let position = Vector3(c * fixed.x - s * fixed.y, s * fixed.x + c * fixed.y, fixed.z)
        let rotating = Vector3(c * relativeVelocity.x - s * relativeVelocity.y, s * relativeVelocity.x + c * relativeVelocity.y, relativeVelocity.z)
        let corotation = Vector3(-SatelliteFrames.earthRotationRate * position.y, SatelliteFrames.earthRotationRate * position.x, 0.0)
        return TemeState(position: position, velocity: rotating + corotation)
    }

    func testLookAtASatelliteStraightOverheadAndDueEast() {
        let place = Support.observer(40.0, -105.0, 1600.0)
        let time = Support.iso("2026-10-18T05:00:00Z")
        let base = SatelliteFrames.earthFixedPosition(of: place.location)
        let latitude = 40.0 * Double.pi / 180
        let longitude = -105.0 * Double.pi / 180
        let up = Vector3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude))
        let east = Vector3(-sin(longitude), cos(longitude), 0.0)
        let north = Vector3(-sin(latitude) * cos(longitude), -sin(latitude) * sin(longitude), cos(latitude))

        let overhead = SatelliteFrames.look(at: temeState(base + up * 500.0, up * 1.5, time), date: time, observer: place)
        XCTAssertEqual(overhead.altitude, 90.0, accuracy: 1e-6)
        XCTAssertEqual(overhead.rangeKilometers, 500.0, accuracy: 1e-6)
        XCTAssertEqual(overhead.rangeRateKilometersPerSecond, 1.5, accuracy: 1e-6)

        let eastward = SatelliteFrames.look(at: temeState(base + east * 100.0 + up * 0.5, east * 7.0, time), date: time, observer: place)
        XCTAssertEqual(eastward.azimuth, 90.0, accuracy: 1e-3)
        XCTAssertEqual(eastward.altitude, 0.0, accuracy: 0.3)  // the tangent plane through the observer
        XCTAssertEqual(eastward.rangeRateKilometersPerSecond, 7.0, accuracy: 0.01)
        XCTAssertEqual(eastward.unitVector.x, eastward.horizontal.unitVector.x, accuracy: 0.0)

        let northward = SatelliteFrames.look(at: temeState(base + north * 1000.0 + up * 300.0, .zero, time), date: time, observer: place)
        XCTAssertEqual(northward.azimuth, 0.0, accuracy: 1e-6)
        XCTAssertEqual(northward.altitude, AstroMath.degrees(atan2(300.0, 1000.0)), accuracy: 0.2)
        XCTAssertEqual(northward.rangeRateKilometersPerSecond, 0.0, accuracy: 1e-9)

        let behind = SatelliteFrames.look(at: temeState(base - up * 800.0, .zero, time), date: time, observer: place)
        XCTAssertEqual(behind.altitude, -90.0, accuracy: 1e-6)
        let west = SatelliteFrames.look(at: temeState(base - east * 500.0 + up * 0.1, .zero, time), date: time, observer: place)
        XCTAssertEqual(west.azimuth, 270.0, accuracy: 1e-2)
    }
}
