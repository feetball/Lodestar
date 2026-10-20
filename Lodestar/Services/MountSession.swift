import Foundation
import LodestarKit

/// What a job on the mount worker returns: its result, and the controller's status as the job left it, so the screen
/// shows the effect of a command at once without asking the mount again.
struct MountJobResult<Value: Sendable>: Sendable {
    let result: Result<Value, MountError>
    let status: MountStatus
    /// What the driver can tell besides the status (alignment, pier side), as the job left it; `nil` for most drivers.
    let detail: MountDriverDetail?

    init(_ result: Result<Value, MountError>, status: MountStatus, detail: MountDriverDetail? = nil) {
        self.result = result
        self.status = status
        self.detail = detail
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
    /// Every job on the worker starts with `channel.beginJob()`, so an `interrupt()` only ends the job it found running.
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
    func poll() async -> MountJobResult<MountStatus> {
        await run { controller in controller.poll() }
    }

    /// Runs `work` on the driver itself, for what only one kind of driver can do (declare the home position, remove an
    /// alignment star). The controller's status after the job comes with the result.
    func runDriver<Value: Sendable>(
        urgent: Bool = false, _ work: @escaping @Sendable (MountDriver) throws -> Value
    ) async -> MountJobResult<Value> {
        await withCheckedContinuation { (continuation: CheckedContinuation<MountJobResult<Value>, Never>) in
            let accepted = queue.submit(urgent: urgent) { [self] in
                continuation.resume(returning: executeOnDriver(work))
            }
            if !accepted {
                continuation.resume(returning: MountJobResult(.failure(.notConnected), status: .disconnected))
            }
        }
    }

    /// The simulated Sky-Watcher turns its telescope to `place`, as if the person had centred it with the nudge arrows, and the
    /// driver forgets what it was doing.
    func centreSimulated(on place: EquatorialCoordinate) async -> MountJobResult<Void> {
        await withCheckedContinuation { (continuation: CheckedContinuation<MountJobResult<Void>, Never>) in
            let accepted = queue.submit(urgent: true) { [self] in
                continuation.resume(returning: performCentre(on: place))
            }
            if !accepted {
                continuation.resume(returning: MountJobResult(.failure(.notConnected), status: .disconnected))
            }
        }
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

    /// Ends the exchange that is waiting for the mount right now, whatever it is, and fails everything else the job that
    /// is running now still sends. Jobs that start afterwards (the Stop) are not affected.
    func interrupt() {
        channel.interrupt()
    }

    /// Ends the session after the jobs already queued: the controller and the link are closed, the thread ends.
    func shutdown() {
        // Whatever is waiting for the mount now is cut short; the jobs after it run normally.
        channel.interrupt()
        let accepted = queue.submit { [self] in
            channel.beginJob()
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
        channel.beginJob()
        do {
            try channel.open(timeoutSeconds: 8)
            let made = try option.makeDriver(channel, options)
            bundle = made
            let created = MountController(driver: made.driver, observer: observer, settings: settings, clock: made.clock)
            made.prepare?()
            let capabilities = try created.connect()
            controller = created
            return MountJobResult(.success(capabilities), status: created.status, detail: made.detail?())
        } catch {
            return MountJobResult(.failure(Self.mountError(error)), status: .disconnected)
        }
    }

    private func performReconfigure(_ settings: MountSettings) -> MountJobResult<Void> {
        channel.beginJob()
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
            return MountJobResult(.success(()), status: fresh.status, detail: bundle.detail?())
        } catch {
            // The failed handshake disconnected the driver, which the controller that stays in use still shares:
            // connect it again, as well as it can be, so a limit that could not be sent does not end the session.
            // The link starts afresh, so that a Stop that cut the handshake short does not cut this one short too.
            channel.beginJob()
            _ = try? bundle.driver.connect()
            return MountJobResult(.failure(Self.mountError(error)), status: current.status)
        }
    }

    private func execute<Value: Sendable>(_ work: (MountController) throws -> Value) -> MountJobResult<Value> {
        channel.beginJob()
        guard let controller else { return MountJobResult(.failure(.notConnected), status: .disconnected) }
        bundle?.prepare?()
        do {
            let value = try work(controller)
            return MountJobResult(.success(value), status: controller.status, detail: bundle?.detail?())
        } catch {
            return MountJobResult(.failure(Self.mountError(error)), status: controller.status, detail: bundle?.detail?())
        }
    }

    private func performCentre(on place: EquatorialCoordinate) -> MountJobResult<Void> {
        channel.beginJob()
        guard let controller, let bundle, let centre = bundle.centreSimulated else {
            return MountJobResult(.failure(.notSupported(feature: .other)), status: controller?.status ?? .disconnected)
        }
        bundle.prepare?()
        do {
            try controller.abort()
            centre(place)
            // Tracking resumes from where the telescope stands now.
            try controller.abort()
            return MountJobResult(.success(()), status: controller.status, detail: bundle.detail?())
        } catch {
            return MountJobResult(.failure(Self.mountError(error)), status: controller.status, detail: bundle.detail?())
        }
    }

    private func executeOnDriver<Value: Sendable>(_ work: (MountDriver) throws -> Value) -> MountJobResult<Value> {
        channel.beginJob()
        guard let controller, let bundle else { return MountJobResult(.failure(.notConnected), status: .disconnected) }
        bundle.prepare?()
        do {
            let value = try work(bundle.driver)
            return MountJobResult(.success(value), status: controller.status, detail: bundle.detail?())
        } catch {
            return MountJobResult(.failure(Self.mountError(error)), status: controller.status, detail: bundle.detail?())
        }
    }

    private static func mountError(_ error: Error) -> MountError {
        if let known = error as? MountError { return known }
        return .transport(detail: "unexpected failure")
    }
}
