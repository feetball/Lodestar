import Foundation

/// A serial queue with a thread of its own that serves its urgent lane first.
///
/// The mount engine is not thread safe and every exchange with the mount blocks until the mount has answered or the
/// timeout has run out, so everything that touches the controller runs here, one job at a time and off the main actor.
/// A job in the urgent lane (Stop) waits only for the job that is running, not for the ones queued behind it.
final class MountWorkQueue: @unchecked Sendable {
    private let condition = NSCondition()
    private var urgentJobs: [@Sendable () -> Void] = []
    private var normalJobs: [@Sendable () -> Void] = []
    private var isClosed = false

    init(name: String) {
        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Queues `job`.
    ///
    /// - Returns: `false` if the queue has been closed; the job is then dropped and never runs.
    @discardableResult
    func submit(urgent: Bool = false, _ job: @escaping @Sendable () -> Void) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        if isClosed { return false }
        if urgent {
            urgentJobs.append(job)
        } else {
            normalJobs.append(job)
        }
        condition.signal()
        return true
    }

    /// Lets the thread end once the jobs already queued have run.
    func close() {
        condition.lock()
        isClosed = true
        condition.broadcast()
        condition.unlock()
    }

    private func run() {
        while let job = nextJob() {
            job()
        }
    }

    /// Waits for the next job, urgent ones first; `nil` once the queue is closed and empty.
    private func nextJob() -> (@Sendable () -> Void)? {
        condition.lock()
        defer { condition.unlock() }
        while urgentJobs.isEmpty && normalJobs.isEmpty {
            if isClosed { return nil }
            condition.wait()
        }
        return urgentJobs.isEmpty ? normalJobs.removeFirst() : urgentJobs.removeFirst()
    }
}

/// A flag that one thread sets and another one reads, for work that can be called off while it runs.
final class MountCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Runs blocking work on a background queue and hands its result back to the caller's task, without tying up a
/// thread of the cooperative pool for the seconds a network exchange can take.
func mountRunBlocking<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work())
        }
    }
}
