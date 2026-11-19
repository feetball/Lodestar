import Foundation
import LodestarKit

/// What the app knows about the sky quality of one place.
struct SkyReading: Sendable {
    /// The Bortle estimate of the place.
    let estimate: BortleEstimate
    /// The 16 compass directions with the light along each, 30 km out, north first.
    let directions: [DirectionBrightness]
}

/// The brightness of the horizon by azimuth for the thin glow ring of the sky chart: `segments` values from 0 (dark) to 1,
/// the first centred on north, one every 5°.
struct HorizonGlowRing: Sendable, Equatable {
    /// The number of segments of the ring.
    static let segments = 72

    /// One value per segment, 0 to 1.
    let glow: [Double]
    /// One sentence for screen readers: where the horizon is brightest.
    let spokenSummary: String

    /// The ring of a list from `LightPollutionMap.darkestDirection`; `nil` when no direction has any light.
    init?(directions: [DirectionBrightness]) {
        guard let brightest = directions.max(by: { $0.meanLevel < $1.meanLevel }), brightest.meanLevel > 0 else {
            return nil
        }
        glow = (0..<Self.segments).map { directions.horizonGlow(azimuth: Double($0) * 360 / Double(Self.segments)) }
        let direction = CompassPoint(azimuth: brightest.azimuth).fullName.lowercased()
        spokenSummary = "A thin glow ring at the horizon marks the artificial light; it is brightest toward the "
            + "\(direction)."
    }
}

/// The light pollution map, loaded the first time a screen asks for it (about 10 ms and 6.5 MB, off the main actor) and
/// kept for as long as the process lives. Readings are `nil` when the bundled file cannot be read: the sky-quality lines
/// then stay out.
actor SkyQualityMapStore {
    static let shared = SkyQualityMapStore()

    private var map: LightPollutionMap?
    private var hasFailed = false

    private func loadedMap() -> LightPollutionMap? {
        if let map { return map }
        if hasFailed { return nil }
        do {
            let loaded = try LightPollutionMap.load()
            map = loaded
            return loaded
        } catch {
            hasFailed = true
            return nil
        }
    }

    /// The sky quality of `location`.
    func reading(at location: GeographicLocation) -> SkyReading? {
        guard let map = loadedMap() else { return nil }
        return SkyReading(estimate: map.bortleEstimate(at: location), directions: map.darkestDirection(around: location))
    }

    /// The glow ring around `location`; `nil` where there is no light.
    func glowRing(at location: GeographicLocation) -> HorizonGlowRing? {
        guard let map = loadedMap() else { return nil }
        return HorizonGlowRing(directions: map.darkestDirection(around: location))
    }
}

/// Names a place to about a kilometre, so that a GPS fix that drifts does not restart the work for every sample.
struct SkyQualityKey: Equatable, Sendable {
    let latitude: Int
    let longitude: Int

    init?(_ location: GeographicLocation?) {
        guard let location else { return nil }
        latitude = Int((location.latitude * 100).rounded(.down))
        longitude = Int((location.longitude * 100).rounded(.down))
    }
}
