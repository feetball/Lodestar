import XCTest
@testable import LodestarKit

final class HorizonProfileTests: XCTestCase {
    private typealias Support = HorizonTestSupport

    private func profile(_ altitudes: [Int: Double]) throws -> HorizonProfile {
        var values = [Double](repeating: 0, count: 360)
        for (index, altitude) in altitudes { values[index] = altitude }
        return try XCTUnwrap(HorizonProfile(altitudes: values))
    }

    private func document(_ tenths: [Int], version: Int = 1) -> String {
        "{\"version\":\(version),\"altitudeTenths\":[\(tenths.map(String.init).joined(separator: ","))]}"
    }

    private func decode(_ text: String) throws -> HorizonProfile {
        try JSONDecoder().decode(HorizonProfile.self, from: Data(text.utf8))
    }

    /// The document the tests decode: tenths `(37 i) mod 701 − 100`, a spread over the whole allowed range.
    private let patternTenths: [Int] = (0..<360).map { ($0 * 37) % 701 - 100 }

    // MARK: Altitude and interpolation

    func testFlatProfileIsFlatEverywhere() {
        let flat = HorizonProfile.flat
        XCTAssertEqual(flat.altitudes.count, 360)
        XCTAssertTrue(flat.isFlat)
        XCTAssertEqual(flat.maximumAltitude, 0)
        XCTAssertEqual(flat.minimumAltitude, 0)
        for azimuth in [0.0, 0.3, 90.0, 179.99, 359.99, -45.0, 725.5] {
            XCTAssertEqual(flat.altitude(at: azimuth), 0)
        }
        XCTAssertEqual(HorizonProfile.flat, HorizonProfile.constant(0))
    }

    func testInterpolationIsLinearBetweenWholeDegrees() throws {
        let skyline = try profile([10: 10, 11: 20, 12: 14])
        XCTAssertEqual(skyline.altitude(at: 10), 10, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: 11), 20, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: 10.5), 15, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: 10.25), 12.5, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: 11.5), 17, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: 9.5), 5, accuracy: 1e-12) // halfway between node 9 (0°) and node 10 (10°)
        XCTAssertFalse(skyline.isFlat)
        XCTAssertEqual(skyline.maximumAltitude, 20)
    }

    func testInterpolationWrapsThroughNorth() throws {
        let skyline = try profile([359: 20, 0: 10])
        XCTAssertEqual(skyline.altitude(at: 359.5), 15, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: -0.5), 15, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: 360), 10, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: -1), 20, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: 359.25), 17.5, accuracy: 1e-12)
        XCTAssertEqual(skyline.altitude(at: 719.5), 15, accuracy: 1e-12)
        // Node 358 is 0° and node 359 is 20°.
        XCTAssertEqual(skyline.altitude(at: 358.5), 10, accuracy: 1e-12)
    }

    func testAzimuthsOutsideTheCircleAreWrapped() {
        let skyline = Support.truthProfile
        for azimuth in [12.34, 90.5, 199.99, 271.0] {
            XCTAssertEqual(skyline.altitude(at: azimuth + 360), skyline.altitude(at: azimuth), accuracy: 1e-9)
            XCTAssertEqual(skyline.altitude(at: azimuth - 720), skyline.altitude(at: azimuth), accuracy: 1e-9)
        }
        // The value just below 360° and the one just below 0° are on the same side of north.
        XCTAssertEqual(skyline.altitude(at: 359.999), skyline.altitude(at: -0.001), accuracy: 1e-9)
    }

    func testNonFiniteAzimuthGivesZero() {
        let skyline = Support.truthProfile
        XCTAssertEqual(skyline.altitude(at: .nan), 0)
        XCTAssertEqual(skyline.altitude(at: .infinity), 0)
        XCTAssertEqual(skyline.altitude(at: -.infinity), 0)
    }

    // MARK: Creation and validation

    func testAltitudesAreRoundedToTenthsOfADegree() throws {
        var values = [Double](repeating: 0, count: 360)
        values[0] = 12.34
        values[1] = 12.36
        values[2] = -3.04
        values[3] = -0.04
        values[4] = 59.96
        let skyline = try XCTUnwrap(HorizonProfile(altitudes: values))
        XCTAssertEqual(skyline.altitudes[0], 12.3)
        XCTAssertEqual(skyline.altitudes[1], 12.4)
        XCTAssertEqual(skyline.altitudes[2], -3.0)
        XCTAssertEqual(skyline.altitudes[3], 0.0)
        XCTAssertEqual(skyline.altitudes[4], 60.0)
        // Zero never carries a sign, so equal profiles compare equal.
        XCTAssertEqual(1.0 / skyline.altitudes[3], Double.infinity)
        XCTAssertEqual(skyline, HorizonProfile(altitudes: skyline.altitudes))
    }

    func testCreateValidatesLengthFiniteAndRange() throws {
        XCTAssertNil(HorizonProfile(altitudes: []))
        XCTAssertNil(HorizonProfile(altitudes: [Double](repeating: 0, count: 359)))
        XCTAssertNil(HorizonProfile(altitudes: [Double](repeating: 0, count: 361)))
        for bad in [Double.nan, .infinity, -.infinity, 60.06, -10.06, 90, -90] {
            var values = [Double](repeating: 1, count: 360)
            values[200] = bad
            XCTAssertNil(HorizonProfile(altitudes: values), "\(bad)")
        }
        // The ends of the range are valid, and so are values that round into it.
        var edges = [Double](repeating: 0, count: 360)
        edges[0] = -10
        edges[1] = 60
        edges[2] = 60.04
        edges[3] = -10.04
        let skyline = try XCTUnwrap(HorizonProfile(altitudes: edges))
        XCTAssertEqual(skyline.maximumAltitude, 60)
        XCTAssertEqual(skyline.minimumAltitude, -10)
    }

    func testMaximumMinimumAndFlatness() throws {
        let skyline = try profile([5: 3, 200: 45.5, 300: -2.5])
        XCTAssertEqual(skyline.maximumAltitude, 45.5)
        XCTAssertEqual(skyline.minimumAltitude, -2.5)
        XCTAssertFalse(skyline.isFlat)
        XCTAssertTrue(try profile([:]).isFlat)
        XCTAssertEqual(Support.truthProfile.minimumAltitude, 2)
        XCTAssertEqual(Support.truthProfile.maximumAltitude, 30)
    }

    func testConstantProfileClampsAndHandlesNonFinite() {
        XCTAssertEqual(HorizonProfile.constant(7.5).altitudes, [Double](repeating: 7.5, count: 360))
        XCTAssertEqual(HorizonProfile.constant(80).minimumAltitude, 60)
        XCTAssertEqual(HorizonProfile.constant(-40).maximumAltitude, -10)
        XCTAssertTrue(HorizonProfile.constant(.nan).isFlat)
        XCTAssertEqual(HorizonProfile.constant(5).altitude(at: 123.4), 5)
    }

    func testEqualityFollowsTheAltitudes() throws {
        let first = try profile([10: 5])
        let second = try profile([10: 5])
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        XCTAssertNotEqual(first, try profile([10: 5.1]))
        XCTAssertNotEqual(first, HorizonProfile.flat)
    }

    // MARK: JSON

    func testJsonRoundTripIsExact() throws {
        let pattern = try XCTUnwrap(HorizonProfile(altitudes: patternTenths.map { Double($0) / 10 }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for skyline in [HorizonProfile.flat, Support.truthProfile, .constant(60), .constant(-10), pattern] {
            let data = try encoder.encode(skyline)
            let decoded = try JSONDecoder().decode(HorizonProfile.self, from: data)
            XCTAssertEqual(decoded, skyline)
            XCTAssertEqual(try encoder.encode(decoded), data)
        }
    }

    func testJsonShapeAndSize() throws {
        let data = try JSONEncoder().encode(Support.truthProfile)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["version", "altitudeTenths"])
        XCTAssertEqual(root["version"] as? Int, 1)
        let tenths = try XCTUnwrap(root["altitudeTenths"] as? [Any])
        XCTAssertEqual(tenths.count, 360)
        XCTAssertEqual(tenths[90] as? Int, 300)
        XCTAssertEqual(tenths[0] as? Int, 20)
        XCTAssertTrue(tenths.allSatisfy { ($0 as? Int) != nil })
        XCTAssertLessThan(data.count, 1_700, "a typical skyline is \(data.count) bytes")
        // The largest possible document is about 2 KB.
        for extreme in [HorizonProfile.constant(-10), .constant(60)] {
            let size = try JSONEncoder().encode(extreme).count
            XCTAssertLessThan(size, 2_000, "\(size) bytes")
        }
        XCTAssertLessThan(try JSONEncoder().encode(HorizonProfile.flat).count, 800)
    }

    func testDecodingAFixedDocument() throws {
        let decoded = try decode(document(patternTenths))
        for index in 0..<360 { XCTAssertEqual(decoded.altitudes[index], Double(patternTenths[index]) / 10) }
        XCTAssertEqual(decoded.maximumAltitude, 60)
        XCTAssertEqual(decoded.minimumAltitude, -10)
        // Unknown keys are ignored, numbers written with a decimal point are accepted.
        let tolerant = "{\"extra\":[1,2],\"version\":1.0,\"altitudeTenths\":[\(patternTenths.map { "\($0).0" }.joined(separator: ","))]}"
        XCTAssertEqual(try decode(tolerant), decoded)
    }

    func testDecodingRejectsInvalidDocuments() {
        let zeros = [Int](repeating: 0, count: 360)
        func fails(_ text: String, line: UInt = #line) {
            XCTAssertThrowsError(try decode(text), String(text.prefix(80)), line: line)
        }
        func replacing(_ literal: String) -> String {
            let items = zeros.enumerated().map { $0.offset == 7 ? literal : "\($0.element)" }
            return "{\"version\":1,\"altitudeTenths\":[\(items.joined(separator: ","))]}"
        }
        fails(document(zeros, version: 2))
        fails(document(zeros, version: 0))
        fails(document(Array(zeros.dropLast())))
        fails(document(zeros + [0]))
        fails(document([]))
        fails(replacing("601"))
        fails(replacing("-101"))
        fails(replacing("12.5"))
        fails(replacing("\"3\""))
        fails(replacing("null"))
        fails("{\"altitudeTenths\":[\(zeros.map(String.init).joined(separator: ","))]}")
        fails("{\"version\":1}")
        fails("{\"version\":\"1\",\"altitudeTenths\":[\(zeros.map(String.init).joined(separator: ","))]}")
        fails("{\"version\":1,\"altitudeTenths\":\"0,0,0\"}")
        fails("[1,2,3]")
        fails(replacing("1e400"))
    }

    // MARK: Editing

    func testRaisedAndLoweredRangeWrapsThroughNorth() {
        let base = HorizonProfile.constant(10)
        let raised = base.raised(by: 5, in: AzimuthRange(from: 350, to: 10))
        for azimuth in [350, 355, 359, 0, 5, 10] { XCTAssertEqual(raised.altitudes[azimuth], 15, "\(azimuth)") }
        for azimuth in [349, 11, 100, 200] { XCTAssertEqual(raised.altitudes[azimuth], 10, "\(azimuth)") }
        let lowered = raised.raised(by: -12.5, in: AzimuthRange(start: 80, length: 20))
        for azimuth in 80...100 { XCTAssertEqual(lowered.altitudes[azimuth], -2.5, "\(azimuth)") }
        XCTAssertEqual(lowered.altitudes[79], 10)
        XCTAssertEqual(lowered.altitudes[101], 10)
        XCTAssertEqual(lowered, base.raised(by: 5, in: AzimuthRange(from: 350, to: 10))
            .raised(by: -12.5, in: AzimuthRange(start: 80, length: 20)))
        XCTAssertEqual(base, base.raised(by: .nan, in: .full))
        XCTAssertEqual(base, base.raised(by: 3, in: AzimuthRange(start: 40, length: 0))
            .raised(by: -3, in: AzimuthRange(start: 40, length: 0)))
    }

    func testRaisedClampsToTheAllowedRange() {
        let base = HorizonProfile.constant(50)
        XCTAssertEqual(base.raised(by: 30, in: .full).minimumAltitude, 60)
        XCTAssertEqual(base.raised(by: -100, in: .full).maximumAltitude, -10)
        let half = base.raised(by: 100, in: AzimuthRange(start: 0, length: 180))
        XCTAssertEqual(half.altitude(at: 90), 60)
        XCTAssertEqual(half.altitude(at: 270), 50)
    }

    func testSettingReplacingAndMaximum() {
        let base = Support.truthProfile
        let wall = base.setting(to: 25, in: AzimuthRange(from: 250, to: 280))
        XCTAssertEqual(wall.altitude(at: 250), 25)
        XCTAssertEqual(wall.altitude(at: 265.5), 25)
        XCTAssertEqual(wall.altitude(at: 280), 25)
        XCTAssertEqual(wall.altitude(at: 249), base.altitude(at: 249))
        XCTAssertEqual(wall.altitude(at: 281), base.altitude(at: 281))
        XCTAssertEqual(base, base.setting(to: .nan, in: .full))
        XCTAssertEqual(HorizonProfile.constant(60), base.setting(to: 90, in: .full))

        // Replace one stretch by another profile's.
        let other = HorizonProfile.constant(20)
        let merged = base.replacing(AzimuthRange(from: 100, to: 130), with: other)
        for azimuth in 100...130 { XCTAssertEqual(merged.altitudes[azimuth], 20) }
        XCTAssertEqual(merged.altitudes[99], base.altitudes[99])
        XCTAssertEqual(merged.altitudes[131], base.altitudes[131])

        // Both sets of obstacles.
        let higher = base.maximum(with: other)
        for azimuth in 0..<360 { XCTAssertEqual(higher.altitudes[azimuth], max(base.altitudes[azimuth], 20)) }
        XCTAssertEqual(higher, other.maximum(with: base))
        XCTAssertEqual(base, base.maximum(with: .flat))
    }

    func testAzimuthRangeContainsAndWraps() {
        let through = AzimuthRange(from: 350, to: 20)
        XCTAssertEqual(through.start, 350)
        XCTAssertEqual(through.length, 30, accuracy: 1e-12)
        XCTAssertEqual(through.end, 20, accuracy: 1e-12)
        XCTAssertTrue(through.contains(350))
        XCTAssertTrue(through.contains(0))
        XCTAssertTrue(through.contains(20))
        XCTAssertTrue(through.contains(-5))
        XCTAssertTrue(through.contains(380))
        XCTAssertFalse(through.contains(20.5))
        XCTAssertFalse(through.contains(349.9))
        XCTAssertFalse(through.contains(.nan))
        XCTAssertTrue(AzimuthRange.full.contains(123))
        XCTAssertEqual(AzimuthRange(start: -10, length: 500).length, 360)
        XCTAssertEqual(AzimuthRange(start: -10, length: 5).start, 350)
        XCTAssertEqual(AzimuthRange(start: .nan, length: .nan).length, 0)
        XCTAssertEqual(AzimuthRange(from: 40, to: 40).length, 0)
        XCTAssertEqual(AzimuthRange(from: .nan, to: 40).start, 0)
        XCTAssertTrue(AzimuthRange(from: 40, to: 40).contains(40))
        XCTAssertFalse(AzimuthRange(from: 40, to: 40).contains(41))
    }

    // MARK: Drawing

    func testPolylineOfTheWholeCircle() {
        let skyline = Support.truthProfile
        let line = skyline.polyline()
        XCTAssertEqual(line.count, 361)
        XCTAssertEqual(line.first?.azimuth, 0)
        XCTAssertEqual(line.last?.azimuth, 360)
        XCTAssertEqual(line.first?.altitude, line.last?.altitude)
        for index in 0..<360 {
            XCTAssertEqual(line[index].azimuth, Double(index))
            XCTAssertEqual(line[index].altitude, skyline.altitudes[index])
        }
        // A coarser step keeps the ends and the multiples of the step.
        let coarse = skyline.polyline(step: 10)
        XCTAssertEqual(coarse.count, 37)
        XCTAssertEqual(coarse[9].azimuth, 90)
        XCTAssertEqual(coarse[9].altitude, 30)
    }

    func testPolylineAcrossNorthKeepsIncreasingAzimuths() throws {
        let skyline = try profile([358: 4, 359: 6, 0: 8, 1: 10, 2: 12])
        let line = skyline.polyline(from: 357.5, to: 362.25)
        XCTAssertEqual(line.map(\.azimuth), [357.5, 358, 359, 360, 361, 362, 362.25])
        XCTAssertEqual(line.map(\.altitude), [2, 4, 6, 8, 10, 12, 9])
        XCTAssertTrue(zip(line, line.dropFirst()).allSatisfy { $0.1.azimuth > $0.0.azimuth })
        XCTAssertEqual(skyline.polyline(from: 10, to: 10).count, 1)
    }

    func testPolylineStepAndInvalidInputs() {
        let skyline = Support.truthProfile
        XCTAssertTrue(skyline.polyline(from: 10, to: 5).isEmpty)
        XCTAssertTrue(skyline.polyline(from: .nan, to: 5).isEmpty)
        XCTAssertTrue(skyline.polyline(from: 0, to: .infinity).isEmpty)
        XCTAssertTrue(skyline.polyline(from: 1e300, to: 1e301).isEmpty)
        XCTAssertTrue(skyline.polyline(from: -2e9, to: 0).isEmpty)
        XCTAssertEqual(skyline.polyline(from: 1e9 - 1, to: 1e9).count, 2)
        // Longer than a full circle: cut to 360°.
        let long = skyline.polyline(from: 100, to: 1000)
        XCTAssertEqual(long.first?.azimuth, 100)
        XCTAssertEqual(long.last?.azimuth, 460)
        // The step is limited to 0.1…45; garbage falls back to 1.
        XCTAssertEqual(skyline.polyline(step: 0.0001).count, 3_601)
        XCTAssertEqual(skyline.polyline(step: 1000).count, 9)
        XCTAssertEqual(skyline.polyline(step: .nan).count, 361)
    }
}
