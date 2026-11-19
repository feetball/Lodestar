/// Reads and writes observing lists: CSV tables (generic and Telescopius) and SkySafari observing lists.
///
/// ## Formats
///
/// - **Generic CSV** (RFC 4180, comma, semicolon or tab separated, header row). Header names are matched without case and
///   punctuation: a designation column ("designation", "catalogue entry", "catalog number", "object", "id"), a name
///   column ("name", "familiar name", "common name", "target") and optionally "ra" or "right ascension" and "dec" or
///   "declination". A coordinate is decimal degrees, or sexagesimal text such as `05h 35m 17.3s`, `05:35:17` or
///   `-05° 23′ 28″`; a plain number in a right ascension column is degrees unless the header says hours ("RA (hours)").
/// - **Telescopius CSV**, as the "download as CSV" of a Telescopius target list writes it: columns "Catalogue Entry"
///   (`M 45`), "Familiar Name" (`Pleiades`), "Alternative Entries" (a comma separated list inside quotation marks),
///   "Right Ascension (j2000)" and "Declination (j2000)" (`03h 46' 24"`, `24º 06' 50"`), plus jNow columns, which are
///   ignored, and a "Label". Exports before the epoch columns existed call them "Right Ascension" and "Declination".
/// - **SkySafari observing list** (`.skylist`, plain text): a first line `SkySafariObservingListVersion=3.0`, then for each
///   object a block `SkyObject=BeginObject`, lines `Key=value` (`ObjectID`, `CommonName`, `CatalogNumber`, `DefaultIndex`,
///   the keys may be indented with tabs) and `EndObject=SkyObject`. Only `CommonName` and `CatalogNumber` are used.
///   SkySafari lists have no coordinates; objects are found by their catalogue numbers.
///
/// Sources of the formats: Telescopius export header and row as quoted from a real export in the Telescopius forum
/// (https://forum.telescopius.com/t/csv-file-download-issues/1865), SkySafari lists as published by RASC
/// (https://rasc.ca/sites/default/files/RASC%20Finest%20NGC%20-%20Summer%20%28v2%29.skylist.txt) and in the SkySafari
/// 6/7 example of https://github.com/Stellarium/stellarium/discussions/2308, and the generator
/// https://github.com/miguelvb/wds_catalog.
///
/// ## Limits
///
/// Files are limited to `maximumTextScalars` characters and `maximumTargets` rows; names are cut to 120 characters.
/// Reading is linear in the size of the file.
public enum ObservingListCodec {
    /// The most rows read from, and written to, a list.
    public static let maximumTargets = 5_000

    /// The longest text that is read, in Unicode scalars.
    public static let maximumTextScalars = 4_000_000

    /// The longest name or designation kept, in Unicode scalars.
    static let maximumNameScalars = 120

    /// The most alternate names kept for a row.
    static let maximumAlternates = 20

    // MARK: Reading

    /// Reads a list, finding out its format from the content.
    ///
    /// - Throws: `InterchangeError` when the file is empty, too large, has an unclosed quotation mark or (CSV) has no usable
    ///   column. Problems with single rows are in the result's `errors`.
    public static func decode(_ text: String) throws -> ObservingListImport {
        var scalars = Array(text.unicodeScalars)
        guard scalars.count <= maximumTextScalars else {
            throw InterchangeError.tooLarge(maximumScalars: maximumTextScalars)
        }
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        guard scalars.contains(where: { !$0.properties.isWhitespace }) else { throw InterchangeError.empty }
        if hasSkySafariHeader(scalars) { return decodeSkySafari(scalars) }
        return try decodeCSV(scalars)
    }

    // MARK: Writing

    /// A list as CSV: `Name,Designation,RA J2000 (deg),Dec J2000 (deg),Type`, one row per entry (the first
    /// `maximumTargets`), coordinates in decimal degrees with five places, text that a spreadsheet could run as a formula
    /// guarded with an apostrophe.
    public static func encodeCSV(_ entries: [ObservingListEntry]) -> String {
        var rows: [[String]] = [["Name", "Designation", "RA J2000 (deg)", "Dec J2000 (deg)", "Type"]]
        for entry in entries.prefix(maximumTargets) {
            let hasPosition = entry.rightAscension.map { $0.isFinite && $0 >= 0 && $0 < 360 } == true
                && entry.declination.map { $0.isFinite && abs($0) <= 90 } == true
            rows.append([
                InterchangeCSV.guarded(InterchangeText.singleLine(entry.name, limit: maximumNameScalars)),
                InterchangeCSV.guarded(InterchangeText.singleLine(entry.designation ?? "", limit: maximumNameScalars)),
                hasPosition ? InterchangeText.fixed(entry.rightAscension ?? 0, decimals: 5) : "",
                hasPosition ? InterchangeText.fixed(entry.declination ?? 0, decimals: 5) : "",
                InterchangeCSV.guarded(InterchangeText.singleLine(entry.typeName ?? "", limit: maximumNameScalars)),
            ])
        }
        return InterchangeCSV.encode(rows)
    }

    /// A list as a SkySafari observing list: version header, `SortedBy=Default Order`, and per entry (the first
    /// `maximumTargets`) one `SkyObject` block with `ObjectID=2,-1,-1` (the value that generators of lists use, SkySafari
    /// looks the object up), the designation as `CatalogNumber` or, without one, the name as `CommonName`, and
    /// `DefaultIndex`. Lines end with LF and keys are indented with a tab, as SkySafari writes them.
    ///
    /// SkySafari only imports objects it knows, and an object must match every `CatalogNumber` and `CommonName` of its
    /// block, so only one identifier is written. Targets that are only a place in the sky (custom targets) are written by
    /// name and are not found by SkySafari.
    public static func encodeSkySafari(_ entries: [ObservingListEntry]) -> String {
        var lines = ["SkySafariObservingListVersion=3.0", "SortedBy=Default Order"]
        for (index, entry) in entries.prefix(maximumTargets).enumerated() {
            let designation = InterchangeText.singleLine(entry.designation ?? "", limit: maximumNameScalars)
            let name = InterchangeText.singleLine(entry.name, limit: maximumNameScalars)
            lines.append("SkyObject=BeginObject")
            lines.append("\tObjectID=2,-1,-1")
            if !designation.isEmpty {
                lines.append("\tCatalogNumber=\(designation)")
            } else if !name.isEmpty {
                lines.append("\tCommonName=\(name)")
            }
            lines.append("\tDefaultIndex=\(index)")
            lines.append("EndObject=SkyObject")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
