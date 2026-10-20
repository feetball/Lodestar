import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Contexts, keys and one event of every kind for the tests of `EventsModels.swift`.
private enum EventsModelsFixtures {
    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: .nan)
    }

    static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone.gmt
    }

    static func context(latitude: Double, longitude: Double, zone identifier: String) -> ObserverContext {
        ObserverContext(
            observer: Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: 0)),
            timeZone: zone(identifier), name: "Test site", source: .device)
    }

    /// A key for a place in Colorado (Denver's zone) unless told otherwise.
    static func key(latitude: Double = 40.0, longitude: Double = -105.0, zone identifier: String = "America/Denver",
                    now: String = "2026-08-12T18:00:00Z") -> EventsKey {
        EventsKey(context: context(latitude: latitude, longitude: longitude, zone: identifier), now: date(now))
    }

    static func location(_ latitude: Double, _ longitude: Double, elevation: Double = 0) -> GeographicLocation {
        GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation)
    }

    // MARK: Events

    static let shower = MeteorShower(
        code: "TST", iauNumber: 999, name: "Testids", activityStartMonth: 7, activityStartDay: 17, activityEndMonth: 8,
        activityEndDay: 24, peakSolarLongitude: 140, zhr: 100, radiant: EquatorialCoordinate(rightAscension: 48, declination: 58),
        radiantDriftRightAscension: 1.42, radiantDriftDeclination: 0.2, velocity: 59, populationIndex: 2.2)

    static func event(_ details: EventDetails, at moment: Date = Date(timeIntervalSince1970: 1_786_564_800),
                      visibility: EventVisibility? = nil) -> AstronomicalEvent {
        AstronomicalEvent(date: moment, details: details, visibility: visibility)
    }

    static func visibility(window: DateInterval?) -> EventVisibility {
        EventVisibility(altitude: 40, azimuth: 135, sunAltitude: -25, isDark: true, bestWindow: window,
                        bestTime: window?.start, darknessLimit: -18, contacts: [])
    }

    static var meteorShower: AstronomicalEvent {
        let peak = MeteorShowerPeak(
            shower: shower, activityStart: date("2026-07-17T00:00:00Z"), activityEnd: date("2026-08-25T00:00:00Z"),
            moonIlluminatedFraction: 0.3, radiant: shower.radiant)
        return event(.meteorShower(peak))
    }

    static func conjunction(_ first: ConjunctionTarget, _ second: ConjunctionTarget) -> AstronomicalEvent {
        event(.conjunction(Conjunction(first: first, second: second, separation: 2, solarElongation: 90,
                                       occultationPossible: false, topocentric: nil)))
    }

    static var opposition: AstronomicalEvent {
        event(.opposition(Opposition(planet: .jupiter, distanceAU: 4.2, apparentMagnitude: -2.5,
                                     angularDiameterArcseconds: 46)))
    }

    static var elongation: AstronomicalEvent {
        event(.greatestElongation(GreatestElongation(planet: .venus, direction: .east, angle: 46, apparentMagnitude: -4.2)))
    }

    static var apsis: AstronomicalEvent {
        event(.earthApsis(EarthApsis(kind: .perihelion, distanceAU: 0.9833)))
    }

    static var season: AstronomicalEvent {
        event(.season(Season(kind: .juneSolstice)))
    }

    static var fullMoon: AstronomicalEvent {
        event(.fullMoonSpecial(FullMoonSpecial(categories: [.supermoon], distanceKilometers: 357_000,
                                               angularDiameterArcseconds: 2_010)))
    }

    static var lunarEclipse: AstronomicalEvent {
        let base = date("2026-03-03T08:44:00Z")
        return event(.lunarEclipse(LunarEclipse(
            kind: .total, gamma: -0.38, penumbralMagnitude: 2.18, umbralMagnitude: 1.17,
            p1: base, u1: base.addingTimeInterval(3_960), u2: base.addingTimeInterval(8_400),
            greatest: base.addingTimeInterval(10_200), u3: base.addingTimeInterval(11_940),
            u4: base.addingTimeInterval(16_680), p4: base.addingTimeInterval(20_400))))
    }

    static var solarEclipse: AstronomicalEvent {
        event(.solarEclipse(SolarEclipse(kind: .total, greatest: date("2026-08-12T17:46:00Z"), gamma: 0.9,
                                         greatestMagnitude: 1.04, isCentral: true, local: nil)))
    }
}

// MARK: - The key of a run

final class EventsKeyTests: XCTestCase {
    private typealias F = EventsModelsFixtures

    // MARK: Day start and end

    func testTheCalendarBeginsAtTheStartOfTheLocalDayOfTheSite() {
        let now = F.date("2026-08-01T03:00:00Z")
        // 03:00 UTC is 22:00 on July 31 in Chicago (UTC-5) and 12:00 on August 1 in Tokyo (UTC+9).
        let chicago = EventsKey(context: F.context(latitude: 41.9, longitude: -87.6, zone: "America/Chicago"), now: now)
        XCTAssertEqual(chicago.dayStart, F.date("2026-07-31T05:00:00Z"))
        let tokyo = EventsKey(context: F.context(latitude: 35.7, longitude: 139.7, zone: "Asia/Tokyo"), now: now)
        XCTAssertEqual(tokyo.dayStart, F.date("2026-07-31T15:00:00Z"))
    }

    func testTheKeyKeepsTheObserverAndTheZoneOfTheContext() {
        let context = F.context(latitude: 41.9, longitude: -87.6, zone: "America/Chicago")
        let key = EventsKey(context: context, now: F.date("2026-08-01T03:00:00Z"))
        XCTAssertEqual(key.observer, context.observer)
        XCTAssertEqual(key.timeZone.identifier, "America/Chicago")
    }

    func testEveryInstantOfALocalDayGivesTheSameStart() {
        // Denver is UTC-6 in August: the local day of August 12 runs from 06:00 UTC to 06:00 UTC.
        let first = F.key(now: "2026-08-12T06:00:00Z")
        let last = F.key(now: "2026-08-13T05:59:59Z")
        XCTAssertEqual(first.dayStart, F.date("2026-08-12T06:00:00Z"))
        XCTAssertEqual(last.dayStart, first.dayStart)
    }

    func testTheNextInstantAfterMidnightStartsTheNextDay() {
        let before = F.key(now: "2026-08-12T05:59:59Z")
        let after = F.key(now: "2026-08-12T06:00:00Z")
        XCTAssertEqual(after.dayStart.timeIntervalSince(before.dayStart), 86_400, accuracy: 0.001)
    }

    func testTheSpanEndsSpanDaysOfLocalTimeAfterTheStart() {
        // Madrid is UTC+2 in summer. 366 days after August 1, 2026 at 00:00 is August 2, 2027 at 00:00.
        let key = EventsKey(context: F.context(latitude: 42.3, longitude: -3.7, zone: "Europe/Madrid"),
                            now: F.date("2026-08-01T10:00:00Z"))
        XCTAssertEqual(key.dayStart, F.date("2026-07-31T22:00:00Z"))
        XCTAssertEqual(key.end, F.date("2027-08-01T22:00:00Z"))
    }

    func testTheSpanFollowsTheCalendarAcrossADaylightSavingChange() {
        // Berlin changes to summer time on March 28, 2027. The day 366 days after March 28, 2026 (CET, UTC+1) starts
        // at 00:00 CEST (UTC+2), one hour fewer than 366 times 24 hours later.
        let key = EventsKey(context: F.context(latitude: 52.5, longitude: 13.4, zone: "Europe/Berlin"),
                            now: F.date("2026-03-28T12:00:00Z"))
        XCTAssertEqual(key.dayStart, F.date("2026-03-27T23:00:00Z"))
        XCTAssertEqual(key.end, F.date("2027-03-28T22:00:00Z"))
        XCTAssertEqual(key.end.timeIntervalSince(key.dayStart), 366 * 86_400 - 3_600, accuracy: 0.001)
    }

    // MARK: Which key covers which

    func testAKeyCoversItself() {
        let key = F.key()
        XCTAssertTrue(key.covers(key))
    }

    func testAnotherInstantOfTheSameLocalDayIsCovered() {
        // 00:30 and 23:30 local time on August 12 in Denver.
        let early = F.key(now: "2026-08-12T06:30:00Z")
        let late = F.key(now: "2026-08-13T05:30:00Z")
        XCTAssertTrue(early.covers(late))
        XCTAssertTrue(late.covers(early))
    }

    func testTheNextLocalDayIsNotCoveredButTheSamePlaceIsNear() {
        let today = F.key(now: "2026-08-12T18:00:00Z")
        let tomorrow = F.key(now: "2026-08-13T18:00:00Z")
        XCTAssertFalse(today.covers(tomorrow))
        XCTAssertTrue(today.isNear(tomorrow))
    }

    // The places below are placed relative to `EventsKey.placeToleranceKilometers`, so that these tests hold whatever the
    // tolerance is: they check that it is respected, not what it is.

    /// The degrees of latitude that make `fraction` of the tolerance along a meridian (a degree is 111.195 km).
    private func latitudeOffset(_ fraction: Double) -> Double {
        fraction * EventsKey.placeToleranceKilometers / 111.195
    }

    /// The degrees of longitude that make `fraction` of the tolerance along the parallel of `latitude`.
    private func longitudeOffset(_ fraction: Double, atLatitude latitude: Double) -> Double {
        fraction * EventsKey.placeToleranceKilometers / (111.195 * cos(latitude * Double.pi / 180))
    }

    func testAPlaceJustInsideTheToleranceIsCovered() {
        let here = F.key(latitude: 40.0)
        let nearby = F.key(latitude: 40.0 + latitudeOffset(0.99))
        XCTAssertTrue(here.covers(nearby))
        XCTAssertTrue(here.isNear(nearby))
    }

    func testAPlaceJustOutsideTheToleranceIsNotCovered() {
        let here = F.key(latitude: 40.0)
        let farther = F.key(latitude: 40.0 + latitudeOffset(1.01))
        XCTAssertFalse(here.covers(farther))
        XCTAssertFalse(here.isNear(farther))
    }

    func testTheToleranceHoldsToTheSouthAndInLongitude() {
        let here = F.key(latitude: 40.0, longitude: -105.0)
        XCTAssertTrue(here.covers(F.key(latitude: 40.0 - latitudeOffset(0.99), longitude: -105.0)))
        XCTAssertFalse(here.covers(F.key(latitude: 40.0 - latitudeOffset(1.01), longitude: -105.0)))
        let step = longitudeOffset(1, atLatitude: 40.0)
        XCTAssertTrue(here.covers(F.key(latitude: 40.0, longitude: -105.0 + 0.95 * step)))
        XCTAssertTrue(here.covers(F.key(latitude: 40.0, longitude: -105.0 - 0.95 * step)))
        XCTAssertFalse(here.covers(F.key(latitude: 40.0, longitude: -105.0 + 1.05 * step)))
        XCTAssertFalse(here.covers(F.key(latitude: 40.0, longitude: -105.0 - 1.05 * step)))
    }

    func testCoveringIsSymmetricForTheSameDayAndZone() {
        let a = F.key(latitude: 40.0)
        let b = F.key(latitude: 40.0 + latitudeOffset(0.5))
        let c = F.key(latitude: 40.0 + latitudeOffset(3))
        XCTAssertEqual(a.covers(b), b.covers(a))
        XCTAssertEqual(a.covers(c), c.covers(a))
        XCTAssertTrue(a.covers(b))
        XCTAssertFalse(a.covers(c))
    }

    func testNearnessIgnoresTheDayButNotThePlace() {
        let here = F.key(latitude: 40.0, now: "2026-08-12T18:00:00Z")
        XCTAssertTrue(here.isNear(F.key(latitude: 40.0 + latitudeOffset(0.1), now: "2027-01-05T18:00:00Z")))
        XCTAssertFalse(here.isNear(F.key(latitude: 40.0 + latitudeOffset(5), now: "2026-08-12T18:00:00Z")))
    }

    func testAPlaceInAnotherZoneIsNotCoveredEvenAtTheSameInstantAndPlace() {
        // In January Chicago and Mexico City are both UTC-6, so the local days start at the same instant.
        let chicago = F.key(latitude: 20.0, longitude: -99.0, zone: "America/Chicago", now: "2026-01-15T18:00:00Z")
        let mexico = F.key(latitude: 20.0, longitude: -99.0, zone: "America/Mexico_City", now: "2026-01-15T18:00:00Z")
        XCTAssertEqual(chicago.dayStart, mexico.dayStart)
        XCTAssertFalse(chicago.covers(mexico))
        XCTAssertTrue(chicago.isNear(mexico))
    }

    func testPlacesOnBothSidesOfTheDateLineAreNear() {
        // A tenth of the tolerance apart, with the date line in between.
        let half = 0.05 * EventsKey.placeToleranceKilometers / 111.195
        let east = F.key(latitude: 0.0, longitude: 180.0 - half, zone: "Pacific/Fiji")
        let west = F.key(latitude: 0.0, longitude: -180.0 + half, zone: "Pacific/Fiji")
        XCTAssertTrue(east.covers(west))
        XCTAssertTrue(west.isNear(east))
    }

    func testKeysOfTheSameContextAndInstantAreEqual() {
        XCTAssertEqual(F.key(), F.key())
        XCTAssertNotEqual(F.key(), F.key(latitude: 40.0001))
        XCTAssertNotEqual(F.key(), F.key(now: "2026-08-13T18:00:00Z"))
    }

    // MARK: Distance

    func testADegreeOfLatitudeIsAbout111Kilometres() {
        XCTAssertEqual(EventsKey.distanceKilometers(from: F.location(40, -105), to: F.location(41, -105)),
                       111.195, accuracy: 0.01)
    }

    func testADegreeOfLongitudeAtTheEquatorIsAbout111Kilometres() {
        XCTAssertEqual(EventsKey.distanceKilometers(from: F.location(0, 10), to: F.location(0, 11)),
                       111.195, accuracy: 0.01)
    }

    func testADegreeOfLongitudeShrinksWithLatitude() {
        // At 60 degrees a degree of longitude is half as long.
        XCTAssertEqual(EventsKey.distanceKilometers(from: F.location(60, 10), to: F.location(60, 11)),
                       55.597, accuracy: 0.05)
    }

    func testDistanceIsZeroToItselfAndIgnoresElevation() {
        let place = F.location(40, -105, elevation: 1_600)
        XCTAssertEqual(EventsKey.distanceKilometers(from: place, to: place), 0, accuracy: 1e-9)
        XCTAssertEqual(EventsKey.distanceKilometers(from: F.location(40, -105, elevation: 0),
                                                    to: F.location(40, -105, elevation: 3_000)), 0, accuracy: 1e-9)
    }

    func testDistanceIsSymmetric() {
        let a = F.location(39.7, -105.0)
        let b = F.location(-33.9, 151.2)
        XCTAssertEqual(EventsKey.distanceKilometers(from: a, to: b), EventsKey.distanceKilometers(from: b, to: a),
                       accuracy: 1e-6)
    }

    func testDistanceAcrossTheDateLineIsShort() {
        XCTAssertEqual(EventsKey.distanceKilometers(from: F.location(0, 179.5), to: F.location(0, -179.5)),
                       111.195, accuracy: 0.01)
    }

    func testHalfTheEarthAwayIsHalfAGreatCircle() {
        // pi times the 6371 km radius.
        XCTAssertEqual(EventsKey.distanceKilometers(from: F.location(0, 0), to: F.location(0, 180)),
                       20_015.09, accuracy: 0.05)
    }
}

// MARK: - Moonlight on a shower

final class EventsMoonInterferenceTests: XCTestCase {
    private func level(_ fraction: Double, _ altitude: Double) -> EventsMoonInterference.Level {
        EventsMoonInterference.level(illuminatedFraction: fraction, moonAltitude: altitude)
    }

    func testAMoonBelowTheHorizonNeverInterferes() {
        XCTAssertEqual(level(1.0, -10), .moonDown)
        XCTAssertEqual(level(0.5, -0.01), .moonDown)
        XCTAssertEqual(level(0.0, -45), .moonDown)
    }

    func testAMoonOnTheHorizonCountsAsDown() {
        XCTAssertEqual(level(1.0, 0), .moonDown)
    }

    func testAMoonJustAboveTheHorizonInterferes() {
        XCTAssertEqual(level(0.9, 0.01), .strong)
    }

    func testAThinMoonIsALittleInterference() {
        XCTAssertEqual(level(0.0, 30), .little)
        XCTAssertEqual(level(0.2499, 30), .little)
    }

    func testAHalfMoonIsModerateInterference() {
        XCTAssertEqual(level(0.25, 30), .moderate)
        XCTAssertEqual(level(0.5999, 30), .moderate)
    }

    func testABrightMoonIsStrongInterference() {
        XCTAssertEqual(level(0.6, 30), .strong)
        XCTAssertEqual(level(1.0, 30), .strong)
    }

    func testTheLevelIsIndependentOfHowHighTheMoonIs() {
        XCTAssertEqual(level(0.4, 1), level(0.4, 89))
    }
}

// MARK: - Entries and categories

final class EventsEntryTests: XCTestCase {
    private typealias F = EventsModelsFixtures

    func testTheIdentifierNamesTheKindTheSecondAndTheTitle() {
        let entry = EventsEntry(event: F.meteorShower, moonInterference: nil)
        XCTAssertEqual(entry.id, "meteorShower.1786564800.Testids peak")
    }

    func testTheIdentifierDropsTheFractionOfASecond() {
        let whole = EventsEntry(event: F.event(F.meteorShower.details, at: Date(timeIntervalSince1970: 1_786_564_800)),
                                moonInterference: nil)
        let fractional = EventsEntry(event: F.event(F.meteorShower.details, at: Date(timeIntervalSince1970: 1_786_564_800.9)),
                                     moonInterference: nil)
        XCTAssertEqual(whole.id, fractional.id)
    }

    func testTwoConjunctionsAtTheSameInstantHaveDifferentIdentifiers() {
        let venus = EventsEntry(event: F.conjunction(.body(.moon), .body(.venus)), moonInterference: nil)
        let jupiter = EventsEntry(event: F.conjunction(.body(.moon), .body(.jupiter)), moonInterference: nil)
        XCTAssertEqual(venus.id, "conjunction.1786564800.Moon and Venus")
        XCTAssertEqual(jupiter.id, "conjunction.1786564800.Moon and Jupiter")
        XCTAssertNotEqual(venus.id, jupiter.id)
    }

    func testTheSameEventAtAnotherInstantHasAnotherIdentifier() {
        let first = EventsEntry(event: F.event(F.season.details, at: Date(timeIntervalSince1970: 1_000)), moonInterference: nil)
        let second = EventsEntry(event: F.event(F.season.details, at: Date(timeIntervalSince1970: 1_001)), moonInterference: nil)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testAnEventWithoutAnObserverHasNoVisibility() {
        XCTAssertNil(EventsEntry(event: F.meteorShower, moonInterference: nil).isVisibleFromHere)
    }

    func testAnEventWithAViewingWindowIsVisibleFromHere() {
        let window = DateInterval(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))
        let event = F.event(F.meteorShower.details, visibility: F.visibility(window: window))
        XCTAssertEqual(EventsEntry(event: event, moonInterference: nil).isVisibleFromHere, true)
    }

    func testAnEventWithoutAViewingWindowIsNotVisibleFromHere() {
        let event = F.event(F.meteorShower.details, visibility: F.visibility(window: nil))
        XCTAssertEqual(EventsEntry(event: event, moonInterference: nil).isVisibleFromHere, false)
    }

    func testEntriesWithTheSameEventAndMoonAreEqual() {
        let moon = EventsMoonInterference(illuminatedFraction: 0.3, moonAltitude: 20, level: .moderate)
        let a = EventsEntry(event: F.meteorShower, moonInterference: moon)
        let b = EventsEntry(event: F.meteorShower, moonInterference: moon)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, EventsEntry(event: F.meteorShower, moonInterference: nil))
    }
}

final class EventsCategoryTests: XCTestCase {
    private typealias F = EventsModelsFixtures

    private func categories(of event: AstronomicalEvent) -> Set<EventsCategory> {
        Set(EventsCategory.allCases.filter { $0.includes(event) })
    }

    func testTheCalendarOffersTheGroupsInOrder() {
        XCTAssertEqual(EventsCategory.allCases.map(\.title),
                       ["Meteor Showers", "Conjunctions", "Eclipses", "Planets", "Moon", "Seasons"])
    }

    func testTheIdentifierIsTheRawValue() {
        XCTAssertEqual(EventsCategory.allCases.map(\.id),
                       ["meteorShowers", "conjunctions", "eclipses", "planets", "moon", "seasons"])
    }

    func testEveryGroupHasItsOwnSymbol() {
        let symbols = EventsCategory.allCases.map(\.systemImage)
        XCTAssertTrue(symbols.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(symbols).count, EventsCategory.allCases.count)
    }

    func testAMeteorShowerIsOnlyInTheMeteorShowers() {
        XCTAssertEqual(categories(of: F.meteorShower), [.meteorShowers])
    }

    func testAMoonConjunctionWithAPlanetIsAConjunctionAndAMoonEvent() {
        XCTAssertEqual(categories(of: F.conjunction(.body(.moon), .body(.venus))), [.conjunctions, .moon])
    }

    func testAMoonConjunctionWithAStarIsAConjunctionAndAMoonEvent() {
        XCTAssertEqual(categories(of: F.conjunction(.body(.moon), .star(.spica))), [.conjunctions, .moon])
    }

    func testAConjunctionOfTwoPlanetsIsAConjunctionAndAPlanetEvent() {
        XCTAssertEqual(categories(of: F.conjunction(.body(.venus), .body(.jupiter))), [.conjunctions, .planets])
    }

    func testAConjunctionOfAPlanetWithAStarIsOnlyAConjunction() {
        XCTAssertEqual(categories(of: F.conjunction(.body(.mars), .star(.spica))), [.conjunctions])
    }

    func testAConjunctionWithTheSunIsNotAPlanetEvent() {
        XCTAssertEqual(categories(of: F.conjunction(.body(.venus), .body(.sun))), [.conjunctions])
    }

    func testAnOppositionAndAnElongationAreOnlyPlanetEvents() {
        XCTAssertEqual(categories(of: F.opposition), [.planets])
        XCTAssertEqual(categories(of: F.elongation), [.planets])
    }

    func testTheEarthsApsidesAndTheSeasonsAreSeasons() {
        XCTAssertEqual(categories(of: F.apsis), [.seasons])
        XCTAssertEqual(categories(of: F.season), [.seasons])
    }

    func testASpecialFullMoonIsOnlyAMoonEvent() {
        XCTAssertEqual(categories(of: F.fullMoon), [.moon])
    }

    func testALunarEclipseIsAnEclipseAndAMoonEvent() {
        XCTAssertEqual(categories(of: F.lunarEclipse), [.eclipses, .moon])
    }

    func testASolarEclipseIsOnlyAnEclipse() {
        XCTAssertEqual(categories(of: F.solarEclipse), [.eclipses])
    }
}
