import Foundation
import LodestarKit

/// The facts of one satellite pass that the Live Activity shows, as plain values: when it rises, peaks and sets, where
/// to look for each, and how high it gets. Nothing here depends on ActivityKit, so the stages and the words are
/// testable and the value travels inside the activity's attributes.
struct SatellitePassTimeline: Sendable, Codable, Hashable {
    /// Where the pass is at one moment.
    enum Stage: Int, Sendable, Codable, Hashable, Comparable {
        case waiting
        case risen
        case peaked
        case over

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let rise: Date
    let peak: Date
    let set: Date
    /// Azimuths from true north through east, degrees.
    let riseAzimuth: Double
    let peakAzimuth: Double
    let setAzimuth: Double
    /// How high the pass gets, degrees.
    let peakAltitude: Double

    /// A timeline, or `nil` when the moments are not in order or a number is not finite.
    init?(rise: Date, peak: Date, set: Date, riseAzimuth: Double, peakAzimuth: Double, setAzimuth: Double,
          peakAltitude: Double) {
        guard rise <= peak, peak <= set,
              [riseAzimuth, peakAzimuth, setAzimuth, peakAltitude].allSatisfy(\.isFinite) else { return nil }
        self.rise = rise
        self.peak = peak
        self.set = set
        self.riseAzimuth = riseAzimuth
        self.peakAzimuth = peakAzimuth
        self.setAzimuth = setAzimuth
        self.peakAltitude = peakAltitude
    }

    /// The stage at `date`: before the rise, between rise and peak, between peak and set, after the set.
    func stage(at date: Date) -> Stage {
        if date < rise { return .waiting }
        if date < peak { return .risen }
        if date < set { return .peaked }
        return .over
    }

    /// The moment the display has to change next (the rise, the peak, the set), or `nil` once the pass is over.
    func nextChange(after date: Date) -> Date? {
        switch stage(at: date) {
        case .waiting: return rise
        case .risen: return peak
        case .peaked: return set
        case .over: return nil
        }
    }

    /// The moment a countdown shown in `stage` runs to: the rise before it, the peak after it, none later.
    func countdownTarget(in stage: Stage) -> Date? {
        switch stage {
        case .waiting: return rise
        case .risen: return peak
        case .peaked, .over: return nil
        }
    }

    /// Where to look in `stage`: where it comes up, then where it peaks, then where it sets.
    func lookAzimuth(in stage: Stage) -> Double {
        switch stage {
        case .waiting: return riseAzimuth
        case .risen: return peakAzimuth
        case .peaked, .over: return setAzimuth
        }
    }
}

/// The words of the Live Activity. The Android notification says the same things.
enum SatellitePassWords {
    /// What the countdown counts to, as a short label above or beside it.
    static func countdownLabel(_ stage: SatellitePassTimeline.Stage) -> String {
        switch stage {
        case .waiting: return "Rises in"
        case .risen: return "Peak in"
        case .peaked: return "Past the peak"
        case .over: return "Pass over"
        }
    }

    /// "Look NE 45°": the compass point and azimuth to look at.
    static func look(_ azimuth: Double, in stage: SatellitePassTimeline.Stage) -> String {
        let verb = stage == .peaked || stage == .over ? "Sets" : "Look"
        return "\(verb) \(direction(azimuth))"
    }

    /// "NE 45°".
    static func direction(_ azimuth: Double) -> String {
        let normalized = azimuth.truncatingRemainder(dividingBy: 360)
        let degrees = normalized < 0 ? normalized + 360 : normalized
        let rounded = Int(degrees.rounded()) % 360
        return "\(AngleFormatter.compassPoint(azimuth: degrees).abbreviation) \(rounded)\u{00B0}"
    }

    /// "Max 64°".
    static func maximum(_ altitude: Double) -> String {
        "Max \(Int(altitude.rounded()))\u{00B0}"
    }

    /// What VoiceOver reads for the activity.
    static func spoken(name: String, timeline: SatellitePassTimeline, stage: SatellitePassTimeline.Stage) -> String {
        let height = "It gets \(Int(timeline.peakAltitude.rounded())) degrees high."
        switch stage {
        case .waiting:
            return "\(name) rises soon in the \(compassName(timeline.riseAzimuth)). \(height)"
        case .risen:
            return "\(name) is up. It peaks soon in the \(compassName(timeline.peakAzimuth)). \(height)"
        case .peaked:
            return "\(name) is past its peak. It sets in the \(compassName(timeline.setAzimuth))."
        case .over:
            return "The \(name) pass is over."
        }
    }

    private static func compassName(_ azimuth: Double) -> String {
        AngleFormatter.compassPoint(azimuth: azimuth).fullName.lowercased()
    }
}
