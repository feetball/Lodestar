import XCTest
import LodestarKit
@testable import AppCore

/// A tiny synthetic catalog (planets, poles and the Sun are always in it) with one comet.
private enum ObjectsHorizonFixture {
    private static let loaded: Result<Catalog, Error> = Result { try ObjectsHorizonFixture.makeCatalog() }

    static func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try loaded.get().object(id: id), id)
    }

    private static func file(_ key: String, _ records: [String]) -> Data {
        Data(#"{"schema":1,"\#(key)":[\#(records.joined(separator: ","))]}"#.utf8)
    }

    private static func makeCatalog() throws -> Catalog {
        let stars = [#"{"hip":1001,"n":"Alpha Test","c":"Ori","ra":10.0,"de":20.0,"m":0.5,"pa":100.0,"pd":-50.0}"#]
        let deepSky = [#"{"id":"M31","m":31,"ngc":[224],"names":["Andromeda Galaxy"],"t":"G","ra":10.68,"de":41.27,"c":"And","vm":3.4,"p":1}"#]
        let constellations = [
            #"{"abbr":"And","name":"Andromeda","genitive":"Andromedae","label":[10.0,40.0],"lines":[[[10.0,30.0],[20.0,40.0]]]}"#,
        ]
        let milkyWay = [#"{"level":1,"polygons":[[[10,10],[20,10],[20,20]]],"holes":[]}"#]
        let base = try Catalog(starsData: file("stars", stars), dsosData: file("objects", deepSky),
                               constellationsData: file("constellations", constellations),
                               milkyWayData: file("levels", milkyWay))
        let orbit = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: 1, eccentricity: 0.5, inclination: 20,
                                                    argumentOfPerihelion: 30, longitudeOfAscendingNode: 40,
                                                    perihelionJulianDayTT: 2_461_000, epochJulianDayTT: 2_461_200.5))
        let magnitudes = try XCTUnwrap(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 10))
        let comet = try XCTUnwrap(SmallBody(designation: "C/2099 A1", name: "Test Comet", kind: .comet, number: nil,
                                            orbit: orbit, photometry: .comet(magnitudes)))
        return base.withSmallBodies([comet])
    }

    /// A custom target at a J2000 place.
    static func target(rightAscension: Double, declination: Double) -> CelestialObject {
        CelestialObject.custom(name: "Target", j2000: EquatorialCoordinate(rightAscension: rightAscension,
                                                                           declination: declination))
    }

    static func observer(latitude: Double, longitude: Double = -105) -> Observer {
        Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: 1600))
    }

    static func context(horizon: HorizonProfile?, observer: Observer? = nil) -> ObserverContext {
        ObserverContext(observer: observer ?? self.observer(latitude: 40), timeZone: TimeZone.gmt, name: "Test",
                        source: .device, horizontalAccuracy: nil, timestamp: nil, horizon: horizon)
    }

    /// 2026-10-21 03:00 UTC.
    static let start = Date(timeIntervalSince1970: 1_792_551_600)

    static var day: DateInterval {
        DateInterval(start: start, duration: 24 * 3600)
    }

    /// A skyline of 30 degrees from azimuth 90 up to (not including) 180, and 0 elsewhere.
    static func wall() throws -> HorizonProfile {
        try XCTUnwrap(HorizonProfile(altitudes: (0..<360).map { (90..<180).contains($0) ? 30.0 : 0.0 }))
    }
}

final class ObjectsHorizonTests: XCTestCase {
    // MARK: The skyline of a context

    func testWithoutAContextThereIsNoSkyline() {
        XCTAssertNil(ObjectsHorizon.skyline(of: nil))
    }

    func testAContextWithoutARecordedHorizonHasNoSkyline() {
        XCTAssertNil(ObjectsHorizon.skyline(of: ObjectsHorizonFixture.context(horizon: nil)))
    }

    func testAFlatProfileCountsAsNoSkyline() {
        XCTAssertNil(ObjectsHorizon.skyline(of: ObjectsHorizonFixture.context(horizon: HorizonProfile.flat)))
        XCTAssertNil(ObjectsHorizon.skyline(of: ObjectsHorizonFixture.context(horizon: HorizonProfile.constant(0))))
    }

    func testARecordedProfileIsReturnedAsIs() throws {
        let constant = HorizonProfile.constant(10)
        XCTAssertEqual(ObjectsHorizon.skyline(of: ObjectsHorizonFixture.context(horizon: constant)), constant)
        let wall = try ObjectsHorizonFixture.wall()
        XCTAssertEqual(ObjectsHorizon.skyline(of: ObjectsHorizonFixture.context(horizon: wall)), wall)
    }

    func testAProfileBelowTheHorizonIsStillASkyline() {
        let low = HorizonProfile.constant(-2)
        XCTAssertFalse(low.isFlat)
        XCTAssertEqual(ObjectsHorizon.skyline(of: ObjectsHorizonFixture.context(horizon: low)), low)
    }

    // MARK: Visibility

    func testAnObjectAboveAConstantSkylineIsVisibleAndOneBelowIsNot() {
        let visibility = HorizonVisibility(profile: .constant(10))
        XCTAssertTrue(ObjectsHorizon.isVisible(altitude: 10.5, azimuth: 0, visibility: visibility))
        XCTAssertTrue(ObjectsHorizon.isVisible(altitude: 45, azimuth: 200, visibility: visibility))
        XCTAssertFalse(ObjectsHorizon.isVisible(altitude: 9.5, azimuth: 0, visibility: visibility))
        XCTAssertFalse(ObjectsHorizon.isVisible(altitude: -3, azimuth: 120, visibility: visibility))
    }

    func testVisibilityDependsOnTheAzimuth() throws {
        let visibility = HorizonVisibility(profile: try ObjectsHorizonFixture.wall())
        // Inside the 30-degree wall, 40 degrees clears it and 25 does not; outside, 25 degrees is fine.
        XCTAssertTrue(ObjectsHorizon.isVisible(altitude: 40, azimuth: 135, visibility: visibility))
        XCTAssertFalse(ObjectsHorizon.isVisible(altitude: 25, azimuth: 135, visibility: visibility))
        XCTAssertTrue(ObjectsHorizon.isVisible(altitude: 25, azimuth: 270, visibility: visibility))
        XCTAssertFalse(ObjectsHorizon.isVisible(altitude: -1, azimuth: 270, visibility: visibility))
    }

    func testVisibilityJudgesTheApparentAltitude() throws {
        // The altitudes of the lists are refracted, so the skyline is compared with them as they are: exactly at the
        // skyline is visible, a hair below is not.
        let visibility = HorizonVisibility(profile: try ObjectsHorizonFixture.wall())
        XCTAssertTrue(ObjectsHorizon.isVisible(altitude: 30.0, azimuth: 135, visibility: visibility))
        XCTAssertFalse(ObjectsHorizon.isVisible(altitude: 29.985, azimuth: 135, visibility: visibility))
    }

    // MARK: Rising and setting over a skyline

    func testAFixedObjectUsesTheSkylineSearchOfTheEngine() {
        let observer = ObjectsHorizonFixture.observer(latitude: 40)
        let visibility = HorizonVisibility(profile: .constant(10))
        let object = ObjectsHorizonFixture.target(rightAscension: 30, declination: 0)
        let result = ObjectsHorizon.riseTransitSet(for: object, visibility: visibility, observer: observer,
                                                   within: ObjectsHorizonFixture.day)
        let expected = visibility.riseTransitSet(forJ2000: EquatorialCoordinate(rightAscension: 30, declination: 0),
                                                 properMotion: nil, observer: observer, within: ObjectsHorizonFixture.day)
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.circumstance, .normal)
        XCTAssertNotNil(result.rise)
        XCTAssertNotNil(result.set)
    }

    func testAStarKeepsItsProperMotion() throws {
        let observer = ObjectsHorizonFixture.observer(latitude: 40)
        let visibility = HorizonVisibility(profile: .constant(10))
        let star = try ObjectsHorizonFixture.object("star.hip1001")
        guard case .fixed(let coordinate, let motion) = star.position else {
            return XCTFail("a star has a fixed place")
        }
        XCTAssertNotNil(motion)
        let result = ObjectsHorizon.riseTransitSet(for: star, visibility: visibility, observer: observer,
                                                   within: ObjectsHorizonFixture.day)
        let expected = visibility.riseTransitSet(forJ2000: coordinate, properMotion: motion, observer: observer,
                                                 within: ObjectsHorizonFixture.day)
        XCTAssertEqual(result, expected)
    }

    func testAPlanetUsesTheSkylineSearchForBodies() throws {
        let observer = ObjectsHorizonFixture.observer(latitude: 40)
        let visibility = HorizonVisibility(profile: .constant(10))
        let result = ObjectsHorizon.riseTransitSet(for: try ObjectsHorizonFixture.object("planet.mars"),
                                                   visibility: visibility, observer: observer,
                                                   within: ObjectsHorizonFixture.day)
        XCTAssertEqual(result, visibility.riseTransitSet(for: .mars, observer: observer, within: ObjectsHorizonFixture.day))
        let sun = ObjectsHorizon.riseTransitSet(for: try ObjectsHorizonFixture.object("sun"), visibility: visibility,
                                                observer: observer, within: ObjectsHorizonFixture.day)
        XCTAssertEqual(sun, visibility.riseTransitSet(for: .sun, observer: observer, within: ObjectsHorizonFixture.day))
    }

    func testACometIsFollowedAlongItsOwnTrack() throws {
        let observer = ObjectsHorizonFixture.observer(latitude: 40)
        let visibility = HorizonVisibility(profile: .constant(10))
        let comet = try ObjectsHorizonFixture.object("comet.C/2099 A1")
        let result = ObjectsHorizon.riseTransitSet(for: comet, visibility: visibility, observer: observer,
                                                   within: ObjectsHorizonFixture.day)
        let expected = visibility.riseTransitSet(
            of: { date in SkyFrame(date: date, observer: observer).horizontal(of: comet, refraction: false) },
            within: ObjectsHorizonFixture.day)
        XCTAssertEqual(result, expected)
    }

    func testTheSkylineDecidesWhetherAnObjectEverGetsUp() {
        let observer = ObjectsHorizonFixture.observer(latitude: 40)
        // On the celestial equator at latitude 40 an object never gets higher than 50 degrees.
        let equatorial = ObjectsHorizonFixture.target(rightAscension: 30, declination: 0)
        let high = ObjectsHorizon.riseTransitSet(for: equatorial, visibility: HorizonVisibility(profile: .constant(60)),
                                                 observer: observer, within: ObjectsHorizonFixture.day)
        XCTAssertEqual(high.circumstance, .alwaysDown)
        XCTAssertNil(high.rise)
        XCTAssertNil(high.set)
        // Declination +80 stays between 30 and 50 degrees: always above a 10-degree skyline, never above a 60-degree one.
        let circumpolar = ObjectsHorizonFixture.target(rightAscension: 30, declination: 80)
        let up = ObjectsHorizon.riseTransitSet(for: circumpolar, visibility: HorizonVisibility(profile: .constant(10)),
                                               observer: observer, within: ObjectsHorizonFixture.day)
        XCTAssertEqual(up.circumstance, .alwaysUp)
        let hidden = ObjectsHorizon.riseTransitSet(for: circumpolar, visibility: HorizonVisibility(profile: .constant(60)),
                                                   observer: observer, within: ObjectsHorizonFixture.day)
        XCTAssertEqual(hidden.circumstance, .alwaysDown)
        // Declination -80 never gets above the horizon at latitude 40.
        let southern = ObjectsHorizonFixture.target(rightAscension: 30, declination: -80)
        let never = ObjectsHorizon.riseTransitSet(for: southern, visibility: HorizonVisibility(profile: .constant(10)),
                                                  observer: observer, within: ObjectsHorizonFixture.day)
        XCTAssertEqual(never.circumstance, .alwaysDown)
    }

    // MARK: The celestial poles

    func testTheNorthPoleStandsStillAtTheLatitude() throws {
        let observer = ObjectsHorizonFixture.observer(latitude: 40)
        let pole = try ObjectsHorizonFixture.object("special.ncp")
        let visible = ObjectsHorizon.riseTransitSet(for: pole, visibility: HorizonVisibility(profile: .constant(10)),
                                                    observer: observer, within: ObjectsHorizonFixture.day)
        XCTAssertEqual(visible, RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: 40,
                                               circumstance: .alwaysUp))
        let hidden = ObjectsHorizon.riseTransitSet(for: pole, visibility: HorizonVisibility(profile: .constant(60)),
                                                   observer: observer, within: ObjectsHorizonFixture.day)
        XCTAssertEqual(hidden, RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: 40,
                                              circumstance: .alwaysDown))
    }

    func testTheSouthPoleIsBelowTheHorizonInTheNorthAndAboveItInTheSouth() throws {
        let pole = try ObjectsHorizonFixture.object("special.scp")
        let visibility = HorizonVisibility(profile: .constant(10))
        let north = ObjectsHorizon.riseTransitSet(for: pole, visibility: visibility,
                                                  observer: ObjectsHorizonFixture.observer(latitude: 40),
                                                  within: ObjectsHorizonFixture.day)
        XCTAssertEqual(north, RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: -40,
                                             circumstance: .alwaysDown))
        let south = ObjectsHorizon.riseTransitSet(for: pole, visibility: visibility,
                                                  observer: ObjectsHorizonFixture.observer(latitude: -40, longitude: 150),
                                                  within: ObjectsHorizonFixture.day)
        XCTAssertEqual(south, RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: 40,
                                             circumstance: .alwaysUp))
    }

    func testThePoleIsLookedUpDueNorthOrDueSouth() throws {
        // A skyline that is only high due north (azimuth 0 to 10) hides the north pole there but not the south pole,
        // which is looked up at azimuth 180 (it is above the horizon for an observer in the south).
        let ridge = try XCTUnwrap(HorizonProfile(altitudes: (0..<360).map { (0..<10).contains($0) ? 55.0 : 0.0 }))
        let visibility = HorizonVisibility(profile: ridge)
        let north = ObjectsHorizon.riseTransitSet(for: try ObjectsHorizonFixture.object("special.ncp"), visibility: visibility,
                                                  observer: ObjectsHorizonFixture.observer(latitude: 40),
                                                  within: ObjectsHorizonFixture.day)
        XCTAssertEqual(north.circumstance, .alwaysDown, "the pole stands at 40 degrees behind a 55-degree ridge at azimuth 0")
        let south = ObjectsHorizon.riseTransitSet(for: try ObjectsHorizonFixture.object("special.scp"), visibility: visibility,
                                                  observer: ObjectsHorizonFixture.observer(latitude: -40, longitude: 150),
                                                  within: ObjectsHorizonFixture.day)
        XCTAssertEqual(south.circumstance, .alwaysUp, "due south there is no ridge")
    }
}
