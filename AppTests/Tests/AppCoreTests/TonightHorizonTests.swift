import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The site's recorded skyline applied to a night (`TonightHorizon`): interval subtraction, which skyline counts, and the
/// Moon, the Milky Way core and the planets judged over it.
final class TonightHorizonTests: XCTestCase {
    private let boulder = Observer(location: GeographicLocation(latitude: 40.0, longitude: -105.27, elevation: 1650))
    private let tromso = Observer(location: GeographicLocation(latitude: 69.65, longitude: 18.96, elevation: 0))

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier), identifier)
    }

    /// Noon on a local calendar day: the instant that stands for the night starting on that date.
    private func noon(_ year: Int, _ month: Int, _ day: Int, in timeZone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private func flatSummary(_ observer: Observer, _ identifier: String, _ year: Int, _ month: Int, _ day: Int) throws
        -> NightSummary {
        let timeZone = try zone(identifier)
        return NightPlanner.summary(nightStartingOn: try noon(year, month, day, in: timeZone), observer: observer,
                                    timeZone: timeZone)
    }

    private func context(horizon: HorizonProfile?) throws -> ObserverContext {
        ObserverContext(observer: boulder, timeZone: try zone("America/Denver"), name: "Test site", source: .device,
                        horizontalAccuracy: nil, timestamp: nil, horizon: horizon)
    }

    private func total(_ intervals: [DateInterval]) -> TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    private func assertSameIntervals(_ actual: [DateInterval], _ expected: [DateInterval], accuracy: TimeInterval,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "\(actual) against \(expected)", file: file, line: line)
        for (found, wanted) in zip(actual, expected) {
            XCTAssertEqual(found.start.timeIntervalSince(wanted.start), 0, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(found.end.timeIntervalSince(wanted.end), 0, accuracy: accuracy, file: file, line: line)
        }
    }

    // MARK: Interval subtraction

    private func interval(_ start: Double, _ end: Double) -> DateInterval {
        DateInterval(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }

    func testSubtractingNothingKeepsTheBase() {
        let base = [interval(0, 100), interval(200, 300)]
        XCTAssertEqual(TonightHorizon.subtracting([], from: base), base)
    }

    func testSubtractingFromNothingGivesNothing() {
        XCTAssertEqual(TonightHorizon.subtracting([interval(0, 10)], from: []), [])
    }

    func testACutInTheMiddleSplitsAnInterval() {
        XCTAssertEqual(TonightHorizon.subtracting([interval(30, 60)], from: [interval(0, 100)]),
                       [interval(0, 30), interval(60, 100)])
    }

    func testACutAcrossTheStartTrimsTheStart() {
        XCTAssertEqual(TonightHorizon.subtracting([interval(-10, 20)], from: [interval(0, 100)]), [interval(20, 100)])
    }

    func testACutAcrossTheEndTrimsTheEnd() {
        XCTAssertEqual(TonightHorizon.subtracting([interval(80, 120)], from: [interval(0, 100)]), [interval(0, 80)])
    }

    func testACutThatCoversAnIntervalRemovesIt() {
        XCTAssertEqual(TonightHorizon.subtracting([interval(-5, 105)], from: [interval(0, 100)]), [])
        XCTAssertEqual(TonightHorizon.subtracting([interval(0, 100)], from: [interval(0, 100)]), [])
    }

    func testCutsOutsideOrOnlyTouchingAnIntervalChangeNothing() {
        let base = [interval(0, 100)]
        XCTAssertEqual(TonightHorizon.subtracting([interval(-50, -1)], from: base), base)
        XCTAssertEqual(TonightHorizon.subtracting([interval(101, 200)], from: base), base)
        // Touching at a single instant removes nothing.
        XCTAssertEqual(TonightHorizon.subtracting([interval(-50, 0)], from: base), base)
        XCTAssertEqual(TonightHorizon.subtracting([interval(100, 200)], from: base), base)
    }

    func testSeveralCutsAreAppliedInTimeOrderWhateverTheOrderGiven() {
        let result = TonightHorizon.subtracting([interval(40, 50), interval(10, 20)], from: [interval(0, 100)])
        XCTAssertEqual(result, [interval(0, 10), interval(20, 40), interval(50, 100)])
    }

    func testACutCanSpanTwoIntervalsOfTheBase() {
        let result = TonightHorizon.subtracting([interval(40, 70)], from: [interval(0, 50), interval(60, 100)])
        XCTAssertEqual(result, [interval(0, 40), interval(70, 100)])
    }

    func testEveryIntervalOfTheBaseIsCutByTheSameCut() {
        let result = TonightHorizon.subtracting([interval(5, 15)], from: [interval(0, 10), interval(10, 20)])
        XCTAssertEqual(result, [interval(0, 5), interval(15, 20)])
    }

    // MARK: Which skyline counts

    func testNoRecordedSkylineMeansAnOpenHorizon() throws {
        XCTAssertNil(TonightHorizon.skyline(of: try context(horizon: nil)))
    }

    func testAFlatSkylineCountsAsNone() throws {
        XCTAssertNil(TonightHorizon.skyline(of: try context(horizon: HorizonProfile.flat)))
        XCTAssertNil(TonightHorizon.skyline(of: try context(horizon: HorizonProfile.constant(0))))
    }

    func testARaisedSkylineIsReturnedAsRecorded() throws {
        let profile = HorizonProfile.constant(12)
        XCTAssertEqual(TonightHorizon.skyline(of: try context(horizon: profile)), profile)
    }

    func testASkylineWithOneHighBinIsNotFlat() throws {
        var altitudes = [Double](repeating: 0, count: HorizonProfile.binCount)
        altitudes[90] = 5
        let profile = try XCTUnwrap(HorizonProfile(altitudes: altitudes))
        XCTAssertEqual(TonightHorizon.skyline(of: try context(horizon: profile)), profile)
    }

    func testASkylineBelowTheHorizonIsNotFlatEither() throws {
        let profile = HorizonProfile.constant(-3)
        XCTAssertEqual(TonightHorizon.skyline(of: try context(horizon: profile)), profile)
    }

    func testTheGalacticCentreIsSagittariusAStar() {
        XCTAssertEqual(TonightHorizon.galacticCentre.rightAscensionHours, 17.761122, accuracy: 1e-5)
        XCTAssertEqual(TonightHorizon.galacticCentre.declination, -29.007806, accuracy: 1e-5)
    }

    // MARK: A skyline the Moon and the planets never clear

    /// Tromsø on 21 December 2026: the Moon never sets over a flat horizon, but it climbs no higher than about 49 degrees,
    /// so a 60 degree wall all round hides it, the planets and the core for the whole night.
    func testAWallHigherThanTheMoonCanClimbLeavesTheWholeNightDark() throws {
        let flat = try flatSummary(tromso, "Europe/Oslo", 2026, 12, 21)
        XCTAssertEqual(flat.moon.riseTransitSet.circumstance, .alwaysUp)
        XCTAssertTrue(flat.darknessIntervals.isEmpty)

        let applied = TonightHorizon.summary(flat, applying: HorizonProfile.constant(60))

        XCTAssertEqual(applied.moon.upIntervals, [])
        XCTAssertEqual(applied.moon.riseTransitSet.circumstance, .alwaysDown)
        XCTAssertNil(applied.moon.riseTransitSet.rise)
        XCTAssertNil(applied.moon.riseTransitSet.set)
        // With no Moon, all the astronomical darkness is moon-free.
        XCTAssertEqual(applied.darknessIntervals, flat.astronomicalDarknessIntervals)
        XCTAssertEqual(applied.moonFreeDarkHours, applied.astronomicalDarkHours, accuracy: 1e-9)
        XCTAssertEqual(applied.moonFreeDarkHours, 13.55, accuracy: 0.05)
    }

    func testTheWallHidesTheCoreAndLeavesNoBestTime() throws {
        let flat = try flatSummary(tromso, "Europe/Oslo", 2026, 12, 21)
        let core = TonightHorizon.summary(flat, applying: HorizonProfile.constant(60)).milkyWayCore
        XCTAssertTrue(core.visibleIntervals.isEmpty)
        XCTAssertTrue(core.moonFreeVisibleIntervals.isEmpty)
        XCTAssertNil(core.bestTime)
        XCTAssertNil(core.maxAltitude)
        XCTAssertNil(core.bestAzimuth)
    }

    func testPlanetsBehindTheWallAreNotUsableButKeepTheirOpenHorizonFigures() throws {
        let flat = try flatSummary(tromso, "Europe/Oslo", 2026, 12, 21)
        let applied = TonightHorizon.summary(flat, applying: HorizonProfile.constant(60))
        XCTAssertEqual(applied.planets.count, flat.planets.count)
        XCTAssertFalse(applied.planets.isEmpty)
        for (planet, open) in zip(applied.planets, flat.planets) {
            let label = planet.body.displayName
            XCTAssertEqual(planet.body, open.body, label)
            XCTAssertTrue(planet.visibleIntervals.isEmpty, label)
            XCTAssertFalse(planet.visibleDuringDarkness, label)
            // A planet that is not usable keeps the altitude it reaches over an open horizon, and its brightness.
            XCTAssertEqual(planet.maxAltitudeDuringDarkness, open.maxAltitudeDuringDarkness, label)
            XCTAssertEqual(planet.magnitude, open.magnitude, label)
        }
    }

    func testTheRestOfTheSummaryIsPassedThroughUnchanged() throws {
        let flat = try flatSummary(tromso, "Europe/Oslo", 2026, 12, 21)
        let applied = TonightHorizon.summary(flat, applying: HorizonProfile.constant(60))
        XCTAssertEqual(applied.observer, flat.observer)
        XCTAssertEqual(applied.night, flat.night)
        XCTAssertEqual(applied.twilight, flat.twilight)
        XCTAssertEqual(applied.referenceDate, flat.referenceDate)
        XCTAssertEqual(applied.moon.phase, flat.moon.phase)
        XCTAssertEqual(applied.astronomicalDarknessIntervals, flat.astronomicalDarknessIntervals)
        XCTAssertEqual(applied.planets.map(\.body), flat.planets.map(\.body))
    }

    // MARK: A skyline that costs the Moon some hours

    /// Boulder on the night of the 25 October 2026 full Moon: the Moon is up from sunset to after dawn over a flat horizon.
    func testASkylineShortensTheMoonsTimeUpAndNeverLengthensIt() throws {
        let flat = try flatSummary(boulder, "America/Denver", 2026, 10, 25)
        let applied = TonightHorizon.summary(flat, applying: HorizonProfile.constant(30))
        XCTAssertFalse(flat.moon.upIntervals.isEmpty)
        XCTAssertFalse(applied.moon.upIntervals.isEmpty, "the full Moon climbs well above 30 degrees")
        XCTAssertLessThan(total(applied.moon.upIntervals), total(flat.moon.upIntervals) - 3_600)
        // Every stretch over the skyline lies inside a stretch over the open horizon.
        for stretch in applied.moon.upIntervals {
            XCTAssertTrue(flat.moon.upIntervals.contains { $0.start.addingTimeInterval(-5) <= stretch.start
                                                           && stretch.end <= $0.end.addingTimeInterval(5) },
                          "\(stretch)")
        }
    }

    func testTheHoursWithoutTheMoonGrowWhenTheSkylineHidesIt() throws {
        let flat = try flatSummary(boulder, "America/Denver", 2026, 10, 25)
        let applied = TonightHorizon.summary(flat, applying: HorizonProfile.constant(30))
        XCTAssertGreaterThanOrEqual(applied.moonFreeDarkHours, flat.moonFreeDarkHours)
        // The dark hours are still inside the astronomical night, and exactly what the Moon leaves of it.
        let remaining = TonightHorizon.subtracting(applied.moon.upIntervals, from: flat.astronomicalDarknessIntervals)
        XCTAssertEqual(applied.darknessIntervals, remaining)
    }

    func testTheCoreNeverReachesAWallAboveItsHighestPoint() throws {
        // At 40 degrees north the Galactic Centre (declination -29) peaks near 21 degrees.
        let flat = try flatSummary(boulder, "America/Denver", 2026, 6, 21)
        let core = TonightHorizon.summary(flat, applying: HorizonProfile.constant(30)).milkyWayCore
        XCTAssertTrue(core.visibleIntervals.isEmpty)
        XCTAssertTrue(core.moonFreeVisibleIntervals.isEmpty)
        XCTAssertNil(core.bestTime)
        XCTAssertNil(core.maxAltitude)
        XCTAssertNil(core.bestAzimuth)
    }

    func testAPlanetOverASkylineIsUsableOnlyWhereItIsAboveTheSkyline() throws {
        let flat = try flatSummary(boulder, "America/Denver", 2026, 10, 25)
        let applied = TonightHorizon.summary(flat, applying: HorizonProfile.constant(30))
        XCTAssertEqual(applied.planets.map(\.body), flat.planets.map(\.body))
        for (planet, open) in zip(applied.planets, flat.planets) {
            XCTAssertLessThanOrEqual(total(planet.visibleIntervals), total(open.visibleIntervals) + 60,
                                     planet.body.displayName)
            XCTAssertEqual(planet.magnitude, open.magnitude, planet.body.displayName)
        }
    }

    // MARK: A low skyline the core and the planets clear

    /// A 5 degree skyline is below the 10 degree minimum that the core and the planets must reach, so it changes
    /// nothing for them.
    func testACoreAboveALowSkylineHasABestTimeAltitudeAndAzimuth() throws {
        // Boulder on 21 June 2026: the core is up for most of the night and the Moon sets at 00:58 MDT, about when it transits.
        let flat = try flatSummary(boulder, "America/Denver", 2026, 6, 21)
        let core = TonightHorizon.summary(flat, applying: HorizonProfile.constant(5)).milkyWayCore
        XCTAssertFalse(flat.milkyWayCore.visibleIntervals.isEmpty)
        assertSameIntervals(core.visibleIntervals, flat.milkyWayCore.visibleIntervals, accuracy: 5)
        assertSameIntervals(core.moonFreeVisibleIntervals, flat.milkyWayCore.moonFreeVisibleIntervals, accuracy: 5)
        XCTAssertFalse(core.moonFreeVisibleIntervals.isEmpty, "the core is still up after the Moon has set")
        // The best moment is the highest one in the Moon-free window.
        let best = try XCTUnwrap(core.bestTime)
        XCTAssertTrue(core.moonFreeVisibleIntervals.contains { $0.start <= best && best <= $0.end })
        let altitude = try XCTUnwrap(core.maxAltitude)
        XCTAssertGreaterThanOrEqual(altitude, 10)
        XCTAssertLessThanOrEqual(altitude, 21.5, "the Galactic Centre never gets higher than 21 degrees at 40 degrees north")
        let azimuth = try XCTUnwrap(core.bestAzimuth)
        XCTAssertGreaterThan(azimuth, 150)
        XCTAssertLessThan(azimuth, 230)
        // The Moon-free stretches are parts of the visible ones.
        XCTAssertGreaterThanOrEqual(total(core.visibleIntervals), total(core.moonFreeVisibleIntervals))
    }

    func testAPlanetAboveALowSkylineIsUsableAsOnAnOpenHorizon() throws {
        // Boulder on 25 October 2026: Saturn, just past opposition, is up all night, and Jupiter climbs before dawn.
        let flat = try flatSummary(boulder, "America/Denver", 2026, 10, 25)
        let applied = TonightHorizon.summary(flat, applying: HorizonProfile.constant(5))
        let seen = zip(applied.planets, flat.planets).filter { $0.1.visibleDuringDarkness }
        XCTAssertFalse(seen.isEmpty, "some planet is above 10 degrees during the dark hours")
        for (planet, open) in seen {
            let label = planet.body.displayName
            XCTAssertTrue(planet.visibleDuringDarkness, label)
            assertSameIntervals(planet.visibleIntervals, open.visibleIntervals, accuracy: 5)
            XCTAssertEqual(try XCTUnwrap(planet.maxAltitudeDuringDarkness),
                           try XCTUnwrap(open.maxAltitudeDuringDarkness), accuracy: 0.1, label)
        }
    }

    // MARK: A flat profile

    func testAFlatProfileGivesTheMoonOfTheOpenHorizon() throws {
        // 21 June 2026: the Moon sets at 00:58 MDT, so the last 2.5 hours before dawn are moon-free.
        let flat = try flatSummary(boulder, "America/Denver", 2026, 6, 21)
        let applied = TonightHorizon.summary(flat, applying: HorizonProfile.flat)
        XCTAssertFalse(flat.darknessIntervals.isEmpty)
        assertSameIntervals(applied.moon.upIntervals, flat.moon.upIntervals, accuracy: 5)
        assertSameIntervals(applied.darknessIntervals, flat.darknessIntervals, accuracy: 10)
    }
}
