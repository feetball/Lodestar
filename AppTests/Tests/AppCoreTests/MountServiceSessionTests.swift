import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Tests of `MountSession` (Services/MountSession.swift): the jobs on the worker thread, the errors they report, the
/// controller rebuilt on new limits, and the end of the session. The mount is the scripted driver of MountServiceTests.swift
/// behind the in-memory `.simulated` channel.
@MainActor
final class MountServiceSessionTests: XCTestCase {
    private typealias Fake = MountServiceTests.Fake
    private typealias Gate = MountServiceTests.Gate
    private typealias Recorder = MountServiceTests.Recorder

    /// Close to the north pole an object's altitude is its declination whatever the time, so a place at declination 60 is
    /// 60 degrees up for the engine's altitude check at any hour.
    private static let pole = Observer(location: GeographicLocation(latitude: 89.9, longitude: 0.0, elevation: 0.0))
    private static let highPlace = EquatorialCoordinate(rightAscension: 30.0, declination: 60.0)

    private var sessions: [MountSession] = []
    private var fakes: [Fake] = []

    override func tearDown() async throws {
        for fake in fakes { fake.releaseAll() }
        for session in sessions { session.shutdown() }
        sessions = []
        fakes = []
        try await super.tearDown()
    }

    // MARK: Helpers

    private func eventually(timeout: TimeInterval = 10.0, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    private func pause(_ seconds: TimeInterval = 0.1) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000.0))
    }

    private func newSession() -> MountSession {
        let session = MountSession(channel: .simulated)
        sessions.append(session)
        return session
    }

    /// A session that has done its handshake with `fake`.
    private func connect(_ fake: Fake, settings: MountSettings = MountSettings(altitudeLimit: -10.0),
                         option: MountConnectionOption? = nil)
        async -> (session: MountSession, outcome: MountJobResult<MountCapabilities>) {
        fakes.append(fake)
        let session = newSession()
        let chosen = option ?? MountServiceTests.option(for: fake)
        let outcome = await session.connect(option: chosen, options: MountDriverOptions(), observer: Self.pole,
                                            settings: settings)
        return (session: session, outcome: outcome)
    }

    private func failure<Value>(_ result: Result<Value, MountError>) -> MountError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    // MARK: - Connecting

    func testConnectingReturnsWhatTheMountCanDoAndTheStatusItStartsIn() async {
        let fake = Fake()
        let connection = await connect(fake)
        XCTAssertEqual(connection.outcome.result, .success(Fake.makeCapabilities()))
        XCTAssertEqual(connection.outcome.status.phase, .idle)
        XCTAssertEqual(connection.outcome.status.position, EquatorialCoordinate(rightAscension: 100.0, declination: 20.0))
        XCTAssertEqual(connection.outcome.status.isTracking, true)
        XCTAssertNil(connection.outcome.detail, "a driver without detail reports none")
        XCTAssertEqual(fake.connectCount, 1)
    }

    func testAFailureToMakeTheDriverIsReportedAsTheMountError() async {
        let fake = Fake()
        let option = MountServiceTests.option(id: "demo-refusing") { _, _ in
            throw MountError.invalidInput(detail: "your location is not known yet")
        }
        let connection = await connect(fake, option: option)
        XCTAssertEqual(failure(connection.outcome.result), .invalidInput(detail: "your location is not known yet"))
        XCTAssertEqual(connection.outcome.status, MountStatus.disconnected)
        XCTAssertEqual(fake.connectCount, 0)
    }

    func testAnUnexpectedErrorBecomesATransportError() async {
        let fake = Fake()
        let option = MountServiceTests.option(id: "demo-boom") { _, _ in throw MountServiceTests.Boom() }
        let connection = await connect(fake, option: option)
        XCTAssertEqual(failure(connection.outcome.result), .transport(detail: "unexpected failure"))
        XCTAssertEqual(connection.outcome.status, MountStatus.disconnected)
    }

    func testAHandshakeThatFailsLeavesTheSessionWithoutAController() async {
        let fake = Fake()
        fake.configure { $0.connectError = .busy }
        let connection = await connect(fake)
        XCTAssertEqual(failure(connection.outcome.result), .busy)
        XCTAssertEqual(connection.outcome.status, MountStatus.disconnected)
        XCTAssertEqual(fake.disconnectCount, 1, "the controller lets go of the driver after a failed handshake")
        let later: MountJobResult<MountPhase> = await connection.session.run { $0.status.phase }
        XCTAssertEqual(failure(later.result), .notConnected)
    }

    func testTheMountIsPreparedBeforeEveryJob() async {
        let fake = Fake()
        let prepared = Recorder()
        let option = MountServiceTests.option(id: "demo-prepared") { _, _ in
            MountDriverBundle(driver: fake, clock: SystemMountClock(), prepare: { prepared.add("prepare") })
        }
        let connection = await connect(fake, option: option)
        let session = connection.session
        XCTAssertEqual(prepared.count, 1, "the handshake")
        _ = await session.run { $0.status.phase }
        XCTAssertEqual(prepared.count, 2)
        _ = await session.poll()
        XCTAssertEqual(prepared.count, 3)
        _ = await session.runDriver { $0.kind }
        XCTAssertEqual(prepared.count, 4)
        _ = await session.reconfigure(MountSettings(altitudeLimit: -10.0))
        XCTAssertEqual(prepared.count, 5)
    }

    // MARK: - Jobs

    func testJobsBeforeTheHandshakeFindNoMount() async {
        let session = newSession()
        let job: MountJobResult<MountPhase> = await session.run { $0.status.phase }
        XCTAssertEqual(failure(job.result), .notConnected)
        XCTAssertEqual(job.status, MountStatus.disconnected)
        XCTAssertNil(job.detail)
        let driverJob: MountJobResult<Bool> = await session.runDriver { _ in true }
        XCTAssertEqual(failure(driverJob.result), .notConnected)
        XCTAssertEqual(driverJob.status, MountStatus.disconnected)
        let polled = await session.poll()
        XCTAssertEqual(failure(polled.result), .notConnected)
        let reconfigured = await session.reconfigure(MountSettings())
        XCTAssertEqual(failure(reconfigured.result), .notConnected)
        XCTAssertEqual(reconfigured.status, MountStatus.disconnected)
    }

    func testAJobReturnsItsValueAndTheStatusItLeft() async {
        let connection = await connect(Fake())
        let job: MountJobResult<MountPhase> = await connection.session.run { $0.status.phase }
        XCTAssertEqual(job.result, .success(.idle))
        XCTAssertEqual(job.status.phase, .idle)
        let place = Self.highPlace
        let started: MountJobResult<Void> = await connection.session.run { controller in try controller.goto(place) }
        XCTAssertNil(failure(started.result))
        XCTAssertEqual(started.status.phase, .slewing, "the status is the controller's after the job")
        XCTAssertEqual(started.status.target, place)
    }

    func testAJobThatThrowsAMountErrorReportsItWithTheStatus() async {
        let connection = await connect(Fake())
        let job: MountJobResult<Int> = await connection.session.run { _ in throw MountError.parked }
        XCTAssertEqual(failure(job.result), .parked)
        XCTAssertEqual(job.status.phase, .idle, "the controller's status, not the one of a lost mount")
    }

    func testAJobThatThrowsAnythingElseReportsATransportError() async {
        let connection = await connect(Fake())
        let job: MountJobResult<Int> = await connection.session.run { _ in throw MountServiceTests.Boom() }
        XCTAssertEqual(failure(job.result), .transport(detail: "unexpected failure"))
    }

    func testAJobThatTheEngineRefusesReportsTheRefusal() async {
        let fake = Fake()
        fake.configure { $0.capabilities = Fake.makeCapabilities(canSync: false) }
        let connection = await connect(fake)
        let place = Self.highPlace
        let job: MountJobResult<MountSyncResult> = await connection.session.run { controller in
            try controller.sync(place)
        }
        XCTAssertEqual(failure(job.result), .notSupported(feature: .sync))
        XCTAssertEqual(job.status.phase, .idle)
        XCTAssertTrue(fake.syncs.isEmpty)
    }

    func testPollingReturnsTheFreshStatus() async {
        let fake = Fake()
        let connection = await connect(fake)
        let moved = EquatorialCoordinate(rightAscension: 200.0, declination: -30.0)
        fake.configure { $0.position = moved }
        let polled = await connection.session.poll()
        XCTAssertEqual(polled.status.position, moved)
        XCTAssertEqual(polled.result, .success(polled.status))
    }

    func testAJobOnTheDriverGetsTheDriverItself() async {
        let fake = Fake()
        let connection = await connect(fake)
        let same: MountJobResult<Bool> = await connection.session.runDriver { driver in driver === fake }
        XCTAssertEqual(same.result, .success(true))
        XCTAssertEqual(same.status.phase, .idle)
        let refused: MountJobResult<Int> = await connection.session.runDriver { _ in throw MountError.standby }
        XCTAssertEqual(failure(refused.result), .standby)
        let unexpected: MountJobResult<Int> = await connection.session.runDriver { _ in throw MountServiceTests.Boom() }
        XCTAssertEqual(failure(unexpected.result), .transport(detail: "unexpected failure"))
    }

    // MARK: - Centring the simulated mount

    func testCentringCallsTheSimulatorBetweenTwoStops() async {
        let fake = Fake()
        let placed = Recorder()
        let option = MountServiceTests.option(for: fake, centre: { place in
            placed.add("\(place.rightAscension) \(place.declination)")
        })
        let connection = await connect(fake, option: option)
        let outcome = await connection.session.centreSimulated(on: Self.highPlace)
        XCTAssertNil(failure(outcome.result))
        XCTAssertEqual(placed.all, ["\(Self.highPlace.rightAscension) \(Self.highPlace.declination)"])
        XCTAssertEqual(fake.abortCount, 2)
        XCTAssertEqual(outcome.status.phase, .idle)
    }

    func testCentringNeedsAMountThatCanBeCentred() async {
        let connection = await connect(Fake())
        let outcome = await connection.session.centreSimulated(on: Self.highPlace)
        XCTAssertEqual(failure(outcome.result), .notSupported(feature: .other))
        XCTAssertEqual(outcome.status.phase, .idle, "the status is the controller's")
        let bare = newSession()
        let before = await bare.centreSimulated(on: Self.highPlace)
        XCTAssertEqual(failure(before.result), .notSupported(feature: .other))
        XCTAssertEqual(before.status, MountStatus.disconnected)
    }

    func testCentringReportsAStopThatFails() async {
        let fake = Fake()
        let option = MountServiceTests.option(for: fake, centre: { _ in })
        let connection = await connect(fake, option: option)
        fake.configure { $0.abortError = .rejected(detail: "jammed") }
        let outcome = await connection.session.centreSimulated(on: Self.highPlace)
        XCTAssertEqual(failure(outcome.result), .rejected(detail: "jammed"))
    }

    // MARK: - New limits

    func testReconfiguringRunsTheControllerOnTheNewLimits() async {
        let fake = Fake()
        let connection = await connect(fake)
        let before: MountJobResult<Double> = await connection.session.run { $0.settings.altitudeLimit }
        XCTAssertEqual(before.result, .success(-10.0))
        let outcome = await connection.session.reconfigure(MountSettings(altitudeLimit: 20.0))
        XCTAssertNil(failure(outcome.result))
        XCTAssertEqual(outcome.status.phase, .idle)
        XCTAssertEqual(fake.connectCount, 2, "the new controller does its handshake again")
        let after: MountJobResult<Double> = await connection.session.run { $0.settings.altitudeLimit }
        XCTAssertEqual(after.result, .success(20.0))
    }

    func testReconfiguringIsRefusedWhileTheMountMoves() async {
        let fake = Fake()
        let connection = await connect(fake)
        let place = Self.highPlace
        let _: MountJobResult<Void> = await connection.session.run { controller in try controller.goto(place) }
        let outcome = await connection.session.reconfigure(MountSettings(altitudeLimit: 20.0))
        XCTAssertEqual(failure(outcome.result), .busy)
        XCTAssertEqual(outcome.status.phase, .slewing)
        XCTAssertEqual(fake.connectCount, 1)
        let limit: MountJobResult<Double> = await connection.session.run { $0.settings.altitudeLimit }
        XCTAssertEqual(limit.result, .success(-10.0), "the old limits stay in force")
    }

    func testAFailedReconfigurationKeepsTheOldControllerAndReconnectsTheDriver() async {
        let fake = Fake()
        let connection = await connect(fake)
        fake.configure { $0.connectError = .rejected(detail: "no") }
        let outcome = await connection.session.reconfigure(MountSettings(altitudeLimit: 20.0))
        XCTAssertEqual(failure(outcome.result), .rejected(detail: "no"))
        XCTAssertEqual(outcome.status.phase, .idle)
        XCTAssertEqual(fake.connectCount, 3, "the failed handshake, and the attempt to connect the shared driver again")
        let phase: MountJobResult<MountPhase> = await connection.session.run { $0.status.phase }
        XCTAssertEqual(phase.result, .success(.idle))
        let limit: MountJobResult<Double> = await connection.session.run { $0.settings.altitudeLimit }
        XCTAssertEqual(limit.result, .success(-10.0))
    }

    // MARK: - Urgent jobs

    func testUrgentJobsOvertakeTheOnesThatWait() async {
        let connection = await connect(Fake())
        let session = connection.session
        let gate = Gate()
        gate.close()
        let order = Recorder()
        let blocker = Task {
            await session.run { _ -> Int in
                order.add("blocker")
                gate.pass()
                return 0
            }
        }
        let started = await eventually { gate.isWaiting }
        XCTAssertTrue(started)
        let normal = Task {
            await session.run { _ -> Int in
                order.add("normal")
                return 1
            }
        }
        await pause()
        let urgent = Task {
            await session.run(urgent: true) { _ -> Int in
                order.add("urgent")
                return 2
            }
        }
        await pause()
        gate.open()
        let results = [await blocker.value.result, await normal.value.result, await urgent.value.result]
        XCTAssertEqual(results, [.success(0), .success(1), .success(2)])
        XCTAssertEqual(order.all, ["blocker", "urgent", "normal"])
    }

    // MARK: - The end of the session

    func testInterruptingASimulatedLinkLeavesLaterJobsAlone() async {
        let connection = await connect(Fake())
        connection.session.interrupt()
        let job: MountJobResult<MountPhase> = await connection.session.run { $0.status.phase }
        XCTAssertEqual(job.result, .success(.idle))
    }

    func testShuttingDownLetsTheDriverGoAndRefusesLaterJobs() async {
        let fake = Fake()
        let connection = await connect(fake)
        connection.session.shutdown()
        let drained = await eventually { fake.disconnectCount == 1 }
        XCTAssertTrue(drained, "the controller disconnects the driver")
        let job: MountJobResult<MountPhase> = await connection.session.run { $0.status.phase }
        XCTAssertEqual(failure(job.result), .notConnected)
        XCTAssertEqual(job.status, MountStatus.disconnected)
        let urgent: MountJobResult<MountPhase> = await connection.session.run(urgent: true) { $0.status.phase }
        XCTAssertEqual(failure(urgent.result), .notConnected)
        let polled = await connection.session.poll()
        XCTAssertEqual(failure(polled.result), .notConnected)
        let centred = await connection.session.centreSimulated(on: Self.highPlace)
        XCTAssertEqual(failure(centred.result), .notConnected)
        XCTAssertEqual(centred.status, MountStatus.disconnected)
        let reconfigured = await connection.session.reconfigure(MountSettings())
        XCTAssertEqual(failure(reconfigured.result), .notConnected)
    }

    func testShuttingDownTwiceIsHarmless() async {
        let fake = Fake()
        let connection = await connect(fake)
        connection.session.shutdown()
        connection.session.shutdown()
        let drained = await eventually { fake.disconnectCount == 1 }
        XCTAssertTrue(drained)
        await pause(0.2)
        XCTAssertEqual(fake.disconnectCount, 1)
    }

    func testAJobThatIsRunningFinishesBeforeTheSessionEnds() async {
        let fake = Fake()
        let connection = await connect(fake)
        let session = connection.session
        let gate = Gate()
        gate.close()
        let running = Task {
            await session.run { _ -> Int in
                gate.pass()
                return 7
            }
        }
        let started = await eventually { gate.isWaiting }
        XCTAssertTrue(started)
        session.shutdown()
        XCTAssertEqual(fake.disconnectCount, 0, "the shutdown waits for the job that is running")
        gate.open()
        let finished = await running.value
        XCTAssertEqual(finished.result, .success(7))
        let drained = await eventually { fake.disconnectCount == 1 }
        XCTAssertTrue(drained)
    }

    func testConnectingToAShutDownSessionFails() async {
        let session = newSession()
        session.shutdown()
        let fake = Fake()
        fakes.append(fake)
        let outcome = await session.connect(option: MountServiceTests.option(for: fake), options: MountDriverOptions(),
                                            observer: Self.pole, settings: MountSettings())
        XCTAssertEqual(failure(outcome.result), .notConnected)
        XCTAssertEqual(outcome.status, MountStatus.disconnected)
        XCTAssertEqual(fake.connectCount, 0)
    }

    // MARK: - The result of a job

    func testAJobResultHasNoDetailByDefault() {
        let plain = MountJobResult(Result<Int, MountError>.success(3), status: MountStatus.disconnected)
        XCTAssertEqual(plain.result, .success(3))
        XCTAssertEqual(plain.status, MountStatus.disconnected)
        XCTAssertNil(plain.detail)
        let failed = MountJobResult(Result<Int, MountError>.failure(.busy), status: MountStatus.disconnected)
        XCTAssertEqual(failure(failed.result), .busy)
    }
}
