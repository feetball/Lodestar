import XCTest
@testable import LodestarKit

/// LX200 codec tests. Sources: Meade Telescope Serial Command Protocol, revision 2007.10 (17 October 2007), commands
/// `:GR#`, `:GD#`, `:Sr`, `:Sd`, `:MS#`, `:CM#`, `:Q#`, `:U#`, `:D#`, `:Gg#`, `:GG#`, `:SC`, `:SL`; OnStep 4.24 `Command.ino`
/// (`:GU#`, `:GW#`, `:MS#` digits 0 to 9, `:CM#` answers `N/A#` and `En#`, `:Sg`, `:SG`).
final class LX200CodecTests: XCTestCase {
    private func hms(_ hours: Int, _ minutes: Int, _ seconds: Double) -> Double {
        Double(hours) + Double(minutes) / 60.0 + seconds / 3600.0
    }

    // MARK: Commands

    func testFixedCommandsMatchTheReference() {
        XCTAssertEqual(LX200Codec.getRightAscension, ":GR#")
        XCTAssertEqual(LX200Codec.getDeclination, ":GD#")
        XCTAssertEqual(LX200Codec.slewToTarget, ":MS#")
        XCTAssertEqual(LX200Codec.syncToTarget, ":CM#")
        XCTAssertEqual(LX200Codec.halt, ":Q#")
        XCTAssertEqual(LX200Codec.togglePrecision, ":U#")
        XCTAssertEqual(LX200Codec.getSlewDistance, ":D#")
        XCTAssertEqual(LX200Codec.getProductName, ":GVP#")
        XCTAssertEqual(LX200Codec.getFirmwareNumber, ":GVN#")
        XCTAssertEqual(LX200Codec.getStatus, ":GU#")
        XCTAssertEqual(LX200Codec.getAlignmentStatus, ":GW#")
        XCTAssertEqual(LX200Codec.trackingOn, ":Te#")
        XCTAssertEqual(LX200Codec.trackingOff, ":Td#")
        XCTAssertEqual(LX200Codec.busyByte, 0x15)
    }

    func testMovementCommands() {
        XCTAssertEqual(LX200Codec.move(.north), ":Mn#")
        XCTAssertEqual(LX200Codec.move(.south), ":Ms#")
        XCTAssertEqual(LX200Codec.move(.east), ":Me#")
        XCTAssertEqual(LX200Codec.move(.west), ":Mw#")
        XCTAssertEqual(LX200Codec.halt(.north), ":Qn#")
        XCTAssertEqual(LX200Codec.halt(.south), ":Qs#")
        XCTAssertEqual(LX200Codec.halt(.east), ":Qe#")
        XCTAssertEqual(LX200Codec.halt(.west), ":Qw#")
        XCTAssertEqual(LX200Codec.setRate(.guide), ":RG#")
        XCTAssertEqual(LX200Codec.setRate(.center), ":RC#")
        XCTAssertEqual(LX200Codec.setRate(.find), ":RM#")
        XCTAssertEqual(LX200Codec.setRate(.slew), ":RS#")
    }

    // MARK: Right ascension

    func testRightAscensionHighPrecisionEncoding() {
        func high(_ hours: Double) -> String { LX200Codec.formatRightAscension(hours: hours, precision: .high) }
        XCTAssertEqual(high(0.0), "00:00:00")
        XCTAssertEqual(high(12.5), "12:30:00")
        XCTAssertEqual(high(hms(5, 35, 0.0)), "05:35:00")
        // Vega, 18h 36m 56.3s, rounds to the nearest second.
        XCTAssertEqual(high(hms(18, 36, 56.3)), "18:36:56")
        XCTAssertEqual(high(hms(18, 36, 56.5)), "18:36:57")
        // 24 h wrap: rounding up to 24:00:00 gives 00:00:00, and out-of-range hours are wrapped.
        XCTAssertEqual(high(23.9999), "00:00:00")
        XCTAssertEqual(high(hms(23, 59, 59.4)), "23:59:59")
        XCTAssertEqual(high(-1.0), "23:00:00")
        XCTAssertEqual(high(25.0), "01:00:00")
        XCTAssertEqual(high(24.0), "00:00:00")
    }

    func testRightAscensionLowPrecisionEncoding() {
        func low(_ hours: Double) -> String { LX200Codec.formatRightAscension(hours: hours, precision: .low) }
        XCTAssertEqual(low(0.0), "00:00.0")
        XCTAssertEqual(low(12.5), "12:30.0")
        XCTAssertEqual(low(hms(5, 35, 0.0)), "05:35.0")
        XCTAssertEqual(low(0.1), "00:06.0")
        XCTAssertEqual(low(hms(18, 36, 56.3)), "18:36.9")
        XCTAssertEqual(low(23.99), "23:59.4")
        XCTAssertEqual(low(23.9999), "00:00.0")
    }

    func testRightAscensionDecoding() throws {
        let high = try LX200Codec.decodeRightAscension("12:34:56")
        XCTAssertEqual(high.value, hms(12, 34, 56.0), accuracy: 1e-12)
        XCTAssertEqual(high.precision, .high)
        let low = try LX200Codec.decodeRightAscension("12:34.5")
        XCTAssertEqual(low.value, 12.0 + 34.5 / 60, accuracy: 1e-12)
        XCTAssertEqual(low.precision, .low)
        XCTAssertEqual(try LX200Codec.decodeRightAscension("00:00:00").value, 0.0, accuracy: 0.0)
        XCTAssertEqual(try LX200Codec.decodeRightAscension("23:59:59").value, hms(23, 59, 59.0), accuracy: 1e-12)
        // 24:00:00 is the same point as 00:00:00.
        XCTAssertEqual(try LX200Codec.decodeRightAscension("24:00:00").value, 0.0, accuracy: 0.0)
        XCTAssertEqual(try LX200Codec.decodeRightAscension("24:00.0").value, 0.0, accuracy: 0.0)
        // OnStep's highest precision (":GRH#"): fractional seconds.
        let fine = try LX200Codec.decodeRightAscension("05:34:31.9490")
        XCTAssertEqual(fine.value, hms(5, 34, 31.949), accuracy: 1e-9)
        XCTAssertEqual(fine.precision, .high)
        XCTAssertEqual(try LX200Codec.decodeRightAscension("05:34:31.9").value, hms(5, 34, 31.9), accuracy: 1e-9)
    }

    func testRightAscensionDecodingRejectsGarbage() {
        let bad = [
            "", "#", "12", "12:3", "12:34", "12:34:", "12:34:5", "12:34:56.", "12:34:56.12345", "12:34.", "12:34.5x",
            "12:34.1234", "12:60:00", "12:34:60", "25:00:00", "24:00:01", "24:01.0", "ab:cd:ef", "12-34-56", "1:34:56",
            "12:34:56#", " 12:34:56", "-1:00:00", "12;34;56", "12:7x:00",
        ]
        for text in bad { assertMalformed(try LX200Codec.decodeRightAscension(text), text) }
    }

    // MARK: Declination

    func testDeclinationHighPrecisionEncoding() {
        func high(_ degrees: Double) -> String { LX200Codec.formatDeclination(degrees: degrees, precision: .high) }
        XCTAssertEqual(high(0.0), "+00*00:00")
        XCTAssertEqual(high(hms(45, 30, 15.0)), "+45*30:15")
        XCTAssertEqual(high(-hms(23, 26, 21.4)), "-23*26:21")
        XCTAssertEqual(high(-0.5), "-00*30:00")
        XCTAssertEqual(high(-90.0), "-90*00:00")
        XCTAssertEqual(high(90.0), "+90*00:00")
        // Out of range values are clamped, tiny negatives do not produce a negative zero, carries propagate.
        XCTAssertEqual(high(90.5), "+90*00:00")
        XCTAssertEqual(high(-120.0), "-90*00:00")
        XCTAssertEqual(high(-0.0001), "+00*00:00")
        XCTAssertEqual(high(29.9999999), "+30*00:00")
        XCTAssertEqual(high(-29.9999999), "-30*00:00")
    }

    func testDeclinationLowPrecisionEncoding() {
        func low(_ degrees: Double) -> String { LX200Codec.formatDeclination(degrees: degrees, precision: .low) }
        XCTAssertEqual(low(0.0), "+00*00")
        XCTAssertEqual(low(45.5), "+45*30")
        XCTAssertEqual(low(-0.25), "-00*15")
        XCTAssertEqual(low(-33.8688), "-33*52")
        XCTAssertEqual(low(-0.001), "+00*00")
        XCTAssertEqual(low(29.9999), "+30*00")
    }

    func testDeclinationDecoding() throws {
        let high = try LX200Codec.decodeDeclination("+45*30:15")
        XCTAssertEqual(high.value, hms(45, 30, 15.0), accuracy: 1e-12)
        XCTAssertEqual(high.precision, .high)
        let low = try LX200Codec.decodeDeclination("-00*30")
        XCTAssertEqual(low.value, -0.5, accuracy: 1e-12)
        XCTAssertEqual(low.precision, .low)
        // Meade's document writes the seconds separator as an apostrophe: sDD*MM'SS.
        XCTAssertEqual(try LX200Codec.decodeDeclination("+45*30'15").value, hms(45, 30, 15.0), accuracy: 1e-12)
        // Some Meade scopes send their LCD's degree sign (byte 0xDF) or the ISO degree sign instead of '*'.
        XCTAssertEqual(try LX200Codec.decodeDeclination("+45\u{00DF}30'15").value, hms(45, 30, 15.0), accuracy: 1e-12)
        XCTAssertEqual(try LX200Codec.decodeDeclination("-12\u{00B0}05:00").value, -hms(12, 5, 0.0), accuracy: 1e-12)
        XCTAssertEqual(try LX200Codec.decodeDeclination("-23*26:21.448").value, -hms(23, 26, 21.448), accuracy: 1e-9)
        // The sign is optional.
        XCTAssertEqual(try LX200Codec.decodeDeclination("45*30").value, 45.5, accuracy: 1e-12)
        XCTAssertEqual(try LX200Codec.decodeDeclination("+90*00:00").value, 90.0, accuracy: 0.0)
        XCTAssertEqual(try LX200Codec.decodeDeclination("-90*00").value, -90.0, accuracy: 0.0)
        XCTAssertEqual(try LX200Codec.decodeDeclination("+00*00:00").value, 0.0, accuracy: 0.0)
    }

    func testDeclinationDecodingRejectsGarbage() {
        let bad = [
            "", "+", "+4*30", "+45*3", "+45x30", "+45*30:", "+45*30:1", "+45*30:15x", "+45*30:15.", "+45*60", "+45*30:60",
            "+91*00", "+90*01", "+90*00:01", "-91*00:00", "++45*30", "+45*30#", "+4a*30", "abc", "+45*30:15.12345",
        ]
        for text in bad { assertMalformed(try LX200Codec.decodeDeclination(text), text) }
    }

    func testPositionsSurviveEncodingAndDecoding() throws {
        var seed: UInt64 = 12_345
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seed >> 11) & 0xFFFF_FFFF) / 4_294_967_296.0
        }
        for _ in 0 ..< 500 {
            let hours = next() * 24
            let degrees = next() * 180 - 90
            for precision in LX200Precision.allCases {
                let ra = try LX200Codec.decodeRightAscension(LX200Codec.formatRightAscension(hours: hours, precision: precision))
                let tolerance = precision == .high ? 0.5 / 3600 : 0.05 / 60
                var difference = abs(ra.value - hours)
                if difference > 12 { difference = 24 - difference }
                XCTAssertLessThanOrEqual(difference, tolerance + 1e-12, "\(hours) \(precision) -> \(ra.value)")
                XCTAssertEqual(ra.precision, precision)
                let dec = try LX200Codec.decodeDeclination(LX200Codec.formatDeclination(degrees: degrees, precision: precision))
                let decTolerance = precision == .high ? 0.5 / 3600 : 0.5 / 60
                XCTAssertLessThanOrEqual(abs(dec.value - degrees), decTolerance + 1e-12, "\(degrees) \(precision) -> \(dec.value)")
            }
        }
    }

    func testTargetCommandsCombineTheFormats() {
        XCTAssertEqual(LX200Codec.setTargetRightAscension(hours: 12.5, precision: .high), ":Sr12:30:00#")
        XCTAssertEqual(LX200Codec.setTargetRightAscension(hours: 12.5, precision: .low), ":Sr12:30.0#")
        XCTAssertEqual(LX200Codec.setTargetDeclination(degrees: 45.5, precision: .high), ":Sd+45*30:00#")
        XCTAssertEqual(LX200Codec.setTargetDeclination(degrees: -0.25, precision: .low), ":Sd-00*15#")
    }

    // MARK: Replies

    func testSlewRefusalDigits() throws {
        XCTAssertNil(try LX200Codec.slewRefusal("0"))
        XCTAssertEqual(try LX200Codec.slewRefusal("1"), .mountHorizonLimit)
        XCTAssertEqual(try LX200Codec.slewRefusal("2"), .mountOverheadLimit)
        XCTAssertEqual(try LX200Codec.slewRefusal("3"), .standby)
        XCTAssertEqual(try LX200Codec.slewRefusal("4"), .parked)
        XCTAssertEqual(try LX200Codec.slewRefusal("5"), .slewInProgress)
        XCTAssertEqual(try LX200Codec.slewRefusal("6"), .outsideMountLimits)
        XCTAssertTrue(try XCTUnwrap(try LX200Codec.slewRefusal("7")).isHardwareFault)
        XCTAssertEqual(try LX200Codec.slewRefusal("8"), .busy)
        XCTAssertTrue(try XCTUnwrap(try LX200Codec.slewRefusal("9")).isRejected)
        for bad: Character in ["a", "#", " ", "E", "\u{15}"] { assertMalformed(try LX200Codec.slewRefusal(bad), String(bad)) }
    }

    func testDistanceBarsMeanSlewing() {
        XCTAssertFalse(LX200Codec.isSlewing(distanceBars: ""))
        XCTAssertTrue(LX200Codec.isSlewing(distanceBars: "\u{7F}"))
        XCTAssertTrue(LX200Codec.isSlewing(distanceBars: "|||"))
    }

    func testOnStepStatusString() throws {
        let tracking = try LX200Codec.decodeStatus("NpEo000")
        XCTAssertTrue(tracking.isTracking)
        XCTAssertFalse(tracking.isGotoActive)
        XCTAssertFalse(tracking.isParked)
        let idle = try LX200Codec.decodeStatus("nNpEo000")
        XCTAssertFalse(idle.isTracking)
        let slewing = try LX200Codec.decodeStatus("pEo000")
        XCTAssertTrue(slewing.isGotoActive)
        XCTAssertTrue(slewing.isTracking)
        let parked = try LX200Codec.decodeStatus("nNPHEo000")
        XCTAssertTrue(parked.isParked)
        XCTAssertTrue(parked.isAtHome)
        XCTAssertTrue(try LX200Codec.decodeStatus("nNIEo000").isParking)
        XCTAssertTrue(try LX200Codec.decodeStatus("nNFEo000").parkFailed)
        for bad in ["", "NEo000", "NpPEo", "N p", "\u{07}pN", String(repeating: "N", count: 41) + "p"] {
            assertMalformed(try LX200Codec.decodeStatus(bad), bad)
        }
    }

    func testAlignmentStatus() throws {
        let status = try LX200Codec.decodeAlignmentStatus("GT2")
        XCTAssertEqual(status.mountType, "G")
        XCTAssertTrue(status.isTracking)
        XCTAssertEqual(status.alignedStars, 2)
        XCTAssertEqual(try LX200Codec.decodeAlignmentStatus("AN0").alignedStars, 0)
        XCTAssertFalse(try LX200Codec.decodeAlignmentStatus("AN0").isTracking)
        for bad in ["", "GT", "GT22", "XT2", "GX2", "GTa"] { assertMalformed(try LX200Codec.decodeAlignmentStatus(bad), bad) }
    }

    func testDialectDetection() {
        XCTAssertEqual(LX200Codec.dialect(productName: "On-Step"), .onstep)
        XCTAssertEqual(LX200Codec.dialect(productName: "OnStep 4.24"), .onstep)
        XCTAssertEqual(LX200Codec.dialect(productName: "LX200 Classic"), .meade)
        XCTAssertEqual(LX200Codec.dialect(productName: ""), .meade)
    }

    // MARK: Site and time

    func testLatitudeCommand() {
        XCTAssertEqual(LX200Codec.setLatitude(40.015), ":St+40*01#")
        XCTAssertEqual(LX200Codec.setLatitude(-33.8688), ":St-33*52#")
        XCTAssertEqual(LX200Codec.setLatitude(0.0), ":St+00*00#")
        XCTAssertEqual(LX200Codec.setLatitude(-0.001), ":St+00*00#")
        XCTAssertEqual(LX200Codec.setLatitude(91.0), ":St+90*00#")
        XCTAssertEqual(LX200Codec.setLatitude(51.9999), ":St+52*00#")
    }

    func testLongitudeCommandCountsWestwards() {
        // "East Longitudes are expressed as negative" (:Gg#), so 105.27° W is sent as 105*16 and 10° E as 350*00.
        XCTAssertEqual(LX200Codec.setLongitude(-105.27), ":Sg105*16#")
        XCTAssertEqual(LX200Codec.setLongitude(10.0), ":Sg350*00#")
        XCTAssertEqual(LX200Codec.setLongitude(0.0), ":Sg000*00#")
        XCTAssertEqual(LX200Codec.setLongitude(180.0), ":Sg180*00#")
        XCTAssertEqual(LX200Codec.setLongitude(-180.0), ":Sg180*00#")
        XCTAssertEqual(LX200Codec.setLongitude(0.0001), ":Sg000*00#")
        XCTAssertEqual(LX200Codec.setLongitude(359.9999), ":Sg000*00#")
        XCTAssertEqual(LX200Codec.setLongitude(370.0), ":Sg350*00#")
    }

    func testUTCOffsetCommandForBothDialects() {
        // ":GG#" is "the number of decimal hours to add to local time to convert it to UTC": west of Greenwich positive.
        func meade(_ hours: Double) -> String { LX200Codec.setUTCOffset(eastOffsetHours: hours, dialect: .meade) }
        func onStep(_ hours: Double) -> String { LX200Codec.setUTCOffset(eastOffsetHours: hours, dialect: .onstep) }
        XCTAssertEqual(meade(0.0), ":SG+00.0#")
        XCTAssertEqual(meade(1.0), ":SG-01.0#")
        XCTAssertEqual(meade(-5.0), ":SG+05.0#")
        XCTAssertEqual(meade(5.5), ":SG-05.5#")
        XCTAssertEqual(onStep(0.0), ":SG+00#")
        XCTAssertEqual(onStep(1.0), ":SG-01#")
        XCTAssertEqual(onStep(-7.0), ":SG+07#")
        XCTAssertEqual(onStep(5.5), ":SG-05:30#")
        XCTAssertEqual(onStep(5.75), ":SG-05:45#")
        XCTAssertEqual(onStep(-20.0), ":SG+14#")
    }

    func testDateAndTimeCommands() throws {
        let fields = try XCTUnwrap(MountCalendar.fields(for: Date(timeIntervalSince1970: 1_792_296_000)))
        XCTAssertEqual(LX200Codec.setDate(fields), ":SC10/18/26#")
        XCTAssertEqual(LX200Codec.setTime(fields), ":SL04:00:00#")
        let other = try XCTUnwrap(MountCalendar.fields(for: Date(timeIntervalSince1970: 951_782_399)))
        XCTAssertEqual(LX200Codec.setDate(other), ":SC02/28/00#")
        XCTAssertEqual(LX200Codec.setTime(other), ":SL23:59:59#")
    }

    func testNonFiniteNumbersNeverBreakTheFormatting() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(LX200Codec.formatRightAscension(hours: value, precision: .high), "00:00:00")
            XCTAssertEqual(LX200Codec.formatRightAscension(hours: value, precision: .low), "00:00.0")
            XCTAssertEqual(LX200Codec.formatDeclination(degrees: value, precision: .high), "+00*00:00")
            XCTAssertEqual(LX200Codec.formatDeclination(degrees: value, precision: .low), "+00*00")
            XCTAssertEqual(LX200Codec.setLatitude(value), ":St+00*00#")
            XCTAssertEqual(LX200Codec.setLongitude(value), ":Sg000*00#")
            XCTAssertEqual(LX200Codec.setUTCOffset(eastOffsetHours: value, dialect: .meade), ":SG+00.0#")
            XCTAssertEqual(LX200Codec.setUTCOffset(eastOffsetHours: value, dialect: .onstep), ":SG+00#")
        }
    }
}
