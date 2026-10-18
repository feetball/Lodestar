import Foundation
import WatchConnectivity

/// Receives the observer the iPhone app sends over WatchConnectivity (`applicationContext`), if the iPhone app has
/// one: the place (and time zone) Lodestar is working for on the phone. Optional: the watch works without it, from
/// its own location.
final class WatchPhoneLink: NSObject, WCSessionDelegate {
    private let onPlace: @Sendable (TonightPlace) -> Void

    init(onPlace: @escaping @Sendable (TonightPlace) -> Void) {
        self.onPlace = onPlace
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
}
