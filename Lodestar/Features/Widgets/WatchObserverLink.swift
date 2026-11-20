import Foundation
import WatchConnectivity

/// Tells the Apple Watch app where the observer is, so its Tonight screen matches the Tonight tab: the latitude,
/// longitude, elevation and time zone of the current observer, whether that is the device's own location or a saved
/// site, and when it was sent, as the session's `applicationContext` whenever it changes. Optional and best effort:
/// without a paired watch, or without the watch app installed, nothing is sent, and the watch app falls back to its own
/// location (as it does once the device's own location, which it cannot see change, has gone stale). The wire format is
/// `TonightPhoneContext` in `WidgetShared/Core/TonightPlaceStore.swift`.
@MainActor
final class WatchObserverLink {
    static let shared = WatchObserverLink()

    private var delegate: SessionDelegate?
    /// What the watch is to be sent.
    private var payload: TonightPhonePlace?
    /// What the active watch was last sent, so that the same message is not sent again; forgotten when the session or
    /// the watch changes.
    private var lastSent: TonightPhonePlace?

    private init() {}

    /// Remembers the observer and sends it as soon as the session allows. Does nothing without an observer.
    func send(_ context: ObserverContext?) {
        guard WCSession.isSupported(), let context, let place = TonightPlace(observer: context) else { return }
        let kind: TonightPhonePlace.Kind
        if case .device = context.source {
            kind = .device
        } else {
            kind = .savedSite
        }
        payload = TonightPhonePlace(place: place, kind: kind, sentAt: Date())
        activateIfNeeded()
        flush()
    }

    /// Whether a live message would reach the watch app now: the session is active, a watch is paired with the app
    /// installed, and that app is open (reachable).
    var isWatchReachable: Bool {
        guard WCSession.isSupported() else { return false }
        activateIfNeeded()
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
            && session.isReachable
    }

    /// Sends `message` to the open watch app at once. Best effort: nothing is queued and a failure is ignored, because
    /// the next message replaces this one.
    func sendLive(_ message: [String: Any]) {
        guard WCSession.isSupported() else { return }
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: { _ in })
    }

    // MARK: Private

    private func activateIfNeeded() {
        guard delegate == nil else { return }
        let delegate = SessionDelegate { [weak self] in
            Task { @MainActor [weak self] in self?.sessionChanged() }
        }
        self.delegate = delegate
        let session = WCSession.default
        session.delegate = delegate
        session.activate()
    }

    /// The session has been activated (again) or the watch's state has changed: another paired watch may be the
    /// active one now, or the watch app may have been installed again, so the observer is sent even if it is the one
    /// sent before.
    private func sessionChanged() {
        lastSent = nil
        flush()
    }

    private func flush() {
        let session = WCSession.default
        guard let payload, payload != lastSent, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(TonightPhoneContext.context(for: payload))
            lastSent = payload
        } catch {
            // The next change, or the watch app being installed, tries again.
        }
    }

    /// Receives the session's callbacks and asks for another try; it holds no state of its own.
    private final class SessionDelegate: NSObject, WCSessionDelegate {
        private let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
            super.init()
        }

        func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                     error: Error?) {
            onChange()
        }

        func sessionDidBecomeInactive(_ session: WCSession) {}

        func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }

        func sessionWatchStateDidChange(_ session: WCSession) {
            onChange()
        }
    }
}
