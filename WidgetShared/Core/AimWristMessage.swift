import Foundation
import LodestarKit

/// What the iPhone app sends the Apple Watch app's Aim page while it aims: the pan and tilt still to make, how far away the
/// target is, and a few flags, as a `WCSession` message of property-list values about twice a second. The iPhone app
/// builds it with `wireMessage` (`Lodestar/Features/Widgets/WatchAimLink.swift`) and the watch app reads it with `decode`,
/// so the keys below are written once.
///
/// Decoding is defensive: a message that is not an aim message, or holds a value that is not finite or outside its range,
/// is dropped.
struct AimWristMessage: Equatable, Sendable {
    /// How close the camera is to the target: the engine's `GuidanceState`, written on the wire as its raw value.
    enum State: String, Sendable {
        case onTarget, close, far

        /// The state of the engine's guidance. A new `GuidanceState` is a compile error here until the watch has
        /// a word for it.
        init(_ guidance: GuidanceState) {
            switch guidance {
            case .onTarget: self = .onTarget
            case .close: self = .close
            case .far: self = .far
            }
        }
    }

    static let versionKey = "aim"
    static let version = 1
    static let sentKey = "sent"
    static let panKey = "pan"
    static let tiltKey = "tilt"
    static let separationKey = "sep"
    static let stateKey = "state"
    static let belowHorizonKey = "below"
    static let nearZenithKey = "zenith"
    static let nightKey = "night"
    static let targetKey = "target"
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

    /// The message as the iPhone app sends it: property-list values only, a few dozen bytes. A target name longer
    /// than `maximumNameLength` is cut. `decode` reads it back.
    var wireMessage: [String: Any] {
        [
            Self.versionKey: Self.version,
            Self.sentKey: sent,
            Self.panKey: pan,
            Self.tiltKey: tilt,
            Self.separationKey: separation,
            Self.stateKey: state.rawValue,
            Self.belowHorizonKey: isBelowHorizon,
            Self.nearZenithKey: isNearZenith,
            Self.nightKey: isNight,
            Self.targetKey: String(targetName.prefix(Self.maximumNameLength)),
        ]
    }

    /// The message in `message`, or `nil` if it is not a valid aim message.
    static func decode(_ message: [String: Any]) -> AimWristMessage? {
        guard message[versionKey] as? Int == version,
              let sent = message[sentKey] as? Double, sent.isFinite,
              let pan = message[panKey] as? Double, pan.isFinite, abs(pan) <= 180,
              let tilt = message[tiltKey] as? Double, tilt.isFinite, abs(tilt) <= 180,
              let separation = message[separationKey] as? Double, separation.isFinite, (0...180).contains(separation),
              let stateName = message[stateKey] as? String, let state = State(rawValue: stateName) else { return nil }
        return AimWristMessage(
            sent: sent, pan: pan, tilt: tilt, separation: separation, state: state,
            isBelowHorizon: message[belowHorizonKey] as? Bool ?? false,
            isNearZenith: message[nearZenithKey] as? Bool ?? false,
            isNight: message[nightKey] as? Bool ?? false,
            targetName: String((message[targetKey] as? String ?? "").prefix(maximumNameLength)))
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
