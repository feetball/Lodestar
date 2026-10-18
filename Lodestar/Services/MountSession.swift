import Foundation
import LodestarKit

/// What a job on the mount worker returns: its result, and the controller's status as the job left it, so the screen
/// shows the effect of a command at once without asking the mount again.
struct MountJobResult<Value: Sendable>: Sendable {
    let result: Result<Value, MountError>
    let status: MountStatus

    init(_ result: Result<Value, MountError>, status: MountStatus) {
        self.result = result
        self.status = status
    }
}

/// One connection to a mount: the link, and the engine's driver and controller living on a worker thread of their own.
///
/// The controller is not thread safe and blocks for up to several seconds per exchange, so every use of it is a job on
/// the session's `MountWorkQueue`. The jobs run one at a time; `urgent` ones (Stop) go before the others, and
/// `interrupt()` ends the exchange in progress at once so that a Stop does not wait for a timeout.
/// Nothing here touches the main actor; callers await the jobs.
final class MountSession: @unchecked Sendable {
    private let channel: MountChannel
    private let queue = MountWorkQueue(name: "net.kuecker.lodestar.mount")

    // Only touched by jobs on the queue.
    private var bundle: MountDriverBundle?
    private var controller: MountController?

    init(channel: MountChannel) {
        self.channel = channel
    }

    // MARK: Session

    /// Opens the link, makes the driver and the controller and runs the handshake.
    func connect(option: MountConnectionOption, options: MountDriverOptions, observer: Observer,
                 settings: MountSettings) async -> MountJobResult<MountCapabilities> {
        await withCheckedContinuation { (continuation: CheckedContinuation<MountJobResult<MountCapabilities>, Never>) in
            let accepted = queue.submit { [self] in
                continuation.resume(returning: performConnect(option: option, options: options, observer: observer,
                                                              settings: settings))
            }
            if !accepted {
                continuation.resume(returning: MountJobResult(.failure(.notConnected), status: .disconnected))
            }
        }
    }

    /// Runs `work` on the controller. A job that throws reports the `MountError`; the status is the controller's after it.
    func run<Value: Sendable>(urgent: Bool = false,
                              _ work: @escaping @Sendable (MountController) throws -> Value) async -> MountJobResult<Value> {
        await withCheckedContinuation { (continuation: CheckedContinuation<MountJobResult<Value>, Never>) in
            let accepted = queue.submit(urgent: urgent) { [self] in
                continuation.resume(returning: execute(work))
            }
            if !accepted {
                continuation.resume(returning: MountJobResult(.failure(.notConnected), status: .disconnected))
            }
        }
    }

    /// One refresh cycle of the controller.
    func poll() async -> MountStatus {
        await run { controller in controller.poll() }.status
    }

    /// Runs the controller on new limits. The mount is asked for its state again, so only call it while idle.
    func reconfigure(_ settings: MountSettings) async -> MountJobResult<Void> {
        await withCheckedContinuation { (continuation: CheckedContinuation<MountJobResult<Void>, Never>) in
            let accepted = queue.submit { [self] in
                continuation.resume(returning: performReconfigure(settings))
            }
            if !accepted {
                continuation.resume(returning: MountJobResult(.failure(.notConnected), status: .disconnected))
            }
        }
    }

    /// Ends the exchange that is waiting for the mount right now, whatever it is.
    func interrupt() {
        channel.interrupt()
    }

    /// Ends the session after the jobs already queued: the controller and the link are closed, the thread ends.
    func shutdown() {
        // Whatever is waiting for the mount now is cut short; the jobs after it run normally.
        channel.interrupt()
        let accepted = queue.submit { [self] in
            controller?.disconnect()
            controller = nil
            bundle = nil
            channel.close()
        }
        if !accepted { channel.close() }
        queue.close()
    }

    // MARK: On the worker thread

    private func performConnect(option: MountConnectionOption, options: MountDriverOptions, observer: Observer,
                                settings: MountSettings) -> MountJobResult<MountCapabilities> {
        do {
            try channel.open(timeoutSeconds: 8)
            let made = try option.makeDriver(channel, options)
            bundle = made
            let created = MountController(driver: made.driver, observer: observer, settings: settings, clock: made.clock)
            made.prepare?()
            let capabilities = try created.connect()
            controller = created
            return MountJobResult(.success(capabilities), status: created.status)
        } catch {
            return MountJobResult(.failure(Self.mountError(error)), status: .disconnected)
        }
    }

    private func performReconfigure(_ settings: MountSettings) -> MountJobResult<Void> {
        guard let bundle, let current = controller else {
            return MountJobResult(.failure(.notConnected), status: .disconnected)
        }
        guard current.status.phase == .idle else {
            return MountJobResult(.failure(.busy), status: current.status)
        }
        bundle.prepare?()
        let fresh = MountController(driver: bundle.driver, observer: current.observer, settings: settings,
                                    clock: bundle.clock)
        do {
            _ = try fresh.connect()
            controller = fresh
            return MountJobResult(.success(()), status: fresh.status)
        } catch {
            return MountJobResult(.failure(Self.mountError(error)), status: current.status)
        }
    }

    private func execute<Value: Sendable>(_ work: (MountController) throws -> Value) -> MountJobResult<Value> {
        guard let controller else { return MountJobResult(.failure(.notConnected), status: .disconnected) }
        bundle?.prepare?()
        do {
            return MountJobResult(.success(try work(controller)), status: controller.status)
        } catch {
            return MountJobResult(.failure(Self.mountError(error)), status: controller.status)
        }
    }

    private static func mountError(_ error: Error) -> MountError {
        if let known = error as? MountError { return known }
        return .transport(detail: "unexpected failure")
    }
}
