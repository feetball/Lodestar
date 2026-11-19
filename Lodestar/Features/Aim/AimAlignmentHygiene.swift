import Foundation
import LodestarKit

/// How the age of an alignment reads: "Aligned 12 min ago" on the card, "Alignment 3 h old" on the chip.
enum AimAlignmentAge {
    /// Shown on the card when the alignment is stale.
    static let staleAdvice = "This alignment is getting old. Align on a star again for the best accuracy."

    /// Whole minutes and hours of `seconds`: "12 min", "3 h" or "1 h 30 min"; "just now" below a minute.
    static func text(seconds: Double) -> String {
        let minutes = seconds.isFinite && seconds > 0 ? Int((seconds / 60).rounded(.down)) : 0
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min" }
        if minutes % 60 == 0 { return "\(minutes / 60) h" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    /// The line on the alignment card, `seconds` after the alignment was made.
    static func cardText(seconds: Double) -> String {
        let age = text(seconds: seconds)
        return age == "just now" ? "Aligned just now" : "Aligned \(age) ago"
    }

    /// The text of the stale chip.
    static func chipText(seconds: Double) -> String {
        "Alignment \(text(seconds: seconds)) old"
    }
}

/// How far a reference object is from the alignment points already taken, as the alignment sheet words it.
enum AimAlignmentSpacing {
    /// Whole degrees, rounded down so that "19°" never sits beside a limit of 20°; arc minutes below a degree.
    static func degreesText(_ degrees: Double) -> String {
        degrees >= 1 ? "\(Int(degrees.rounded(.down)))\u{00B0}" : AppFormat.separation(degrees)
    }

    /// The nearest point's name, or "point 2" when it has none.
    static func pointLabel(_ nearest: AlignmentPointSeparation) -> String {
        nearest.pointName ?? "point \(nearest.pointIndex + 1)"
    }

    /// "47° from Vega", for the candidate list.
    static func nearestText(_ nearest: AlignmentPointSeparation) -> String {
        "\(degreesText(nearest.degrees)) from \(pointLabel(nearest))"
    }

    /// Whether `nearest` is closer than the spacing that gives a well-conditioned fit.
    static func isTooClose(_ nearest: AlignmentPointSeparation) -> Bool {
        nearest.degrees < AlignmentHygiene.minimumPointSeparationDegrees
    }

    /// The warning for syncing `candidate` next to the `existing` points, or `nil` when it is far enough from all of
    /// them (or there are none): "Only 8° from Vega: pick a star at least 20° away for a better fit".
    static func warningText(candidate: HorizontalCoordinate, existing: [AlignmentPoint]) -> String? {
        guard AlignmentHygiene.separationWarning(candidate: candidate, existing: existing) != nil,
              let nearest = AlignmentHygiene.bestSeparation(candidate: candidate, existing: existing) else { return nil }
        let minimum = Int(AlignmentHygiene.minimumPointSeparationDegrees)
        return "Only \(degreesText(nearest.degrees)) from \(pointLabel(nearest)): pick a star at least \(minimum)\u{00B0} away for a better fit"
    }
}
