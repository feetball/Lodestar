import Foundation

/// What a spoken phrase was about; `GuidanceSpeech` uses it to decide what is worth saying next.
public enum SpokenKind: String, Hashable, Sendable {
    /// The pan and tilt to make.
    case guidance
    /// Within `GuidanceSpeech.almostThereSeparation` of the target but not on it yet.
    case almostThere
    /// The camera is on target.
    case onTarget
    /// The target is below the horizon.
    case belowHorizon
}

/// What was last spoken: the timing and the values `GuidanceSpeech.phrase` compares the next guidance with. Keep the
/// state of the last phrase that was actually spoken, pass it back as `previous`, and drop it (use `nil`) when a
/// session ends or the target changes.
///
/// Values are produced by `GuidanceSpeech.phrase`; the initializer is internal.
public struct SpokenState: Hashable, Sendable {
    /// What the phrase was about.
    public let kind: SpokenKind
    /// The pan change (degrees, positive to the right) of the guidance it was spoken for.
    public let pan: Double
    /// The tilt change (degrees, positive up) of the guidance it was spoken for.
    public let tilt: Double
    /// When it was spoken.
    public let time: Date
    /// Whether the word "degrees" has been said in this session.
    public let hasSaidDegrees: Bool
}

/// A phrase to speak and the state to remember once it has been spoken.
public struct SpokenPhrase: Hashable, Sendable {
    /// The words, ready for a speech synthesiser.
    public let text: String
    /// Pass this as `previous` to the next `GuidanceSpeech.phrase` call if the phrase was spoken.
    public let state: SpokenState
}

/// The words of spoken aiming guidance, shared by both apps so that they say the same things. A pure function: the
/// timing state travels in the value it returns, so nothing here depends on a clock or a speech engine.
///
/// - Off target: "Pan right 12, tilt up 3", whole degrees, the word "degrees" only in the first phrase with numbers
///   of a session. A component that rounds to 0° is left out; within 5° of the zenith, where azimuth is a poor
///   guide (`Guidance.isNearZenith`), the pan is left out while there is a tilt to make.
/// - Within `almostThereSeparation` of the target but not on it: "Almost there".
/// - On target: "On target", once; then silence until the camera has drifted off (the tracker's hysteresis).
/// - Target below the horizon: "Target is below the horizon", once; nothing else is said while it is.
/// - A guidance phrase is repeated only when the pan or the tilt changed by `changeThreshold` degrees or more since
///   the last one, or `repeatInterval` seconds have passed; so is "Almost there". A change of kind is spoken at once.
///   "Almost there" is left again only at `almostThereSeparation` times `GuidanceTracker.hysteresisFactor`, so a
///   camera hovering around the limit does not chatter.
///
/// Cost: a few comparisons and one short string per call.
public enum GuidanceSpeech {
    /// Separation in degrees below which "Almost there" is said instead of the pan and tilt.
    public static let almostThereSeparation = 2.0
    /// The change in pan or tilt, in degrees, that makes the guidance worth repeating.
    public static let changeThreshold = 1.0
    /// Seconds after which the guidance is repeated even if it has not changed.
    public static let repeatInterval = 5.0

    /// What to say now for `current`, or `nil` for silence. `previous` is the state of the last phrase spoken in this
    /// session (`nil` at the start); `now` is the time of this call. The returned `state` describes the phrase once it
    /// has been spoken: do not pass it back if the phrase was dropped. `nil` also when `current` holds a value that
    /// is not finite.
    public static func phrase(current: Guidance, previous: SpokenState?, now: Date) -> SpokenPhrase? {
        guard current.separation.isFinite, current.panDelta.isFinite, current.tiltDelta.isFinite else { return nil }
        let saidDegrees = previous?.hasSaidDegrees ?? false
        // A clock that went backwards counts as a long time: the remembered moment is no use.
        let isDue: Bool
        if let previous {
            let elapsed = now.timeIntervalSince(previous.time)
            isDue = elapsed < 0 || elapsed >= repeatInterval
        } else {
            isDue = true
        }

        if current.targetBelowHorizon {
            if previous?.kind == .belowHorizon { return nil }
            return spoken("Target is below the horizon", kind: .belowHorizon, current: current, now: now,
                          hasSaidDegrees: saidDegrees)
        }
        if current.state == .onTarget {
            if previous?.kind == .onTarget { return nil }
            return spoken("On target", kind: .onTarget, current: current, now: now, hasSaidDegrees: saidDegrees)
        }
        let almostLimit = previous?.kind == .almostThere
            ? almostThereSeparation * GuidanceTracker.hysteresisFactor
            : almostThereSeparation
        if current.separation < almostLimit {
            if previous?.kind == .almostThere, !isDue { return nil }
            return spoken("Almost there", kind: .almostThere, current: current, now: now, hasSaidDegrees: saidDegrees)
        }

        let panWhole = abs(current.panDelta).rounded()
        let tiltWhole = abs(current.tiltDelta).rounded()
        let includeTilt = tiltWhole >= 1
        let includePan = panWhole >= 1 && !(current.isNearZenith && includeTilt)
        if !includePan && !includeTilt { return nil }
        if let previous, previous.kind == .guidance, !isDue {
            let panChanged = includePan
                && abs(AstroMath.normalizeSignedDegrees(current.panDelta - previous.pan)) >= changeThreshold
            let tiltChanged = includeTilt && abs(current.tiltDelta - previous.tilt) >= changeThreshold
            if !panChanged && !tiltChanged { return nil }
        }

        var text = ""
        var lastWhole = 0
        if includePan {
            lastWhole = Int(panWhole)
            text = "Pan \(current.panDelta > 0 ? "right" : "left") \(lastWhole)"
        }
        if includeTilt {
            lastWhole = Int(tiltWhole)
            let words = "\(current.tiltDelta > 0 ? "up" : "down") \(lastWhole)"
            text = includePan ? "\(text), tilt \(words)" : "Tilt \(words)"
        }
        if !saidDegrees { text += lastWhole == 1 ? " degree" : " degrees" }
        return spoken(text, kind: .guidance, current: current, now: now, hasSaidDegrees: true)
    }

    private static func spoken(_ text: String, kind: SpokenKind, current: Guidance, now: Date,
                               hasSaidDegrees: Bool) -> SpokenPhrase {
        SpokenPhrase(text: text, state: SpokenState(kind: kind, pan: current.panDelta, tilt: current.tiltDelta, time: now,
                                                    hasSaidDegrees: hasSaidDegrees))
    }
}
