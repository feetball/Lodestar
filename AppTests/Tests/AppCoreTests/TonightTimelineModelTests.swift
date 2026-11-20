import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The darkness timeline of one night (`TonightTimelineModel`) and the sky levels it draws (`TonightSkyLevel`).
final class TonightTimelineModelTests: XCTestCase {
    private let boulder = Observer(location: GeographicLocation(latitude: 40.0, longitude: -105.27, elevation: 1650))
    private let tromso = Observer(location: GeographicLocation(latitude: 69.65, longitude: 18.96, elevation: 0))
    private let pole = Observer(location: GeographicLocation(latitude: 89.9, longitude: 0, elevation: 0))

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier), identifier)
    }

    private func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try zone(identifier)
        return calendar
    }

    private func summary(_ observer: Observer, _ identifier: String, _ year: Int, _ month: Int, _ day: Int) throws
        -> NightSummary {
        let timeZone = try zone(identifier)
        let noon = try XCTUnwrap(try calendar(identifier).date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        return NightPlanner.summary(nightStartingOn: noon, observer: observer, timeZone: timeZone)
    }

    /// `base` with some of its stretches and its twilight replaced.
    private func replacing(_ base: NightSummary, twilight: NightTwilight? = nil, moonUp: [DateInterval]? = nil,
                           dark: [DateInterval]? = nil, coreVisible: [DateInterval]? = nil,
                           coreMoonFree: [DateInterval]? = nil) -> NightSummary {
        let moon = MoonSummary(phase: base.moon.phase, riseTransitSet: base.moon.riseTransitSet,
                               upIntervals: moonUp ?? base.moon.upIntervals)
        let core = MilkyWayCoreVisibility(
            riseTransitSet: base.milkyWayCore.riseTransitSet,
            visibleIntervals: coreVisible ?? base.milkyWayCore.visibleIntervals,
            moonFreeVisibleIntervals: coreMoonFree ?? base.milkyWayCore.moonFreeVisibleIntervals,
            bestTime: nil, maxAltitude: nil, bestAzimuth: nil)
        return NightSummary(observer: base.observer, night: base.night, twilight: twilight ?? base.twilight,
                            referenceDate: base.referenceDate, moon: moon,
                            astronomicalDarknessIntervals: base.astronomicalDarknessIntervals,
                            darknessIntervals: dark ?? base.darknessIntervals, milkyWayCore: core, planets: base.planets)
    }

    private func twilight(like base: NightTwilight, sunset: Date? = nil, civilDusk: Date? = nil,
                          nauticalDusk: Date? = nil, astronomicalDusk: Date? = nil, astronomicalDawn: Date? = nil,
                          nauticalDawn: Date? = nil, civilDawn: Date? = nil, sunrise: Date? = nil) -> NightTwilight {
        NightTwilight(sunset: sunset, civilDusk: civilDusk, nauticalDusk: nauticalDusk, astronomicalDusk: astronomicalDusk,
                      astronomicalDawn: astronomicalDawn, nauticalDawn: nauticalDawn, civilDawn: civilDawn,
                      sunrise: sunrise, interval: base.interval, solarMidnight: base.solarMidnight,
                      sunAltitudeAtMidnight: base.sunAltitudeAtMidnight)
    }

    // MARK: Sky levels

    func testSkyLevelsRunFromFullNightToDay() {
        XCTAssertEqual(TonightSkyLevel.allCases, [.night, .astronomical, .nautical, .civil, .day])
        XCTAssertEqual(TonightSkyLevel.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
    }

    func testSkyLevelOfTheSunsAltitudeAtTheTwilightLimits() {
        XCTAssertEqual(TonightSkyLevel(sunAltitude: -90), .night)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: TwilightCalculator.astronomicalAltitude), .night)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: TwilightCalculator.astronomicalAltitude + 0.001), .astronomical)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: TwilightCalculator.nauticalAltitude), .astronomical)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: TwilightCalculator.nauticalAltitude + 0.001), .nautical)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: TwilightCalculator.civilAltitude), .nautical)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: TwilightCalculator.civilAltitude + 0.001), .civil)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: RiseSetCalculator.sunHorizonAltitude), .civil)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: RiseSetCalculator.sunHorizonAltitude + 0.001), .day)
        XCTAssertEqual(TonightSkyLevel(sunAltitude: 60), .day)
    }

    func testSkyLevelTitles() {
        XCTAssertEqual(TonightSkyLevel.allCases.map(\.title), ["Night", "Astronomical", "Nautical", "Civil", "Day"])
    }

    func testTheBrighterTheSkyTheMoreTheTimelineFillsIt() {
        XCTAssertEqual(TonightSkyLevel.night.fillOpacity, 0)
        XCTAssertEqual(TonightSkyLevel.astronomical.fillOpacity, 0.16, accuracy: 1e-12)
        XCTAssertEqual(TonightSkyLevel.nautical.fillOpacity, 0.36, accuracy: 1e-12)
        XCTAssertEqual(TonightSkyLevel.civil.fillOpacity, 0.6, accuracy: 1e-12)
        XCTAssertEqual(TonightSkyLevel.day.fillOpacity, 0.9, accuracy: 1e-12)
        let opacities = TonightSkyLevel.allCases.map(\.fillOpacity)
        XCTAssertEqual(opacities, opacities.sorted())
    }

    // MARK: Label spacing

    func testLabelSpacingPicksTheSmallestStepThatKeepsTheGap() {
        // Every hour when 50 points are enough for a 40 point label and a 6 point gap.
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 50, labelWidth: 40, gap: 6), 1)
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 30, labelWidth: 40, gap: 6), 2)
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 20, labelWidth: 40, gap: 6), 3)
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 12, labelWidth: 40, gap: 6), 4)
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 8, labelWidth: 40, gap: 6), 6)
    }

    func testLabelSpacingAcceptsAnExactFitButNotLess() {
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 46, labelWidth: 40, gap: 6), 1)
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 45.9, labelWidth: 40, gap: 6), 2)
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 23, labelWidth: 40, gap: 6), 2)
    }

    func testLabelSpacingFallsBackToEveryTwelfthHour() {
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 7, labelWidth: 40, gap: 6), 12)
        XCTAssertEqual(TonightTimelineModel.labelSpacing(pointsPerHour: 0, labelWidth: 40, gap: 6), 12)
    }

    // MARK: An ordinary night

    func testTheRangeRunsFromSunsetToSunrise() throws {
        let night = try summary(boulder, "America/Denver", 2026, 10, 10)
        let model = TonightTimelineModel(summary: night, timeZone: try zone("America/Denver"))
        XCTAssertEqual(model.range.start, night.twilight.sunset)
        XCTAssertEqual(model.range.end, night.twilight.sunrise)
        XCTAssertGreaterThan(model.range.duration, 10 * 3600)
        XCTAssertLessThan(model.range.duration, 14 * 3600)
    }

    func testTheBandsStepThroughEveryTwilightAndBack() throws {
        let night = try summary(boulder, "America/Denver", 2026, 10, 10)
        let model = TonightTimelineModel(summary: night, timeZone: try zone("America/Denver"))
        XCTAssertEqual(model.bands.map(\.level), [.civil, .nautical, .astronomical, .night, .astronomical, .nautical, .civil])
        let twilight = night.twilight
        let edges: [Date] = [twilight.sunset, twilight.civilDusk, twilight.nauticalDusk, twilight.astronomicalDusk,
                             twilight.astronomicalDawn, twilight.nauticalDawn, twilight.civilDawn, twilight.sunrise]
            .compactMap { $0 }
        XCTAssertEqual(edges.count, 8)
        XCTAssertEqual(model.bands.map(\.interval.start), Array(edges.dropLast()))
        XCTAssertEqual(model.bands.map(\.interval.end), Array(edges.dropFirst()))
    }

    func testTheBandsCoverTheRangeWithoutGaps() throws {
        let night = try summary(boulder, "America/Denver", 2026, 10, 10)
        let model = TonightTimelineModel(summary: night, timeZone: try zone("America/Denver"))
        XCTAssertEqual(model.bands.first?.interval.start, model.range.start)
        XCTAssertEqual(model.bands.last?.interval.end, model.range.end)
        for (earlier, later) in zip(model.bands, model.bands.dropFirst()) {
            XCTAssertEqual(earlier.interval.end, later.interval.start)
            XCTAssertNotEqual(earlier.level, later.level)
        }
    }

    func testTheHourTicksAreTheWholeHoursInsideTheRange() throws {
        let night = try summary(boulder, "America/Denver", 2026, 10, 10)
        let denver = try calendar("America/Denver")
        let model = TonightTimelineModel(summary: night, timeZone: denver.timeZone)
        let ticks = model.hourTicks
        let first = try XCTUnwrap(ticks.first)
        let last = try XCTUnwrap(ticks.last)
        XCTAssertGreaterThan(first.date, model.range.start)
        XCTAssertLessThanOrEqual(first.date.timeIntervalSince(model.range.start), 3600)
        XCTAssertLessThan(last.date, model.range.end)
        XCTAssertLessThanOrEqual(model.range.end.timeIntervalSince(last.date), 3600)
        for tick in ticks {
            let parts = denver.dateComponents([.hour, .minute, .second], from: tick.date)
            XCTAssertEqual(parts.hour, tick.hour)
            XCTAssertEqual(parts.minute, 0)
            XCTAssertEqual(parts.second, 0)
        }
        for (earlier, later) in zip(ticks, ticks.dropFirst()) {
            XCTAssertEqual(later.date.timeIntervalSince(earlier.date), 3600, accuracy: 0.001)
            XCTAssertEqual((earlier.hour + 1) % 24, later.hour)
        }
        // Sunset is in the early evening and sunrise in the morning, so the ticks run through midnight.
        XCTAssertTrue(ticks.contains { $0.hour == 0 })
        XCTAssertTrue(first.hour >= 17 && first.hour <= 20, "first tick at \(first.hour)")
    }

    func testTheHourTicksFollowTheGivenTimeZoneEvenIfItIsOffsetByHalfAnHour() throws {
        let night = try summary(boulder, "America/Denver", 2026, 10, 10)
        let kolkata = try calendar("Asia/Kolkata")
        let model = TonightTimelineModel(summary: night, timeZone: kolkata.timeZone)
        let utc = try calendar("UTC")
        XCTAssertFalse(model.hourTicks.isEmpty)
        for tick in model.hourTicks {
            XCTAssertEqual(kolkata.component(.hour, from: tick.date), tick.hour)
            XCTAssertEqual(kolkata.component(.minute, from: tick.date), 0)
            XCTAssertEqual(utc.component(.minute, from: tick.date), 30)
        }
    }

    func testTheMoonAndDarkStretchesStayInsideTheRange() throws {
        let night = try summary(boulder, "America/Denver", 2026, 6, 21)
        let model = TonightTimelineModel(summary: night, timeZone: try zone("America/Denver"))
        XCTAssertFalse(model.dark.isEmpty)
        for stretch in model.moonUp + model.dark + model.coreVisible + model.coreMoonFree {
            XCTAssertGreaterThanOrEqual(stretch.start, model.range.start)
            XCTAssertLessThanOrEqual(stretch.end, model.range.end)
            XCTAssertGreaterThan(stretch.duration, 0)
        }
        // The dark stretches are the moon-free ones, not the whole astronomical night.
        XCTAssertEqual(model.dark, night.darknessIntervals)
    }

    func testAPermutedTwilightGivesTheSameBands() throws {
        // The events are sorted before the bands are cut, so the field they are stored in does not matter.
        let night = try summary(boulder, "America/Denver", 2026, 10, 10)
        let real = night.twilight
        let swapped = twilight(like: real, sunset: real.sunset, civilDusk: real.civilDawn,
                               nauticalDusk: real.nauticalDawn, astronomicalDusk: real.astronomicalDawn,
                               astronomicalDawn: real.astronomicalDusk, nauticalDawn: real.nauticalDusk,
                               civilDawn: real.civilDusk, sunrise: real.sunrise)
        let denver = try zone("America/Denver")
        let expected = TonightTimelineModel(summary: night, timeZone: denver)
        let found = TonightTimelineModel(summary: replacing(night, twilight: swapped), timeZone: denver)
        XCTAssertEqual(found.bands.map(\.level), expected.bands.map(\.level))
        XCTAssertEqual(found.bands.map(\.interval), expected.bands.map(\.interval))
    }

    // MARK: The Sun that does not set or does not rise

    func testInThePolarNightTheWholeWindowIsOneNightBand() throws {
        let night = try summary(pole, "UTC", 2026, 12, 21)
        let model = TonightTimelineModel(summary: night, timeZone: try zone("UTC"))
        XCTAssertEqual(model.range, night.night)
        XCTAssertEqual(model.bands.count, 1)
        XCTAssertEqual(model.bands.first?.level, .night)
        XCTAssertEqual(model.bands.first?.interval, night.night)
    }

    func testThePolarNightHasAnHourTickForEveryHourExceptTheEdges() throws {
        let night = try summary(pole, "UTC", 2026, 12, 21)
        let model = TonightTimelineModel(summary: night, timeZone: try zone("UTC"))
        // From 12:00 to 12:00 the next day: ticks at 13:00 ... 23:00 and 00:00 ... 11:00.
        XCTAssertEqual(model.hourTicks.map(\.hour), Array(13...23) + Array(0...11))
    }

    func testInTheMidnightSunTheWholeWindowIsOneDayBand() throws {
        let night = try summary(tromso, "Europe/Oslo", 2026, 6, 21)
        XCTAssertNil(night.twilight.sunset)
        let model = TonightTimelineModel(summary: night, timeZone: try zone("Europe/Oslo"))
        XCTAssertEqual(model.range, night.night)
        XCTAssertEqual(model.bands.count, 1)
        XCTAssertEqual(model.bands.first?.level, .day)
        XCTAssertEqual(model.hourTicks.count, 23)
    }

    // MARK: Bands and stretches built from chosen events

    func testNeighbouringStretchesAtTheSameLevelMergeIntoOneBand() throws {
        let base = try summary(pole, "UTC", 2026, 12, 21)
        let middle = base.night.start.addingTimeInterval(base.night.duration / 2)
        let cut = twilight(like: base.twilight, civilDusk: middle)
        let model = TonightTimelineModel(summary: replacing(base, twilight: cut), timeZone: try zone("UTC"))
        XCTAssertEqual(model.bands.count, 1)
        XCTAssertEqual(model.bands.first?.interval, base.night)
    }

    func testEventsOnOrOutsideTheEdgesOfTheRangeCutNothing() throws {
        let base = try summary(pole, "UTC", 2026, 12, 21)
        let cut = twilight(like: base.twilight, civilDusk: base.night.start, nauticalDusk: base.night.end,
                           astronomicalDusk: base.night.start.addingTimeInterval(-3600),
                           astronomicalDawn: base.night.end.addingTimeInterval(3600))
        let model = TonightTimelineModel(summary: replacing(base, twilight: cut), timeZone: try zone("UTC"))
        XCTAssertEqual(model.bands.count, 1)
        XCTAssertEqual(model.bands.first?.level, .night)
        XCTAssertEqual(model.bands.first?.interval, base.night)
    }

    func testStretchesAreClippedToTheRangeAndEmptyOnesDropped() throws {
        let base = try summary(pole, "UTC", 2026, 12, 21)
        let start = base.night.start, end = base.night.end
        func at(_ offset: TimeInterval, from origin: Date) -> Date { origin.addingTimeInterval(offset) }

        let moon = [
            DateInterval(start: at(-5000, from: start), end: at(-4000, from: start)), // before the range
            DateInterval(start: at(-7200, from: start), end: start), // ends exactly where the range starts
            DateInterval(start: at(-7200, from: start), end: at(3600, from: start)), // starts before
            DateInterval(start: at(1000, from: start), end: at(2000, from: start)), // inside
            DateInterval(start: at(-600, from: end), end: at(600, from: end)), // ends after
            DateInterval(start: end, end: at(100, from: end)), // starts exactly where the range ends
        ]
        let model = TonightTimelineModel(summary: replacing(base, moonUp: moon), timeZone: try zone("UTC"))
        XCTAssertEqual(model.moonUp, [
            DateInterval(start: start, end: at(3600, from: start)),
            DateInterval(start: at(1000, from: start), end: at(2000, from: start)),
            DateInterval(start: at(-600, from: end), end: end),
        ])
    }

    func testAStretchThatCoversTheWholeRangeIsKeptWhole() throws {
        let base = try summary(pole, "UTC", 2026, 12, 21)
        let wide = DateInterval(start: base.night.start.addingTimeInterval(-86_400),
                                end: base.night.end.addingTimeInterval(86_400))
        let model = TonightTimelineModel(summary: replacing(base, moonUp: [wide]), timeZone: try zone("UTC"))
        XCTAssertEqual(model.moonUp, [base.night])
    }

    func testEachStretchComesFromItsOwnSourceInTheSummary() throws {
        let base = try summary(pole, "UTC", 2026, 12, 21)
        let start = base.night.start
        func hour(_ from: Double, _ to: Double) -> DateInterval {
            DateInterval(start: start.addingTimeInterval(from * 3600), end: start.addingTimeInterval(to * 3600))
        }
        let edited = replacing(base, moonUp: [hour(1, 2)], dark: [hour(3, 4)], coreVisible: [hour(5, 6)],
                               coreMoonFree: [hour(7, 8)])
        let model = TonightTimelineModel(summary: edited, timeZone: try zone("UTC"))
        XCTAssertEqual(model.moonUp, [hour(1, 2)])
        XCTAssertEqual(model.dark, [hour(3, 4)])
        XCTAssertEqual(model.coreVisible, [hour(5, 6)])
        XCTAssertEqual(model.coreMoonFree, [hour(7, 8)])
    }

    // MARK: An empty range

    func testSunriseAtSunsetLeavesAnEmptyTimeline() throws {
        let base = try summary(boulder, "America/Denver", 2026, 10, 10)
        let moment = base.night.start.addingTimeInterval(6 * 3600)
        let flat = twilight(like: base.twilight, sunset: moment, sunrise: moment)
        let everything = [DateInterval(start: base.night.start, end: base.night.end)]
        let model = TonightTimelineModel(
            summary: replacing(base, twilight: flat, moonUp: everything, dark: everything, coreVisible: everything,
                               coreMoonFree: everything),
            timeZone: try zone("America/Denver"))
        XCTAssertEqual(model.range.start, moment)
        XCTAssertEqual(model.range.duration, 0)
        XCTAssertTrue(model.bands.isEmpty)
        XCTAssertTrue(model.hourTicks.isEmpty)
        XCTAssertTrue(model.moonUp.isEmpty)
        XCTAssertTrue(model.dark.isEmpty)
        XCTAssertTrue(model.coreVisible.isEmpty)
        XCTAssertTrue(model.coreMoonFree.isEmpty)
    }

    func testASunriseBeforeSunsetIsTreatedAsAnEmptyRangeAtSunset() throws {
        let base = try summary(boulder, "America/Denver", 2026, 10, 10)
        let sunset = base.night.start.addingTimeInterval(6 * 3600)
        let backwards = twilight(like: base.twilight, sunset: sunset, sunrise: sunset.addingTimeInterval(-3600))
        let model = TonightTimelineModel(summary: replacing(base, twilight: backwards),
                                         timeZone: try zone("America/Denver"))
        XCTAssertEqual(model.range, DateInterval(start: sunset, end: sunset))
        XCTAssertTrue(model.bands.isEmpty)
        XCTAssertTrue(model.hourTicks.isEmpty)
    }
}
