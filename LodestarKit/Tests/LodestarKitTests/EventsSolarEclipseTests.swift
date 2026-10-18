import XCTest
@testable import LodestarKit

/// Solar eclipses: the global circumstances against the NASA catalog and the local circumstances against the U.S. Naval
/// Observatory.
///
/// - NASA: F. Espenak, *Catalog of Solar Eclipses: 2001 to 2100* (https://eclipse.gsfc.nasa.gov/SEcat5/SE2001-2100.html):
///   greatest eclipse in TD with the catalog's ΔT (73–77 s, so the UT is TD − ΔT), gamma, magnitude and kind.
/// - USNO: the Solar Eclipse Computer API (https://aa.usno.navy.mil/api/eclipses/solar/date?date=…&coords=lat,lon&height=m),
///   queried 2026-10-18: contact times in UT, magnitude (fraction of the Sun's diameter covered), obscuration, Sun
///   altitude and azimuth at maximum. USNO assumes ΔT of 72.5–74 s, the kit about 69 s, so the kit's times differ
///   by up to about 15 s (observed); tests allow 45 s, the brief ±1 minute.
/// - Luxor 2027-08-02, which the USNO service does not cover: topocentric apparent positions of the Sun and Moon from
///   JPL Horizons (DE441, observer table at SITE_COORD 32.6396,25.6872,0.075; quantities 2 and 20), contacts from the
///   separation against the apparent radii (Sun 695 700 km, Moon 1 737.4 km) at 20 s steps. The same method reproduces
///   the USNO times for Dallas and Burgos to 6 s. Published minute-level times (partial begins 11:40, totality 13:01 to
///   13:08, ends 14:26 EEST, UTC+3) agree.
final class EventsSolarEclipseTests: XCTestCase {
    private typealias Support = EventsTestSupport

    private struct Catalog {
        let date: String
        let kind: SolarEclipseKind
        let greatest: String
        let gamma: Double
        let magnitude: Double
    }

    private let catalog = [
        Catalog(date: "2023-04-20", kind: .hybrid, greatest: "2023-04-20T04:16:43Z", gamma: -0.3952, magnitude: 1.0132),
        Catalog(date: "2023-10-14", kind: .annular, greatest: "2023-10-14T17:59:27Z", gamma: 0.3753, magnitude: 0.9520),
        Catalog(date: "2024-04-08", kind: .total, greatest: "2024-04-08T18:17:15Z", gamma: 0.3431, magnitude: 1.0566),
        Catalog(date: "2024-10-02", kind: .annular, greatest: "2024-10-02T18:44:59Z", gamma: -0.3509, magnitude: 0.9326),
        Catalog(date: "2025-03-29", kind: .partial, greatest: "2025-03-29T10:47:21Z", gamma: 1.0405, magnitude: 0.9376),
        Catalog(date: "2025-09-21", kind: .partial, greatest: "2025-09-21T19:41:49Z", gamma: -1.0651, magnitude: 0.8550),
        Catalog(date: "2026-02-17", kind: .annular, greatest: "2026-02-17T12:11:51Z", gamma: -0.9743, magnitude: 0.9630),
        Catalog(date: "2026-08-12", kind: .total, greatest: "2026-08-12T17:45:51Z", gamma: 0.8977, magnitude: 1.0386),
        Catalog(date: "2027-02-06", kind: .annular, greatest: "2027-02-06T15:59:32Z", gamma: -0.2952, magnitude: 0.9281),
        Catalog(date: "2027-08-02", kind: .total, greatest: "2027-08-02T10:06:34Z", gamma: 0.1421, magnitude: 1.0790),
        Catalog(date: "2028-01-26", kind: .annular, greatest: "2028-01-26T15:07:42Z", gamma: 0.3901, magnitude: 0.9208),
        Catalog(date: "2028-07-22", kind: .total, greatest: "2028-07-22T02:55:23Z", gamma: -0.6056, magnitude: 1.0560),
    ]

    private func eclipses(_ from: String, _ to: String) -> [SolarEclipse] {
        Support.solarEclipses(SolarEclipseFinder.events(from: Support.utc(from), to: Support.utc(to))).map { $0.1 }
    }

    func testGlobalCircumstancesAgainstTheNasaCatalog() {
        for entry in catalog {
            let found = eclipses("\(entry.date)T00:00:00Z", "\(entry.date)T23:59:59Z")
            XCTAssertEqual(found.count, 1, entry.date)
            guard let eclipse = found.first else { continue }
            XCTAssertEqual(eclipse.kind, entry.kind, entry.date)
            Support.assertInstant(entry.greatest, eclipse.greatest, tolerance: 45, "\(entry.date) greatest eclipse")
            Support.assertNear(entry.gamma, eclipse.gamma, tolerance: 0.003, "\(entry.date) gamma")
            // Central eclipses: ratio of the diameters (1 mm in a thousand: the kit's Moon and Sun radii differ a little
            // from the catalog's). Partial eclipses: the Earth is a sphere here, so allow 0.007.
            let tolerance = entry.kind == .partial ? 0.007 : 0.003
            Support.assertNear(entry.magnitude, eclipse.greatestMagnitude, tolerance: tolerance, "\(entry.date) magnitude")
            XCTAssertNil(eclipse.local, "no observer, no local circumstances")
        }
    }

    func testKindsAgainstTheNasaCatalog2029To2045() {
        // Columns of the catalog: date, greatest eclipse (TD), ΔT (s), type (P partial, A annular, T total, H hybrid;
        // a trailing + or - marks a non-central total or annular eclipse, "s" an annular eclipse whose antumbra just
        // reaches the Earth), gamma, magnitude.
        let rows = """
        2029 Jan 14 | 17:13:48 | 77 | P | 1.0553 | 0.8714
        2029 Jun 12 | 04:06:13 | 77 | P | 1.2943 | 0.4576
        2029 Jul 11 | 15:37:19 | 77 | P | -1.4191 | 0.2303
        2029 Dec 05 | 15:03:58 | 77 | P | -1.0609 | 0.8911
        2030 Jun 01 | 06:29:13 | 78 | A | 0.5626 | 0.9443
        2030 Nov 25 | 06:51:37 | 78 | T | -0.3867 | 1.0468
        2031 May 21 | 07:16:04 | 78 | A | -0.1970 | 0.9589
        2031 Nov 14 | 21:07:31 | 79 | H | 0.3078 | 1.0106
        2032 May 09 | 13:26:42 | 79 | A | -0.9375 | 0.9957
        2032 Nov 03 | 05:34:13 | 79 | P | 1.0643 | 0.8554
        2033 Mar 30 | 18:02:36 | 80 | T | 0.9778 | 1.0462
        2033 Sep 23 | 13:54:31 | 80 | P | -1.1583 | 0.6890
        2034 Mar 20 | 10:18:45 | 80 | T | 0.2894 | 1.0458
        2034 Sep 12 | 16:19:28 | 81 | A | -0.3936 | 0.9736
        2035 Mar 09 | 23:05:54 | 81 | A | -0.4368 | 0.9919
        2035 Sep 02 | 01:56:46 | 81 | T | 0.3727 | 1.0320
        2036 Feb 27 | 04:46:49 | 82 | P | -1.1942 | 0.6286
        2036 Jul 23 | 10:32:06 | 82 | P | -1.4250 | 0.1991
        2036 Aug 21 | 17:25:45 | 82 | P | 1.0825 | 0.8622
        2037 Jan 16 | 09:48:55 | 82 | P | 1.1477 | 0.7049
        2037 Jul 13 | 02:40:36 | 83 | T | -0.7246 | 1.0413
        2038 Jan 05 | 13:47:11 | 83 | A | 0.4169 | 0.9728
        2038 Jul 02 | 13:32:55 | 84 | A | 0.0398 | 0.9911
        2038 Dec 26 | 01:00:10 | 84 | T | -0.2881 | 1.0268
        2039 Jun 21 | 17:12:54 | 84 | A | 0.8312 | 0.9454
        2039 Dec 15 | 16:23:46 | 85 | T | -0.9458 | 1.0356
        2040 May 11 | 03:43:02 | 85 | P | -1.2529 | 0.5306
        2040 Nov 04 | 19:09:02 | 85 | P | 1.0993 | 0.8074
        2041 Apr 30 | 11:52:21 | 86 | T | -0.4492 | 1.0189
        2041 Oct 25 | 01:36:22 | 86 | A | 0.4133 | 0.9467
        2042 Apr 20 | 02:17:30 | 86 | T | 0.2956 | 1.0614
        2042 Oct 14 | 02:00:42 | 87 | A | -0.3030 | 0.9300
        2043 Apr 09 | 18:57:49 | 87 | T+ | 1.0031 | 1.0095
        2043 Oct 03 | 03:01:49 | 88 | A- | -1.0102 | 0.9497
        2044 Feb 28 | 20:24:39 | 88 | As | -0.9954 | 0.9600
        2044 Aug 23 | 01:17:02 | 88 | T | 0.9613 | 1.0364
        2045 Feb 16 | 23:56:07 | 89 | A | -0.3125 | 0.9285
        2045 Aug 12 | 17:42:39 | 89 | T | 0.2116 | 1.0774
        """.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        XCTAssertEqual(rows.count, 38)
        for row in rows {
            let fields = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let date = fields[0].split(separator: " ").map(String.init)
            let month = (months.firstIndex(of: date[1]) ?? 0) + 1
            let iso = "\(date[0])-\(String(format: "%02d", month))-\(date[2])T\(fields[1])Z"
            let greatest = Support.utc(iso).addingTimeInterval(-(Double(fields[2]) ?? 0))
            let found = SolarEclipseFinder.events(from: greatest.addingTimeInterval(-3 * 86_400),
                                                  to: greatest.addingTimeInterval(3 * 86_400))
            XCTAssertEqual(found.count, 1, row)
            guard let eclipse = Support.solarEclipses(found).first?.1 else { continue }
            let expectedKind: SolarEclipseKind = switch fields[3].first {
            case "P": .partial
            case "A": .annular
            case "H": .hybrid
            default: .total
            }
            XCTAssertEqual(eclipse.kind, expectedKind, row)
            XCTAssertTrue(abs(Support.seconds(eclipse.greatest, greatest)) < 45, "\(row) greatest")
            Support.assertNear(Double(fields[4]) ?? .nan, eclipse.gamma, tolerance: 0.003, "\(row) gamma")
            Support.assertNear(Double(fields[5]) ?? .nan, eclipse.greatestMagnitude,
                               tolerance: expectedKind == .partial ? 0.007 : 0.005, "\(row) magnitude")
            // The global flag: the axis of the shadow touches the Earth unless the catalog marks the eclipse non-central.
            XCTAssertEqual(eclipse.isCentral,
                           expectedKind != .partial && !fields[3].hasSuffix("+") && !fields[3].hasSuffix("-"), row)
        }
    }

    func testCentralFlagMarksEclipsesThatReachTheGround() {
        for entry in catalog {
            guard let eclipse = eclipses("\(entry.date)T00:00:00Z", "\(entry.date)T23:59:59Z").first else {
                XCTFail(entry.date)
                continue
            }
            XCTAssertEqual(eclipse.isCentral, entry.kind != .partial, entry.date)
        }
    }

    func testEveryEclipseOf2025To2028IsFound() {
        // NASA catalog: 2025 two partial eclipses, 2026 two, 2027 two, 2028 two (annular January, total July).
        XCTAssertEqual(eclipses("2025-01-01T00:00:00Z", "2025-12-31T23:59:59Z").count, 2)
        XCTAssertEqual(eclipses("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z").count, 2)
        XCTAssertEqual(eclipses("2027-01-01T00:00:00Z", "2027-12-31T23:59:59Z").count, 2)
        XCTAssertEqual(eclipses("2028-01-01T00:00:00Z", "2028-12-31T23:59:59Z").count, 2)
    }

    private func local(_ date: String, _ site: Support.Site) -> LocalSolarCircumstances? {
        let day = Support.utc("\(date)T12:00:00Z")
        let events = SolarEclipseFinder.events(from: day.addingTimeInterval(-86_400), to: day.addingTimeInterval(86_400),
                                               observer: site.observer)
        XCTAssertEqual(events.count, 1, "\(date) \(site.name)")
        guard let eclipse = Support.solarEclipses(events).first?.1 else { return nil }
        XCTAssertNotNil(eclipse.local, "\(date) \(site.name)")
        return eclipse.local
    }

    func testTotalityAtDallasOn2024April8() throws {
        // USNO: Dallas 32.7767N 96.7970W 150 m: first contact 17:23:14.6 UT (12:23 CDT), totality 18:40:37.7 to
        // 18:44:30.2 (13:40–13:44 CDT; 3m 52.5s), maximum 18:42:33.0, last contact 20:02:35.7; magnitude 1.015,
        // obscuration 100 %, Sun at altitude 64.6° and azimuth 188.0° at maximum.
        let circumstances = try XCTUnwrap(local("2024-04-08", Support.dallas))
        XCTAssertEqual(circumstances.kind, .total)
        Support.assertInstant("2024-04-08T17:23:14Z", circumstances.c1, tolerance: 45, "C1")
        Support.assertInstant("2024-04-08T18:40:38Z", circumstances.c2, tolerance: 45, "C2")
        Support.assertInstant("2024-04-08T18:42:33Z", circumstances.maximum, tolerance: 45, "maximum")
        Support.assertInstant("2024-04-08T18:44:30Z", circumstances.c3, tolerance: 45, "C3")
        Support.assertInstant("2024-04-08T20:02:36Z", circumstances.c4, tolerance: 45, "C4")
        Support.assertNear(232.5, circumstances.centralDuration, tolerance: 15, "duration of totality")
        Support.assertNear(1.015, circumstances.magnitude, tolerance: 0.005, "magnitude")
        XCTAssertEqual(circumstances.obscuration, 1.0)
        Support.assertNear(64.6, try XCTUnwrap(circumstances.sunAltitude), tolerance: 0.3, "Sun altitude")
        Support.assertNear(188.0, try XCTUnwrap(circumstances.sunAzimuth), tolerance: 0.3, "Sun azimuth")
        let visible = try XCTUnwrap(circumstances.visibleInterval)
        XCTAssertTrue(abs(Support.seconds(visible.start, try XCTUnwrap(circumstances.c1))) < 0.01)
        XCTAssertTrue(abs(Support.seconds(visible.end, try XCTUnwrap(circumstances.c4))) < 0.01)
    }

    func testTotalityAtBurgosOn2026August12() throws {
        // USNO: Burgos 42.3439N 3.6969W 860 m: first contact 17:33:19.3 UT, totality 18:28:20.4 to 18:30:06.7
        // (20:28–20:30 CEST; 1m 46.3s), maximum 18:29:12.7, magnitude 1.014, Sun at altitude 8.2°, azimuth 282.6°;
        // sunset 19:20 UT.
        let circumstances = try XCTUnwrap(local("2026-08-12", Support.burgos))
        XCTAssertEqual(circumstances.kind, .total)
        Support.assertInstant("2026-08-12T17:33:19Z", circumstances.c1, tolerance: 45, "C1")
        Support.assertInstant("2026-08-12T18:28:20Z", circumstances.c2, tolerance: 45, "C2")
        Support.assertInstant("2026-08-12T18:29:13Z", circumstances.maximum, tolerance: 45, "maximum")
        Support.assertInstant("2026-08-12T18:30:07Z", circumstances.c3, tolerance: 45, "C3")
        Support.assertNear(106.3, circumstances.centralDuration, tolerance: 8, "duration of totality")
        Support.assertNear(1.014, circumstances.magnitude, tolerance: 0.005, "magnitude")
        Support.assertNear(8.2, try XCTUnwrap(circumstances.sunAltitude), tolerance: 0.3, "Sun altitude")
        Support.assertNear(282.6, try XCTUnwrap(circumstances.sunAzimuth), tolerance: 0.3, "Sun azimuth")
        // The eclipse ends (C4 19:21 UT) a little after the Sun sets (19:20), so the visible part is cut off.
        XCTAssertTrue(try XCTUnwrap(circumstances.c4) >= (try XCTUnwrap(circumstances.visibleInterval)).end)
    }

    func testTotalityAtLuxorOn2027August2() throws {
        // JPL Horizons (see the class comment): C1 08:40:19.4, C2 10:02:05.7, maximum 10:05:18.5, C3 10:08:30.6 (6m 24.8s),
        // C4 11:26:32.9 UT; Sun altitude about 82°.
        let circumstances = try XCTUnwrap(local("2027-08-02", Support.luxor))
        XCTAssertEqual(circumstances.kind, .total)
        Support.assertInstant("2027-08-02T08:40:19Z", circumstances.c1, tolerance: 45, "C1")
        Support.assertInstant("2027-08-02T10:02:06Z", circumstances.c2, tolerance: 45, "C2")
        Support.assertInstant("2027-08-02T10:05:19Z", circumstances.maximum, tolerance: 45, "maximum")
        Support.assertInstant("2027-08-02T10:08:31Z", circumstances.c3, tolerance: 45, "C3")
        Support.assertInstant("2027-08-02T11:26:33Z", circumstances.c4, tolerance: 45, "C4")
        Support.assertNear(384.8, circumstances.centralDuration, tolerance: 15, "duration of totality")
        Support.assertNear(82.0, try XCTUnwrap(circumstances.sunAltitude), tolerance: 0.5, "Sun altitude")
    }

    func testPartialEclipseAtNewYorkOn2024April8() throws {
        // USNO: New York 40.7128N 74.0060W 10 m: begins 18:10:32.3 UT, maximum 19:25:30.1, ends 20:36:19.3;
        // magnitude 0.911, obscuration 89.9 %, Sun at altitude 43.4°, azimuth 235.1° at maximum.
        let circumstances = try XCTUnwrap(local("2024-04-08", Support.newYork))
        XCTAssertEqual(circumstances.kind, .partial)
        Support.assertInstant("2024-04-08T18:10:32Z", circumstances.c1, tolerance: 45, "C1")
        Support.assertInstant("2024-04-08T19:25:30Z", circumstances.maximum, tolerance: 45, "maximum")
        Support.assertInstant("2024-04-08T20:36:19Z", circumstances.c4, tolerance: 45, "C4")
        XCTAssertNil(circumstances.c2)
        XCTAssertNil(circumstances.c3)
        XCTAssertEqual(circumstances.centralDuration, 0)
        Support.assertNear(0.911, circumstances.magnitude, tolerance: 0.002, "magnitude")
        Support.assertNear(0.899, circumstances.obscuration, tolerance: 0.002, "obscuration")
        Support.assertNear(43.4, try XCTUnwrap(circumstances.sunAltitude), tolerance: 0.3, "Sun altitude")
        Support.assertNear(235.1, try XCTUnwrap(circumstances.sunAzimuth), tolerance: 0.3, "Sun azimuth")
    }

    func testAnnularEclipseAtAlbuquerqueOn2023October14() throws {
        // USNO: Albuquerque 35.0844N 106.6504W 1600 m: begins 15:13:11.5 UT, annularity 16:34:29.8 to 16:39:16.9
        // (4m 47.1s), maximum 16:36:52.4, ends 18:09:21.9; magnitude 0.970, obscuration 89.7 %, Sun at 36.1°, 136.8°.
        let circumstances = try XCTUnwrap(local("2023-10-14", Support.albuquerque))
        XCTAssertEqual(circumstances.kind, .annular)
        Support.assertInstant("2023-10-14T15:13:12Z", circumstances.c1, tolerance: 45, "C1")
        Support.assertInstant("2023-10-14T16:34:30Z", circumstances.c2, tolerance: 45, "C2")
        Support.assertInstant("2023-10-14T16:36:52Z", circumstances.maximum, tolerance: 45, "maximum")
        Support.assertInstant("2023-10-14T16:39:17Z", circumstances.c3, tolerance: 45, "C3")
        Support.assertInstant("2023-10-14T18:09:22Z", circumstances.c4, tolerance: 45, "C4")
        Support.assertNear(287.1, circumstances.centralDuration, tolerance: 15, "duration of annularity")
        Support.assertNear(0.970, circumstances.magnitude, tolerance: 0.003, "magnitude")
        Support.assertNear(0.897, circumstances.obscuration, tolerance: 0.003, "obscuration")
        Support.assertNear(36.1, try XCTUnwrap(circumstances.sunAltitude), tolerance: 0.3, "Sun altitude")
        Support.assertNear(136.8, try XCTUnwrap(circumstances.sunAzimuth), tolerance: 0.3, "Sun azimuth")
    }

    func testPartialEclipsesOf2026August12() throws {
        // USNO, 2026-08-12 (UT): London 51.5074N 0.1278W: begins 17:17:16.5, maximum 18:13:15.6 (magnitude 0.925,
        // obscuration 91.4 %, Sun at 10.3°, 280.8°), ends 19:06:16.4. Canary Islands 28N 15W: begins 17:58:34.1,
        // maximum 18:53:44.9, magnitude 0.755, obscuration 69.9 %. Madrid 40.4168N 3.7038W: begins 17:36:42.4, maximum
        // 18:32:18.5, magnitude 0.999 (just outside the path of totality), the eclipse ends after sunset.
        let london = try XCTUnwrap(local("2026-08-12", Support.london))
        XCTAssertEqual(london.kind, .partial)
        Support.assertInstant("2026-08-12T17:17:16Z", london.c1, tolerance: 45, "London C1")
        Support.assertInstant("2026-08-12T18:13:16Z", london.maximum, tolerance: 45, "London maximum")
        Support.assertInstant("2026-08-12T19:06:16Z", london.c4, tolerance: 45, "London C4")
        Support.assertNear(0.925, london.magnitude, tolerance: 0.002, "London magnitude")
        Support.assertNear(0.914, london.obscuration, tolerance: 0.002, "London obscuration")
        Support.assertNear(10.3, try XCTUnwrap(london.sunAltitude), tolerance: 0.3, "London Sun altitude")
        Support.assertNear(280.8, try XCTUnwrap(london.sunAzimuth), tolerance: 0.3, "London Sun azimuth")

        let canary = try XCTUnwrap(local("2026-08-12", Support.canaryIslands))
        XCTAssertEqual(canary.kind, .partial)
        Support.assertInstant("2026-08-12T17:58:34Z", canary.c1, tolerance: 45, "Canary C1")
        Support.assertInstant("2026-08-12T18:53:45Z", canary.maximum, tolerance: 45, "Canary maximum")
        Support.assertNear(0.755, canary.magnitude, tolerance: 0.002, "Canary magnitude")
        Support.assertNear(0.699, canary.obscuration, tolerance: 0.002, "Canary obscuration")

        let madrid = try XCTUnwrap(local("2026-08-12", Support.madrid))
        XCTAssertEqual(madrid.kind, .partial)
        Support.assertInstant("2026-08-12T17:36:42Z", madrid.c1, tolerance: 45, "Madrid C1")
        Support.assertInstant("2026-08-12T18:32:18Z", madrid.maximum, tolerance: 45, "Madrid maximum")
        Support.assertNear(0.999, madrid.magnitude, tolerance: 0.001, "Madrid magnitude")
        XCTAssertTrue(madrid.obscuration > 0.999)
        XCTAssertNil(madrid.c2)
        XCTAssertTrue(try XCTUnwrap(madrid.c4) > (try XCTUnwrap(madrid.visibleInterval)).end, "the Sun sets before the eclipse ends")
    }

    func testEclipseInProgressAtSunsetAndNoEclipseAtAll() throws {
        // USNO 2026-02-17 at 66.5S 110.5E: begins 11:05:41.4 UT, maximum 12:04:54.0 (magnitude 0.947, obscuration
        // 91.3 %, Sun at 3.8°), sunset 12:57 before the eclipse ends. Buenos Aires (2026-02-17) and Tokyo (2024-04-08):
        // "Eclipse not visible from selected location".
        let antarctic = try XCTUnwrap(local("2026-02-17", Support.antarctica))
        XCTAssertEqual(antarctic.kind, .partial)
        Support.assertInstant("2026-02-17T11:05:41Z", antarctic.c1, tolerance: 45, "Antarctic C1")
        Support.assertInstant("2026-02-17T12:04:54Z", antarctic.maximum, tolerance: 45, "Antarctic maximum")
        Support.assertNear(0.947, antarctic.magnitude, tolerance: 0.003, "Antarctic magnitude")
        Support.assertNear(3.8, try XCTUnwrap(antarctic.sunAltitude), tolerance: 0.3, "Antarctic Sun altitude")
        let sunset = try XCTUnwrap(antarctic.visibleInterval).end
        Support.assertInstant("2026-02-17T12:57:00Z", sunset, tolerance: 120, "sunset")
        XCTAssertTrue(try XCTUnwrap(antarctic.c4) > sunset)

        let buenosAires = try XCTUnwrap(local("2026-02-17", Support.buenosAires))
        XCTAssertEqual(buenosAires.kind, .none)
        XCTAssertNil(buenosAires.c1)
        XCTAssertNil(buenosAires.maximum)
        XCTAssertNil(buenosAires.visibleInterval)
        XCTAssertEqual(buenosAires.magnitude, 0)

        // Tokyo: the Moon does cross the Sun's disc a little at 17:50 UT, but the Sun is far below the horizon
        // (it is 02:50 JST), so nothing is seen.
        let tokyo = try XCTUnwrap(local("2024-04-08", Support.tokyo))
        XCTAssertEqual(tokyo.kind, .none)
        XCTAssertNil(tokyo.visibleInterval)
        XCTAssertTrue(try XCTUnwrap(tokyo.sunAltitude) < -20)
    }

    func testLocalCircumstancesFunctionMatchesTheFinder() throws {
        let global = try XCTUnwrap(eclipses("2024-04-08T00:00:00Z", "2024-04-08T23:59:59Z").first)
        let direct = SolarEclipseFinder.localCircumstances(of: global, observer: Support.dallas.observer)
        XCTAssertEqual(local("2024-04-08", Support.dallas), direct)
    }

    func testSolarEclipseVisibilityHasContactsAndWindow() throws {
        let options = EventOptions(kinds: [.solarEclipse])
        let events = EventCalculator.events(from: Support.utc("2024-04-08T00:00:00Z"), to: Support.utc("2024-04-08T23:59:59Z"),
                                            observer: Support.dallas.observer, options: options)
        XCTAssertEqual(events.count, 1)
        let visibility = try XCTUnwrap(events.first?.visibility)
        XCTAssertEqual(visibility.contacts.map(\.contact), [.c1, .c2, .maximum, .c3, .c4])
        XCTAssertTrue(visibility.contacts.allSatisfy { $0.altitude > 50 })
        XCTAssertTrue(!visibility.isDark)
        let window = try XCTUnwrap(visibility.bestWindow)
        let circumstances = try XCTUnwrap(Support.solarEclipses(events).first?.1.local)
        XCTAssertEqual(circumstances.visibleInterval, window)
        XCTAssertEqual(circumstances.maximum, visibility.bestTime)
        Support.assertNear(64.6, visibility.altitude, tolerance: 0.3, "altitude at maximum")
        // From Tokyo the same eclipse is not observable at all.
        let tokyo = EventCalculator.events(from: Support.utc("2024-04-08T00:00:00Z"), to: Support.utc("2024-04-08T23:59:59Z"),
                                           observer: Support.tokyo.observer, options: options)
        XCTAssertTrue(try !XCTUnwrap(tokyo.first?.visibility).isObservable)
    }

    func testObscurationOfOverlappingDiscs() {
        // Limiting cases, then two equal discs a radius apart: the lens has area (2·acos(1/2) - sqrt(3)/2) r² =
        // (2π/3 - √3/2) r², i.e. a fraction 2/3 - √3/(2π) = 0.39100 of the disc.
        XCTAssertEqual(DiscOverlap.obscuration(sunRadius: 1, moonRadius: 1, separation: 2), 0)
        XCTAssertEqual(DiscOverlap.obscuration(sunRadius: 1, moonRadius: 0.9, separation: 3), 0)
        XCTAssertEqual(DiscOverlap.obscuration(sunRadius: 1, moonRadius: 1.05, separation: 0), 1)
        XCTAssertEqual(DiscOverlap.obscuration(sunRadius: 1, moonRadius: 1.05, separation: 0.04), 1)
        XCTAssertEqual(DiscOverlap.obscuration(sunRadius: 1, moonRadius: 0.9, separation: 0.05), 0.9 * 0.9, accuracy: 1e-15)
        XCTAssertEqual(DiscOverlap.obscuration(sunRadius: 1, moonRadius: 1, separation: 1),
                       2.0 / 3 - 3.0.squareRoot() / (2 * Double.pi), accuracy: 1e-12)
        // The magnitude: half the Sun's diameter covered when the Moon's edge reaches the Sun's centre.
        XCTAssertEqual(DiscOverlap.magnitude(sunRadius: 1, moonRadius: 1, separation: 1), 0.5, accuracy: 1e-15)
        XCTAssertEqual(DiscOverlap.magnitude(sunRadius: 1, moonRadius: 0.9, separation: 5), 0)
        XCTAssertEqual(DiscOverlap.magnitude(sunRadius: 1, moonRadius: 1.1, separation: 0), 1.05, accuracy: 1e-15)
    }

    func testPartialSiteObscurationIsBelowTheMagnitudeInDiameter() throws {
        // For a partial eclipse the area covered is less than the share of the diameter covered (0.899 against 0.911).
        let circumstances = try XCTUnwrap(local("2024-04-08", Support.newYork))
        XCTAssertTrue(circumstances.obscuration < circumstances.magnitude)
        XCTAssertTrue(circumstances.obscuration > 0.5)
    }
}
