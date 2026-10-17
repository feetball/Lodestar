import Foundation

/// A rule of thumb for the longest exposure that keeps stars looking like points.
public enum ExposureRule: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    /// 500 ÷ full-frame-equivalent focal length.
    case rule500
    /// 400 ÷ full-frame-equivalent focal length.
    case rule400
    /// 300 ÷ full-frame-equivalent focal length.
    case rule300
    /// Frédéric Michaud's NPF rule: (35 × aperture + 30 × pixel pitch) ÷ focal length.
    case npf

    /// A stable identifier, equal to the raw value.
    public var id: String { rawValue }

    /// A short name for pickers, for example "500 rule".
    public var displayName: String {
        switch self {
        case .rule500: return "500 rule"
        case .rule400: return "400 rule"
        case .rule300: return "300 rule"
        case .npf: return "NPF rule"
        }
    }

    /// A one-sentence description of how the rule works and when to prefer it.
    public var summary: String {
        switch self {
        case .rule500:
            return "500 divided by the full-frame-equivalent focal length. Simple, but too lenient for dense sensors."
        case .rule400:
            return "A stricter variant: 400 divided by the full-frame-equivalent focal length."
        case .rule300:
            return "The strictest variant: 300 divided by the full-frame-equivalent focal length."
        case .npf:
            return "Michaud's rule uses aperture, pixel pitch and focal length, and suits high-resolution sensors best."
        }
    }

    /// The numerator of the 500/400/300 family; nil for NPF.
    fileprivate var equivalentFocalLengthNumerator: Double? {
        switch self {
        case .rule500: return 500
        case .rule400: return 400
        case .rule300: return 300
        case .npf: return nil
        }
    }
}

/// The result of an exposure calculation.
public struct ExposureEstimate: Hashable, Sendable {
    /// The longest suggested exposure, in seconds. A guideline, not a guarantee.
    public let seconds: Double

    /// The rule that produced the estimate.
    public let rule: ExposureRule

    /// Whether the NPF rule had to assume `ExposureCalculator.defaultPixelPitchMicrometers`
    /// because the setup has no pixel pitch. Always false for the other rules.
    public let usedDefaultPixelPitch: Bool

    /// The factor applied for the target's declination: 1 when none was given or it is at the
    /// celestial equator, up to `ExposureCalculator.maximumDeclinationFactor` near the poles.
    public let declinationFactor: Double

    /// Plain-language remarks on assumptions and adjustments, in English, suitable for a footnote.
    public let notes: [String]
}

/// Computes the longest exposure that avoids visible star trails, and the length of the trails
/// an exposure produces.
///
/// Stars move across the sky at the sidereal rate, which is fastest at the celestial equator and
/// slows by cos(declination) towards the poles. Without a declination every estimate assumes the
/// equator, the worst case.
public enum ExposureCalculator: Sendable {

    /// The pixel pitch, in micrometres, that NPF assumes when the setup has none.
    ///
    /// 4.0 µm is typical of a 45-megapixel full-frame or a 24 to 26-megapixel APS-C camera. Cameras
    /// with larger pixels can expose longer, so the assumption errs towards shorter exposures.
    public static let defaultPixelPitchMicrometers = 4.0

    /// The largest factor by which a declination may lengthen an exposure.
    ///
    /// 1 / cos(declination) grows without bound towards the pole. The factor is capped at 5, which
    /// is reached at about 78.5° of declination, because a wide frame also contains stars farther
    /// from the pole than the target, and those trail more.
    public static let maximumDeclinationFactor = 5.0

    /// The rate at which stars at the celestial equator cross the sky, in arcseconds per second
    /// of time: 360° per sidereal day.
    public static let siderealRateArcsecondsPerSecond = 15.041

    /// NPF's weight, in seconds × millimetres per f-number, for the aperture term (diffraction).
    private static let npfApertureCoefficient = 35.0

    /// NPF's weight, in seconds × millimetres per micrometre, for the pixel pitch term.
    private static let npfPixelPitchCoefficient = 30.0

    /// Estimates the longest exposure before stars visibly trail.
    ///
    /// The 500, 400 and 300 rules divide their constant by the full-frame-equivalent focal length
    /// (focal length × crop factor). NPF uses the real focal length together with aperture and
    /// pixel pitch: `(35 × N + 30 × p) / f`, with `N` the f-number, `p` the pixel pitch in µm and
    /// `f` the focal length in mm. When the setup has no pixel pitch NPF assumes
    /// `defaultPixelPitchMicrometers` and sets `usedDefaultPixelPitch`.
    ///
    /// A declination multiplies the result by 1 / cos(declination), capped at
    /// `maximumDeclinationFactor`, because stars near the celestial pole trail less. A declination
    /// outside ±90° or not finite is ignored and noted.
    ///
    /// - Parameters:
    ///   - rule: The rule to apply.
    ///   - setup: The camera and lens.
    ///   - declination: The declination of the target in degrees, or nil to assume the celestial equator.
    public static func maxExposure(
        rule: ExposureRule,
        setup: LensSetup,
        declination: Double? = nil
    ) -> ExposureEstimate {
        var notes: [String] = []
        var usedDefaultPixelPitch = false

        let baseSeconds: Double
        if let numerator = rule.equivalentFocalLengthNumerator {
            baseSeconds = numerator / setup.equivalentFocalLengthMillimeters
        } else {
            let pitch: Double
            if let known = setup.pixelPitchMicrometers {
                pitch = known
            } else {
                pitch = defaultPixelPitchMicrometers
                usedDefaultPixelPitch = true
                notes.append(
                    "Pixel pitch unknown: assumed \(pitch) \u{00B5}m. "
                        + "Enter the camera's resolution for an exact NPF result."
                )
            }
            baseSeconds = (npfApertureCoefficient * setup.aperture + npfPixelPitchCoefficient * pitch)
                / setup.focalLengthMillimeters
        }

        let factor = declinationFactor(for: declination, notes: &notes)
        return ExposureEstimate(
            seconds: baseSeconds * factor,
            rule: rule,
            usedDefaultPixelPitch: usedDefaultPixelPitch,
            declinationFactor: factor,
            notes: notes
        )
    }

    /// The length of the trail a star draws during an exposure, in arcseconds.
    ///
    /// An exposure that is negative or not finite counts as zero, and a declination that is nil,
    /// not finite or outside ±90° counts as the celestial equator, where trails are longest.
    ///
    /// - Parameters:
    ///   - exposureSeconds: The exposure time in seconds.
    ///   - declination: The star's declination in degrees, or nil to assume the celestial equator.
    public static func trailLengthArcseconds(exposureSeconds: Double, declination: Double? = nil) -> Double {
        let seconds = exposureSeconds.isFinite ? max(exposureSeconds, 0) : 0
        let degrees = declination.flatMap { (-90.0...90.0).contains($0) ? $0 : nil } ?? 0
        return siderealRateArcsecondsPerSecond * seconds * cos(degrees * .pi / 180)
    }

    /// The length of the trail a star draws during an exposure, in pixels of the image.
    ///
    /// Divides `trailLengthArcseconds(exposureSeconds:declination:)` by the setup's image scale.
    /// When the setup has no pixel pitch, `defaultPixelPitchMicrometers` is assumed, as for NPF;
    /// check `setup.pixelPitchMicrometers` to tell whether the result is an estimate.
    ///
    /// - Parameters:
    ///   - exposureSeconds: The exposure time in seconds.
    ///   - declination: The star's declination in degrees, or nil to assume the celestial equator.
    ///   - setup: The camera and lens.
    public static func trailLengthPixels(
        exposureSeconds: Double,
        declination: Double? = nil,
        setup: LensSetup
    ) -> Double {
        let pitch = setup.pixelPitchMicrometers ?? defaultPixelPitchMicrometers
        let trail = trailLengthArcseconds(exposureSeconds: exposureSeconds, declination: declination)
        return trail / setup.imageScale(forPixelPitch: pitch)
    }

    // MARK: Declination

    /// The exposure multiplier for a target declination, appending an explanatory note when it
    /// changes the result. Returns 1 for nil and for invalid declinations.
    private static func declinationFactor(for declination: Double?, notes: inout [String]) -> Double {
        guard let declination else { return 1 }
        guard (-90.0...90.0).contains(declination) else {
            notes.append("Declination ignored: it must be between \u{2212}90\u{00B0} and +90\u{00B0}.")
            return 1
        }

        let uncapped = 1 / cos(declination * .pi / 180)
        let factor = min(uncapped, maximumDeclinationFactor)
        // At the equator (and within rounding of it) there is nothing to explain.
        guard factor >= 1.05 else { return factor }

        let signed = AngleFormatter.formatSignedDegrees(declination, decimals: 1)
        let applied = NumberText.fixedDescription(factor, decimals: 1)
        if uncapped > maximumDeclinationFactor {
            notes.append(
                "Declination \(signed) lengthens the limit \u{00D7}\(applied), the maximum, "
                    + "because a wide frame also contains stars farther from the pole."
            )
        } else {
            notes.append(
                "Declination \(signed) lengthens the limit \u{00D7}\(applied) "
                    + "because stars near the celestial pole move more slowly."
            )
        }
        return factor
    }
}
