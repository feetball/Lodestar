extension ObservingListCodec {
    private static let skySafariHeader = "skysafariobservinglistversion"

    /// Whether the first line that is not blank starts with `SkySafariObservingListVersion`, in any case.
    static func hasSkySafariHeader(_ scalars: [Unicode.Scalar]) -> Bool {
        var first = String.UnicodeScalarView()
        var started = false
        for scalar in scalars {
            if scalar == "\n" || scalar == "\r" {
                if started { break }
                continue
            }
            if !started && scalar.properties.isWhitespace { continue }
            started = true
            first.append(scalar)
            if first.count >= skySafariHeader.unicodeScalars.count { break }
        }
        return String(first).lowercased() == skySafariHeader
    }

    /// The lines of `scalars`, split at LF, CRLF and CR.
    private static func lines(of scalars: [Unicode.Scalar]) -> [String] {
        var result: [String] = []
        var current = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\n" || scalar == "\r" {
                if scalar == "\r" && index + 1 < scalars.count && scalars[index + 1] == "\n" { index += 1 }
                result.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
            index += 1
        }
        if !current.isEmpty { result.append(String(current)) }
        return result
    }

    /// One `SkyObject` block being read.
    private struct SkySafariObject {
        let line: Int
        var catalogNumbers: [String] = []
        var commonNames: [String] = []
    }

    /// Reads a SkySafari observing list. Keys other than `CatalogNumber` and `CommonName` are ignored, and so is everything
    /// outside the `SkyObject` blocks.
    static func decodeSkySafari(_ scalars: [Unicode.Scalar]) -> ObservingListImport {
        var targets: [ImportedTarget] = []
        var errors: [ObservingListRowError] = []
        var isTruncated = false
        var open: SkySafariObject?
        var objectCount = 0

        func close(_ object: SkySafariObject, isTerminated: Bool) {
            if !isTerminated { errors.append(ObservingListRowError(line: object.line, reason: .unterminatedObject)) }
            let designation = object.catalogNumbers.first
            let name = object.commonNames.first
            guard designation != nil || name != nil else {
                if isTerminated { errors.append(ObservingListRowError(line: object.line, reason: .missingName)) }
                return
            }
            let others = Array(object.catalogNumbers.dropFirst()) + Array(object.commonNames.dropFirst())
            targets.append(ImportedTarget(
                name: name,
                designation: designation,
                alternates: Array(others.prefix(maximumAlternates)),
                line: object.line
            ))
        }

        for (offset, rawLine) in lines(of: scalars).enumerated() {
            let lineNumber = offset + 1
            let line = InterchangeText.singleLine(rawLine, limit: 2_000)
            let view = line.unicodeScalars
            guard let separator = view.firstIndex(of: "=") else { continue }
            let key = InterchangeText.singleLine(String(view[view.startIndex..<separator]), limit: 200).lowercased()
            let value = InterchangeText.singleLine(String(view[view.index(after: separator)...]), limit: 2_000)
            if key == "skyobject" && value.lowercased() == "beginobject" {
                if let object = open { close(object, isTerminated: false) }
                if objectCount >= maximumTargets {
                    isTruncated = true
                    open = nil
                    break
                }
                objectCount += 1
                open = SkySafariObject(line: lineNumber)
            } else if key == "endobject" && value.lowercased() == "skyobject" {
                if let object = open { close(object, isTerminated: true) }
                open = nil
            } else if open != nil, !value.isEmpty {
                let text = InterchangeText.singleLine(value, limit: maximumNameScalars)
                if key == "catalognumber" {
                    open?.catalogNumbers.append(text)
                } else if key == "commonname" {
                    open?.commonNames.append(text)
                }
            }
        }
        if let object = open { close(object, isTerminated: false) }
        return ObservingListImport(format: .skySafari, targets: targets, errors: errors, isTruncated: isTruncated)
    }
}
