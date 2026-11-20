import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The astronomy behind the Tonight screen (`TonightCalculator`): which night is "tonight", how far another night is
/// from it, when tonight ends, and the ranked targets.
final class TonightCalculatorTests: XCTestCase {
    private static let bundledCatalog = Result { try Catalog.loadBundled() }
    private static let fixtureCatalog = Result {
        try Catalog.loadBundled().withSmallBodies(TonightCalculatorTests.fixtureBodies())
    }

    private let boulder = Observer(location: GeographicLocation(latitude: 40.0, longitude: -105.27, elevation: 1650))
    private let tromso = Observer(location: GeographicLocation(latitude: 69.65, longitude: 18.96, elevation: 0))

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier), identifier)
    }

    private func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try zone(identifier)
        return calendar
    }

    private func local(_ identifier: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0)
        throws -> Date {
        try XCTUnwrap(try calendar(identifier).date(from: DateComponents(year: year, month: month, day: day,
                                                                         hour: hour, minute: minute)))
    }

    private func denver(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        try local("America/Denver", year, month, day, hour, minute)
    }

    private func makeContext(_ observer: Observer, _ identifier: String, horizon: HorizonProfile? = nil) throws
        -> ObserverContext {
        ObserverContext(observer: observer, timeZone: try zone(identifier), name: "Test site", source: .device,
                        horizontalAccuracy: nil, timestamp: nil, horizon: horizon)
    }

    private func boulderContext(horizon: HorizonProfile? = nil) throws -> ObserverContext {
        try makeContext(boulder, "America/Denver", horizon: horizon)
    }

    private func report(_ context: ObserverContext, _ choice: TonightNightChoice, now: Date,
                        catalog: Catalog? = nil) -> TonightReport {
        TonightCalculator.report(for: TonightInput(key: TonightNightKey(context: context, choice: choice), now: now,
                                                   catalog: catalog))
    }

    private func ranked(_ outcome: TonightTargetsOutcome) -> [TonightTarget]? {
        if case .ranked(let targets) = outcome { return targets }
        return nil
    }

    private func isNoDarkness(_ outcome: TonightTargetsOutcome) -> Bool {
        if case .noDarkness = outcome { return true }
        return false
    }

    private func isCatalogPending(_ outcome: TonightTargetsOutcome) -> Bool {
        if case .catalogPending = outcome { return true }
        return false
    }

    // MARK: Constants and noon

    func testTheTargetListLimitsAndTheMinimumAltitude() {
        XCTAssertEqual(TonightCalculator.targetLimit, 12)
        XCTAssertEqual(TonightCalculator.minimumTargetAltitude, NightPlanner.defaultMinimumAltitude)
        XCTAssertEqual(TonightCalculator.minimumTargetAltitude, 20.0)
    }

    func testLocalNoonIsNoonOfTheCalendarDayInTheCalendarsTimeZone() throws {
        let denverCalendar = try calendar("America/Denver")
        // 21:00 on 10 October in Denver is already 11 October in UTC.
        let evening = try denver(2026, 10, 10, 21, 0)
        XCTAssertEqual(TonightCalculator.localNoon(of: evening, calendar: denverCalendar), try denver(2026, 10, 10))
        XCTAssertEqual(TonightCalculator.localNoon(of: evening, calendar: try calendar("UTC")),
                       try local("UTC", 2026, 10, 11))
    }

    func testLocalNoonOfAMomentJustAfterMidnightIsTheNoonOfThatDay() throws {
        let justAfterMidnight = try denver(2026, 10, 11, 0, 1)
        XCTAssertEqual(TonightCalculator.localNoon(of: justAfterMidnight, calendar: try calendar("America/Denver")),
                       try denver(2026, 10, 11))
    }

    func testLocalNoonOnDaylightSavingChangeDays() throws {
        let denverCalendar = try calendar("America/Denver")
        for (month, day) in [(3, 8), (11, 1)] {
            let morning = try denver(2026, month, day, 6, 0)
            let noon = TonightCalculator.localNoon(of: morning, calendar: denverCalendar)
            let parts = denverCalendar.dateComponents([.month, .day, .hour, .minute, .second], from: noon)
            XCTAssertEqual(parts.month, month)
            XCTAssertEqual(parts.day, day)
            XCTAssertEqual(parts.hour, 12)
            XCTAssertEqual(parts.minute, 0)
            XCTAssertEqual(parts.second, 0)
        }
    }

    // MARK: Which night is tonight

    func testInTheEveningTonightIsTheNightThatStartsToday() throws {
        let now = try denver(2026, 10, 10, 20, 0)
        let result = report(try boulderContext(), .tonight, now: now)
        XCTAssertEqual(result.nightStart, try denver(2026, 10, 10))
        XCTAssertEqual(result.tonightStart, try denver(2026, 10, 10))
        XCTAssertEqual(result.nightsFromTonight, 0)
        XCTAssertEqual(result.summary.night.start, try denver(2026, 10, 10))
        XCTAssertEqual(result.summary.night.end, try denver(2026, 10, 11))
        XCTAssertEqual(result.timeZone, try zone("America/Denver"))
        XCTAssertFalse(result.appliesSkyline)
    }

    func testTonightEndsAtTheSunriseThatEndsTheNight() throws {
        let now = try denver(2026, 10, 10, 20, 0)
        let result = report(try boulderContext(), .tonight, now: now)
        let sunrise = try XCTUnwrap(result.summary.twilight.sunrise)
        XCTAssertEqual(result.tonightExpiry, sunrise)
        XCTAssertGreaterThan(sunrise.timeIntervalSince(now), 9 * 3600)
        XCTAssertLessThan(sunrise.timeIntervalSince(now), 13 * 3600)
    }

    func testAfterMidnightButBeforeSunriseTonightIsStillTheNightThatStartedYesterday() throws {
        let now = try denver(2026, 10, 11, 3, 0)
        let result = report(try boulderContext(), .tonight, now: now)
        XCTAssertEqual(result.nightStart, try denver(2026, 10, 10))
        XCTAssertEqual(result.tonightStart, try denver(2026, 10, 10))
        XCTAssertEqual(result.nightsFromTonight, 0)
        XCTAssertGreaterThan(result.tonightExpiry, now)
        XCTAssertLessThan(result.tonightExpiry.timeIntervalSince(now), 6 * 3600)
        XCTAssertEqual(result.tonightExpiry, result.summary.twilight.sunrise)
    }

    func testAfterSunriseTonightIsTheComingNight() throws {
        let now = try denver(2026, 10, 11, 9, 0)
        let result = report(try boulderContext(), .tonight, now: now)
        XCTAssertEqual(result.nightStart, try denver(2026, 10, 11))
        XCTAssertEqual(result.tonightStart, try denver(2026, 10, 11))
        XCTAssertEqual(result.nightsFromTonight, 0)
        XCTAssertGreaterThan(result.tonightExpiry.timeIntervalSince(now), 20 * 3600)
    }

    func testTonightMovesOnAtTheSunriseOfTheNightUnderWay() throws {
        let context = try boulderContext()
        let night = TwilightCalculator.night(startingOn: try denver(2026, 10, 10), observer: boulder,
                                             timeZone: context.timeZone)
        let sunrise = try XCTUnwrap(night.sunrise)
        let before = report(context, .tonight, now: sunrise.addingTimeInterval(-60))
        let after = report(context, .tonight, now: sunrise.addingTimeInterval(60))
        XCTAssertEqual(before.nightStart, try denver(2026, 10, 10))
        XCTAssertEqual(before.tonightExpiry, sunrise)
        XCTAssertEqual(after.nightStart, try denver(2026, 10, 11))
        XCTAssertGreaterThan(after.tonightExpiry, sunrise)
    }

    func testAtNoonTonightIsTheComingNight() throws {
        let result = report(try boulderContext(), .tonight, now: try denver(2026, 10, 11, 12, 0))
        XCTAssertEqual(result.nightStart, try denver(2026, 10, 11))
        XCTAssertEqual(result.nightsFromTonight, 0)
    }

    // MARK: Other nights

    func testALaterNightCountsTheNightsAfterTonight() throws {
        let now = try denver(2026, 10, 10, 20, 0)
        let result = report(try boulderContext(), .date(try denver(2026, 10, 13, 14, 0)), now: now)
        XCTAssertEqual(result.nightStart, try denver(2026, 10, 13))
        XCTAssertEqual(result.tonightStart, try denver(2026, 10, 10))
        XCTAssertEqual(result.nightsFromTonight, 3)
    }

    func testAnEarlierNightCountsNegativeNights() throws {
        let now = try denver(2026, 10, 10, 20, 0)
        let result = report(try boulderContext(), .date(try denver(2026, 10, 8, 3, 0)), now: now)
        XCTAssertEqual(result.nightStart, try denver(2026, 10, 8))
        XCTAssertEqual(result.nightsFromTonight, -2)
    }

    func testTheDateOfTonightIsNightZero() throws {
        let now = try denver(2026, 10, 10, 20, 0)
        let result = report(try boulderContext(), .date(try denver(2026, 10, 10, 6, 0)), now: now)
        XCTAssertEqual(result.nightStart, try denver(2026, 10, 10))
        XCTAssertEqual(result.nightsFromTonight, 0)
    }

    func testAnotherNightStillExpiresWhenTonightEnds() throws {
        let context = try boulderContext()
        let now = try denver(2026, 10, 10, 20, 0)
        let tonight = TwilightCalculator.night(startingOn: try denver(2026, 10, 10), observer: boulder,
                                               timeZone: context.timeZone)
        let result = report(context, .date(try denver(2026, 10, 13)), now: now)
        XCTAssertEqual(result.tonightExpiry, tonight.sunrise)
        XCTAssertNotEqual(result.tonightExpiry, result.summary.twilight.sunrise)
        XCTAssertLessThan(result.tonightExpiry, result.nightStart)
    }

    func testNightsAreCountedInCalendarDaysAcrossTheEndOfDaylightSavingTime() throws {
        // Clocks go back on 1 November 2026, so 31 October noon to 3 November noon is 73 hours but three nights.
        let now = try denver(2026, 10, 31, 20, 0)
        let result = report(try boulderContext(), .date(try denver(2026, 11, 3, 10, 0)), now: now)
        XCTAssertEqual(result.nightStart, try denver(2026, 11, 3))
        XCTAssertEqual(result.nightsFromTonight, 3)
        let back = report(try boulderContext(), .date(try denver(2026, 10, 30, 10, 0)), now: now)
        XCTAssertEqual(back.nightsFromTonight, -1)
    }

    func testTheTimelineBelongsToTheNightReported() throws {
        let result = report(try boulderContext(), .tonight, now: try denver(2026, 10, 10, 20, 0))
        XCTAssertEqual(result.timeline.range.start, result.summary.twilight.sunset)
        XCTAssertEqual(result.timeline.range.end, result.summary.twilight.sunrise)
        XCTAssertFalse(result.timeline.bands.isEmpty)
    }

    // MARK: The Sun that does not set

    func testInTheMidnightSunThereIsNoDarknessToRankInAndTonightEndsWithTheNight() throws {
        let site = try makeContext(tromso, "Europe/Oslo")
        let now = try local("Europe/Oslo", 2026, 6, 21, 22, 0)
        let result = report(site, .tonight, now: now)
        XCTAssertFalse(result.summary.hasAstronomicalDarkness)
        XCTAssertTrue(isNoDarkness(result.targets))
        XCTAssertNil(result.summary.twilight.sunrise)
        XCTAssertEqual(result.tonightExpiry, result.summary.night.end)
        XCTAssertEqual(result.nightStart, try local("Europe/Oslo", 2026, 6, 21))
        XCTAssertEqual(result.nightsFromTonight, 0)
        XCTAssertNil(result.smallBodies)
    }

    func testNoDarknessWinsOverAMissingCatalog() throws {
        let site = try makeContext(tromso, "Europe/Oslo")
        let now = try local("Europe/Oslo", 2026, 6, 21, 22, 0)
        let withoutCatalog = report(site, .tonight, now: now, catalog: nil)
        let withCatalog = report(site, .tonight, now: now, catalog: try Self.bundledCatalog.get())
        XCTAssertTrue(isNoDarkness(withoutCatalog.targets))
        XCTAssertTrue(isNoDarkness(withCatalog.targets))
    }

    func testInThePolarNightTheNightEndsWhereTheWindowEnds() throws {
        let pole = Observer(location: GeographicLocation(latitude: 89.9, longitude: 0, elevation: 0))
        let result = report(try makeContext(pole, "UTC"), .tonight, now: try local("UTC", 2026, 12, 21, 20, 0))
        XCTAssertTrue(result.summary.hasAstronomicalDarkness)
        XCTAssertNil(result.summary.twilight.sunrise)
        XCTAssertEqual(result.tonightExpiry, result.summary.night.end)
        XCTAssertEqual(result.timeline.bands.map(\.level), [.night])
    }

    // MARK: Targets

    func testWithoutACatalogTheTargetsArePendingAndThereIsNoSmallBodyCard() throws {
        let result = report(try boulderContext(), .tonight, now: try denver(2026, 10, 10, 20, 0), catalog: nil)
        XCTAssertTrue(isCatalogPending(result.targets))
        XCTAssertNil(result.smallBodies)
    }

    func testTheBestTargetsAreDeepSkyObjectsThatClimbHighInTheDark() throws {
        let catalog = try Self.bundledCatalog.get()
        let result = report(try boulderContext(), .tonight, now: try denver(2026, 10, 10, 20, 0), catalog: catalog)
        let targets = try XCTUnwrap(ranked(result.targets))
        XCTAssertEqual(targets.count, TonightCalculator.targetLimit)
        let dark = result.summary.astronomicalDarknessIntervals
        for target in targets {
            let label = target.object.id
            XCTAssertGreaterThanOrEqual(target.peakAltitude, TonightCalculator.minimumTargetAltitude, label)
            XCTAssertLessThanOrEqual(target.peakAltitude, 90, label)
            XCTAssertGreaterThan(target.hoursAboveMinimum, 0, label)
            XCTAssertLessThanOrEqual(target.hoursAboveMinimum, result.summary.astronomicalDarkHours + 0.01, label)
            XCTAssertTrue(dark.contains { $0.start <= target.peakTime && target.peakTime <= $0.end },
                          "\(label) peaks at \(target.peakTime), outside the dark hours")
            XCTAssertGreaterThanOrEqual(target.peakAzimuth, 0, label)
            XCTAssertLessThan(target.peakAzimuth, 360, label)
            XCTAssertTrue([ObjectGroup.galaxies, .nebulae, .clusters].contains(target.object.group), label)
            XCTAssertNil(target.note, label)
            XCTAssertEqual(target.id, target.object.id)
        }
        XCTAssertEqual(Set(targets.map(\.id)).count, targets.count, "no object is listed twice")
    }

    func testAnObjectThatPassesNearlyOverheadInTheDarkIsAmongTheBestTargets() throws {
        // The Andromeda Galaxy (declination +41) culminates within a degree of the zenith at 40 degrees north, around
        // one o'clock in the morning in early October; it is bright and the biggest object in the catalog.
        let catalog = try Self.bundledCatalog.get()
        let result = report(try boulderContext(), .tonight, now: try denver(2026, 10, 10, 20, 0), catalog: catalog)
        let targets = try XCTUnwrap(ranked(result.targets))
        let andromeda = try XCTUnwrap(targets.first { $0.object.id == "dso.M31" })
        XCTAssertGreaterThan(andromeda.peakAltitude, 80)
        XCTAssertGreaterThan(andromeda.hoursAboveMinimum, 6)
    }

    func testASkylineKeepsOnlyTargetsThatClearIt() throws {
        let catalog = try Self.bundledCatalog.get()
        let open = report(try boulderContext(), .tonight, now: try denver(2026, 10, 10, 20, 0))
        let walled = report(try boulderContext(horizon: HorizonProfile.constant(45)), .tonight,
                            now: try denver(2026, 10, 10, 20, 0), catalog: catalog)
        XCTAssertFalse(open.appliesSkyline)
        XCTAssertTrue(walled.appliesSkyline)
        let targets = try XCTUnwrap(ranked(walled.targets))
        XCTAssertFalse(targets.isEmpty)
        XCTAssertLessThanOrEqual(targets.count, TonightCalculator.targetLimit)
        for target in targets {
            XCTAssertGreaterThanOrEqual(target.peakAltitude, 44, target.object.id)
        }
        XCTAssertTrue(targets.contains { $0.object.id == "dso.M31" })
    }

    func testAFlatRecordedSkylineIsNotAppliedOrAnnounced() throws {
        let result = report(try boulderContext(horizon: HorizonProfile.flat), .tonight,
                            now: try denver(2026, 10, 10, 20, 0))
        XCTAssertFalse(result.appliesSkyline)
    }

    func testASkylineMovesTheMoonAndTheCoreInTheSummaryToo() throws {
        // At 40 degrees north the Galactic Centre peaks near 21 degrees, so a 30 degree skyline hides it all night.
        let now = try denver(2026, 6, 21, 20, 0)
        let open = report(try boulderContext(), .tonight, now: now)
        let walled = report(try boulderContext(horizon: HorizonProfile.constant(30)), .tonight, now: now)
        XCTAssertFalse(open.summary.milkyWayCore.visibleIntervals.isEmpty, "the core is up on a June night")
        XCTAssertTrue(walled.appliesSkyline)
        XCTAssertTrue(walled.summary.milkyWayCore.visibleIntervals.isEmpty)
        XCTAssertEqual(walled.summary.night, open.summary.night)
    }

    // MARK: Comets and asteroids among the targets

    private func fixtureTarget(_ catalog: Catalog) throws -> TonightReport {
        // The evening of 18 October 2026, the night of Vesta's opposition.
        report(try boulderContext(), .tonight, now: try denver(2026, 10, 18, 20, 0), catalog: catalog)
    }

    func testTheBrightCometsOfTheNightAreReported() throws {
        let result = try fixtureTarget(try Self.fixtureCatalog.get())
        let bright = try XCTUnwrap(result.smallBodies)
        // On this date 161P/Hartley-IRAS is the one comet brighter than magnitude 10.
        XCTAssertEqual(bright.map(\.id), ["comet.161P"])
        let magnitude = try XCTUnwrap(bright.first?.info.magnitude)
        XCTAssertEqual(magnitude, 9.7, accuracy: 0.15)
    }

    func testABrightAsteroidIsRankedBeforeTheDeepSkyObjects() throws {
        let result = try fixtureTarget(try Self.fixtureCatalog.get())
        let targets = try XCTUnwrap(ranked(result.targets))
        let first = try XCTUnwrap(targets.first)
        XCTAssertEqual(first.object.id, "asteroid.4")
        let note = try XCTUnwrap(first.note)
        XCTAssertTrue(note.hasPrefix("Asteroid\u{00A0}\u{00B7} mag\u{00A0}\u{2248}\u{00A0}"), note)
        XCTAssertTrue(note.hasSuffix("from\u{00A0}the\u{00A0}Sun"), note)
        XCTAssertGreaterThanOrEqual(first.peakAltitude, TonightCalculator.minimumTargetAltitude)
        // The comet is fainter than magnitude 8, so it is on the card but not among the targets.
        XCTAssertFalse(targets.contains { $0.object.id == "comet.161P" })
    }

    func testTheMovingTargetsComeFirstAndTheDeepSkyListKeepsItsLimit() throws {
        let result = try fixtureTarget(try Self.fixtureCatalog.get())
        let targets = try XCTUnwrap(ranked(result.targets))
        let moving = targets.prefix { $0.note != nil }
        let deepSky = targets.dropFirst(moving.count)
        XCTAssertGreaterThanOrEqual(moving.count, 1)
        XCTAssertLessThanOrEqual(moving.count, SmallBodyTonightPlanner.targetCount)
        XCTAssertEqual(deepSky.count, TonightCalculator.targetLimit)
        XCTAssertTrue(deepSky.allSatisfy { $0.note == nil })
        XCTAssertTrue(moving.allSatisfy { $0.object.smallBody != nil })
    }

    // MARK: Fixtures

    /// The comets of the review fixtures and the two brightest asteroids: real MPC lines of 2026-10-18.
    private static func fixtureBodies() throws -> [SmallBody] {
        let cometLines = [
            "    CJ95O010  1997 03 29.0284  0.925995  0.994895  130.7313  281.8097   89.7335  20261017  -2.0  4.0  C/1995 O1 (Hale-Bopp)                                    MPC194091",
            "    CK23A030  2024 09 27.8337  0.391312  1.000180  308.5842   21.6759  139.0991  20261017   6.5  3.2  C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2026-O98",
            "0012P         2024 04 21.2066  0.781920  0.954748  199.0355  255.8678   74.1469  20261017   5.0  6.0  12P/Pons-Brooks                                          MPEC 2026-TI5",
            "0001P         2061 08  1.5218  0.570945  0.968030  112.1616   59.2610  162.1917  20261017   5.5  3.2  1P/Halley                                                MPC191592",
            "0002P         2027 02 10.2276  0.338603  0.847319  187.2873  334.0197   11.3480  20261017  14.4  4.0  2P/Encke                                                 MPC xxxxx",
            "0073P     bt  2027 12 25.1036  0.915911  0.700909  214.4932   52.3435    6.1794  20261017  11.5  6.0  73P-BT/Schwassmann-Wachmann                              MPC106348",
            "    CK13A010  2014 10 26.8227  1.391249  1.000073    2.5353  301.1848  128.6857  20261017   8.2  2.4  C/2013 A1 (SidingSpring)                                 MPC194130",
            "    PK26N020  2026 09 25.7701  2.422069  0.212174  218.8645   96.3812    2.2496  20261017  17.4  4.0  P/2026 N2                                                MPEC 2026-Q95",
            "0161P         2026 11 27.1783  1.265109  0.836180   47.0652    1.4736   95.7919  20261017   8.5  6.0  161P/Hartley-IRAS                                        MPEC 2026-TP0",
            "0078P         2026 06 25.1355  2.004570  0.462933  192.8100  210.4913    6.2574  20261017   5.5  8.0  78P/Gehrels                                              MPEC 2026-TP0",
            "0029P         2034 03 15.1855  5.797924  0.042915   51.2459  312.3998    9.3549  20261017   4.0  4.0  29P/Schwassmann-Wachmann                                 MPEC 2026-RA1",
            "    CK14UR1N  2031 01 16.6692 10.959316  1.004054  326.0949  190.0073   95.4457  20261017   2.5  3.2  C/2014 UN271 (Bernardinelli-Bernstein)                   MPEC 2026-TP0",
            "    CK24E010  2026 01 20.8145  0.565779  1.000381  243.6172  108.0685   75.1999  20261017   7.0  4.0  C/2024 E1 (Wierzchos)                                    MPEC 2026-O98",
            "    PK26R020  2026 10 25.2362  0.789531  0.898740  205.5263  179.2306   78.0993  20261017  16.0  4.0  P/2026 R2 (Leonard)                                      MPC xxxxx",
        ]
        let asteroidLines = [
            "00001    3.34  0.15 K2669 274.41935   73.29420   80.24863   10.58803  0.0796923  0.21430445   2.7655526  0 E2026-SD4  7376 127 1801-2026 0.82 M-v 30k MPCORBFIT  4000      (1) Ceres              20260922",
            "00004    3.25  0.15 K2669  81.19019  151.46856  103.70135    7.14393  0.0902037  0.27161836   2.3613660  0 E2026-T23  7610 112 1821-2025 0.84 M-p 18k Pan        4000      (4) Vesta              20250624",
        ]
        return try cometLines.map { try CometElementsParser.parseLine($0) }
            + asteroidLines.map { try MinorPlanetElementsParser.parseLine($0) }
    }
}
