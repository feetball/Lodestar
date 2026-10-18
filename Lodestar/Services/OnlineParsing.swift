import Foundation
import LodestarKit

/// Thrown by a parser that was handed bytes it cannot use; the download is then discarded and the cache kept.
struct OnlineDataError: Error, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// The result of parsing a download: the value, and the newest orbit epoch in it if it has one.
struct OnlineParsed<Value: Sendable>: Sendable {
    let value: Value
    var dataEpoch: Date?
}

/// Parsed data of any feed, ready to be published.
enum OnlineLoaded: Sendable {
    case satellites(SatelliteGroup)
    case comets([SmallBody])
    case forecast(CloudForecast)
}

/// Validates the bytes of a download with the engine's parsers and turns them into the data kept in memory. A download
/// that does not parse, or parses to nothing, throws and never replaces good data.
enum OnlineParsing {
    /// Up to this share of the comet lines (as a fraction of the parsed comets) may be rejected; beyond it the file's
    /// format has probably changed.
    static let maximumRejectedShare = 0.25

    static func parse(_ resource: OnlineResource, data: Data, now: Date) throws -> OnlineParsed<OnlineLoaded> {
        switch resource {
        case .stations, .visual, .starlink:
            guard let group = resource.group else { throw OnlineDataError("Not a satellite resource.") }
            let parsed = try SatelliteGroup.parse(group: group, data: data, now: now)
            return OnlineParsed(value: .satellites(parsed.value), dataEpoch: parsed.dataEpoch)
        case .comets:
            return OnlineParsed(value: .comets(try comets(data)))
        case .forecast:
            return OnlineParsed(value: .forecast(try ForecastParser.parseForecast(data)))
        }
    }

    /// The comets in `CometEls.txt`. The file is plain ASCII with fixed columns, so each byte is one character. Throws when
    /// the file has no comet or many rejected lines.
    static func comets(_ data: Data) throws -> [SmallBody] {
        guard let text = String(data: data, encoding: .isoLatin1) else { throw OnlineDataError("Not a comet file.") }
        let result: SmallBodyParseResult
        do {
            result = try CometElementsParser.parse(text)
        } catch {
            throw OnlineDataError("Not a comet file: \(error.localizedDescription)")
        }
        guard !result.bodies.isEmpty else { throw OnlineDataError("No comets in the file.") }
        guard Double(result.rejectedLineCount) <= Double(result.bodies.count) * maximumRejectedShare else {
            throw OnlineDataError("\(result.rejectedLineCount) lines of the comet file were rejected.")
        }
        return result.bodies
    }
}
