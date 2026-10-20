import LodestarKit
import XCTest
@testable import AppCore

/// What lies under the reticle while there is no target: the nearest named thing within the tolerance.
final class AimLookAroundTests: XCTestCase {
    private enum Fixture {
        static let catalog = Result { try Catalog.loadBundled() }
    }

    private let observer = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    private let date = Date(timeIntervalSince1970: 1_784_178_000)

    /// The centre of the picture: due south, 40 degrees up.
    private let look = HorizontalCoordinate(azimuth: 180, altitude: 40).unitVector

    // MARK: Helpers

    private func object(_ id: String) throws -> CelestialObject {
        let catalog = try Fixture.catalog.get()
        return try XCTUnwrap(catalog.object(id: id), id)
    }

    /// A direction `offset` degrees above the centre of the picture (below it for a negative offset).
    private func direction(_ offset: Double) -> Vector3 {
        HorizontalCoordinate(azimuth: 180, altitude: 40 + offset).unitVector
    }

    private func star(_ id: String, offset: Double, magnitude: Double = 1.0, name: String? = "Starname") -> SkySnapshot.Star {
        SkySnapshot.Star(id: id, direction: direction(offset), magnitude: magnitude, colorIndex: nil, name: name)
    }

    private func body(_ object: CelestialObject, offset: Double) -> SkySnapshot.Body {
        let place = direction(offset)
        return SkySnapshot.Body(object: object, direction: place, horizontal: HorizontalCoordinate(vector: place),
                                magnitude: nil, angularDiameter: 0.5, illuminatedFraction: nil, isWaxing: nil)
    }

    private func deepSky(_ object: CelestialObject, offset: Double) -> SkySnapshot.DeepSky {
        SkySnapshot.DeepSky(object: object, direction: direction(offset), majorAxis: nil)
    }

    private func snapshot(stars: [SkySnapshot.Star] = [], bodies: [SkySnapshot.Body] = [],
                          deepSky: [SkySnapshot.DeepSky] = []) -> SkySnapshot {
        SkySnapshot(date: date, observer: observer, stars: stars, bodies: bodies, deepSky: deepSky, constellations: [],
                    milkyWay: [], target: nil, mosaic: [], smallBodies: [])
    }

    private func nearest(in snapshot: SkySnapshot, within radius: Double = 4) -> AimLookAround.Nearby? {
        AimLookAround.nearest(to: look, in: snapshot, within: radius)
    }

    // MARK: The tolerance

    func testTheToleranceIsATenthOfTheFieldOfViewBetweenTwoAndEightDegrees() {
        XCTAssertEqual(AimLookAround.radius(fieldOfView: 5), 2.0)
        XCTAssertEqual(AimLookAround.radius(fieldOfView: 20), 2.0)
        XCTAssertEqual(AimLookAround.radius(fieldOfView: 35), 3.5, accuracy: 1e-12)
        XCTAssertEqual(AimLookAround.radius(fieldOfView: 50), 5.0)
        XCTAssertEqual(AimLookAround.radius(fieldOfView: 80), 8.0)
        XCTAssertEqual(AimLookAround.radius(fieldOfView: 120), 8.0)
        XCTAssertEqual(AimLookAround.radius(fieldOfView: 0), 2.0)
        XCTAssertEqual(AimLookAround.radius(fieldOfView: -30), 2.0)
    }

    // MARK: Nothing close

    func testAnEmptySkyHasNothingUnderTheReticle() {
        XCTAssertNil(nearest(in: snapshot()))
    }

    func testNothingWithinTheToleranceGivesNone() throws {
        let sky = snapshot(stars: [star("star.a", offset: 3)], bodies: [body(try object("moon"), offset: 3.5)],
                           deepSky: [deepSky(try object("dso.M31"), offset: 3.2)])
        XCTAssertNil(nearest(in: sky, within: 2))
    }

    func testTheToleranceIsInclusiveUpToItsEdge() {
        let sky = snapshot(stars: [star("star.a", offset: 1.99)])
        XCTAssertEqual(nearest(in: sky, within: 2)?.id, "star.a")
        let outside = snapshot(stars: [star("star.a", offset: 2.01)])
        XCTAssertNil(nearest(in: outside, within: 2))
    }

    // MARK: Stars

    func testANamedBrightStarIsFoundWithItsSeparation() throws {
        let sky = snapshot(stars: [star("star.vega", offset: 1.5, magnitude: 0.03, name: "Vega")])
        let found = try XCTUnwrap(nearest(in: sky))
        XCTAssertEqual(found.id, "star.vega")
        XCTAssertEqual(found.name, "Vega")
        XCTAssertEqual(found.separation, 1.5, accuracy: 1e-9)
    }

    func testTheSeparationIsTheAngleOnTheSkyInEveryDirection() throws {
        let sideways = SkySnapshot.Star(id: "star.side", direction: HorizontalCoordinate(azimuth: 180 + 2, altitude: 40).unitVector,
                                        magnitude: 1, colorIndex: nil, name: "Side")
        let found = try XCTUnwrap(nearest(in: snapshot(stars: [sideways])))
        // Two degrees of azimuth at 40 degrees of altitude are 2 cos 40 = 1.53 degrees of arc.
        XCTAssertEqual(found.separation, 2 * AstroMath.cosDeg(40), accuracy: 0.01)
    }

    func testAStarWithoutANameIsNeverOffered() {
        let sky = snapshot(stars: [star("star.unnamed", offset: 0.5, name: nil)])
        XCTAssertNil(nearest(in: sky))
    }

    func testOnlyStarsOfMagnitudeThreeOrBrighterAreOffered() {
        XCTAssertEqual(nearest(in: snapshot(stars: [star("star.edge", offset: 1, magnitude: 3.0)]))?.id, "star.edge")
        XCTAssertEqual(nearest(in: snapshot(stars: [star("star.bright", offset: 1, magnitude: -1.4)]))?.id, "star.bright")
        XCTAssertNil(nearest(in: snapshot(stars: [star("star.faint", offset: 1, magnitude: 3.01)])))
    }

    func testTheNearerOfTwoStarsWinsWhateverTheOrder() {
        let near = star("star.near", offset: 1.0)
        let far = star("star.far", offset: -1.5)
        XCTAssertEqual(nearest(in: snapshot(stars: [near, far]))?.id, "star.near")
        XCTAssertEqual(nearest(in: snapshot(stars: [far, near]))?.id, "star.near")
    }

    func testAFainterStarDoesNotBeatABrighterOneThatIsNearer() {
        // Brightness plays no part among stars once they pass the limit: distance decides.
        let nearFaint = star("star.faint", offset: 0.5, magnitude: 2.9)
        let farBright = star("star.bright", offset: 2.0, magnitude: -1.0)
        XCTAssertEqual(nearest(in: snapshot(stars: [farBright, nearFaint]))?.id, "star.faint")
    }

    // MARK: Planets and the Moon

    func testTheMoonIsFoundByItsOwnName() throws {
        let moon = try object("moon")
        let found = try XCTUnwrap(nearest(in: snapshot(bodies: [body(moon, offset: 1.0)])))
        XCTAssertEqual(found.id, "moon")
        XCTAssertEqual(found.name, moon.name)
        XCTAssertEqual(found.separation, 1.0, accuracy: 1e-9)
    }

    func testAPlanetBeatsAStarThatIsSomewhatNearer() throws {
        // A body counts for half its distance: 3 degrees away it scores 1.5, a star 2 degrees away scores 2.
        let jupiter = try object("planet.jupiter")
        let sky = snapshot(stars: [star("star.near", offset: -2.0)], bodies: [body(jupiter, offset: 3.0)])
        let found = try XCTUnwrap(nearest(in: sky))
        XCTAssertEqual(found.id, "planet.jupiter")
        XCTAssertEqual(found.separation, 3.0, accuracy: 1e-9)
    }

    func testAStarMuchNearerThanAPlanetStillWins() throws {
        let jupiter = try object("planet.jupiter")
        let sky = snapshot(stars: [star("star.near", offset: -1.0)], bodies: [body(jupiter, offset: 3.0)])
        XCTAssertEqual(nearest(in: sky)?.id, "star.near")
    }

    func testAPlanetOutsideTheToleranceIsNotOffered() throws {
        let sky = snapshot(bodies: [body(try object("planet.mars"), offset: 5.0)])
        XCTAssertNil(nearest(in: sky, within: 4))
    }

    // MARK: Deep-sky objects

    func testABrightDeepSkyObjectIsFoundByName() throws {
        let m31 = try object("dso.M31")
        let found = try XCTUnwrap(nearest(in: snapshot(deepSky: [deepSky(m31, offset: -1.0)])))
        XCTAssertEqual(found.id, "dso.M31")
        XCTAssertEqual(found.name, m31.name)
        XCTAssertEqual(found.separation, 1.0, accuracy: 1e-9)
    }

    func testOnlyDeepSkyObjectsOfMagnitudeNineOrBrighterAreOffered() throws {
        let m87 = try object("dso.M87")
        let m70 = try object("dso.M70")
        XCTAssertEqual(m87.magnitude, 9.0)
        let faintestMagnitude = try XCTUnwrap(m70.magnitude)
        XCTAssertGreaterThan(faintestMagnitude, 9.0)
        XCTAssertEqual(nearest(in: snapshot(deepSky: [deepSky(m87, offset: 1.0)]))?.id, "dso.M87")
        XCTAssertNil(nearest(in: snapshot(deepSky: [deepSky(m70, offset: 1.0)])))
    }

    func testADeepSkyObjectWithoutAMagnitudeIsNeverOffered() {
        let target = CelestialObject.custom(name: "My field", j2000: EquatorialCoordinate(rightAscension: 10, declination: 41))
        XCTAssertNil(target.magnitude)
        XCTAssertNil(nearest(in: snapshot(deepSky: [deepSky(target, offset: 0.2)])))
    }

    func testADeepSkyObjectIsWeighedLikeAStar() throws {
        let m31 = try object("dso.M31")
        let sky = snapshot(stars: [star("star.far", offset: 2.0)], deepSky: [deepSky(m31, offset: 1.0)])
        XCTAssertEqual(nearest(in: sky)?.id, "dso.M31")
    }

    // MARK: Ties

    func testTwoStarsAtTheSamePlaceGiveTheFirstOne() {
        let first = star("star.first", offset: 1.0, name: "First")
        let second = star("star.second", offset: 1.0, name: "Second")
        XCTAssertEqual(nearest(in: snapshot(stars: [first, second]))?.id, "star.first")
        XCTAssertEqual(nearest(in: snapshot(stars: [second, first]))?.id, "star.second")
    }

    func testAStarAndADeepSkyObjectAtTheSamePlaceGiveTheStar() throws {
        let m31 = try object("dso.M31")
        let sky = snapshot(stars: [star("star.same", offset: 1.0)], deepSky: [deepSky(m31, offset: 1.0)])
        XCTAssertEqual(nearest(in: sky)?.id, "star.same")
    }

    func testABodyAndAStarExactlyAtTheCentreGiveTheBody() throws {
        let moon = try object("moon")
        let sky = snapshot(stars: [star("star.centre", offset: 0.0)], bodies: [body(moon, offset: 0.0)])
        let found = try XCTUnwrap(nearest(in: sky))
        XCTAssertEqual(found.id, "moon")
        XCTAssertEqual(found.separation, 0.0, accuracy: 1e-9)
    }

    func testTheResultsAreEquatable() {
        let a = AimLookAround.Nearby(id: "x", name: "X", separation: 1.0)
        XCTAssertEqual(a, AimLookAround.Nearby(id: "x", name: "X", separation: 1.0))
        XCTAssertNotEqual(a, AimLookAround.Nearby(id: "x", name: "X", separation: 1.5))
        XCTAssertNotEqual(a, AimLookAround.Nearby(id: "y", name: "X", separation: 1.0))
    }
}
