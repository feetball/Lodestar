import XCTest
@testable import LodestarKit

/// Lunar eclipses against the NASA/Espenak catalog.
///
/// Reference: F. Espenak and J. Meeus, *Five Millennium Catalog of Lunar Eclipses*, NASA GSFC
/// (https://eclipse.gsfc.nasa.gov/LEcat5/LE2001-2100.html: greatest eclipse in TD, ΔT, gamma, magnitudes, durations) and
/// the per-eclipse plots https://eclipse.gsfc.nasa.gov/LEplot/LEplot2001/LE2025Mar14T.pdf (and the three others): contact
/// times in UT, computed with ΔT = 75 s and the Danjon rule. The kit uses its own ΔT (about 69 s in 2025–26), so its
/// times run a few seconds behind; the observed differences are below 17 s and the brief allowed ±2 minutes.
final class EventsLunarEclipseTests: XCTestCase {
    private typealias Support = EventsTestSupport

    /// NASA contact times (UT) of one eclipse; `nil` where the eclipse has no such contact.
    private struct Reference {
        let date: String
        let kind: LunarEclipseKind
        let p1: String
        let u1: String?
        let u2: String?
        let greatest: String
        let u3: String?
        let u4: String?
        let p4: String
        let gamma: Double
        let penumbralMagnitude: Double
        let umbralMagnitude: Double
    }

    private let references = [
        Reference(date: "2025-03-14", kind: .total, p1: "2025-03-14T03:57:24Z", u1: "2025-03-14T05:09:33Z",
                  u2: "2025-03-14T06:25:59Z", greatest: "2025-03-14T06:58:42Z", u3: "2025-03-14T07:31:23Z",
                  u4: "2025-03-14T08:47:48Z", p4: "2025-03-14T10:00:01Z", gamma: 0.3484, penumbralMagnitude: 2.2595,
                  umbralMagnitude: 1.1784),
        Reference(date: "2025-09-07", kind: .total, p1: "2025-09-07T15:28:21Z", u1: "2025-09-07T16:27:02Z",
                  u2: "2025-09-07T17:30:41Z", greatest: "2025-09-07T18:11:43Z", u3: "2025-09-07T18:52:47Z",
                  u4: "2025-09-07T19:56:26Z", p4: "2025-09-07T20:55:00Z", gamma: -0.2752, penumbralMagnitude: 2.3440,
                  umbralMagnitude: 1.3619),
        Reference(date: "2026-03-03", kind: .total, p1: "2026-03-03T08:44:22Z", u1: "2026-03-03T09:50:00Z",
                  u2: "2026-03-03T11:04:26Z", greatest: "2026-03-03T11:33:37Z", u3: "2026-03-03T12:02:45Z",
                  u4: "2026-03-03T13:17:10Z", p4: "2026-03-03T14:22:59Z", gamma: -0.3765, penumbralMagnitude: 2.1838,
                  umbralMagnitude: 1.1507),
        Reference(date: "2026-08-28", kind: .partial, p1: "2026-08-28T01:23:55Z", u1: "2026-08-28T02:33:48Z", u2: nil,
                  greatest: "2026-08-28T04:12:49Z", u3: nil, u4: "2026-08-28T05:51:55Z", p4: "2026-08-28T07:01:41Z",
                  gamma: 0.4964, penumbralMagnitude: 1.9645, umbralMagnitude: 0.9299),
    ]

    private func eclipses(_ from: String, _ to: String) -> [LunarEclipse] {
        Support.lunarEclipses(LunarEclipseFinder.events(from: Support.utc(from), to: Support.utc(to))).map { $0.1 }
    }

    func testContactTimesAgainstTheNasaCatalog() {
        // Observed differences are at most 17 s; 40 s leaves room for the ΔT assumption and still catches regressions.
        let tolerance = 40.0
        for reference in references {
            let found = eclipses("\(reference.date)T00:00:00Z", "\(reference.date)T23:59:59Z")
            XCTAssertEqual(found.count, 1, reference.date)
            guard let eclipse = found.first else { continue }
            XCTAssertEqual(eclipse.kind, reference.kind, reference.date)
            Support.assertInstant(reference.p1, eclipse.p1, tolerance: tolerance, "\(reference.date) P1")
            Support.assertInstant(reference.greatest, eclipse.greatest, tolerance: tolerance, "\(reference.date) greatest")
            Support.assertInstant(reference.p4, eclipse.p4, tolerance: tolerance, "\(reference.date) P4")
            let pairs: [(String, String?, Date?)] = [
                ("U1", reference.u1, eclipse.u1), ("U2", reference.u2, eclipse.u2),
                ("U3", reference.u3, eclipse.u3), ("U4", reference.u4, eclipse.u4),
            ]
            for (label, expected, actual) in pairs {
                if let expected {
                    Support.assertInstant(expected, actual, tolerance: tolerance, "\(reference.date) \(label)")
                } else {
                    XCTAssertNil(actual, "\(reference.date) \(label)")
                }
            }
        }
    }

    func testMagnitudesAndGammaAgainstTheNasaCatalog() {
        for reference in references {
            guard let eclipse = eclipses("\(reference.date)T00:00:00Z", "\(reference.date)T23:59:59Z").first else {
                XCTFail(reference.date)
                continue
            }
            Support.assertNear(reference.gamma, eclipse.gamma, tolerance: 0.002, "\(reference.date) gamma")
            Support.assertNear(reference.penumbralMagnitude, eclipse.penumbralMagnitude, tolerance: 0.002,
                               "\(reference.date) penumbral magnitude")
            Support.assertNear(reference.umbralMagnitude, eclipse.umbralMagnitude, tolerance: 0.002,
                               "\(reference.date) umbral magnitude")
        }
    }

    func testDurationsAgainstTheNasaCatalog() {
        // Catalog durations (minutes): 2025-03-14 pen 362.6, par 218.3, total 65.4; 2026-08-28 pen 337.8, par 198.1.
        let march = eclipses("2025-03-14T00:00:00Z", "2025-03-14T23:59:59Z")[0]
        Support.assertNear(362.6 * 60, march.penumbralDuration, tolerance: 40, "penumbral duration")
        Support.assertNear(218.3 * 60, march.partialDuration, tolerance: 40, "partial duration")
        Support.assertNear(65.4 * 60, march.totalDuration, tolerance: 40, "total duration")
        let august = eclipses("2026-08-28T00:00:00Z", "2026-08-28T23:59:59Z")[0]
        Support.assertNear(337.8 * 60, august.penumbralDuration, tolerance: 40, "penumbral duration")
        Support.assertNear(198.1 * 60, august.partialDuration, tolerance: 40, "partial duration")
        XCTAssertEqual(august.totalDuration, 0)
    }

    func testKindsMagnitudesAndDurationsAgainstTheNasaCatalog2028To2040() {
        // Columns of the catalog: date, greatest eclipse (TD), ΔT (s), type (N penumbral, P partial, T total), gamma,
        // penumbral and umbral magnitude, durations (minutes) of the penumbral, partial and total phases.
        let rows = """
        2028 Jan 12 | 04:14:13 | 77 | P | 0.9817 | 1.0468 | 0.0662 | 250.7 | 56.0 | -
        2028 Jul 06 | 18:20:57 | 77 | P | -0.7903 | 1.4266 | 0.3892 | 310.6 | 141.5 | -
        2028 Dec 31 | 16:53:15 | 77 | T | 0.3258 | 2.2742 | 1.2463 | 336.2 | 208.8 | 71.3
        2029 Jun 26 | 03:23:22 | 77 | T | 0.0124 | 2.8266 | 1.8436 | 335.1 | 219.5 | 101.9
        2029 Dec 20 | 22:43:12 | 78 | T | -0.3811 | 2.2008 | 1.1174 | 358.0 | 213.3 | 53.7
        2030 Jun 15 | 18:34:34 | 78 | P | 0.7534 | 1.4480 | 0.5025 | 278.2 | 144.4 | -
        2030 Dec 09 | 22:28:51 | 78 | N | -1.0731 | 0.9416 | -0.1628 | 279.2 | - | -
        2031 May 07 | 03:52:02 | 78 | N | -1.0694 | 0.8814 | -0.0904 | 237.3 | - | -
        2031 Jun 05 | 11:45:17 | 78 | N | 1.4731 | 0.1292 | -0.8199 | 95.6 | - | -
        2031 Oct 30 | 07:46:45 | 79 | N | 1.1773 | 0.7161 | -0.3204 | 231.8 | - | -
        2032 Apr 25 | 15:14:51 | 79 | T | -0.3558 | 2.2192 | 1.1913 | 342.4 | 211.2 | 65.5
        2032 Oct 18 | 19:03:40 | 79 | T | 0.4169 | 2.0830 | 1.1028 | 315.4 | 195.9 | 47.1
        2033 Apr 14 | 19:13:51 | 80 | T | 0.3954 | 2.1711 | 1.0944 | 361.2 | 215.0 | 49.2
        2033 Oct 08 | 10:56:23 | 80 | T | -0.2889 | 2.3057 | 1.3497 | 312.6 | 202.4 | 78.8
        2034 Apr 03 | 19:06:59 | 80 | N | 1.1144 | 0.8545 | -0.2274 | 265.4 | - | -
        2034 Sep 28 | 02:47:37 | 81 | P | -1.0110 | 0.9911 | 0.0144 | 248.7 | 26.7 | -
        2035 Feb 22 | 09:06:12 | 81 | N | -1.0367 | 0.9652 | -0.0535 | 255.7 | - | -
        2035 Aug 19 | 01:12:15 | 81 | P | 0.9433 | 1.1507 | 0.1037 | 289.8 | 76.5 | -
        2036 Feb 11 | 22:13:06 | 82 | T | -0.3110 | 2.2751 | 1.2995 | 316.1 | 201.9 | 74.5
        2036 Aug 07 | 02:52:32 | 82 | T | 0.2004 | 2.5266 | 1.4544 | 372.1 | 231.3 | 95.3
        2037 Jan 31 | 14:01:38 | 82 | T | 0.3619 | 2.1803 | 1.2074 | 312.1 | 197.5 | 63.7
        2037 Jul 27 | 04:09:53 | 83 | P | -0.5582 | 1.8584 | 0.8095 | 340.8 | 192.4 | -
        2038 Jan 21 | 03:49:52 | 83 | N | 1.0710 | 0.8996 | -0.1140 | 245.8 | - | -
        2038 Jun 17 | 02:45:02 | 83 | N | 1.3082 | 0.4422 | -0.5275 | 176.3 | - | -
        2038 Jul 16 | 11:35:56 | 84 | N | -1.2837 | 0.4999 | -0.4952 | 192.4 | - | -
        2038 Dec 11 | 17:45:00 | 84 | N | -1.1448 | 0.8046 | -0.2892 | 258.5 | - | -
        2039 Jun 06 | 18:54:25 | 84 | P | 0.5460 | 1.8272 | 0.8846 | 296.7 | 179.3 | -
        2039 Nov 30 | 16:56:28 | 85 | P | -0.4721 | 2.0418 | 0.9426 | 360.1 | 206.0 | -
        2040 May 26 | 11:46:22 | 85 | T | -0.1872 | 2.4938 | 1.5348 | 321.4 | 210.7 | 92.2
        2040 Nov 18 | 19:04:40 | 85 | T | 0.2361 | 2.4525 | 1.3974 | 353.6 | 220.4 | 87.8
        """.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        XCTAssertEqual(rows.count, 30)
        for row in rows {
            let fields = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let date = fields[0].split(separator: " ").map(String.init)
            let month = (months.firstIndex(of: date[1]) ?? 0) + 1
            let iso = "\(date[0])-\(String(format: "%02d", month))-\(date[2])T\(fields[1])Z"
            let greatest = Support.utc(iso).addingTimeInterval(-(Double(fields[2]) ?? 0))
            let day = String(iso.prefix(10))
            let found = eclipses("\(day)T00:00:00Z", "\(day)T23:59:59Z").filter {
                abs(Support.seconds($0.greatest, greatest)) < 3_600
            }
            XCTAssertEqual(found.count, 1, row)
            guard let eclipse = found.first else { continue }
            let expectedKind: LunarEclipseKind = switch fields[3] {
            case "N": .penumbral
            case "P": .partial
            default: .total
            }
            XCTAssertEqual(eclipse.kind, expectedKind, row)
            XCTAssertTrue(abs(Support.seconds(eclipse.greatest, greatest)) < 45, "\(row) greatest")
            Support.assertNear(Double(fields[4]) ?? .nan, eclipse.gamma, tolerance: 0.003, "\(row) gamma")
            Support.assertNear(Double(fields[5]) ?? .nan, eclipse.penumbralMagnitude, tolerance: 0.005,
                               "\(row) penumbral magnitude")
            Support.assertNear(Double(fields[6]) ?? .nan, eclipse.umbralMagnitude, tolerance: 0.005,
                               "\(row) umbral magnitude")
            Support.assertNear((Double(fields[7]) ?? .nan) * 60, eclipse.penumbralDuration, tolerance: 60,
                               "\(row) penumbral duration")
            Support.assertNear((Double(fields[8]) ?? 0) * 60, eclipse.partialDuration, tolerance: 60,
                               "\(row) partial duration")
            Support.assertNear((Double(fields[9]) ?? 0) * 60, eclipse.totalDuration, tolerance: 60,
                               "\(row) total duration")
        }
    }

    func testPenumbralEclipsesOf2027() {
        // Catalog: 2027 Feb 20 greatest 23:14:06 TD (ΔT 76 s), gamma -1.0480, pen 0.9266, um -0.0569;
        // 2027 Aug 17 07:14:59 TD, gamma 1.2797, pen 0.5456, um -0.5254; 2027 Jul 18 16:04:09 TD, pen 0.0014.
        let found = eclipses("2027-01-01T00:00:00Z", "2027-12-31T23:59:59Z")
        XCTAssertEqual(found.count, 3)
        guard found.count == 3 else { return }
        XCTAssertTrue(found.allSatisfy { $0.kind == .penumbral })
        XCTAssertTrue(found.allSatisfy { $0.u1 == nil && $0.u2 == nil && $0.u3 == nil && $0.u4 == nil })
        Support.assertInstant("2027-02-20T23:12:50Z", found[0].greatest, tolerance: 40, "Feb greatest")
        Support.assertInstant("2027-07-18T16:02:53Z", found[1].greatest, tolerance: 40, "Jul greatest")
        Support.assertInstant("2027-08-17T07:13:43Z", found[2].greatest, tolerance: 40, "Aug greatest")
        Support.assertNear(0.9266, found[0].penumbralMagnitude, tolerance: 0.004, "Feb penumbral magnitude")
        Support.assertNear(-0.0569, found[0].umbralMagnitude, tolerance: 0.004, "Feb umbral magnitude")
        Support.assertNear(-1.0480, found[0].gamma, tolerance: 0.003, "Feb gamma")
        Support.assertNear(0.5456, found[2].penumbralMagnitude, tolerance: 0.004, "Aug penumbral magnitude")
        Support.assertNear(1.2797, found[2].gamma, tolerance: 0.003, "Aug gamma")
        Support.assertNear(0.0014, found[1].penumbralMagnitude, tolerance: 0.002, "Jul penumbral magnitude")
    }

    func testContactsAreInOrderAndComplete() {
        let total = eclipses("2025-03-14T00:00:00Z", "2025-03-14T23:59:59Z")[0]
        XCTAssertEqual(total.contacts.map(\.contact), [.p1, .u1, .u2, .greatest, .u3, .u4, .p4])
        for index in 1..<total.contacts.count {
            XCTAssertTrue(total.contacts[index].time > total.contacts[index - 1].time)
        }
        let partial = eclipses("2026-08-28T00:00:00Z", "2026-08-28T23:59:59Z")[0]
        XCTAssertEqual(partial.contacts.map(\.contact), [.p1, .u1, .greatest, .u4, .p4])
        let penumbral = eclipses("2027-02-20T00:00:00Z", "2027-02-21T23:59:59Z")[0]
        XCTAssertEqual(penumbral.contacts.map(\.contact), [.p1, .greatest, .p4])
    }

    func testQuietMonthsHaveNoEclipse() {
        // 2025 has only the two eclipses of March and September (NASA catalog).
        XCTAssertEqual(eclipses("2025-03-20T00:00:00Z", "2025-08-31T23:59:59Z").count, 0)
        XCTAssertEqual(eclipses("2025-01-01T00:00:00Z", "2025-12-31T23:59:59Z").count, 2)
        XCTAssertEqual(eclipses("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z").count, 2)
    }

    func testSignOfGammaFollowsTheSideOfTheAxis() {
        // The Moon passes north of the shadow axis in March 2025 (declination +2°41′ against the axis at +2°24′).
        let march = eclipses("2025-03-14T00:00:00Z", "2025-03-14T23:59:59Z")[0]
        let september = eclipses("2025-09-07T00:00:00Z", "2025-09-07T23:59:59Z")[0]
        XCTAssertTrue(march.gamma > 0 && september.gamma < 0)
    }

    func testVisibilityFromLosAngelesAndMoscow() {
        // 2025-03-14: the whole eclipse happens during the night of 13/14 March in California (PDT, UTC-7: P1 20:57,
        // totality 23:26–00:31) and in the afternoon and evening in Moscow, where the full Moon has not risen.
        let from = Support.utc("2025-03-14T00:00:00Z")
        let to = Support.utc("2025-03-14T23:59:59Z")
        let onlyEclipses = EventOptions(kinds: [.lunarEclipse])
        let losAngeles = EventCalculator.events(from: from, to: to, observer: Support.losAngeles.observer, options: onlyEclipses)
        XCTAssertEqual(losAngeles.count, 1)
        guard let visibility = losAngeles.first?.visibility else { return XCTFail("no visibility") }
        XCTAssertEqual(visibility.contacts.count, 7)
        for contact in visibility.contacts {
            let frame = SkyFrame(date: contact.time, observer: Support.losAngeles.observer)
            let moon = frame.horizontal(of: .moon, refraction: false)
            Support.assertNear(moon.altitude, contact.altitude, tolerance: 1e-9, "\(contact.contact) altitude")
            Support.assertNear(moon.azimuth, contact.azimuth, tolerance: 1e-9, "\(contact.contact) azimuth")
        }
        // Totality is high in the sky and the sky is dark.
        guard let totalityStart = visibility.contacts.first(where: { $0.contact == .u2 }) else { return XCTFail("no U2") }
        XCTAssertTrue(totalityStart.altitude > 30, "Moon at the start of totality: \(totalityStart.altitude)")
        XCTAssertTrue(visibility.isDark && visibility.isObservable)
        guard let window = visibility.bestWindow, let eclipse = Support.lunarEclipses(losAngeles).first?.1,
              let umbralStart = eclipse.u1, let umbralEnd = eclipse.u4 else { return XCTFail("no window") }
        XCTAssertTrue(abs(Support.seconds(window.start, umbralStart)) < 0.01, "the window starts at U1")
        XCTAssertTrue(abs(Support.seconds(window.end, umbralEnd)) < 0.01, "the window ends at U4")
        XCTAssertEqual(visibility.bestTime, eclipse.greatest)
        XCTAssertEqual(visibility.darknessLimit, 0)

        guard let moscow = EventCalculator.events(from: from, to: to, observer: Support.moscow.observer,
                                                  options: onlyEclipses).first,
              let moscowVisibility = moscow.visibility else { return XCTFail("no Moscow visibility") }
        XCTAssertNil(moscowVisibility.bestWindow)
        XCTAssertNil(moscowVisibility.bestTime)
        XCTAssertTrue(moscowVisibility.contacts.allSatisfy { $0.altitude < 0 }, "the Moon is below the horizon all through the eclipse")
        XCTAssertTrue(!moscowVisibility.isObservable)
        // visibleOnly drops it from the list.
        let visibleOnly = EventOptions(kinds: [.lunarEclipse], visibleOnly: true)
        XCTAssertEqual(EventCalculator.events(from: from, to: to, observer: Support.moscow.observer, options: visibleOnly).count, 0)
        XCTAssertEqual(EventCalculator.events(from: from, to: to, observer: Support.losAngeles.observer, options: visibleOnly).count, 1)
    }

    func testEclipseWithTheMoonRisingDuringIt() {
        // Auckland (36.85S 174.76E, NZDT UTC+13) on 2025-03-14: the full Moon rises at about 06:45 UT (19:45 local),
        // between the start (U2 06:26) and the end (U3 07:31) of totality; the umbral phases U1–U4 are 05:09–08:48 UT.
        // The window starts at moonrise and runs to the end of the partial phase.
        let auckland = Observer(location: GeographicLocation(latitude: -36.85, longitude: 174.76, elevation: 20))
        let onlyEclipses = EventOptions(kinds: [.lunarEclipse])
        let events = EventCalculator.events(from: Support.utc("2025-03-14T00:00:00Z"), to: Support.utc("2025-03-14T23:59:59Z"),
                                            observer: auckland, options: onlyEclipses)
        guard let visibility = events.first?.visibility, let eclipse = Support.lunarEclipses(events).first?.1,
              let window = visibility.bestWindow, let totalityStart = eclipse.u2, let totalityEnd = eclipse.u3,
              let umbralEnd = eclipse.u4 else { return XCTFail("no visibility") }
        XCTAssertTrue(visibility.contacts.contains { $0.altitude < 0 } && visibility.contacts.contains { $0.altitude > 0 })
        let frame = SkyFrame(date: window.start, observer: auckland)
        Support.assertNear(RiseSetCalculator.standardHorizonAltitude, frame.horizontal(of: .moon, refraction: false).altitude,
                           tolerance: 0.01, "window starts at moonrise")
        XCTAssertTrue(window.start > totalityStart && window.start < totalityEnd, "moonrise during totality")
        XCTAssertTrue(abs(Support.seconds(window.end, umbralEnd)) < 0.01)
        // The greatest eclipse (06:58 UT) is after moonrise: it is the best moment.
        XCTAssertEqual(visibility.bestTime, eclipse.greatest)
        XCTAssertTrue((visibility.contacts.first { $0.contact == .greatest }?.altitude ?? -90) > 0)
        XCTAssertTrue((visibility.contacts.first { $0.contact == .p1 }?.altitude ?? 90) < 0)
    }

    func testInvalidIntervalsGiveNoEclipses() {
        let moment = Support.utc("2025-03-14T00:00:00Z")
        XCTAssertTrue(LunarEclipseFinder.events(from: moment, to: moment.addingTimeInterval(-1)).isEmpty)
        XCTAssertTrue(LunarEclipseFinder.events(from: moment, to: moment).isEmpty)
    }

    func testShadowEnlargementFollowsDanjonsRule() {
        // The NASA plot of 2025-03-14 lists penumbral radius 1.1899° and umbral radius 0.6537° at greatest eclipse.
        let shadow = LunarShadow(ut: JulianDate(date: Support.utc("2025-03-14T06:58:42Z")).ut)
        Support.assertNear(0.6537, shadow.umbra, tolerance: 0.0005, "umbral radius")
        Support.assertNear(1.1899, shadow.penumbra, tolerance: 0.0005, "penumbral radius")
        Support.assertNear(0.3171, shadow.separation, tolerance: 0.001, "axis distance")
        XCTAssertTrue(abs(LunarShadow.shadowEnlargement - 1.01) < 1e-12)
    }
}
