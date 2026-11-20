import Foundation
import XCTest
@testable import AppCore

/// Remembers the thread a job ran on.
private final class WorkQueueThreadBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Thread?

    func remember(_ thread: Thread) {
        lock.lock()
        stored = thread
        lock.unlock()
    }

    var thread: Thread? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// Counts how many jobs run at the same time.
private final class WorkQueueOverlapCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var highest = 0
    private var finished = 0

    func enter() {
        lock.lock()
        running += 1
        highest = max(highest, running)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        running -= 1
        finished += 1
        lock.unlock()
    }

    var mostAtOnce: Int {
        lock.lock()
        defer { lock.unlock() }
        return highest
    }

    var jobsFinished: Int {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}

/// Tests of `MountWorkQueue`, `MountCancelFlag` and `mountRunBlocking` (Services/MountWorkQueue.swift).
final class MountServiceWorkQueueTests: XCTestCase {
    private typealias Gate = MountServiceTests.Gate
    private typealias Recorder = MountServiceTests.Recorder

    private func eventually(timeout: TimeInterval = 10.0, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    // MARK: - Order

    func testJobsRunInTheOrderTheyWereSubmitted() async {
        let queue = MountWorkQueue(name: "MountServiceTests.order")
        defer { queue.close() }
        let recorder = Recorder()
        for index in 0..<20 {
            queue.submit { recorder.add("\(index)") }
        }
        let done = await eventually { recorder.count == 20 }
        XCTAssertTrue(done)
        XCTAssertEqual(recorder.all, (0..<20).map { "\($0)" })
    }

    func testJobsRunOnTheThreadOfTheQueueAndNotOnTheMainThread() async {
        let queue = MountWorkQueue(name: "MountServiceTests.thread")
        defer { queue.close() }
        let recorder = Recorder()
        queue.submit { recorder.add("\(Thread.isMainThread) \(Thread.current.name ?? "no name")") }
        let done = await eventually { recorder.count == 1 }
        XCTAssertTrue(done)
        XCTAssertEqual(recorder.all, ["false MountServiceTests.thread"])
    }

    func testJobsRunOneAtATime() async {
        let queue = MountWorkQueue(name: "MountServiceTests.serial")
        defer { queue.close() }
        let counter = WorkQueueOverlapCounter()
        for _ in 0..<100 {
            queue.submit {
                counter.enter()
                counter.leave()
            }
        }
        let done = await eventually { counter.jobsFinished == 100 }
        XCTAssertTrue(done)
        XCTAssertEqual(counter.mostAtOnce, 1)
    }

    func testUrgentJobsGoBeforeTheOnesThatWait() async {
        let queue = MountWorkQueue(name: "MountServiceTests.urgent")
        defer { queue.close() }
        let gate = Gate()
        gate.close()
        let recorder = Recorder()
        queue.submit {
            recorder.add("first")
            gate.pass()
        }
        let started = await eventually { gate.isWaiting }
        XCTAssertTrue(started)
        queue.submit { recorder.add("normal 1") }
        queue.submit { recorder.add("normal 2") }
        queue.submit(urgent: true) { recorder.add("urgent 1") }
        queue.submit(urgent: true) { recorder.add("urgent 2") }
        gate.open()
        let done = await eventually { recorder.count == 5 }
        XCTAssertTrue(done)
        XCTAssertEqual(recorder.all, ["first", "urgent 1", "urgent 2", "normal 1", "normal 2"])
    }

    func testAnUrgentJobDoesNotInterruptTheJobThatIsRunning() async {
        let queue = MountWorkQueue(name: "MountServiceTests.running")
        defer { queue.close() }
        let gate = Gate()
        gate.close()
        let recorder = Recorder()
        queue.submit {
            recorder.add("first start")
            gate.pass()
            recorder.add("first end")
        }
        let started = await eventually { gate.isWaiting }
        XCTAssertTrue(started)
        queue.submit(urgent: true) { recorder.add("urgent") }
        // The only thread of the queue is stuck in the first job, so the urgent one cannot have started.
        XCTAssertEqual(recorder.all, ["first start"])
        gate.open()
        let done = await eventually { recorder.count == 3 }
        XCTAssertTrue(done)
        XCTAssertEqual(recorder.all, ["first start", "first end", "urgent"])
    }

    func testJobsSubmittedFromManyThreadsAllRunOnce() async {
        let queue = MountWorkQueue(name: "MountServiceTests.many")
        defer { queue.close() }
        let recorder = Recorder()
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            queue.submit(urgent: index % 2 == 0) { recorder.add("\(index)") }
        }
        let done = await eventually { recorder.count == 200 }
        XCTAssertTrue(done)
        XCTAssertEqual(Set(recorder.all).count, 200, "every job ran exactly once")
    }

    // MARK: - Closing

    func testSubmitSaysWhetherTheJobWasAccepted() async {
        let queue = MountWorkQueue(name: "MountServiceTests.accepted")
        XCTAssertTrue(queue.submit {})
        XCTAssertTrue(queue.submit(urgent: true) {})
        queue.close()
        XCTAssertFalse(queue.submit {})
        XCTAssertFalse(queue.submit(urgent: true) {})
    }

    func testAClosedQueueNeverRunsARefusedJob() async {
        let queue = MountWorkQueue(name: "MountServiceTests.refused")
        let box = WorkQueueThreadBox()
        let recorder = Recorder()
        queue.submit {
            box.remember(Thread.current)
            recorder.add("accepted")
        }
        let ran = await eventually { recorder.count == 1 }
        XCTAssertTrue(ran)
        queue.close()
        let accepted = queue.submit { recorder.add("refused") }
        XCTAssertFalse(accepted)
        let ended = await eventually { box.thread?.isFinished == true }
        XCTAssertTrue(ended, "the thread of a closed queue ends")
        XCTAssertEqual(recorder.all, ["accepted"], "nothing runs once the thread has ended")
    }

    func testJobsAcceptedBeforeTheQueueWasClosedAllRun() async {
        let queue = MountWorkQueue(name: "MountServiceTests.drain")
        let gate = Gate()
        gate.close()
        let recorder = Recorder()
        queue.submit {
            recorder.add("first")
            gate.pass()
        }
        let started = await eventually { gate.isWaiting }
        XCTAssertTrue(started)
        for index in 1...5 {
            queue.submit { recorder.add("normal \(index)") }
        }
        queue.submit(urgent: true) { recorder.add("urgent") }
        queue.close()
        XCTAssertFalse(queue.submit { recorder.add("too late") })
        gate.open()
        let done = await eventually { recorder.count == 7 }
        XCTAssertTrue(done)
        XCTAssertEqual(recorder.all, ["first", "urgent", "normal 1", "normal 2", "normal 3", "normal 4", "normal 5"])
        await Task.yield()
        XCTAssertEqual(recorder.count, 7)
    }

    func testClosingWakesAnIdleWorkerSoThatItsThreadEnds() async {
        let queue = MountWorkQueue(name: "MountServiceTests.idle")
        let box = WorkQueueThreadBox()
        queue.submit { box.remember(Thread.current) }
        let ran = await eventually { box.thread != nil }
        XCTAssertTrue(ran)
        // The worker has nothing to do and waits.
        XCTAssertEqual(box.thread?.isFinished, false)
        queue.close()
        let ended = await eventually { box.thread?.isFinished == true }
        XCTAssertTrue(ended)
    }

    func testClosingTwiceIsHarmless() async {
        let queue = MountWorkQueue(name: "MountServiceTests.twice")
        queue.close()
        queue.close()
        XCTAssertFalse(queue.submit {})
    }

    // MARK: - The flag

    func testACancelFlagStartsUncancelledAndStaysCancelled() {
        let flag = MountCancelFlag()
        XCTAssertFalse(flag.isCancelled)
        flag.cancel()
        XCTAssertTrue(flag.isCancelled)
        flag.cancel()
        XCTAssertTrue(flag.isCancelled)
    }

    func testACancelFlagSetOnAnotherThreadIsSeenByTheReader() async {
        let flag = MountCancelFlag()
        DispatchQueue.global().async {
            flag.cancel()
        }
        let seen = await eventually { flag.isCancelled }
        XCTAssertTrue(seen)
        XCTAssertTrue(flag.isCancelled)
    }

    func testEachFlagIsIndependent() {
        let first = MountCancelFlag()
        let second = MountCancelFlag()
        first.cancel()
        XCTAssertTrue(first.isCancelled)
        XCTAssertFalse(second.isCancelled)
    }

    // MARK: - Blocking work

    func testBlockingWorkReturnsItsResultFromOutsideTheMainThread() async {
        let onMainThread = await mountRunBlocking { Thread.isMainThread }
        XCTAssertFalse(onMainThread)
        let answer = await mountRunBlocking { 6 * 7 }
        XCTAssertEqual(answer, 42)
        let text = await mountRunBlocking { "done" }
        XCTAssertEqual(text, "done")
    }

    func testBlockingJobsStartedTogetherEachReturnTheirOwnResult() async {
        var total = 0
        await withTaskGroup(of: Int.self) { group in
            for index in 1...8 {
                group.addTask { await mountRunBlocking { index * index } }
            }
            for await square in group { total += square }
        }
        XCTAssertEqual(total, 204)
    }
}
