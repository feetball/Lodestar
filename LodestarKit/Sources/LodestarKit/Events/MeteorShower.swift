import Foundation

/// One shower of the IMO Working List of Visual Meteor Showers.
///
/// Source: International Meteor Organization, *2026 Meteor Shower Calendar* (IMO INFO 3-25, edited by Jürgen
/// Rendtel), archived copy https://web.archive.org/web/20251223170423/https://imo.net/files/meteor-shower/cal2026.pdf
/// (sha256 fde5388889ebda9fe13436d793da5e9935ae46b99edf20e0b19f7fe32ce1ed9f):
/// Table 5 (details "correct according to the best information available in June 2025") for the activity period, the
/// solar longitude of the maximum (equinox J2000.0), the radiant at the maximum, the entry velocity V∞, the population
/// index r and the ZHR; and Table 6 (radiant positions through the year) for the daily drift, which is the least-squares
/// slope of the tabulated α and δ (the Draconids, with one tabulated position, and the Ursids, with two, are given the
/// slope those positions allow). Radiant places are taken as J2000. The list is hand-entered here; showers with a ZHR
/// below 5, a variable ZHR, an activity of one night or no observable radiant are not included.
public struct MeteorShower: Sendable, Hashable {
    /// The IAU three-letter code, e.g. "PER".
    public let code: String
    /// The IAU Meteor Data Center number, e.g. 7.
    public let iauNumber: Int
    /// The English name, e.g. "Perseids".
    public let name: String
    /// Month of the first day of the activity period (1…12).
    public let activityStartMonth: Int
    /// Day of the first day of the activity period.
    public let activityStartDay: Int
    /// Month of the last day of the activity period.
    public let activityEndMonth: Int
    /// Day of the last day of the activity period.
    public let activityEndDay: Int
    /// Solar longitude of the maximum in degrees (equinox J2000.0); fixes the date every year.
    public let peakSolarLongitude: Double
    /// The zenithal hourly rate at the maximum.
    public let zhr: Int
    /// The radiant (J2000) at the maximum.
    public let radiant: EquatorialCoordinate
    /// Daily drift of the radiant's right ascension in degrees per day.
    public let radiantDriftRightAscension: Double
    /// Daily drift of the radiant's declination in degrees per day.
    public let radiantDriftDeclination: Double
    /// The atmospheric entry velocity V∞ in km/s.
    public let velocity: Double
    /// The population index r.
    public let populationIndex: Double

    public init(code: String, iauNumber: Int, name: String, activityStartMonth: Int, activityStartDay: Int,
                activityEndMonth: Int, activityEndDay: Int, peakSolarLongitude: Double, zhr: Int,
                radiant: EquatorialCoordinate, radiantDriftRightAscension: Double, radiantDriftDeclination: Double,
                velocity: Double, populationIndex: Double) {
        self.code = code
        self.iauNumber = iauNumber
        self.name = name
        self.activityStartMonth = activityStartMonth
        self.activityStartDay = activityStartDay
        self.activityEndMonth = activityEndMonth
        self.activityEndDay = activityEndDay
        self.peakSolarLongitude = peakSolarLongitude
        self.zhr = zhr
        self.radiant = radiant
        self.radiantDriftRightAscension = radiantDriftRightAscension
        self.radiantDriftDeclination = radiantDriftDeclination
        self.velocity = velocity
        self.populationIndex = populationIndex
    }

    /// The instant of the maximum nearest to `date`: when the Sun's apparent ecliptic longitude (equinox J2000.0)
    /// equals `peakSolarLongitude`. The result is within half a year of `date`; the cost is a handful of solar positions.
    public func peak(near date: Date) -> Date {
        EventSearch.instant(peakUT(near: EventSearch.ut(date)))
    }

    /// The radiant (J2000) on `date`: the radiant at the maximum of the nearest return moved by the daily drift,
    /// for at most the length of the activity period on either side of the maximum.
    public func radiant(at date: Date) -> EquatorialCoordinate {
        let ut = EventSearch.ut(date)
        let peakUT = peakUT(near: ut)
        let interval = activityInterval(peakUT: peakUT)
        let days = AstroMath.clamp(ut - peakUT, interval.first - peakUT, interval.last - peakUT)
        return EquatorialCoordinate(rightAscension: radiant.rightAscension + radiantDriftRightAscension * days,
                                    declination: radiant.declination + radiantDriftDeclination * days)
    }

    /// The activity period around the maximum at `peak`, from 00:00 UT of the first day to the end of the last.
    public func activityPeriod(aroundPeak peak: Date) -> DateInterval {
        let interval = activityInterval(peakUT: EventSearch.ut(peak))
        return DateInterval(start: EventSearch.instant(interval.first), end: EventSearch.instant(interval.last))
    }

    /// `true` when `date` lies in the activity period around the nearest maximum.
    public func isActive(at date: Date) -> Bool {
        let ut = EventSearch.ut(date)
        let interval = activityInterval(peakUT: peakUT(near: ut))
        return ut >= interval.first && ut <= interval.last
    }

    func peakUT(near: Double) -> Double {
        let longitude = EventSearch.sunLongitudeJ2000(JulianDate(ut: near))
        let delta = AstroMath.normalizeSignedDegrees(peakSolarLongitude - longitude)
        return EventSearch.solveSolarLongitude(target: peakSolarLongitude,
                                               guess: near + delta / EventSearch.meanSolarRate) {
            EventSearch.sunLongitudeJ2000($0)
        }
    }

    /// The first and last UT Julian Date of the activity period that contains the maximum at `peakUT`.
    func activityInterval(peakUT: Double) -> (first: Double, last: Double) {
        guard peakUT.isFinite else { return (.nan, .nan) }
        let year = Int(JulianDate.decimalYear(julianDay: peakUT).rounded(.down))
        var start = -Double.infinity
        var end = Double.infinity
        for candidate in (year - 1)...(year + 1) {
            let first = JulianDate.julianDay(year: candidate, month: activityStartMonth, day: activityStartDay)
            if first <= peakUT, first > start { start = first }
            let last = JulianDate.julianDay(year: candidate, month: activityEndMonth, day: activityEndDay) + 1
            if last >= peakUT, last < end { end = last }
        }
        return (start, end)
    }

    /// Every shower of the list, in order of the maximum through the calendar year.
    public static let all: [MeteorShower] = [
        MeteorShower(code: "QUA", iauNumber: 10, name: "Quadrantids", activityStartMonth: 12, activityStartDay: 28,
                     activityEndMonth: 1, activityEndDay: 12, peakSolarLongitude: 283.15, zhr: 80,
                     radiant: EquatorialCoordinate(rightAscension: 230, declination: 49),
                     radiantDriftRightAscension: 0.68, radiantDriftDeclination: -0.19, velocity: 41,
                     populationIndex: 2.1),
        MeteorShower(code: "ACE", iauNumber: 102, name: "α-Centaurids", activityStartMonth: 1, activityStartDay: 31,
                     activityEndMonth: 2, activityEndDay: 20, peakSolarLongitude: 319.4, zhr: 6,
                     radiant: EquatorialCoordinate(rightAscension: 211, declination: -58),
                     radiantDriftRightAscension: 1.21, radiantDriftDeclination: -0.29, velocity: 58,
                     populationIndex: 2.0),
        MeteorShower(code: "LYR", iauNumber: 6, name: "April Lyrids", activityStartMonth: 4, activityStartDay: 14,
                     activityEndMonth: 4, activityEndDay: 30, peakSolarLongitude: 32.32, zhr: 18,
                     radiant: EquatorialCoordinate(rightAscension: 271, declination: 34),
                     radiantDriftRightAscension: 1.06, radiantDriftDeclination: 0, velocity: 49,
                     populationIndex: 2.1),
        MeteorShower(code: "ETA", iauNumber: 31, name: "η-Aquariids", activityStartMonth: 4, activityStartDay: 19,
                     activityEndMonth: 5, activityEndDay: 28, peakSolarLongitude: 45.5, zhr: 50,
                     radiant: EquatorialCoordinate(rightAscension: 338, declination: -1),
                     radiantDriftRightAscension: 0.85, radiantDriftDeclination: 0.40, velocity: 66,
                     populationIndex: 2.4),
        MeteorShower(code: "ARI", iauNumber: 171, name: "Daytime Arietids", activityStartMonth: 5,
                     activityStartDay: 14, activityEndMonth: 6, activityEndDay: 24, peakSolarLongitude: 76.7, zhr: 30,
                     radiant: EquatorialCoordinate(rightAscension: 43, declination: 24),
                     radiantDriftRightAscension: 1.0, radiantDriftDeclination: 0, velocity: 38,
                     populationIndex: 2.8),
        MeteorShower(code: "SDA", iauNumber: 5, name: "Southern δ-Aquariids", activityStartMonth: 7,
                     activityStartDay: 12, activityEndMonth: 8, activityEndDay: 23, peakSolarLongitude: 128, zhr: 25,
                     radiant: EquatorialCoordinate(rightAscension: 340, declination: -16),
                     radiantDriftRightAscension: 0.75, radiantDriftDeclination: 0.21, velocity: 41,
                     populationIndex: 2.5),
        MeteorShower(code: "CAP", iauNumber: 1, name: "α-Capricornids", activityStartMonth: 7, activityStartDay: 3,
                     activityEndMonth: 8, activityEndDay: 15, peakSolarLongitude: 128, zhr: 5,
                     radiant: EquatorialCoordinate(rightAscension: 307, declination: -10),
                     radiantDriftRightAscension: 0.91, radiantDriftDeclination: 0.27, velocity: 23,
                     populationIndex: 2.5),
        MeteorShower(code: "PER", iauNumber: 7, name: "Perseids", activityStartMonth: 7, activityStartDay: 17,
                     activityEndMonth: 8, activityEndDay: 24, peakSolarLongitude: 140, zhr: 100,
                     radiant: EquatorialCoordinate(rightAscension: 48, declination: 58),
                     radiantDriftRightAscension: 1.42, radiantDriftDeclination: 0.20, velocity: 59,
                     populationIndex: 2.2),
        MeteorShower(code: "AUR", iauNumber: 206, name: "Aurigids", activityStartMonth: 8, activityStartDay: 28,
                     activityEndMonth: 9, activityEndDay: 5, peakSolarLongitude: 158.6, zhr: 6,
                     radiant: EquatorialCoordinate(rightAscension: 91, declination: 39),
                     radiantDriftRightAscension: 1.05, radiantDriftDeclination: -0.05, velocity: 66,
                     populationIndex: 2.5),
        MeteorShower(code: "SPE", iauNumber: 208, name: "September ε-Perseids", activityStartMonth: 9,
                     activityStartDay: 5, activityEndMonth: 9, activityEndDay: 21, peakSolarLongitude: 166.7, zhr: 8,
                     radiant: EquatorialCoordinate(rightAscension: 48, declination: 40),
                     radiantDriftRightAscension: 1.06, radiantDriftDeclination: 0.06, velocity: 64,
                     populationIndex: 2.5),
        MeteorShower(code: "DRA", iauNumber: 9, name: "Draconids", activityStartMonth: 10, activityStartDay: 6,
                     activityEndMonth: 10, activityEndDay: 10, peakSolarLongitude: 195.4, zhr: 5,
                     radiant: EquatorialCoordinate(rightAscension: 262, declination: 54),
                     radiantDriftRightAscension: 0, radiantDriftDeclination: 0, velocity: 20,
                     populationIndex: 2.6),
        MeteorShower(code: "ORI", iauNumber: 8, name: "Orionids", activityStartMonth: 10, activityStartDay: 2,
                     activityEndMonth: 11, activityEndDay: 7, peakSolarLongitude: 208, zhr: 20,
                     radiant: EquatorialCoordinate(rightAscension: 95, declination: 16),
                     radiantDriftRightAscension: 0.65, radiantDriftDeclination: 0.08, velocity: 66,
                     populationIndex: 2.5),
        MeteorShower(code: "STA", iauNumber: 2, name: "Southern Taurids", activityStartMonth: 9, activityStartDay: 20,
                     activityEndMonth: 11, activityEndDay: 20, peakSolarLongitude: 223, zhr: 7,
                     radiant: EquatorialCoordinate(rightAscension: 52, declination: 15),
                     radiantDriftRightAscension: 0.76, radiantDriftDeclination: 0.19, velocity: 27,
                     populationIndex: 2.3),
        MeteorShower(code: "NTA", iauNumber: 17, name: "Northern Taurids", activityStartMonth: 10,
                     activityStartDay: 20, activityEndMonth: 12, activityEndDay: 10, peakSolarLongitude: 230, zhr: 5,
                     radiant: EquatorialCoordinate(rightAscension: 58, declination: 22),
                     radiantDriftRightAscension: 0.87, radiantDriftDeclination: 0.16, velocity: 29,
                     populationIndex: 2.3),
        MeteorShower(code: "LEO", iauNumber: 13, name: "Leonids", activityStartMonth: 11, activityStartDay: 6,
                     activityEndMonth: 11, activityEndDay: 30, peakSolarLongitude: 235.27, zhr: 15,
                     radiant: EquatorialCoordinate(rightAscension: 152, declination: 22),
                     radiantDriftRightAscension: 0.60, radiantDriftDeclination: -0.26, velocity: 71,
                     populationIndex: 2.5),
        MeteorShower(code: "HYD", iauNumber: 16, name: "σ-Hydrids", activityStartMonth: 12, activityStartDay: 3,
                     activityEndMonth: 12, activityEndDay: 20, peakSolarLongitude: 257, zhr: 7,
                     radiant: EquatorialCoordinate(rightAscension: 125, declination: 2),
                     radiantDriftRightAscension: 0.80, radiantDriftDeclination: -0.20, velocity: 58,
                     populationIndex: 3.0),
        MeteorShower(code: "GEM", iauNumber: 4, name: "Geminids", activityStartMonth: 12, activityStartDay: 4,
                     activityEndMonth: 12, activityEndDay: 20, peakSolarLongitude: 262.2, zhr: 150,
                     radiant: EquatorialCoordinate(rightAscension: 112, declination: 33),
                     radiantDriftRightAscension: 1.00, radiantDriftDeclination: -0.06, velocity: 35,
                     populationIndex: 2.6),
        MeteorShower(code: "URS", iauNumber: 15, name: "Ursids", activityStartMonth: 12, activityStartDay: 17,
                     activityEndMonth: 12, activityEndDay: 26, peakSolarLongitude: 270.7, zhr: 10,
                     radiant: EquatorialCoordinate(rightAscension: 217, declination: 76),
                     radiantDriftRightAscension: 0, radiantDriftDeclination: -0.40, velocity: 33,
                     populationIndex: 2.8),
    ]

    /// The shower with the IAU `code` (case-insensitive), or `nil`.
    public static func withCode(_ code: String) -> MeteorShower? {
        all.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }
}

/// The maximum of one shower in one year.
public struct MeteorShowerPeak: Sendable, Hashable {
    /// The shower.
    public let shower: MeteorShower
    /// The first instant of the activity period of this return (00:00 UT of the first day).
    public let activityStart: Date
    /// The last instant of the activity period (the end of the last day, UT).
    public let activityEnd: Date
    /// The illuminated fraction of the Moon at the maximum, [0, 1]; a bright Moon hides the fainter meteors.
    public let moonIlluminatedFraction: Double
    /// The radiant (J2000) at the maximum: aim at it with `AimTarget.radiant` or `MeteorShower.radiant(at:)` for
    /// another date.
    public let radiant: EquatorialCoordinate

    public init(shower: MeteorShower, activityStart: Date, activityEnd: Date, moonIlluminatedFraction: Double,
                radiant: EquatorialCoordinate) {
        self.shower = shower
        self.activityStart = activityStart
        self.activityEnd = activityEnd
        self.moonIlluminatedFraction = moonIlluminatedFraction
        self.radiant = radiant
    }
}

/// Finds the maxima of the `MeteorShower` list in an interval of time.
///
/// Cost: a few solar positions per shower and year.
public enum MeteorShowerFinder {
    /// The maxima from `from` to `to` (both inclusive), as events without visibility, in time order.
    public static func events(from: Date, to: Date) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let fromUT = EventSearch.ut(from)
        let toUT = EventSearch.ut(EventSearch.limitedEnd(from: from, to: to))
        var found = [AstronomicalEvent]()
        for shower in MeteorShower.all {
            var peak = shower.peakUT(near: fromUT)
            while peak < fromUT {
                peak = shower.peakUT(near: peak + EventSearch.tropicalYearDays)
            }
            while peak <= toUT {
                found.append(event(shower, peakUT: peak))
                peak = shower.peakUT(near: peak + EventSearch.tropicalYearDays)
            }
        }
        return EventSearch.sortedByDate(found)
    }

    private static func event(_ shower: MeteorShower, peakUT: Double) -> AstronomicalEvent {
        let jd = JulianDate(ut: peakUT)
        let interval = shower.activityInterval(peakUT: peakUT)
        let peak = MeteorShowerPeak(
            shower: shower,
            activityStart: EventSearch.instant(interval.first),
            activityEnd: EventSearch.instant(interval.last),
            moonIlluminatedFraction: Ephemeris.state(of: .moon, at: jd).illuminatedFraction ?? 0,
            radiant: shower.radiant)
        return AstronomicalEvent(date: jd.date, details: .meteorShower(peak), visibility: nil)
    }
}
