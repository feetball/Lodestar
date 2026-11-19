import Foundation
import WatchConnectivity

/// Receives what the iPhone app sends over WatchConnectivity: the observer (`applicationContext`), if the iPhone app has
/// one, the place (and time zone) Lodestar is working for on the phone, which the watch can work without, from its own
/// location; and, while the phone aims, live aim messages for the Aim page (`AimWristMessage`).
final class WatchPhoneLink: NSObject, WCSessionDelegate {
    private let onPlace: @Sendable (TonightPlace) -> Void
    private let onAim: @Sendable (AimWristMessage) -> Void

    init(onPlace: @escaping @Sendable (TonightPlace) -> Void, onAim: @escaping @Sendable (AimWristMessage) -> Void) {
        self.onPlace = onPlace
        self.onAim = onAim
        super.init()
    }

    /// Starts the session; the place the phone sent last arrives as soon as it is active.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated,
              let place = TonightPhoneContext.place(from: session.receivedApplicationContext) else { return }
        onPlace(place)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let place = TonightPhoneContext.place(from: applicationContext) {
            onPlace(place)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let aim = AimWristMessage.decode(message) {
            onAim(aim)
        }
    }
}
