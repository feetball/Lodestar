import Foundation

/// Reader for the answer of the JPL Small-Body Database API for one object
/// (https://ssd-api.jpl.nasa.gov/doc/sbdb.html), for example
/// `https://ssd-api.jpl.nasa.gov/sbdb.api?des=12P&phys-par=1&full-prec=1`.
///
/// Request `phys-par=1` to get the magnitude parameters (`M1`, `K1`, `M2`, `K2`, `PC` for comets, `H`, `G` for asteroids).
/// The reader uses `object.fullname` and `object.kind`, `orbit.epoch`, `orbit.equinox` (must be `J2000` if present),
/// `orbit.elements` (`e`, `q`, `i`, `om`, `w`, `tp`, with `a`, `ma` as fallbacks) and `phys_par`. Values may be
/// strings or numbers (the service writes strings); unknown members are ignored. The time of perihelion `tp` is a Julian
/// Day in TDB, which is taken as TT (they differ by less than 2 ms).
///
/// The answer is a small document (3–6 kB); texts above `maximumInputLength` characters or nested deeper than
/// `maximumNesting` are refused. The JSON grammar is strict (RFC 8259) and the same in Kotlin and Swift.
public enum SmallBodyJSONParser {
    /// The longest accepted input, 1 Mi characters.
    public static let maximumInputLength = 1_048_576

    /// The deepest accepted nesting of objects and arrays, 32.
    public static let maximumNesting = JSONReader.maximumNesting

    /// The slope K1 assumed for a comet that has M1 but no K1, 10.
    public static let defaultTotalSlope = CometMagnitudes.defaultTotalSlope

    /// Reads the answer for one object.
    ///
    /// - Throws: `SmallBodyParseError` if the text is not JSON of the expected shape, the service reports that the object
    ///   was not found (or not unique), the object is neither comet nor asteroid, or a required element is missing,
    ///   malformed or out of range.
    public static func parse(_ json: String) throws -> SmallBody {
        let length = json.utf16.count
        guard length <= maximumInputLength else {
            throw SmallBodyParseError.inputTooLarge(length: length, maximum: maximumInputLength)
        }
        let root: JSONValue
        do {
            var reader = JSONReader(json)
            root = try reader.readDocument()
        } catch let error as JSONReaderError {
            throw SmallBodyParseError.invalidJSON(reason: error.failure == .tooDeep ? "nested too deeply" : "the text is not valid JSON")
        }
        guard case .object(let document) = root else {
            throw SmallBodyParseError.invalidJSON(reason: "the top level is not an object")
        }
        guard case .object(let object)? = document["object"] else {
            throw SmallBodyParseError.unsupportedObject(reason: text(document["message"]) ?? "the answer contains no object")
        }
        guard case .object(let orbitObject)? = document["orbit"] else {
            throw SmallBodyParseError.unsupportedObject(reason: "the answer contains no orbit")
        }

        // Kind and names.
        guard let kindText = text(object["kind"]) else {
            throw SmallBodyParseError.unsupportedObject(reason: "the object has no kind")
        }
        let kind: SmallBodyKind
        switch kindText.unicodeScalars.first {
        case "c"?: kind = .comet
        case "a"?: kind = .asteroid
        default:
            throw SmallBodyParseError.unsupportedObject(
                reason: "the object kind \"\(RecordFields.excerpt(kindText))\" is not a comet or asteroid")
        }
        let fullName = trimmed(text(object["fullname"]) ?? "")
        if fullName.isEmpty { throw SmallBodyParseError.missingField(.designation) }
        let designation: String
        let name: String
        let number: Int?
        if kind == .comet {
            let parts = SmallBodyNaming.cometParts(fullName)
            designation = parts.designation
            name = parts.name
            number = SmallBodyNaming.cometNumber(designation)
        } else {
            let identity = SmallBodyNaming.asteroidFullName(fullName)
            designation = identity.designation
            name = identity.name
            number = identity.number
        }

        // Orbit.
        if let equinox = text(orbitObject["equinox"]), equinox != "J2000" {
            throw SmallBodyParseError.unsupportedObject(reason: "the elements refer to the equinox \(RecordFields.excerpt(equinox))")
        }
        guard case .array(let elementArray)? = orbitObject["elements"] else {
            throw SmallBodyParseError.unsupportedObject(reason: "the orbit has no elements")
        }
        let elements = namedValues(elementArray)
        guard let eccentricity = try numericValue(elements["e"], .eccentricity, 0.0, OrbitalElements.maximumEccentricity) else {
            throw SmallBodyParseError.missingField(.eccentricity)
        }
        guard let inclination = try numericValue(elements["i"], .inclination, 0.0, 180.0) else {
            throw SmallBodyParseError.missingField(.inclination)
        }
        guard let node = try numericValue(elements["om"], .longitudeOfAscendingNode, 0.0, 360.0) else {
            throw SmallBodyParseError.missingField(.longitudeOfAscendingNode)
        }
        guard let argument = try numericValue(elements["w"], .argumentOfPerihelion, 0.0, 360.0) else {
            throw SmallBodyParseError.missingField(.argumentOfPerihelion)
        }
        let epoch = try numericValue(orbitObject["epoch"], .epoch, OrbitalElements.minimumJulianDay, OrbitalElements.maximumJulianDay)
        let semiMajorAxis = try numericValue(elements["a"], .semiMajorAxis, -1e12, 1e12)
        let perihelionDistance = try numericValue(elements["q"], .perihelionDistance, 0.0, OrbitalElements.maximumPerihelionDistanceAU)
        let perihelionTime = try numericValue(elements["tp"], .perihelionTime, OrbitalElements.minimumJulianDay, OrbitalElements.maximumJulianDay)
        let orbit: OrbitalElements
        if let perihelionTime {
            var q = perihelionDistance
            if q == nil, let semiMajorAxis, eccentricity < 1, semiMajorAxis > 0 { q = semiMajorAxis * (1 - eccentricity) }
            guard let q else { throw SmallBodyParseError.missingField(.perihelionDistance) }
            guard let made = OrbitalElements(
                perihelionDistanceAU: q, eccentricity: eccentricity, inclination: inclination, argumentOfPerihelion: argument,
                longitudeOfAscendingNode: node, perihelionJulianDayTT: perihelionTime, epochJulianDayTT: epoch) else {
                throw SmallBodyParseError.inconsistentElements(reason: "the elements do not describe an orbit")
            }
            orbit = made
        } else {
            guard let anomaly = try numericValue(elements["ma"], .meanAnomaly, -1e9, 1e9) else {
                throw SmallBodyParseError.missingField(.perihelionTime)
            }
            var axis = semiMajorAxis
            if axis == nil, let perihelionDistance, eccentricity < 1 { axis = perihelionDistance / (1 - eccentricity) }
            guard let a = axis else { throw SmallBodyParseError.missingField(.semiMajorAxis) }
            guard let epoch else { throw SmallBodyParseError.missingField(.epoch) }
            guard let made = OrbitalElements.fromMeanAnomaly(
                semiMajorAxisAU: a, eccentricity: eccentricity, inclination: inclination, argumentOfPerihelion: argument,
                longitudeOfAscendingNode: node, meanAnomaly: anomaly, epochJulianDayTT: epoch) else {
                throw SmallBodyParseError.inconsistentElements(reason: "the elements do not describe an elliptic orbit")
            }
            orbit = made
        }

        // Brightness.
        var parameterArray = [JSONValue]()
        if case .array(let items)? = document["phys_par"] { parameterArray = items }
        let parameters = namedValues(parameterArray)
        let totalMagnitude = try numericValue(parameters["M1"], .absoluteMagnitude, -20.0, 40.0)
        let totalSlope = try numericValue(parameters["K1"], .slopeParameter, -5.0, 60.0)
        let nuclearMagnitude = try numericValue(parameters["M2"], .nuclearMagnitude, -20.0, 40.0)
        let nuclearSlope = try numericValue(parameters["K2"], .nuclearMagnitude, -5.0, 60.0)
        let phaseCoefficient = try numericValue(parameters["PC"], .nuclearMagnitude, -0.1, 0.5)
        let absoluteMagnitude = try numericValue(parameters["H"], .absoluteMagnitude, -5.0, 40.0)
        let slope = try numericValue(parameters["G"], .slopeParameter, -0.25, 1.0)
        var cometModel: SmallBodyPhotometry?
        if let totalMagnitude,
           let magnitudes = CometMagnitudes(totalMagnitude: totalMagnitude, totalSlope: totalSlope ?? defaultTotalSlope,
                                            nuclearMagnitude: nuclearMagnitude, nuclearSlope: nuclearSlope,
                                            nuclearPhaseCoefficient: phaseCoefficient ?? 0.0) {
            cometModel = .comet(magnitudes)
        }
        var asteroidModel: SmallBodyPhotometry?
        if let absoluteMagnitude,
           let magnitudes = AsteroidMagnitudes(absoluteMagnitude: absoluteMagnitude,
                                               slopeParameter: slope ?? AsteroidMagnitudes.defaultSlopeParameter) {
            asteroidModel = .asteroid(magnitudes)
        }
        let photometry = kind == .comet ? (cometModel ?? asteroidModel) : (asteroidModel ?? cometModel)

        guard let body = SmallBody(designation: designation, name: name, kind: kind, number: number, orbit: orbit,
                                   photometry: photometry) else {
            throw SmallBodyParseError.invalidDesignation(text: RecordFields.excerpt(fullName))
        }
        return body
    }

    /// The `value` of every `{"name": ..., "value": ...}` entry of `array` by name (the last of a repeated name wins).
    private static func namedValues(_ array: [JSONValue]) -> [String: JSONValue] {
        var values = [String: JSONValue]()
        for item in array {
            guard case .object(let entry) = item, let key = text(entry["name"]) else { continue }
            values[key] = entry["value"] ?? .null
        }
        return values
    }

    /// The text of a JSON string; `nil` for anything else.
    private static func text(_ value: JSONValue?) -> String? {
        if case .string(let string)? = value { return string }
        return nil
    }

    /// `text` without surrounding spaces and tabs.
    private static func trimmed(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)[...]
        while let first = scalars.first, first.value == 0x20 || first.value == 0x09 { scalars = scalars.dropFirst() }
        while let last = scalars.last, last.value == 0x20 || last.value == 0x09 { scalars = scalars.dropLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// The number in a JSON string or number within `minimum...maximum`; `nil` when the value is absent or `null`.
    ///
    /// - Throws: `malformedField` if the value is not a plain decimal (or is a boolean, array or object),
    ///   `fieldOutOfRange` if it is outside the range.
    private static func numericValue(_ value: JSONValue?, _ field: SmallBodyField, _ minimum: Double, _ maximum: Double) throws -> Double? {
        let result: Double
        switch value {
        case nil, .null?:
            return nil
        case .number(let number)?:
            result = number
        case .string(let string)?:
            guard let parsed = RecordFields.decimal(trimmed(string), allowExponent: true) else {
                throw SmallBodyParseError.malformedField(field, text: RecordFields.excerpt(string))
            }
            result = parsed
        case .bool(let flag)?:
            throw SmallBodyParseError.malformedField(field, text: flag ? "true" : "false")
        case .array?:
            throw SmallBodyParseError.malformedField(field, text: "array")
        case .object?:
            throw SmallBodyParseError.malformedField(field, text: "object")
        }
        if result < minimum || result > maximum { throw SmallBodyParseError.fieldOutOfRange(field, value: result) }
        return result
    }
}
