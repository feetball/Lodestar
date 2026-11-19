import Foundation

/// Writes the session log as CSV and as an OpenAstronomyLog 2.1 XML document.
///
/// Both writers take the first `SessionLogEntry.maximumEntries` entries in date order (entries with the same date keep their
/// order). Cost: linear in the number of entries.
public enum SessionLogCodec {
    /// The most entries written.
    public static let maximumEntries = 5_000

    // MARK: Nights

    /// The night of an instant as a day count since 1970-01-01: the local calendar day of the time twelve hours earlier, so
    /// that frames shot after midnight belong to the evening before, for a site `utcOffsetMinutes` east of UTC.
    public static func night(of date: Date, utcOffsetMinutes: Int) -> Int64 {
        InterchangeText.floorDivide(
            InterchangeText.wholeSeconds(of: date) + Int64(utcOffsetMinutes) * 60 - 43_200,
            86_400
        )
    }

    /// The date of a night as "2026-11-18".
    public static func nightText(_ night: Int64) -> String {
        InterchangeText.dateText(daysSinceEpoch: night)
    }

    /// The entries in date order, at most `maximumEntries`.
    static func ordered(_ entries: [SessionLogEntry]) -> [SessionLogEntry] {
        entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.date != rhs.element.date ? lhs.element.date < rhs.element.date : lhs.offset < rhs.offset
            }
            .prefix(maximumEntries)
            .map(\.element)
    }

    // MARK: CSV

    /// The log as CSV (RFC 4180, CRLF line breaks) with the columns `Date (UTC)`, `Night`, `Target`, `Target ID`,
    /// `RA J2000 (deg)`, `Dec J2000 (deg)`, `Site`, `Latitude`, `Longitude`, `Camera`, `Focal length (mm)`,
    /// `Aperture (f/)`, `Exposure (s)`, `ISO`, `Frames`, `Total exposure (s)`, `Filter`, `Imaged` (yes or no) and `Notes`.
    /// Unknown values are empty; text that a spreadsheet could run as a formula is guarded with an apostrophe.
    public static func encodeCSV(_ entries: [SessionLogEntry]) -> String {
        var rows: [[String]] = [[
            "Date (UTC)", "Night", "Target", "Target ID", "RA J2000 (deg)", "Dec J2000 (deg)", "Site", "Latitude",
            "Longitude", "Camera", "Focal length (mm)", "Aperture (f/)", "Exposure (s)", "ISO", "Frames",
            "Total exposure (s)", "Filter", "Imaged", "Notes",
        ]]
        for entry in ordered(entries) {
            rows.append([
                InterchangeText.dateTimeText(epochSeconds: InterchangeText.wholeSeconds(of: entry.date)),
                nightText(entry.night),
                InterchangeCSV.guarded(entry.targetName),
                InterchangeCSV.guarded(entry.targetID),
                entry.rightAscension.map { InterchangeText.fixed($0, decimals: 5) } ?? "",
                entry.declination.map { InterchangeText.fixed($0, decimals: 5) } ?? "",
                InterchangeCSV.guarded(entry.siteName),
                entry.siteLatitude.map { InterchangeText.decimal($0, maximumDecimals: 5) } ?? "",
                entry.siteLongitude.map { InterchangeText.decimal($0, maximumDecimals: 5) } ?? "",
                InterchangeCSV.guarded(entry.camera),
                entry.focalLength.map { InterchangeText.decimal($0, maximumDecimals: 1) } ?? "",
                entry.lensAperture.map { InterchangeText.decimal($0, maximumDecimals: 1) } ?? "",
                InterchangeText.decimal(entry.exposureSeconds, maximumDecimals: 3),
                entry.iso > 0 ? String(entry.iso) : "",
                String(entry.frameCount),
                InterchangeText.decimal(entry.totalExposureSeconds, maximumDecimals: 3),
                InterchangeCSV.guarded(entry.filter),
                entry.isImaged ? "yes" : "no",
                InterchangeCSV.guarded(entry.notes),
            ])
        }
        return InterchangeCSV.encode(rows)
    }
}
