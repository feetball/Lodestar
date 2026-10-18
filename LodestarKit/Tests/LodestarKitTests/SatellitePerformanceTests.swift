import XCTest
@testable import LodestarKit

/// Timing of the expensive calls on the sizes the app uses: 100 satellites over three days, and 10 000 Starlink
/// element sets for an exposure. The limits are an order of magnitude above what a desktop needs, so they only
/// catch a regression (a phone is about three to five times slower than the desktop this was measured on); the
/// measured times are printed. (Debug builds are several times slower than release builds; the limits allow for it.)
final class SatellitePerformanceTests: XCTestCase {
    private typealias Support = SatelliteTestSupport
    private let boulder = SatelliteTestSupport.boulder
    private let start = SatelliteTestSupport.iso("2026-10-18T04:00:00Z")

    private func starlink(copies: Int) throws -> [Satellite] {
        let base = try ElementSetParser.parseJson(Support.fixtureData("satellite_starlink_sample.json")).elements
        var result: [Satellite] = []
        result.reserveCapacity(base.count * copies)
        for copy in 0..<copies {
            for (position, element) in base.enumerated() {
                let shifted = try OrbitalElements(
                    name: element.name,
                    catalogNumber: 200_000 + 1000 * copy + position,
                    epoch: element.epoch,
                    meanMotion: element.meanMotion,
                    eccentricity: element.eccentricity,
                    inclination: element.inclination,
                    rightAscensionOfAscendingNode: (element.rightAscensionOfAscendingNode + 15.0 * Double(copy)).truncatingRemainder(dividingBy: 360.0),
                    argumentOfPericenter: element.argumentOfPericenter,
                    meanAnomaly: (element.meanAnomaly + 37.0 * Double(copy)).truncatingRemainder(dividingBy: 360.0),
                    bstar: element.bstar
                )
                result.append(Satellite(elements: shifted))
            }
        }
        return result
    }

    private func milliseconds(_ block: () throws -> Void) rethrows -> Double {
        let begin = DispatchTime.now().uptimeNanoseconds
        try block()
        return Double(DispatchTime.now().uptimeNanoseconds - begin) / 1.0e6
    }

    func testTenThousandStarlinkSatellitesForOneExposure() throws {
        var satellites: [Satellite] = []
        let setup = try milliseconds { satellites = try starlink(copies: 81) }
        XCTAssertGreaterThanOrEqual(satellites.count, 10_000)
        let exposure = DateInterval(start: Support.date(1_792_373_400.0), duration: 30.0)  // 2026-10-19T01:30:00Z
        let frames = [
            CameraFrame(boresight: HorizontalCoordinate(azimuth: 200.0, altitude: 50.0), widthDegrees: 100.0, heightDegrees: 70.0),
            CameraFrame(boresight: HorizontalCoordinate(azimuth: 200.0, altitude: 50.0), widthDegrees: 20.0, heightDegrees: 13.0),
        ]
        for candidate in frames {
            let frame = try XCTUnwrap(candidate)
            var assessment: StreakAssessment?
            let elapsed = milliseconds { assessment = StreakRisk.assess(satellites, observer: boulder, frame: frame, exposure: exposure) }
            let result = try XCTUnwrap(assessment)
            print("assess \(satellites.count) satellites, \(frame.widthDegrees) deg frame: \(elapsed) ms (setup of the satellites \(setup) ms), \(result.crossings.count) crossings")
            XCTAssertEqual(result.evaluatedCount, satellites.count)
            XCTAssertLessThan(elapsed, 20_000.0, "the assessment took \(elapsed) ms")
        }
    }

    func testHundredSatellitesOverThreeDays() throws {
        let stations = try ElementSetParser.parseJson(Support.fixtureData("satellite_stations.json")).elements.map { Satellite(elements: $0) }
        let chosen = Array((try starlink(copies: 1) + stations).prefix(100))
        XCTAssertEqual(chosen.count, 100)
        let interval = DateInterval(start: start, duration: 3 * 86_400.0)
        var count = 0
        let elapsed = milliseconds {
            let finder = SatellitePassFinder(observer: boulder, interval: interval)
            for satellite in chosen { count += finder.passes(of: satellite).count }
        }
        print("passes of 100 satellites over 3 days: \(elapsed) ms, \(count) passes")
        XCTAssertGreaterThan(count, 100)
        XCTAssertLessThan(elapsed, 20_000.0, "the pass search took \(elapsed) ms")
    }
}
