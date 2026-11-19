import Foundation
import LodestarKit

/// The skyline that applies at a site and where it comes from; both `nil` for an open horizon.
struct ResolvedHorizon: Equatable, Sendable {
    let profile: HorizonProfile?
    let source: HorizonSource?

    /// An open horizon.
    static let open = ResolvedHorizon(profile: nil, source: nil)
}

/// Decides which skyline applies at a site: the one the user recorded, the terrain horizon computed from elevation data,
/// or the recorded one with the terrain in the stretches the sweep left open. Pure, apart from reading the coverage of the
/// recording from the preferences.
enum SiteHorizon {
    /// `recorded` where the sweep reached, `terrain` in the `gaps` (see `HorizonProfile.merged`). A flat result is an open
    /// horizon. The source is `.recordedAndTerrain` only when the terrain contributes something: a recorded skyline
    /// without gaps stays a recorded one however much terrain is stored.
    static func resolve(recorded: HorizonProfile?, terrain: HorizonProfile?, gaps: [AzimuthRange]) -> ResolvedHorizon {
        let usedRecorded = recorded.flatMap { $0.isFlat ? nil : $0 }
        guard let merged = HorizonProfile.merged(recorded: usedRecorded, terrain: terrain, gaps: gaps), !merged.isFlat else {
            return .open
        }
        let source: HorizonSource
        if usedRecorded == nil {
            source = .terrain
        } else if terrain != nil, !gaps.isEmpty {
            source = .recordedAndTerrain
        } else {
            source = .recorded
        }
        return ResolvedHorizon(profile: merged, source: source)
    }

    /// What applies at `site`: the stretches the recording left open come from the swept degrees remembered with it
    /// (`HorizonCoverageMemory`); without them the recorded skyline wins everywhere.
    static func resolve(_ site: SavedSite) -> ResolvedHorizon {
        guard let terrain = site.terrainHorizon, site.horizon != nil else {
            return resolve(recorded: site.horizon, terrain: site.terrainHorizon, gaps: [])
        }
        let swept = HorizonCoverageMemory.entry(for: site)?.mask
        return resolve(recorded: site.horizon, terrain: terrain,
                       gaps: swept.map { HorizonProfile.unsweptRanges(swept: $0) } ?? [])
    }
}
