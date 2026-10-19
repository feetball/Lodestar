import Foundation
import WatchConnectivity

/// Tells the Apple Watch app where the observer is, so its Tonight screen matches the Tonight tab: the latitude,
/// longitude, elevation and time zone of the current observer, sent as the session's `applicationContext` whenever it
/// changes. Optional and best effort: without a paired watch, or without the watch app installed, nothing is sent,
/// and the watch app falls back to its own location. The keys are those of `TonightPhoneContext` in
/// `WidgetShared/TonightPlaceStore.swift`.
@MainActor
final class WatchObserverLink {
    static let shared = WatchObserverLink()

    /// What the watch is sent.
    private struct Payload: Equatable {
        let latitude: Double
        let longitude: Double
        let elevation: Double
        let timeZone: String

        var context: [String: Any] {
            ["lat": latitude, "lon": longitude, "elevation": elevation, "timeZone": timeZone]
        }
    }

    private var delegate: SessionDelegate?
    private var payload: Payload?
    /// What the active watch was last sent, so that an unchanged observer is not sent again; forgotten when the
    /// session or the watch changes.
    private var lastSent: Payload?

    private init() {}

    /// Remembers the observer and sends it as soon as the session allows. Does nothing without an observer.
    func send(_ context: ObserverContext?) {
        guard WCSession.isSupported(), let context else { return }
        let location = context.location
        let zone: String
        if case .device = context.source {
            zone = TimeZone.current.identifier
        } else {
            zone = context.timeZone.identifier
        }
        payload = Payload(latitude: location.latitude, longitude: location.longitude,
                          elevation: location.elevation, timeZone: zone)
        activateIfNeeded()
        flush()
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
            try session.updateApplicationContext(payload.context)
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
