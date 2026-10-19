import Foundation

/// The bright asteroids that ship with the library, so that Ceres, Vesta, Pallas and the other asteroids a camera can
/// reach work offline: 216 asteroids as `SmallBody` values, ready for `Catalog.withSmallBodies(_:)`.
///
/// ```swift
/// let asteroids = try BundledAsteroids.load()
/// let catalog = try Catalog.loadBundled().withSmallBodies(asteroids.bodies + downloadedComets)
/// if asteroids.ageDays(at: Date()) > 365 { /* say "elements of \(asteroids.oldestEpoch)" */ }
/// ```
///
/// **Content.** An extract of the Minor Planet Center's `MPCORB.DAT` (file of 2026-10-18; MPC one-line format, read by
/// `MinorPlanetElementsParser`): the asteroids with `H ≤ 10.5` whose best-case peak magnitude
/// (`SmallBodyBrightness.peakMagnitudeEstimate(of:)`) is 11 or brighter. That is the main-belt asteroids from (4) Vesta
/// (best case 5.2) to (471) Papagena (8.5) and fainter, plus (433) Eros and (1036) Ganymed. 47 kB; built by
/// `Tools/build_bright_asteroids.py` from a pinned snapshot (see `Tools/asteroids.lock.json`).
///
/// **Freshness.** The elements are osculating at the epoch of each record (`oldestEpoch` to `newestEpoch`: 2026-06-09
/// for all 216); positions are two-body extrapolations from there. Measured against JPL Horizons (Ceres, Pallas, Juno,
/// Vesta, Iris, Hebe, Eros): at most 0.3″ after 30 days, 5.3″ after 131 days, 37″ after a year and 13′ after two years
/// (median 3′). That is good for aiming within the field of view of a lens for a year; after that, and whenever there
/// are newer elements, replace them: pass the downloaded bodies after these in the list given to
/// `Catalog.withSmallBodies(_:)`, where the last body with an identifier wins. Show "elements of <date>" when
/// `ageDays(at:)` exceeds 365.
public struct BundledAsteroids: Sendable {
    /// The name of the bundled file in the library's resources.
    public static let resourceFileName = "asteroids.txt"
    /// The largest file that is accepted, 1 MiB (the shipped one is 47 kB).
    public static let maximumFileBytes = 1024 * 1024
    /// The cut's best-case peak magnitude: no asteroid that can never reach this magnitude is in the list.
    public static let peakMagnitudeLimit = 11.0
    /// The cut's absolute magnitude.
    public static let maximumAbsoluteMagnitude = 10.5

    /// The asteroids, in the order of the file (by number).
    public let bodies: [SmallBody]
    /// Lines of the file that were not valid orbit lines; 0 for the shipped file.
    public let rejectedLineCount: Int
    /// The earliest osculating epoch among the bodies.
    public let oldestEpoch: Date
    /// The latest osculating epoch among the bodies.
    public let newestEpoch: Date

    /// The days from `oldestEpoch` to `date` (negative before it): how far the elements are extrapolated.
    public func ageDays(at date: Date) -> Double {
        date.timeIntervalSince(oldestEpoch) / 86_400
    }

    /// Reads the bundled file; a few milliseconds.
    ///
    /// - Throws: `CatalogError.brightAsteroidsUnavailable` when the file is missing, unreadable, too large or has no
    ///   valid line.
    public static func load() throws -> BundledAsteroids {
        try parse(bundledData())
    }

    /// The raw contents of the bundled file.
    static func bundledData() throws -> Data {
        let bundle = Bundle.module
        let name = (resourceFileName as NSString).deletingPathExtension
        let fileExtension = (resourceFileName as NSString).pathExtension
        guard let url = bundle.url(forResource: name, withExtension: fileExtension)
                ?? bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources") else {
            throw CatalogError.brightAsteroidsUnavailable(reason: "the resource \(resourceFileName) is missing")
        }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw CatalogError.brightAsteroidsUnavailable(reason: error.localizedDescription)
        }
    }

    /// Reads the contents of such a file; `load()` is this with the bundled bytes.
    static func parse(_ data: Data) throws -> BundledAsteroids {
        guard data.count <= maximumFileBytes else {
            throw CatalogError.brightAsteroidsUnavailable(reason: "the file is larger than \(maximumFileBytes) bytes")
        }
        let result: SmallBodyParseResult
        do {
            result = try MinorPlanetElementsParser.parse(String(decoding: data, as: UTF8.self))
        } catch {
            throw CatalogError.brightAsteroidsUnavailable(reason: String(describing: error))
        }
        guard !result.bodies.isEmpty else {
            throw CatalogError.brightAsteroidsUnavailable(reason: "no valid line (\(result.rejectedLineCount) rejected)")
        }
        let epochs = result.bodies.map(\.orbit.epochJulianDayTT)
        return BundledAsteroids(bodies: result.bodies, rejectedLineCount: result.rejectedLineCount,
                                oldestEpoch: JulianDate(tt: epochs.min() ?? 0).date,
                                newestEpoch: JulianDate(tt: epochs.max() ?? 0).date)
    }
}
