import XCTest
@testable import LodestarKit

/// Shared fixtures and helpers of the satellite tests (Kotlin: `SatelliteTestSupport.kt`).
enum SatelliteTestSupport {
    struct MissingFixture: Error, CustomStringConvertible {
        let name: String
        var description: String { "Fixture \(name) is missing from the test bundle's Fixtures directory" }
    }

    /// The ISS element set of the CelesTrak snapshot of 2026-10-18 (`satellite_stations.tle`).
    static let issLine1 = "1 25544U 98067A   26291.14461894  .00007503  00000+0  14456-3 0  9994"
    static let issLine2 = "2 25544  51.6328  51.6259 0006780 277.7856  82.2363 15.48918166590814"

    /// The epoch of those elements, 2026-10-18T03:28:15.076416Z, in seconds since 1970.
    static let issEpochUnixSeconds = 1792294095.076416

    static func fixtureData(_ name: String) throws -> Data {
        guard let directory = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw MissingFixture(name: "Fixtures directory")
        }
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw MissingFixture(name: name) }
        return try Data(contentsOf: url)
    }

    static func fixtureText(_ name: String) throws -> String {
        String(decoding: try fixtureData(name), as: UTF8.self)
    }

    /// A fixture that is a JSON object.
    static func jsonObject(_ name: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: fixtureData(name))
        guard let object = value as? [String: Any] else { throw MissingFixture(name: name + " (not an object)") }
        return object
    }

    static func date(_ unixSeconds: Double) -> Date { Date(timeIntervalSince1970: unixSeconds) }

    /// The instant of an ISO 8601 UTC time such as `2026-10-18T11:29:00Z`.
    static func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    static func observer(_ latitude: Double, _ longitude: Double, _ elevation: Double = 0) -> Observer {
        Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation))
    }

    static let boulder = observer(40.015, -105.2705, 1655.0)
    static let sydney = observer(-33.8688, 151.2093, 20.0)

    /// `line` with its last character replaced by the correct checksum digit.
    static func withChecksum(_ line: String) -> String {
        String(line.prefix(68)) + String(ElementSetParser.checksum(line))
    }

    /// `line` with the characters `[start, end)` replaced by `replacement`.
    static func replacing(_ line: String, _ start: Int, _ end: Int, with replacement: String) -> String {
        var scalars = Array(line.unicodeScalars)
        scalars.replaceSubrange(start..<end, with: Array(replacement.unicodeScalars))
        return String(String.UnicodeScalarView(scalars))
    }

    static func iss() throws -> OrbitalElements {
        try ElementSetParser.parseTwoLine(line1: issLine1, line2: issLine2, name: "ISS (ZARYA)")
    }

    /// The reference satellites by identifier: `iss`, `css`, `hst`, `starlink`, `gps`, `molniya`, `geo`, `polar`.
    static func referenceSatellites() throws -> [String: Satellite] {
        let ids = ["iss", "css", "hst", "starlink", "gps", "molniya", "geo", "polar"]
        let batch = try ElementSetParser.parseJson(fixtureData("satellite_omm_sample.json"))
        precondition(batch.skippedCount == 0 && batch.elements.count == ids.count)
        var result: [String: Satellite] = [:]
        for (id, element) in zip(ids, batch.elements) { result[id] = Satellite(elements: element) }
        return result
    }

    /// A geostationary-like element set that sits over longitude `longitude` on the equator at `epoch`.
    static func geostationary(longitude: Double, epoch: Date) throws -> OrbitalElements {
        let gmstDegrees = AstroMath.degrees(SatelliteFrames.greenwichMeanSiderealTime(at: epoch))
        let anomaly = AstroMath.normalizeDegrees(gmstDegrees + longitude)
        return try OrbitalElements(
            name: "GEOTEST",
            catalogNumber: 99_990,
            epoch: epoch,
            meanMotion: 1.00273790935,
            eccentricity: 0.0001,
            inclination: 0.05,
            rightAscensionOfAscendingNode: 0.0,
            argumentOfPericenter: 0.0,
            meanAnomaly: anomaly
        )
    }

    /// The number stored under `key` in a JSON object.
    static func number(_ object: [String: Any], _ key: String) -> Double {
        (object[key] as? NSNumber)?.doubleValue ?? .nan
    }

    static func text(_ object: [String: Any], _ key: String) -> String { object[key] as? String ?? "" }

    static func list(_ object: [String: Any], _ key: String) -> [[String: Any]] { object[key] as? [[String: Any]] ?? [] }

    static func numbers(_ object: [String: Any], _ key: String) -> [Double] {
        (object[key] as? [NSNumber])?.map(\.doubleValue) ?? []
    }

    static func boolean(_ object: [String: Any], _ key: String) -> Bool {
        (object[key] as? NSNumber)?.boolValue ?? false
    }
}
