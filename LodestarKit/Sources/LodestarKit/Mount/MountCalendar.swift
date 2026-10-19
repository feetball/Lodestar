import Foundation

/// A UTC calendar date and time of day.
public struct MountDateTime: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let second: Int
    public let millisecond: Int

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, millisecond: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.millisecond = millisecond
    }

    /// A copy with the year replaced (the Kotlin `copy(year = …)`).
    func withYear(_ year: Int) -> MountDateTime {
        MountDateTime(year: year, month: month, day: day, hour: hour, minute: minute, second: second, millisecond: millisecond)
    }
}

/// Calendar arithmetic in UTC, identical in both languages (civil-from-days of H. Hinnant, no time zone database).
enum MountCalendar {
    /// The UTC fields of `date`, or nil if the date is outside the years 1970 to 9999.
    static func fields(for date: Date) -> MountDateTime? {
        let total = date.timeIntervalSince1970
        guard total.isFinite, total >= 0, total <= 253_402_300_799.0 else { return nil }
        let whole = total.rounded(.down)
        let seconds = Int(whole)
        let millisecond = min(max(Int((total - whole) * 1000), 0), 999)
        let days = seconds / 86_400
        let secondOfDay = seconds % 86_400
        let z = days + 719_468
        let era = z / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return MountDateTime(year: year, month: month, day: day, hour: secondOfDay / 3600, minute: secondOfDay % 3600 / 60,
                             second: secondOfDay % 60, millisecond: millisecond)
    }

    static func twoDigits(_ value: Int) -> String { value >= 0 && value <= 9 ? "0\(value)" : "\(value)" }

    static func threeDigits(_ value: Int) -> String {
        if value >= 0 && value <= 9 { return "00\(value)" }
        if value >= 10 && value <= 99 { return "0\(value)" }
        return "\(value)"
    }
}
