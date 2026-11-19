/// One record of a CSV table.
struct CsvRecord: Hashable, Sendable {
    /// The line the record starts on, from 1 (a quoted field may span lines).
    let line: Int
    /// The fields in order.
    let fields: [String]
}

/// The records of a CSV table.
struct CsvTable: Sendable {
    /// The records, the header first, without the empty lines.
    let records: [CsvRecord]
    /// `true` when more records followed the `InterchangeCSV.parse` limit.
    let isTruncated: Bool
    /// The delimiter that was used.
    let delimiter: Unicode.Scalar
}

/// A reader and writer for comma separated values after RFC 4180 (https://www.rfc-editor.org/rfc/rfc4180): fields may
/// be quoted, a doubled quotation mark inside a quoted field is one quotation mark, and a quoted field may contain
/// delimiters and line breaks.
///
/// The reader is lenient where exporters are sloppy: it accepts CRLF, LF and CR line breaks, a byte order mark, a
/// semicolon or tab as the delimiter, a quotation mark inside an unquoted field (kept as it is) and text after a
/// closing quotation mark (appended). It never traps; the only error is a quoted field that is never closed.
enum InterchangeCSV {
    private static let quote: Unicode.Scalar = "\""
    private static let byteOrderMark: Unicode.Scalar = "\u{FEFF}"

    /// The delimiters `detectDelimiter(_:)` chooses between, the comma first.
    private static let delimiters: [Unicode.Scalar] = [",", ";", "\t"]

    /// The delimiter of a table: the one of comma, semicolon and tab that occurs most often outside quotation marks in the
    /// first line, the comma on a tie or when none occurs.
    static func detectDelimiter(_ scalars: [Unicode.Scalar]) -> Unicode.Scalar {
        var counts = [Int](repeating: 0, count: delimiters.count)
        var inQuotes = false
        for scalar in scalars {
            if scalar == quote {
                inQuotes.toggle()
            } else if !inQuotes {
                if scalar == "\n" || scalar == "\r" { break }
                if let index = delimiters.firstIndex(of: scalar) { counts[index] += 1 }
            }
        }
        var best = 0
        for index in 1..<delimiters.count where counts[index] > counts[best] {
            best = index
        }
        return delimiters[best]
    }

    /// Reads the records of `scalars` (the delimiter is detected).
    ///
    /// Empty lines are skipped. After `maximumRecords` records (the header counts) the rest is left unread and the table
    /// is marked truncated.
    ///
    /// - Throws: `InterchangeError.unterminatedQuote` when a quoted field is not closed before the end of the text.
    static func parse(_ scalars: [Unicode.Scalar], maximumRecords: Int) throws -> CsvTable {
        let delimiter = detectDelimiter(scalars)
        var records: [CsvRecord] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var line = 1
        var recordLine = 1
        var isQuoted = false
        var hasContent = false
        var isTruncated = false
        var index = scalars.first == byteOrderMark ? 1 : 0
        let count = scalars.count

        func finishField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
        }

        func finishRecord() {
            finishField()
            let isEmpty = fields.count == 1 && fields[0].isEmpty && !hasContent
            if !isEmpty { records.append(CsvRecord(line: recordLine, fields: fields)) }
            fields = []
            hasContent = false
        }

        while index < count {
            let scalar = scalars[index]
            // Reaching the limit always happens between records, so any further text that is not a line break is a record.
            if records.count >= maximumRecords && scalar != "\n" && scalar != "\r" {
                isTruncated = true
                break
            }
            if isQuoted {
                if scalar == quote {
                    if index + 1 < count && scalars[index + 1] == quote {
                        field.append(quote)
                        index += 1
                    } else {
                        isQuoted = false
                    }
                } else {
                    if scalar == "\n" { line += 1 }
                    field.append(scalar)
                }
            } else if scalar == quote && field.isEmpty {
                isQuoted = true
                hasContent = true
            } else if scalar == delimiter {
                finishField()
                hasContent = true
            } else if scalar == "\n" || scalar == "\r" {
                if scalar == "\r" && index + 1 < count && scalars[index + 1] == "\n" { index += 1 }
                finishRecord()
                line += 1
                recordLine = line
            } else {
                field.append(scalar)
                hasContent = true
            }
            index += 1
        }
        if isQuoted { throw InterchangeError.unterminatedQuote(line: recordLine) }
        if !isTruncated && (!field.isEmpty || !fields.isEmpty || hasContent) { finishRecord() }
        return CsvTable(records: records, isTruncated: isTruncated, delimiter: delimiter)
    }

    /// One field as CSV text: quoted when it has a delimiter, a quotation mark or a line break, with quotation marks doubled.
    static func field(_ value: String) -> String {
        let needsQuotes = value.unicodeScalars.contains { $0 == "," || $0 == quote || $0 == "\n" || $0 == "\r" }
        guard needsQuotes else { return value }
        var result = String.UnicodeScalarView()
        result.append(quote)
        for scalar in value.unicodeScalars {
            if scalar == quote { result.append(quote) }
            result.append(scalar)
        }
        result.append(quote)
        return String(result)
    }

    /// The rows as CSV text with CRLF line breaks, the last row ended too (RFC 4180 section 2).
    static func encode(_ rows: [[String]]) -> String {
        var result = ""
        for row in rows {
            result += row.map(field).joined(separator: ",")
            result += "\r\n"
        }
        return result
    }

    private static func startsFormula(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "=" || scalar == "+" || scalar == "-" || scalar == "@" || scalar == "\t" || scalar == "\r"
    }

    /// `value` made safe to open in a spreadsheet: text that starts with `=`, `+`, `-`, `@`, a tab or a carriage return
    /// would be run as a formula, so it gets a leading apostrophe (OWASP "CSV injection"). `unguarded(_:)` undoes it.
    static func guarded(_ value: String) -> String {
        guard let first = value.unicodeScalars.first, startsFormula(first) else { return value }
        return "'" + value
    }

    /// `value` without the apostrophe `guarded(_:)` put in front of a formula character.
    static func unguarded(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count >= 2, scalars[0] == "'", startsFormula(scalars[1]) else { return value }
        return String(String.UnicodeScalarView(scalars.dropFirst()))
    }
}
