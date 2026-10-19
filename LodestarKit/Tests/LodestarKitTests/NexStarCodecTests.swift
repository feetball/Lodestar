import XCTest
@testable import LodestarKit

/// NexStar / SynScan codec tests. Sources: "NexStar Communication Protocol" (Celestron; sha256 of the PDF copy
/// a97100496545aa1f96aeb1060bf0a8a45a1e12f418743a1708d9d48dad194dfe) and "SynScan Serial Communication Protocol" version 3.3
/// (Sky-Watcher, SSAP-F-160414V1-EN; sha256 bbdbb0c785f9b4e61fd1c1ff2e7adbe294ead97c9e98c3d07e55187ced03f33e).
final class NexStarCodecTests: XCTestCase {
    private func text(_ bytes: [UInt8]) -> String { MountText.latin1(bytes) }

    private func bytes(_ values: Int...) -> [UInt8] { values.map { UInt8($0) } }

    // MARK: Angles

    func testDocumentedPositionExampleDecodes() throws {
        // "If the Get RA/DEC command returns 34AB,12CE then the DEC value is 12CE … 4814/65536 = 0.07346 … 26.4441 degrees."
        let position = try NexStarCodec.decodePosition("34AB,12CE")
        XCTAssertEqual(position.declination, 26.4441, accuracy: 0.00005)
        XCTAssertEqual(position.rightAscension, Double(0x34AB) / 65536.0 * 360.0, accuracy: 1e-9)
        XCTAssertEqual(position.rightAscension, 74.0643, accuracy: 0.0001)
    }

    func testDocumentedPrecisePositionExampleDecodes() throws {
        // "If the precise GET AZM-ALT command returns 12AB0500,40000500 then the AZM value is 12AB0500 … 26.252 degrees."
        XCTAssertEqual(try NexStarCodec.decodeAngle("12AB0500"), 26.252, accuracy: 0.0005)
        XCTAssertEqual(try NexStarCodec.decodeAngle("40000500"), 90.0, accuracy: 0.0002)
        // The SynScan edition: 12AB05 in 24 bits is 1,223,429 / 16,777,216 × 360 and the last two digits are ignored.
        XCTAssertEqual(try NexStarCodec.decodeAngle("12AB0500"), 1_223_429.0 / 16_777_216.0 * 360.0, accuracy: 1e-12)
        XCTAssertEqual(try NexStarCodec.decodeAngle("12AB0500"), try NexStarCodec.decodeAngle("12AB05FF"), accuracy: 0.0)
    }

    func testGotoCommandsMatchTheDocumentedForms() {
        // "GOTO RA/DEC R34AB,12CE" and "GOTO precise RA/DEC r34AB0500,12CE0500".
        let standard = EquatorialCoordinate(rightAscension: Double(0x34AB) / 65536.0 * 360.0, declination: Double(0x12CE) / 65536.0 * 360.0)
        XCTAssertEqual(text(NexStarCodec.goto(standard, precise: false)), "R34AB,12CE")
        XCTAssertEqual(text(NexStarCodec.sync(standard, precise: false)), "S34AB,12CE")
        let precise = EquatorialCoordinate(rightAscension: Double(0x34AB05) / 16_777_216.0 * 360.0,
                                           declination: Double(0x12CE05) / 16_777_216.0 * 360.0)
        XCTAssertEqual(text(NexStarCodec.goto(precise, precise: true)), "r34AB0500,12CE0500")
        XCTAssertEqual(text(NexStarCodec.sync(precise, precise: true)), "s34AB0500,12CE0500")
        XCTAssertEqual(text(NexStarCodec.getPosition(precise: true)), "e")
        XCTAssertEqual(text(NexStarCodec.getPosition(precise: false)), "E")
    }

    func testNegativeDeclinationsAreEncodedAsFractionsOfAFullTurn() throws {
        // -10° is 350° of a revolution: 350/360 × 65536 = 63715.56 → F8E4; × 2^24 = 16311,… → F8E38E, then the unused byte.
        XCTAssertEqual(NexStarCodec.encodeAngle(-10.0, precise: false), "F8E4")
        XCTAssertEqual(NexStarCodec.encodeAngle(-10.0, precise: true), "F8E38E00")
        XCTAssertEqual(NexStarCodec.encodeAngle(-90.0, precise: false), "C000")
        XCTAssertEqual(NexStarCodec.encodeAngle(90.0, precise: true), "40000000")
        let southern = try NexStarCodec.decodePosition("3B9B,F8E4")
        XCTAssertEqual(southern.declination, -10.0, accuracy: 0.003)
        XCTAssertEqual(try NexStarCodec.decodePosition("0000,C000").declination, -90.0, accuracy: 1e-9)
        XCTAssertEqual(try NexStarCodec.decodePosition("0000,4000").declination, 90.0, accuracy: 1e-9)
    }

    func testRightAscensionWrapsAtAFullTurn() {
        XCTAssertEqual(NexStarCodec.encodeAngle(0.0, precise: false), "0000")
        XCTAssertEqual(NexStarCodec.encodeAngle(360.0, precise: false), "0000")
        XCTAssertEqual(NexStarCodec.encodeAngle(359.9999, precise: false), "0000")
        XCTAssertEqual(NexStarCodec.encodeAngle(359.99999999, precise: true), "00000000")
        XCTAssertEqual(NexStarCodec.encodeAngle(359.9999, precise: true), "FFFFFB00")
        XCTAssertEqual(NexStarCodec.encodeAngle(180.0, precise: false), "8000")
        XCTAssertEqual(NexStarCodec.encodeAngle(-180.0, precise: false), "8000")
        XCTAssertEqual(NexStarCodec.encodeAngle(83.8221, precise: false), "3B9B")
        XCTAssertEqual(NexStarCodec.encodeAngle(41.2689, precise: true), "1D58C600")
    }

    func testAnglesSurviveEncodingAndDecoding() throws {
        var seed: UInt64 = 99
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seed >> 11) & 0xFFFF_FFFF) / 4_294_967_296.0
        }
        for _ in 0 ..< 500 {
            let ra = next() * 360
            let dec = next() * 180 - 90
            for precise in [false, true] {
                let tolerance = precise ? 360.0 / 16_777_216 / 2 + 1e-9 : 360.0 / 65_536 / 2 + 1e-9
                let reply = NexStarCodec.encodeAngle(ra, precise: precise) + "," + NexStarCodec.encodeAngle(dec, precise: precise)
                let decoded = try NexStarCodec.decodePosition(reply)
                var raDifference = abs(decoded.rightAscension - ra)
                if raDifference > 180 { raDifference = 360 - raDifference }
                XCTAssertLessThanOrEqual(raDifference, tolerance, "\(ra) \(precise) -> \(decoded.rightAscension)")
                XCTAssertLessThanOrEqual(abs(decoded.declination - dec), tolerance, "\(dec) \(precise) -> \(decoded.declination)")
            }
        }
    }

    func testGarbledPositionsAreRejected() throws {
        let bad = [
            "", ",", "34AB", "34AB,", ",12CE", "34AB;12CE", "34AB,12C", "34AB,12CE0500", "34AB0500,12CE", "34AB,12CG",
            "34AB,12CE,", "34AB 12CE", "34AB0500,12CE0500,", "34AB,5000", "34AB,B000", "34AB,7FFF", "-34A,12CE", "34AB,12CE#",
        ]
        for reply in bad { assertMalformed(try NexStarCodec.decodePosition(reply), reply) }
        // Lower case hexadecimal digits are accepted.
        XCTAssertEqual(try NexStarCodec.decodePosition("34ab,12ce").declination, 26.4441, accuracy: 0.00005)
        assertMalformed(try NexStarCodec.decodeAngle("123"))
        assertMalformed(try NexStarCodec.decodeAngle("12345"))
    }

    func testNonFiniteAnglesAreHandled() {
        for value in [Double.nan, Double.infinity] {
            XCTAssertEqual(NexStarCodec.encodeAngle(value, precise: false), "0000")
            XCTAssertEqual(NexStarCodec.encodeAngle(value, precise: true), "00000000")
        }
    }

    // MARK: Commands

    func testSimpleCommands() {
        XCTAssertEqual(text(NexStarCodec.getVersion), "V")
        XCTAssertEqual(text(NexStarCodec.getModel), "m")
        XCTAssertEqual(text(NexStarCodec.getAlignmentComplete), "J")
        XCTAssertEqual(text(NexStarCodec.getGotoInProgress), "L")
        XCTAssertEqual(text(NexStarCodec.cancelGoto), "M")
        XCTAssertEqual(text(NexStarCodec.getTrackingMode), "t")
        XCTAssertEqual(NexStarCodec.setTrackingMode(.off), bytes(Int(UInt8(ascii: "T")), 0))
        XCTAssertEqual(NexStarCodec.setTrackingMode(.altAz), bytes(Int(UInt8(ascii: "T")), 1))
        XCTAssertEqual(NexStarCodec.setTrackingMode(.eqNorth), bytes(Int(UInt8(ascii: "T")), 2))
        XCTAssertEqual(NexStarCodec.setTrackingMode(.eqSouth), bytes(Int(UInt8(ascii: "T")), 3))
        XCTAssertEqual(NexStarTrackingMode.fromCode(2), .eqNorth)
        XCTAssertNil(NexStarTrackingMode.fromCode(4))
    }

    func testVariableRateSlewMatchesTheDocumentedExample() throws {
        let p = Int(UInt8(ascii: "P"))
        // "if the desired tracking rate is 150 arcseconds/second: trackRateHigh = (150 * 4) \ 256 = 2, trackRateLow = 600 mod 256 = 88"
        XCTAssertEqual(try NexStarCodec.variableRateSlew(axis: .azimuthRightAscension, positive: true, arcsecondsPerSecond: 150.0),
                       bytes(p, 3, 16, 6, 2, 88, 0, 0))
        XCTAssertEqual(try NexStarCodec.variableRateSlew(axis: .azimuthRightAscension, positive: false, arcsecondsPerSecond: 150.0),
                       bytes(p, 3, 16, 7, 2, 88, 0, 0))
        XCTAssertEqual(try NexStarCodec.variableRateSlew(axis: .altitudeDeclination, positive: true, arcsecondsPerSecond: 0.25),
                       bytes(p, 3, 17, 6, 0, 1, 0, 0))
        XCTAssertEqual(try NexStarCodec.variableRateSlew(axis: .altitudeDeclination, positive: false, arcsecondsPerSecond: 16_383.75),
                       bytes(p, 3, 17, 7, 255, 255, 0, 0))
        for rate in [-1.0, 16_383.76, Double.nan, Double.infinity] {
            assertInvalidInput(try NexStarCodec.variableRateSlew(axis: .altitudeDeclination, positive: true, arcsecondsPerSecond: rate),
                               "\(rate)")
        }
    }

    func testFixedRateSlewAndDeviceVersionCommands() throws {
        let p = Int(UInt8(ascii: "P"))
        XCTAssertEqual(try NexStarCodec.fixedRateSlew(axis: .azimuthRightAscension, positive: true, rate: 5), bytes(p, 2, 16, 36, 5, 0, 0, 0))
        XCTAssertEqual(try NexStarCodec.fixedRateSlew(axis: .altitudeDeclination, positive: false, rate: 0), bytes(p, 2, 17, 37, 0, 0, 0, 0))
        assertInvalidInput(try NexStarCodec.fixedRateSlew(axis: .altitudeDeclination, positive: true, rate: 10))
        assertInvalidInput(try NexStarCodec.fixedRateSlew(axis: .altitudeDeclination, positive: true, rate: -1))
        XCTAssertEqual(NexStarCodec.getDeviceVersion(axis: .azimuthRightAscension), bytes(p, 1, 16, 254, 0, 0, 0, 2))
        XCTAssertEqual(NexStarCodec.getDeviceVersion(axis: .altitudeDeclination), bytes(p, 1, 17, 254, 0, 0, 0, 2))
    }

    func testLocationCommandMatchesTheDocumentedExample() throws {
        let w = Int(UInt8(ascii: "W"))
        // "to set the location to 118°20'17" W, 33°50'41" N … "W" & chr(33) & chr(50) & chr(41) & chr(0) & chr(118) & chr(20) & chr(17) & chr(1)"
        let location = GeographicLocation(latitude: 33 + 50 / 60.0 + 41 / 3600.0, longitude: -(118 + 20 / 60.0 + 17 / 3600.0), elevation: 0)
        XCTAssertEqual(try NexStarCodec.setLocation(location), bytes(w, 33, 50, 41, 0, 118, 20, 17, 1))
        let southEast = GeographicLocation(latitude: -33.8688, longitude: 151.2093, elevation: 0)
        XCTAssertEqual(try NexStarCodec.setLocation(southEast), bytes(w, 33, 52, 8, 1, 151, 12, 33, 0))
        XCTAssertEqual(try NexStarCodec.setLocation(GeographicLocation(latitude: 90, longitude: 180, elevation: 0)),
                       bytes(w, 90, 0, 0, 0, 180, 0, 0, 0))
    }

    func testTimeCommandMatchesTheDocumentedExample() throws {
        let h = Int(UInt8(ascii: "H"))
        // "to set the time to 3:26:00PM on April 6, 2005 in the Eastern time zone (-5 UTC: 256-5 = 251) … chr(15) chr(26) chr(0)
        // chr(4) chr(6) chr(5) chr(251) chr(1)"
        let date = MountDateTime(year: 2005, month: 4, day: 6, hour: 15, minute: 26, second: 0, millisecond: 0)
        XCTAssertEqual(try NexStarCodec.setTime(date, zoneOffsetHours: -5, daylightSaving: true), bytes(h, 15, 26, 0, 4, 6, 5, 251, 1))
        XCTAssertEqual(try NexStarCodec.setTime(date, zoneOffsetHours: 0, daylightSaving: false), bytes(h, 15, 26, 0, 4, 6, 5, 0, 0))
        XCTAssertEqual(try NexStarCodec.setTime(date, zoneOffsetHours: 14, daylightSaving: false), bytes(h, 15, 26, 0, 4, 6, 5, 14, 0))
        assertInvalidInput(try NexStarCodec.setTime(date, zoneOffsetHours: 15, daylightSaving: false))
        assertInvalidInput(try NexStarCodec.setTime(date, zoneOffsetHours: -13, daylightSaving: false))
        assertInvalidInput(try NexStarCodec.setTime(date.withYear(1999), zoneOffsetHours: 0, daylightSaving: false))
        assertInvalidInput(try NexStarCodec.setTime(date.withYear(2100), zoneOffsetHours: 0, daylightSaving: false))
        let now = try XCTUnwrap(MountCalendar.fields(for: Date(timeIntervalSince1970: 1_792_296_000)))
        XCTAssertEqual(try NexStarCodec.setTime(now, zoneOffsetHours: 0, daylightSaving: false), bytes(h, 4, 0, 0, 10, 18, 26, 0, 0))
    }

    // MARK: Replies

    func testVersionReplies() throws {
        let celestron = try NexStarCodec.decodeVersion(bytes(5, 28))
        XCTAssertEqual(celestron, NexStarVersion(flavor: .celestron, major: 5, minor: 28, patch: 0))
        XCTAssertEqual(celestron.description, "5.28")
        // "if the version is 04.37.07, then the hand control responses '042507#'"
        let synScan = try NexStarCodec.decodeVersion(MountText.ascii("042507"))
        XCTAssertEqual(synScan, NexStarVersion(flavor: .synscan, major: 4, minor: 37, patch: 7))
        XCTAssertEqual(synScan.description, "4.37.07")
        XCTAssertEqual(try NexStarCodec.decodeVersion(MountText.ascii("032600")), NexStarVersion(flavor: .synscan, major: 3, minor: 38, patch: 0))
        XCTAssertEqual(try NexStarCodec.decodeVersion(MountText.ascii("042606")), NexStarVersion(flavor: .synscan, major: 4, minor: 38, patch: 6))
        for bad in [bytes(), bytes(4), bytes(4, 1, 2), MountText.ascii("04250G"), MountText.ascii("04250"), MountText.ascii("0425070")] {
            assertMalformed(try NexStarCodec.decodeVersion(bad))
        }
    }

    func testVersionComparison() {
        let version = NexStarVersion(flavor: .synscan, major: 4, minor: 37, patch: 3)
        XCTAssertTrue(version.isAtLeast(4, 37, 3))
        XCTAssertTrue(version.isAtLeast(4, 37))
        XCTAssertTrue(version.isAtLeast(3, 99))
        XCTAssertFalse(version.isAtLeast(4, 37, 4))
        XCTAssertFalse(version.isAtLeast(4, 38))
        XCTAssertFalse(version.isAtLeast(5, 0))
    }

    func testModelNames() {
        XCTAssertEqual(NexStarCodec.modelName(12, flavor: .celestron), "Celestron NexStar 6/8 SE")
        XCTAssertEqual(NexStarCodec.modelName(9, flavor: .celestron), "Celestron CPC")
        XCTAssertEqual(NexStarCodec.modelName(99, flavor: .celestron), "Celestron NexStar")
        XCTAssertEqual(NexStarCodec.modelName(0, flavor: .synscan), "Sky-Watcher EQ6 GOTO")
        XCTAssertEqual(NexStarCodec.modelName(131, flavor: .synscan), "Sky-Watcher AZ GOTO")
        XCTAssertEqual(NexStarCodec.modelName(150, flavor: .synscan), "Sky-Watcher Dobsonian GOTO")
        XCTAssertEqual(NexStarCodec.modelName(160, flavor: .synscan), "Sky-Watcher AllView GOTO")
        XCTAssertEqual(NexStarCodec.modelName(77, flavor: .synscan), "Sky-Watcher SynScan")
    }
}
