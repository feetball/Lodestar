import Foundation

/// Line-by-line leniency shared by the batch parsers.
enum SmallBodyBatch {
    /// The longest text a batch parser accepts, 64 Mi characters (a full `NEA.txt` is under 9 Mi).
    static let maximumInputLength = 64 * 1024 * 1024

    /// How many leading lines are searched for the dashed line that ends an MPCORB header.
    static let maximumHeaderLines = 200

    /// The shortest run of dashes that counts as the end of a header.
    static let minimumHeaderRule = 20

    /// Parses every line of `text` with `parseLine` and collects the results. Blank lines are ignored; a line that
    /// `parseLine` rejects is counted and the first few are reported; a second occurrence of an identifier is
    /// rejected as a duplicate. With `skipHeader`, everything up to a line of at least `minimumHeaderRule` dashes in
    /// the first `maximumHeaderLines` lines is ignored.
    ///
    /// - Throws: `SmallBodyParseError.inputTooLarge` if `text` is longer than `maximumInputLength`.
    static func parse(_ text: String, skipHeader: Bool, parseLine: (String) throws -> SmallBody) throws -> SmallBodyParseResult {
        let length = text.utf16.count
        guard length <= maximumInputLength else {
            throw SmallBodyParseError.inputTooLarge(length: length, maximum: maximumInputLength)
        }
        let bytes = Array(text.utf8)
        let firstDataLine = skipHeader ? lineAfterHeader(bytes) : 1
        var bodies = [SmallBody]()
        var seen = Set<String>()
        var rejections = [SmallBodyLineRejection]()
        var rejected = 0
        var lineNumber = 0
        var start = 0
        while start <= bytes.count {
            var end = start
            while end < bytes.count && bytes[end] != 0x0A { end += 1 }
            lineNumber += 1
            if lineNumber >= firstDataLine {
                var lineEnd = end
                if lineEnd > start && bytes[lineEnd - 1] == 0x0D { lineEnd -= 1 }
                if !isBlank(bytes[start..<lineEnd]) {
                    let line = String(decoding: bytes[start..<lineEnd], as: UTF8.self)
                    var failure: SmallBodyParseError?
                    do {
                        let body = try parseLine(line)
                        if seen.insert(body.id).inserted {
                            bodies.append(body)
                        } else {
                            failure = SmallBodyParseError.duplicateObject(id: body.id)
                        }
                    } catch let error as SmallBodyParseError {
                        failure = error
                    }
                    if let failure {
                        rejected += 1
                        if rejections.count < SmallBodyParseResult.maximumReportedRejections {
                            rejections.append(SmallBodyLineRejection(lineNumber: lineNumber, error: failure))
                        }
                    }
                }
            }
            start = end + 1
        }
        return SmallBodyParseResult(bodies: bodies, rejectedLineCount: rejected, rejections: rejections)
    }

    private static func isBlank(_ line: ArraySlice<UInt8>) -> Bool {
        for byte in line where byte != 0x20 && byte != 0x09 { return false }
        return true
    }

    /// The 1-based number of the first line after an MPCORB header, or 1 if the text has none.
    private static func lineAfterHeader(_ bytes: [UInt8]) -> Int {
        var lineNumber = 0
        var start = 0
        while start <= bytes.count && lineNumber < maximumHeaderLines {
            var end = start
            while end < bytes.count && bytes[end] != 0x0A { end += 1 }
            lineNumber += 1
            var lineEnd = end
            if lineEnd > start && bytes[lineEnd - 1] == 0x0D { lineEnd -= 1 }
            if lineEnd - start >= minimumHeaderRule {
                var onlyDashes = true
                for index in start..<lineEnd where bytes[index] != 0x2D {
                    onlyDashes = false
                    break
                }
                if onlyDashes { return lineNumber + 1 }
            }
            start = end + 1
        }
        return 1
    }
}
