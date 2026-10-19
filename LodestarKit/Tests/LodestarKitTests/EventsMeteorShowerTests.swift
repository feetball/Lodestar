import XCTest
@testable import LodestarKit

/// Meteor shower maxima.
///
/// Reference: International Meteor Organization, *2026 Meteor Shower Calendar* (IMO INFO 3-25, edited by Jürgen Rendtel),
/// archived at web.archive.org/web/20251223170423/https://imo.net/files/meteor-shower/cal2026.pdf: Table 5 (working list),
/// Table 6 (radiant positions) and the shower descriptions, which give the 2026 maxima in UT: Lyrids April 22 19h 40m
/// (λ☉ 32.32°), Perseids August 13 02h to 04h (λ☉ 140.0° to 140.1°), September ε-Perseids September 9 18h (166.7°),
/// Draconids October 9 01h (195.4°), Leonids November 17 23h 45m (235.27°), Geminids December 14 14h (262.2°); the calendar
/// also states that the Quadrantid maximum falls at Full Moon and the Perseid and Geminid maxima in moon-free nights.
final class EventsMeteorShowerTests: XCTestCase {
    private typealias Support = EventsTestSupport

    private func peaks(_ from: String, _ to: String) -> [(AstronomicalEvent, MeteorShowerPeak)] {
        Support.peaks(MeteorShowerFinder.events(from: Support.utc(from), to: Support.utc(to)))
    }

    private func peak(_ code: String, _ year: Int, file: StaticString = #filePath, line: UInt = #line) throws -> (AstronomicalEvent, MeteorShowerPeak) {
        try XCTUnwrap(peaks("\(year)-01-01T00:00:00Z", "\(year)-12-31T23:59:59Z").first { $0.1.shower.code == code },
                      file: file, line: line)
    }

    func testMaximaOf2026AgainstTheImoCalendar() throws {
        Support.assertInstant("2026-04-22T19:40:00Z", try peak("LYR", 2026).0.date, tolerance: 1_800, "Lyrids")
        Support.assertInstant("2026-09-09T18:00:00Z", try peak("SPE", 2026).0.date, tolerance: 1_800, "September epsilon-Perseids")
        Support.assertInstant("2026-10-09T01:00:00Z", try peak("DRA", 2026).0.date, tolerance: 2_400, "Draconids")
        Support.assertInstant("2026-11-17T23:45:00Z", try peak("LEO", 2026).0.date, tolerance: 1_800, "Leonids")
        Support.assertInstant("2026-12-14T14:00:00Z", try peak("GEM", 2026).0.date, tolerance: 1_800, "Geminids")
    }

    func testPerseidMaximumOf2026() throws {
        // IMO: August 13, 02h to 04h UT for λ☉ = 140.0° to 140.1°: the table value 140.0° is the early end.
        let perseids = try peak("PER", 2026)
        let date = perseids.0.date
        XCTAssertTrue(date >= Support.utc("2026-08-13T01:00:00Z") && date <= Support.utc("2026-08-13T03:00:00Z"), "\(date)")
        XCTAssertEqual(perseids.1.shower.name, "Perseids")
        XCTAssertEqual(perseids.1.shower.zhr, 100)
        // The Sun's longitude (J2000 ecliptic) at the peak is the table value.
        Support.assertNear(140.0, EventSearch.sunLongitudeJ2000(JulianDate(date: date)), tolerance: 1e-5, "solar longitude")
        // New Moon on August 12: the Moon is a thin crescent at the peak (IMO: moon-free night).
        XCTAssertTrue(perseids.1.moonIlluminatedFraction < 0.01, "\(perseids.1.moonIlluminatedFraction)")
    }

    func testMoonIlluminationAtTheMaxima() throws {
        // IMO 2026: the Quadrantid maximum falls at Full Moon, the Perseids and Geminids in moon-free nights.
        XCTAssertTrue(try peak("QUA", 2026).1.moonIlluminatedFraction > 0.99)
        XCTAssertTrue(try peak("PER", 2026).1.moonIlluminatedFraction < 0.01)
        XCTAssertTrue(try peak("GEM", 2026).1.moonIlluminatedFraction < 0.5)
        // The η-Aquariid maximum is about four days after Full Moon: the Moon is well past full but still bright.
        let aquariids = try peak("ETA", 2026).1.moonIlluminatedFraction
        XCTAssertTrue(aquariids > 0.7 && aquariids < 0.9, "\(aquariids)")
    }

    func testTheDateWorksEveryYear() throws {
        // The solar longitude fixes the date: the Perseid maximum moves by about six hours a year and one day in four
        // years (leap day), staying within August 12–14.
        for year in 2026...2040 {
            let date = Support.text(try peak("PER", year).0.date)
            XCTAssertTrue(date.hasPrefix("\(year)-08-12") || date.hasPrefix("\(year)-08-13") || date.hasPrefix("\(year)-08-14"), date)
            let geminids = Support.text(try peak("GEM", year).0.date)
            XCTAssertTrue(geminids.hasPrefix("\(year)-12-13") || geminids.hasPrefix("\(year)-12-14") || geminids.hasPrefix("\(year)-12-15"), geminids)
        }
        // The Quadrantids belong to January of the year they are asked for.
        XCTAssertTrue(Support.text(try peak("QUA", 2027).0.date).hasPrefix("2027-01-0"))
    }

    func testEveryShowerPeaksOncePerYear() {
        let found = peaks("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")
        XCTAssertEqual(found.count, MeteorShower.all.count)
        XCTAssertEqual(Set(MeteorShower.all.map(\.code)), Set(found.map { $0.1.shower.code }))
        for index in 1..<found.count { XCTAssertTrue(found[index].0.date >= found[index - 1].0.date) }
        // Three years hold three peaks of each.
        XCTAssertEqual(peaks("2026-01-01T00:00:00Z", "2028-12-31T23:59:59Z").count, 3 * MeteorShower.all.count)
    }

    func testRangeEdgesSelectPeaks() {
        // The Perseids peak at 02:09 UT on August 13, 2026: a range ending before it does not contain it.
        XCTAssertTrue(!peaks("2026-08-13T00:00:00Z", "2026-08-13T02:00:00Z").contains { $0.1.shower.code == "PER" })
        XCTAssertTrue(peaks("2026-08-13T02:00:00Z", "2026-08-13T03:00:00Z").contains { $0.1.shower.code == "PER" })
        XCTAssertTrue(!peaks("2026-08-13T02:30:00Z", "2026-08-13T04:00:00Z").contains { $0.1.shower.code == "PER" })
    }

    func testTheListMatchesTable5() throws {
        let all = MeteorShower.all
        XCTAssertEqual(all.count, 18)
        XCTAssertEqual(Set(all.map(\.code)).count, all.count)
        XCTAssertEqual(Set(all.map(\.iauNumber)).count, all.count)
        for shower in all {
            XCTAssertTrue(shower.peakSolarLongitude >= 0 && shower.peakSolarLongitude < 360, shower.code)
            XCTAssertTrue(shower.radiant.rightAscension >= 0 && shower.radiant.rightAscension < 360, shower.code)
            XCTAssertTrue((-90.0...90.0).contains(shower.radiant.declination), shower.code)
            XCTAssertTrue(shower.zhr >= 5 && (10.0...80.0).contains(shower.velocity) && (1.5...3.5).contains(shower.populationIndex), shower.code)
            XCTAssertTrue((1...12).contains(shower.activityStartMonth) && (1...12).contains(shower.activityEndMonth), shower.code)
            XCTAssertTrue((1...31).contains(shower.activityStartDay) && (1...31).contains(shower.activityEndDay), shower.code)
            XCTAssertTrue(abs(shower.radiantDriftRightAscension) < 2 && abs(shower.radiantDriftDeclination) < 1, shower.code)
        }
        // Table 5 of the 2026 calendar for the showers the brief names.
        let perseids = try XCTUnwrap(MeteorShower.withCode("per"))
        XCTAssertEqual(perseids.iauNumber, 7)
        XCTAssertEqual(perseids.peakSolarLongitude, 140.0)
        XCTAssertEqual(perseids.radiant.rightAscension, 48.0)
        XCTAssertEqual(perseids.radiant.declination, 58.0)
        XCTAssertEqual(perseids.velocity, 59.0)
        XCTAssertEqual(perseids.populationIndex, 2.2)
        let geminids = try XCTUnwrap(MeteorShower.withCode("GEM"))
        XCTAssertEqual(geminids.peakSolarLongitude, 262.2)
        XCTAssertEqual(geminids.zhr, 150)
        XCTAssertEqual(geminids.radiant.rightAscension, 112.0)
        XCTAssertEqual(geminids.radiant.declination, 33.0)
        let quadrantids = try XCTUnwrap(MeteorShower.withCode("QUA"))
        XCTAssertEqual(quadrantids.peakSolarLongitude, 283.15)
        XCTAssertEqual(quadrantids.zhr, 80)
        for code in ["QUA", "LYR", "ETA", "SDA", "CAP", "PER", "DRA", "ORI", "STA", "NTA", "LEO", "GEM", "URS"] {
            XCTAssertNotNil(MeteorShower.withCode(code), code)
        }
        XCTAssertNil(MeteorShower.withCode("XXX"))
    }

    func testRadiantDriftsWithTheDate() throws {
        let perseids = try XCTUnwrap(MeteorShower.withCode("PER"))
        let maximum = try peak("PER", 2026).0.date
        let atPeak = perseids.radiant(at: maximum)
        Support.assertNear(48.0, atPeak.rightAscension, tolerance: 1e-3, "radiant at the peak")
        Support.assertNear(58.0, atPeak.declination, tolerance: 1e-3, "radiant at the peak")
        let tenDaysLater = perseids.radiant(at: maximum.addingTimeInterval(10 * 86_400))
        Support.assertNear(48.0 + 14.2, tenDaysLater.rightAscension, tolerance: 1e-3, "RA ten days after")
        Support.assertNear(58.0 + 2.0, tenDaysLater.declination, tolerance: 1e-3, "Dec ten days after")
        // IMO Table 6 (rounded to whole degrees): Perseid radiant on Aug 5 at 37° +56° and on Aug 15 at 51° +58°.
        let august5 = perseids.radiant(at: Support.utc("2026-08-05T00:00:00Z"))
        Support.assertNear(37.0, august5.rightAscension, tolerance: 1.0, "Table 6, August 5 right ascension")
        Support.assertNear(56.0, august5.declination, tolerance: 1.0, "Table 6, August 5 declination")
        let august15 = perseids.radiant(at: Support.utc("2026-08-15T00:00:00Z"))
        Support.assertNear(51.0, august15.rightAscension, tolerance: 1.0, "Table 6, August 15 right ascension")
        Support.assertNear(58.0, august15.declination, tolerance: 1.0, "Table 6, August 15 declination")
        let before = perseids.radiant(at: maximum.addingTimeInterval(-8 * 86_400))
        Support.assertNear(48.0 - 8 * 1.42, before.rightAscension, tolerance: 1e-3, "RA eight days before")
        // Long after the activity period the drift stops at its end.
        let december = perseids.radiant(at: maximum.addingTimeInterval(100 * 86_400))
        let end = perseids.radiant(at: Support.utc("2026-08-24T23:59:00Z"))
        Support.assertNear(end.rightAscension, december.rightAscension, tolerance: 0.2, "clamped at the end of the activity")
        // The Draconids do not drift.
        let draconids = try XCTUnwrap(MeteorShower.withCode("DRA"))
        XCTAssertEqual(draconids.radiant, draconids.radiant(at: Support.utc("2026-10-07T00:00:00Z")))
    }

    func testActivityPeriods() throws {
        let perseids = try XCTUnwrap(MeteorShower.withCode("PER"))
        let maximum = try peak("PER", 2026)
        XCTAssertEqual(maximum.1.activityStart, Support.utc("2026-07-17T00:00:00Z"))
        XCTAssertEqual(maximum.1.activityEnd, Support.utc("2026-08-25T00:00:00Z"))
        XCTAssertEqual(perseids.activityPeriod(aroundPeak: maximum.0.date),
                       DateInterval(start: Support.utc("2026-07-17T00:00:00Z"), end: Support.utc("2026-08-25T00:00:00Z")))
        XCTAssertTrue(perseids.isActive(at: Support.utc("2026-08-01T00:00:00Z")))
        XCTAssertTrue(!perseids.isActive(at: Support.utc("2026-09-01T00:00:00Z")))
        XCTAssertTrue(!perseids.isActive(at: Support.utc("2026-07-10T00:00:00Z")))
        // The Quadrantids are active over the turn of the year, Dec 28 to Jan 12.
        let quadrantids = try peak("QUA", 2026)
        XCTAssertEqual(quadrantids.1.activityStart, Support.utc("2025-12-28T00:00:00Z"))
        XCTAssertEqual(quadrantids.1.activityEnd, Support.utc("2026-01-13T00:00:00Z"))
        let shower = try XCTUnwrap(MeteorShower.withCode("QUA"))
        XCTAssertTrue(shower.isActive(at: Support.utc("2026-01-01T12:00:00Z")))
        XCTAssertTrue(shower.isActive(at: Support.utc("2025-12-30T12:00:00Z")))
        XCTAssertTrue(!shower.isActive(at: Support.utc("2026-02-01T00:00:00Z")))
    }

    func testShowerWithBadValuesDoesNotCrash() {
        // A shower assembled by the caller may hold anything: nothing may trap.
        let broken = MeteorShower(code: "BAD", iauNumber: 0, name: "Broken", activityStartMonth: 13, activityStartDay: 40,
                                  activityEndMonth: 0, activityEndDay: 0, peakSolarLongitude: .nan, zhr: 0,
                                  radiant: EquatorialCoordinate(rightAscension: 400, declination: 120),
                                  radiantDriftRightAscension: .nan, radiantDriftDeclination: .infinity, velocity: .nan,
                                  populationIndex: .nan)
        let moment = Support.utc("2026-08-13T00:00:00Z")
        _ = broken.peak(near: moment)
        _ = broken.radiant(at: moment)
        _ = broken.activityPeriod(aroundPeak: moment)
        XCTAssertTrue(!broken.isActive(at: moment))
        let bent = MeteorShower(code: "BNT", iauNumber: 0, name: "Bent", activityStartMonth: 2, activityStartDay: 30,
                                activityEndMonth: 14, activityEndDay: 99, peakSolarLongitude: 1_000, zhr: 5,
                                radiant: EquatorialCoordinate(rightAscension: 10, declination: 10),
                                radiantDriftRightAscension: 1, radiantDriftDeclination: 0, velocity: 20, populationIndex: 2)
        _ = bent.peak(near: moment)
        _ = bent.radiant(at: moment)
        _ = bent.activityPeriod(aroundPeak: moment)
        let pole = MeteorShower(code: "X", iauNumber: 0, name: "X", activityStartMonth: 1, activityStartDay: 1,
                                activityEndMonth: 1, activityEndDay: 2, peakSolarLongitude: 10, zhr: 5,
                                radiant: EquatorialCoordinate(rightAscension: 40, declination: 90),
                                radiantDriftRightAscension: 0, radiantDriftDeclination: 0, velocity: 20, populationIndex: 2)
        XCTAssertEqual(pole.radiant, EquatorialCoordinate(rightAscension: 40, declination: 90))
    }

    func testRadiantIsAimable() throws {
        let perseids = try XCTUnwrap(MeteorShower.withCode("PER"))
        let maximum = try peak("PER", 2026)
        let observer = Support.boulder.observer
        let frame = SkyFrame(date: maximum.0.date.addingTimeInterval(86_400 * 5), observer: observer)
        let target = AimTarget.radiant(perseids)
        let expected = frame.horizontal(j2000: perseids.radiant(at: frame.date), properMotion: nil, refraction: true)
        XCTAssertEqual(target.horizontal(in: frame), expected)
        XCTAssertEqual(target.horizontal(in: frame, refraction: false),
                       frame.horizontal(j2000: perseids.radiant(at: frame.date), properMotion: nil, refraction: false))
        XCTAssertEqual(maximum.0.aimTargets, [AimTarget.radiant(perseids)])
        // aimDirection of a single target is that target.
        XCTAssertEqual(maximum.0.aimDirection(in: frame), expected)
    }

    func testRadiantAltitudeAndWindowAtADarkSite() throws {
        // Boulder (40N 105.27W), Perseids 2026: the peak, 02:09 UT = 20:09 MDT on August 12, comes in daylight at the
        // observer's place; the radiant is highest before dawn and the window lies in the dark of the night.
        let options = EventOptions(kinds: [.meteorShower], timeZone: TimeZone(identifier: "America/Denver"))
        let events = EventCalculator.events(from: Support.utc("2026-08-12T00:00:00Z"), to: Support.utc("2026-08-14T00:00:00Z"),
                                            observer: Support.boulder.observer, options: options)
        let perseids = try XCTUnwrap(events.first {
            if case let .meteorShower(peak) = $0.details { return peak.shower.code == "PER" }
            return false
        })
        let visibility = try XCTUnwrap(perseids.visibility)
        let window = try XCTUnwrap(visibility.bestWindow)
        XCTAssertEqual(visibility.darknessLimit, -18.0)
        // Astronomical dusk at Boulder on August 12 is about 22:00 MDT (04:00 UT August 13) and dawn about 04:50 MDT (10:50 UT).
        XCTAssertTrue(window.start >= Support.utc("2026-08-13T03:00:00Z") && window.start <= Support.utc("2026-08-13T05:00:00Z"), "\(window.start)")
        XCTAssertTrue(window.end >= Support.utc("2026-08-13T10:00:00Z") && window.end <= Support.utc("2026-08-13T11:30:00Z"), "\(window.end)")
        let best = try XCTUnwrap(visibility.bestTime)
        XCTAssertTrue(best >= window.start && best <= window.end)
        guard case let .radiant(shower) = perseids.aimTargets[0] else { return XCTFail("the target is the radiant") }
        let radiant = SkyFrame(date: best, observer: Support.boulder.observer).horizontal(j2000: shower.radiant, properMotion: nil, refraction: false)
        XCTAssertTrue(radiant.altitude > 60, "the Perseid radiant is high before dawn: \(radiant.altitude)")
        // At the peak itself the radiant is in the north-east sky but the Sun is still up.
        XCTAssertTrue(!visibility.isDark)
        XCTAssertTrue(visibility.sunAltitude > -18)
    }
}
