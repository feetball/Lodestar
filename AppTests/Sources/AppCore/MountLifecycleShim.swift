import Foundation

/// Stands in for Lodestar/Services/MountLifecycle.swift (UIKit: the background task and the VoiceOver announcement) in the test
/// package, with the same members. It counts what the app would ask iOS for, so that a test can check it.
@MainActor
final class MountLifecycle {
    private let onBackground: @MainActor @Sendable () -> Void
    private(set) var backgroundTasksBegun = 0
    private(set) var backgroundTasksEnded = 0
    /// What `announce` was asked to say, oldest first.
    private(set) static var announcements: [String] = []

    init(onBackground: @escaping @MainActor @Sendable () -> Void) {
        self.onBackground = onBackground
    }

    func beginBackgroundTask() { backgroundTasksBegun += 1 }

    func endBackgroundTask() { backgroundTasksEnded += 1 }

    static func announce(_ text: String) { announcements.append(text) }

    /// A test's way of sending the app to the background.
    func simulateBackground() { onBackground() }
}
