import XCTest
@testable import LodestarKit

/// The SkyFrame and rise/set helpers for catalog objects.
final class CatalogSkyTests: XCTestCase {
    /// 2026-10-17 03:00 UT.
    private let date = JulianDate(ut: JulianDate.julianDay(year: 2026, month: 10, day: 17, hour: 3)).date

    private func observer(latitude: Double, longitude: Double = -105) -> Observer {
        Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: 0))
    }

    private func frame(latitude: Double = 40, at date: Date? = nil) -> SkyFrame {
        SkyFrame(date: date ?? self.date, observer: observer(latitude: latitude))
    }

    private func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try CatalogFixture.catalog().object(id: id), id)
    }

    // MARK: Horizontal coordinates

    func testPolarisStandsAtTheAltitudeOfTheLatitude() throws {
        let polaris = try object("star.hip11767")
        for latitude in [10.0, 25, 40, 52, 60] {
            let horizontal = frame(latitude: latitude).horizontal(of: polaris, refraction: false)
            // Polaris circles the pole at a distance of about 0.65°.
            XCTAssertEqual(horizontal.altitude, latitude, accuracy: 0.8, "latitude \(latitude)")
        }
        let atForty = frame().horizontal(of: polaris, refraction: false)
        XCTAssertLessThan(min(atForty.azimuth, 360 - atForty.azimuth), 2.5, "Polaris is due north")
        let refracted = frame().horizontal(of: polaris, refraction: true)
        XCTAssertGreaterThan(refracted.altitude, atForty.altitude)
        XCTAssertLessThan(refracted.altitude - atForty.altitude, 0.05)
        XCTAssertEqual(frame().horizontal(of: polaris), refracted, "refraction is on by default")
    }

    func testPolesStandAtTheLatitudeAndItsNegative() throws {
        let north = try object("special.ncp")
        let south = try object("special.scp")
        for latitude in [-60.0, -33.9, 0, 25, 40, 89] {
            let skyFrame = frame(latitude: latitude)
            let ncp = skyFrame.horizontal(of: north, refraction: false)
            let scp = skyFrame.horizontal(of: south, refraction: false)
            XCTAssertEqual(ncp.altitude, latitude, accuracy: 1e-9)
            XCTAssertEqual(scp.altitude, -latitude, accuracy: 1e-9)
            if abs(latitude) < 89 {
                XCTAssertEqual(AstroMath.normalizeSignedDegrees(ncp.azimuth), 0, accuracy: 1e-7, "north pole is due north")
                XCTAssertEqual(scp.azimuth, 180, accuracy: 1e-7, "south pole is due south")
            }
        }
        let refracted = frame().horizontal(of: north, refraction: true)
        XCTAssertEqual(refracted.altitude - 40, 0.0194, accuracy: 0.004, "about 1.2′ of refraction at 40°")
        XCTAssertEqual(frame(latitude: -34).horizontal(of: north, refraction: true).altitude, -34, accuracy: 1e-9,
                       "no refraction far below the horizon")
    }

    func testSolarSystemObjectsMatchTheEphemeris() throws {
        let skyFrame = frame()
        for body in SolarSystemBody.allCases {
            let id = body == .sun ? "sun" : body == .moon ? "moon" : "planet.\(body.rawValue)"
            let catalogObject = try object(id)
            for refraction in [true, false] {
                XCTAssertEqual(skyFrame.horizontal(of: catalogObject, refraction: refraction),
                               skyFrame.horizontal(of: body, refraction: refraction), id)
            }
            XCTAssertEqual(skyFrame.apparentEquatorial(of: catalogObject), skyFrame.topocentricEquatorial(of: body), id)
        }
        // The Sun at 03:00 UT over Colorado is below the horizon; the Moon is topocentric.
        XCTAssertLessThan(skyFrame.horizontal(of: try object("sun"), refraction: false).altitude, 0)
        let moon = try object("moon")
        let topocentric = skyFrame.apparentEquatorial(of: moon)
        let geocentric = skyFrame.geocentricApparentEquatorial(of: .moon)
        XCTAssertGreaterThan(topocentric.angularSeparation(to: geocentric), 0.05, "lunar parallax is up to a degree")
    }

    func testFixedObjectsIncludeProperMotionAndTheApparentPlace() throws {
        let skyFrame = frame()
        for id in ["star.hip32349", "star.hip87937", "dso.M31", "dso.NGC7000", "special.galacticCenter", "star.hip11767"] {
            let catalogObject = try object(id)
            guard case .fixed(let coordinate, let motion) = catalogObject.position else { return XCTFail(id) }
            XCTAssertEqual(skyFrame.horizontal(of: catalogObject, refraction: false),
                           skyFrame.horizontal(j2000: coordinate, properMotion: motion, refraction: false), id)
            XCTAssertEqual(skyFrame.apparentEquatorial(of: catalogObject), skyFrame.apparentPlace(j2000: coordinate, properMotion: motion), id)
        }
        // Barnard's Star moves 10.3″ a year; since 2000 that is more than 4′.
        let barnard = try object("star.hip87937")
        guard case .fixed(let coordinate, _) = barnard.position else { return XCTFail("fixed") }
        let moved = skyFrame.apparentEquatorial(of: barnard)
        let still = skyFrame.apparentPlace(j2000: coordinate, properMotion: nil)
        XCTAssertEqual(moved.angularSeparation(to: still), 0.077, accuracy: 0.01)
    }

    func testPoleApparentPlaceIsTheTruePole() throws {
        let skyFrame = frame()
        XCTAssertEqual(skyFrame.apparentEquatorial(of: try object("special.ncp")), EquatorialCoordinate(rightAscension: 0, declination: 90))
        XCTAssertEqual(skyFrame.apparentEquatorial(of: try object("special.scp")), EquatorialCoordinate(rightAscension: 0, declination: -90))
    }

    func testCustomTargetsBehaveLikeFixedObjects() throws {
        let position = EquatorialCoordinate(rightAscension: 150, declination: 10)
        let target = CelestialObject.custom(name: "Leo field", j2000: position)
        let skyFrame = frame()
        XCTAssertEqual(skyFrame.horizontal(of: target), skyFrame.horizontal(j2000: position, properMotion: nil, refraction: true))
        XCTAssertEqual(skyFrame.apparentEquatorial(of: target), skyFrame.apparentPlace(j2000: position))
        XCTAssertNil(skyFrame.currentAngularSize(of: target))
        XCTAssertNil(skyFrame.currentMagnitude(of: target))
        let transit = RiseSetCalculator.riseTransitSet(for: target, observer: observer(latitude: 40),
                                                       within: DateInterval(start: date, duration: 86_400))
        XCTAssertEqual(transit, RiseSetCalculator.riseTransitSet(forJ2000: position, observer: observer(latitude: 40),
                                                                 within: DateInterval(start: date, duration: 86_400)))
    }

    func testEveryCatalogObjectHasAFinitePosition() throws {
        let catalog = try CatalogFixture.catalog()
        let skyFrame = frame(latitude: -30, at: date)
        for object in catalog.objects {
            let horizontal = skyFrame.horizontal(of: object)
            XCTAssertTrue(horizontal.azimuth.isFinite && (0..<360).contains(horizontal.azimuth), object.id)
            XCTAssertTrue(horizontal.altitude.isFinite && (-90...90).contains(horizontal.altitude), object.id)
            let apparent = skyFrame.apparentEquatorial(of: object)
            XCTAssertTrue(apparent.rightAscension.isFinite && apparent.declination.isFinite, object.id)
        }
    }

    // MARK: Size and brightness

    func testCurrentAngularSizeOfSolarSystemBodies() throws {
        let moon = try object("moon")
        var sizes: [Double] = []
        for day in 0..<28 {
            let skyFrame = frame(at: date.addingTimeInterval(Double(day) * 86_400))
            let size = try XCTUnwrap(skyFrame.currentAngularSize(of: moon))
            XCTAssertEqual(size.majorArcminutes, skyFrame.state(of: .moon).angularDiameterArcseconds / 60, accuracy: 1e-12)
            XCTAssertEqual(size.minorArcminutes, size.majorArcminutes)
            XCTAssertNil(size.positionAngle)
            XCTAssertTrue((28.5...34.5).contains(size.majorArcminutes), "\(size.majorArcminutes)")
            sizes.append(size.majorArcminutes)
        }
        XCTAssertGreaterThan(try XCTUnwrap(sizes.max()) - (try XCTUnwrap(sizes.min())), 2, "the Moon's size changes through the month")
        let sun = try XCTUnwrap(frame().currentAngularSize(of: try object("sun")))
        XCTAssertEqual(sun.majorArcminutes, 32, accuracy: 0.6)
        let jupiter = try XCTUnwrap(frame().currentAngularSize(of: try object("planet.jupiter")))
        XCTAssertTrue((0.45...0.9).contains(jupiter.majorArcminutes), "\(jupiter.majorArcminutes)")
        XCTAssertTrue(jupiter.description.hasSuffix("″"), jupiter.description)
        XCTAssertTrue(try XCTUnwrap(frame().currentAngularSize(of: try object("moon"))).description.hasSuffix("′"))
    }

    func testCurrentAngularSizeOfOtherObjectsIsTheCatalogSize() throws {
        let skyFrame = frame()
        let m31 = try object("dso.M31")
        XCTAssertEqual(skyFrame.currentAngularSize(of: m31), m31.angularSize)
        XCTAssertEqual(skyFrame.currentAngularSize(of: m31)?.description, "178′ × 70′")
        XCTAssertNil(skyFrame.currentAngularSize(of: try object("star.hip32349")))
        XCTAssertNil(skyFrame.currentAngularSize(of: try object("special.ncp")))
    }

    func testCurrentMagnitude() throws {
        let skyFrame = frame()
        XCTAssertEqual(try XCTUnwrap(skyFrame.currentMagnitude(of: try object("sun"))), -26.7, accuracy: 0.3)
        let moon = try XCTUnwrap(skyFrame.currentMagnitude(of: try object("moon")))
        XCTAssertTrue((-13.5 ... -2).contains(moon), "\(moon)")
        let jupiter = try XCTUnwrap(skyFrame.currentMagnitude(of: try object("planet.jupiter")))
        XCTAssertTrue((-3.0 ... -1.4).contains(jupiter), "\(jupiter)")
        XCTAssertEqual(skyFrame.currentMagnitude(of: try object("star.hip32349")), -1.44)
        XCTAssertEqual(skyFrame.currentMagnitude(of: try object("dso.M31")), 3.44)
        XCTAssertNil(skyFrame.currentMagnitude(of: try object("special.scp")))
        XCTAssertNil(skyFrame.currentMagnitude(of: try object("dso.B33")))
    }

    // MARK: Rise, transit and set

    func testRiseTransitSetOfAFixedObject() throws {
        let interval = DateInterval(start: date, duration: 86_400)
        let place = observer(latitude: 40)
        let m31 = try object("dso.M31")
        let result = RiseSetCalculator.riseTransitSet(for: m31, observer: place, within: interval)
        XCTAssertEqual(result.circumstance, .normal)
        let rise = try XCTUnwrap(result.rise), set = try XCTUnwrap(result.set), transit = try XCTUnwrap(result.transit)
        XCTAssertTrue(interval.contains(rise) && interval.contains(set) && interval.contains(transit))
        // 90° minus the distance in declination (of date) from the latitude, geometric.
        let apparentDeclination = frame().apparentEquatorial(of: m31).declination
        XCTAssertEqual(try XCTUnwrap(result.transitAltitude), 90 - abs(apparentDeclination - 40), accuracy: 0.02)
        guard case .fixed(let coordinate, let motion) = m31.position else { return XCTFail("fixed") }
        XCTAssertEqual(result, RiseSetCalculator.riseTransitSet(forJ2000: coordinate, properMotion: motion, observer: place, within: interval))
        // The altitude at the rise and set times is that of the standard horizon.
        for time in [rise, set] {
            let altitude = SkyFrame(date: time, observer: place).horizontal(of: m31, refraction: false).altitude
            XCTAssertEqual(altitude, RiseSetCalculator.standardHorizonAltitude, accuracy: 0.05)
        }
        let sirius = RiseSetCalculator.riseTransitSet(for: try object("star.hip32349"), observer: place, within: interval)
        let siriusDeclination = frame().apparentEquatorial(of: try object("star.hip32349")).declination
        XCTAssertEqual(try XCTUnwrap(sirius.transitAltitude), 90 - abs(siriusDeclination - 40), accuracy: 0.02)
    }

    func testRiseTransitSetOfSolarSystemBodiesUsesTheirOwnThresholds() throws {
        let interval = DateInterval(start: date, duration: 86_400)
        let place = observer(latitude: 40)
        for (id, body) in [("sun", SolarSystemBody.sun), ("moon", .moon), ("planet.jupiter", .jupiter), ("planet.venus", .venus)] {
            XCTAssertEqual(RiseSetCalculator.riseTransitSet(for: try object(id), observer: place, within: interval),
                           RiseSetCalculator.riseTransitSet(for: body, observer: place, within: interval), id)
        }
        let sun = RiseSetCalculator.riseTransitSet(for: try object("sun"), observer: place, within: interval)
        XCTAssertEqual(sun.circumstance, .normal)
        XCTAssertNotNil(sun.rise)
        XCTAssertNotNil(sun.set)
    }

    func testCircumpolarAndNeverRisingFixedObjects() throws {
        let interval = DateInterval(start: date, duration: 86_400)
        let polaris = try object("star.hip11767")
        XCTAssertEqual(RiseSetCalculator.riseTransitSet(for: polaris, observer: observer(latitude: 40), within: interval).circumstance, .alwaysUp)
        XCTAssertEqual(RiseSetCalculator.riseTransitSet(for: polaris, observer: observer(latitude: -40), within: interval).circumstance, .alwaysDown)
        let sirius = try object("star.hip32349")
        XCTAssertEqual(RiseSetCalculator.riseTransitSet(for: sirius, observer: observer(latitude: 80), within: interval).circumstance, .alwaysDown)
        XCTAssertEqual(RiseSetCalculator.riseTransitSet(for: sirius, observer: observer(latitude: -80), within: interval).circumstance, .alwaysUp)
    }

    func testCelestialPolesNeverRiseOrSet() throws {
        let interval = DateInterval(start: date, duration: 86_400)
        let north = try object("special.ncp")
        let south = try object("special.scp")
        let expectations: [(latitude: Double, north: RiseTransitSet.Circumstance, south: RiseTransitSet.Circumstance)] = [
            (40, .alwaysUp, .alwaysDown), (-40, .alwaysDown, .alwaysUp), (89, .alwaysUp, .alwaysDown), (-89, .alwaysDown, .alwaysUp),
            (0, .alwaysUp, .alwaysUp), (-0.5, .alwaysUp, .alwaysUp), (-0.6, .alwaysDown, .alwaysUp),
            (0.5, .alwaysUp, .alwaysUp), (0.6, .alwaysUp, .alwaysDown),
        ]
        for (latitude, northExpected, southExpected) in expectations {
            let place = observer(latitude: latitude)
            let ncp = RiseSetCalculator.riseTransitSet(for: north, observer: place, within: interval)
            let scp = RiseSetCalculator.riseTransitSet(for: south, observer: place, within: interval)
            XCTAssertEqual(ncp.circumstance, northExpected, "NCP at \(latitude)")
            XCTAssertEqual(scp.circumstance, southExpected, "SCP at \(latitude)")
            for result in [ncp, scp] {
                XCTAssertNil(result.rise)
                XCTAssertNil(result.set)
                XCTAssertNil(result.transit)
            }
            XCTAssertEqual(try XCTUnwrap(ncp.transitAltitude), latitude, accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(scp.transitAltitude), -latitude, accuracy: 1e-12)
        }
    }

    func testPolesAgreeWithTheHorizontalCoordinates() throws {
        let interval = DateInterval(start: date, duration: 3_600)
        for latitude in [-70.0, -20, 15, 48, 85] {
            let place = observer(latitude: latitude)
            let skyFrame = SkyFrame(date: date, observer: place)
            for id in ["special.ncp", "special.scp"] {
                let pole = try object(id)
                let result = RiseSetCalculator.riseTransitSet(for: pole, observer: place, within: interval)
                let altitude = skyFrame.horizontal(of: pole, refraction: false).altitude
                XCTAssertEqual(try XCTUnwrap(result.transitAltitude), altitude, accuracy: 1e-9)
                XCTAssertEqual(result.circumstance, altitude >= RiseSetCalculator.standardHorizonAltitude ? .alwaysUp : .alwaysDown)
            }
        }
    }
}
