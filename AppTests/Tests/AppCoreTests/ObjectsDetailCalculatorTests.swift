import XCTest
import LodestarKit
@testable import AppCore

/// Objects, observers and instants for the detail calculator tests. The numbers the tests compare with come from the
/// LodestarKit engine itself (`SkyFrame`, `TwilightCalculator`, `RiseSetCalculator`, ...), called with the same inputs.
private enum ObjectsDetailFixture {
    private static let loaded: Result<Catalog, Error> = Result { try ObjectsDetailFixture.makeCatalog() }

    static func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try loaded.get().object(id: id), id)
    }

    private static func file(_ key: String, _ records: [String]) -> Data {
        Data(#"{"schema":1,"\#(key)":[\#(records.joined(separator: ","))]}"#.utf8)
    }

    private static func makeCatalog() throws -> Catalog {
        // The star is 10 parsecs away.
        let stars = [#"{"hip":1001,"n":"Alpha Test","c":"Ori","ra":10.0,"de":20.0,"m":0.5,"d":10.0}"#]
        let deepSky = [#"{"id":"M31","m":31,"ngc":[224],"names":["Andromeda Galaxy"],"t":"G","ra":10.68,"de":41.27,"c":"And","vm":3.4,"maj":178,"min":63,"p":1}"#]
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
    static func target(_ rightAscension: Double, _ declination: Double) -> CelestialObject {
        CelestialObject.custom(name: "Target", j2000: EquatorialCoordinate(rightAscension: rightAscension,
                                                                           declination: declination))
    }

    static let boulder = Observer(location: GeographicLocation(latitude: 40, longitude: -105, elevation: 1600))
    static let tromso = Observer(location: GeographicLocation(latitude: 69.65, longitude: 18.96, elevation: 0))

    static func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier), identifier)
    }

    static func context(_ observer: Observer, zone: TimeZone, horizon: HorizonProfile? = nil) -> ObserverContext {
        ObserverContext(observer: observer, timeZone: zone, name: "Test", source: .device, horizontalAccuracy: nil,
                        timestamp: nil, horizon: horizon)
    }

    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// 2026-10-21 03:00 UTC: 21:00 on the 20th in Colorado (MDT), well inside the night.
    static let evening = Date(timeIntervalSince1970: 1_792_551_600)
    /// 2026-10-21 09:00 UTC: 03:00 on the 21st in Colorado, before dawn.
    static let beforeDawn = Date(timeIntervalSince1970: 1_792_573_200)
    /// 2026-10-21 16:00 UTC: 10:00 on the 21st in Colorado, after sunrise.
    static let morning = Date(timeIntervalSince1970: 1_792_598_400)
    /// 2026-10-20 20:00 UTC: 14:00 on the 20th in Colorado.
    static let afternoon = Date(timeIntervalSince1970: 1_792_526_400)
    /// 2026-10-20 18:00 UTC: noon on the 20th in Colorado.
    static let noonOnTheTwentieth = Date(timeIntervalSince1970: 1_792_519_200)
    /// 2026-10-21 18:00 UTC: noon on the 21st in Colorado.
    static let noonOnTheTwentyFirst = Date(timeIntervalSince1970: 1_792_605_600)
    /// 2026-06-21 12:00 UTC: 14:00 in Norway in midsummer.
    static let midsummer = Date(timeIntervalSince1970: 1_782_043_200)
    /// 2026-12-21 12:00 UTC: 13:00 in Norway in midwinter.
    static let midwinter = Date(timeIntervalSince1970: 1_797_854_400)

    /// The first instant on a 15-minute grid, from `start` for at most `hours` hours, at which the Moon's position
    /// satisfies `condition`.
    static func firstInstant(from start: Date, hours: Int, observer: Observer = boulder,
                             where condition: (HorizontalCoordinate) -> Bool) -> Date? {
        for step in 0..<(hours * 4) {
            let date = start.addingTimeInterval(Double(step) * 900)
            if condition(SkyFrame(date: date, observer: observer).horizontal(of: .moon, refraction: false)) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Now

final class ObjectsDetailCurrentTests: XCTestCase {
    private func current(_ id: String, at date: Date = ObjectsDetailFixture.evening, skyline: HorizonProfile? = nil,
                          observer: Observer = ObjectsDetailFixture.boulder) throws -> ObjectDetailCurrent {
        ObjectDetailCalculator.current(of: try ObjectsDetailFixture.object(id), observer: observer, skyline: skyline, at: date)
    }

    private func skyFrame(_ date: Date = ObjectsDetailFixture.evening,
                       observer: Observer = ObjectsDetailFixture.boulder) -> SkyFrame {
        SkyFrame(date: date, observer: observer)
    }

    func testTheSampleStepIsTenMinutes() {
        XCTAssertEqual(ObjectDetailCalculator.sampleStep, 600)
    }

    func testADeepSkyObjectIsPlacedWithRefractionLikeTheAimScreen() throws {
        let andromeda = try ObjectsDetailFixture.object("dso.M31")
        let result = try current("dso.M31")
        let frame = skyFrame()
        XCTAssertEqual(result.date, ObjectsDetailFixture.evening)
        XCTAssertEqual(result.horizontal, frame.horizontal(of: andromeda, refraction: true))
        XCTAssertEqual(result.equatorial, frame.apparentEquatorial(of: andromeda))
        XCTAssertEqual(result.magnitude, 3.4)
        XCTAssertEqual(result.angularSize, andromeda.angularSize)
        XCTAssertEqual(result.angularSize?.majorArcminutes, 178)
        XCTAssertEqual(result.angularSize?.minorArcminutes, 63)
    }

    func testADeepSkyObjectHasNoDistancePhaseOrSmallBodyData() throws {
        let result = try current("dso.M31")
        XCTAssertNil(result.distance)
        XCTAssertNil(result.illuminatedFraction)
        XCTAssertNil(result.moonPhase)
        XCTAssertFalse(result.isBehindSkyline)
        XCTAssertFalse(result.isSmallBody)
        XCTAssertNil(result.smallBody)
    }

    func testAStarWithADistanceGivesItInLightYears() throws {
        let result = try current("star.hip1001")
        guard case .lightYears(let value)? = result.distance else {
            return XCTFail("expected a distance in light-years, got \(String(describing: result.distance))")
        }
        // 10 parsecs.
        XCTAssertEqual(value, 32.6156, accuracy: 0.001)
        XCTAssertEqual(result.magnitude, 0.5)
        XCTAssertNil(result.illuminatedFraction)
        XCTAssertNil(result.moonPhase)
    }

    func testTheMoonHasItsDistanceInKilometresItsPhaseAndItsSize() throws {
        let moon = try ObjectsDetailFixture.object("moon")
        let result = try current("moon")
        let frame = skyFrame()
        let state = frame.state(of: .moon)
        guard case .kilometers(let distance)? = result.distance else {
            return XCTFail("expected a distance in kilometers, got \(String(describing: result.distance))")
        }
        XCTAssertEqual(distance, state.distanceKilometers, accuracy: 1e-6)
        XCTAssertGreaterThan(distance, 350_000)
        XCTAssertLessThan(distance, 410_000)
        XCTAssertEqual(result.illuminatedFraction, state.illuminatedFraction)
        XCTAssertEqual(result.moonPhase, MoonPhaseCalculator.info(at: ObjectsDetailFixture.evening))
        XCTAssertEqual(result.magnitude, frame.currentMagnitude(of: moon))
        let size = try XCTUnwrap(result.angularSize)
        XCTAssertGreaterThan(size.majorArcminutes, 28)
        XCTAssertLessThan(size.majorArcminutes, 35)
        XCTAssertEqual(size.minorArcminutes, size.majorArcminutes)
        XCTAssertEqual(result.horizontal, frame.horizontal(of: moon, refraction: true))
    }

    func testTheSunHasItsDistanceInAstronomicalUnitsAndNoPhase() throws {
        let sun = try ObjectsDetailFixture.object("sun")
        let result = try current("sun")
        let frame = skyFrame()
        guard case .astronomicalUnits(let distance)? = result.distance else {
            return XCTFail("expected a distance in astronomical units, got \(String(describing: result.distance))")
        }
        XCTAssertEqual(distance, frame.state(of: .sun).distanceAU, accuracy: 1e-9)
        XCTAssertGreaterThan(distance, 0.98)
        XCTAssertLessThan(distance, 1.02)
        XCTAssertNil(result.illuminatedFraction, "the Sun has no phase")
        XCTAssertNil(result.moonPhase, "only the Moon has a phase name")
        let size = try XCTUnwrap(result.angularSize)
        XCTAssertGreaterThan(size.majorArcminutes, 31)
        XCTAssertLessThan(size.majorArcminutes, 33)
        XCTAssertEqual(result.magnitude, frame.currentMagnitude(of: sun))
    }

    func testAPlanetHasItsDistanceInAstronomicalUnitsAndAPhase() throws {
        let result = try current("planet.mars")
        guard case .astronomicalUnits(let distance)? = result.distance else {
            return XCTFail("expected a distance in astronomical units, got \(String(describing: result.distance))")
        }
        XCTAssertEqual(distance, skyFrame().state(of: .mars).distanceAU, accuracy: 1e-9)
        XCTAssertGreaterThan(distance, 0.3)
        XCTAssertLessThan(distance, 2.8)
        let lit = try XCTUnwrap(result.illuminatedFraction)
        XCTAssertGreaterThan(lit, 0)
        XCTAssertLessThanOrEqual(lit, 1)
        XCTAssertNil(result.moonPhase)
        XCTAssertNotNil(result.magnitude)
    }

    func testACometCarriesItsDetailAndHasNoDistanceInLightYears() throws {
        let comet = try ObjectsDetailFixture.object("comet.C/2099 A1")
        let body = try XCTUnwrap(comet.smallBody)
        let result = try current("comet.C/2099 A1")
        let frame = skyFrame()
        XCTAssertTrue(result.isSmallBody)
        XCTAssertEqual(result.smallBody, SmallBodyDetail.compute(body, frame: frame))
        XCTAssertEqual(result.smallBody?.info.body.id, "comet.C/2099 A1")
        XCTAssertNil(result.distance)
        XCTAssertNil(result.illuminatedFraction)
        XCTAssertNil(result.moonPhase)
        XCTAssertEqual(result.magnitude, frame.currentMagnitude(of: comet))
        XCTAssertEqual(result.horizontal, frame.horizontal(of: comet, refraction: true))
    }

    // MARK: Skyline

    func testTheCelestialPoleStandsAtTheLatitudeDueNorth() throws {
        let result = try current("special.ncp")
        XCTAssertEqual(result.horizontal.altitude, 40, accuracy: 0.1)
        XCTAssertEqual(min(result.horizontal.azimuth, 360 - result.horizontal.azimuth), 0, accuracy: 0.01)
        XCTAssertEqual(result.equatorial.declination, 90)
        XCTAssertNil(result.magnitude)
        XCTAssertNil(result.angularSize)
        XCTAssertNil(result.distance)
    }

    func testAnObjectAboveTheHorizonButBehindTheSkylineIsFlagged() throws {
        // The north pole is at 40 degrees; a skyline of 60 degrees hides it, one of 10 degrees does not.
        XCTAssertTrue(try current("special.ncp", skyline: HorizonProfile.constant(60)).isBehindSkyline)
        XCTAssertFalse(try current("special.ncp", skyline: HorizonProfile.constant(10)).isBehindSkyline)
        XCTAssertFalse(try current("special.ncp", skyline: nil).isBehindSkyline)
    }

    func testAFlatSkylineHidesNothingThatIsUp() throws {
        XCTAssertFalse(try current("special.ncp", skyline: HorizonProfile.flat).isBehindSkyline)
    }

    func testAnObjectBelowTheHorizonIsNotBehindTheSkyline() throws {
        // The south pole is 40 degrees below the horizon.
        let result = try current("special.scp", skyline: HorizonProfile.constant(10))
        XCTAssertEqual(result.horizontal.altitude, -40, accuracy: 0.1)
        XCTAssertFalse(result.isBehindSkyline)
    }

    func testTheSkylineDoesNotChangeThePosition() throws {
        let plain = try current("dso.M31")
        let withSkyline = try current("dso.M31", skyline: HorizonProfile.constant(30))
        XCTAssertEqual(plain.horizontal, withSkyline.horizontal)
        XCTAssertEqual(plain.equatorial, withSkyline.equatorial)
    }
}

// MARK: - Tonight

final class ObjectsDetailNightTests: XCTestCase {
    /// A target at declination +20, which transits at 70 degrees from Colorado.
    private let star = ObjectsDetailFixture.target(30, 20)

    private func denver() throws -> TimeZone {
        try ObjectsDetailFixture.zone("America/Denver")
    }

    private func makeNight(_ date: Date, horizon: HorizonProfile? = nil,
                           object: CelestialObject? = nil) throws -> ObjectDetailNight {
        let context = ObjectsDetailFixture.context(ObjectsDetailFixture.boulder, zone: try denver(), horizon: horizon)
        return ObjectDetailCalculator.night(of: object ?? star, context: context, containing: date)
    }

    private func twilight(startingOn day: Date) throws -> NightTwilight {
        TwilightCalculator.night(startingOn: day, observer: ObjectsDetailFixture.boulder, timeZone: try denver())
    }

    // MARK: Which night

    func testInTheEveningTheNightThatBeganTodayIsShown() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        XCTAssertEqual(night.twilight, try twilight(startingOn: ObjectsDetailFixture.noonOnTheTwentieth))
        XCTAssertEqual(night.interval, night.twilight.interval)
        XCTAssertTrue(night.interval.contains(ObjectsDetailFixture.evening))
    }

    func testBeforeDawnTheNightThatBeganYesterdayIsStillShown() throws {
        let night = try makeNight(ObjectsDetailFixture.beforeDawn)
        XCTAssertEqual(night.twilight, try twilight(startingOn: ObjectsDetailFixture.noonOnTheTwentieth))
        XCTAssertTrue(night.interval.contains(ObjectsDetailFixture.beforeDawn))
    }

    func testAfterSunriseTheComingNightIsShown() throws {
        let night = try makeNight(ObjectsDetailFixture.morning)
        XCTAssertEqual(night.twilight, try twilight(startingOn: ObjectsDetailFixture.noonOnTheTwentyFirst))
        XCTAssertGreaterThan(night.interval.start, ObjectsDetailFixture.morning)
    }

    func testInTheAfternoonTheComingNightIsShown() throws {
        let night = try makeNight(ObjectsDetailFixture.afternoon)
        XCTAssertEqual(night.twilight, try twilight(startingOn: ObjectsDetailFixture.noonOnTheTwentieth))
        XCTAssertTrue(night.interval.contains(ObjectsDetailFixture.afternoon))
        XCTAssertLessThan(night.interval.start, ObjectsDetailFixture.afternoon)
    }

    func testTheNightExpiresAtSunrise() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        XCTAssertEqual(night.expiry, night.twilight.sunrise)
        XCTAssertGreaterThan(night.expiry, ObjectsDetailFixture.evening)
        XCTAssertLessThan(night.expiry, night.interval.end)
    }

    // MARK: The chart

    func testTheChartRunsFromSunsetToSunrise() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        XCTAssertEqual(night.chartRange.start, try XCTUnwrap(night.twilight.sunset))
        XCTAssertEqual(night.chartRange.end, try XCTUnwrap(night.twilight.sunrise))
        XCTAssertEqual(night.darkness, night.twilight.astronomicalNight)
        XCTAssertNotNil(night.darkness)
    }

    func testTheAltitudeCurveHasASampleEveryTenMinutes() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        let range = night.chartRange
        let gaps = Int((range.duration / ObjectDetailCalculator.sampleStep).rounded(.up))
        XCTAssertEqual(night.samples.count, gaps + 1)
        XCTAssertEqual(night.samples.first?.date, range.start)
        XCTAssertEqual(night.samples.last?.date, range.end)
        for (index, sample) in night.samples.dropLast().enumerated() {
            XCTAssertEqual(sample.date, range.start.addingTimeInterval(Double(index) * 600), "sample \(index)")
        }
        // The last gap is the remainder, between 0 and 10 minutes.
        let lastGap = range.end.timeIntervalSince(night.samples[night.samples.count - 2].date)
        XCTAssertGreaterThan(lastGap, 0)
        XCTAssertLessThanOrEqual(lastGap, 600)
    }

    func testEverySampleIsTheApparentAltitudeAtItsInstant() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        for sample in night.samples {
            let expected = SkyFrame(date: sample.date, observer: ObjectsDetailFixture.boulder)
                .horizontal(of: star, refraction: true).altitude
            XCTAssertEqual(sample.altitude, expected, accuracy: 1e-9)
            XCTAssertEqual(sample.id, sample.date)
        }
    }

    func testTheSamplesShowTheObjectRisingAndFalling() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        let highest = try XCTUnwrap(night.samples.map(\.altitude).max())
        // Declination +20 transits at 70 degrees from latitude 40.
        XCTAssertGreaterThan(highest, 69)
        XCTAssertLessThan(highest, 71)
    }

    // MARK: Rise, transit and set

    func testWithoutASkylineTheEventsAreThoseOfTheHorizon() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        let expected = RiseSetCalculator.riseTransitSet(for: star, observer: ObjectsDetailFixture.boulder,
                                                        within: night.interval)
        XCTAssertEqual(night.events, expected)
        XCTAssertFalse(night.appliesSkyline)
        XCTAssertNotNil(night.events.transit)
    }

    func testTheTransitAltitudeIsTheApparentOne() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        let geometric = try XCTUnwrap(night.events.transitAltitude)
        let apparent = try XCTUnwrap(night.transitAltitude)
        XCTAssertEqual(apparent, Refraction.apparentAltitude(trueAltitude: geometric,
                                                             atmosphere: ObjectsDetailFixture.boulder.atmosphere))
        XCTAssertGreaterThan(apparent, geometric)
        XCTAssertEqual(apparent, 70, accuracy: 0.5)
    }

    func testTheTimelineListsTheEventsInTheOrderTheyHappen() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        let timeline = night.timeline
        XCTAssertEqual(timeline.map(\.date), timeline.map(\.date).sorted())
        let kinds = Set(timeline.map(\.kind))
        XCTAssertTrue(kinds.contains(.transit))
        for event in timeline {
            switch event.kind {
            case .rise: XCTAssertEqual(event.date, night.events.rise)
            case .transit: XCTAssertEqual(event.date, night.events.transit)
            case .set: XCTAssertEqual(event.date, night.events.set)
            }
        }
    }

    // MARK: The best moment in the dark

    func testTheBestPointInTheDarkIsTheTransitWhenItFallsInTheDark() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        let darkness = try XCTUnwrap(night.darkness)
        let best = try XCTUnwrap(night.bestInDarkness)
        let transit = try XCTUnwrap(night.events.transit)
        XCTAssertTrue(darkness.contains(transit))
        XCTAssertTrue(darkness.contains(best.date))
        XCTAssertEqual(best.date.timeIntervalSince(transit), 0, accuracy: 1)
        XCTAssertEqual(best.altitude, try XCTUnwrap(night.transitAltitude), accuracy: 0.01)
        for sample in night.samples where darkness.contains(sample.date) {
            XCTAssertGreaterThanOrEqual(best.altitude + 1e-9, sample.altitude)
        }
    }

    func testTheBestPointInTheDarkIsTheHighestInstantOfTheDarknessForAnObjectThatSetsDuringTheNight() throws {
        // An object that is in the west at dusk and gone later: the best moment lies in the darkness, and neither a
        // sample nor either end of the darkness is higher.
        let setting = ObjectsDetailFixture.target(230, 0)
        let night = try makeNight(ObjectsDetailFixture.evening, object: setting)
        let darkness = try XCTUnwrap(night.darkness)
        let best = try XCTUnwrap(night.bestInDarkness)
        XCTAssertTrue(darkness.contains(best.date))
        for sample in night.samples where darkness.contains(sample.date) {
            XCTAssertGreaterThanOrEqual(best.altitude + 1e-9, sample.altitude)
        }
        let atStart = SkyFrame(date: darkness.start, observer: ObjectsDetailFixture.boulder)
            .horizontal(of: setting, refraction: true).altitude
        let atEnd = SkyFrame(date: darkness.end, observer: ObjectsDetailFixture.boulder)
            .horizontal(of: setting, refraction: true).altitude
        XCTAssertGreaterThanOrEqual(best.altitude + 1e-9, atStart)
        XCTAssertGreaterThanOrEqual(best.altitude + 1e-9, atEnd)
    }

    // MARK: The hour axis

    func testTheHourTicksAreEveryTwoHoursOnTheLocalHour() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        let calendar = ObjectsDetailFixture.calendar(try denver())
        let ticks = night.hourTicks
        // A night of about 13 hours is between 9 and 18 hours long: a label every second hour.
        XCTAssertTrue((6...7).contains(ticks.count), "\(ticks.count) ticks")
        for tick in ticks {
            XCTAssertEqual(calendar.component(.minute, from: tick), 0)
            XCTAssertEqual(calendar.component(.second, from: tick), 0)
            XCTAssertEqual(calendar.component(.hour, from: tick) % 2, 0)
            XCTAssertTrue(night.chartRange.contains(tick))
        }
        for (earlier, later) in zip(ticks, ticks.dropFirst()) {
            XCTAssertEqual(later.timeIntervalSince(earlier), 7_200, accuracy: 0.001)
        }
        XCTAssertLessThan(try XCTUnwrap(ticks.first).timeIntervalSince(night.chartRange.start), 7_200)
        XCTAssertLessThan(night.chartRange.end.timeIntervalSince(try XCTUnwrap(ticks.last)), 7_200)
    }

    // MARK: Twilight shading

    func testTheTwilightBandsAreTheSixStretchesBetweenSunsetDuskAndDawn() throws {
        let night = try makeNight(ObjectsDetailFixture.evening)
        let twilight = night.twilight
        let sunset = try XCTUnwrap(twilight.sunset), sunrise = try XCTUnwrap(twilight.sunrise)
        let civilDusk = try XCTUnwrap(twilight.civilDusk), civilDawn = try XCTUnwrap(twilight.civilDawn)
        let nauticalDusk = try XCTUnwrap(twilight.nauticalDusk), nauticalDawn = try XCTUnwrap(twilight.nauticalDawn)
        let astronomicalDusk = try XCTUnwrap(twilight.astronomicalDusk)
        let astronomicalDawn = try XCTUnwrap(twilight.astronomicalDawn)
        // Civil twilight (3), nautical (2) and astronomical (1), each in the evening and in the morning; no daylight.
        XCTAssertEqual(night.twilightBands.map(\.brightness), [3, 3, 2, 2, 1, 1])
        XCTAssertEqual(night.twilightBands.map(\.interval), [
            DateInterval(start: sunset, end: civilDusk), DateInterval(start: civilDawn, end: sunrise),
            DateInterval(start: civilDusk, end: nauticalDusk), DateInterval(start: nauticalDawn, end: civilDawn),
            DateInterval(start: nauticalDusk, end: astronomicalDusk), DateInterval(start: astronomicalDawn, end: nauticalDawn),
        ])
        XCTAssertEqual(night.twilightBands.map(\.id), night.twilightBands.map { $0.interval.start })
    }

    // MARK: A recorded skyline

    func testASkylineMakesTheEventsTheObjectClearingAndSinkingBehindIt() throws {
        let profile = HorizonProfile.constant(10)
        let night = try makeNight(ObjectsDetailFixture.evening, horizon: profile)
        XCTAssertTrue(night.appliesSkyline)
        let expected = ObjectsHorizon.riseTransitSet(for: star, visibility: HorizonVisibility(profile: profile),
                                                     observer: ObjectsDetailFixture.boulder, within: night.interval)
        XCTAssertEqual(night.events, expected)
        let open = try makeNight(ObjectsDetailFixture.evening)
        // The culmination is the same moment; clearing a 10-degree skyline happens later than rising, and sinking
        // behind it earlier than setting.
        let transit = try XCTUnwrap(night.events.transit)
        XCTAssertEqual(transit.timeIntervalSince(try XCTUnwrap(open.events.transit)), 0, accuracy: 30)
        let clears = try XCTUnwrap(night.events.rise)
        let rises = try XCTUnwrap(open.events.rise)
        XCTAssertGreaterThan(clears, rises)
        let sinks = try XCTUnwrap(night.events.set)
        let sets = try XCTUnwrap(open.events.set)
        XCTAssertLessThan(sinks, sets)
    }

    func testTheBestPointOverASkylineKeepsToVisibleInstants() throws {
        let night = try makeNight(ObjectsDetailFixture.evening, horizon: HorizonProfile.constant(10))
        let open = try makeNight(ObjectsDetailFixture.evening)
        let best = try XCTUnwrap(night.bestInDarkness)
        let openBest = try XCTUnwrap(open.bestInDarkness)
        XCTAssertGreaterThanOrEqual(best.altitude, 10)
        // The culmination is in the dark and above the skyline, so it is the same moment as without a skyline.
        XCTAssertEqual(best.date.timeIntervalSince(openBest.date), 0, accuracy: 30)
        XCTAssertEqual(best.altitude, openBest.altitude, accuracy: 0.001)
    }

    func testAnObjectThatStaysBehindTheSkylineHasNoBestPoint() throws {
        // On the celestial equator the object reaches 50 degrees at most, below a 60-degree skyline.
        let equatorial = ObjectsDetailFixture.target(30, 0)
        let night = try makeNight(ObjectsDetailFixture.evening, horizon: HorizonProfile.constant(60), object: equatorial)
        XCTAssertTrue(night.appliesSkyline)
        XCTAssertEqual(night.events.circumstance, .alwaysDown)
        XCTAssertNil(night.bestInDarkness)
        XCTAssertNotNil(night.darkness)
        // Without the skyline it has one.
        let open = try makeNight(ObjectsDetailFixture.evening, object: equatorial)
        XCTAssertNotNil(open.bestInDarkness)
    }

    func testAFlatProfileIsNotASkyline() throws {
        let night = try makeNight(ObjectsDetailFixture.evening, horizon: HorizonProfile.flat)
        XCTAssertFalse(night.appliesSkyline)
        XCTAssertEqual(night.events, try makeNight(ObjectsDetailFixture.evening).events)
    }

    // MARK: Polar latitudes

    func testInTheMidnightSunTheWholeDayIsDaylightAndTheChartIsTheWholeDay() throws {
        let zone = try ObjectsDetailFixture.zone("Europe/Oslo")
        let context = ObjectsDetailFixture.context(ObjectsDetailFixture.tromso, zone: zone)
        let object = ObjectsDetailFixture.target(30, 10)
        let night = ObjectDetailCalculator.night(of: object, context: context, containing: ObjectsDetailFixture.midsummer)
        XCTAssertNil(night.twilight.sunset)
        XCTAssertNil(night.twilight.sunrise)
        XCTAssertEqual(night.chartRange, night.interval)
        XCTAssertEqual(night.chartRange.duration, 86_400)
        XCTAssertEqual(night.samples.count, 145)
        XCTAssertEqual(night.expiry, night.interval.end)
        // One band of daylight over the whole chart.
        XCTAssertEqual(night.twilightBands.map(\.brightness), [4])
        XCTAssertEqual(night.twilightBands.map(\.interval), [night.chartRange])
        // It never gets dark, so there is no best moment in the dark.
        XCTAssertNil(night.darkness)
        XCTAssertNil(night.bestInDarkness)
        // A label every four hours: 16, 20, 0, 4, 8 and 12 o'clock.
        let calendar = ObjectsDetailFixture.calendar(zone)
        XCTAssertEqual(night.hourTicks.map { calendar.component(.hour, from: $0) }, [16, 20, 0, 4, 8, 12])
    }

    func testInThePolarNightThereIsTwilightAtNoonAndDarknessAtNight() throws {
        let zone = try ObjectsDetailFixture.zone("Europe/Oslo")
        let context = ObjectsDetailFixture.context(ObjectsDetailFixture.tromso, zone: zone)
        // Declination +70 never gets below 49 degrees from latitude 69.65.
        let object = ObjectsDetailFixture.target(30, 70)
        let night = ObjectDetailCalculator.night(of: object, context: context, containing: ObjectsDetailFixture.midwinter)
        XCTAssertNil(night.twilight.sunset)
        XCTAssertNil(night.twilight.sunrise)
        XCTAssertEqual(night.chartRange, night.interval)
        XCTAssertEqual(night.events.circumstance, .alwaysUp)
        XCTAssertNil(night.events.rise)
        XCTAssertNil(night.events.set)
        // The Sun is never above the horizon, so no daylight band; it is lit twilight around noon, then dark.
        XCTAssertFalse(night.twilightBands.isEmpty)
        XCTAssertTrue(night.twilightBands.allSatisfy { $0.brightness < 4 })
        XCTAssertEqual(night.twilightBands.first?.interval.start, night.chartRange.start)
        XCTAssertEqual(night.twilightBands.first?.brightness, 3)
        // The bands do not overlap and stay inside the chart.
        let sorted = night.twilightBands.map(\.interval).sorted { $0.start < $1.start }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.end, later.start)
        }
        for band in night.twilightBands {
            XCTAssertGreaterThanOrEqual(band.interval.start, night.chartRange.start)
            XCTAssertLessThanOrEqual(band.interval.end, night.chartRange.end)
        }
        // There is real darkness, and the object has a best moment in it.
        let darkness = try XCTUnwrap(night.darkness)
        let best = try XCTUnwrap(night.bestInDarkness)
        XCTAssertTrue(darkness.contains(best.date))
        XCTAssertGreaterThan(best.altitude, 49)
    }
}

// MARK: - Photography

final class ObjectsDetailPhotographyTests: XCTestCase {
    private let star = ObjectsDetailFixture.target(30, 20)

    private func lens(focalLength: Double = 50, aperture: Double = 2.8, pixelPitch: Double? = nil,
                      sensor: SensorFormat = .fullFrame) -> LensSetup {
        LensSetup(sensor: sensor, focalLengthMillimeters: focalLength, aperture: aperture,
                  pixelPitchMicrometers: pixelPitch)
    }

    func testTheFrameIsTheFieldOfViewOfTheLens() {
        let result = ObjectDetailCalculator.photography(of: star, size: nil, declination: nil, lens: lens())
        XCTAssertEqual(result.frame, FieldOfView.of(sensor: .fullFrame, focalLength: 50))
        // 36 by 24 mm behind 50 mm: 39.6 by 27.0 degrees.
        XCTAssertEqual(result.frame.horizontal, 39.6, accuracy: 0.05)
        XCTAssertEqual(result.frame.vertical, 27.0, accuracy: 0.05)
    }

    func testAnObjectWithoutASizeHasNoFraming() {
        let result = ObjectDetailCalculator.photography(of: star, size: nil, declination: 20, lens: lens())
        XCTAssertNil(result.framing)
    }

    func testAnExtendedObjectIsFramedAsAFractionOfTheFrame() throws {
        // Andromeda, 178 by 63 arcminutes, in a 39.6 by 27.0 degree frame.
        let size = try XCTUnwrap(AngularSize(majorArcminutes: 178, minorArcminutes: 63))
        let framing = try XCTUnwrap(ObjectDetailCalculator.photography(of: star, size: size, declination: nil,
                                                                       lens: lens()).framing)
        XCTAssertEqual(framing.majorFraction, 0.0749, accuracy: 0.0005)
        XCTAssertEqual(framing.minorFraction, 0.0389, accuracy: 0.0005)
        XCTAssertTrue(framing.fitsInFrame)
        XCTAssertEqual(framing.longSidePanels, 1)
        XCTAssertEqual(framing.shortSidePanels, 1)
    }

    func testAnObjectWithOnlyAMajorAxisIsTreatedAsRound() throws {
        let size = try XCTUnwrap(AngularSize(majorArcminutes: 100))
        let framing = try XCTUnwrap(ObjectDetailCalculator.photography(of: star, size: size, declination: nil,
                                                                       lens: lens()).framing)
        // 100 arcminutes along the long side (2376 arcminutes) and along the short side (1619 arcminutes).
        XCTAssertEqual(framing.majorFraction, 0.0421, accuracy: 0.0005)
        XCTAssertEqual(framing.minorFraction, 0.0618, accuracy: 0.0005)
    }

    func testALongLensMakesAnObjectTooBigForTheFrame() throws {
        let size = try XCTUnwrap(AngularSize(majorArcminutes: 178, minorArcminutes: 63))
        let framing = try XCTUnwrap(ObjectDetailCalculator.photography(of: star, size: size, declination: nil,
                                                                       lens: lens(focalLength: 1000)).framing)
        // The frame is 2.06 by 1.38 degrees (123.7 by 82.5 arcminutes).
        XCTAssertEqual(framing.majorFraction, 1.438, accuracy: 0.005)
        XCTAssertEqual(framing.minorFraction, 0.764, accuracy: 0.005)
        XCTAssertFalse(framing.fitsInFrame)
        XCTAssertEqual(framing.longSidePanels, 2)
        XCTAssertEqual(framing.shortSidePanels, 1)
    }

    func testTheExposureLimitsFollowTheRulesAtTheEquator() throws {
        let result = ObjectDetailCalculator.photography(of: star, size: nil, declination: 0, lens: lens())
        // 500 divided by 50 mm on full frame; NPF with the default pixel pitch: (35 * 2.8 + 30 * 4.0) / 50.
        let rule500 = try XCTUnwrap(result.rule500)
        XCTAssertEqual(rule500.seconds, 10, accuracy: 1e-9)
        XCTAssertEqual(rule500.rule, .rule500)
        XCTAssertEqual(rule500.declinationFactor, 1, accuracy: 1e-12)
        let npf = try XCTUnwrap(result.npf)
        XCTAssertEqual(npf.seconds, 4.36, accuracy: 1e-9)
        XCTAssertEqual(npf.rule, .npf)
        XCTAssertTrue(npf.usedDefaultPixelPitch)
    }

    func testAKnownPixelPitchIsUsedForTheNPFRule() throws {
        let result = ObjectDetailCalculator.photography(of: star, size: nil, declination: 0, lens: lens(pixelPitch: 5.9))
        let npf = try XCTUnwrap(result.npf)
        XCTAssertEqual(npf.seconds, (35 * 2.8 + 30 * 5.9) / 50, accuracy: 1e-9)
        XCTAssertFalse(npf.usedDefaultPixelPitch)
    }

    func testTheExposureLimitGrowsTowardsThePole() throws {
        let setup = lens()
        let result = ObjectDetailCalculator.photography(of: star, size: nil, declination: 60, lens: setup)
        // 1 / cos 60 degrees is 2.
        XCTAssertEqual(try XCTUnwrap(result.rule500).seconds, 20, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(result.rule500).declinationFactor, 2, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(result.npf).seconds, 4.36 * 2, accuracy: 1e-6)
        XCTAssertEqual(result.rule500, ExposureCalculator.maxExposure(rule: .rule500, setup: setup, declination: 60))
        XCTAssertEqual(result.npf, ExposureCalculator.maxExposure(rule: .npf, setup: setup, declination: 60))
    }

    func testWithoutADeclinationTheLimitIsTheEquatorialOne() throws {
        let result = ObjectDetailCalculator.photography(of: star, size: nil, declination: nil, lens: lens())
        XCTAssertEqual(try XCTUnwrap(result.rule500).seconds, 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result.rule500).declinationFactor, 1, accuracy: 1e-12)
    }

    func testTheSunAndTheMoonHaveNoStarTrailLimits() throws {
        for id in ["sun", "moon"] {
            let object = try ObjectsDetailFixture.object(id)
            let result = ObjectDetailCalculator.photography(of: object, size: nil, declination: 10, lens: lens())
            XCTAssertNil(result.npf, id)
            XCTAssertNil(result.rule500, id)
        }
    }

    func testAPlanetHasStarTrailLimits() throws {
        let mars = try ObjectsDetailFixture.object("planet.mars")
        let result = ObjectDetailCalculator.photography(of: mars, size: nil, declination: 10, lens: lens())
        XCTAssertNotNil(result.npf)
        XCTAssertNotNil(result.rule500)
    }

    func testTheMoonStillGetsItsFraming() throws {
        let moon = try ObjectsDetailFixture.object("moon")
        let size = try XCTUnwrap(AngularSize(majorArcminutes: 31, minorArcminutes: 31))
        let result = ObjectDetailCalculator.photography(of: moon, size: size, declination: 10, lens: lens(focalLength: 200))
        let framing = try XCTUnwrap(result.framing)
        // 31 arcminutes in a 10.3 degree (617 arcminute) frame.
        XCTAssertEqual(framing.majorFraction, 31 / (result.frame.longSide * 60), accuracy: 1e-9)
        XCTAssertEqual(framing.majorFraction, 0.0502, accuracy: 0.001)
        XCTAssertTrue(framing.fitsInFrame)
    }
}

// MARK: - The Moon's effect

final class ObjectsDetailMoonTests: XCTestCase {
    private let star = ObjectsDetailFixture.target(30, 10)

    /// A night whose darkness and best point are as given.
    private func makeNight(darkness: DateInterval?, best: ObjectDetailPeak?) throws -> ObjectDetailNight {
        let zone = try ObjectsDetailFixture.zone("America/Denver")
        let twilight = TwilightCalculator.night(startingOn: ObjectsDetailFixture.noonOnTheTwentieth,
                                                observer: ObjectsDetailFixture.boulder, timeZone: zone)
        return ObjectDetailNight(
            interval: twilight.interval, chartRange: twilight.interval, twilight: twilight, darkness: darkness,
            events: RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: nil, circumstance: .normal),
            transitAltitude: nil, samples: [], twilightBands: [], hourTicks: [], bestInDarkness: best, appliesSkyline: false)
    }

    private func conditions(for object: CelestialObject, now: Date, darkness: DateInterval?,
                            best: ObjectDetailPeak? = nil) throws -> ObjectDetailMoonConditions? {
        ObjectDetailCalculator.moonConditions(for: object, observer: ObjectsDetailFixture.boulder,
                                              night: try makeNight(darkness: darkness, best: best), now: now)
    }

    private func around(_ date: Date) -> DateInterval {
        DateInterval(start: date.addingTimeInterval(-3_600), end: date.addingTimeInterval(3_600))
    }

    private func fullMoon() throws -> Date {
        let phases = MoonPhaseCalculator.nextPhases(after: Date(timeIntervalSince1970: 1_791_644_400), count: 8)
        return try XCTUnwrap(phases.first { $0.kind == .fullMoon }).date
    }

    private func firstQuarter() throws -> Date {
        let phases = MoonPhaseCalculator.nextPhases(after: Date(timeIntervalSince1970: 1_791_644_400), count: 8)
        return try XCTUnwrap(phases.first { $0.kind == .firstQuarter }).date
    }

    /// The Moon's apparent place at `date`, as a custom target.
    private func atTheMoon(on date: Date, opposite: Bool = false) -> CelestialObject {
        let place = SkyFrame(date: date, observer: ObjectsDetailFixture.boulder).topocentricEquatorial(of: .moon)
        let coordinate = opposite
            ? EquatorialCoordinate(rightAscension: place.rightAscension + 180, declination: -place.declination)
            : place
        return CelestialObject.custom(name: "Moon spot", j2000: coordinate)
    }

    func testTheSunAndTheMoonHaveNoMoonConditions() throws {
        for id in ["sun", "moon"] {
            let object = try ObjectsDetailFixture.object(id)
            let result = try conditions(for: object, now: ObjectsDetailFixture.evening,
                                        darkness: around(ObjectsDetailFixture.evening))
            XCTAssertNil(result, id)
        }
    }

    func testAnObjectNextToAFullMoonIsSeverelyAffected() throws {
        let start = try fullMoon().addingTimeInterval(-6 * 3600)
        let now = try XCTUnwrap(ObjectsDetailFixture.firstInstant(from: start, hours: 36) { $0.altitude > 20 })
        let result = try XCTUnwrap(conditions(for: atTheMoon(on: now), now: now, darkness: around(now)))
        XCTAssertEqual(result.date, now)
        XCTAssertTrue(result.isNow)
        XCTAssertLessThan(result.separation, 2)
        XCTAssertGreaterThan(result.illuminatedFraction, 0.9)
        XCTAssertEqual(result.impact, .severe)
    }

    func testAnObjectOppositeAFullMoonIsModeratelyAffected() throws {
        let start = try fullMoon().addingTimeInterval(-6 * 3600)
        let now = try XCTUnwrap(ObjectsDetailFixture.firstInstant(from: start, hours: 36) { $0.altitude > 20 })
        let result = try XCTUnwrap(conditions(for: atTheMoon(on: now, opposite: true), now: now, darkness: around(now)))
        XCTAssertGreaterThan(result.separation, 170)
        XCTAssertGreaterThan(result.illuminatedFraction, 0.9)
        XCTAssertEqual(result.impact, .moderate)
    }

    func testAnObjectFarFromAQuarterMoonIsOnlyMinorlyAffected() throws {
        let now = try XCTUnwrap(ObjectsDetailFixture.firstInstant(from: try firstQuarter(), hours: 36) { $0.altitude > 10 })
        let result = try XCTUnwrap(conditions(for: atTheMoon(on: now, opposite: true), now: now, darkness: around(now)))
        XCTAssertGreaterThan(result.separation, 170)
        XCTAssertGreaterThan(result.illuminatedFraction, 0.3)
        XCTAssertLessThan(result.illuminatedFraction, 0.7)
        XCTAssertEqual(result.impact, .minor)
    }

    func testWhileTheMoonIsDownItDoesNotMatter() throws {
        let now = try XCTUnwrap(ObjectsDetailFixture.firstInstant(from: ObjectsDetailFixture.evening, hours: 36) {
            $0.altitude < -5
        })
        let result = try XCTUnwrap(conditions(for: star, now: now, darkness: around(now)))
        XCTAssertEqual(result.impact, .moonDown)
        XCTAssertTrue(result.isNow)
    }

    func testTheSeparationAndThePhaseAreThoseOfTheEngine() throws {
        let now = ObjectsDetailFixture.evening
        let result = try XCTUnwrap(conditions(for: star, now: now, darkness: around(now)))
        let frame = SkyFrame(date: now, observer: ObjectsDetailFixture.boulder)
        let moon = frame.horizontal(of: .moon, refraction: false)
        XCTAssertEqual(result.separation, frame.horizontal(of: star, refraction: false).angularSeparation(to: moon),
                       accuracy: 1e-9)
        XCTAssertEqual(result.illuminatedFraction, try XCTUnwrap(frame.state(of: .moon).illuminatedFraction), accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(result.separation, 0)
        XCTAssertLessThanOrEqual(result.separation, 180)
    }

    func testWhenItIsNotDarkTheBestMomentTonightIsUsed() throws {
        let now = ObjectsDetailFixture.evening
        let best = ObjectDetailPeak(date: now.addingTimeInterval(9_000), altitude: 45)
        let darkness = DateInterval(start: now.addingTimeInterval(7_200), end: now.addingTimeInterval(14_400))
        let result = try XCTUnwrap(conditions(for: star, now: now, darkness: darkness, best: best))
        XCTAssertEqual(result.date, best.date)
        XCTAssertFalse(result.isNow)
        let frame = SkyFrame(date: best.date, observer: ObjectsDetailFixture.boulder)
        XCTAssertEqual(result.separation,
                       frame.horizontal(of: star, refraction: false)
                           .angularSeparation(to: frame.horizontal(of: .moon, refraction: false)), accuracy: 1e-9)
    }

    func testWhenItIsDarkNowTheBestMomentIsNotNeeded() throws {
        let now = ObjectsDetailFixture.evening
        let best = ObjectDetailPeak(date: now.addingTimeInterval(9_000), altitude: 45)
        let result = try XCTUnwrap(conditions(for: star, now: now, darkness: around(now), best: best))
        XCTAssertEqual(result.date, now)
        XCTAssertTrue(result.isNow)
    }

    func testTheEndOfTheDarknessStillCountsAsDark() throws {
        let now = ObjectsDetailFixture.evening
        let darkness = DateInterval(start: now.addingTimeInterval(-7_200), end: now)
        let best = ObjectDetailPeak(date: now.addingTimeInterval(-3_600), altitude: 45)
        let result = try XCTUnwrap(conditions(for: star, now: now, darkness: darkness, best: best))
        XCTAssertTrue(result.isNow)
    }

    func testWithoutDarknessOrABestMomentTheConditionsAreForNow() throws {
        let now = ObjectsDetailFixture.evening
        let result = try XCTUnwrap(conditions(for: star, now: now, darkness: nil, best: nil))
        XCTAssertEqual(result.date, now)
        XCTAssertTrue(result.isNow)
    }

    func testAMomentTonightThatIsNotNowIsNotCalledNow() throws {
        let now = ObjectsDetailFixture.evening
        let result = try XCTUnwrap(conditions(for: star, now: now, darkness: nil,
                                              best: ObjectDetailPeak(date: now.addingTimeInterval(1), altitude: 10)))
        XCTAssertFalse(result.isNow)
        XCTAssertEqual(result.date, now.addingTimeInterval(1))
    }
}

// MARK: - The whole snapshot

final class ObjectsDetailSnapshotTests: XCTestCase {
    private let star = ObjectsDetailFixture.target(30, 20)

    private func context(horizon: HorizonProfile? = nil) throws -> ObserverContext {
        ObjectsDetailFixture.context(ObjectsDetailFixture.boulder, zone: try ObjectsDetailFixture.zone("America/Denver"),
                                     horizon: horizon)
    }

    private func input(_ object: CelestialObject? = nil, at date: Date = ObjectsDetailFixture.evening,
                       previous: ObjectDetailNight? = nil, horizon: HorizonProfile? = nil) throws -> ObjectDetailInput {
        ObjectDetailInput(object: object ?? star, context: try context(horizon: horizon), date: date, previousNight: previous)
    }

    func testTheSnapshotHoldsNowTonightAndTheMoon() throws {
        let snapshot = ObjectDetailCalculator.snapshot(for: try input())
        let frame = SkyFrame(date: ObjectsDetailFixture.evening, observer: ObjectsDetailFixture.boulder)
        XCTAssertEqual(snapshot.current.date, ObjectsDetailFixture.evening)
        XCTAssertEqual(snapshot.current.horizontal, frame.horizontal(of: star, refraction: true))
        XCTAssertFalse(snapshot.current.isBehindSkyline)
        let expectedNight = try ObjectDetailCalculator.night(of: star, context: context(),
                                                             containing: ObjectsDetailFixture.evening)
        XCTAssertEqual(snapshot.night.twilight, expectedNight.twilight)
        XCTAssertEqual(snapshot.night.events, expectedNight.events)
        XCTAssertEqual(snapshot.night.samples.count, expectedNight.samples.count)
        XCTAssertEqual(snapshot.night.bestInDarkness, expectedNight.bestInDarkness)
        let moon = try XCTUnwrap(snapshot.moon)
        XCTAssertEqual(moon, ObjectDetailCalculator.moonConditions(
            for: star, observer: ObjectsDetailFixture.boulder, night: snapshot.night, now: ObjectsDetailFixture.evening))
        XCTAssertTrue(moon.isNow, "21:00 is inside the astronomical night")
    }

    func testTheSunAndTheMoonHaveNoMoonConditionsInTheirSnapshot() throws {
        for id in ["sun", "moon"] {
            let object = try ObjectsDetailFixture.object(id)
            let snapshot = ObjectDetailCalculator.snapshot(for: try input(object))
            XCTAssertNil(snapshot.moon, id)
        }
    }

    func testTheSnapshotUsesTheSkylineOfTheContext() throws {
        // The north pole at 40 degrees is behind a 60-degree skyline.
        let pole = try ObjectsDetailFixture.object("special.ncp")
        let behind = ObjectDetailCalculator.snapshot(for: try input(pole, horizon: HorizonProfile.constant(60)))
        XCTAssertTrue(behind.current.isBehindSkyline)
        XCTAssertTrue(behind.night.appliesSkyline)
        let open = ObjectDetailCalculator.snapshot(for: try input(pole, horizon: HorizonProfile.constant(10)))
        XCTAssertFalse(open.current.isBehindSkyline)
        let flat = ObjectDetailCalculator.snapshot(for: try input(pole, horizon: HorizonProfile.flat))
        XCTAssertFalse(flat.night.appliesSkyline)
    }

    /// A night with the same content as `real` except a marker in its hour ticks.
    private func marked(_ real: ObjectDetailNight) -> ObjectDetailNight {
        ObjectDetailNight(interval: real.interval, chartRange: real.chartRange, twilight: real.twilight,
                          darkness: real.darkness, events: real.events, transitAltitude: real.transitAltitude,
                          samples: real.samples, twilightBands: real.twilightBands,
                          hourTicks: [Date(timeIntervalSince1970: 5)], bestInDarkness: real.bestInDarkness,
                          appliesSkyline: real.appliesSkyline)
    }

    func testAnEarlierNightIsReusedWhileItIsStillTonight() throws {
        let real = ObjectDetailCalculator.night(of: star, context: try context(), containing: ObjectsDetailFixture.evening)
        let previous = marked(real)
        let later = ObjectsDetailFixture.beforeDawn
        XCTAssertGreaterThan(previous.expiry, later)
        let snapshot = ObjectDetailCalculator.snapshot(for: try input(at: later, previous: previous))
        XCTAssertEqual(snapshot.night.hourTicks, [Date(timeIntervalSince1970: 5)], "the earlier night was kept")
        // Now is still computed for the new instant.
        XCTAssertEqual(snapshot.current.date, later)
    }

    func testAnExpiredNightIsComputedAgain() throws {
        let real = ObjectDetailCalculator.night(of: star, context: try context(), containing: ObjectsDetailFixture.evening)
        let previous = marked(real)
        let snapshot = ObjectDetailCalculator.snapshot(for: try input(at: ObjectsDetailFixture.morning, previous: previous))
        XCTAssertNotEqual(snapshot.night.hourTicks, previous.hourTicks)
        XCTAssertEqual(snapshot.night.twilight,
                       TwilightCalculator.night(startingOn: ObjectsDetailFixture.noonOnTheTwentyFirst,
                                                observer: ObjectsDetailFixture.boulder,
                                                timeZone: try ObjectsDetailFixture.zone("America/Denver")))
    }

    func testANightThatExpiresExactlyNowIsComputedAgain() throws {
        let real = ObjectDetailCalculator.night(of: star, context: try context(), containing: ObjectsDetailFixture.evening)
        let previous = marked(real)
        let snapshot = ObjectDetailCalculator.snapshot(for: try input(at: previous.expiry, previous: previous))
        XCTAssertNotEqual(snapshot.night.hourTicks, previous.hourTicks)
    }
}
