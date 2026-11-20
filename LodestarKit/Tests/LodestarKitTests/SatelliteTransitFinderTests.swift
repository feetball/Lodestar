import XCTest
@testable import LodestarKit

/// `SatelliteTransitFinder` against an independent reference. The ISS element set is the CelesTrak TLE of 2026-11-19
/// (`satellite_iss_transit.tle`). The expected transits for Boulder in the 14 days from 2026-11-19T17:00Z come from
/// `Tools/make_satellite_transit_reference.py` (a brute-force Skyfield 1.55 + DE440s search that shares no code with
/// the kit):
///
///     2026-11-23T20:33:23.62Z  Sun   centreline 23150.6 m @ 357.5°
///     2026-11-24T03:05:37.61Z  Moon   centreline 15707.9 m @ 230.2°
///     2026-11-25T02:17:56.29Z  Moon   centreline 40162.7 m @ 241.9°
///
/// The other checks use only the kit's own public pieces (`Satellite.look`, `SkyFrame`) to measure the separation.
/// (Kotlin: `SatelliteTransitFinderTests.kt`.)
final class SatelliteTransitFinderTests: XCTestCase {
    private typealias Support = SatelliteTestSupport
    private let boulder = SatelliteTestSupport.boulder
    private let from = SatelliteTestSupport.iso("2026-11-19T17:00:00Z")
    private var to: Date { from.addingTimeInterval(14 * 86_400) }

    private static let timeTolerance = 0.25
    private static let distanceTolerance = 500.0
    private static let bearingTolerance = 1.0

    private func satellite() throws -> Satellite {
        let batch = try ElementSetParser.parseTwoLineText(Support.fixtureText("satellite_iss_transit.tle"))
        XCTAssertEqual(batch.elements.count, 1)
        return Satellite(elements: try XCTUnwrap(batch.elements.first))
    }

    private func transits(_ body: SolarSystemBody, observer: Observer? = nil, maxGround: Double = 50_000) throws -> [SatelliteTransit] {
        SatelliteTransitFinder.transits(
            satellite: try satellite(), body: body, observer: observer ?? boulder, from: from, to: to,
            maxGroundDistanceMeters: maxGround
        )
    }

    private func allTransits() throws -> [SatelliteTransit] {
        (try transits(.sun) + transits(.moon)).sorted { $0.date < $1.date }
    }

    private func allTransitsWithin(_ maxGround: Double) throws -> [SatelliteTransit] {
        try transits(.sun, maxGround: maxGround) + transits(.moon, maxGround: maxGround)
    }

    /// The angle between the satellite and the body's centre from the kit's own `look` and `SkyFrame`, in degrees.
    private func separation(_ body: SolarSystemBody, _ observer: Observer, _ date: Date) throws -> Double {
        let look = try XCTUnwrap(try satellite().look(at: date, observer: observer))
        let direction = SkyFrame(date: date, observer: observer).horizontal(of: body, refraction: false)
        return look.direction.angle(to: direction.unitVector)
    }

    func testSatelliteSpanTable() {
        XCTAssertEqual(SatelliteTransitFinder.satelliteSpanMeters(catalogNumber: 25544), 109.0)
        XCTAssertEqual(SatelliteTransitFinder.satelliteSpanMeters(catalogNumber: 48274), 55.0)
        XCTAssertEqual(SatelliteTransitFinder.satelliteSpanMeters(catalogNumber: 53239), 55.0)
        XCTAssertEqual(SatelliteTransitFinder.satelliteSpanMeters(catalogNumber: 99_999), 50.0)
    }

    func testTheBoulderTransitsMatchTheSkyfieldReference() throws {
        let found = try allTransits()
        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(found.map(\.body), [.sun, .moon, .moon])
        let expected: [(String, Double, Double)] = [
            ("2026-11-23T20:33:23.62Z", 23_150.6, 357.5),
            ("2026-11-24T03:05:37.61Z", 15_707.9, 230.2),
            ("2026-11-25T02:17:56.29Z", 40_162.7, 241.9),
        ]
        for (transit, reference) in zip(found, expected) {
            // The kit takes UT1 = UTC and ignores polar motion; the two searches agree to a few milliseconds and tens of metres.
            XCTAssertEqual(
                transit.date.timeIntervalSince1970, Self.referenceTime(reference.0), accuracy: Self.timeTolerance
            )
            let centreline = try XCTUnwrap(transit.centreline)
            XCTAssertEqual(centreline.distanceMeters, reference.1, accuracy: Self.distanceTolerance)
            XCTAssertEqual(centreline.bearing, reference.2, accuracy: Self.bearingTolerance)
            XCTAssertFalse(transit.isFromSite)
            XCTAssertEqual(transit.catalogNumber, 25544)
        }
    }

    /// The time of an ISO 8601 text with fractional seconds, in seconds since 1970.
    private static func referenceTime(_ text: String) -> Double {
        let whole = SatelliteTestSupport.iso(String(text.prefix(19)) + "Z").timeIntervalSince1970
        return whole + (Double(String(text.dropFirst(19).dropLast())) ?? 0)
    }

    func testTransitsAreChronologicalAndDescribeTheirGeometry() throws {
        let found = try allTransits()
        XCTAssertEqual(found.map(\.date), found.map(\.date).sorted())
        let ground = try satellite()
        for transit in found {
            XCTAssertTrue(transit.date >= from && transit.date <= to)
            let radius: ClosedRange<Double> = transit.body == .sun ? 0.2615...0.2725 : 0.24...0.30
            XCTAssertTrue(radius.contains(transit.bodyAngularRadius), "radius \(transit.bodyAngularRadius)")
            XCTAssertEqual(
                transit.satelliteAngularSize, 109.0 / (transit.satelliteRangeKilometers * 1000.0) * 180.0 / Double.pi,
                accuracy: 1e-9
            )
            XCTAssertTrue((0.05...2.0).contains(transit.angularSpeed), "speed \(transit.angularSpeed)")
            XCTAssertGreaterThanOrEqual(transit.bodyAltitude, SatelliteTransitFinder.minimumBodyAltitude)
            XCTAssertTrue(transit.bodyAzimuth >= 0 && transit.bodyAzimuth < 360)
            XCTAssertEqual(transit.isDaylight, transit.sunAltitude > SatelliteTransitFinder.daylightSunAltitude)
            XCTAssertEqual(transit.isNight, transit.sunAltitude < SatellitePassFinder.defaultDarknessSunAltitude)
            XCTAssertFalse(transit.isDaylight && transit.isNight)
            if transit.body == .sun { XCTAssertTrue(transit.isDaylight) }
            // The body's direction is the SkyFrame's.
            let direction = SkyFrame(date: transit.date, observer: boulder).horizontal(of: transit.body, refraction: false)
            XCTAssertEqual(transit.bodyAltitude, direction.altitude, accuracy: 0.005)
            XCTAssertEqual(
                abs(AstroMath.normalizeSignedDegrees(direction.azimuth - transit.bodyAzimuth))
                    * cos(AstroMath.radians(direction.altitude)),
                0.0, accuracy: 0.005
            )
            // The satellite's direction is the kit's own look; the separation is the one the kit measures independently.
            XCTAssertEqual(transit.minimumSeparation, try separation(transit.body, boulder, transit.date), accuracy: 0.005)
            let look = try XCTUnwrap(ground.look(at: transit.date, observer: boulder))
            XCTAssertEqual(transit.satelliteRangeKilometers, look.rangeKilometers, accuracy: 1e-6)
            // The crossing of the whole disc takes diameter / speed (the centreline's speed differs by a few per cent).
            XCTAssertEqual(
                transit.centrelineDurationSeconds, 2.0 * transit.bodyAngularRadius / transit.angularSpeed,
                accuracy: 0.15 * transit.centrelineDurationSeconds
            )
            XCTAssertTrue((0.2...2.0).contains(transit.centrelineDurationSeconds), "duration \(transit.centrelineDurationSeconds)")
        }
        XCTAssertTrue(try XCTUnwrap(found.first { $0.body == .sun }).isDaylight)
    }

    func testObserverOnTheCentrelineSeesTheSatelliteCrossTheCentre() throws {
        let ground = try satellite()
        for transit in try allTransits() {
            let centreline = try XCTUnwrap(transit.centreline)
            XCTAssertLessThan(centreline.separation, 0.01)
            let moved = Observer(location: centreline.location)
            // Measured with the kit's own look and SkyFrame, not the finder.
            let measured = try separation(transit.body, moved, transit.date)
            XCTAssertLessThan(measured, 0.02, "separation \(measured)")
            // And found again from there, as a transit from the site itself, with its own centreline right there.
            let again = SatelliteTransitFinder.transits(
                satellite: ground, body: transit.body, observer: moved, from: transit.date.addingTimeInterval(-900),
                to: transit.date.addingTimeInterval(900), maxGroundDistanceMeters: 1_000
            )
            XCTAssertEqual(again.count, 1)
            let here = try XCTUnwrap(again.first)
            XCTAssertTrue(here.isFromSite)
            XCTAssertLessThan(here.minimumSeparation, 0.02, "separation \(here.minimumSeparation)")
            XCTAssertEqual(here.date.timeIntervalSince(transit.date), 0.0, accuracy: 1.0)
            XCTAssertLessThan(try XCTUnwrap(here.centreline).distanceMeters, 100.0)
        }
    }

    func testTheCrossingDurationIsTheChordOverTheAngularSpeed() throws {
        let ground = try satellite()
        for transit in try allTransits() {
            let centreline = try XCTUnwrap(transit.centreline)
            let moved = Observer(location: centreline.location)
            let again = SatelliteTransitFinder.transits(
                satellite: ground, body: transit.body, observer: moved, from: transit.date.addingTimeInterval(-900),
                to: transit.date.addingTimeInterval(900), maxGroundDistanceMeters: 0
            )
            XCTAssertEqual(again.count, 1)
            let here = try XCTUnwrap(again.first)
            // From the centreline the chord is the whole diameter.
            XCTAssertEqual(here.siteDurationSeconds, here.centrelineDurationSeconds, accuracy: 0.03 * here.centrelineDurationSeconds)
            XCTAssertEqual(
                here.siteDurationSeconds, 2.0 * here.bodyAngularRadius / here.angularSpeed,
                accuracy: 0.03 * here.siteDurationSeconds
            )
            // At the ends of the chord the satellite's centre is on the limb of the disc (measured with the kit's own pieces).
            let half = here.siteDurationSeconds / 2.0
            for sign in [-1.0, 1.0] {
                let edge = here.date.addingTimeInterval(sign * half)
                XCTAssertEqual(try separation(transit.body, moved, edge), here.bodyAngularRadius, accuracy: 0.01)
            }
            // Inside the chord the centre is inside the disc.
            XCTAssertLessThan(try separation(transit.body, moved, here.date), here.bodyAngularRadius)
        }
    }

    func testASmallerGroundDistanceKeepsTheNearerTransits() throws {
        XCTAssertEqual(try allTransitsWithin(20_000).count, 1)
        XCTAssertEqual(try allTransitsWithin(30_000).count, 2)
        XCTAssertEqual(try allTransitsWithin(45_000).count, 3)
        XCTAssertEqual(try allTransitsWithin(0).count, 0)
        // Negative and non-finite distances are made harmless; a huge one is limited to 200 km.
        XCTAssertEqual(try allTransitsWithin(-5).count, 0)
        XCTAssertEqual(try allTransitsWithin(.nan).count, 3)
        let huge = try allTransitsWithin(1.0e9)
        XCTAssertGreaterThanOrEqual(huge.count, 3)
        XCTAssertTrue(huge.allSatisfy { ($0.centreline?.distanceMeters ?? 0.0) <= SatelliteTransitFinder.maximumGroundDistanceMeters })
    }

    func testNoTransitsWhenTheBodyIsBelowTheHorizon() throws {
        let ground = try satellite()
        let passes = SatellitePassFinder(
            observer: boulder, interval: DateInterval(start: from, end: to), minimumAltitude: 3.0
        ).passes(of: ground)
        for body in [SolarSystemBody.sun, SolarSystemBody.moon] {
            // Passes with the body well below the horizon at both ends (it moves a quarter of a degree a minute).
            let withBodyDown = passes.filter { pass in
                [pass.rise.date, pass.set.date].allSatisfy {
                    SkyFrame(date: $0, observer: boulder).horizontal(of: body, refraction: false).altitude < -10.0
                }
            }
            XCTAssertGreaterThanOrEqual(withBodyDown.count, 10, "only \(withBodyDown.count) passes with the \(body) down")
            for pass in withBodyDown.prefix(10) {
                let found = SatelliteTransitFinder.transits(
                    satellite: ground, body: body, observer: boulder, from: pass.rise.date.addingTimeInterval(-300),
                    to: pass.set.date.addingTimeInterval(300), maxGroundDistanceMeters: 200_000
                )
                XCTAssertEqual(found, [])
            }
        }
    }

    func testInvalidRequestsGiveNoTransits() throws {
        let ground = try satellite()
        XCTAssertEqual(SatelliteTransitFinder.transits(satellite: ground, body: .mars, observer: boulder, from: from, to: to), [])
        XCTAssertEqual(SatelliteTransitFinder.transits(satellite: ground, body: .sun, observer: boulder, from: to, to: from), [])
        XCTAssertEqual(SatelliteTransitFinder.transits(satellite: ground, body: .sun, observer: boulder, from: from, to: from), [])
    }

    func testTheWindowIsLimitedToThirtyDays() throws {
        let found = SatelliteTransitFinder.transits(
            satellite: try satellite(), body: .moon, observer: boulder, from: from, to: from.addingTimeInterval(90 * 86_400)
        )
        let limit = from.addingTimeInterval(SatelliteTransitFinder.maximumWindowDays * 86_400)
        XCTAssertTrue(found.allSatisfy { $0.date <= limit })
    }

    func testAFourteenDaySearchOfBothBodiesIsFast() throws {
        _ = try transits(.sun)
        let begin = DispatchTime.now().uptimeNanoseconds
        _ = try allTransits()
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1.0e6
        print("ISS transits of the Sun and the Moon, 14 days: \(String(format: "%.0f", milliseconds)) ms")
        XCTAssertLessThan(milliseconds, 3_000.0)
    }

    func testTransitsBeyondTheGroundDistanceAreDropped() throws {
        let sun = try XCTUnwrap(try transits(.sun).first)
        XCTAssertNotNil(sun.centreline)
        // With a reach shorter than its centreline distance the transit is dropped, not reported without one.
        XCTAssertTrue(try transits(.sun, maxGround: 10_000).isEmpty)
        XCTAssertNil(try transits(.sun).first { $0.isFromSite })
    }
}
