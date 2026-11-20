import Foundation

/// What the iPhone app sends the Apple Watch app's Aim page while it aims: the pan and tilt still to make, how far away the
/// target is, and a few flags, as a `WCSession` message of property-list values about twice a second. The iPhone app
/// builds the same keys in `Lodestar/Features/Widgets/WatchAimLink.swift`.
///
/// Decoding is defensive: a message that is not an aim message, or holds a value that is not finite or outside its range,
/// is dropped.
struct AimWristMessage: Equatable, Sendable {
    /// How close the camera is to the target (the raw values of the engine's `GuidanceState`).
    enum State: String, Sendable {
        case onTarget, close, far
    }

    static let versionKey = "aim"
    static let version = 1
    /// The longest target name kept, in characters.
    static let maximumNameLength = 40

    /// When the phone sent it, seconds since 1970 on the phone's clock; grows with every message, so it orders them.
    let sent: TimeInterval
    /// Degrees to pan to centre the target; positive means right.
    let pan: Double
    /// Degrees to tilt; positive means up.
    let tilt: Double
    /// Angle between the camera and the target, degrees.
    let separation: Double
    let state: State
    let isBelowHorizon: Bool
    /// Within a few degrees of the zenith, where azimuth (the pan) is a poor guide.
    let isNearZenith: Bool
    /// Whether the phone is in night mode, so the watch dims to red as well.
    let isNight: Bool
    let targetName: String

    /// The message in `message`, or `nil` if it is not a valid aim message.
    static func decode(_ message: [String: Any]) -> AimWristMessage? {
        guard message[versionKey] as? Int == version,
              let sent = message["sent"] as? Double, sent.isFinite,
              let pan = message["pan"] as? Double, pan.isFinite, abs(pan) <= 180,
              let tilt = message["tilt"] as? Double, tilt.isFinite, abs(tilt) <= 180,
              let separation = message["sep"] as? Double, separation.isFinite, (0...180).contains(separation),
              let stateName = message["state"] as? String, let state = State(rawValue: stateName) else { return nil }
        return AimWristMessage(
            sent: sent, pan: pan, tilt: tilt, separation: separation, state: state,
            isBelowHorizon: message["below"] as? Bool ?? false,
            isNearZenith: message["zenith"] as? Bool ?? false,
            isNight: message["night"] as? Bool ?? false,
            targetName: String((message["target"] as? String ?? "").prefix(maximumNameLength)))
    }

    // MARK: What the watch shows

    /// Direction of the shortest way to the target on the head's axes, radians counter-clockwise from "pan right": up is
    /// tilting up. Near the zenith the pan is left out, as the spoken guidance does.
    var arrowAngle: Double {
        let horizontal = isNearZenith && wholeTilt >= 1 ? 0 : pan
        return atan2(tilt, horizontal)
    }

    var isOnTarget: Bool { state == .onTarget && !isBelowHorizon }

    /// The moves to make, in whole degrees: "Pan right 12°", "Tilt up 3°". A move that rounds to nothing is left out;
    /// within 2° of the target, or with nothing to move, "Almost there" stands in.
    var moves: [String] {
        if separation < 2 { return ["Almost there"] }
        var lines: [String] = []
        if wholePan >= 1 && !(isNearZenith && wholeTilt >= 1) {
            lines.append("Pan \(pan > 0 ? "right" : "left") \(wholePan)\u{00B0}")
        }
        if wholeTilt >= 1 {
            lines.append("Tilt \(tilt > 0 ? "up" : "down") \(wholeTilt)\u{00B0}")
        }
        return lines.isEmpty ? ["Almost there"] : lines
    }

    /// "26° away", with a decimal below 10°.
    var distanceText: String {
        separation < 10 ? String(format: "%.1f\u{00B0} away", separation) : "\(Int(separation.rounded()))\u{00B0} away"
    }

    /// The whole screen for VoiceOver: "Pan right 12°, Tilt up 3°, 12° away, Orion Nebula".
    var spokenSummary: String {
        if isBelowHorizon { return "Target is below the horizon" }
        if isOnTarget { return targetName.isEmpty ? "On target" : "On target, \(targetName)" }
        let parts = moves + [distanceText] + (targetName.isEmpty ? [] : [targetName])
        return parts.joined(separator: ", ")
    }

    private var wholePan: Int { Int(abs(pan).rounded()) }
    private var wholeTilt: Int { Int(abs(tilt).rounded()) }
}
