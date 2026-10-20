import Foundation
import LodestarKit

/// The words of the comet and asteroid screens: rows, warnings, the tail card and the lists. The Android app uses the
/// same texts. Pure, so it can be used on any thread.
enum SmallBodyText {
    static let noBrightnessData = "no brightness data"
    static let twilightGlow = "in the twilight glow"
    static let positionApproximate = "position approximate"
    static let noCurrentOrbit = "no current orbit"

    static let photographable = "Photographable"

    static let tailTitle = "Ion tail direction (approximate)"
    static let tailNote = "The real tail is up to several degrees long and curves. "
        + "Tilting the camera by this much lays it along the frame."
    static let tailForeshortened = "Seen almost end-on, so the tail is short and hard to make out."

    static let targetsNote = "Comets and asteroids come first when they are bright and high enough tonight."

    static let footnote = "Magnitudes are estimates, good to a magnitude or two. "
        + "Only bodies at least 25\u{00B0} from the Sun are listed."

    /// Half a day in seconds: the elements of a file are given for 0h of a day.
    private static let halfDay: TimeInterval = 43_200

    // MARK: Names

    /// `true` for a comet or an asteroid.
    static func isSmallBody(_ object: CelestialObject) -> Bool {
        object.smallBody != nil
    }

    /// The name for rows and buttons: the common name of a comet or an asteroid ("Tsuchinshan-ATLAS", "Vesta"), else
    /// its designation ("2024 YR4"); the name of every other object.
    static func displayName(_ object: CelestialObject) -> String {
        object.smallBody == nil ? object.name : (object.alternateNames.first ?? object.name)
    }

    /// The kind of body an identifier like "comet.12P" or "asteroid.4" stands for, `nil` for other identifiers.
    static func kind(ofID id: String) -> SmallBodyKind? {
        if id.hasPrefix("comet.") { return .comet }
        if id.hasPrefix("asteroid.") { return .asteroid }
        return nil
    }

    /// The designation in a small-body identifier: "12P" for "comet.12P".
    static func designation(ofID id: String) -> String {
        guard let dot = id.firstIndex(of: ".") else { return id }
        return String(id[id.index(after: dot)...])
    }

    // MARK: Numbers

    /// The magnitude with one decimal and a true minus sign: "7.4", "−0.3".
    static func magnitudeNumber(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = abs(rounded).formatted(.number.precision(.fractionLength(1)))
        return (rounded < 0 ? "\u{2212}" : "") + text
    }

    /// The magnitude as an estimate: "mag ≈ 7.4"; "no brightness data" (capitalised with `sentence`) for `nil`.
    static func magnitude(_ value: Double?, sentence: Bool = false) -> String {
        guard let value, value.isFinite else {
            return sentence ? capitalized(noBrightnessData) : noBrightnessData
        }
        return "mag \u{2248} \(magnitudeNumber(value))"
    }

    /// "62° from the Sun".
    static func elongation(_ degrees: Double) -> String {
        "\(AngleFormatter.formatDegrees(degrees, decimals: 0)) from the Sun"
    }

    /// The warning as it reads inside a line of text.
    static func warning(_ warning: SmallBodyWarning) -> String {
        switch warning {
        case .twilightGlow: return twilightGlow
        case .positionApproximate: return positionApproximate
        case .noBrightnessData: return noBrightnessData
        }
    }

    /// The warning as a sentence of its own ("In the twilight glow"), for chips and notes.
    static func sentence(_ warning: SmallBodyWarning) -> String {
        capitalized(Self.warning(warning))
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: Rows

    /// Kind, magnitude estimate and elongation on one line, then the warnings: "Comet · mag ≈ 7.4 · 62° from the Sun",
    /// "Asteroid · no brightness data · 18° from the Sun · in the twilight glow". `info` is `nil` before the
    /// position is known (`isComputed` false) or when the orbit cannot be evaluated ("no current orbit"). With
    /// `spoken` the parts are separated by commas and written out.
    static func subtitle(of object: CelestialObject, info: SmallBodyInfo?, isComputed: Bool, spoken: Bool = false,
                         withWarnings: Bool = true) -> String {
        var parts = [object.category.displayName]
        if let info {
            parts.append(magnitude(info.magnitude))
            parts.append(elongation(info.elongation))
            if withWarnings {
                // "no brightness data" has been said by the magnitude part.
                parts += info.warnings.filter { $0 != .noBrightnessData }.map(Self.warning)
            }
        } else if isComputed {
            parts.append(noCurrentOrbit)
        }
        if spoken {
            return parts.map {
                $0.replacingOccurrences(of: "mag \u{2248} ", with: "magnitude about ")
                    .replacingOccurrences(of: "\u{00B0}", with: " degrees")
            }.joined(separator: ", ")
        }
        // When the line wraps, the dot stays with the text before it (a line never starts with one) and "mag ≈ 7.4"
        // stays in one piece.
        return parts.map { $0.replacingOccurrences(of: "mag \u{2248} ", with: "mag\u{00A0}\u{2248}\u{00A0}") }
            .joined(separator: "\u{00A0}\u{00B7} ")
    }

    /// The one line under a name in the picker, Tonight and the lists: kind, estimate and elongation.
    static func summary(of object: CelestialObject, info: SmallBodyInfo?) -> String {
        subtitle(of: object, info: info, isComputed: true)
    }

    /// `summary(of:info:)` for the info of `object` at `date`; just the kind for any other object.
    static func summary(of object: CelestialObject, at date: Date) -> String {
        guard let body = object.smallBody else { return object.category.displayName }
        return summary(of: object, info: SmallBodyInfo.compute(body, at: date))
    }

    // MARK: Detail

    /// The date of the orbital elements, "Oct 17, 2026".
    static func elementsDate(of body: SmallBody) -> String {
        // Epochs are quoted in dynamical time (0h TT): label the calendar day of that clock, not of UTC.
        let epoch = JulianDate(tt: body.orbit.epochJulianDayTT)
        let date = epoch.date.addingTimeInterval(epoch.deltaT + halfDay)
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }

    /// "Straight up", "35° to the right of up", "20° to the left of up", "Straight down".
    static func tailDirection(_ angleFromVertical: Double) -> String {
        let degrees = Int(roundedHalfUp(abs(angleFromVertical)))
        if degrees == 0 { return "Straight up" }
        if degrees == 180 { return "Straight down" }
        return angleFromVertical > 0 ? "\(degrees)\u{00B0} to the right of up" : "\(degrees)\u{00B0} to the left of up"
    }

    /// "12° clockwise", "12° counter-clockwise" or "None needed".
    static func cameraTilt(_ tilt: Double) -> String {
        let degrees = Int(roundedHalfUp(abs(tilt)))
        if degrees == 0 { return "None needed" }
        return tilt > 0 ? "\(degrees)\u{00B0} clockwise" : "\(degrees)\u{00B0} counter-clockwise"
    }

    /// Rounds halves up, as the Android app does.
    static func roundedHalfUp(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    // MARK: Moving targets

    /// Why a mosaic cannot cover `object`, a comet or an asteroid.
    static func mosaicRefusal(for object: CelestialObject) -> String {
        "\(displayName(object)) moves among the stars, so a mosaic cannot follow it. Plan a custom size instead."
    }
}
