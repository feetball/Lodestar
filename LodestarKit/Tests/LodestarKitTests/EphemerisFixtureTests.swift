import XCTest
@testable import LodestarKit

/// Loads the JSON reference fixtures (Skyfield with JPL DE440s) bundled with the tests.
///
/// A missing or malformed fixture throws, so the calling test fails instead of passing vacuously.
enum EphemerisFixtureStore {
    struct MissingFixture: Error, CustomStringConvertible {
        let name: String
        var description: String { "Fixture \(name) is missing from the test bundle's Fixtures directory" }
    }

    static func load<T: Decodable>(_ type: T.Type, from fileName: String) throws -> T {
        guard let directory = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw MissingFixture(name: "Fixtures directory")
        }
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { throw MissingFixture(name: fileName) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    /// The `Date` of a fixture's UT1 Julian Date.
    static func date(universalJulianDate jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - JulianDate.unixEpoch) * JulianDate.secondsPerDay)
    }
}

/// Compares `Ephemeris` with `bodies_apparent.json`: apparent places of the Sun, Moon and planets from
/// DE440s, at 50 instants between 1950 and 2049, each seen from one of six observing sites.
final class EphemerisFixtureTests: XCTestCase {
    private struct BodyCase: Decodable {
        let utc: String
        let ut1Jd: Double
        let ttJd: Double
        let lat: Double
        let lon: Double
        let elevationM: Double
        let body: String
        let raApparentJ2000Deg: Double
        let decApparentJ2000Deg: Double
        let raApparentDeg: Double
        let decApparentDeg: Double
        let raTopoDeg: Double
        let decTopoDeg: Double
        let distanceAu: Double
        let azDeg: Double
        let altDeg: Double
        let illuminatedFraction: Double?
        let phaseAngleDeg: Double?
        let elongationDeg: Double?
        let heliocentricDistanceAu: Double?
        let apparentMagnitude: Double?

        var solarSystemBody: SolarSystemBody { SolarSystemBody(rawValue: body) ?? .sun }

        /// The instant with exactly the fixture's UT1 and TT, so ΔT differences do not enter.
        var julianDate: JulianDate { JulianDate(ut: ut1Jd, deltaT: (ttJd - ut1Jd) * JulianDate.secondsPerDay) }

        var observer: Observer {
            Observer(location: GeographicLocation(latitude: lat, longitude: lon, elevation: elevationM))
        }
    }

    private struct BodyFixture: Decodable {
        let cases: [BodyCase]
    }

    /// Maximum acceptable angular error in arcseconds of an apparent position, by body. The Sun and
    /// planets come from truncated VSOP87 (observed maxima 0.2″ Sun, 0.6″ Mercury, 1.6″ Venus, 4.8″
    /// Mars, 2.7″ Jupiter, 4.3″ Saturn, 4.2″ Uranus, 4.1″ Neptune); the Moon from Meeus' truncated
    /// ELP-2000 (8.1″). The limits leave room for other instants and platforms.
    private static let positionToleranceArcseconds: [SolarSystemBody: Double] = [
        .sun: 1, .moon: 15, .mercury: 2, .venus: 4, .mars: 10, .jupiter: 6, .saturn: 8, .uranus: 8, .neptune: 8,
    ]

    /// Maximum acceptable relative error of the geocentric and heliocentric distances.
    private static let distanceToleranceRelative: [SolarSystemBody: Double] = [
        .sun: 5e-6, .moon: 2.5e-4, .mercury: 1e-5, .venus: 2e-5, .mars: 4e-5, .jupiter: 4e-5, .saturn: 5e-5,
        .uranus: 4e-5, .neptune: 3e-5,
    ]

    private func fixtureCases() throws -> [BodyCase] {
        let cases = try EphemerisFixtureStore.load(BodyFixture.self, from: "bodies_apparent.json").cases
        XCTAssertEqual(cases.count, 450, "50 instants x 9 bodies")
        for body in SolarSystemBody.allCases {
            XCTAssertEqual(cases.filter { $0.solarSystemBody == body }.count, 50, "cases for \(body)")
        }
        return cases
    }

    private func assertAngle(_ error: Double, within tolerance: Double, _ what: String, _ fixtureCase: BodyCase,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(error, tolerance,
                                 "\(fixtureCase.body) \(what) at \(fixtureCase.utc): \(error)″ > \(tolerance)″",
                                 file: file, line: line)
    }

    // MARK: Positions

    func testGeocentricJ2000DirectionMatchesDE440s() throws {
        for fixtureCase in try fixtureCases() {
            let body = fixtureCase.solarSystemBody
            let state = Ephemeris.state(of: body, at: fixtureCase.julianDate)
            let expected = EquatorialCoordinate(rightAscension: fixtureCase.raApparentJ2000Deg,
                                                declination: fixtureCase.decApparentJ2000Deg)
            let error = EquatorialCoordinate(vector: state.geocentricJ2000).angularSeparation(to: expected) * 3600
            assertAngle(error, within: Self.positionToleranceArcseconds[body] ?? 0, "J2000 direction", fixtureCase)
            XCTAssertEqual(state.geocentricJ2000, Ephemeris.geocentricJ2000(of: body, at: fixtureCase.julianDate))
        }
    }

    /// The apparent ecliptic coordinates of date follow from the fixture's apparent place of date and the true
    /// obliquity: λ includes the nutation in longitude, β is relative to the mean ecliptic of date.
    func testEclipticCoordinatesOfDateMatchDE440s() throws {
        for fixtureCase in try fixtureCases() {
            let body = fixtureCase.solarSystemBody
            let jd = fixtureCase.julianDate
            let trueObliquity = Obliquity.mean(jd) + Nutation(julianDate: jd).obliquity
            let place = EquatorialCoordinate(rightAscension: fixtureCase.raApparentDeg, declination: fixtureCase.decApparentDeg)
            let expected = CoordinateTransforms.equatorialToEcliptic(place, obliquity: trueObliquity)
            let state = Ephemeris.state(of: body, at: jd)
            let tolerance = (Self.positionToleranceArcseconds[body] ?? 0) / 3600
            XCTAssertEqual(AstroMath.normalizeSignedDegrees(state.eclipticLongitudeOfDate - expected.longitude)
                           * AstroMath.cosDeg(expected.latitude), 0, accuracy: tolerance,
                           "\(fixtureCase.body) ecliptic longitude at \(fixtureCase.utc)")
            XCTAssertEqual(state.eclipticLatitudeOfDate, expected.latitude, accuracy: tolerance,
                           "\(fixtureCase.body) ecliptic latitude at \(fixtureCase.utc)")
        }
    }

    func testGeocentricApparentPlaceOfDateMatchesDE440s() throws {
        for fixtureCase in try fixtureCases() {
            let body = fixtureCase.solarSystemBody
            let frame = SkyFrame(julianDate: fixtureCase.julianDate, observer: fixtureCase.observer)
            let expected = EquatorialCoordinate(rightAscension: fixtureCase.raApparentDeg,
                                                declination: fixtureCase.decApparentDeg)
            let error = frame.geocentricApparentEquatorial(of: body).angularSeparation(to: expected) * 3600
            assertAngle(error, within: Self.positionToleranceArcseconds[body] ?? 0, "apparent place of date", fixtureCase)
        }
    }

    func testTopocentricPlaceAndHorizontalCoordinatesMatchDE440s() throws {
        for fixtureCase in try fixtureCases() {
            let body = fixtureCase.solarSystemBody
            let tolerance = Self.positionToleranceArcseconds[body] ?? 0
            let frame = SkyFrame(julianDate: fixtureCase.julianDate, observer: fixtureCase.observer)

            let expectedPlace = EquatorialCoordinate(rightAscension: fixtureCase.raTopoDeg,
                                                     declination: fixtureCase.decTopoDeg)
            assertAngle(frame.topocentricEquatorial(of: body).angularSeparation(to: expectedPlace) * 3600,
                        within: tolerance, "topocentric place", fixtureCase)

            let expectedHorizontal = HorizontalCoordinate(azimuth: fixtureCase.azDeg, altitude: fixtureCase.altDeg)
            let geometric = frame.horizontal(of: body, refraction: false)
            assertAngle(geometric.angularSeparation(to: expectedHorizontal) * 3600, within: tolerance,
                        "azimuth and altitude", fixtureCase)

            // Refraction only ever raises the body, and by more the closer to the horizon it is.
            let refracted = frame.horizontal(of: body, refraction: true)
            XCTAssertGreaterThanOrEqual(refracted.altitude, geometric.altitude)
            XCTAssertEqual(refracted.azimuth, geometric.azimuth, accuracy: 1e-9)
        }
    }

    /// The same comparison with the library's own estimate of ΔT instead of Skyfield's: the Moon moves
    /// 0.55″ per second of time, so the ΔT model adds well under an arcsecond.
    func testPlaceFromDateUsesLibraryDeltaT() throws {
        for fixtureCase in try fixtureCases() {
            let body = fixtureCase.solarSystemBody
            let frame = SkyFrame(date: EphemerisFixtureStore.date(universalJulianDate: fixtureCase.ut1Jd),
                                 observer: fixtureCase.observer)
            let expectedHorizontal = HorizontalCoordinate(azimuth: fixtureCase.azDeg, altitude: fixtureCase.altDeg)
            let error = frame.horizontal(of: body, refraction: false).angularSeparation(to: expectedHorizontal) * 3600
            assertAngle(error, within: (Self.positionToleranceArcseconds[body] ?? 0) + 2, "altitude and azimuth", fixtureCase)
        }
    }

    // MARK: Distances and phases

    func testDistancesMatchDE440s() throws {
        for fixtureCase in try fixtureCases() {
            let body = fixtureCase.solarSystemBody
            let state = Ephemeris.state(of: body, at: fixtureCase.julianDate)
            let tolerance = Self.distanceToleranceRelative[body] ?? 0
            XCTAssertEqual(state.distanceAU / fixtureCase.distanceAu, 1, accuracy: tolerance,
                           "\(fixtureCase.body) distance at \(fixtureCase.utc)")
            XCTAssertEqual(state.distanceKilometers, state.distanceAU * SkyFrame.kilometersPerAU, accuracy: 1e-6)
            if let expected = fixtureCase.heliocentricDistanceAu {
                XCTAssertEqual(try XCTUnwrap(state.heliocentricDistanceAU) / expected, 1, accuracy: tolerance,
                               "\(fixtureCase.body) heliocentric distance at \(fixtureCase.utc)")
            }
        }
    }

    func testPhaseElongationAndIlluminationMatchDE440s() throws {
        for fixtureCase in try fixtureCases() {
            let state = Ephemeris.state(of: fixtureCase.solarSystemBody, at: fixtureCase.julianDate)
            guard let expectedFraction = fixtureCase.illuminatedFraction,
                  let expectedPhaseAngle = fixtureCase.phaseAngleDeg,
                  let expectedElongation = fixtureCase.elongationDeg else {
                XCTAssertEqual(fixtureCase.body, "sun")
                XCTAssertNil(state.illuminatedFraction)
                XCTAssertNil(state.phaseAngle)
                XCTAssertNil(state.elongation)
                continue
            }
            let message = "\(fixtureCase.body) at \(fixtureCase.utc)"
            XCTAssertEqual(try XCTUnwrap(state.illuminatedFraction), expectedFraction, accuracy: 0.0005, message)
            XCTAssertEqual(try XCTUnwrap(state.phaseAngle), expectedPhaseAngle, accuracy: 0.02, message)
            XCTAssertEqual(try XCTUnwrap(state.elongation), expectedElongation, accuracy: 0.01, message)
        }
    }

    /// Mallama & Hilton (2018) as implemented by Skyfield. Skyfield takes the Sun to be at the
    /// solar-system barycentre, which shifts r and α slightly; for Mercury at large phase angles that is
    /// worth up to 0.13 mag, for the others at most 0.03 mag (Uranus) — Skyfield also switches on its
    /// phase term for Uranus above 3.1° while this implementation ignores it.
    func testPlanetMagnitudesMatchMallamaHilton() throws {
        let tolerance: [SolarSystemBody: Double] = [
            .mercury: 0.2, .venus: 0.05, .mars: 0.05, .jupiter: 0.02, .saturn: 0.02, .uranus: 0.03, .neptune: 0.03,
        ]
        for fixtureCase in try fixtureCases() {
            let state = Ephemeris.state(of: fixtureCase.solarSystemBody, at: fixtureCase.julianDate)
            guard let expected = fixtureCase.apparentMagnitude else {
                XCTAssertFalse(fixtureCase.solarSystemBody.isPlanet, "planets have a magnitude in the fixture")
                continue
            }
            XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), expected,
                           accuracy: tolerance[fixtureCase.solarSystemBody] ?? 0,
                           "\(fixtureCase.body) magnitude at \(fixtureCase.utc)")
        }
    }

    // MARK: Moon-specific flags

    func testMoonWaxingFlagFollowsElongation() throws {
        for fixtureCase in try fixtureCases() where fixtureCase.solarSystemBody == .moon {
            let state = Ephemeris.state(of: .moon, at: fixtureCase.julianDate)
            let sun = Ephemeris.state(of: .sun, at: fixtureCase.julianDate)
            let difference = AstroMath.normalizeDegrees(state.eclipticLongitudeOfDate - sun.eclipticLongitudeOfDate)
            XCTAssertEqual(state.isWaxing, difference < 180, "Moon at \(fixtureCase.utc)")
        }
    }
}
