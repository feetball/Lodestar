import Foundation
import LodestarKit

/// Mirrors the aiming guidance to the Apple Watch app's Aim page: a tiny message (numbers, a state word and the target's
/// name) about twice a second while Aim leads to something and the watch app is open. Nothing is sent otherwise, and the
/// watch drops what is stale: it shows "Waiting for iPhone" after three seconds without a message.
///
/// The message is `AimWristMessage` in `WidgetShared/Core/AimWristMessage.swift`, which also decodes it on the watch.
@MainActor
final class WatchAimLink {
    static let shared = WatchAimLink()

    /// Seconds between messages (2 Hz).
    static let interval: Duration = .milliseconds(500)

    private var lastSent: ContinuousClock.Instant?

    private init() {}

    /// Sends `guidance` unless a message went out less than `interval` ago or no watch app is listening. Call as often as
    /// you like, once per frame for example.
    func send(_ guidance: Guidance, targetName: String, isNight: Bool, now: Date = Date()) {
        let instant = ContinuousClock.now
        if let lastSent, instant - lastSent < Self.interval { return }
        guard WatchObserverLink.shared.isWatchReachable else { return }
        lastSent = instant
        WatchObserverLink.shared.sendLive(Self.message(for: guidance, targetName: targetName, isNight: isNight, sent: now))
    }

    /// The message for `guidance`: property-list values only, a few dozen bytes.
    static func message(for guidance: Guidance, targetName: String, isNight: Bool, sent: Date) -> [String: Any] {
        AimWristMessage(
            sent: sent.timeIntervalSince1970, pan: guidance.panDelta, tilt: guidance.tiltDelta,
            separation: guidance.separation, state: AimWristMessage.State(guidance.state),
            isBelowHorizon: guidance.targetBelowHorizon, isNearZenith: guidance.isNearZenith,
            isNight: isNight, targetName: targetName
        ).wireMessage
    }
}
