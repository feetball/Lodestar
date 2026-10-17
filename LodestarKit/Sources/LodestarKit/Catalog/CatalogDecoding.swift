import Foundation

// Decoding and validation of the four bundled JSON files (see Tools/README.md for the schema).
//
// Each file is decoded leniently, record by record, so that one bad record cannot take the rest
// down; every record that does decode is then validated before it becomes a catalog object.

/// Decodes an array element, yielding `nil` instead of throwing when the element has the wrong shape.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// A record that failed validation, with the reason.
struct Rejection: Error {
    let reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}

// MARK: - File shapes

struct StarsFile: Decodable {
    let schema: Int?
    let stars: [Lossy<StarRecord>]
}

struct StarRecord: Decodable {
    let hip: Int?
    let hr: Int?
    let hd: Int?
    let hyg: Int?
    let n: String?
    let b: String?
    let f: Int?
    let c: String?
    let ra: Double?
    let de: Double?
    let pa: Double?
    let pd: Double?
    let m: Double?
    let ci: Double?
    let sp: String?
    let d: Double?
}

struct DeepSkyFile: Decodable {
    let schema: Int?
    let objects: [Lossy<DeepSkyRecord>]
}

struct DeepSkyRecord: Decodable {
    let id: String?
    let m: Int?
    let ngc: [Int]?
    let ic: [Int]?
    let names: [String]?
    let t: String?
    let ra: Double?
    let de: Double?
    let c: String?
    let vm: Double?
    let bm: Double?
    let maj: Double?
    let minorAxis: Double?
    let pa: Double?
    let h: String?
    let sb: Double?

    private enum CodingKeys: String, CodingKey {
        case id, m, ngc, ic, names, t, ra, de, c, vm, bm, maj, pa, h, sb
        case minorAxis = "min"
    }
}

struct ConstellationsFile: Decodable {
    let schema: Int?
    let constellations: [Lossy<ConstellationRecord>]
}

struct ConstellationRecord: Decodable {
    let abbr: String?
    let name: String?
    let genitive: String?
    let label: [Double]?
    let lines: [Lossy<[[Double]]>]?
}

struct MilkyWayFile: Decodable {
    let schema: Int?
    let levels: [Lossy<MilkyWayLevelRecord>]
}

struct MilkyWayLevelRecord: Decodable {
    let level: Int?
    let polygons: [Lossy<[[Double]]>]?
    let holes: [Lossy<[[Double]]>]?
}

// MARK: - Validated records

struct StarEntry {
    let hipparcos: Int?
    let harvard: Int?
    let henryDraper: Int?
    let hygRow: Int?
    let properName: String?
    let bayer: String?
    let flamsteed: Int?
    let constellation: String?
    let position: EquatorialCoordinate
    let properMotion: ProperMotion?
    let magnitude: Double
    let colorIndex: Double?
    let spectralType: String?
    let distanceParsecs: Double?
    /// The record's position in the file, to keep the order of equally bright stars.
    let sourceIndex: Int

    /// The catalog identifier: Hipparcos number, else Harvard Revised number, else HYG row.
    var objectID: String {
        if let hipparcos { return "star.hip\(hipparcos)" }
        if let harvard { return "star.hr\(harvard)" }
        return "star.hyg\(hygRow ?? 0)"
    }
}

struct DeepSkyEntry {
    let id: String
    let messier: Int?
    let ngc: [Int]
    let ic: [Int]
    let names: [String]
    let typeCode: String
    let position: EquatorialCoordinate
    let constellation: String?
    let visualMagnitude: Double?
    let blueMagnitude: Double?
    let majorAxis: Double?
    let minorAxis: Double?
    let positionAngle: Double?
    let hubbleType: String?
    let surfaceBrightness: Double?
}

struct ValidatedConstellation {
    let constellation: Constellation
    /// Positions in the record's `lines` of the polylines that were dropped.
    let rejectedLines: [Int]
}

struct ValidatedLevel {
    let level: MilkyWayOutline.Level
    /// The rings that were dropped, as "polygon 3" or "hole 0".
    let rejectedRings: [String]
}

// MARK: - Validation

enum CatalogValidation {
    static let magnitudeRange = -30.0...40.0
    static let maximumNameScalars = 80

    static func star(_ record: StarRecord, sourceIndex: Int) throws -> StarEntry {
        let hip = try catalogNumber(record.hip, "hip")
        let hr = try catalogNumber(record.hr, "hr")
        let hd = try catalogNumber(record.hd, "hd")
        let hyg = try catalogNumber(record.hyg, "hyg")
        guard hip != nil || hr != nil || hyg != nil else {
            throw Rejection("no hip, hr or hyg number")
        }
        guard let magnitude = record.m, magnitude.isFinite, magnitudeRange.contains(magnitude) else {
            throw Rejection("magnitude missing or out of range")
        }
        var flamsteed: Int?
        if let number = record.f {
            guard (1...999).contains(number) else { throw Rejection("Flamsteed number \(number) out of range") }
            flamsteed = number
        }
        var bayer: String?
        if let text = record.b {
            let cleaned = try cleanedText(text, field: "b", maximumScalars: 4)
            if let cleaned, cleaned.unicodeScalars.contains(where: { $0.properties.isWhitespace }) {
                throw Rejection("Bayer letter contains whitespace")
            }
            bayer = cleaned
        }
        return StarEntry(
            hipparcos: hip, harvard: hr, henryDraper: hd, hygRow: hyg,
            properName: try cleanedText(record.n, field: "n", maximumScalars: maximumNameScalars),
            bayer: bayer, flamsteed: flamsteed,
            constellation: try constellationAbbreviation(record.c),
            position: try position(ra: record.ra, dec: record.de),
            properMotion: try properMotion(ra: record.pa, dec: record.pd),
            magnitude: magnitude,
            colorIndex: try number(record.ci, "ci", in: -2...10),
            spectralType: try cleanedText(record.sp, field: "sp", maximumScalars: 24),
            distanceParsecs: try positiveNumber(record.d, "d", upTo: 1_000_000),
            sourceIndex: sourceIndex)
    }

    static func deepSkyObject(_ record: DeepSkyRecord) throws -> DeepSkyEntry {
        guard let rawID = record.id, let id = try cleanedText(rawID, field: "id", maximumScalars: 40),
              id.unicodeScalars.allSatisfy(isIdentifierScalar) else {
            throw Rejection("id missing or contains unusual characters")
        }
        guard let rawType = record.t, let typeCode = try cleanedText(rawType, field: "t", maximumScalars: 8) else {
            throw Rejection("\(id): type missing")
        }
        var messier: Int?
        if let number = record.m {
            guard (1...999).contains(number) else { throw Rejection("\(id): Messier number out of range") }
            messier = number
        }
        let major = try positiveNumber(record.maj, "maj", upTo: AngularSize.maximumArcminutes)
        let minor = try positiveNumber(record.minorAxis, "min", upTo: AngularSize.maximumArcminutes)
        if let major, let minor, minor > major {
            throw Rejection("\(id): minor axis longer than major axis")
        }
        if minor != nil, major == nil {
            throw Rejection("\(id): minor axis without major axis")
        }
        return DeepSkyEntry(
            id: id, messier: messier,
            ngc: try designationNumbers(record.ngc, "ngc"), ic: try designationNumbers(record.ic, "ic"),
            names: try commonNames(record.names), typeCode: typeCode,
            position: try position(ra: record.ra, dec: record.de),
            constellation: try constellationAbbreviation(record.c),
            visualMagnitude: try number(record.vm, "vm", in: magnitudeRange),
            blueMagnitude: try number(record.bm, "bm", in: magnitudeRange),
            majorAxis: major, minorAxis: minor,
            positionAngle: try number(record.pa, "pa", in: 0...360),
            hubbleType: try cleanedText(record.h, field: "h", maximumScalars: 16),
            surfaceBrightness: try positiveNumber(record.sb, "sb", upTo: 40))
    }

    static func constellation(_ record: ConstellationRecord) throws -> ValidatedConstellation {
        guard let abbreviation = try constellationAbbreviation(record.abbr) else {
            throw Rejection("abbreviation missing")
        }
        guard let name = try cleanedText(record.name, field: "name", maximumScalars: maximumNameScalars),
              let genitive = try cleanedText(record.genitive, field: "genitive", maximumScalars: maximumNameScalars) else {
            throw Rejection("\(abbreviation): name or genitive missing")
        }
        guard let label = record.label, label.count == 2,
              let labelPosition = try? position(ra: label[0], dec: label[1]) else {
            throw Rejection("\(abbreviation): label position missing or out of range")
        }
        var lines: [[EquatorialCoordinate]] = []
        var rejectedLines: [Int] = []
        for (index, element) in (record.lines ?? []).enumerated() {
            if let vertices = element.value, vertices.count >= 2, let polyline = try? coordinates(vertices) {
                lines.append(polyline)
            } else {
                rejectedLines.append(index)
            }
        }
        return ValidatedConstellation(
            constellation: Constellation(abbreviation: abbreviation, name: name, genitive: genitive,
                                         labelPosition: labelPosition, lines: lines),
            rejectedLines: rejectedLines)
    }

    static func milkyWayLevel(_ record: MilkyWayLevelRecord) throws -> ValidatedLevel {
        guard let level = record.level, (1...100).contains(level) else {
            throw Rejection("level number missing or out of range")
        }
        var rejectedRings: [String] = []
        func rings(_ elements: [Lossy<[[Double]]>]?, kind: String) -> [[EquatorialCoordinate]] {
            var result: [[EquatorialCoordinate]] = []
            for (index, element) in (elements ?? []).enumerated() {
                if let vertices = element.value, vertices.count >= 3, let ring = try? coordinates(vertices) {
                    result.append(ring)
                } else {
                    rejectedRings.append("\(kind) \(index)")
                }
            }
            return result
        }
        let polygons = rings(record.polygons, kind: "polygon")
        let holes = rings(record.holes, kind: "hole")
        guard !polygons.isEmpty || !holes.isEmpty else {
            throw Rejection("level \(level) has no valid rings")
        }
        return ValidatedLevel(level: MilkyWayOutline.Level(level: level, polygons: polygons, holes: holes),
                              rejectedRings: rejectedRings)
    }

    // MARK: Field helpers

    private static func position(ra: Double?, dec: Double?) throws -> EquatorialCoordinate {
        guard let ra, let dec, ra.isFinite, dec.isFinite, (0...360).contains(ra), (-90...90).contains(dec) else {
            throw Rejection("position missing or out of range")
        }
        return EquatorialCoordinate(rightAscension: ra, declination: dec)
    }

    private static func coordinates(_ vertices: [[Double]]) throws -> [EquatorialCoordinate] {
        try vertices.map { vertex in
            guard vertex.count == 2 else { throw Rejection("vertex is not a pair") }
            return try position(ra: vertex[0], dec: vertex[1])
        }
    }

    private static func properMotion(ra: Double?, dec: Double?) throws -> ProperMotion? {
        guard ra != nil || dec != nil else { return nil }
        let limit = 100_000.0
        let rightAscension = try number(ra, "pa", in: -limit...limit) ?? 0
        let declination = try number(dec, "pd", in: -limit...limit) ?? 0
        return ProperMotion(raMilliarcsecondsPerYear: rightAscension, decMilliarcsecondsPerYear: declination)
    }

    private static func catalogNumber(_ value: Int?, _ field: String) throws -> Int? {
        guard let value else { return nil }
        guard (1...99_999_999).contains(value) else { throw Rejection("\(field) \(value) out of range") }
        return value
    }

    private static func designationNumbers(_ values: [Int]?, _ field: String) throws -> [Int] {
        var result: [Int] = []
        for value in values ?? [] {
            guard (1...99_999).contains(value) else { throw Rejection("\(field) \(value) out of range") }
            if !result.contains(value) { result.append(value) }
        }
        return result
    }

    private static func commonNames(_ values: [String]?) throws -> [String] {
        var result: [String] = []
        for value in values ?? [] {
            guard let name = try cleanedText(value, field: "names", maximumScalars: maximumNameScalars) else { continue }
            if !result.contains(name) { result.append(name) }
        }
        return result
    }

    private static func number(_ value: Double?, _ field: String, in range: ClosedRange<Double>) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, range.contains(value) else { throw Rejection("\(field) \(value) out of range") }
        return value
    }

    private static func positiveNumber(_ value: Double?, _ field: String, upTo limit: Double) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, value > 0, value <= limit else { throw Rejection("\(field) \(value) out of range") }
        return value
    }

    /// The trimmed text, `nil` when absent or blank; throws for text that is too long or contains
    /// control characters.
    private static func cleanedText(_ value: String?, field: String, maximumScalars: Int) throws -> String? {
        guard let value else { return nil }
        // Bounds the cost of looking at absurdly long strings.
        guard value.utf8.count <= 8 * maximumScalars else { throw Rejection("\(field) is too long") }
        let scalars = value.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, scalars[start].properties.isWhitespace {
            start = scalars.index(after: start)
        }
        while start < end {
            let last = scalars.index(before: end)
            guard scalars[last].properties.isWhitespace else { break }
            end = last
        }
        guard start < end else { return nil }
        var count = 0
        for scalar in scalars[start..<end] {
            count += 1
            if scalar.properties.generalCategory == .control { throw Rejection("\(field) contains control characters") }
        }
        guard count <= maximumScalars else { throw Rejection("\(field) is too long") }
        return start == scalars.startIndex && end == scalars.endIndex ? value : String(scalars[start..<end])
    }

    /// An IAU-style abbreviation: two to four ASCII letters.
    private static func constellationAbbreviation(_ value: String?) throws -> String? {
        guard let text = try cleanedText(value, field: "constellation", maximumScalars: 4) else { return nil }
        guard text.unicodeScalars.count >= 2,
              text.unicodeScalars.allSatisfy({ ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A) }) else {
            throw Rejection("constellation abbreviation \(text) is malformed")
        }
        return text
    }

    private static func isIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x2B, 0x5F: true
        default: false
        }
    }
}
