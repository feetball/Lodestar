import Foundation

/// The eight named phases of the Moon.
public enum MoonPhaseName: String, CaseIterable, Codable, Sendable {
    case newMoon, waxingCrescent, firstQuarter, waxingGibbous, fullMoon, waningGibbous, lastQuarter, waningCrescent

    /// Half-width in degrees of the elongation range, around 0°, 90°, 180° and 270°, that counts
    /// as new moon, first quarter, full moon and last quarter (about 22 hours on either side).
    public static let principalHalfWidth = 11.25

    /// The phase name for a lunar elongation (Moon minus Sun ecliptic longitude) in degrees.
    ///
    /// The four principal phases cover `principalHalfWidth` either side of 0°, 90°, 180° and 270°;
    /// the crescent and gibbous phases fill the gaps between them.
    public init(elongation: Double) {
        let normalized = AstroMath.normalizeDegrees(elongation.isFinite ? elongation : 0)
        let width = Self.principalHalfWidth
        switch normalized {
        case ..<width: self = .newMoon
        case ..<(90 - width): self = .waxingCrescent
        case ..<(90 + width): self = .firstQuarter
        case ..<(180 - width): self = .waxingGibbous
        case ..<(180 + width): self = .fullMoon
        case ..<(270 - width): self = .waningGibbous
        case ..<(270 + width): self = .lastQuarter
        case ..<(360 - width): self = .waningCrescent
        default: self = .newMoon
        }
    }

    /// The English name, e.g. "Waxing Crescent".
    public var displayName: String {
        switch self {
        case .newMoon: "New Moon"
        case .waxingCrescent: "Waxing Crescent"
        case .firstQuarter: "First Quarter"
        case .waxingGibbous: "Waxing Gibbous"
        case .fullMoon: "Full Moon"
        case .waningGibbous: "Waning Gibbous"
        case .lastQuarter: "Last Quarter"
        case .waningCrescent: "Waning Crescent"
        }
    }

    /// The matching SF Symbol (drawn as seen from the northern hemisphere).
    public var symbolName: String {
        switch self {
        case .newMoon: "moonphase.new.moon"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .fullMoon: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        }
    }
}

/// The four instants of a lunation that astronomers tabulate.
public enum PrincipalMoonPhase: String, CaseIterable, Codable, Sendable {
    case newMoon, firstQuarter, fullMoon, lastQuarter

    /// The lunar elongation in degrees at which the phase occurs: 0, 90, 180 or 270.
    public var elongation: Double {
        switch self {
        case .newMoon: 0
        case .firstQuarter: 90
        case .fullMoon: 180
        case .lastQuarter: 270
        }
    }

    /// The English name, e.g. "Full Moon".
    public var displayName: String { name.displayName }

    /// The matching SF Symbol.
    public var symbolName: String { name.symbolName }

    /// The corresponding `MoonPhaseName`.
    public var name: MoonPhaseName {
        switch self {
        case .newMoon: .newMoon
        case .firstQuarter: .firstQuarter
        case .fullMoon: .fullMoon
        case .lastQuarter: .lastQuarter
        }
    }
}

/// The Moon's phase at one instant.
public struct MoonPhaseInfo: Sendable, Hashable {
    /// The instant the values describe.
    public let date: Date
    /// Fraction of the visible disc that is sunlit, [0, 1].
    public let illuminatedFraction: Double
    /// The Sun–Moon–Earth angle in degrees, [0, 180]; 0° at full moon, 180° at new moon.
    public let phaseAngle: Double
    /// The Moon's apparent ecliptic longitude minus the Sun's, in degrees, [0, 360).
    public let elongation: Double
    /// Days since the previous new moon.
    public let ageDays: Double
    /// The named phase for this elongation.
    public let name: MoonPhaseName

    /// `true` between new moon and full moon.
    public var isWaxing: Bool { elongation < 180 }
}

/// Phase of the Moon and the dates of new moon, quarters and full moon.
public enum MoonPhaseCalculator {
    /// Mean length of the synodic month in days.
    public static let meanSynodicMonthDays = 29.530_588_861
    /// The largest number of phases `nextPhases` returns.
    public static let maximumPhaseCount = 1_000

    /// Mean rate of change of the elongation in degrees per day.
    private static let meanElongationRate = 360 / meanSynodicMonthDays

    /// The phase of the Moon at `date`.
    public static func info(at date: Date) -> MoonPhaseInfo {
        let julianDate = JulianDate(date: date)
        let state = Ephemeris.state(of: .moon, at: julianDate)
        let elongation = Ephemeris.lunarElongation(at: julianDate)
        let previousNewMoon = instant(ofElongation: 0, near: julianDate.addingDays(-elongation / meanElongationRate))
        return MoonPhaseInfo(date: date,
                             illuminatedFraction: state.illuminatedFraction ?? 0,
                             phaseAngle: state.phaseAngle ?? 0,
                             elongation: elongation,
                             ageDays: max(0, julianDate.ut - previousNewMoon.ut),
                             name: MoonPhaseName(elongation: elongation))
    }

    /// The next `count` new moons, first quarters, full moons and last quarters after `date`, in
    /// time order. `count` is limited to `maximumPhaseCount`. A phase less than a second after
    /// `date` counts as `date` itself, so passing the date of one result returns the following phases.
    ///
    /// The instants are found by root finding on the difference of the apparent geocentric
    /// ecliptic longitudes of the Moon and the Sun, as in the Astronomical Almanac.
    public static func nextPhases(after date: Date, count: Int) -> [(kind: PrincipalMoonPhase, date: Date)] {
        let wanted = min(max(count, 0), maximumPhaseCount)
        var phases = [(kind: PrincipalMoonPhase, date: Date)]()
        guard wanted > 0, date.timeIntervalSince1970.isFinite else { return phases }
        let start = JulianDate(date: date)
        let startElongation = Ephemeris.lunarElongation(at: start)
        guard startElongation.isFinite else { return phases }
        var quarterIndex = Int(startElongation / 90) + 1
        var estimate = start.addingDays((90 * Double(quarterIndex) - startElongation) / meanElongationRate)
        // At most the first two candidates can fall at or before `date`; every later one is appended.
        for _ in 0..<(wanted + 2) where phases.count < wanted {
            let kind = PrincipalMoonPhase.allCases[quarterIndex % 4]
            let moment = instant(ofElongation: kind.elongation, near: estimate)
            if moment.date.timeIntervalSince(date) > 1 {
                phases.append((kind, moment.date))
            }
            quarterIndex += 1
            estimate = moment.addingDays(meanSynodicMonthDays / 4)
        }
        return phases
    }

    /// The instant near `estimate` at which the lunar elongation equals `target` degrees (secant method).
    private static func instant(ofElongation target: Double, near estimate: JulianDate) -> JulianDate {
        func error(at julianDate: JulianDate) -> Double {
            AstroMath.normalizeSignedDegrees(Ephemeris.lunarElongation(at: julianDate) - target)
        }
        var previous = estimate
        var previousError = error(at: previous)
        var current = previous.addingDays(-previousError / meanElongationRate)
        var currentError = error(at: current)
        for _ in 0..<10 {
            guard abs(current.ut - previous.ut) > 1e-7, currentError != previousError else { break }
            let next = current.addingDays(-currentError * (current.ut - previous.ut) / (currentError - previousError))
            previous = current
            previousError = currentError
            current = next
            currentError = error(at: current)
        }
        return current
    }
}
