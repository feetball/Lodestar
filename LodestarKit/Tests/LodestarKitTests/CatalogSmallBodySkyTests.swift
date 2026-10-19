import XCTest
@testable import LodestarKit

private typealias Fixture = CatalogSmallBodyFixture

/// The SkyFrame and rise/set helpers for the catalog objects of comets and asteroids.
final class CatalogSmallBodySkyTests: XCTestCase {
    private let observer = Observer(location: GeographicLocation(latitude: 40, longitude: -105, elevation: 1600))

    /// 2026-10-18 03:00 UT.
    private let date = JulianDate(ut: JulianDate.julianDay(year: 2026, month: 10, day: 18, hour: 3)).date

    private var frame: SkyFrame { SkyFrame(date: date, observer: observer) }

    private func bodies() throws -> [SmallBody] {
        try Fixture.comets + [try Fixture.oumuamua, try Fixture.ceres, try Fixture.vesta, try Fixture.eros, try Fixture.yr4]
    }

    func testHorizontalPositionEqualsTheCometsEngineState() throws {
        let skyFrame = frame
        for body in try bodies() {
            let object = CelestialObject(smallBody: body)
            for refraction in [true, false] {
                XCTAssertEqual(try XCTUnwrap(skyFrame.horizontal(of: body, refraction: refraction)),
                               skyFrame.horizontal(of: object, refraction: refraction), body.id)
            }
            XCTAssertEqual(skyFrame.horizontal(of: object, refraction: true), skyFrame.horizontal(of: object),
                           "refraction is on by default")
            // The same pipeline by hand: the state's apparent geocentric vector through the frame.
            let state = try XCTUnwrap(skyFrame.state(of: body))
            XCTAssertEqual(skyFrame.horizontal(geocentricJ2000: state.geocentricJ2000, refraction: true),
                           skyFrame.horizontal(of: object), body.id)
        }
    }

    func testApparentEquatorialPlaceIsTopocentric() throws {
        let skyFrame = frame
        for body in try bodies() {
            let object = CelestialObject(smallBody: body)
            XCTAssertEqual(try XCTUnwrap(skyFrame.topocentricEquatorial(of: body)), skyFrame.apparentEquatorial(of: object), body.id)
        }
        // Eros is 0.3 to 1 AU away in 2026: parallax moves it by arcminutes against the geocentric place.
        let eros = CelestialObject(smallBody: try Fixture.eros)
        let state = try XCTUnwrap(skyFrame.state(of: try Fixture.eros))
        let geocentric = EquatorialCoordinate(vector: skyFrame.precessionNutationMatrix * state.geocentricJ2000)
        XCTAssertGreaterThan(skyFrame.apparentEquatorial(of: eros).angularSeparation(to: geocentric), 0.001)
    }

    func testCurrentMagnitudeIsTheStateMagnitude() throws {
        let skyFrame = frame
        for body in try bodies() {
            let object = CelestialObject(smallBody: body)
            let expected = try XCTUnwrap(skyFrame.state(of: body)).apparentMagnitude
            XCTAssertNotNil(expected, body.id)
            XCTAssertEqual(skyFrame.currentMagnitude(of: object), expected, body.id)
        }
        let vesta = CelestialObject(smallBody: try Fixture.vesta)
        let magnitude = try XCTUnwrap(skyFrame.currentMagnitude(of: vesta))
        XCTAssertGreaterThanOrEqual(magnitude, try XCTUnwrap(vesta.estimatedPeakMagnitude) - 1e-9,
                                    "never brighter than the best case: \(magnitude)")
        XCTAssertNil(skyFrame.currentMagnitude(of: CelestialObject(smallBody: try Fixture.withoutMagnitude)),
                     "no parameters, no magnitude")
    }

    func testAngularSizeStaysTheCatalogSize() throws {
        let skyFrame = frame
        for body in try bodies() {
            XCTAssertNil(skyFrame.currentAngularSize(of: CelestialObject(smallBody: body)), body.id)
        }
    }

    func testRiseTransitSetEqualsTheCometsEngine() throws {
        let interval = DateInterval(start: JulianDate(ut: JulianDate.julianDay(year: 2026, month: 10, day: 18, hour: 12)).date,
                                    duration: 86_400)
        for body in [try Fixture.vesta, try Fixture.ceres, try Fixture.tsuchinshanAtlas, try Fixture.ponsBrooks] {
            let object = CelestialObject(smallBody: body)
            let expected = SmallBodyEphemeris.riseTransitSet(of: body, observer: observer, within: interval)
            XCTAssertEqual(RiseSetCalculator.riseTransitSet(for: object, observer: observer, within: interval), expected, body.id)
        }
        // Vesta in October 2026 is in Taurus-Aries, high in the night sky of Colorado: it rises, transits and sets once.
        let vesta = RiseSetCalculator.riseTransitSet(for: CelestialObject(smallBody: try Fixture.vesta), observer: observer,
                                                     within: interval)
        XCTAssertEqual(vesta.circumstance, .normal)
        XCTAssertNotNil(vesta.rise)
        XCTAssertNotNil(vesta.transit)
        XCTAssertNotNil(vesta.set)
    }

    func testObjectsOfSmallBodiesAreSolarSystemObjects() throws {
        for body in try bodies() {
            let object = CelestialObject(smallBody: body)
            XCTAssertTrue(object.isSolarSystem, body.id)
            XCTAssertNil(object.j2000, body.id)
        }
    }

    func testAnOrbitThatCannotBeEvaluatedIsBelowTheHorizon() throws {
        // 'Oumuamua is on a hyperbolic orbit; the two-body motion is only evaluated within 137 years of perihelion (2017).
        let farDate = JulianDate(ut: JulianDate.julianDay(year: 2200, month: 1, day: 1)).date
        let farFuture = SkyFrame(date: farDate, observer: observer)
        let object = CelestialObject(smallBody: try Fixture.oumuamua)
        XCTAssertNil(farFuture.state(of: try Fixture.oumuamua))
        XCTAssertEqual(farFuture.horizontal(of: object), HorizontalCoordinate(azimuth: 0, altitude: -90))
        XCTAssertEqual(farFuture.horizontal(of: object, refraction: false), HorizontalCoordinate(azimuth: 0, altitude: -90))
        XCTAssertEqual(farFuture.apparentEquatorial(of: object), EquatorialCoordinate(rightAscension: 0, declination: 0))
        XCTAssertNil(farFuture.currentMagnitude(of: object))
        let events = RiseSetCalculator.riseTransitSet(for: object, observer: observer,
                                                      within: DateInterval(start: farDate, duration: 86_400))
        XCTAssertNil(events.rise)
        XCTAssertNil(events.set)
        // Within the span it works.
        XCTAssertNotNil(frame.state(of: try Fixture.oumuamua))
    }
}
