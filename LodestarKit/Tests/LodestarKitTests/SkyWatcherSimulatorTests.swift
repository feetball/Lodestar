import XCTest
@testable import LodestarKit

/// Tests of the Sky-Watcher motor controller simulator itself: protocol behaviour, physics, fault injection, true geometry.
final class SkyWatcherSimulatorTests: XCTestCase {
    private let countsPerDegree = 9_216_000.0 / 360.0

    private func make(mode: SkyWatcherMountMode = .altAzimuth, errors: SkyWatcherPointingErrors = SkyWatcherPointingErrors(),
                      axis1Inverted: Bool = false, seed: UInt64 = 1) -> (ManualMountClock, SkyWatcherSimulator) {
        let clock = ManualMountClock(start: SkyWatcherTestSupport.start)
        let simulator = SkyWatcherSimulator(clock: clock, location: SkyWatcherTestSupport.boulderLocation, mode: mode, errors: errors,
                                            axis1Inverted: axis1Inverted, seed: seed)
        return (clock, simulator)
    }

    private func ask(_ simulator: SkyWatcherSimulator, _ command: String) throws -> String {
        try simulator.send(MountText.latin1Bytes(command))
        return MountText.latin1(try simulator.receive(maxCount: 64, timeoutSeconds: 1.0))
    }

    private func initialized() throws -> (ManualMountClock, SkyWatcherSimulator) {
        let made = make()
        XCTAssertEqual(try ask(made.1, ":F3\r"), "=\r")
        return made
    }

    private func counts(_ simulator: SkyWatcherSimulator, _ axis: Int) throws -> Int {
        let reply = try ask(simulator, ":j\(axis)\r")
        return try SkyWatcherCodec.decodePosition(String(reply.dropFirst().prefix(6)))
    }

    // MARK: Inquiries and state

    func testTheSimulatorAnswersTheInquiries() throws {
        let (_, simulator) = make()
        XCTAssertEqual(try ask(simulator, ":e1\r"), "=0322A5\r")
        XCTAssertEqual(try ask(simulator, ":e2\r"), "=0322A5\r")
        XCTAssertEqual(try ask(simulator, ":a1\r"), "=\(try SkyWatcherCodec.encode24(9_216_000))\r")
        XCTAssertEqual(try ask(simulator, ":a2\r"), "=\(try SkyWatcherCodec.encode24(9_216_000))\r")
        XCTAssertEqual(try ask(simulator, ":b1\r"), "=\(try SkyWatcherCodec.encode24(1_500_000))\r")
        XCTAssertEqual(try ask(simulator, ":g1\r"), "=20\r")
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=100\r")
        XCTAssertEqual(try ask(simulator, ":j1\r"), "=000080\r")
        XCTAssertEqual(try ask(simulator, ":q1010000\r"), "=008000\r")
        XCTAssertEqual(try ask(simulator, ":D1\r"), "=C83600\r")
        XCTAssertEqual(try ask(simulator, ":s1\r"), "=\(try SkyWatcherCodec.encode24(9_216_000 / 40))\r")
        XCTAssertEqual(try ask(simulator, ":i1\r"), "=000000\r")
        XCTAssertEqual(try ask(simulator, ":O11\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":P12\r"), "=\r")
    }

    func testMotionNeedsInitializationAndWakefulness() throws {
        let (_, simulator) = make()
        XCTAssertEqual(try ask(simulator, ":G110\r"), "!4\r")
        XCTAssertEqual(try ask(simulator, ":I1102000\r"), "!4\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "!4\r")
        XCTAssertEqual(try ask(simulator, ":F1\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=101\r")
        XCTAssertEqual(try ask(simulator, ":G110\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":G210\r"), "!4\r")
        XCTAssertEqual(try ask(simulator, ":f2\r"), "=100\r")
        XCTAssertEqual(try ask(simulator, ":F3\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":G210\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":B11\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":G110\r"), "!5\r")
        XCTAssertEqual(try ask(simulator, ":B10\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":G110\r"), "=\r")
    }

    func testMalformedCommandsGetTheDocumentedErrors() throws {
        let (_, simulator) = try initialized()
        XCTAssertEqual(try ask(simulator, ":x1\r"), "!0\r")
        XCTAssertEqual(try ask(simulator, ":j\r"), "!1\r")
        XCTAssertEqual(try ask(simulator, ":G11\r"), "!1\r")
        XCTAssertEqual(try ask(simulator, ":H12345\r"), "!1\r")
        XCTAssertEqual(try ask(simulator, ":G1AB\r"), "!3\r")
        XCTAssertEqual(try ask(simulator, ":G140\r"), "!3\r")
        XCTAssertEqual(try ask(simulator, ":G102\r"), "!3\r")
        XCTAssertEqual(try ask(simulator, ":H1ZZZZZZ\r"), "!3\r")
        XCTAssertEqual(try ask(simulator, ":H1abcdef\r"), "!3\r")
        XCTAssertEqual(try ask(simulator, ":j9\r"), "!3\r")
        XCTAssertEqual(try ask(simulator, ":j3\r"), "!3\r")
        XCTAssertEqual(try ask(simulator, ":I1000000\r"), "!3\r")
        // Noise in front of the colon is ignored, and a second colon starts the command again.
        XCTAssertEqual(try ask(simulator, "xx:j1\r"), "=000080\r")
        XCTAssertEqual(try ask(simulator, ":G1:j1\r"), "=000080\r")
        XCTAssertEqual(try ask(simulator, "::j1\r"), "=000080\r")
        // A line without a colon gets no answer at all.
        try simulator.send(MountText.latin1Bytes("j1\r"))
        XCTAssertTrue(skyWatcherThrown { try simulator.receive(maxCount: 64, timeoutSeconds: 0.5) }?.isTimeout == true)
        // Neither does a command that is not finished.
        try simulator.send(MountText.latin1Bytes(":j1"))
        XCTAssertTrue(skyWatcherThrown { try simulator.receive(maxCount: 64, timeoutSeconds: 0.5) }?.isTimeout == true)
        try simulator.send(MountText.latin1Bytes("\r"))
        XCTAssertEqual(MountText.latin1(try simulator.receive(maxCount: 64, timeoutSeconds: 1.0)), "=000080\r")
    }

    func testPositionCanBeSetWhileStopped() throws {
        let (_, simulator) = try initialized()
        XCTAssertEqual(try ask(simulator, ":E1120080\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":j1\r"), "=120080\r")
        XCTAssertEqual(try ask(simulator, ":d1\r"), "=120080\r")
        XCTAssertEqual(try counts(simulator, 1), 0x12)
        XCTAssertEqual(try ask(simulator, ":E2FFFF7F\r"), "=\r")
        XCTAssertEqual(try counts(simulator, 2), -1)
        XCTAssertEqual(try ask(simulator, ":G110\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":I1102000\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":E1000080\r"), "!2\r")
        XCTAssertEqual(try ask(simulator, ":G110\r"), "!2\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "!2\r")
    }

    // MARK: Speed mode

    func testSpeedModeRunsAtTheStepPeriod() throws {
        let (clock, simulator) = try initialized()
        let sidereal = try XCTUnwrap(SkyWatcherCodec.speed(degreesPerSecond: SkyWatcherSky.siderealDegreesPerSecond, countsPerRevolution: 9_216_000,
                                                           timerFrequency: 1_500_000, highSpeedRatio: 32))
        XCTAssertEqual(try ask(simulator, ":G110\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":I1\(try SkyWatcherCodec.encode24(sidereal.period))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=111\r")
        clock.advance(seconds: 100.0)
        // 100 s of sidereal motion (plus the latency of the replies, about 0.15 s): 106.96 counts per second.
        XCTAssertEqual(Double(try counts(simulator, 1)), 10_696.0, accuracy: 15.0)
        XCTAssertEqual(simulator.axis1Degrees, 100.15 * SkyWatcherSky.siderealDegreesPerSecond, accuracy: 1e-4)
        XCTAssertEqual(try counts(simulator, 2), 0)
        XCTAssertEqual(simulator.speedStarts, 1)
        XCTAssertEqual(try ask(simulator, ":i1\r"), "=\(try SkyWatcherCodec.encode24(sidereal.period))\r")
        // A new period changes the speed while the axis runs (low-speed mode).
        XCTAssertEqual(try ask(simulator, ":I1\(try SkyWatcherCodec.encode24(sidereal.period / 2))\r"), "=\r")
        let before = try counts(simulator, 1)
        clock.advance(seconds: 10.0)
        XCTAssertEqual(Double(try counts(simulator, 1) - before), 2 * 10.05 * 106.96, accuracy: 8.0)
    }

    func testDirectionAndHighSpeedMode() throws {
        let (clock, simulator) = try initialized()
        // Axis 2 backwards at high speed: 3°/s.
        XCTAssertEqual(try ask(simulator, ":G231\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":I2\(try SkyWatcherCodec.encode24(625))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J2\r"), "=\r")
        // B0 speed mode, B1 counter-clockwise, B2 fast: digit 7.
        XCTAssertEqual(try ask(simulator, ":f2\r"), "=711\r")
        clock.advance(seconds: 10.0)
        XCTAssertEqual(simulator.axis2Degrees, -30.0, accuracy: 0.3)
        XCTAssertEqual(simulator.peakSpeedDegreesPerSecond, 3.0, accuracy: 0.01)
        // In high-speed mode the period cannot be changed while the axis runs.
        XCTAssertEqual(try ask(simulator, ":I2\(try SkyWatcherCodec.encode24(700))\r"), "!2\r")
        // The controller never exceeds its maximum speed: period 6 would be far faster.
        XCTAssertEqual(try ask(simulator, ":L2\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":G230\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":I2\(try SkyWatcherCodec.encode24(6))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J2\r"), "=\r")
        let start = simulator.axis2Degrees
        clock.advance(seconds: 1.0)
        XCTAssertEqual(simulator.axis2Degrees - start, 3.0, accuracy: 0.01)
    }

    func testStoppingBrakesOrStopsAtOnce() throws {
        let (clock, simulator) = try initialized()
        XCTAssertEqual(try ask(simulator, ":G130\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":I1\(try SkyWatcherCodec.encode24(625))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        clock.advance(seconds: 10.0)
        let before = simulator.axis1Degrees
        XCTAssertEqual(try ask(simulator, ":K1\r"), "=\r")
        // Still decelerating right after the command (speed mode, fast, running).
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=511\r")
        clock.advance(seconds: 2.0)
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=101\r")
        // Braking from 3°/s at 6°/s² takes 0.5 s and 0.75°.
        XCTAssertEqual(simulator.axis1Degrees - before, 0.75, accuracy: 0.05)
        // L stops instantly.
        XCTAssertEqual(try ask(simulator, ":G130\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        clock.advance(seconds: 5.0)
        XCTAssertEqual(try ask(simulator, ":L1\r"), "=\r")
        let stopped = simulator.axis1Degrees
        clock.advance(seconds: 5.0)
        XCTAssertEqual(simulator.axis1Degrees, stopped, accuracy: 1e-9)
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=101\r")
        XCTAssertEqual(try ask(simulator, ":K3\r"), "=\r")
    }

    // MARK: GOTO

    func testFastGotoAcceleratesCruisesAndBrakes() throws {
        let (clock, simulator) = try initialized()
        let increment = Int(90.0 * countsPerDegree)
        XCTAssertEqual(try ask(simulator, ":G100\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":H1\(try SkyWatcherCodec.encode24(increment))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":M1\(try SkyWatcherCodec.encode24(3200))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        // GOTO mode (B0 = 0), fast (B2): digit 4.
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=411\r")
        XCTAssertEqual(try ask(simulator, ":h1\r"), "=\(try SkyWatcherCodec.encodePosition(increment))\r")
        XCTAssertEqual(try ask(simulator, ":k10\r"), "=\(try SkyWatcherCodec.encode24(increment))\r")
        clock.advance(seconds: 10.0)
        XCTAssertTrue(simulator.isMoving)
        XCTAssertTrue((20.0 ... 40.0).contains(simulator.axis1Degrees), "\(simulator.axis1Degrees)")
        // 90° at 3°/s with 6°/s² ramps: 30.5 s.
        clock.advance(seconds: 19.0)
        XCTAssertTrue(simulator.isMoving)
        clock.advance(seconds: 2.0)
        XCTAssertTrue(!simulator.isMoving)
        XCTAssertEqual(simulator.axis1Degrees, 90.0, accuracy: 1e-3)
        XCTAssertEqual(try counts(simulator, 1), increment)
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=101\r")
        XCTAssertEqual(simulator.gotosStarted, 1)
        XCTAssertEqual(simulator.peakSpeedDegreesPerSecond, 3.0, accuracy: 0.01)
        // Backwards: the direction digit 1 decreases the count by the increment.
        XCTAssertEqual(try ask(simulator, ":G101\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":H1\(try SkyWatcherCodec.encode24(increment / 3))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        clock.advance(seconds: 60.0)
        XCTAssertEqual(simulator.axis1Degrees, 60.0, accuracy: 1e-3)
    }

    func testSlowGotoRunsAtConstantSpeedAndAbsoluteTargetsWork() throws {
        let (clock, simulator) = try initialized()
        let increment = Int(5.0 * countsPerDegree)
        XCTAssertEqual(try ask(simulator, ":G220\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":H2\(try SkyWatcherCodec.encode24(increment))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J2\r"), "=\r")
        // Slow GOTO: digit 0 (B0 = 0 goto, B2 = 0 slow).
        XCTAssertEqual(try ask(simulator, ":f2\r"), "=011\r")
        clock.advance(seconds: 5.0)
        XCTAssertEqual(simulator.axis2Degrees, 2.5, accuracy: 0.1)
        clock.advance(seconds: 6.0)
        XCTAssertEqual(simulator.axis2Degrees, 5.0, accuracy: 1e-3)
        XCTAssertTrue(!simulator.isMoving)
        // An absolute target (S) needs no increment.
        XCTAssertEqual(try ask(simulator, ":G100\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":S1\(try SkyWatcherCodec.encodePosition(-50_000))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        clock.advance(seconds: 30.0)
        XCTAssertEqual(try counts(simulator, 1), -50_000)
        // Both axes at once with J3.
        XCTAssertEqual(try ask(simulator, ":G100\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":G200\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":H1\(try SkyWatcherCodec.encode24(1000))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":H2\(try SkyWatcherCodec.encode24(2000))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J3\r"), "=\r")
        clock.advance(seconds: 10.0)
        XCTAssertEqual(try counts(simulator, 1), -49_000)
        XCTAssertEqual(try counts(simulator, 2), increment + 2000)
        XCTAssertEqual(simulator.gotosStarted, 4)
    }

    func testStoppingAGotoAndErrorsOfTheGotoSequence() throws {
        let (clock, simulator) = try initialized()
        XCTAssertEqual(try ask(simulator, ":G100\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":H1\(try SkyWatcherCodec.encode24(2_000_000))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "!2\r")
        clock.advance(seconds: 5.0)
        XCTAssertEqual(try ask(simulator, ":K1\r"), "=\r")
        clock.advance(seconds: 3.0)
        XCTAssertTrue(!simulator.isMoving)
        XCTAssertTrue((10.0 ... 20.0).contains(simulator.axis1Degrees), "\(simulator.axis1Degrees)")
        // Starting in speed mode without a period is refused.
        XCTAssertEqual(try ask(simulator, ":G210\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J2\r"), "!3\r")
    }

    // MARK: Faults

    func testInjectedFaultsDamageTheReply() throws {
        let (_, simulator) = make()
        simulator.inject("j", .silence)
        try simulator.send(MountText.latin1Bytes(":j1\r"))
        XCTAssertTrue(skyWatcherThrown { try simulator.receive(maxCount: 64, timeoutSeconds: 0.6) }?.isTimeout == true)
        XCTAssertEqual(try ask(simulator, ":j1\r"), "=000080\r")
        simulator.inject("j1", .replace(text: "=12"))
        XCTAssertEqual(try ask(simulator, ":j1\r"), "=12")
        simulator.inject("f", .truncate(keep: 2))
        XCTAssertEqual(try ask(simulator, ":f1\r"), "=1")
        simulator.inject("a", .disconnect)
        try simulator.send(MountText.latin1Bytes(":a1\r"))
        XCTAssertTrue(skyWatcherThrown { try simulator.receive(maxCount: 64, timeoutSeconds: 0.6) }?.isTransport == true)
        XCTAssertTrue(skyWatcherThrown { try simulator.send(MountText.latin1Bytes(":j1\r")) }?.isTransport == true)
        XCTAssertEqual(Array(simulator.commandLog.prefix(4)), ["j1", "j1", "j1", "f1"])
    }

    func testRandomLossAndGarbleAreSeededAndBounded() throws {
        let (_, simulator) = make(seed: 99)
        simulator.requestLossProbability = 0.3
        var answered = 0
        for _ in 0 ..< 1000 {
            try simulator.send(MountText.latin1Bytes(":j1\r"))
            do {
                _ = try simulator.receive(maxCount: 64, timeoutSeconds: 0.1)
                answered += 1
            } catch MountError.timeout {
                // lost
            }
            try simulator.discardPendingInput()
        }
        XCTAssertTrue((620 ... 780).contains(answered), "\(answered) answered")
        // A lost reply still changes the mount's state.
        let (_, other) = make(seed: 5)
        other.replyLossProbability = 1.0
        try other.send(MountText.latin1Bytes(":F1\r"))
        XCTAssertTrue(skyWatcherThrown { try other.receive(maxCount: 64, timeoutSeconds: 0.1) }?.isTimeout == true)
        other.replyLossProbability = 0.0
        XCTAssertEqual(try ask(other, ":f1\r"), "=101\r")
        // All four kinds of damage occur, and every damaged reply is either rejected by the codec or still readable.
        let (_, damaged) = make(seed: 3)
        damaged.garbleProbability = 1.0
        var kinds = Set<String>()
        for _ in 0 ..< 200 {
            try damaged.send(MountText.latin1Bytes(":j1\r"))
            let reply: [UInt8]
            do {
                reply = MountText.latin1Bytes(MountText.latin1(try damaged.receive(maxCount: 64, timeoutSeconds: 0.1)))
            } catch MountError.timeout {
                kinds.insert("incomplete")
                continue
            }
            try damaged.discardPendingInput()
            if !reply.contains(0x0D) {
                kinds.insert("incomplete")
                continue
            }
            do {
                let parsed = try SkyWatcherCodec.parseDatagram(reply)
                kinds.insert(reply.count > 9 ? "doubled" : "junk in front")
                XCTAssertEqual(parsed, .success(payload: "000080"))
            } catch MountError.malformedReply {
                kinds.insert("bad character")
            }
        }
        XCTAssertEqual(kinds, Set(["incomplete", "doubled", "junk in front", "bad character"]))
    }

    func testTheRandomGeneratorIsIdenticalInBothLanguages() {
        let first = SkyWatcherSimulatedRandom(seed: 1)
        let expected = [0.28083505005035947, 0.6711372530266764, 0.7258461452833668, 0.303529299965799, 0.056176763098259475]
        for value in expected { XCTAssertEqual(first.next(), value, accuracy: 1e-15) }
        let second = SkyWatcherSimulatedRandom(seed: 12345)
        for value in [0.5950924872394683, 0.7531544145408081, 0.07656564459726423] { XCTAssertEqual(second.next(), value, accuracy: 1e-15) }
        XCTAssertEqual(SkyWatcherSimulatedRandom(seed: 0).next(), SkyWatcherSimulatedRandom(seed: 0x2545F4914F6CDD1D).next(), accuracy: 0.0)
        let random = SkyWatcherSimulatedRandom(seed: 77)
        for _ in 0 ..< 1000 {
            let value = random.next()
            XCTAssertTrue(value >= 0.0 && value < 1.0)
        }
    }

    // MARK: True geometry

    private func assertVector(_ expected: Vector3, _ actual: Vector3, accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "x \(actual)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "y \(actual)", file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, "z \(actual)", file: file, line: line)
    }

    func testTruePointingFollowsTheGeometry() throws {
        let (_, home) = make()
        assertVector(Vector3(0.0, 1.0, 0.0), home.truePointing())
        home.placeAxes(axis1Degrees: 90.0, axis2Degrees: 45.0)
        assertVector(Vector3(AstroMath.cosDeg(45.0), 0.0, AstroMath.sinDeg(45.0)), home.truePointing())
        XCTAssertEqual(home.axis1Degrees, 90.0, accuracy: 1e-9)
        XCTAssertEqual(try counts(home, 1), Int(90.0 * countsPerDegree))
        let (_, tilted) = make(errors: SkyWatcherPointingErrors(baseTiltX: 1.0))
        assertVector(Vector3(0.0, AstroMath.cosDeg(1.0), AstroMath.sinDeg(1.0)), tilted.truePointing())
        let (_, polar) = make(mode: .equatorial, errors: SkyWatcherPointingErrors(baseTiltY: 0.5))
        assertVector(Vector3(AstroMath.sinDeg(0.5), 0.0, AstroMath.cosDeg(0.5)), polar.truePointing())
        let (_, index) = make(mode: .equatorial, errors: SkyWatcherPointingErrors(axis2Index: 3.0))
        // Home with a dec index error: 3° away from the pole, towards the west (positive angles).
        assertVector(Vector3(0.0, -AstroMath.sinDeg(3.0), AstroMath.cosDeg(3.0)), index.truePointing())
    }

    func testInvertedAxesCountBackwards() throws {
        let (clock, simulator) = make(axis1Inverted: true)
        simulator.placeAxes(axis1Degrees: 10.0, axis2Degrees: 0.0)
        XCTAssertEqual(simulator.axis1Degrees, 10.0, accuracy: 1e-9)
        XCTAssertEqual(try counts(simulator, 1), -Int(10.0 * countsPerDegree))
        XCTAssertEqual(try ask(simulator, ":F3\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":G110\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":I1\(try SkyWatcherCodec.encode24(6000))\r"), "=\r")
        XCTAssertEqual(try ask(simulator, ":J1\r"), "=\r")
        clock.advance(seconds: 10.0)
        // Direction digit 0 increases the count, which turns an inverted axis towards smaller angles.
        XCTAssertTrue(simulator.axis1Degrees < 10.0)
        XCTAssertTrue(abs(simulator.truePointing().length - 1.0) < 1e-12)
    }
}
