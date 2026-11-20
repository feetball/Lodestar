import Foundation

/// Stands in for Lodestar/Features/Satellites/SatellitePassActivityController.swift (ActivityKit: the Live Activity of a followed
/// satellite pass) in the test package, with the same members. It records what the app would ask the system to do, so that a test
/// can check it.
@MainActor
final class SatellitePassActivityController {
    /// How long a finished pass stays on the Lock Screen.
    static let lingerAfterPass: TimeInterval = 120

    /// The sources `begin` was called with, oldest first.
    private(set) var begun: [SatelliteAimSource] = []
    private(set) var endCount = 0
    private(set) var refreshCount = 0

    init() {}

    func begin(for source: SatelliteAimSource, isNight: Bool, now: Date = Date()) { begun.append(source) }

    func end() { endCount += 1 }

    func refresh(now: Date = Date()) { refreshCount += 1 }
}
