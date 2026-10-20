import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Zones, events and visibility values for the tests of `EventsDetailModel.swift`.
private enum EventsDetailFixtures {
    static let utc = TimeZone.gmt
    static let chicago = TimeZone(identifier: "America/Chicago") ?? TimeZone.gmt
    static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone.gmt

    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: .nan)
    }

    /// The ASCII digits of `text`: they survive another decimal mark or digit grouping.
    static func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    /// 17:46 UTC on August 12, 2026.
    static let moment = date("2026-08-12T17:46:00Z")

    static let window = DateInterval(start: date("2026-08-13T02:10:00Z"), end: date("2026-08-13T08:50:00Z"))

    static let best = date("2026-08-13T04:00:00Z")

    static func visibility(altitude: Double = 40, azimuth: Double = 135, window: DateInterval? = nil, best: Date? = nil,
                           darknessLimit: Double = -18, contacts: [ContactVisibility] = []) -> EventVisibility {
        EventVisibility(altitude: altitude, azimuth: azimuth, sunAltitude: -25, isDark: true, bestWindow: window,
                        bestTime: best, darknessLimit: darknessLimit, contacts: contacts)
    }

    /// A visibility with a viewing window and a best time.
    static func visible(altitude: Double = 40, darknessLimit: Double = -18) -> EventVisibility {
        visibility(altitude: altitude, window: window, best: best, darknessLimit: darknessLimit)
    }

    static func entry(_ details: EventDetails, visibility: EventVisibility? = nil,
                      interference: EventsMoonInterference? = nil) -> EventsEntry {
        EventsEntry(event: AstronomicalEvent(date: moment, details: details, visibility: visibility),
                    moonInterference: interference)
    }

    static func contact(_ contact: EclipseContact, _ time: String, altitude: Double = 20,
                        azimuth: Double = 90) -> ContactVisibility {
        ContactVisibility(contact: contact, time: date(time), altitude: altitude, azimuth: azimuth)
    }

    // MARK: Details

    static func meteor(zhr: Int = 100, velocity: Double = 59) -> EventDetails {
        let shower = MeteorShower(
            code: "TST", iauNumber: 999, name: "Perseids", activityStartMonth: 7, activityStartDay: 17, activityEndMonth: 8,
            activityEndDay: 24, peakSolarLongitude: 140, zhr: zhr,
            radiant: EquatorialCoordinate(rightAscension: 48, declination: 58), radiantDriftRightAscension: 1.42,
            radiantDriftDeclination: 0.2, velocity: velocity, populationIndex: 2.2)
        return .meteorShower(MeteorShowerPeak(
            shower: shower, activityStart: date("2026-07-17T00:00:00Z"), activityEnd: date("2026-08-25T00:00:00Z"),
            moonIlluminatedFraction: 0.64, radiant: shower.radiant))
    }

    static func conjunction(_ first: ConjunctionTarget = .body(.moon), _ second: ConjunctionTarget = .body(.venus),
                            separation: Double = 2.5, elongation: Double = 90, occultationPossible: Bool = false,
                            topocentric: TopocentricApproach? = nil) -> EventDetails {
        .conjunction(Conjunction(first: first, second: second, separation: separation, solarElongation: elongation,
                                 occultationPossible: occultationPossible, topocentric: topocentric))
    }

    static func opposition(magnitude: Double? = -2.5) -> EventDetails {
        .opposition(Opposition(planet: .mars, distanceAU: 4.0, apparentMagnitude: magnitude, angularDiameterArcseconds: 45.67))
    }

    static func elongation(_ planet: SolarSystemBody = .venus, _ direction: ElongationDirection,
                           angle: Double = 46.0, magnitude: Double? = nil) -> EventDetails {
        .greatestElongation(GreatestElongation(planet: planet, direction: direction, angle: angle, apparentMagnitude: magnitude))
    }

    static func apsis(_ kind: EarthApsisKind = .perihelion) -> EventDetails {
        .earthApsis(EarthApsis(kind: kind, distanceAU: 0.9833))
    }

    static func season(_ kind: SeasonKind) -> EventDetails {
        .season(Season(kind: kind))
    }

    static func fullMoon(_ categories: [FullMoonCategory]) -> EventDetails {
        .fullMoonSpecial(FullMoonSpecial(categories: categories, distanceKilometers: 356_900.4, angularDiameterArcseconds: 2_010))
    }

    /// A lunar eclipse of the given kind: 5 h 40 min in the penumbra, 3 h 32 min in the umbra (if any) and 59 min of
    /// totality (if total).
    static func lunar(_ kind: LunarEclipseKind) -> EventDetails {
        let base = date("2026-03-03T08:44:00Z")
        func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
        let hasUmbra = kind != .penumbral
        let isTotal = kind == .total
        let umbral = kind == .penumbral ? -0.2149 : (isTotal ? 1.1722 : 0.5123)
        return .lunarEclipse(LunarEclipse(
            kind: kind, gamma: -0.38, penumbralMagnitude: kind == .penumbral ? 0.9234 : 2.1838, umbralMagnitude: umbral,
            p1: at(0), u1: hasUmbra ? at(3_960) : nil, u2: isTotal ? at(8_400) : nil, greatest: at(10_200),
            u3: isTotal ? at(11_940) : nil, u4: hasUmbra ? at(16_680) : nil, p4: at(20_400)))
    }

    static func local(_ kind: LocalSolarEclipseKind, altitude: Double? = 12.4, azimuth: Double? = 268,
                      duration: Double = 106) -> LocalSolarCircumstances {
        LocalSolarCircumstances(kind: kind, c1: nil, c2: nil, maximum: date("2026-08-12T18:29:13Z"), c3: nil, c4: nil,
                                magnitude: 0.6128, obscuration: 0.5, sunAltitude: altitude, sunAzimuth: azimuth,
                                centralDuration: duration, visibleInterval: nil)
    }

    static func solar(_ kind: SolarEclipseKind = .total, central: Bool = true,
                      local: LocalSolarCircumstances? = nil) -> EventDetails {
        .solarEclipse(SolarEclipse(kind: kind, greatest: moment, gamma: 0.8977, greatestMagnitude: 1.0386,
                                   isCentral: central, local: local))
    }
}

final class EventsDetailModelTests: XCTestCase {
    private typealias F = EventsDetailFixtures

    private func facts(_ entry: EventsEntry, southern: Bool = false, in zone: TimeZone? = nil) -> [EventsDetailRow] {
        EventsDetailModel.facts(of: entry, isSouthernHemisphere: southern, timeZone: zone ?? F.utc)
    }

    private func times(_ entry: EventsEntry, in zone: TimeZone? = nil) -> [EventsDetailRow] {
        EventsDetailModel.times(of: entry, timeZone: zone ?? F.utc)
    }

    // MARK: Rows

    func testARowIsIdentifiedByItsLabel() {
        XCTAssertEqual(EventsDetailRow(label: "Rate", value: "Up to 100 meteors an hour").id, "Rate")
    }

    func testAContactRowIsBelowTheHorizonOnlyWhenItsAltitudeIsNegative() {
        func row(_ altitude: Double) -> EventsContactRow {
            EventsContactRow(id: "C1", name: "Eclipse begins", time: F.moment, altitude: altitude, azimuth: 90)
        }
        XCTAssertTrue(row(-0.1).isBelowHorizon)
        XCTAssertTrue(row(-30).isBelowHorizon)
        XCTAssertFalse(row(0).isBelowHorizon)
        XCTAssertFalse(row(12).isBelowHorizon)
    }

    // MARK: Facts: meteor showers

    func testMeteorShowerFactsGiveTheRateTheActivityAndTheSpeed() {
        let rows = facts(F.entry(F.meteor()), in: F.tokyo)
        XCTAssertEqual(rows.map(\.label), ["Rate", "Active", "Speed"])
        XCTAssertEqual(rows[0].value, "Up to 100 meteors an hour")
        XCTAssertEqual(rows[2].value, "59 km/s")
    }

    func testTheActivityRunsFromTheFirstToTheLastDayInUniversalTime() {
        // The period ends at midnight after the last day (August 24), and the days are UT whatever the zone of the site.
        let first = AppFormat.day(F.date("2026-07-17T12:00:00Z"), in: F.utc)
        let last = AppFormat.day(F.date("2026-08-24T12:00:00Z"), in: F.utc)
        let expected = "\(first) \u{2013} \(last) (UT)"
        XCTAssertEqual(facts(F.entry(F.meteor()), in: F.tokyo)[1].value, expected)
        XCTAssertEqual(facts(F.entry(F.meteor()), in: F.chicago)[1].value, expected)
    }

    func testTheSpeedIsRoundedToWholeKilometresPerSecond() {
        XCTAssertEqual(facts(F.entry(F.meteor(velocity: 35.4)))[2].value, "35 km/s")
        XCTAssertEqual(facts(F.entry(F.meteor(velocity: 35.5)))[2].value, "36 km/s")
    }

    func testTheRateIsTheZenithalHourlyRate() {
        XCTAssertEqual(facts(F.entry(F.meteor(zhr: 5)))[0].value, "Up to 5 meteors an hour")
    }

    func testMeteorShowerFactsAddTheMoonWhenThereIsInterference() {
        let moon = EventsMoonInterference(illuminatedFraction: 0.4, moonAltitude: 30, level: .moderate)
        let rows = facts(F.entry(F.meteor(), interference: moon))
        XCTAssertEqual(rows.map(\.label), ["Rate", "Active", "Speed", "Moon"])
        XCTAssertEqual(rows[3].value, "Moon 40% lit: moonlight hides the fainter meteors")
    }

    // MARK: Facts: conjunctions

    func testConjunctionFactsOfTwoPlanets() {
        let rows = facts(F.entry(F.conjunction(.body(.venus), .body(.jupiter), separation: 1.2, elongation: 46.4)))
        XCTAssertEqual(rows.map(\.label), ["Pair", "Separation", "Distance from the Sun"])
        XCTAssertEqual(rows[0].value, "Venus and Jupiter")
        XCTAssertEqual(rows[1].value, "1.2\u{00B0}")
        XCTAssertEqual(rows[2].value, "46\u{00B0}")
    }

    func testConjunctionFactsGiveTheApproachSeenFromHere() {
        let approach = TopocentricApproach(time: F.moment, separation: 0.25, isOccultation: false)
        let details = F.conjunction(.body(.moon), .star(.spica), separation: 0.5, elongation: 120, occultationPossible: true,
                                    topocentric: approach)
        let rows = facts(F.entry(details), in: F.tokyo)
        XCTAssertEqual(rows.map(\.label), ["Pair", "Separation", "From here", "Distance from the Sun", "Occultation"])
        XCTAssertEqual(rows[0].value, "Moon and Spica")
        XCTAssertEqual(rows[1].value, "30\u{2032}")
        XCTAssertEqual(rows[2].value, "15\u{2032} at " + AppFormat.time(F.moment, in: F.tokyo))
        XCTAssertEqual(rows[3].value, "120\u{00B0}")
        XCTAssertEqual(rows[4].value, "Possible elsewhere, not from here")
    }

    func testTheApproachTimeFollowsTheZone() {
        let approach = TopocentricApproach(time: F.moment, separation: 0.25, isOccultation: false)
        let details = F.conjunction(.body(.moon), .star(.spica), topocentric: approach)
        XCTAssertNotEqual(facts(F.entry(details), in: F.utc)[2].value, facts(F.entry(details), in: F.tokyo)[2].value)
    }

    func testConjunctionFactsForAnOccultationFromHere() {
        let approach = TopocentricApproach(time: F.moment, separation: 0.0, isOccultation: true)
        let details = F.conjunction(.body(.moon), .star(.spica), separation: 0.5, occultationPossible: true, topocentric: approach)
        let rows = facts(F.entry(details), in: F.chicago)
        XCTAssertEqual(rows.map(\.label), ["Pair", "Separation", "From here", "Distance from the Sun"])
        XCTAssertEqual(rows[2].value, "Occultation, closest at " + AppFormat.time(F.moment, in: F.chicago))
    }

    func testConjunctionFactsWithAnOccultationPossibleAndNoObserver() {
        let rows = facts(F.entry(F.conjunction(.body(.moon), .star(.spica), occultationPossible: true)))
        XCTAssertEqual(rows.map(\.label), ["Pair", "Separation", "Distance from the Sun", "Occultation"])
        XCTAssertEqual(rows[3].value, "Possible in parts of the world")
    }

    func testConjunctionFactsWithoutAnOccultationPossibleHaveNoOccultationRow() {
        let approach = TopocentricApproach(time: F.moment, separation: 0.4, isOccultation: false)
        let rows = facts(F.entry(F.conjunction(.body(.moon), .body(.venus), topocentric: approach)))
        XCTAssertEqual(rows.map(\.label), ["Pair", "Separation", "From here", "Distance from the Sun"])
    }

    // MARK: Facts: oppositions, elongations, apsides, seasons

    func testOppositionFacts() {
        let rows = facts(F.entry(F.opposition(magnitude: -2.5)))
        XCTAssertEqual(rows.map(\.label), ["Planet", "Brightness", "Distance", "Size"])
        XCTAssertEqual(rows[0].value, "Mars")
        XCTAssertTrue(rows[1].value.hasPrefix("mag \u{2212}2"), rows[1].value)
        // 4.00 AU, which is 598 million km.
        XCTAssertTrue(rows[2].value.contains(" AU ("), rows[2].value)
        XCTAssertTrue(rows[2].value.hasSuffix(" million km)"), rows[2].value)
        XCTAssertEqual(F.digits(rows[2].value), "400598")
        // 45.7 arcseconds.
        XCTAssertTrue(rows[3].value.hasSuffix("\u{2033}"), rows[3].value)
        XCTAssertEqual(F.digits(rows[3].value), "457")
    }

    func testOppositionFactsWithoutAMagnitudeHaveNoBrightnessRow() {
        let rows = facts(F.entry(F.opposition(magnitude: nil)))
        XCTAssertEqual(rows.map(\.label), ["Planet", "Distance", "Size"])
    }

    func testAnEveningElongation() {
        let rows = facts(F.entry(F.elongation(.venus, .east)))
        XCTAssertEqual(rows.map(\.label), ["Planet", "Elongation", "Sky"])
        XCTAssertEqual(rows[0].value, "Venus")
        XCTAssertEqual(rows[1].value, "46.0\u{00B0} east of the Sun")
        XCTAssertEqual(rows[2].value, "Evening, after sunset")
    }

    func testAMorningElongationWithABrightness() {
        let rows = facts(F.entry(F.elongation(.mercury, .west, angle: 25.3, magnitude: 0.3)))
        XCTAssertEqual(rows.map(\.label), ["Planet", "Elongation", "Sky", "Brightness"])
        XCTAssertEqual(rows[0].value, "Mercury")
        XCTAssertEqual(rows[1].value, "25.3\u{00B0} west of the Sun")
        XCTAssertEqual(rows[2].value, "Morning, before sunrise")
        XCTAssertTrue(rows[3].value.hasPrefix("mag 0"), rows[3].value)
    }

    func testAnApsisGivesTheDistanceToFourPlaces() {
        let rows = facts(F.entry(F.apsis(.perihelion)))
        XCTAssertEqual(rows.map(\.label), ["Distance from the Sun"])
        XCTAssertTrue(rows[0].value.hasSuffix(" AU"), rows[0].value)
        XCTAssertEqual(F.digits(rows[0].value), "09833")
    }

    func testASeasonNamesTheEventAndWhatItMeansInTheHemisphere() {
        let north = facts(F.entry(F.season(.juneSolstice)))
        XCTAssertEqual(north.map(\.label), ["Event", "In your hemisphere"])
        XCTAssertEqual(north[0].value, "June solstice")
        XCTAssertEqual(north[1].value, "Summer begins \u{00B7} longest day")
        let south = facts(F.entry(F.season(.juneSolstice)), southern: true)
        XCTAssertEqual(south[1].value, "Winter begins \u{00B7} shortest day")
    }

    // MARK: Facts: the Moon and eclipses

    func testSpecialFullMoonFacts() {
        let rows = facts(F.entry(F.fullMoon([.supermoon, .blueMoon])))
        XCTAssertEqual(rows.map(\.label), ["Kind", "Distance", "Size"])
        XCTAssertEqual(rows[0].value, "Supermoon, Blue Moon")
        XCTAssertTrue(rows[1].value.hasSuffix(" km"), rows[1].value)
        XCTAssertEqual(F.digits(rows[1].value), "356900")
        XCTAssertTrue(rows[2].value.hasSuffix("\u{2032} across"), rows[2].value)
        XCTAssertEqual(F.digits(rows[2].value), "335")
    }

    func testTotalLunarEclipseFacts() {
        let rows = facts(F.entry(F.lunar(.total)))
        XCTAssertEqual(rows.map(\.label),
                       ["Type", "Umbral magnitude", "Penumbral magnitude", "Penumbral phase", "Partial phase", "Totality"])
        XCTAssertEqual(rows[0].value, "Total lunar eclipse")
        XCTAssertEqual(F.digits(rows[1].value), "1172")
        XCTAssertEqual(F.digits(rows[2].value), "2184")
        XCTAssertEqual(rows[3].value, "5h 40m")
        XCTAssertEqual(rows[4].value, "3h 32m")
        XCTAssertEqual(rows[5].value, "59m 00s")
    }

    func testPartialLunarEclipseFactsHaveNoTotality() {
        let rows = facts(F.entry(F.lunar(.partial)))
        XCTAssertEqual(rows.map(\.label),
                       ["Type", "Umbral magnitude", "Penumbral magnitude", "Penumbral phase", "Partial phase"])
        XCTAssertEqual(rows[0].value, "Partial lunar eclipse")
    }

    func testPenumbralLunarEclipseFactsHaveNeitherPartialPhaseNorTotality() {
        let rows = facts(F.entry(F.lunar(.penumbral)))
        XCTAssertEqual(rows.map(\.label), ["Type", "Umbral magnitude", "Penumbral magnitude", "Penumbral phase"])
        XCTAssertEqual(rows[0].value, "Penumbral lunar eclipse")
        XCTAssertEqual(F.digits(rows[2].value), "0923")
    }

    func testSolarEclipseFactsWithoutAnObserverStopAtThePath() {
        let rows = facts(F.entry(F.solar(.total, local: F.local(.total))))
        XCTAssertEqual(rows.map(\.label), ["Type", "Path"])
        XCTAssertEqual(rows[0].value, "Total solar eclipse")
        XCTAssertEqual(rows[1].value, "Central: total or annular along a track")
    }

    func testAPartialSolarEclipseIsPartialFromEverywhere() {
        let rows = facts(F.entry(F.solar(.partial, central: false)))
        XCTAssertEqual(rows[0].value, "Partial solar eclipse")
        XCTAssertEqual(rows[1].value, "Partial from everywhere")
    }

    func testSolarEclipseFactsWithAnObserverButNoLocalCircumstancesStopAtThePath() {
        let rows = facts(F.entry(F.solar(.annular, local: nil), visibility: F.visible()))
        XCTAssertEqual(rows.map(\.label), ["Type", "Path"])
        XCTAssertEqual(rows[0].value, "Annular solar eclipse")
    }

    func testSolarEclipseFactsWhenNothingIsVisibleFromHere() {
        let entry = F.entry(F.solar(.total, local: F.local(LocalSolarEclipseKind.none)), visibility: F.visibility())
        let rows = facts(entry)
        XCTAssertEqual(rows.map(\.label), ["Type", "Path", "From here"])
        XCTAssertEqual(rows[2].value, "No eclipse visible")
    }

    func testPartialSolarEclipseFactsFromHere() {
        let entry = F.entry(F.solar(.total, local: F.local(.partial)), visibility: F.visibility())
        let rows = facts(entry)
        XCTAssertEqual(rows.map(\.label), ["Type", "Path", "From here", "Magnitude", "Sun covered", "Sun at maximum"])
        XCTAssertEqual(rows[2].value, "Partial eclipse")
        XCTAssertEqual(F.digits(rows[3].value), "0613")
        XCTAssertEqual(rows[4].value, "50%")
        // Azimuth 268 degrees is in the west sector (258.75 to 281.25).
        XCTAssertEqual(rows[5].value, "12\u{00B0} high, W")
    }

    func testAnnularSolarEclipseFactsFromHereGiveTheLengthOfTheRing() {
        let entry = F.entry(F.solar(.annular, local: F.local(.annular, duration: 312)), visibility: F.visibility())
        let rows = facts(entry)
        XCTAssertEqual(rows.map(\.label),
                       ["Type", "Path", "From here", "Magnitude", "Sun covered", "Annularity", "Sun at maximum"])
        XCTAssertEqual(rows[2].value, "Annular eclipse")
        XCTAssertEqual(rows[5].value, "5m 12s")
    }

    func testTotalSolarEclipseFactsFromHereGiveTheLengthOfTotality() {
        let entry = F.entry(F.solar(.total, local: F.local(.total, duration: 106)), visibility: F.visibility())
        let rows = facts(entry)
        XCTAssertEqual(rows.map(\.label),
                       ["Type", "Path", "From here", "Magnitude", "Sun covered", "Totality", "Sun at maximum"])
        XCTAssertEqual(rows[2].value, "Total eclipse")
        XCTAssertEqual(rows[5].value, "1m 46s")
    }

    func testSolarEclipseFactsLeaveOutTheSunsPlaceWhenItIsNotKnown() {
        let withoutAltitude = F.entry(F.solar(.total, local: F.local(.total, altitude: nil, azimuth: 268)),
                                      visibility: F.visibility())
        XCTAssertFalse(facts(withoutAltitude).map(\.label).contains("Sun at maximum"))
        let withoutAzimuth = F.entry(F.solar(.total, local: F.local(.total, altitude: 12.4, azimuth: nil)),
                                     visibility: F.visibility())
        XCTAssertFalse(facts(withoutAzimuth).map(\.label).contains("Sun at maximum"))
    }

    // MARK: Positions

    func testAPositionGivesTheAltitudeAndTheCompassPoint() {
        XCTAssertEqual(EventsDetailModel.position(altitude: 34.4, azimuth: 135), "34\u{00B0} high, SE")
        XCTAssertEqual(EventsDetailModel.position(altitude: 34.6, azimuth: 135), "35\u{00B0} high, SE")
    }

    func testAPositionNamesEveryCompassSector() {
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: 0), "10\u{00B0} high, N")
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: 90), "10\u{00B0} high, E")
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: 180), "10\u{00B0} high, S")
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: 270), "10\u{00B0} high, W")
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: 22.5), "10\u{00B0} high, NNE")
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: 247.5), "10\u{00B0} high, WSW")
    }

    func testAPositionWrapsTheAzimuth() {
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: 359.9), "10\u{00B0} high, N")
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: 360 + 90), "10\u{00B0} high, E")
        XCTAssertEqual(EventsDetailModel.position(altitude: 10, azimuth: -90), "10\u{00B0} high, W")
    }

    func testAPositionBelowTheHorizonKeepsItsSign() {
        XCTAssertEqual(EventsDetailModel.position(altitude: -3.2, azimuth: 180), "\u{2212}3\u{00B0} high, S")
        XCTAssertEqual(EventsDetailModel.position(altitude: 0, azimuth: 180), "0\u{00B0} high, S")
    }

    // MARK: Times

    func testTheTimesOfAMeteorShowerGiveThePeakTheWindowTheBestTimeAndTheRadiant() {
        let rows = times(F.entry(F.meteor(), visibility: F.visible(altitude: 34)), in: F.chicago)
        XCTAssertEqual(rows.map(\.label), ["Peak", "Best dark window", "Highest at", "At that moment"])
        XCTAssertEqual(rows[0].value, EventsFormat.dayAndTime(F.moment, in: F.chicago))
        XCTAssertEqual(rows[1].value, EventsFormat.window(F.window, in: F.chicago))
        XCTAssertEqual(rows[2].value, AppFormat.time(F.best, in: F.chicago))
        XCTAssertEqual(rows[3].value, "34\u{00B0} high, SE")
    }

    func testTheTimesOfAnEventWithoutAnObserverAreTheInstantOnly() {
        let kinds: [(EventDetails, String)] = [
            (F.meteor(), "Peak"),
            (F.conjunction(), "Closest"),
            (F.opposition(), "Opposition"),
            (F.elongation(.venus, .east), "Greatest elongation"),
            (F.apsis(), "Moment"),
            (F.season(.marchEquinox), "Moment"),
            (F.fullMoon([.supermoon]), "Full Moon"),
            (F.lunar(.total), "Greatest eclipse"),
            (F.solar(), "Greatest eclipse (anywhere)"),
        ]
        for (details, label) in kinds {
            let rows = times(F.entry(details), in: F.tokyo)
            XCTAssertEqual(rows.map(\.label), [label], label)
            XCTAssertEqual(rows[0].value, EventsFormat.dayAndTime(F.moment, in: F.tokyo), label)
        }
    }

    func testTheTimesOfAConjunctionUseTheGenericWindowLabels() {
        let rows = times(F.entry(F.conjunction(), visibility: F.visible()))
        XCTAssertEqual(rows.map(\.label), ["Closest", "Best window", "Highest at", "At that moment"])
    }

    func testTheTimesOfOppositionsElongationsAndSpecialFullMoonsUseTheGenericWindowLabels() {
        for (details, instant) in [(F.opposition(), "Opposition"), (F.elongation(.venus, .west), "Greatest elongation"),
                                   (F.fullMoon([.micromoon]), "Full Moon")] {
            let rows = times(F.entry(details, visibility: F.visible()))
            XCTAssertEqual(rows.map(\.label), [instant, "Best window", "Highest at", "At that moment"], instant)
        }
    }

    func testTheTimesOfALunarEclipseSayWhenItIsVisible() {
        let rows = times(F.entry(F.lunar(.total), visibility: F.visible()), in: F.utc)
        XCTAssertEqual(rows.map(\.label), ["Greatest eclipse", "Visible from here", "Best time", "At that moment"])
        XCTAssertEqual(rows[1].value, EventsFormat.window(F.window, in: F.utc))
        XCTAssertEqual(rows[2].value, AppFormat.time(F.best, in: F.utc))
    }

    func testTheTimesOfASolarEclipseEndWithTheMaximumHere() {
        let rows = times(F.entry(F.solar(), visibility: F.visible()), in: F.utc)
        XCTAssertEqual(rows.map(\.label), ["Greatest eclipse (anywhere)", "Visible from here", "Maximum here"])
        XCTAssertEqual(rows[2].value, AppFormat.time(F.best, in: F.utc))
    }

    func testTheSubjectIsLeftOutWhileItIsOnOrBelowTheHorizon() {
        let belowHorizon = times(F.entry(F.conjunction(), visibility: F.visible(altitude: -5)))
        XCTAssertEqual(belowHorizon.map(\.label), ["Closest", "Best window", "Highest at"])
        let onHorizon = times(F.entry(F.conjunction(), visibility: F.visible(altitude: 0)))
        XCTAssertEqual(onHorizon.map(\.label), ["Closest", "Best window", "Highest at"])
    }

    func testWithoutAWindowTheTimesAreTheInstantAndThePositionOfTheSubject() {
        let rows = times(F.entry(F.conjunction(), visibility: F.visibility(altitude: 12, azimuth: 270)))
        XCTAssertEqual(rows.map(\.label), ["Closest", "At that moment"])
        XCTAssertEqual(rows[1].value, "12\u{00B0} high, W")
    }

    func testWithoutAWindowAndBelowTheHorizonOnlyTheInstantRemains() {
        let rows = times(F.entry(F.opposition(), visibility: F.visibility(altitude: -20)))
        XCTAssertEqual(rows.map(\.label), ["Opposition"])
    }

    func testAWindowWithoutABestTimeHasNoHighestRow() {
        let rows = times(F.entry(F.conjunction(), visibility: F.visibility(window: F.window, best: nil)))
        XCTAssertEqual(rows.map(\.label), ["Closest", "Best window", "At that moment"])
    }

    // MARK: Visibility sentences

    func testNoSentenceForAnEventNotSeenInTheSky() {
        XCTAssertNil(EventsDetailModel.visibilitySentence(of: F.entry(F.season(.juneSolstice)), timeZone: F.utc))
        XCTAssertNil(EventsDetailModel.visibilitySentence(of: F.entry(F.meteor()), timeZone: F.utc))
    }

    func testAVisibleEventSaysWhenItCanBeSeen() {
        let sentence = EventsDetailModel.visibilitySentence(of: F.entry(F.meteor(), visibility: F.visible()), timeZone: F.chicago)
        XCTAssertEqual(sentence, "Visible from here between \(EventsFormat.window(F.window, in: F.chicago)).")
    }

    func testAVisibleEclipseSaysWhenItCanBeSeen() {
        let entry = F.entry(F.lunar(.total), visibility: F.visible())
        XCTAssertEqual(EventsDetailModel.visibilitySentence(of: entry, timeZone: F.tokyo),
                       "Visible from here between \(EventsFormat.window(F.window, in: F.tokyo)).")
    }

    func testAnInvisibleLunarEclipseSaysTheMoonIsDown() {
        let entry = F.entry(F.lunar(.partial), visibility: F.visibility(altitude: -30))
        XCTAssertEqual(EventsDetailModel.visibilitySentence(of: entry, timeZone: F.utc),
                       "The Moon is below the horizon during the eclipse as seen from here.")
    }

    func testAnInvisibleSolarEclipseSaysTheSunIsDown() {
        let entry = F.entry(F.solar(.total, local: F.local(.partial)), visibility: F.visibility(altitude: -30))
        XCTAssertEqual(EventsDetailModel.visibilitySentence(of: entry, timeZone: F.utc),
                       "The Sun is below the horizon during the eclipse as seen from here.")
    }

    func testASolarEclipseThatDoesNotTouchTheSunHereSaysSo() {
        // Even with a window, "none" means no part of the eclipse is seen.
        let entry = F.entry(F.solar(.total, local: F.local(LocalSolarEclipseKind.none)), visibility: F.visible())
        XCTAssertEqual(EventsDetailModel.visibilitySentence(of: entry, timeZone: F.utc),
                       "No part of the eclipse can be seen from here.")
        let withoutWindow = F.entry(F.solar(.total, local: F.local(LocalSolarEclipseKind.none)), visibility: F.visibility())
        XCTAssertEqual(EventsDetailModel.visibilitySentence(of: withoutWindow, timeZone: F.utc),
                       "No part of the eclipse can be seen from here.")
    }

    func testAnInvisibleOtherEventHasNoGoodWindow() {
        let expected = "There is no good viewing window from here: the target stays too low or the sky too bright that night."
        for details in [F.meteor(), F.conjunction(), F.opposition(), F.elongation(.venus, .east), F.fullMoon([.supermoon])] {
            let entry = F.entry(details, visibility: F.visibility(altitude: 5))
            XCTAssertEqual(EventsDetailModel.visibilitySentence(of: entry, timeZone: F.utc), expected)
        }
    }

    // MARK: Window rules

    func testNoWindowRuleWithoutVisibility() {
        XCTAssertNil(EventsDetailModel.windowRule(of: F.entry(F.meteor())))
        XCTAssertNil(EventsDetailModel.windowRule(of: F.entry(F.season(.marchEquinox))))
    }

    func testAnEclipseNeedsNoWindowRule() {
        XCTAssertNil(EventsDetailModel.windowRule(of: F.entry(F.lunar(.total), visibility: F.visible(darknessLimit: 0))))
        XCTAssertNil(EventsDetailModel.windowRule(of: F.entry(F.solar(), visibility: F.visible(darknessLimit: 0))))
    }

    func testMeteorShowersNeedAstronomicalDarkness() {
        XCTAssertEqual(EventsDetailModel.windowRule(of: F.entry(F.meteor(), visibility: F.visible(darknessLimit: -18))),
                       "A viewing window needs the target at least 10\u{00B0} high and the Sun at least 18\u{00B0} below the horizon.")
    }

    func testConjunctionsNeedTheEndOfCivilTwilight() {
        XCTAssertEqual(EventsDetailModel.windowRule(of: F.entry(F.conjunction(), visibility: F.visible(darknessLimit: -6))),
                       "A viewing window needs the target at least 10\u{00B0} high and the Sun at least 6\u{00B0} below the horizon.")
    }

    func testSpecialFullMoonsNeedOnlySunset() {
        XCTAssertEqual(EventsDetailModel.windowRule(of: F.entry(F.fullMoon([.supermoon]),
                                                                visibility: F.visible(darknessLimit: -0.8333))),
                       "A viewing window needs the target at least 10\u{00B0} high after sunset.")
    }

    func testTheSunsetRuleEndsJustAboveOneDegree() {
        let sunset = "A viewing window needs the target at least 10\u{00B0} high after sunset."
        XCTAssertEqual(EventsDetailModel.windowRule(of: F.entry(F.conjunction(), visibility: F.visible(darknessLimit: -0.9999))),
                       sunset)
        XCTAssertEqual(EventsDetailModel.windowRule(of: F.entry(F.conjunction(), visibility: F.visible(darknessLimit: -1))),
                       "A viewing window needs the target at least 10\u{00B0} high and the Sun at least 1\u{00B0} below the horizon.")
    }

    func testTheDepthOfTheSunIsRoundedToWholeDegrees() {
        XCTAssertEqual(EventsDetailModel.windowRule(of: F.entry(F.conjunction(), visibility: F.visible(darknessLimit: -5.6))),
                       "A viewing window needs the target at least 10\u{00B0} high and the Sun at least 6\u{00B0} below the horizon.")
        XCTAssertEqual(EventsDetailModel.windowRule(of: F.entry(F.conjunction(), visibility: F.visible(darknessLimit: -17.4))),
                       "A viewing window needs the target at least 10\u{00B0} high and the Sun at least 17\u{00B0} below the horizon.")
    }

    func testAPositiveDarknessLimitNeedsNoRule() {
        XCTAssertNil(EventsDetailModel.windowRule(of: F.entry(F.conjunction(), visibility: F.visible(darknessLimit: 3))))
    }

    // MARK: Contacts

    func testAnEntryWithoutVisibilityHasNoContacts() {
        XCTAssertTrue(EventsDetailModel.contacts(of: F.entry(F.lunar(.total))).isEmpty)
    }

    func testAnEventWithoutContactsHasNone() {
        XCTAssertTrue(EventsDetailModel.contacts(of: F.entry(F.lunar(.total), visibility: F.visible())).isEmpty)
    }

    func testTheContactsOfALunarEclipseAreNamedAndInTimeOrder() {
        // Handed over out of order on purpose.
        let contacts = [
            F.contact(.p4, "2026-03-03T14:20:00Z"), F.contact(.u2, "2026-03-03T11:00:00Z"),
            F.contact(.p1, "2026-03-03T08:40:00Z"), F.contact(.u4, "2026-03-03T13:15:00Z"),
            F.contact(.greatest, "2026-03-03T11:30:00Z"), F.contact(.u1, "2026-03-03T09:50:00Z"),
            F.contact(.u3, "2026-03-03T12:00:00Z"),
        ]
        let rows = EventsDetailModel.contacts(of: F.entry(F.lunar(.total), visibility: F.visibility(contacts: contacts)))
        XCTAssertEqual(rows.map(\.name), ["Penumbra begins", "Partial phase begins", "Totality begins", "Greatest eclipse",
                                          "Totality ends", "Partial phase ends", "Penumbra ends"])
        XCTAssertEqual(rows.map(\.id), ["P1", "U1", "U2", "greatest", "U3", "U4", "P4"])
        XCTAssertEqual(rows.map(\.time), rows.map(\.time).sorted())
    }

    func testAContactRowKeepsTheTimeAndThePlaceOfTheMoon() {
        let contacts = [F.contact(.greatest, "2026-03-03T11:30:00Z", altitude: -4.5, azimuth: 250)]
        let rows = EventsDetailModel.contacts(of: F.entry(F.lunar(.total), visibility: F.visibility(contacts: contacts)))
        XCTAssertEqual(rows, [EventsContactRow(id: "greatest", name: "Greatest eclipse",
                                               time: F.date("2026-03-03T11:30:00Z"), altitude: -4.5, azimuth: 250)])
        XCTAssertTrue(rows[0].isBelowHorizon)
    }

    func testTheContactsOfATotalSolarEclipseSpeakOfTotality() {
        let contacts = [
            F.contact(.c4, "2026-08-12T19:30:00Z"), F.contact(.c1, "2026-08-12T17:33:00Z"),
            F.contact(.c3, "2026-08-12T18:30:00Z"), F.contact(.maximum, "2026-08-12T18:29:00Z"),
            F.contact(.c2, "2026-08-12T18:28:00Z"),
        ]
        let entry = F.entry(F.solar(.total, local: F.local(.total)), visibility: F.visibility(contacts: contacts))
        let rows = EventsDetailModel.contacts(of: entry)
        XCTAssertEqual(rows.map(\.name), ["Eclipse begins", "Totality begins", "Maximum", "Totality ends", "Eclipse ends"])
        XCTAssertEqual(rows.map(\.id), ["C1", "C2", "maximum", "C3", "C4"])
    }

    func testTheContactsOfAnAnnularSolarEclipseSpeakOfAnnularity() {
        let contacts = [F.contact(.c2, "2026-08-12T18:28:00Z"), F.contact(.c3, "2026-08-12T18:33:00Z")]
        let entry = F.entry(F.solar(.annular, local: F.local(.annular)), visibility: F.visibility(contacts: contacts))
        XCTAssertEqual(EventsDetailModel.contacts(of: entry).map(\.name), ["Annularity begins", "Annularity ends"])
    }

    func testTheContactsOfAPartialSolarEclipseHereSpeakOfACentralPhase() {
        let contacts = [F.contact(.c2, "2026-08-12T18:28:00Z"), F.contact(.c3, "2026-08-12T18:33:00Z")]
        let entry = F.entry(F.solar(.total, local: F.local(.partial)), visibility: F.visibility(contacts: contacts))
        XCTAssertEqual(EventsDetailModel.contacts(of: entry).map(\.name), ["Central phase begins", "Central phase ends"])
    }

    func testTheContactsOfASolarEclipseWithoutLocalCircumstancesSpeakOfACentralPhase() {
        let contacts = [F.contact(.c2, "2026-08-12T18:28:00Z"), F.contact(.c3, "2026-08-12T18:33:00Z")]
        let entry = F.entry(F.solar(.total, local: nil), visibility: F.visibility(contacts: contacts))
        XCTAssertEqual(EventsDetailModel.contacts(of: entry).map(\.name), ["Central phase begins", "Central phase ends"])
    }

    func testTheBelowHorizonFlagFollowsTheAltitudeOfEachContact() {
        let contacts = [
            F.contact(.p1, "2026-03-03T08:40:00Z", altitude: -12), F.contact(.u1, "2026-03-03T09:50:00Z", altitude: 0),
            F.contact(.u2, "2026-03-03T11:00:00Z", altitude: 25),
        ]
        let rows = EventsDetailModel.contacts(of: F.entry(F.lunar(.total), visibility: F.visibility(contacts: contacts)))
        XCTAssertEqual(rows.map(\.isBelowHorizon), [true, false, false])
    }
}
