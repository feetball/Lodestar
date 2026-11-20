import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The words of the satellite features (`SatelliteText`), the list filter (`SatellitePassFilter`) and the identity of
/// one pass (`SatellitePassItem`).
///
/// Clock times follow the user's 12/24-hour setting, so the expected text of a time is built from `AppFormat.time` or
/// from `SatelliteText.timeWithSeconds` and the tests check how the pieces are joined.
final class TonightSatelliteTextTests: XCTestCase {
    private let dot = "\u{00B7}"
    private let utc = TimeZone(identifier: "UTC") ?? .gmt

    /// Skips the test where numbers are not written like "0.62" (the code formats them with the user's locale).
    private func requirePointDecimals() throws {
        try XCTSkipUnless(3.4.formatted(.number.precision(.fractionLength(1))) == "3.4",
                          "numbers are not written with a decimal point in this locale")
    }

    private func instant(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: iso), iso)
    }

    private func issSatellite() throws -> Satellite {
        let elements = try ElementSetParser.parseTwoLine(
            line1: "1 25544U 98067A   26291.14461894  .00007503  00000+0  14456-3 0  9994",
            line2: "2 25544  51.6328  51.6259 0006780 277.7856  82.2363 15.48918166590814", name: "ISS (ZARYA)")
        return Satellite(elements: elements)
    }

    /// A satellite with the elements of a low-orbit station under another catalog number and name.
    private func satellite(number: Int, name: String?) throws -> Satellite {
        let elements = try OrbitalElements(
            name: name, catalogNumber: number, epoch: Date(timeIntervalSince1970: 1_792_294_095), meanMotion: 15.5,
            eccentricity: 0.001, inclination: 51.6, rightAscensionOfAscendingNode: 50, argumentOfPericenter: 100,
            meanAnomaly: 10)
        return Satellite(elements: elements)
    }

    private func point(_ seconds: Double, azimuth: Double = 225, altitude: Double = 30,
                       magnitude: Double? = -3.2) -> SatellitePassPoint {
        SatellitePassPoint(date: Date(timeIntervalSince1970: seconds), azimuth: azimuth, altitude: altitude,
                           rangeKilometers: 600, isSunlit: true, magnitude: magnitude)
    }

    /// A pass from `rise` to `set` (seconds since 1970) with the given visible parts and an optional brightest point.
    private func item(_ satellite: Satellite, group: ElementSetGroup = .stations, rise: Double = 1_000,
                      set: Double = 1_600, visible: [(Double, Double)] = [(1_100, 1_500)],
                      brightest: SatellitePassPoint? = nil, peak: SatellitePassPoint? = nil) -> SatellitePassItem {
        let culmination = point((rise + set) / 2, azimuth: 45, altitude: 67.4)
        let pass = SatellitePass(
            rise: point(rise, azimuth: 225, altitude: 10), culmination: culmination,
            set: point(set, azimuth: 0, altitude: 10),
            visibleIntervals: visible.map { DateInterval(start: Date(timeIntervalSince1970: $0.0),
                                                         end: Date(timeIntervalSince1970: $0.1)) },
            brightest: brightest, isRiseCut: false, isSetCut: false)
        return SatellitePassItem(satellite: satellite, group: group, pass: pass, peak: peak ?? culmination)
    }

    // MARK: Texts shared with the Android app

    func testTheTitlesAndNotesStayAsTheyAre() {
        XCTAssertEqual(SatelliteText.cardTitle, "Satellite passes")
        XCTAssertEqual(SatelliteText.allPasses, "All passes")
        XCTAssertEqual(SatelliteText.passesTitle, "Satellite Passes")
        XCTAssertEqual(SatelliteText.noPassesTonight, "No visible passes on this night.")
        XCTAssertEqual(SatelliteText.noPasses, "No visible passes in the next three days.")
        XCTAssertEqual(SatelliteText.nightOver, "This night is over.")
        XCTAssertEqual(SatelliteText.tooFar, "Passes can be predicted only three days ahead.")
        XCTAssertEqual(SatelliteText.staleTag, "orbit data too old")
        XCTAssertEqual(SatelliteText.stale,
                       "Orbit data is too old for exact times. Update it in Settings \u{25B8} Online Data.")
        XCTAssertEqual(SatelliteText.attribution, "Orbital data: CelesTrak, T. S. Kelso")
        XCTAssertEqual(SatelliteText.follow, "Follow in Aim")
        XCTAssertEqual(SatelliteText.wait, "Wait at the peak")
        XCTAssertEqual(SatelliteText.offTitle, "Satellite Passes Are Off")
        XCTAssertEqual(SatelliteText.streakStaleChip, "Starlink data too old")
        XCTAssertEqual(SatelliteText.streakSheetTitle, "Starlink crossings")
    }

    func testTheVisibilityNoteAndTheBelowHorizonLabelStayAsTheyAre() {
        XCTAssertEqual(SatelliteText.visibleOnly,
                       "Visible passes only: the satellite is lit by the Sun while the sky is dark, at least 10\u{00B0} up.")
        XCTAssertEqual(SatelliteText.rideAlongBelow, "Below the horizon")
    }

    // MARK: Filters

    func testThePassFilters() {
        XCTAssertEqual(SatellitePassFilter.allCases, [.iss, .bright])
        XCTAssertEqual(SatellitePassFilter.allCases.map(\.id), ["iss", "bright"])
        XCTAssertEqual(SatellitePassFilter.allCases.map(\.title), ["ISS", "Bright satellites"])
    }

    // MARK: One line of a pass

    func testTheSpanOfAPassJoinsTheTwoTimesWithAnEnDash() throws {
        let station = try issSatellite()
        let start = try instant("2026-10-18T21:34:00Z")
        let end = try instant("2026-10-18T21:39:00Z")
        let pass = item(station, visible: [(start.timeIntervalSince1970, end.timeIntervalSince1970)])
        XCTAssertEqual(SatelliteText.span(pass, in: utc), "\(AppFormat.time(start, in: utc)) \u{2013} \(AppFormat.time(end, in: utc))")
    }

    func testThePeakIsTheAltitudeAndTheCompassPoint() {
        XCTAssertEqual(SatelliteText.peak(point(0, azimuth: 45, altitude: 67.4)), "peak 67\u{00B0} NE")
        XCTAssertEqual(SatelliteText.peak(point(0, azimuth: 225, altitude: 10.4)), "peak 10\u{00B0} SW")
        XCTAssertEqual(SatelliteText.peak(point(0, azimuth: 359.9, altitude: 89.6)), "peak 90\u{00B0} N")
        XCTAssertEqual(SatelliteText.peak(point(0, azimuth: 180, altitude: 33.6)), "peak 34\u{00B0} S")
    }

    func testTheMagnitudeOfAPassIsItsBrightestPoint() throws {
        try requirePointDecimals()
        let station = try issSatellite()
        let bright = item(station, brightest: point(1_300, magnitude: -3.2))
        XCTAssertEqual(SatelliteText.magnitude(bright), "mag \u{2212}3.2")
        let faint = item(station, brightest: point(1_300, magnitude: 2.0))
        XCTAssertEqual(SatelliteText.magnitude(faint), "mag 2.0")
    }

    func testThePlaceholderIsShownWhenTheBrightnessIsUnknown() throws {
        let station = try issSatellite()
        XCTAssertEqual(SatelliteText.magnitude(item(station, brightest: nil)), AppFormat.missing)
        XCTAssertEqual(SatelliteText.magnitude(item(station, brightest: point(1_300, magnitude: nil))), AppFormat.missing)
    }

    // MARK: Durations and clocks

    func testDurationBelowAMinuteIsInSeconds() {
        XCTAssertEqual(SatelliteText.duration(0), "0 s")
        XCTAssertEqual(SatelliteText.duration(41.6), "42 s")
        XCTAssertEqual(SatelliteText.duration(59.4), "59 s")
    }

    func testDurationFromAMinuteUpIsInMinutesAndSeconds() {
        XCTAssertEqual(SatelliteText.duration(59.5), "1 min 0 s")
        XCTAssertEqual(SatelliteText.duration(60), "1 min 0 s")
        XCTAssertEqual(SatelliteText.duration(318), "5 min 18 s")
        XCTAssertEqual(SatelliteText.duration(3_600), "60 min 0 s")
    }

    func testANegativeDurationIsZero() {
        XCTAssertEqual(SatelliteText.duration(-5), "0 s")
        XCTAssertEqual(SatelliteText.duration(-0.4), "0 s")
    }

    func testClockHasMinutesAndSecondsAndHoursOnlyWhenNeeded() {
        XCTAssertEqual(SatelliteText.clock(0), "0:00")
        XCTAssertEqual(SatelliteText.clock(59), "0:59")
        XCTAssertEqual(SatelliteText.clock(161), "2:41")
        XCTAssertEqual(SatelliteText.clock(3_599), "59:59")
        XCTAssertEqual(SatelliteText.clock(3_600), "1:00:00")
        XCTAssertEqual(SatelliteText.clock(3_723), "1:02:03")
        XCTAssertEqual(SatelliteText.clock(36_000), "10:00:00")
    }

    func testATimeWithSecondsShowsMinutesAndSecondsInTheGivenZone() throws {
        let date = try instant("2026-10-18T21:34:12Z")
        XCTAssertTrue(SatelliteText.timeWithSeconds(date, in: utc).contains("34:12"))
        let denver = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        // Denver is six hours behind UTC in October, so the clock reads 15:34:12 (or 3:34:12 PM).
        XCTAssertTrue(SatelliteText.timeWithSeconds(date, in: denver).contains(":34:12"))
        XCTAssertNotEqual(SatelliteText.timeWithSeconds(date, in: denver), SatelliteText.timeWithSeconds(date, in: utc))
    }

    func testAPointOfAPassIsTimeAzimuthAndAltitude() throws {
        let date = try instant("2026-10-18T21:34:12Z")
        let place = SatellitePassPoint(date: date, azimuth: 225, altitude: 10.4, rangeKilometers: 900, isSunlit: true,
                                       magnitude: nil)
        XCTAssertEqual(SatelliteText.point(place, in: utc),
                       "\(SatelliteText.timeWithSeconds(date, in: utc)) \(dot) 225.0\u{00B0} SW \(dot) 10\u{00B0}")
    }

    // MARK: Spoken

    func testTheSpokenPathDescribesRiseCulminationAndSet() throws {
        let station = try issSatellite()
        let pass = item(station, visible: [])
        XCTAssertEqual(SatelliteText.spokenPath(pass, in: utc),
                       "Sky path of the ISS pass. It rises in the southwest, reaches 67 degrees in the northeast and "
                       + "sets in the north.")
    }

    func testTheSpokenPathAddsWhenThePassIsVisible() throws {
        let station = try issSatellite()
        let start = try instant("2026-10-18T21:34:00Z")
        let end = try instant("2026-10-18T21:39:00Z")
        let pass = item(station, rise: start.timeIntervalSince1970 - 60, set: end.timeIntervalSince1970 + 60,
                        visible: [(start.timeIntervalSince1970, end.timeIntervalSince1970)])
        XCTAssertEqual(SatelliteText.spokenPath(pass, in: utc),
                       "Sky path of the ISS pass. It rises in the southwest, reaches 67 degrees in the northeast and "
                       + "sets in the north. Visible from \(AppFormat.time(start, in: utc)) to \(AppFormat.time(end, in: utc)).")
    }

    func testTheSpokenPathNamesOtherSatellitesByTheirElementSet() throws {
        let other = item(try satellite(number: 90_001, name: "TEST SAT 1"), visible: [])
        XCTAssertTrue(SatelliteText.spokenPath(other, in: utc).hasPrefix("Sky path of the TEST SAT 1 pass."))
        let unnamed = item(try satellite(number: 90_002, name: nil), visible: [])
        XCTAssertTrue(SatelliteText.spokenPath(unnamed, in: utc).hasPrefix("Sky path of the NORAD 90002 pass."))
    }

    // MARK: Aim

    func testFollowInfoGivesRangeSpeedAndLight() throws {
        try requirePointDecimals()
        XCTAssertEqual(SatelliteText.followInfo(rangeKilometers: 612.4, angularSpeed: 0.623, isSunlit: true),
                       "Range 612 km \(dot) 0.62\u{00B0}/s \(dot) Sunlit")
        XCTAssertEqual(SatelliteText.followInfo(rangeKilometers: 899.6, angularSpeed: 1.0, isSunlit: false),
                       "Range 900 km \(dot) 1.00\u{00B0}/s \(dot) In Earth's shadow")
    }

    func testThePeakCountdown() {
        XCTAssertEqual(SatelliteText.peakCountdown(161), "Peak in 2:41")
        XCTAssertEqual(SatelliteText.peakCountdown(2), "Peak in 0:02")
        XCTAssertEqual(SatelliteText.peakCountdown(3_723), "Peak in 1:02:03")
        XCTAssertEqual(SatelliteText.peakCountdown(-42), "Peak passed 0:42 ago")
        XCTAssertEqual(SatelliteText.peakCountdown(-2), "Peak passed 0:02 ago")
    }

    func testTheSatelliteIsAtThePeakWithinTwoSeconds() {
        XCTAssertEqual(SatelliteText.peakCountdown(0), "At the peak now")
        XCTAssertEqual(SatelliteText.peakCountdown(1.99), "At the peak now")
        XCTAssertEqual(SatelliteText.peakCountdown(-1.99), "At the peak now")
    }

    func testTheCountdownOfAnUnknownTimeIsThePlaceholder() {
        XCTAssertEqual(SatelliteText.peakCountdown(.nan), AppFormat.missing)
        XCTAssertEqual(SatelliteText.peakCountdown(.infinity), AppFormat.missing)
    }

    func testTheNoteAboutAPassBeforeItBeginsSaysWhenItRises() {
        let rise = Date(timeIntervalSince1970: 10_000)
        let now = rise.addingTimeInterval(-720)
        let note = SatelliteText.passNote(now: now, rise: rise, set: rise.addingTimeInterval(300)) { _ in "T" }
        XCTAssertEqual(note, "Rises T (in 12m 00s)")
    }

    func testTheNoteAboutAPassAfterItEndsSaysSo() {
        let rise = Date(timeIntervalSince1970: 10_000)
        let set = rise.addingTimeInterval(300)
        XCTAssertEqual(SatelliteText.passNote(now: set.addingTimeInterval(1), rise: rise, set: set) { _ in "T" },
                       "The pass is over")
    }

    func testDuringAPassThereIsNoNote() {
        let rise = Date(timeIntervalSince1970: 10_000)
        let set = rise.addingTimeInterval(300)
        XCTAssertNil(SatelliteText.passNote(now: rise.addingTimeInterval(100), rise: rise, set: set) { _ in "T" })
        // At the very rise and at the very set the pass is under way.
        XCTAssertNil(SatelliteText.passNote(now: rise, rise: rise, set: set) { _ in "T" })
        XCTAssertNil(SatelliteText.passNote(now: set, rise: rise, set: set) { _ in "T" })
    }

    func testTheNoteUsesTheTextOfTheRiseTimeGivenByTheCaller() {
        let rise = Date(timeIntervalSince1970: 10_000)
        var asked: [Date] = []
        let note = SatelliteText.passNote(now: rise.addingTimeInterval(-60), rise: rise, set: rise.addingTimeInterval(300)) {
            asked.append($0)
            return "21:34"
        }
        XCTAssertEqual(note, "Rises 21:34 (in 1m 00s)")
        XCTAssertEqual(asked, [rise])
    }

    // MARK: Streak warning

    func testTheStreakChipCountsCrossingsAndShowsTheRisk() {
        XCTAssertEqual(SatelliteText.streakChip(crossings: 3, exposureSeconds: 30, risk: 0.12),
                       "Starlink: 3 crossings in 30 s \(dot) 12% streak risk")
        XCTAssertEqual(SatelliteText.streakChip(crossings: 1, exposureSeconds: 120, risk: 0.5),
                       "Starlink: 1 crossing in 120 s \(dot) 50% streak risk")
        XCTAssertEqual(SatelliteText.streakChip(crossings: 0, exposureSeconds: 30, risk: 0.08),
                       "Starlink: no crossings in 30 s \(dot) 8% streak risk")
    }

    func testTheStreakRiskIsKeptBetweenZeroAndAHundredPercent() {
        XCTAssertEqual(SatelliteText.streakChip(crossings: 2, exposureSeconds: 30, risk: 1.5),
                       "Starlink: 2 crossings in 30 s \(dot) 100% streak risk")
        XCTAssertEqual(SatelliteText.streakChip(crossings: 0, exposureSeconds: 30, risk: -0.2),
                       "Starlink: no crossings in 30 s \(dot) 0% streak risk")
    }

    func testTheStreakSummaryGivesTheNumbersBehindTheChip() throws {
        try requirePointDecimals()
        XCTAssertEqual(SatelliteText.streakSummary(exposureSeconds: 30, sunlitAbove20: 47, crossingsPerMinute: 0.8, risk: 0.12),
                       "47 sunlit satellites above 20\u{00B0} right now. About 0.8 crossings a minute in this frame; "
                       + "12% chance of a streak in a 30 s exposure.")
    }

    func testTheStreakSummarySaysOneSatelliteInTheSingular() throws {
        try requirePointDecimals()
        XCTAssertEqual(SatelliteText.streakSummary(exposureSeconds: 15, sunlitAbove20: 1, crossingsPerMinute: 0.04, risk: 1.4),
                       "1 sunlit satellite above 20\u{00B0} right now. About 0.0 crossings a minute in this frame; "
                       + "100% chance of a streak in a 15 s exposure.")
        XCTAssertTrue(SatelliteText.streakSummary(exposureSeconds: 15, sunlitAbove20: 0, crossingsPerMinute: 0,
                                                  risk: 0).hasPrefix("0 sunlit satellites above 20"))
    }

    func testACrossingLineHasTheTimesTheMagnitudeAndWhetherItWasAlreadyInFrame() throws {
        let station = try issSatellite()
        let enters = try instant("2026-10-18T21:34:12Z")
        let leaves = try instant("2026-10-18T21:34:19Z")
        func crossing(startsBefore: Bool, magnitude: Double?) -> SatelliteCrossing {
            SatelliteCrossing(
                satellite: station,
                entry: CrossingPoint(date: enters, azimuth: 200, altitude: 30, position: nil),
                exit: CrossingPoint(date: leaves, azimuth: 210, altitude: 40, position: nil),
                startsBeforeExposure: startsBefore, endsAfterExposure: false, magnitude: magnitude)
        }
        let times = "\(SatelliteText.timeWithSeconds(enters, in: utc)) \u{2013} \(SatelliteText.timeWithSeconds(leaves, in: utc))"
        XCTAssertEqual(SatelliteText.crossing(crossing(startsBefore: false, magnitude: nil), in: utc),
                       "\(times) \(dot) \(AppFormat.missing)")
        XCTAssertEqual(SatelliteText.crossing(crossing(startsBefore: true, magnitude: nil), in: utc),
                       "\(times) \(dot) \(AppFormat.missing) \(dot) already in frame")
        XCTAssertEqual(SatelliteText.crossing(crossing(startsBefore: false, magnitude: 3.0), in: utc),
                       "\(times) \(dot) \(AppFormat.magnitude(3.0))")
    }

    // MARK: A pass in a list

    func testThePassOfTheStationIsCalledISS() throws {
        let station = item(try issSatellite())
        XCTAssertTrue(station.isISS)
        XCTAssertEqual(station.name, "ISS")
    }

    func testAnotherSatelliteKeepsTheNameOfItsElementSet() throws {
        let other = item(try satellite(number: 90_001, name: "TEST SAT 1"))
        XCTAssertFalse(other.isISS)
        XCTAssertEqual(other.name, "TEST SAT 1")
        XCTAssertEqual(item(try satellite(number: 90_002, name: nil)).name, "NORAD 90002")
    }

    func testAPassIsVisibleFromTheStartOfItsVisiblePartToTheEnd() throws {
        let pass = item(try issSatellite(), rise: 1_000, set: 1_600, visible: [(1_100, 1_200), (1_300, 1_500)])
        XCTAssertEqual(pass.start, Date(timeIntervalSince1970: 1_100))
        XCTAssertEqual(pass.end, Date(timeIntervalSince1970: 1_500))
    }

    func testAPassWithoutAVisiblePartUsesItsRiseAndSet() throws {
        let pass = item(try issSatellite(), rise: 1_000, set: 1_600, visible: [])
        XCTAssertEqual(pass.start, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(pass.end, Date(timeIntervalSince1970: 1_600))
    }

    func testThePassIdentifierNamesTheSatelliteAndTheRiseToTheMinute() throws {
        let station = try issSatellite()
        // 1_792_300_020 s is exactly 29,871,667 minutes after 1970.
        XCTAssertEqual(item(station, rise: 1_792_300_020, set: 1_792_300_600, visible: []).id, "25544@29871667")
        XCTAssertEqual(item(station, rise: 1_792_300_049, set: 1_792_300_600, visible: []).id, "25544@29871667")
        XCTAssertEqual(item(station, rise: 1_792_300_051, set: 1_792_300_600, visible: []).id, "25544@29871668")
        XCTAssertEqual(item(try satellite(number: 90_001, name: nil), rise: 1_792_300_020, set: 1_792_300_600,
                            visible: []).id, "90001@29871667")
    }

    func testTwoSearchesFindingTheSamePassAreTheSamePass() throws {
        let station = try issSatellite()
        let first = item(station, rise: 1_792_300_020, set: 1_792_300_600, visible: [])
        let again = item(station, rise: 1_792_300_020.004, set: 1_792_300_600.004, visible: [])
        XCTAssertEqual(first, again)
        XCTAssertEqual(first.hashValue, again.hashValue)
        XCTAssertEqual(Set([first, again]).count, 1)
    }

    func testPassesOfDifferentSatellitesOrMinutesAreDifferent() throws {
        let station = try issSatellite()
        let other = try satellite(number: 90_001, name: nil)
        let first = item(station, rise: 1_792_300_020, set: 1_792_300_600, visible: [])
        XCTAssertNotEqual(first, item(other, rise: 1_792_300_020, set: 1_792_300_600, visible: []))
        XCTAssertNotEqual(first, item(station, rise: 1_792_300_020 + 5_580, set: 1_792_300_600 + 5_580, visible: []))
        XCTAssertEqual(Set([first, item(other, rise: 1_792_300_020, set: 1_792_300_600, visible: [])]).count, 2)
    }

    func testAPassIsFreshWhileItsElementSetIsYoungerThanTheLimitOfItsGroup() throws {
        let station = try issSatellite()
        let epoch = station.elements.epoch
        let day = 86_400.0
        let inStations = item(station, group: .stations)
        XCTAssertTrue(inStations.isFresh(at: epoch))
        XCTAssertTrue(inStations.isFresh(at: epoch.addingTimeInterval(3 * day - 60)))
        XCTAssertFalse(inStations.isFresh(at: epoch.addingTimeInterval(3 * day + 60)))
        // The visual group allows seven days.
        let inVisual = item(station, group: .visual)
        XCTAssertTrue(inVisual.isFresh(at: epoch.addingTimeInterval(7 * day - 60)))
        XCTAssertFalse(inVisual.isFresh(at: epoch.addingTimeInterval(7 * day + 60)))
    }

    func testAnElementSetFromTheFutureIsFresh() throws {
        let station = try issSatellite()
        XCTAssertTrue(item(station).isFresh(at: station.elements.epoch.addingTimeInterval(-10 * 86_400)))
    }
}
