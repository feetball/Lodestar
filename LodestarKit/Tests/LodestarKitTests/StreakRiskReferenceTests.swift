import XCTest
@testable import LodestarKit

/// Compares the streak-risk assessment with Skyfield: `satellite_streaks.json` lists, for five camera frames, the
/// runs in which each satellite of a synthetic constellation of 2976 element sets (the 124 Starlink records of
/// `satellite_starlink_sample.json` copied 24 times with the node moved by 15° and the mean anomaly by 37° per
/// copy, catalog number 200000 + 1000·copy + position) is inside the frame, sunlit (Skyfield's `is_sunlit`) and
/// above the horizon, found by sampling every 0.1 s (`Tools/make_satellite_fixtures.py streaks`).
final class StreakRiskReferenceTests: XCTestCase {
    private typealias Support = SatelliteTestSupport

    /// The synthetic constellation, built exactly as the generator builds it.
    private func constellation() throws -> [Satellite] {
        let base = try ElementSetParser.parseJson(Support.fixtureData("satellite_starlink_sample.json"))
        XCTAssertEqual(base.skippedCount, 0)
        XCTAssertEqual(base.elements.count, 124)
        var result: [Satellite] = []
        for copy in 0..<24 {
            for (position, element) in base.elements.enumerated() {
                let shifted = try OrbitalElements(
                    name: element.name,
                    objectId: element.objectId,
                    catalogNumber: 200_000 + 1000 * copy + position,
                    classification: element.classification,
                    epoch: element.epoch,
                    meanMotion: element.meanMotion,
                    eccentricity: element.eccentricity,
                    inclination: element.inclination,
                    rightAscensionOfAscendingNode: (element.rightAscensionOfAscendingNode + 15.0 * Double(copy)).truncatingRemainder(dividingBy: 360.0),
                    argumentOfPericenter: element.argumentOfPericenter,
                    meanAnomaly: (element.meanAnomaly + 37.0 * Double(copy)).truncatingRemainder(dividingBy: 360.0),
                    ephemerisType: element.ephemerisType,
                    elementSetNumber: element.elementSetNumber,
                    revolutionNumberAtEpoch: element.revolutionNumberAtEpoch,
                    bstar: element.bstar,
                    meanMotionDot: element.meanMotionDot,
                    meanMotionDdot: element.meanMotionDdot
                )
                result.append(Satellite(elements: shifted))
            }
        }
        return result
    }

    func testCrossingsMatchSkyfield() throws {
        let reference = try Support.jsonObject("satellite_streaks.json")
        let satellites = try constellation()
        XCTAssertEqual(Support.numbers(reference, "satellites").map { Int($0) }, satellites.map(\.catalogNumber))
        var totalCrossings = 0
        var worstTime = 0.0
        let sites = try XCTUnwrap(reference["sites"] as? [String: Any])
        for testCase in Support.list(reference, "cases") {
            let site = try XCTUnwrap(sites[Support.text(testCase, "site")] as? [String: Any])
            let observer = Support.observer(Support.number(site, "latitude"), Support.number(site, "longitude"), Support.number(site, "elevation"))
            let frame = try XCTUnwrap(CameraFrame(
                boresight: HorizontalCoordinate(azimuth: Support.number(testCase, "azimuth"), altitude: Support.number(testCase, "altitude")),
                widthDegrees: Support.number(testCase, "width"),
                heightDegrees: Support.number(testCase, "height"),
                rollDegrees: Support.number(testCase, "roll")
            ))
            let start = Support.number(testCase, "start")
            let exposure = Support.number(testCase, "exposure")
            let rateWindow = Support.number(testCase, "rateWindow")
            let options = StreakOptions(minimumAltitude: 0.0, summaryAltitude: Support.number(testCase, "summaryAltitude"), rateWindow: rateWindow)
            let assessment = StreakRisk.assess(satellites, observer: observer, frame: frame, exposure: DateInterval(start: Support.date(start), duration: exposure), options: options)
            let label = "\(Support.text(testCase, "site")) \(Support.number(testCase, "width"))x\(Support.number(testCase, "height"))"
            XCTAssertEqual(assessment.evaluatedCount, Int(Support.number(testCase, "evaluated")), "\(label): evaluated")
            XCTAssertEqual(assessment.aboveHorizonCount, Int(Support.number(testCase, "aboveHorizon")), "\(label): above the horizon")
            XCTAssertEqual(
                assessment.sunlitAboveSummaryAltitudeCount, Int(Support.number(testCase, "sunlitAboveSummaryAltitude")),
                "\(label): sunlit above the summary altitude"
            )

            let expected = Support.list(testCase, "crossings")
            // The whole window (the longer of exposure and rate window) is in the fixture: the rate counts all
            // runs, the crossing list those that touch the exposure.
            XCTAssertEqual(assessment.crossingsPerMinute, Double(expected.count) * 60.0 / rateWindow, accuracy: 1e-9, "\(label): crossings per minute")
            let inExposure = expected.filter { Support.number($0, "exit") >= start && Support.number($0, "entry") <= start + exposure }
            XCTAssertEqual(assessment.crossings.count, inExposure.count, "\(label): number of crossings in the exposure")
            var used = Set<Int>()
            for truth in inExposure {
                let number = Int(Support.number(truth, "satellite"))
                let entry = max(Support.number(truth, "entry"), start)
                let exit = min(Support.number(truth, "exit"), start + exposure)
                let matching = assessment.crossings.enumerated().first { index, crossing in
                    !used.contains(index) && crossing.satellite.catalogNumber == number
                        && abs(crossing.entry.date.timeIntervalSince1970 - entry) < 0.5
                        && abs(crossing.exit.date.timeIntervalSince1970 - exit) < 0.5
                }
                let found = try XCTUnwrap(matching, "\(label): no crossing of \(number) between \(entry) and \(exit)")
                used.insert(found.offset)
                worstTime = max(worstTime, abs(found.element.entry.date.timeIntervalSince1970 - entry))
                worstTime = max(worstTime, abs(found.element.exit.date.timeIntervalSince1970 - exit))
                totalCrossings += 1
            }
            for crossing in assessment.crossings {
                let position = try XCTUnwrap(crossing.entry.position)
                XCTAssertTrue(abs(position.x) < 1.0001 && abs(position.y) < 1.0001, "\(label): entry point on the frame")
            }
        }
        print("streaks: \(totalCrossings) crossings in 5 frames matched, worst entry/exit difference \(worstTime) s")
        XCTAssertGreaterThanOrEqual(totalCrossings, 30)
        XCTAssertLessThan(worstTime, 0.3, "worst entry/exit difference")
    }
}
