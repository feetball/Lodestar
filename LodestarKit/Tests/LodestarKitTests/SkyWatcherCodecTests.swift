import XCTest
@testable import LodestarKit

/// Sky-Watcher motor controller codec tests. Source: Sky-Watcher, "Motor Controller Command Set"
/// (`skywatcher_motor_controller_command_set.pdf`, sha256 a4c583bdf617b45ea64b3c742e8b8ab7009a953a2d42c97fdaacd67455d7f73a): command
/// format (`:` letter channel data CR), the data formats ("for HEX number 0x123456 … 5 6 3 4 1 2"), the 0x800000 position offset
/// ("0x000012 should be converted to 0x800012 … 0x801234 reported by the motor controller is 0x001234"), the status bits, the error
/// codes 0 to 8, the T1 preset formulas and the Wi-Fi notes (UDP port 11880, 192.168.4.1). Mount codes: INDI `skywatcherAPI.h`.
final class SkyWatcherCodecTests: XCTestCase {
    private func text(_ bytes: [UInt8]) -> String { MountText.latin1(bytes) }

    private func bytes(_ value: String) -> [UInt8] { MountText.latin1Bytes(value) }

    // MARK: Numbers

    func testNumbersAreLittleEndianHex() throws {
        XCTAssertEqual(try SkyWatcherCodec.encode24(0x123456), "563412")
        XCTAssertEqual(try SkyWatcherCodec.encode16(0x1234), "3412")
        XCTAssertEqual(try SkyWatcherCodec.encode8(0x12), "12")
        XCTAssertEqual(try SkyWatcherCodec.encode24(0), "000000")
        XCTAssertEqual(try SkyWatcherCodec.encode24(0xFFFFFF), "FFFFFF")
        XCTAssertEqual(try SkyWatcherCodec.decode24("563412"), 0x123456)
        XCTAssertEqual(try SkyWatcherCodec.decode16("3412"), 0x1234)
        XCTAssertEqual(try SkyWatcherCodec.decode8("12"), 0x12)
        XCTAssertEqual(try SkyWatcherCodec.decode24("EFCDAB"), 0xABCDEF)
        for value in [0, 1, 255, 256, 65_535, 65_536, 0x7FFFFF, 0x800000, 0xFFFFFE, 0xFFFFFF] {
            XCTAssertEqual(try SkyWatcherCodec.decode24(try SkyWatcherCodec.encode24(value)), value)
        }
    }

    func testNumberCodecsRejectBadValuesAndText() {
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.encode24(-1) }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.encode24(0x1000000) }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.encode16(0x10000) }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.encode8(256) }?.isInvalidInput == true)
        for bad in ["", "56341", "5634122", "56341G", "56341g", "56 412", "5634-2"] {
            XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.decode24(bad) }?.isMalformedReply == true, bad)
        }
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.decode16("341") }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.decode8("1") }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.decode8("1x") }?.isMalformedReply == true)
    }

    func testPositionsAreOffsetBy0x800000() throws {
        // "0x000012 should be converted to 0x800012 when preparing the command" → digits 12 00 80.
        XCTAssertEqual(try SkyWatcherCodec.encodePosition(0x12), "120080")
        // "the true position of data 0x801234 reported by the motor controller is 0x001234".
        XCTAssertEqual(try SkyWatcherCodec.decodePosition("341280"), 0x1234)
        XCTAssertEqual(try SkyWatcherCodec.encodePosition(0), "000080")
        XCTAssertEqual(try SkyWatcherCodec.encodePosition(-1), "FFFF7F")
        XCTAssertEqual(try SkyWatcherCodec.encodePosition(-0x800000), "000000")
        XCTAssertEqual(try SkyWatcherCodec.encodePosition(0x7FFFFF), "FFFFFF")
        XCTAssertEqual(try SkyWatcherCodec.decodePosition("FFFF7F"), -1)
        XCTAssertEqual(try SkyWatcherCodec.decodePosition("000000"), -0x800000)
        for counts in [-0x800000, -123_456, -1, 0, 1, 99_999, 0x7FFFFF] {
            XCTAssertEqual(try SkyWatcherCodec.decodePosition(try SkyWatcherCodec.encodePosition(counts)), counts)
        }
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.encodePosition(0x800000) }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.encodePosition(-0x800001) }?.isInvalidInput == true)
    }

    // MARK: Requests

    func testRequestsFollowTheCommandFormat() throws {
        XCTAssertEqual(try SkyWatcherCodec.request(.inquireVersion, axis: .axis1), [0x3A, 0x65, 0x31, 0x0D])
        XCTAssertEqual(text(try SkyWatcherCodec.inquire(.inquireVersion, axis: .axis1)), ":e1\r")
        XCTAssertEqual(text(try SkyWatcherCodec.inquire(.inquireCountsPerRevolution, axis: .axis2)), ":a2\r")
        XCTAssertEqual(text(try SkyWatcherCodec.inquire(.inquireTimerFrequency, axis: .axis1)), ":b1\r")
        XCTAssertEqual(text(try SkyWatcherCodec.inquire(.inquirePosition, axis: .axis2)), ":j2\r")
        XCTAssertEqual(text(try SkyWatcherCodec.inquire(.inquireStatus, axis: .axis1)), ":f1\r")
        XCTAssertEqual(text(try SkyWatcherCodec.inquire(.inquireHighSpeedRatio, axis: .axis2)), ":g2\r")
        XCTAssertEqual(text(try SkyWatcherCodec.inquire(.extendedInquire, axis: .axis1)), ":q1010000\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setMotionMode(axis: .axis1, mode: .gotoFast, direction: .decreasing)), ":G101\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setMotionMode(axis: .axis2, mode: .trackFast, direction: .increasing)), ":G230\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setMotionMode(axis: .axis1, mode: .gotoSlow, direction: .increasing)), ":G120\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setMotionMode(axis: .axis2, mode: .trackSlow, direction: .increasing)), ":G210\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setGotoTargetIncrement(axis: .axis2, counts: 0x123456)), ":H2563412\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setBrakePointIncrement(axis: .axis1, counts: 3200)), ":M1800C00\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setGotoTarget(axis: .axis1, position: -1)), ":S1FFFF7F\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setStepPeriod(axis: .axis2, period: 14_023)), ":I2C73600\r")
        XCTAssertEqual(text(try SkyWatcherCodec.start(axis: .axis1)), ":J1\r")
        XCTAssertEqual(text(try SkyWatcherCodec.stop(axis: .axis2)), ":K2\r")
        XCTAssertEqual(text(try SkyWatcherCodec.stop(axis: .axis1, instant: true)), ":L1\r")
        XCTAssertEqual(text(try SkyWatcherCodec.setPosition(axis: .axis1, counts: 0x12)), ":E1120080\r")
        XCTAssertEqual(text(try SkyWatcherCodec.initializationDone(axis: .axis2)), ":F2\r")
    }

    func testRequestsRejectWhatTheControllerWouldRefuse() {
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.inquire(.startMotion, axis: .axis1) }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.request(.setStepPeriod, axis: .axis1, data: "1234567") }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.request(.setStepPeriod, axis: .axis1, data: "12ab") }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.setGotoTargetIncrement(axis: .axis1, counts: -1) }?.isInvalidInput == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.setStepPeriod(axis: .axis1, period: 0x1000000) }?.isInvalidInput == true)
    }

    func testCommandTableIsConsistent() {
        let letters = SkyWatcherCommand.allCases.map { $0.letter }
        XCTAssertEqual(letters.count, Set(letters).count)
        for command in SkyWatcherCommand.allCases { XCTAssertEqual(SkyWatcherCommand.fromLetter(command.letter), command) }
        XCTAssertNil(SkyWatcherCommand.fromLetter("Q"))
        XCTAssertNil(SkyWatcherCommand.fromLetter("z"))
        XCTAssertEqual(Set(SkyWatcherCommand.allCases.filter { $0.isInquiry }.map { $0.letter }),
                       Set<Character>(["a", "b", "c", "h", "i", "j", "k", "m", "f", "g", "D", "d", "e", "s", "q"]))
        XCTAssertEqual(SkyWatcherCommand.inquireStatus.replyDigits, 3)
        XCTAssertEqual(SkyWatcherCommand.inquireHighSpeedRatio.replyDigits, 2)
        XCTAssertEqual(SkyWatcherCommand.inquirePosition.replyDigits, 6)
        XCTAssertEqual(SkyWatcherCommand.startMotion.replyDigits, 0)
    }

    // MARK: Replies

    func testRepliesParse() throws {
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes("=")), .success(payload: ""))
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes("=563412")), .success(payload: "563412"))
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes("=0322A5")), .success(payload: "0322A5"))
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes("!2")), .failure(code: 2))
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes("!8")), .failure(code: 8))
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes("!0A")), .failure(code: 10))
        XCTAssertEqual(try SkyWatcherCodec.parseDatagram(bytes("=1234\r")), .success(payload: "1234"))
        XCTAssertEqual(try SkyWatcherCodec.parseDatagram(bytes("=\r")), .success(payload: ""))
        XCTAssertEqual(try SkyWatcherCodec.parseDatagram(bytes("!4\r")), .failure(code: 4))
        // Only the first reply of a datagram counts.
        XCTAssertEqual(try SkyWatcherCodec.parseDatagram(bytes("=12\r=34\r")), .success(payload: "12"))
    }

    func testRepliesTolerateBytesInFrontOfTheMarker() throws {
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes("\n=12")), .success(payload: "12"))
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes(":j1=1A2B3C")), .success(payload: "1A2B3C"))
        XCTAssertEqual(try SkyWatcherCodec.parseReply(bytes(" !1")), .failure(code: 1))
    }

    func testMalformedRepliesAreRejected() {
        let bad = ["", "563412", "=56341G", "=5634120", "=ab", "=12 34", "=1-2", "!", "!123", "!G", "!1G", "!!2", "x", ":", "?",
                   "=\u{00DF}1", "=12\u{0000}", "=1\u{0001}"]
        for line in bad {
            XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.parseReply(bytes(line)) }?.isMalformedReply == true, "'\(line)'")
        }
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.parseDatagram(bytes("=1234")) }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.parseDatagram(bytes("")) }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.parseDatagram(bytes("\r")) }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.parseDatagram(bytes("=1G34\r")) }?.isMalformedReply == true)
    }

    func testErrorCodesMapToMountErrors() {
        XCTAssertEqual(SkyWatcherCodec.error(0), .notSupported(feature: .other))
        XCTAssertTrue(SkyWatcherCodec.error(1).isRejected)
        XCTAssertEqual(SkyWatcherCodec.error(2), .busy)
        XCTAssertTrue(SkyWatcherCodec.error(3).isRejected)
        if case let .rejected(detail) = SkyWatcherCodec.error(4) { XCTAssertTrue(detail.contains("not initialized")) } else { XCTFail("code 4") }
        XCTAssertEqual(SkyWatcherCodec.error(5), .standby)
        XCTAssertEqual(SkyWatcherCodec.error(7), .busy)
        if case let .rejected(detail) = SkyWatcherCodec.error(8) { XCTAssertTrue(detail.contains("PEC")) } else { XCTFail("code 8") }
        for code in [6, 9, 10, 15] {
            XCTAssertEqual(SkyWatcherCodec.error(code), .remote(code: code, detail: "undocumented motor controller error"))
        }
        for error in SkyWatcherErrorCode.allCases { XCTAssertEqual(SkyWatcherErrorCode.fromCode(error.code), error) }
        XCTAssertNil(SkyWatcherErrorCode.fromCode(6))
        XCTAssertEqual(SkyWatcherErrorCode.allCases.map { $0.code }, [0, 1, 2, 3, 4, 5, 7, 8])
        // Only the errors a damaged request can cause are worth sending the command again for.
        for code in 0 ... 15 {
            XCTAssertEqual(SkyWatcherCodec.isPossiblyCausedByDamagedRequest(code), code == 0 || code == 1 || code == 3, "\(code)")
        }
        for error in [0, 1, 2, 3, 4, 5, 7, 8, 6, 12] { XCTAssertFalse(SkyWatcherCodec.error(error).isCommunicationFailure) }
    }

    func testStatusReplyBits() throws {
        // B0: 1 = speed (tracking) mode, B1: 1 = counter-clockwise, B2: 1 = fast; second digit B0 running, B1 blocked; third B0 initialized, B1 level switch.
        let running = try SkyWatcherCodec.decodeStatus("511")
        XCTAssertTrue(running.isSpeedMode && running.isFast && !running.isDecreasing)
        XCTAssertTrue(running.isRunning && !running.isBlocked && running.isInitialized && !running.isLevelSwitchOn)
        XCTAssertFalse(running.isGoto)
        let goto = try SkyWatcherCodec.decodeStatus("211")
        XCTAssertFalse(goto.isSpeedMode)
        XCTAssertTrue(goto.isDecreasing && goto.isRunning && goto.isGoto && !goto.isFast)
        let idle = try SkyWatcherCodec.decodeStatus("100")
        XCTAssertTrue(idle.isSpeedMode && !idle.isRunning && !idle.isInitialized && !idle.isGoto)
        let flags = try SkyWatcherCodec.decodeStatus("033")
        XCTAssertTrue(flags.isRunning && flags.isBlocked && flags.isInitialized && flags.isLevelSwitchOn && !flags.isSpeedMode)
        for first in "01234567" {
            for second in "0123" {
                for third in "0123" {
                    let payload = "\(first)\(second)\(third)"
                    XCTAssertEqual(SkyWatcherCodec.encodeStatus(try SkyWatcherCodec.decodeStatus(payload)), payload)
                }
            }
        }
        for bad in ["", "11", "1111", "1G1", "1 1"] {
            XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.decodeStatus(bad) }?.isMalformedReply == true, bad)
        }
    }

    func testVersionReply() throws {
        let azGti = try SkyWatcherCodec.decodeVersion("0322A5")
        XCTAssertEqual(azGti, SkyWatcherVersion(major: 3, minor: 0x22, mountCode: 0xA5))
        XCTAssertEqual(azGti.description, "3.22")
        XCTAssertEqual(azGti.mountName, "AZ-GTi")
        XCTAssertEqual(azGti.mountClass, .either)
        XCTAssertEqual(SkyWatcherMountCatalog.defaultMode(0xA5), .altAzimuth)
        let heq5 = try SkyWatcherCodec.decodeVersion("010601")
        XCTAssertEqual(heq5.mountName, "HEQ5")
        XCTAssertEqual(heq5.description, "1.06")
        XCTAssertEqual(heq5.mountClass, .equatorialOnly)
        XCTAssertEqual(SkyWatcherMountCatalog.defaultMode(0x01), .equatorial)
        XCTAssertEqual(SkyWatcherCodec.encodeVersion(azGti), "0322A5")
        XCTAssertEqual(try SkyWatcherCodec.decodeVersion("03400C").mountName, "Star Adventurer GTi")
        XCTAssertEqual(SkyWatcherMountCatalog.name(0x77), "Sky-Watcher motor controller")
        XCTAssertEqual(SkyWatcherMountCatalog.mountClass(0x77), .either)
        let names: [Int: String] = [
            0x00: "EQ6", 0x01: "HEQ5", 0x02: "EQ5", 0x03: "EQ3", 0x04: "EQ8", 0x05: "AZ-EQ6", 0x06: "AZ-EQ5",
            0x0A: "Star Adventurer", 0x0C: "Star Adventurer GTi", 0x20: "EQ8-R Pro", 0x22: "AZ-EQ6 Pro", 0x23: "EQ6-R Pro",
            0x24: "EQ6 Pro", 0x25: "CQ350 Pro", 0x31: "EQ5 Pro", 0x44: "Wave 100i", 0x45: "Wave 150i", 0x80: "GT",
            0x81: "MF", 0x82: "114GT", 0x90: "Dob", 0xA2: "AZ-GTe", 0xA5: "AZ-GTi",
        ]
        for (code, name) in names { XCTAssertEqual(SkyWatcherMountCatalog.name(code), name, "0x\(String(code, radix: 16))") }
        XCTAssertEqual(SkyWatcherMountCatalog.defaultMode(0x0C), .equatorial)
        XCTAssertEqual(SkyWatcherMountCatalog.defaultMode(0xA2), .altAzimuth)
        for bad in ["", "0322A", "0322A55", "0322AG"] {
            XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.decodeVersion(bad) }?.isMalformedReply == true, bad)
        }
        XCTAssertEqual(try SkyWatcherCodec.decodeHighSpeedRatio("20"), 32)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.decodeHighSpeedRatio("00") }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherCodec.decodeHighSpeedRatio("2") }?.isMalformedReply == true)
    }

    // MARK: Speeds

    private let counts = 9_216_000
    private let timer = 1_500_000
    private let ratio = 32

    func testStepPeriodsFollowTheDocumentedFormula() throws {
        // T1 = TMR_Freq × 360 / speed / CPR (low speed).
        let sidereal = SkyWatcherSky.siderealDegreesPerSecond
        let speed = try XCTUnwrap(SkyWatcherCodec.speed(degreesPerSecond: sidereal, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio))
        XCTAssertEqual(speed.period, 14_024)
        XCTAssertFalse(speed.isHighSpeed)
        XCTAssertEqual(SkyWatcherCodec.degreesPerSecond(period: speed.period, isHighSpeed: false, countsPerRevolution: counts, timerFrequency: timer,
                                                        highSpeedRatio: ratio), sidereal, accuracy: sidereal * 1e-4)
        let slow = try XCTUnwrap(SkyWatcherCodec.speed(degreesPerSecond: 0.5, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio))
        XCTAssertEqual(slow.period, 117)
        XCTAssertFalse(slow.isHighSpeed)
        // Negative speeds give the same period; the direction is the G command's business.
        XCTAssertEqual(SkyWatcherCodec.speed(degreesPerSecond: -0.5, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio), slow)
    }

    func testHighSpeedPeriodsUseTheHighSpeedRatio() throws {
        // T1 = N × TMR_Freq × 360 / speed / CPR above 128 times the sidereal rate: 3°/s gives 32 × 1.5e6 × 360 / (3 × 9.216e6) = 625.
        let fast = try XCTUnwrap(SkyWatcherCodec.speed(degreesPerSecond: 3.0, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio))
        XCTAssertEqual(fast.period, 625)
        XCTAssertTrue(fast.isHighSpeed)
        XCTAssertEqual(SkyWatcherCodec.degreesPerSecond(period: 625, isHighSpeed: true, countsPerRevolution: counts, timerFrequency: timer,
                                                        highSpeedRatio: ratio), 3.0, accuracy: 1e-12)
        let limit = SkyWatcherCodec.lowSpeedLimitDegreesPerSecond
        XCTAssertEqual(limit, 128 * SkyWatcherSky.siderealDegreesPerSecond, accuracy: 1e-15)
        XCTAssertFalse(try XCTUnwrap(SkyWatcherCodec.speed(degreesPerSecond: limit * 0.999, countsPerRevolution: counts, timerFrequency: timer,
                                                           highSpeedRatio: ratio)).isHighSpeed)
        let above = try XCTUnwrap(SkyWatcherCodec.speed(degreesPerSecond: limit * 1.001, countsPerRevolution: counts, timerFrequency: timer,
                                                        highSpeedRatio: ratio))
        XCTAssertTrue(above.isHighSpeed)
        XCTAssertTrue(abs(above.period - 3_505) <= 5, "\(above.period)")
        // The smallest period the engine asks for is 6; a faster request is limited to it.
        let limited = try XCTUnwrap(SkyWatcherCodec.speed(degreesPerSecond: 1_000_000.0, countsPerRevolution: counts, timerFrequency: timer,
                                                          highSpeedRatio: ratio))
        XCTAssertEqual(limited.period, SkyWatcherCodec.minimumPeriod)
        XCTAssertTrue(limited.isHighSpeed)
    }

    func testUnrepresentableSpeedsGiveNoPeriod() throws {
        XCTAssertNil(SkyWatcherCodec.speed(degreesPerSecond: 0.0, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio))
        XCTAssertNil(SkyWatcherCodec.speed(degreesPerSecond: Double.nan, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio))
        XCTAssertNil(SkyWatcherCodec.speed(degreesPerSecond: Double.infinity, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio))
        XCTAssertNil(SkyWatcherCodec.speed(degreesPerSecond: 1e-9, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio))
        XCTAssertNil(SkyWatcherCodec.speed(degreesPerSecond: 1.0, countsPerRevolution: 0, timerFrequency: timer, highSpeedRatio: ratio))
        XCTAssertNil(SkyWatcherCodec.speed(degreesPerSecond: 1.0, countsPerRevolution: counts, timerFrequency: 0, highSpeedRatio: ratio))
        XCTAssertNil(SkyWatcherCodec.speed(degreesPerSecond: 1.0, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: 0))
        XCTAssertEqual(SkyWatcherCodec.degreesPerSecond(period: 0, isHighSpeed: false, countsPerRevolution: counts, timerFrequency: timer,
                                                        highSpeedRatio: ratio), 0.0, accuracy: 0.0)
        // The slowest speed that still fits in 24 bits.
        let slowest = 1_500_000.0 * 360.0 / (16_777_215.0 * 9_216_000.0)
        XCTAssertEqual(try XCTUnwrap(SkyWatcherCodec.speed(degreesPerSecond: slowest, countsPerRevolution: counts, timerFrequency: timer,
                                                           highSpeedRatio: ratio)).period, 0xFFFFFF)
        XCTAssertNil(SkyWatcherCodec.speed(degreesPerSecond: slowest * 0.9999, countsPerRevolution: counts, timerFrequency: timer, highSpeedRatio: ratio))
    }

    // MARK: Discovery

    func testDiscoveryProbe() throws {
        XCTAssertEqual(SkyWatcherDiscovery.port, 11880)
        XCTAssertEqual(SkyWatcherDiscovery.accessPointAddress, "192.168.4.1")
        XCTAssertEqual(text(SkyWatcherDiscovery.probePayload), ":e1\r")
        XCTAssertTrue(SkyWatcherDiscovery.isProbe(bytes(":e1\r")))
        XCTAssertFalse(SkyWatcherDiscovery.isProbe(bytes(":e2\r")))
        XCTAssertEqual(try SkyWatcherDiscovery.parseProbeReply(bytes("=0322A5\r")), SkyWatcherVersion(major: 3, minor: 0x22, mountCode: 0xA5))
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherDiscovery.parseProbeReply(bytes("!0\r")) }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherDiscovery.parseProbeReply(bytes("=0322A5")) }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherDiscovery.parseProbeReply(bytes("=12\r")) }?.isMalformedReply == true)
        XCTAssertTrue(skyWatcherThrown { try SkyWatcherDiscovery.parseProbeReply(bytes("hello\r")) }?.isMalformedReply == true)
    }

    func testDiscoveryAddresses() {
        XCTAssertEqual(SkyWatcherDiscovery.broadcastAddress("192.168.1.23", prefixLength: 24), "192.168.1.255")
        XCTAssertEqual(SkyWatcherDiscovery.broadcastAddress("10.0.5.77", prefixLength: 16), "10.0.255.255")
        XCTAssertEqual(SkyWatcherDiscovery.broadcastAddress("172.16.4.9", prefixLength: 20), "172.16.15.255")
        XCTAssertEqual(SkyWatcherDiscovery.broadcastAddress("192.168.4.2", prefixLength: 30), "192.168.4.3")
        for bad in ["300.1.1.1", "1.2.3", "1.2.3.4.5", "a.b.c.d", "1..2.3", "", "1.2.3.-4", "1.2.3.1234"] {
            XCTAssertNil(SkyWatcherDiscovery.broadcastAddress(bad, prefixLength: 24), bad)
        }
        XCTAssertNil(SkyWatcherDiscovery.broadcastAddress("10.0.0.1", prefixLength: 31))
        XCTAssertNil(SkyWatcherDiscovery.broadcastAddress("10.0.0.1", prefixLength: 7))
        XCTAssertEqual(SkyWatcherDiscovery.probeTargets("192.168.4.2", prefixLength: 24), ["192.168.4.1"])
        XCTAssertEqual(SkyWatcherDiscovery.probeTargets("192.168.1.23", prefixLength: 24), ["192.168.1.255", "192.168.4.1"])
        XCTAssertEqual(SkyWatcherDiscovery.probeTargets("10.0.0.5", prefixLength: 33), ["192.168.4.1"])
        XCTAssertEqual(SkyWatcherDiscovery.probeTargets("nonsense", prefixLength: 24), [])
    }

    // MARK: Configuration

    func testConfigurationAndLimitsAreClamped() {
        let location = SkyWatcherTestSupport.boulderLocation
        let clamped = SkyWatcherConfiguration(location: location, exchangeTimeoutSeconds: 99.0, attempts: 0, trackingUpdateIntervalSeconds: 0.0,
                                              assumedSlewDegreesPerSecond: 1e9, refinementToleranceDegrees: -1.0,
                                              maximumAlignmentResidualDegrees: Double.nan)
        XCTAssertEqual(clamped.exchangeTimeoutSeconds, 5.0, accuracy: 0.0)
        XCTAssertEqual(clamped.attempts, 1)
        XCTAssertEqual(clamped.trackingUpdateIntervalSeconds, 0.25, accuracy: 0.0)
        XCTAssertEqual(clamped.assumedSlewDegreesPerSecond, 10.0, accuracy: 0.0)
        XCTAssertEqual(clamped.refinementToleranceDegrees, 0.002, accuracy: 0.0)
        XCTAssertEqual(clamped.maximumAlignmentResidualDegrees, 1.0, accuracy: 0.0)
        XCTAssertEqual(SkyWatcherConfiguration(location: location, attempts: 99).attempts, 6)
        XCTAssertEqual(SkyWatcherConfiguration(location: location, exchangeTimeoutSeconds: 0.0).exchangeTimeoutSeconds, 0.2, accuracy: 0.0)
        let limits = SkyWatcherLimits(minimumAltitudeDegrees: -90.0, maximumAltitudeDegrees: 10.0, azimuthMinimumDegrees: 5.0,
                                      azimuthMaximumDegrees: -5.0, meridianOverlapDegrees: 99.0, pathMarginDegrees: Double.nan,
                                      maximumAxisRateDegreesPerSecond: 0.0)
        XCTAssertEqual(limits.minimumAltitudeDegrees, -20.0, accuracy: 0.0)
        XCTAssertEqual(limits.maximumAltitudeDegrees, 60.0, accuracy: 0.0)
        XCTAssertEqual(limits.azimuthMinimumDegrees, 0.0, accuracy: 0.0)
        XCTAssertEqual(limits.azimuthMaximumDegrees, 0.0, accuracy: 0.0)
        XCTAssertEqual(limits.meridianOverlapDegrees, 30.0, accuracy: 0.0)
        XCTAssertEqual(limits.pathMarginDegrees, 5.0, accuracy: 0.0)
        XCTAssertEqual(limits.maximumAxisRateDegreesPerSecond, 0.1, accuracy: 0.0)
        XCTAssertEqual(SkyWatcherLimits.standard, SkyWatcherLimits())
        XCTAssertEqual(MountProtocol(rawValue: "skywatcher"), .skywatcher)
        for mode in SkyWatcherMountMode.allCases { XCTAssertEqual(SkyWatcherMountMode(rawValue: mode.rawValue), mode) }
        for side in SkyWatcherPierSide.allCases { XCTAssertEqual(SkyWatcherPierSide(rawValue: side.rawValue), side) }
        for axis in SkyWatcherAxis.allCases { XCTAssertEqual(SkyWatcherAxis(rawValue: axis.rawValue), axis) }
        for strategy in SkyWatcherTrackingStrategy.allCases { XCTAssertEqual(SkyWatcherTrackingStrategy(rawValue: strategy.rawValue), strategy) }
        for mountClass in SkyWatcherMountClass.allCases { XCTAssertEqual(SkyWatcherMountClass(rawValue: mountClass.rawValue), mountClass) }
        for mode in SkyWatcherMotionMode.allCases { XCTAssertEqual(SkyWatcherMotionMode.fromCode(mode.code), mode) }
        for direction in SkyWatcherDirection.allCases { XCTAssertEqual(SkyWatcherDirection.fromCode(direction.code), direction) }
        XCTAssertNil(SkyWatcherMotionMode.fromCode("4"))
        XCTAssertEqual(SkyWatcherAxis.allCases.map { $0.index }, [0, 1])
        XCTAssertEqual(SkyWatcherAxis.allCases.map { $0.channel }, ["1", "2"])
    }
}
