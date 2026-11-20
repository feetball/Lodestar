extension ObservingListCodec {
    /// Reads a CSV table whose header names the columns.
    static func decodeCSV(_ scalars: [Unicode.Scalar]) throws -> ObservingListImport {
        let table = try InterchangeCSV.parse(scalars, maximumRecords: maximumTargets + 1)
        guard let header = table.records.first else { throw InterchangeError.empty }
        guard let columns = ObservingListColumns(header: header.fields) else { throw InterchangeError.missingColumns }

        var targets: [ImportedTarget] = []
        var errors: [ObservingListRowError] = []
        for record in table.records.dropFirst() {
            // A row of empty cells says nothing.
            if record.fields.allSatisfy({ InterchangeText.singleLine($0, limit: 1).isEmpty }) { continue }

            func cell(_ index: Int?, limit: Int = maximumNameScalars) -> String {
                guard let index, index < record.fields.count else { return "" }
                return InterchangeText.singleLine(InterchangeCSV.unguarded(record.fields[index]), limit: limit)
            }
            let designation = cell(columns.designation)
            // Telescopius writes the custom name of a list entry in "Label"; it comes after the familiar name.
            let familiarName = cell(columns.name)
            let name = familiarName.isEmpty ? cell(columns.label) : familiarName
            let alternates = alternateNames(cell(columns.alternates, limit: 2_000))
            let raText = cell(columns.rightAscension, limit: AngleTextParser.maximumLength + 1)
            let decText = cell(columns.declination, limit: AngleTextParser.maximumLength + 1)

            var rightAscension: Double?
            var declination: Double?
            var hasCoordinateError = false
            if !raText.isEmpty || !decText.isEmpty {
                if raText.isEmpty || decText.isEmpty {
                    errors.append(ObservingListRowError(line: record.line, reason: .incompleteCoordinates))
                    hasCoordinateError = true
                } else {
                    let parsedRightAscension = ObservingListCoordinates.rightAscension(raText, unit: columns.rightAscensionUnit)
                    let parsedDeclination = ObservingListCoordinates.declination(decText)
                    if parsedRightAscension == nil {
                        errors.append(ObservingListRowError(line: record.line, reason: .invalidRightAscension))
                    }
                    if parsedDeclination == nil {
                        errors.append(ObservingListRowError(line: record.line, reason: .invalidDeclination))
                    }
                    hasCoordinateError = parsedRightAscension == nil || parsedDeclination == nil
                    if !hasCoordinateError {
                        rightAscension = parsedRightAscension
                        declination = parsedDeclination
                    }
                }
            }
            let isIdentified = !designation.isEmpty || !name.isEmpty || !alternates.isEmpty
            if !isIdentified && rightAscension == nil {
                if !hasCoordinateError { errors.append(ObservingListRowError(line: record.line, reason: .missingName)) }
                continue
            }
            targets.append(ImportedTarget(
                name: name.isEmpty ? nil : name,
                designation: designation.isEmpty ? nil : designation,
                alternates: alternates,
                rightAscension: rightAscension,
                declination: declination,
                line: record.line
            ))
        }
        let format: ObservingListFormat = columns.isTelescopius ? .telescopiusCSV : .genericCSV
        return ObservingListImport(format: format, targets: targets, errors: errors, isTruncated: table.isTruncated)
    }

    /// The names of a comma separated cell ("CL MELOTTE 22,H 0346+24"), without empty entries and repeats.
    private static func alternateNames(_ text: String) -> [String] {
        var result: [String] = []
        for part in text.split(separator: ",", omittingEmptySubsequences: true) {
            let name = InterchangeText.singleLine(String(part), limit: maximumNameScalars)
            if !name.isEmpty && !result.contains(name) { result.append(name) }
            if result.count >= maximumAlternates { break }
        }
        return result
    }
}
