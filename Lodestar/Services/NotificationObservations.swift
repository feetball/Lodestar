import Foundation
import os

/// Owns block-based `NotificationCenter` observers and removes them when it is released.
///
/// This lets a main-actor type observe notifications without a `deinit` of its own, which would be nonisolated and
/// could not reach the type's actor state.
final class NotificationObservations: @unchecked Sendable {
    private let center: NotificationCenter
    /// Observer tokens are not `Sendable`; they are only ever touched while holding this lock.
    private let tokens = OSAllocatedUnfairLock<[NSObjectProtocol]>(uncheckedState: [])

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    deinit {
        for token in tokens.withLockUnchecked({ $0 }) {
            center.removeObserver(token)
        }
    }

    /// Calls `handler` on the posting thread for every notification named `name` (from `object`, if given).
    func observe(_ name: Notification.Name, object: Any? = nil, handler: @escaping @Sendable (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: nil, using: handler)
        tokens.withLockUnchecked { $0.append(token) }
    }
}
