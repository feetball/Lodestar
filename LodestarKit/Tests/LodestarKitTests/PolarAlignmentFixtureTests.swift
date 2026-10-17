import XCTest
@testable import LodestarKit

/// The polar-scope reading against Skyfield (JPL DE440s, IAU 2006/2000A): the fixtures hold the apparent
/// places and the azimuths and altitudes of Polaris and σ Octantis for ten instants between 1957 and 2039,
/// each seen from two of six observing sites.
/// None of the reference numbers comes from LodestarKit.
final class PolarAlignmentFixtureTests: XCTestCase {
    private struct StarCase: Decodable {
        let utc: String
        let ut1Jd: Double
        let ttJd: Double
        let lat: Double
        let lon: Double
        let elevationM: Double
        let star: String
        let raApparentDeg: Double
        let decApparentDeg: Double
        let azDeg: Double
        let altDeg: Double

        /// The instant with exactly the fixture's UT1 and TT, so ΔT differences do not enter.
        var julianDate: JulianDate { JulianDate(ut: ut1Jd, deltaT: (ttJd - ut1Jd) * JulianDate.secondsPerDay) }

        var frame: SkyFrame {
            SkyFrame(julianDate: julianDate,
                     observer: Observer(location: GeographicLocation(latitude: lat, longitude: lon, elevation: elevationM)))
        }

        var hemisphere: PolarAlignment.Hemisphere { star == "Polaris" ? .north : .south }
    }

    private struct StarFixture: Decodable {
        let cases: [StarCase]
    }

    private struct SiderealCase: Decodable {
        let utc: String
        let gastHours: Double
    }

    private struct SiderealFixture: Decodable {
        let cases: [SiderealCase]
    }

    private func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let directory = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(contentsOf: directory.appendingPathComponent(name)))
    }

    private func poleStarCases() throws -> [StarCase] {
        let cases = try load(StarFixture.self, "stars_apparent.json").cases
            .filter { $0.star == "Polaris" || $0.star == "sigma Octantis" }
        XCTAssertGreaterThanOrEqual(cases.count, 20, "the fixtures hold both stars at many instants")
        return cases
    }

    /// Difference of two angles in degrees, in (−180, 180].
    private func difference(_ a: Double, _ b: Double) -> Double { AstroMath.normalizeSignedDegrees(a - b) }

    /// The reading worked out from the star's azimuth and altitude alone: the direction of the star from the
    /// pole in the plane tangent to the sky at the pole, seen by an observer who looks at the pole with the
    /// zenith above it, in degrees clockwise from the top.
    private func drawnAngle(of star: StarCase) -> (angle: Double, separation: Double) {
        let latitude = star.lat
        let northern = star.hemisphere == .north
        let pole = Vector3(0, northern ? AstroMath.cosDeg(latitude) : -AstroMath.cosDeg(latitude),
                           northern ? AstroMath.sinDeg(latitude) : -AstroMath.sinDeg(latitude))
        let zenith = Vector3(0, 0, 1)
        let up = (zenith - pole * zenith.dot(pole)).normalized
        let right = pole.cross(up)
        let direction = HorizontalCoordinate(azimuth: star.azDeg, altitude: star.altDeg).unitVector
        let offset = direction - pole * direction.dot(pole)
        return (AstroMath.normalizeDegrees(AstroMath.atan2Deg(offset.dot(right), offset.dot(up))), direction.angle(to: pole))
    }

    // MARK: Against Skyfield

    func testClockAngleMatchesTheAngleDerivedFromAzimuthAndAltitude() throws {
        // The reference azimuths and altitudes include diurnal aberration (up to 0.3″), which moves the star
        // by up to 0.01° around the pole, so that is the best agreement to ask for.
        for star in try poleStarCases() {
            let label = "\(star.star) at \(star.lat), \(star.lon) on \(star.utc)"
            let expected = drawnAngle(of: star)
            let reading = PolarAlignment.polarScopeReading(frame: star.frame, hemisphere: star.hemisphere)
            XCTAssertEqual(difference(reading.angle, expected.angle), 0, accuracy: 0.015, label)
            XCTAssertEqual(reading.separationFromPole, expected.separation, accuracy: 0.001, label)

            let inverted = PolarAlignment.polarScopeReading(frame: star.frame, hemisphere: star.hemisphere, view: .inverted)
            XCTAssertEqual(difference(inverted.angle, expected.angle + 180), 0, accuracy: 0.015, label)
        }
    }

    func testSeparationFromThePoleIsNinetyMinusTheApparentDeclination() throws {
        for star in try poleStarCases() {
            let reading = PolarAlignment.polarScopeReading(frame: star.frame, hemisphere: star.hemisphere)
            XCTAssertEqual(reading.separationFromPole, 90 - abs(star.decApparentDeg), accuracy: 1e-4,
                           "\(star.star) on \(star.utc)")
            XCTAssertEqual(reading.referenceStarName, star.star == "Polaris" ? "Polaris" : "σ Octantis")
        }
    }

    func testHourAngleIsLocalSiderealTimeMinusTheApparentRightAscension() throws {
        // Only two of the fixtures' instants also have a Skyfield sidereal time: 2000-01-01T12:00Z and 2026-10-17T00:00Z.
        let sidereal = try load(SiderealFixture.self, "sidereal.json").cases
        var checked = 0
        for star in try poleStarCases() {
            guard let instant = sidereal.first(where: { $0.utc == star.utc }) else { continue }
            checked += 1
            let reading = PolarAlignment.polarScopeReading(frame: star.frame, hemisphere: star.hemisphere)
            let expected = AstroMath.normalizeSignedDegrees(instant.gastHours * 15 + star.lon - star.raApparentDeg)
            XCTAssertEqual(difference(reading.hourAngle, expected), 0, accuracy: 0.002, "\(star.star) on \(star.utc)")
            let sign = star.hemisphere == .north ? -1.0 : 1.0
            XCTAssertEqual(difference(reading.angle, sign * expected), 0, accuracy: 0.002, "\(star.star) on \(star.utc)")
        }
        XCTAssertGreaterThanOrEqual(checked, 4, "at least two instants appear in both fixtures")
    }
}
