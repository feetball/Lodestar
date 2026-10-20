import UIKit

/// The pieces of the mount service that need UIKit: noticing that the app went to the background, keeping the app
/// alive for the few seconds it takes to stop the mount then, and VoiceOver announcements.
@MainActor
final class MountLifecycle {
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    /// - Parameter onBackground: Called on the main actor when the app has moved to the background.
    init(onBackground: @escaping @MainActor @Sendable () -> Void) {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { onBackground() }
        }
    }

    /// Asks iOS for time to finish stopping the mount after the app has left the screen.
    func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        // iOS calls the handler on the main thread and wants the task ended before it returns, so no hop to a Task here.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Stop the mount") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
    }

    func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Has VoiceOver say `text`.
    static func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
