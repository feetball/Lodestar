import XCTest
@testable import LodestarKit

/// Compares passes, looks and shadow transitions with Skyfield 1.55 (SGP4 from the `sgp4` package, JPL DE421,
/// IAU 2000 frames, `is_sunlit` with a point-source Sun), computed by `Tools/make_satellite_fixtures.py passes`
/// from the CelesTrak GP snapshot of 2026-10-18 in `satellite_omm_sample.json`. Skyfield shares no code with
/// LodestarKit. Differences in the models: LodestarKit takes UT1 equal to UTC and ignores polar motion; Skyfield
/// uses its UT1 - UTC table (0.09 s here) and the full TEME rotation.
final class SatelliteReferenceTests: XCTestCase {
    private typealias Support = SatelliteTestSupport

    private func observer(_ reference: [String: Any], _ siteId: String) throws -> Observer {
        let sites = try XCTUnwrap(reference["sites"] as? [String: Any])
        let site = try XCTUnwrap(sites[siteId] as? [String: Any])
        return Support.observer(Support.number(site, "latitude"), Support.number(site, "longitude"), Support.number(site, "elevation"))
    }

    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360.0)
        return difference > 180.0 ? 360.0 - difference : difference
    }

    func testPassesMatchSkyfield() throws {
        let reference = try Support.jsonObject("satellite_reference.json")
        let satellites = try Support.referenceSatellites()
        var worstTime = 0.0
        var worstLongTime = 0.0
        var worstAltitude = 0.0
        var worstAzimuth = 0.0
        var worstVisible = 0.0
        var comparedPasses = 0
        var comparedVisible = 0
        for testCase in Support.list(reference, "cases") {
            let id = Support.text(testCase, "satellite")
            let site = Support.text(testCase, "site")
            let label = "\(id) at \(site)"
            let start = Support.number(testCase, "start")
            let end = Support.number(testCase, "end")
            let finder = SatellitePassFinder(
                observer: try observer(reference, site),
                interval: DateInterval(start: Support.date(start), end: Support.date(end)),
                minimumAltitude: Support.number(testCase, "minimumAltitude"),
                darknessSunAltitude: Support.number(testCase, "darknessSunAltitude")
            )
            let found = finder.passes(of: try XCTUnwrap(satellites[id]))
            let complete = found.filter { !$0.isRiseCut && !$0.isSetCut }
            let expected = Support.list(testCase, "passes")
            XCTAssertEqual(complete.count, expected.count, "\(label): number of complete passes")
            for (pass, truth) in zip(complete, expected) {
                let rise = Support.number(truth, "rise")
                let culmination = Support.number(truth, "culmination")
                let set = Support.number(truth, "set")
                // A pass that lasts hours (a geosynchronous or Molniya orbit) has altitude rates of 0.01 degrees
                // per second and less, so the same altitude error shifts its times by seconds.
                let long = set - rise > 3_600.0
                let differences = max(
                    abs(pass.rise.date.timeIntervalSince1970 - rise),
                    max(abs(pass.culmination.date.timeIntervalSince1970 - culmination), abs(pass.set.date.timeIntervalSince1970 - set))
                )
                if long { worstLongTime = max(worstLongTime, differences) } else { worstTime = max(worstTime, differences) }
                worstAltitude = max(worstAltitude, abs(pass.culmination.altitude - Support.number(truth, "culminationAltitude")))
                // Near the zenith the azimuth is ill-conditioned: compare directions.
                let culminationTruth = HorizontalCoordinate(azimuth: Support.number(truth, "culminationAzimuth"), altitude: Support.number(truth, "culminationAltitude"))
                worstAzimuth = max(worstAzimuth, pass.culmination.horizontal.angularSeparation(to: culminationTruth))
                worstAzimuth = max(worstAzimuth, angleDifference(pass.rise.azimuth, Support.number(truth, "riseAzimuth")))
                worstAzimuth = max(worstAzimuth, angleDifference(pass.set.azimuth, Support.number(truth, "setAzimuth")))
                let visible = (truth["visible"] as? [[NSNumber]] ?? []).map { $0.map(\.doubleValue) }
                XCTAssertEqual(pass.visibleIntervals.count, visible.count, "\(label): visible parts of the pass at \(rise)")
                for (interval, edges) in zip(pass.visibleIntervals, visible) {
                    worstVisible = max(worstVisible, abs(interval.start.timeIntervalSince1970 - edges[0]))
                    worstVisible = max(worstVisible, abs(interval.end.timeIntervalSince1970 - edges[1]))
                    comparedVisible += 1
                }
                comparedPasses += 1
            }
        }
        print("passes: \(comparedPasses) compared, worst time \(worstTime) s (long passes \(worstLongTime) s), altitude \(worstAltitude) deg, azimuth \(worstAzimuth) deg; \(comparedVisible) visible parts, worst edge \(worstVisible) s")
        XCTAssertGreaterThanOrEqual(comparedPasses, 90)
        XCTAssertGreaterThanOrEqual(comparedVisible, 25)
        XCTAssertLessThan(worstTime, 0.5, "worst time difference")
        XCTAssertLessThan(worstLongTime, 2.0, "worst time difference of the long passes")
        XCTAssertLessThan(worstAltitude, 0.01, "worst culmination altitude difference")
        XCTAssertLessThan(worstAzimuth, 0.02, "worst direction difference")
        XCTAssertLessThan(worstVisible, 1.0, "worst visible edge difference")
    }

    func testLooksMatchSkyfield() throws {
        let reference = try Support.jsonObject("satellite_reference.json")
        let satellites = try Support.referenceSatellites()
        var worstAngle = 0.0
        var worstRange = 0.0
        var worstRate = 0.0
        var sunlitMismatches = 0
        var worstSun = 0.0
        let looks = Support.list(reference, "looks")
        for truth in looks {
            let id = Support.text(truth, "satellite")
            let site = Support.text(truth, "site")
            let time = Support.number(truth, "time")
            let look = try XCTUnwrap(try XCTUnwrap(satellites[id]).look(at: Support.date(time), observer: observer(reference, site)), "\(id) at \(site)")
            let expected = HorizontalCoordinate(azimuth: Support.number(truth, "azimuth"), altitude: Support.number(truth, "altitude"))
            worstAngle = max(worstAngle, look.horizontal.angularSeparation(to: expected))
            worstRange = max(worstRange, abs(look.rangeKilometers - Support.number(truth, "rangeKilometers")))
            worstRate = max(worstRate, abs(look.rangeRateKilometersPerSecond - Support.number(truth, "rangeRateKilometersPerSecond")))
            worstSun = max(worstSun, abs(look.sunAltitude - Support.number(truth, "sunAltitude")))
            if look.isSunlit != Support.boolean(truth, "isSunlit") { sunlitMismatches += 1 }
        }
        print("looks: \(looks.count) compared, worst angle \(worstAngle) deg, range \(worstRange) km, range rate \(worstRate) km/s, Sun altitude \(worstSun) deg, sunlit mismatches \(sunlitMismatches)")
        XCTAssertEqual(looks.count, 50)
        XCTAssertEqual(sunlitMismatches, 0)
        XCTAssertLessThan(worstAngle, 0.01, "worst direction difference")
        XCTAssertLessThan(worstRange, 0.5, "worst range difference")
        XCTAssertLessThan(worstRate, 0.001, "worst range-rate difference")
        XCTAssertLessThan(worstSun, 0.02, "worst Sun altitude difference")
    }

    func testEarthShadowTransitionsMatchSkyfield() throws {
        let reference = try Support.jsonObject("satellite_reference.json")
        let satellites = try Support.referenceSatellites()
        var worst = 0.0
        var compared = 0
        for entry in Support.list(reference, "shadowTransitions") {
            let satellite = try XCTUnwrap(satellites[Support.text(entry, "satellite")])
            let propagator = satellite.propagator
            for transition in Support.list(entry, "transitions") {
                let time = Support.number(transition, "time")
                let enters = Support.boolean(transition, "entersSunlight")
                // Bisect our own half-illumination crossing between 20 s before and 20 s after Skyfield's.
                func lit(_ t: Double) -> Bool {
                    let date = Support.date(t)
                    guard let state = propagator.state(at: date).state else { return false }
                    return EarthShadow.isSunlit(satellite: state.position, sun: SatelliteFrames.sunPosition(at: date))
                }
                XCTAssertEqual(lit(time - 20.0), !enters, "\(satellite.name) before the transition at \(time)")
                XCTAssertEqual(lit(time + 20.0), enters, "\(satellite.name) after the transition at \(time)")
                var low = time - 20.0
                var high = time + 20.0
                while high - low > 0.001 {
                    let middle = 0.5 * (low + high)
                    if lit(middle) == enters { high = middle } else { low = middle }
                }
                worst = max(worst, abs(0.5 * (low + high) - time))
                compared += 1
            }
        }
        print("shadow: \(compared) transitions compared, worst difference \(worst) s")
        XCTAssertGreaterThanOrEqual(compared, 12)
        XCTAssertLessThan(worst, 0.5, "worst shadow transition difference")
    }
}
