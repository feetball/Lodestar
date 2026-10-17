import XCTest
@testable import LodestarKit

/// Pointing on real sky positions: apparent azimuth/altitude of bright stars computed with
/// Skyfield and JPL DE440s (see `Fixtures/README.md`), independent of LodestarKit's own astronomy.
final class PointingFixtureTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private struct Case: Decodable {
        let utc: String
        let site: String
        let star: String
        let azDeg: Double
        let altRefractedDeg: Double?

        enum CodingKeys: String, CodingKey {
            case utc, site, star
            case azDeg = "az_deg"
            case altRefractedDeg = "alt_refracted_deg"
        }

        /// The apparent (refracted) position, or `nil` below the horizon.
        var target: HorizontalCoordinate? {
            altRefractedDeg.map { HorizontalCoordinate(azimuth: azDeg, altitude: $0) }
        }
    }

    private struct Document: Decodable {
        let cases: [Case]
    }

    private func loadCases() throws -> [Case] {
        let directory = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil),
                                      "The Fixtures resource directory is missing from the test bundle.")
        let url = directory.appendingPathComponent("stars_apparent.json")
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(Document.self, from: data)
        XCTAssertGreaterThan(document.cases.count, 100, "stars_apparent.json looks truncated")
        return document.cases
    }

    func testEveryVisibleStarCanBeAimedAtWithEveryMount() throws {
        let cases = try loadCases()
        var random = PointingTestRandom(seed: 801)
        var aimed = 0
        for item in cases {
            guard let target = item.target, target.altitude > -0.5 else { continue }
            for mount in MountProfile.presets {
                let attitude = try Support.attitude(mount: mount,
                                                    frame: Support.cameraFrame(boresight: target, rollDegrees: random.uniform(-90, 90)),
                                                    referenceAzimuth: random.uniform(-20, 20))
                let solution = PointingSolution.solve(attitude: attitude, mount: mount)
                var tracker = GuidanceTracker(onTargetThreshold: 0.5)
                let guidance = try XCTUnwrap(tracker.update(solution: solution, target: target))
                XCTAssertEqual(guidance.state, .onTarget, "\(item.star) \(item.site) \(mount.id)")
                XCTAssertEqual(guidance.separation, 0, accuracy: 1e-6)
                XCTAssertEqual(guidance.targetBelowHorizon, target.altitude < 0)
                XCTAssertEqual(guidance.isNearZenith, target.altitude > Guidance.nearZenithAltitude)
            }
            aimed += 1
        }
        XCTAssertGreaterThan(aimed, 100)
    }

    func testAlignmentOnRealStarsRecoversThePointingElsewhere() throws {
        let cases = try loadCases()
        var groups = [String: [Case]]()
        for item in cases { groups["\(item.utc) \(item.site)", default: []].append(item) }
        var random = PointingTestRandom(seed: 802)
        let mount = MountProfile.backCameraLandscapeRight
        var validated = 0
        for (key, group) in groups.sorted(by: { $0.key < $1.key }) {
            let up = group.filter { ($0.altRefractedDeg ?? -1) > 8 && ($0.altRefractedDeg ?? 90) < 78 }
            guard up.count >= 4 else { continue }
            // The phone's compass is 9° off and the clamp is 1.5° out of true.
            let scenario = AlignmentTestScenario(headingOffset: 9, correction: Vector3(1.3, -0.8, 0), mount: mount)
            let aligned = try up.prefix(3).enumerated().compactMap { index, item -> AlignmentPoint? in
                guard let target = item.target else { return nil }
                return try scenario.point(target: target, roll: random.uniform(-30, 30), random: &random, index: index, name: item.star)
            }
            let model = try AlignmentModel.solve(points: aligned, mount: mount)
            XCTAssertLessThan(model.rmsResidual, 0.02, key)
            for item in up.dropFirst(3) {
                guard let target = item.target else { continue }
                let attitude = try scenario.point(target: target, roll: random.uniform(-30, 30), random: &random).attitude
                let solved = PointingSolution.solve(attitude: attitude, mount: mount, alignment: model)
                XCTAssertEqual(solved.boresight.angularSeparation(to: target), 0, accuracy: 0.1, "\(key) \(item.star)")
                validated += 1
            }
        }
        XCTAssertGreaterThan(validated, 30, "too few groups were usable")
    }
}
