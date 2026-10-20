import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Zones, events and visibility values for the tests of `EventsFormat.swift`.
private enum EventsFormatFixtures {
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

    /// 17:46 UTC on August 12, 2026: 12:46 that day in Chicago and 02:46 on August 13 in Tokyo.
    static let moment = date("2026-08-12T17:46:00Z")

    static let window = DateInterval(start: date("2026-08-13T02:10:00Z"), end: date("2026-08-13T08:50:00Z"))

    static func visibility(altitude: Double = 40, window: DateInterval? = nil) -> EventVisibility {
        EventVisibility(altitude: altitude, azimuth: 135, sunAltitude: -25, isDark: true, bestWindow: window,
                        bestTime: window?.start, darknessLimit: -18, contacts: [])
    }

    static func entry(_ details: EventDetails, visibility: EventVisibility? = nil,
                      interference: EventsMoonInterference? = nil) -> EventsEntry {
        EventsEntry(event: AstronomicalEvent(date: moment, details: details, visibility: visibility),
                    moonInterference: interference)
    }

    // MARK: Details

    static func meteor(zhr: Int = 100, moonFraction: Double = 0.64) -> EventDetails {
        let shower = MeteorShower(
            code: "TST", iauNumber: 999, name: "Perseids", activityStartMonth: 7, activityStartDay: 17, activityEndMonth: 8,
            activityEndDay: 24, peakSolarLongitude: 140, zhr: zhr,
            radiant: EquatorialCoordinate(rightAscension: 48, declination: 58), radiantDriftRightAscension: 1.42,
            radiantDriftDeclination: 0.2, velocity: 59, populationIndex: 2.2)
        return .meteorShower(MeteorShowerPeak(
            shower: shower, activityStart: date("2026-07-17T00:00:00Z"), activityEnd: date("2026-08-25T00:00:00Z"),
            moonIlluminatedFraction: moonFraction, radiant: shower.radiant))
    }

    static func conjunction(_ first: ConjunctionTarget = .body(.moon), _ second: ConjunctionTarget = .body(.venus),
                            separation: Double = 2.5, topocentric: TopocentricApproach? = nil) -> EventDetails {
        .conjunction(Conjunction(first: first, second: second, separation: separation, solarElongation: 90,
                                 occultationPossible: false, topocentric: topocentric))
    }

    static func opposition(magnitude: Double? = -2.5) -> EventDetails {
        .opposition(Opposition(planet: .mars, distanceAU: 4.0, apparentMagnitude: magnitude, angularDiameterArcseconds: 45.67))
    }

    static func elongation(_ direction: ElongationDirection, magnitude: Double? = nil) -> EventDetails {
        .greatestElongation(GreatestElongation(planet: .venus, direction: direction, angle: 46.0, apparentMagnitude: magnitude))
    }

    static func season(_ kind: SeasonKind) -> EventDetails {
        .season(Season(kind: kind))
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

    /// What the observer sees: the maximum at 18:29:13 UTC unless told otherwise.
    static func local(_ kind: LocalSolarEclipseKind, maximum: Date? = EventsFormatFixtures.date("2026-08-12T18:29:13Z"),
                      obscuration: Double = 0.62, duration: Double = 106) -> LocalSolarCircumstances {
        LocalSolarCircumstances(kind: kind, c1: nil, c2: nil, maximum: maximum, c3: nil, c4: nil, magnitude: 1.0386,
                                obscuration: obscuration, sunAltitude: 12.4, sunAzimuth: 268, centralDuration: duration,
                                visibleInterval: nil)
    }

    static func solar(_ kind: SolarEclipseKind = .total, local: LocalSolarCircumstances? = nil) -> EventDetails {
        .solarEclipse(SolarEclipse(kind: kind, greatest: moment, gamma: 0.8977, greatestMagnitude: 1.0386,
                                   isCentral: true, local: local))
    }
}

final class EventsFormatTests: XCTestCase {
    private typealias F = EventsFormatFixtures

    // MARK: Symbols

    func testEachKindOfEventHasItsSymbol() {
        func symbol(_ details: EventDetails) -> String { EventsFormat.symbol(for: F.entry(details).event) }
        XCTAssertEqual(symbol(F.meteor()), "sparkles")
        XCTAssertEqual(symbol(F.opposition()), "arrow.left.arrow.right.circle")
        XCTAssertEqual(symbol(F.elongation(.east)), "angle")
        XCTAssertEqual(symbol(.earthApsis(EarthApsis(kind: .aphelion, distanceAU: 1.0167))), "globe.europe.africa")
        XCTAssertEqual(symbol(F.season(.marchEquinox)), "sun.max")
        XCTAssertEqual(symbol(.fullMoonSpecial(FullMoonSpecial(categories: [.blueMoon], distanceKilometers: 380_000,
                                                               angularDiameterArcseconds: 1_900))), "moonphase.full.moon")
        XCTAssertEqual(symbol(F.lunar(.total)), "moon.circle.fill")
        XCTAssertEqual(symbol(F.solar()), "sun.max.fill")
    }

    func testAConjunctionWithTheMoonHasAMoonSymbol() {
        XCTAssertEqual(EventsFormat.symbol(for: F.entry(F.conjunction(.body(.moon), .body(.venus))).event), "moon.circle")
        XCTAssertEqual(EventsFormat.symbol(for: F.entry(F.conjunction(.body(.moon), .star(.spica))).event), "moon.circle")
    }

    func testAConjunctionOfPlanetsHasAPairSymbol() {
        XCTAssertEqual(EventsFormat.symbol(for: F.entry(F.conjunction(.body(.venus), .body(.jupiter))).event),
                       "circle.grid.2x1.fill")
    }

    // MARK: Dates

    func testDayAndTimeJoinsTheDayAndTheTimeInTheZone() {
        let text = EventsFormat.dayAndTime(F.moment, in: F.chicago)
        let parts = text.components(separatedBy: " \u{00B7} ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], AppFormat.day(F.moment, in: F.chicago))
        XCTAssertEqual(parts[1], AppFormat.time(F.moment, in: F.chicago))
    }

    func testDayAndTimeFollowsTheZoneToTheNextDay() {
        let chicago = EventsFormat.dayAndTime(F.moment, in: F.chicago).components(separatedBy: " \u{00B7} ")
        let tokyo = EventsFormat.dayAndTime(F.moment, in: F.tokyo).components(separatedBy: " \u{00B7} ")
        // 12:46 on August 12 in Chicago, 02:46 on August 13 in Tokyo.
        XCTAssertNotEqual(chicago[0], tokyo[0])
        XCTAssertNotEqual(chicago[1], tokyo[1])
    }

    func testFullDateTimeFollowsTheZone() {
        XCTAssertNotEqual(EventsFormat.fullDateTime(F.moment, in: F.chicago), EventsFormat.fullDateTime(F.moment, in: F.tokyo))
    }

    func testFullDateTimeOfTwoZonesWithTheSameOffsetIsTheSame() throws {
        let plusOne = try XCTUnwrap(TimeZone(secondsFromGMT: 3_600))
        let etc = try XCTUnwrap(TimeZone(identifier: "Etc/GMT-1"))
        XCTAssertEqual(EventsFormat.fullDateTime(F.moment, in: plusOne), EventsFormat.fullDateTime(F.moment, in: etc))
    }

    func testTheMonthIsTheMonthInTheZone() {
        // 02:00 UTC on August 1 is still July 31 in Chicago.
        let instant = F.date("2026-08-01T02:00:00Z")
        XCTAssertNotEqual(EventsFormat.month(instant, in: F.utc), EventsFormat.month(instant, in: F.chicago))
        XCTAssertEqual(EventsFormat.month(instant, in: F.utc), EventsFormat.month(F.date("2026-08-20T12:00:00Z"), in: F.utc))
        XCTAssertEqual(EventsFormat.month(instant, in: F.chicago),
                       EventsFormat.month(F.date("2026-07-15T12:00:00Z"), in: F.chicago))
    }

    func testTheMonthNamesTheYearToo() {
        XCTAssertNotEqual(EventsFormat.month(F.date("2026-12-15T12:00:00Z"), in: F.utc),
                          EventsFormat.month(F.date("2027-12-15T12:00:00Z"), in: F.utc))
        XCTAssertNotEqual(EventsFormat.month(F.date("2026-12-15T12:00:00Z"), in: F.utc),
                          EventsFormat.month(F.date("2026-11-15T12:00:00Z"), in: F.utc))
    }

    func testTheMonthAtTheNewYearDependsOnTheZone() {
        // 20:00 UTC on December 31 is already January 1 in Tokyo.
        let instant = F.date("2026-12-31T20:00:00Z")
        XCTAssertEqual(EventsFormat.month(instant, in: F.tokyo), EventsFormat.month(F.date("2027-01-10T00:00:00Z"), in: F.tokyo))
        XCTAssertNotEqual(EventsFormat.month(instant, in: F.tokyo), EventsFormat.month(instant, in: F.utc))
    }

    func testTheZoneNameFollowsDaylightSavingTime() {
        XCTAssertEqual(EventsFormat.zoneName(F.chicago, at: F.date("2026-07-01T12:00:00Z")), "CDT")
        XCTAssertEqual(EventsFormat.zoneName(F.chicago, at: F.date("2026-12-01T12:00:00Z")), "CST")
    }

    // MARK: Countdown

    private func countdown(to target: String, from now: String = "2026-08-12T15:00:00Z", in zone: TimeZone? = nil) -> String {
        EventsFormat.countdown(to: F.date(target), from: F.date(now), in: zone ?? F.chicago)
    }

    func testAnEventLaterTheSameLocalDayIsToday() {
        // 10:00 in Chicago now; 18:30 the same day.
        XCTAssertEqual(countdown(to: "2026-08-12T23:30:00Z"), "Today")
    }

    func testAnEventEarlierTheSameLocalDayIsStillToday() {
        // 00:30 in Chicago, nine and a half hours before now.
        XCTAssertEqual(countdown(to: "2026-08-12T05:30:00Z"), "Today")
    }

    func testTheLastMinuteOfTheLocalDayIsStillToday() {
        // 23:59 in Chicago.
        XCTAssertEqual(countdown(to: "2026-08-13T04:59:00Z"), "Today")
    }

    func testTheFirstMinuteOfTheNextLocalDayIsTomorrow() {
        // 00:00 in Chicago on August 13, only 14 hours after now.
        XCTAssertEqual(countdown(to: "2026-08-13T05:00:00Z"), "Tomorrow")
    }

    func testTheLastMinuteOfYesterdayIsYesterday() {
        // 23:59 in Chicago on August 11.
        XCTAssertEqual(countdown(to: "2026-08-12T04:59:00Z"), "Yesterday")
    }

    func testTheFirstMinuteOfTodayIsNotYesterday() {
        // 00:00 in Chicago on August 12.
        XCTAssertEqual(countdown(to: "2026-08-12T05:00:00Z"), "Today")
    }

    func testAFewDaysAheadCountsLocalDays() {
        XCTAssertEqual(countdown(to: "2026-08-14T15:00:00Z"), "In 2 days")
        XCTAssertEqual(countdown(to: "2026-08-24T15:00:00Z"), "In 12 days")
        XCTAssertEqual(countdown(to: "2027-08-12T15:00:00Z"), "In 365 days")
    }

    func testAFewDaysAgoCountsLocalDays() {
        XCTAssertEqual(countdown(to: "2026-08-10T15:00:00Z"), "2 days ago")
        XCTAssertEqual(countdown(to: "2026-08-09T15:00:00Z"), "3 days ago")
    }

    func testTheSameInstantsCanBeTodayInOneZoneAndTomorrowInAnother() {
        // 10:00 UTC and 16:00 UTC on August 12: the same day in Chicago, but 19:00 and 01:00 (next day) in Tokyo.
        let now = "2026-08-12T10:00:00Z"
        let target = "2026-08-12T16:00:00Z"
        XCTAssertEqual(countdown(to: target, from: now, in: F.chicago), "Today")
        XCTAssertEqual(countdown(to: target, from: now, in: F.tokyo), "Tomorrow")
    }

    func testDaylightSavingTimeDoesNotShiftTheCount() {
        // Chicago returns to standard time on November 1, 2026: two calendar days are 49 hours apart.
        XCTAssertEqual(countdown(to: "2026-11-02T12:00:00Z", from: "2026-10-31T12:00:00Z"), "In 2 days")
        XCTAssertEqual(countdown(to: "2026-11-01T12:00:00Z", from: "2026-10-31T12:00:00Z"), "Tomorrow")
        // And it moves forward on March 8, 2026: the next calendar day is only 23 hours away.
        XCTAssertEqual(countdown(to: "2026-03-08T12:00:00Z", from: "2026-03-07T13:00:00Z"), "Tomorrow")
    }

    // MARK: Windows

    func testAWindowKeepsEachTimeAndTheDashTogether() {
        let text = EventsFormat.window(F.window, in: F.utc)
        let parts = text.components(separatedBy: "\u{00A0}\u{2013} ")
        XCTAssertEqual(parts.count, 2)
        // The times are the zone's times, with their own spaces made non-breaking.
        XCTAssertEqual(parts[0].replacingOccurrences(of: "\u{00A0}", with: " "), AppFormat.time(F.window.start, in: F.utc))
        XCTAssertEqual(parts[1].replacingOccurrences(of: "\u{00A0}", with: " "), AppFormat.time(F.window.end, in: F.utc))
    }

    func testAWindowCanBreakOnlyAfterTheDash() {
        // The only plain space is the one after the dash.
        let text = EventsFormat.window(F.window, in: F.chicago)
        XCTAssertEqual(text.filter { $0 == " " }.count, 1)
        XCTAssertTrue(text.contains("\u{2013} "))
        XCTAssertFalse(text.contains(" \u{2013}"))
    }

    func testAWindowFollowsTheZone() {
        XCTAssertNotEqual(EventsFormat.window(F.window, in: F.utc), EventsFormat.window(F.window, in: F.tokyo))
    }

    func testASpokenWindowReadsFromOneTimeToTheOther() {
        let text = EventsFormat.spokenWindow(F.window, in: F.tokyo)
        let parts = text.components(separatedBy: " to ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], AppFormat.time(F.window.start, in: F.tokyo))
        XCTAssertEqual(parts[1], AppFormat.time(F.window.end, in: F.tokyo))
    }

    // MARK: Visibility

    func testVisibilityTextSaysWhetherTheEventCanBeSeen() {
        XCTAssertEqual(EventsFormat.visibilityText(of: F.entry(F.meteor(), visibility: F.visibility(window: F.window))),
                       "Visible from here")
        XCTAssertEqual(EventsFormat.visibilityText(of: F.entry(F.meteor(), visibility: F.visibility(window: nil))),
                       "Not visible from here")
    }

    func testVisibilityTextIsMissingForEventsNotSeenInTheSky() {
        XCTAssertNil(EventsFormat.visibilityText(of: F.entry(F.season(.juneSolstice))))
        XCTAssertNil(EventsFormat.visibilityText(of: F.entry(F.meteor())))
    }

    func testMoonTextForEachLevel() {
        func text(_ level: EventsMoonInterference.Level, _ fraction: Double) -> String {
            EventsFormat.moonText(EventsMoonInterference(illuminatedFraction: fraction, moonAltitude: 10, level: level))
        }
        XCTAssertEqual(text(.moonDown, 0.64), "Moon 64% lit, but below the horizon at the best time")
        XCTAssertEqual(text(.little, 0.2), "Moon 20% lit: little interference")
        XCTAssertEqual(text(.moderate, 0.4), "Moon 40% lit: moonlight hides the fainter meteors")
        XCTAssertEqual(text(.strong, 0.9), "Moon 90% lit: strong moonlight, only the brighter meteors show")
    }

    func testShortMoonTextForEachLevel() {
        func text(_ level: EventsMoonInterference.Level) -> String {
            EventsFormat.shortMoonText(EventsMoonInterference(illuminatedFraction: 0.5, moonAltitude: 10, level: level))
        }
        XCTAssertEqual(text(.moonDown), "Moon down at the best time")
        XCTAssertEqual(text(.little), "Little Moon interference")
        XCTAssertEqual(text(.moderate), "Some moonlight")
        XCTAssertEqual(text(.strong), "Strong moonlight")
    }

    // MARK: Summaries: meteor showers and conjunctions

    private func summary(_ details: EventDetails, visibility: EventVisibility? = nil, southern: Bool = false,
                         in zone: TimeZone? = nil) -> String {
        EventsFormat.summary(of: F.entry(details, visibility: visibility), isSouthernHemisphere: southern,
                             timeZone: zone ?? F.utc)
    }

    func testAMeteorShowerSummaryGivesTheRateAndTheMoon() {
        XCTAssertEqual(summary(F.meteor()), "ZHR 100 \u{00B7} Moon 64% lit")
    }

    func testAMeteorShowerSummaryAddsTheRadiantWhenItIsUp() {
        XCTAssertEqual(summary(F.meteor(), visibility: F.visibility(altitude: 34.4)),
                       "ZHR 100 \u{00B7} Moon 64% lit \u{00B7} radiant 34\u{00B0} high")
    }

    func testAMeteorShowerSummaryLeavesOutARadiantOnOrBelowTheHorizon() {
        XCTAssertEqual(summary(F.meteor(), visibility: F.visibility(altitude: 0)), "ZHR 100 \u{00B7} Moon 64% lit")
        XCTAssertEqual(summary(F.meteor(), visibility: F.visibility(altitude: -12)), "ZHR 100 \u{00B7} Moon 64% lit")
    }

    func testAMeteorShowerSummaryRoundsTheMoonToWholePercents() {
        XCTAssertEqual(summary(F.meteor(zhr: 150, moonFraction: 0.0)), "ZHR 150 \u{00B7} Moon 0% lit")
        XCTAssertEqual(summary(F.meteor(zhr: 5, moonFraction: 1.0)), "ZHR 5 \u{00B7} Moon 100% lit")
    }

    func testAConjunctionSummaryGivesTheSeparation() {
        XCTAssertEqual(summary(F.conjunction(separation: 2.5)), "2.5\u{00B0} apart")
        XCTAssertEqual(summary(F.conjunction(separation: 12.4)), "12\u{00B0} apart")
        XCTAssertEqual(summary(F.conjunction(separation: 0.5)), "30\u{2032} apart")
    }

    func testAConjunctionSummaryMentionsAnOccultationFromHere() {
        let occultation = TopocentricApproach(time: F.moment, separation: 0.0, isOccultation: true)
        XCTAssertEqual(summary(F.conjunction(.body(.moon), .star(.spica), separation: 0.5, topocentric: occultation)),
                       "30\u{2032} apart \u{00B7} occultation from here")
    }

    func testAConjunctionSummaryIgnoresAMissWithTheMoonFromHere() {
        let miss = TopocentricApproach(time: F.moment, separation: 0.4, isOccultation: false)
        XCTAssertEqual(summary(F.conjunction(.body(.moon), .star(.spica), separation: 0.5, topocentric: miss)),
                       "30\u{2032} apart")
    }

    // MARK: Summaries: planets, apsides, seasons, the Moon

    func testAnOppositionSummaryGivesTheBrightnessAndTheDistance() {
        let text = summary(F.opposition(magnitude: -2.5))
        XCTAssertTrue(text.hasPrefix("mag \u{2212}2"), text)
        XCTAssertTrue(text.contains(" \u{00B7} "), text)
        XCTAssertTrue(text.hasSuffix(" AU away"), text)
        // Mars at 4.00 AU.
        XCTAssertEqual(F.digits(text), "25400")
    }

    func testAnOppositionSummaryWithoutABrightnessGivesOnlyTheDistance() {
        let text = summary(F.opposition(magnitude: nil))
        XCTAssertFalse(text.contains("mag"), text)
        XCTAssertFalse(text.contains("\u{00B7}"), text)
        XCTAssertTrue(text.hasSuffix(" AU away"), text)
        XCTAssertEqual(F.digits(text), "400")
    }

    func testAnEveningElongationSummary() {
        XCTAssertEqual(summary(F.elongation(.east)), "46\u{00B0} east of the Sun \u{00B7} evening sky")
    }

    func testAMorningElongationSummary() {
        XCTAssertEqual(summary(F.elongation(.west)), "46\u{00B0} west of the Sun \u{00B7} morning sky")
    }

    func testAnElongationSummaryAddsTheBrightness() {
        let text = summary(F.elongation(.east, magnitude: -4.2))
        XCTAssertTrue(text.hasPrefix("46\u{00B0} east of the Sun \u{00B7} evening sky \u{00B7} mag \u{2212}4"), text)
    }

    func testAnApsisSummaryGivesTheDistanceToThreePlaces() {
        let text = summary(.earthApsis(EarthApsis(kind: .perihelion, distanceAU: 0.9833)))
        XCTAssertTrue(text.hasSuffix(" AU from the Sun"), text)
        XCTAssertEqual(F.digits(text), "0983")
    }

    func testSeasonSummariesForTheNorthernHemisphere() {
        XCTAssertEqual(summary(F.season(.marchEquinox)), "Spring begins \u{00B7} day and night nearly equal")
        XCTAssertEqual(summary(F.season(.juneSolstice)), "Summer begins \u{00B7} longest day")
        XCTAssertEqual(summary(F.season(.septemberEquinox)), "Autumn begins \u{00B7} day and night nearly equal")
        XCTAssertEqual(summary(F.season(.decemberSolstice)), "Winter begins \u{00B7} shortest day")
    }

    func testSeasonSummariesForTheSouthernHemisphere() {
        XCTAssertEqual(summary(F.season(.marchEquinox), southern: true), "Autumn begins \u{00B7} day and night nearly equal")
        XCTAssertEqual(summary(F.season(.juneSolstice), southern: true), "Winter begins \u{00B7} shortest day")
        XCTAssertEqual(summary(F.season(.septemberEquinox), southern: true), "Spring begins \u{00B7} day and night nearly equal")
        XCTAssertEqual(summary(F.season(.decemberSolstice), southern: true), "Summer begins \u{00B7} longest day")
    }

    func testASpecialFullMoonSummaryGivesTheDistanceAndTheSize() {
        let text = summary(.fullMoonSpecial(FullMoonSpecial(categories: [.supermoon], distanceKilometers: 356_900.4,
                                                            angularDiameterArcseconds: 2_010)))
        XCTAssertTrue(text.contains(" km away \u{00B7} "), text)
        XCTAssertTrue(text.hasSuffix("\u{2032} across"), text)
        // 356,900 km and 33.5 arcminutes.
        XCTAssertEqual(F.digits(text), "356900335")
    }

    // MARK: Summaries: eclipses

    func testAPenumbralLunarEclipseSummaryGivesThePenumbralMagnitude() {
        let text = summary(F.lunar(.penumbral))
        XCTAssertTrue(text.hasPrefix("Penumbral magnitude "), text)
        XCTAssertEqual(F.digits(text), "0923")
    }

    func testAPartialLunarEclipseSummaryGivesTheUmbralMagnitude() {
        let text = summary(F.lunar(.partial))
        XCTAssertTrue(text.hasPrefix("Umbral magnitude "), text)
        XCTAssertFalse(text.contains("totality"), text)
        XCTAssertEqual(F.digits(text), "0512")
    }

    func testATotalLunarEclipseSummaryAddsTheLengthOfTotality() {
        let text = summary(F.lunar(.total))
        XCTAssertTrue(text.hasPrefix("Umbral magnitude "), text)
        XCTAssertTrue(text.hasSuffix(" \u{00B7} totality 59m 00s"), text)
        XCTAssertEqual(F.digits(text), "11725900")
    }

    func testASolarEclipseSummaryWithoutAnObserverGivesTheGreatestEclipse() {
        let text = summary(F.solar(.annular), in: F.tokyo)
        XCTAssertEqual(text, "Annular, greatest eclipse " + AppFormat.time(F.moment, in: F.tokyo))
    }

    func testASolarEclipseSummaryWithAnObserverButNoLocalCircumstancesFallsBackToTheGreatestEclipse() {
        let text = summary(F.solar(.hybrid, local: nil), visibility: F.visibility(window: F.window), in: F.utc)
        XCTAssertEqual(text, "Hybrid, greatest eclipse " + AppFormat.time(F.moment, in: F.utc))
    }

    func testASolarEclipseSummaryIgnoresLocalCircumstancesWithoutAnObserver() {
        // Without a visibility the observer is unknown, so the local part is not trusted.
        let text = summary(F.solar(.total, local: F.local(.total)))
        XCTAssertEqual(text, "Total, greatest eclipse " + AppFormat.time(F.moment, in: F.utc))
    }

    func testASolarEclipseSummaryWhenNothingIsVisible() {
        let text = summary(F.solar(.total, local: F.local(LocalSolarEclipseKind.none, maximum: nil)),
                           visibility: F.visibility(window: nil))
        XCTAssertEqual(text, "No eclipse visible from here")
    }

    func testASolarEclipseSummaryForAPartialEclipseHere() {
        let maximum = F.local(.partial, obscuration: 0.62).maximum
        let text = summary(F.solar(.partial, local: F.local(.partial, obscuration: 0.62)),
                           visibility: F.visibility(window: F.window), in: F.tokyo)
        XCTAssertEqual(text, "Partial here: 62% covered, maximum " + AppFormat.time(maximum, in: F.tokyo))
    }

    func testASolarEclipseSummaryForAnAnnularEclipseHere() {
        let local = F.local(.annular, duration: 312)
        let text = summary(F.solar(.annular, local: local), visibility: F.visibility(window: F.window), in: F.utc)
        XCTAssertEqual(text, "Annular here: 5m 12s at " + AppFormat.time(local.maximum, in: F.utc))
    }

    func testASolarEclipseSummaryForATotalEclipseHere() {
        let local = F.local(.total, duration: 106)
        let text = summary(F.solar(.total, local: local), visibility: F.visibility(window: F.window), in: F.utc)
        XCTAssertEqual(text, "Total here: 1m 46s at " + AppFormat.time(local.maximum, in: F.utc))
    }

    func testTheLocalMaximumIsShownInTheZoneOfTheSite() {
        let local = F.local(.total)
        let utc = summary(F.solar(.total, local: local), visibility: F.visibility(window: F.window), in: F.utc)
        let tokyo = summary(F.solar(.total, local: local), visibility: F.visibility(window: F.window), in: F.tokyo)
        XCTAssertNotEqual(utc, tokyo)
        XCTAssertTrue(tokyo.hasSuffix(AppFormat.time(local.maximum, in: F.tokyo)), tokyo)
    }

    func testAMissingLocalMaximumReadsAsADash() {
        let local = F.local(.partial, maximum: nil)
        let text = summary(F.solar(.partial, local: local), visibility: F.visibility(window: F.window))
        XCTAssertEqual(text, "Partial here: 62% covered, maximum \u{2014}")
    }

    // MARK: Magnitudes

    func testAnEclipseMagnitudeHasThreeDecimals() {
        XCTAssertEqual(F.digits(EventsFormat.magnitude(1.172)), "1172")
        XCTAssertEqual(F.digits(EventsFormat.magnitude(0.5)), "0500")
        XCTAssertEqual(F.digits(EventsFormat.magnitude(1.0386)), "1039")
        XCTAssertEqual(F.digits(EventsFormat.magnitude(0)), "0000")
    }

    // MARK: Spoken summary

    func testTheSpokenSummaryOfAVisibleShowerHasEveryPart() {
        let moon = EventsMoonInterference(illuminatedFraction: 0.64, moonAltitude: 20, level: .strong)
        let entry = F.entry(F.meteor(), visibility: F.visibility(window: F.window), interference: moon)
        let text = EventsFormat.spokenSummary(of: entry, isSouthernHemisphere: false, timeZone: F.chicago)
        let expected = "Perseids peak, \(EventsFormat.fullDateTime(F.moment, in: F.chicago)), "
            + "ZHR 100 \u{00B7} Moon 64% lit \u{00B7} radiant 40\u{00B0} high, "
            + "Moon 64% lit: strong moonlight, only the brighter meteors show, Visible from here"
        XCTAssertEqual(text, expected)
    }

    func testTheSpokenSummaryOfAnInvisibleEventSaysSo() {
        let entry = F.entry(F.lunar(.partial), visibility: F.visibility(window: nil))
        let text = EventsFormat.spokenSummary(of: entry, isSouthernHemisphere: false, timeZone: F.utc)
        XCTAssertTrue(text.hasPrefix("Partial lunar eclipse, "), text)
        XCTAssertTrue(text.hasSuffix(", Not visible from here"), text)
        XCTAssertFalse(text.contains("Moon"), text)
    }

    func testTheSpokenSummaryOfAnEventNotSeenInTheSkyHasNoVisibilityPart() {
        let entry = F.entry(F.season(.marchEquinox))
        let text = EventsFormat.spokenSummary(of: entry, isSouthernHemisphere: true, timeZone: F.utc)
        let expected = "March equinox, \(EventsFormat.fullDateTime(F.moment, in: F.utc)), "
            + "Autumn begins \u{00B7} day and night nearly equal"
        XCTAssertEqual(text, expected)
    }
}
