import Foundation

/// A validated set of mean orbital elements for the SGP4/SDP4 propagator: one record of CelesTrak's GP data
/// (OMM keywords) or one classic two-line element set.
///
/// Units are those of the published formats: angles in degrees, the mean motion in revolutions per day, the
/// drag term in inverse Earth radii. Create values with `init(...)` or with `ElementSetParser`; both validate every
/// field, so an instance always holds finite values in the ranges listed below.
///
/// | Field | Accepted values |
/// |---|---|
/// | `catalogNumber` | 0 ... 999 999 999 |
/// | `classification` | `A` ... `Z` (`U`, `C`, `S` in practice) |
/// | `epoch` | years 1957 ... 2099 |
/// | `meanMotion` | greater than 0 and below 100 revolutions per day |
/// | `eccentricity` | 0 ... below 1 |
/// | `inclination` | 0 ... 180 |
/// | `rightAscensionOfAscendingNode`, `argumentOfPericenter`, `meanAnomaly` | 0 ... 360 |
/// | `bstar` | magnitude at most 10 |
/// | `meanMotionDot`, `meanMotionDdot` | magnitude at most 100 (SGP4 does not use them) |
/// | `ephemerisType` | 0 ... 9 |
/// | `elementSetNumber` | 0 ... 99 999 |
/// | `revolutionNumberAtEpoch` | 0 ... 9 999 999 |
///
/// Names and designators are informational: control characters are removed and the text is capped.
public struct OrbitalElements: Hashable, Sendable {
    /// The object name, e.g. "ISS (ZARYA)", if known (at most 80 characters).
    public let name: String?
    /// The international designator in CelesTrak's spelling ("1998-067A"), if known.
    public let objectId: String?
    /// The NORAD catalog number.
    public let catalogNumber: Int
    /// The security classification letter, normally `U`.
    public let classification: Character
    /// The epoch of the elements, UTC.
    public let epoch: Date
    /// Mean motion (Kozai mean, as published) in revolutions per day.
    public let meanMotion: Double
    /// Mean eccentricity.
    public let eccentricity: Double
    /// Mean inclination in degrees.
    public let inclination: Double
    /// Mean right ascension of the ascending node in degrees.
    public let rightAscensionOfAscendingNode: Double
    /// Mean argument of perigee in degrees.
    public let argumentOfPericenter: Double
    /// Mean anomaly in degrees.
    public let meanAnomaly: Double
    /// The ephemeris type digit (0 for SGP4/SDP4 elements).
    public let ephemerisType: Int
    /// The element set number.
    public let elementSetNumber: Int
    /// The revolution count at epoch.
    public let revolutionNumberAtEpoch: Int
    /// The SGP4 drag term B* in inverse Earth radii.
    public let bstar: Double
    /// First derivative of the mean motion divided by two, in revolutions per day squared.
    public let meanMotionDot: Double
    /// Second derivative of the mean motion divided by six, in revolutions per day cubed.
    public let meanMotionDdot: Double
    /// Julian Day (at 0h, so a half-integer) of the epoch's date, as the SGP4 reference computes it.
    let epochJulianDay: Double
    /// Fraction of the day of the epoch, as the SGP4 reference computes it.
    let epochJulianDayFraction: Double

    /// The longest accepted name, in characters.
    public static let maximumNameLength = 80
    /// The longest accepted international designator, in characters.
    public static let maximumObjectIdLength = 20
    /// Julian Day of 1949 December 31 00:00 UT, the zero of the SGP4 reference time scale.
    static let sgp4EpochOffset = 2_433_281.5
    /// Seconds from 1970-01-01T00:00:00Z to the Foundation reference date 2001-01-01T00:00:00Z.
    private static let referenceDateUnixSeconds: Int64 = 978_307_200

    /// The orbital period in minutes, `1440 / meanMotion`.
    public var periodMinutes: Double { 1_440.0 / meanMotion }

    /// The epoch in days since 1949 December 31 00:00 UT, the time scale of the SGP4 reference code.
    var sgp4EpochDays: Double { (epochJulianDay + epochJulianDayFraction) - Self.sgp4EpochOffset }

    /// The age of the element set at `date` in days: positive when `date` is after the epoch. SGP4's error grows
    /// by roughly 1 to 3 km per day for low orbits, so refresh stale sets (see the notes in the API document).
    public func ageDays(_ date: Date) -> Double { date.timeIntervalSince(epoch) / JulianDate.secondsPerDay }

    /// Validates the values and creates an element set.
    ///
    /// - Parameter epoch: The epoch (UTC), years 1957 ... 2099.
    /// - Throws: `ElementSetError.valueOutOfRange` if a number is not finite or outside its range;
    ///   `ElementSetError.invalidField` if the classification is not an upper-case letter.
    public init(
        name: String? = nil,
        objectId: String? = nil,
        catalogNumber: Int,
        classification: Character = "U",
        epoch: Date,
        meanMotion: Double,
        eccentricity: Double,
        inclination: Double,
        rightAscensionOfAscendingNode: Double,
        argumentOfPericenter: Double,
        meanAnomaly: Double,
        ephemerisType: Int = 0,
        elementSetNumber: Int = 0,
        revolutionNumberAtEpoch: Int = 0,
        bstar: Double = 0,
        meanMotionDot: Double = 0,
        meanMotionDdot: Double = 0
    ) throws {
        let seconds = epoch.timeIntervalSince1970
        guard seconds.isFinite else { throw ElementSetError.valueOutOfRange(field: "EPOCH", value: seconds) }
        var day = (seconds / JulianDate.secondsPerDay).rounded(.down)
        guard day > -1.0e7 && day < 1.0e7 else { throw ElementSetError.valueOutOfRange(field: "EPOCH", value: seconds) }
        var secondOfDay = seconds - day * JulianDate.secondsPerDay
        if secondOfDay < 0.0 {
            day -= 1.0
            secondOfDay += JulianDate.secondsPerDay
        } else if secondOfDay >= JulianDate.secondsPerDay {
            day += 1.0
            secondOfDay -= JulianDate.secondsPerDay
        }
        let civil = ElementCalendar.civilFromDays(Int64(day))
        let hour = (secondOfDay / 3_600.0).rounded(.down)
        let minute = ((secondOfDay - hour * 3_600.0) / 60.0).rounded(.down)
        let second = secondOfDay - hour * 3_600.0 - minute * 60.0
        self = try Self.make(
            name: name, objectId: objectId, catalogNumber: catalogNumber, classification: classification,
            year: civil.year, month: civil.month, day: civil.day, hour: Int(hour), minute: Int(minute), second: second,
            meanMotion: meanMotion, eccentricity: eccentricity, inclination: inclination,
            rightAscensionOfAscendingNode: rightAscensionOfAscendingNode, argumentOfPericenter: argumentOfPericenter,
            meanAnomaly: meanAnomaly, ephemerisType: ephemerisType, elementSetNumber: elementSetNumber,
            revolutionNumberAtEpoch: revolutionNumberAtEpoch, bstar: bstar, meanMotionDot: meanMotionDot,
            meanMotionDdot: meanMotionDdot
        )
    }

    private init(
        name: String?, objectId: String?, catalogNumber: Int, classification: Character, epoch: Date,
        meanMotion: Double, eccentricity: Double, inclination: Double, rightAscensionOfAscendingNode: Double,
        argumentOfPericenter: Double, meanAnomaly: Double, ephemerisType: Int, elementSetNumber: Int,
        revolutionNumberAtEpoch: Int, bstar: Double, meanMotionDot: Double, meanMotionDdot: Double,
        epochJulianDay: Double, epochJulianDayFraction: Double
    ) {
        self.name = name
        self.objectId = objectId
        self.catalogNumber = catalogNumber
        self.classification = classification
        self.epoch = epoch
        self.meanMotion = meanMotion
        self.eccentricity = eccentricity
        self.inclination = inclination
        self.rightAscensionOfAscendingNode = rightAscensionOfAscendingNode
        self.argumentOfPericenter = argumentOfPericenter
        self.meanAnomaly = meanAnomaly
        self.ephemerisType = ephemerisType
        self.elementSetNumber = elementSetNumber
        self.revolutionNumberAtEpoch = revolutionNumberAtEpoch
        self.bstar = bstar
        self.meanMotionDot = meanMotionDot
        self.meanMotionDdot = meanMotionDdot
        self.epochJulianDay = epochJulianDay
        self.epochJulianDayFraction = epochJulianDayFraction
    }

    /// Validates the values and creates an element set from the calendar components of the epoch. The parsers
    /// use this so the SGP4 epoch is computed exactly as the reference code does.
    static func make(
        name: String?,
        objectId: String?,
        catalogNumber: Int,
        classification: Character,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Double,
        meanMotion: Double,
        eccentricity: Double,
        inclination: Double,
        rightAscensionOfAscendingNode: Double,
        argumentOfPericenter: Double,
        meanAnomaly: Double,
        ephemerisType: Int,
        elementSetNumber: Int,
        revolutionNumberAtEpoch: Int,
        bstar: Double,
        meanMotionDot: Double,
        meanMotionDdot: Double
    ) throws -> OrbitalElements {
        guard year >= 1957 && year <= 2099 else { throw ElementSetError.valueOutOfRange(field: "EPOCH", value: Double(year)) }
        guard month >= 1 && month <= 12 else { throw ElementSetError.valueOutOfRange(field: "EPOCH", value: Double(month)) }
        guard day >= 1 && day <= ElementCalendar.daysInMonth(year: year, month: month) else {
            throw ElementSetError.valueOutOfRange(field: "EPOCH", value: Double(day))
        }
        guard hour >= 0 && hour <= 23 else { throw ElementSetError.valueOutOfRange(field: "EPOCH", value: Double(hour)) }
        guard minute >= 0 && minute <= 59 else { throw ElementSetError.valueOutOfRange(field: "EPOCH", value: Double(minute)) }
        guard second >= 0 && second < 60 else { throw ElementSetError.valueOutOfRange(field: "EPOCH", value: second) }
        guard catalogNumber >= 0 && catalogNumber <= 999_999_999 else {
            throw ElementSetError.valueOutOfRange(field: "NORAD_CAT_ID", value: Double(catalogNumber))
        }
        guard let letter = classification.asciiValue, letter >= 65 && letter <= 90 else {
            throw ElementSetError.invalidField(field: "CLASSIFICATION_TYPE", text: String(classification))
        }
        try checkRange("MEAN_MOTION", meanMotion, 0, 100, lowerOpen: true, upperOpen: true)
        try checkRange("ECCENTRICITY", eccentricity, 0, 1, lowerOpen: false, upperOpen: true)
        try checkRange("INCLINATION", inclination, 0, 180)
        try checkRange("RA_OF_ASC_NODE", rightAscensionOfAscendingNode, 0, 360)
        try checkRange("ARG_OF_PERICENTER", argumentOfPericenter, 0, 360)
        try checkRange("MEAN_ANOMALY", meanAnomaly, 0, 360)
        try checkRange("BSTAR", bstar, -10, 10)
        try checkRange("MEAN_MOTION_DOT", meanMotionDot, -100, 100)
        try checkRange("MEAN_MOTION_DDOT", meanMotionDdot, -100, 100)
        try checkRange("EPHEMERIS_TYPE", Double(ephemerisType), 0, 9)
        try checkRange("ELEMENT_SET_NO", Double(elementSetNumber), 0, 99_999)
        try checkRange("REV_AT_EPOCH", Double(revolutionNumberAtEpoch), 0, 9_999_999)

        let julian = ElementCalendar.julianDay(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        let unixSeconds = ElementCalendar.daysFromCivil(year: year, month: month, day: day) * 86_400
            + Int64(hour) * 3_600 + Int64(minute) * 60
        let epoch = Date(timeIntervalSinceReferenceDate: Double(unixSeconds - referenceDateUnixSeconds) + second)
        return OrbitalElements(
            name: cleanText(name, maximumLength: maximumNameLength),
            objectId: cleanText(objectId, maximumLength: maximumObjectIdLength),
            catalogNumber: catalogNumber,
            classification: classification,
            epoch: epoch,
            meanMotion: meanMotion,
            eccentricity: eccentricity,
            inclination: inclination,
            rightAscensionOfAscendingNode: rightAscensionOfAscendingNode,
            argumentOfPericenter: argumentOfPericenter,
            meanAnomaly: meanAnomaly,
            ephemerisType: ephemerisType,
            elementSetNumber: elementSetNumber,
            revolutionNumberAtEpoch: revolutionNumberAtEpoch,
            bstar: bstar,
            meanMotionDot: meanMotionDot,
            meanMotionDdot: meanMotionDdot,
            epochJulianDay: julian.day,
            epochJulianDayFraction: julian.fraction
        )
    }

    private static func checkRange(
        _ field: String, _ value: Double, _ lower: Double, _ upper: Double,
        lowerOpen: Bool = false, upperOpen: Bool = false
    ) throws {
        let inside = value.isFinite
            && (lowerOpen ? value > lower : value >= lower)
            && (upperOpen ? value < upper : value <= upper)
        if !inside { throw ElementSetError.valueOutOfRange(field: field, value: value) }
    }

    /// Removes control characters, trims, caps the length; `nil` when nothing is left.
    static func cleanText(_ text: String?, maximumLength: Int) -> String? {
        guard let text else { return nil }
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where scalar.value >= 32 && scalar.value != 127 {
            kept.append(scalar)
        }
        // Count UTF-16 units like Kotlin's `String.length` does.
        let trimmed = String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.utf16.count > maximumLength {
            let units = Array(trimmed.utf16.prefix(maximumLength))
            let cut = String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return cut
        }
        return trimmed
    }
}

/// A civil calendar date.
struct ElementCivilDate: Sendable {
    let year: Int
    let month: Int
    let day: Int
}

/// A Julian Day split as the SGP4 reference does: the day at 0h and the fraction of the day.
struct ElementJulianDay: Sendable {
    let day: Double
    let fraction: Double
}

/// Month, day and time of day found from a day of the year (the reference's `days2mdhms`).
struct ElementMonthDayTime: Sendable {
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Double
}

/// Calendar arithmetic for element epochs, written to reproduce the SGP4 reference code exactly.
enum ElementCalendar {
    /// `true` for leap years of the Gregorian calendar.
    static func isLeapYear(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    /// Days in `month` (1 ... 12) of `year`.
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
        let quotient = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? quotient - 1 : quotient
    }

    /// Days from 1970-01-01 to the given proleptic Gregorian date (Howard Hinnant's algorithm).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = floorDivide(y, 400)
        let yearOfEra = y - era * 400
        let shifted = Int64(month + (month > 2 ? -3 : 9))
        let dayOfYear = (153 * shifted + 2) / 5 + Int64(day) - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The civil date `days` days after 1970-01-01.
    static func civilFromDays(_ days: Int64) -> ElementCivilDate {
        let shifted = days + 719_468
        let era = floorDivide(shifted, 146_097)
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = Int(dayOfYear - (153 * monthIndex + 2) / 5 + 1)
        let month = Int(monthIndex < 10 ? monthIndex + 3 : monthIndex - 9)
        let year = Int(yearOfEra + era * 400 + (month <= 2 ? 1 : 0))
        return ElementCivilDate(year: year, month: month, day: day)
    }

    /// The reference's `jday_SGP4`: Julian Day at 0h and fraction of the day. Valid for 1901 ... 2099.
    static func julianDay(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Double) -> ElementJulianDay {
        var julian = 367.0 * Double(year)
            - ((7 * (Double(year) + ((Double(month + 9)) / 12.0).rounded(.down))) * 0.25).rounded(.down)
            + (Double(275 * month) / 9.0).rounded(.down)
            + Double(day) + 1_721_013.5
        var fraction = (second + Double(minute) * 60.0 + Double(hour) * 3_600.0) / 86_400.0
        if abs(fraction) > 1.0 {
            let whole = fraction.rounded(.down)
            julian += whole
            fraction -= whole
        }
        return ElementJulianDay(day: julian, fraction: fraction)
    }

    /// The reference's `days2mdhms_SGP4`: month, day and time of day from the day of the year (1.0 = Jan 1 0h).
    static func monthDayTime(year: Int, days: Double) -> ElementMonthDayTime {
        let monthLengths = [0, 31, year % 4 == 0 ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let dayOfYear = Int(days.rounded(.down))
        var index = 1
        var elapsed = 0
        while dayOfYear > elapsed + monthLengths[index] && index < 12 {
            elapsed += monthLengths[index]
            index += 1
        }
        let day = dayOfYear - elapsed
        var temp = (days - Double(dayOfYear)) * 24.0
        let hour = Int(temp.rounded(.down))
        temp = (temp - Double(hour)) * 60.0
        let minute = Int(temp.rounded(.down))
        let second = (temp - Double(minute)) * 60.0
        return ElementMonthDayTime(month: index, day: day, hour: hour, minute: minute, second: second)
    }
}
