import Foundation
import Observation
import WatchKit

/// The state of the watch app's Aim page: the newest aim message from the iPhone and when it arrived.
///
/// The iPhone sends about twice a second while it aims. The page shows "Waiting for iPhone" until a message has come and
/// again when none has for `staleAfter` seconds, and a message older than the newest one is dropped (messages may arrive
/// out of order). Reaching the target plays a success haptic.
@MainActor
@Observable
final class WatchAimModel {
    /// Seconds without a message after which what was shown is out of date.
    static let staleAfter: TimeInterval = 3

    /// The newest message and when it arrived (on this watch's clock); `nil` until the first one.
    private(set) var latest: (message: AimWristMessage, received: Date)?

    /// The newest message if it is recent enough to show at `date`.
    func current(at date: Date) -> AimWristMessage? {
        guard let latest, date.timeIntervalSince(latest.received) <= Self.staleAfter else { return nil }
        return latest.message
    }

    /// Takes over a message from the iPhone.
    func receive(_ message: AimWristMessage, at date: Date = Date()) {
        if let latest, message.sent <= latest.message.sent { return }
        let wasOnTarget = current(at: date)?.isOnTarget ?? false
        latest = (message, date)
        if message.isOnTarget && !wasOnTarget {
            WKInterfaceDevice.current().play(.success)
        }
    }
}
