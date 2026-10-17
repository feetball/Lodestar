import XCTest
@testable import LodestarKit

/// The polar-scope reading: its clock convention, its invariants over a day, and worked examples.
final class PolarAlignmentTests: XCTestCase {
    private typealias Support = PlanningTestSupport

    private let boulder = Support.boulder          // 40° N, 105.27° W
    private let paranal = Support.paranal          // 24.63° S, 70.40° W
    private let sydney = Support.sydney            // 33.87° S, 151.21° E

    /// Degrees of hour angle per second: a sidereal day is 86 164.0905 s.
    private let siderealRate = 360.985_647_366_29 / 86_400

    private let origin = Date(timeIntervalSince1970: 1_792_195_200)          // 2026-10-17T00:00:00Z

    private func frame(_ site: PlanningTestSupport.Site, _ date: Date) -> SkyFrame {
        SkyFrame(date: date, observer: site.observer)
    }

    private func reading(_ site: PlanningTestSupport.Site, _ date: Date, _ hemisphere: PolarAlignment.Hemisphere,
                         _ view: PolarAlignment.ScopeView = .naked) -> PolarScopeReading {
        PolarAlignment.polarScopeReading(frame: frame(site, date), hemisphere: hemisphere, view: view)
    }

    /// Difference of two angles in degrees, in (−180, 180].
    private func difference(_ a: Double, _ b: Double) -> Double { AstroMath.normalizeSignedDegrees(a - b) }

    /// The instant after `date` at which the reference star's hour angle is `target` degrees.
    private func instant(ofHourAngle target: Double, after date: Date, _ site: PlanningTestSupport.Site,
                         _ hemisphere: PolarAlignment.Hemisphere) -> Date {
        var current = date
        for _ in 0..<6 {
            let error = difference(target, reading(site, current, hemisphere).hourAngle)
            current = current.addingTimeInterval(error / siderealRate)
        }
        return current
    }

    // MARK: Worked examples

    /// Numbers worked out by hand from Skyfield's apparent places and sidereal time (the fixtures), not from
    /// LodestarKit. At 2026-10-17T00:00:00Z Greenwich apparent sidereal time is 1.7010005 h = 25.5150°.
    func testPolarisFromBoulderAtSixPM() {
        // Polaris: apparent RA 47.174033°, Dec +89.374866°. Local apparent sidereal time at 105.27° W is
        // 25.5150° − 105.27° = −79.7550°, so the hour angle is −79.7550° − 47.1740° = −126.9290°. Facing north the
        // sky turns counter-clockwise, so the clock angle is +126.929°: 4 h 13.9 min. Pole distance 0.62513°.
        let result = reading(boulder, origin, .north)
        XCTAssertEqual(result.referenceStarName, "Polaris")
        XCTAssertEqual(result.hourAngle, -126.929_025, accuracy: 0.002)
        XCTAssertEqual(result.angle, 126.929_025, accuracy: 0.002)
        XCTAssertEqual(result.clockPosition, 4.230_968, accuracy: 0.0001)
        XCTAssertEqual(result.separationFromPole, 0.625_134, accuracy: 0.0001)
        XCTAssertEqual(result.poleAltitude, 40, accuracy: 1e-6)
        XCTAssertEqual(result.poleAzimuth, 0, accuracy: 1e-6)

        let scope = reading(boulder, origin, .north, .inverted)
        XCTAssertEqual(scope.angle, 306.929_025, accuracy: 0.002)
        XCTAssertEqual(scope.clockPosition, 10.230_968, accuracy: 0.0001)
    }

    func testSigmaOctantisFromParanalAtEightPM() {
        // σ Octantis: apparent RA 322.785822°, Dec −88.847666°. Local sidereal time at 70.40° W is
        // 25.5150° − 70.40° = −44.8850°, so the hour angle is −44.8850° − 322.7858° = −367.6708°, which is
        // −7.6708°. Facing south the sky turns clockwise: the clock angle is 352.329°, or 11 h 44.6 min,
        // half an hour before the star stands directly above the pole. Pole distance 1.15233°.
        let result = reading(paranal, origin, .south)
        XCTAssertEqual(result.referenceStarName, "σ Octantis")
        XCTAssertEqual(result.hourAngle, -7.670_814, accuracy: 0.002)
        XCTAssertEqual(result.angle, 352.329_186, accuracy: 0.002)
        XCTAssertEqual(result.clockPosition, 11.744_306, accuracy: 0.0001)
        XCTAssertEqual(result.separationFromPole, 1.152_334, accuracy: 0.0001)
        XCTAssertEqual(result.poleAltitude, 24.63, accuracy: 1e-6)
        XCTAssertEqual(result.poleAzimuth, 180, accuracy: 1e-6)
    }

    func testSigmaOctantisFromSydneyAtElevenAM() {
        // Sydney, 151.21° E: local sidereal time 25.5150° + 151.21° = 176.7250°; the hour angle is
        // 176.7250° − 322.7858° = −146.0608°; clockwise from the top that is 213.939°, or 7 h 8 min.
        let result = reading(sydney, origin, .south)
        XCTAssertEqual(result.hourAngle, -146.060_814, accuracy: 0.002)
        XCTAssertEqual(result.angle, 213.939_186, accuracy: 0.002)
        XCTAssertEqual(result.clockPosition, 7.131_306, accuracy: 0.0001)
        XCTAssertEqual(result.view, .naked)
        XCTAssertEqual(result.hemisphere, .south)
    }

    // MARK: The clock convention

    func testNorthernSkyTurnsCounterClockwiseWithUpperCulminationAtTwelve() {
        let upper = instant(ofHourAngle: 0, after: origin, boulder, .north)
        // "Hours" are sidereal hours, 3 600 / 1.0027379 s each; clock readings are compared on the dial, so 11.999 is near 0.
        func offDial(afterHours hours: Double, expected: Double) -> Double {
            let clock = reading(boulder, upper.addingTimeInterval(hours * 3_600 / 1.002_737_909), .north).clockPosition
            return difference(clock * 30, expected * 30) / 30
        }
        XCTAssertEqual(offDial(afterHours: 0, expected: 0), 0, accuracy: 0.003, "12:00, directly above the pole")
        XCTAssertEqual(offDial(afterHours: 6, expected: 9), 0, accuracy: 0.003, "a quarter turn counter-clockwise: 9:00")
        XCTAssertEqual(offDial(afterHours: 12, expected: 6), 0, accuracy: 0.003, "lower culmination, directly below the pole")
        XCTAssertEqual(offDial(afterHours: 18, expected: 3), 0, accuracy: 0.003)
        XCTAssertEqual(offDial(afterHours: -6, expected: 3), 0, accuracy: 0.003, "six hours before upper culmination: 3:00")
    }

    func testSouthernSkyTurnsClockwiseWithUpperCulminationAtTwelve() {
        let upper = instant(ofHourAngle: 0, after: origin, paranal, .south)
        func offDial(afterHours hours: Double, expected: Double) -> Double {
            let clock = reading(paranal, upper.addingTimeInterval(hours * 3_600 / 1.002_737_909), .south).clockPosition
            return difference(clock * 30, expected * 30) / 30
        }
        XCTAssertEqual(offDial(afterHours: 0, expected: 0), 0, accuracy: 0.003)
        XCTAssertEqual(offDial(afterHours: 6, expected: 3), 0, accuracy: 0.003, "a quarter turn clockwise: 3:00")
        XCTAssertEqual(offDial(afterHours: 12, expected: 6), 0, accuracy: 0.003)
        XCTAssertEqual(offDial(afterHours: 18, expected: 9), 0, accuracy: 0.003)
    }

    func testUpperCulminationPutsTheStarStraightAboveThePoleInTheSky() throws {
        // At upper culmination the star is on the meridian on the zenith side of the pole, so it is higher
        // than the pole; at lower culmination it is lower.
        for (site, hemisphere) in [(boulder, PolarAlignment.Hemisphere.north), (paranal, .south)] {
            let upper = instant(ofHourAngle: 0, after: origin, site, hemisphere)
            let lower = instant(ofHourAngle: 180, after: origin, site, hemisphere)
            let star = hemisphere == .north ? PolarAlignment.polaris : PolarAlignment.sigmaOctantis
            func height(_ date: Date) -> (star: Double, pole: Double) {
                let skyFrame = frame(site, date)
                return (skyFrame.horizontal(j2000: star.position, properMotion: star.properMotion, refraction: false).altitude,
                        skyFrame.horizontalOfCelestialPole(north: hemisphere == .north, refraction: false).altitude)
            }
            XCTAssertGreaterThan(height(upper).star, height(upper).pole + 0.5, "\(hemisphere)")
            XCTAssertLessThan(height(lower).star, height(lower).pole - 0.5, "\(hemisphere)")
            XCTAssertEqual(difference(reading(site, upper, hemisphere).angle, 0), 0, accuracy: 0.001)
            XCTAssertEqual(difference(reading(site, lower, hemisphere).angle, 180), 0, accuracy: 0.001)
        }
    }

    func testInvertedViewIsTurnedThroughSixHours() {
        for hemisphere in PolarAlignment.Hemisphere.allCases {
            for hours in stride(from: 0.0, to: 24, by: 1.7) {
                let date = origin.addingTimeInterval(hours * 3_600)
                let naked = reading(boulder, date, hemisphere)
                let inverted = reading(boulder, date, hemisphere, .inverted)
                XCTAssertEqual(naked.view, .naked)
                XCTAssertEqual(inverted.view, .inverted)
                XCTAssertEqual(difference(inverted.angle, naked.angle + 180), 0, accuracy: 1e-9)
                let hourShift = (inverted.clockPosition - naked.clockPosition + 12).truncatingRemainder(dividingBy: 12)
                XCTAssertEqual(hourShift, 6, accuracy: 1e-9)
                XCTAssertEqual(inverted.hourAngle, naked.hourAngle)
                XCTAssertEqual(inverted.separationFromPole, naked.separationFromPole)
            }
        }
    }

    // MARK: Invariants

    func testReadingsStayInRangeAndAgreeWithTheirDefinitionsThroughADay() {
        for (site, hemisphere) in [(boulder, PolarAlignment.Hemisphere.north), (paranal, .south), (sydney, .south)] {
            for step in 0..<288 {
                let date = origin.addingTimeInterval(Double(step) * 300)
                for view in PolarAlignment.ScopeView.allCases {
                    let result = reading(site, date, hemisphere, view)
                    let label = "\(site.name) \(hemisphere) \(view) +\(step * 5) min"
                    XCTAssertTrue((0..<360).contains(result.angle), label)
                    XCTAssertTrue((0..<12).contains(result.clockPosition), label)
                    XCTAssertEqual(result.clockPosition * 30, result.angle, accuracy: 1e-9, label)
                    XCTAssertTrue(result.hourAngle > -180 && result.hourAngle <= 180, label)
                    XCTAssertEqual(result.hemisphere, hemisphere, label)
                    XCTAssertEqual(result.poleAltitude, hemisphere == .north ? site.latitude : -site.latitude,
                                   accuracy: 1e-6, label)
                    XCTAssertEqual(result.poleAzimuth, hemisphere == .north ? 0 : 180, accuracy: 1e-6, label)
                }
            }
        }
    }

    func testTheStarMovesAroundTheClockAtTheSiderealRate() {
        for (site, hemisphere, direction) in [(boulder, PolarAlignment.Hemisphere.north, -1.0), (paranal, .south, 1.0)] {
            var previous = reading(site, origin, hemisphere).angle
            for hour in 1...30 {
                let angle = reading(site, origin.addingTimeInterval(Double(hour) * 3_600), hemisphere).angle
                XCTAssertEqual(difference(angle, previous), direction * siderealRate * 3_600, accuracy: 0.002,
                               "\(hemisphere) hour \(hour)")
                previous = angle
            }
        }
    }

    func testTheReadingRepeatsAfterOneSiderealDay() {
        let siderealDay = 86_400 / 1.002_737_909_350_795
        for (site, hemisphere) in [(boulder, PolarAlignment.Hemisphere.north), (paranal, .south)] {
            let first = reading(site, origin, hemisphere)
            let next = reading(site, origin.addingTimeInterval(siderealDay), hemisphere)
            XCTAssertEqual(difference(next.angle, first.angle), 0, accuracy: 0.01)
            XCTAssertEqual(next.separationFromPole, first.separationFromPole, accuracy: 3e-4)
        }
    }

    func testPoleDistanceIsStableThroughTheNightAndAtTheExpectedSize() {
        var polaris = [Double](), sigma = [Double]()
        for step in 0..<144 {
            let date = origin.addingTimeInterval(Double(step) * 600)
            polaris.append(reading(boulder, date, .north).separationFromPole)
            sigma.append(reading(paranal, date, .south).separationFromPole)
        }
        XCTAssertLessThan((polaris.max() ?? 0) - (polaris.min() ?? 0), 0.0005, "under two arcseconds a day")
        XCTAssertLessThan((sigma.max() ?? 0) - (sigma.min() ?? 0), 0.0005)
        XCTAssertEqual(polaris[0], 0.625, accuracy: 0.01, "Polaris is 37.5′ from the pole in 2026")
        XCTAssertEqual(sigma[0], 1.152, accuracy: 0.01, "σ Octantis is 69′ from the pole in 2026")
    }

    func testPolarisSpiralsInTowardThePoleUntilTheTwentyTwentiesAndSigmaOctantisMovesOut() {
        // 2000 to 2060: the distance of Polaris from the pole falls from 0.7° to 0.45° while σ Octantis drifts away.
        func separations(_ year: Double) -> (north: Double, south: Double) {
            let date = Date(timeIntervalSince1970: (year - 1970) * 365.2425 * 86_400)
            return (reading(boulder, date, .north).separationFromPole, reading(paranal, date, .south).separationFromPole)
        }
        let early = separations(2000.5), late = separations(2040.5)
        XCTAssertLessThan(late.north, early.north)
        XCTAssertGreaterThan(late.south, early.south)
        XCTAssertEqual(early.north, 0.7, accuracy: 0.05)
    }

    // MARK: Hemispheres

    func testHemisphereFollowsTheSignOfTheLatitude() {
        XCTAssertEqual(PolarAlignment.Hemisphere(latitude: 40), .north)
        XCTAssertEqual(PolarAlignment.Hemisphere(latitude: 0), .north)
        XCTAssertEqual(PolarAlignment.Hemisphere(latitude: -0.0), .north)
        XCTAssertEqual(PolarAlignment.Hemisphere(latitude: -0.001), .south)
        XCTAssertEqual(PolarAlignment.Hemisphere(latitude: -89.9), .south)
        XCTAssertEqual(PolarAlignment.Hemisphere.allCases, [.north, .south])
    }

    func testReadingWithoutAHemisphereUsesTheObserversOwn() {
        for site in [boulder, paranal, sydney, Support.tromso, Support.quito] {
            let skyFrame = frame(site, origin)
            let automatic = PolarAlignment.polarScopeReading(frame: skyFrame)
            let expected = site.latitude < 0 ? PolarAlignment.Hemisphere.south : .north
            XCTAssertEqual(automatic, PolarAlignment.polarScopeReading(frame: skyFrame, hemisphere: expected), site.name)
            XCTAssertEqual(automatic.referenceStarName, expected == .north ? "Polaris" : "σ Octantis", site.name)
            XCTAssertEqual(PolarAlignment.polarScopeReading(frame: skyFrame, view: .inverted),
                           PolarAlignment.polarScopeReading(frame: skyFrame, hemisphere: expected, view: .inverted), site.name)
        }
    }

    func testThePoleOfTheOtherHemisphereIsBelowTheHorizon() {
        let polaris = reading(sydney, origin, .north)
        XCTAssertEqual(polaris.poleAltitude, -33.87, accuracy: 1e-6)
        XCTAssertEqual(polaris.poleAzimuth, 0, accuracy: 1e-6)
        XCTAssertTrue((0..<360).contains(polaris.angle))
        let sigma = reading(boulder, origin, .south)
        XCTAssertEqual(sigma.poleAltitude, -40, accuracy: 1e-6)
        XCTAssertEqual(sigma.poleAzimuth, 180, accuracy: 1e-6)
    }

    func testTheEquatorHasTheCelestialPolesOnTheHorizon() {
        let north = reading(Support.quito, origin, .north)
        let south = reading(Support.quito, origin, .south)
        XCTAssertEqual(north.poleAltitude, 0, accuracy: 1e-6)
        XCTAssertEqual(south.poleAltitude, 0, accuracy: 1e-6)
        XCTAssertEqual(north.poleAzimuth, 0, accuracy: 1e-6)
        XCTAssertEqual(south.poleAzimuth, 180, accuracy: 1e-6)
    }

    func testTheGeographicPolesHaveTheCelestialPoleAtTheZenith() {
        for (latitude, hemisphere) in [(90.0, PolarAlignment.Hemisphere.north), (-90.0, .south)] {
            let pole = Support.Site(name: "pole \(latitude)", latitude: latitude, longitude: 0)
            let result = reading(pole, origin, hemisphere)
            XCTAssertEqual(result.poleAltitude, 90, accuracy: 1e-6)
            XCTAssertTrue(result.angle.isFinite && (0..<360).contains(result.angle))
            XCTAssertTrue(result.separationFromPole > 0.5 && result.separationFromPole < 1.3)
        }
    }

    // MARK: The reference stars

    func testReferenceStarsAreNamedAndNumbered() {
        let polaris = reading(boulder, origin, .north)
        XCTAssertEqual(polaris.referenceStarName, "Polaris")
        XCTAssertEqual(polaris.hipparcosNumber, 11_767)
        let sigma = reading(paranal, origin, .south)
        XCTAssertEqual(sigma.referenceStarName, "σ Octantis")
        XCTAssertEqual(sigma.hipparcosNumber, 104_382)
    }

    /// The astrometry in `PolarAlignment` is the Hipparcos data in `Resources/stars.json` (HYG v4.1).
    func testAstrometryMatchesTheBundledStarCatalog() throws {
        struct Catalog: Decodable {
            struct Star: Decodable {
                let hip: Int?
                let ra: Double
                let de: Double
                let pa: Double?
                let pd: Double?
            }
            let stars: [Star]
        }
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/LodestarKit/Resources/stars.json")
        guard FileManager.default.isReadableFile(atPath: resources.path) else {
            throw XCTSkip("Resources/stars.json is not reachable from the test's source location (\(resources.path))")
        }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: resources))
        for star in [PolarAlignment.polaris, PolarAlignment.sigmaOctantis] {
            let entry = try XCTUnwrap(catalog.stars.first { $0.hip == star.hipparcosNumber }, star.name)
            let place = EquatorialCoordinate(rightAscension: entry.ra, declination: entry.de)
            XCTAssertEqual(star.position.angularSeparation(to: place) * 3_600, 0, accuracy: 0.05, "\(star.name): arcseconds apart")
            XCTAssertEqual(star.properMotion.raMilliarcsecondsPerYear, try XCTUnwrap(entry.pa), accuracy: 0.005, star.name)
            XCTAssertEqual(star.properMotion.decMilliarcsecondsPerYear, try XCTUnwrap(entry.pd), accuracy: 0.005, star.name)
        }
        XCTAssertEqual(PolarAlignment.polaris.hipparcosNumber, 11_767)
        XCTAssertEqual(PolarAlignment.sigmaOctantis.hipparcosNumber, 104_382)
    }

    func testReadingsWithTheSameValuesAreEqual() {
        let first = reading(boulder, origin, .north)
        XCTAssertEqual(first, reading(boulder, origin, .north))
        XCTAssertNotEqual(first, reading(boulder, origin, .north, .inverted))
        XCTAssertNotEqual(first, reading(boulder, origin.addingTimeInterval(60), .north))
    }
}
