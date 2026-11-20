import Foundation
import LodestarKit

/// What a finished terrain computation says: the `lines` under the buttons of the site editor, and the ground elevation the
/// elevation data puts at the site, rounded to whole metres, which the editor offers as the site's elevation.
struct TerrainSummary: Equatable, Sendable {
    let lines: [String]
    let groundElevationMeters: Int?
}

/// The words of the terrain horizon section of the site editor. The Android app uses the same texts.
enum TerrainText {
    static let sectionTitle = "Terrain Horizon"

    static let footer = "Works out the skyline of the hills and mountains around the site from elevation data. It is used "
        + "where you have not recorded a skyline, and in the stretches a partial sweep left open. Trees and buildings are "
        + "not in it."

    /// Under the skyline strip of the recording screen, for a site that has a terrain horizon.
    static let stripNote = "The stretches you do not sweep use the terrain horizon."

    static let notComputed = "Not computed"
    static let compute = "Compute from Elevation Data\u{2026}"
    static let remove = "Remove Terrain Horizon\u{2026}"
    static let cancel = "Cancel"
    static let switchedOff = "Turn on Terrain horizons in Settings \u{25B8} Online Data to download elevation data."
    static let saveFirst = "Save the site first, then compute its terrain horizon here."
    static let moved = "You moved this site. Save it first, then compute the terrain horizon of the new place."
    static let movedStored = "You moved this site. The terrain horizon belongs to the old spot: save the site, then "
        + "compute it again."
    static let confirmTitle = "Download Elevation Data?"
    static let confirmButton = "Download"
    static let removeTitle = "Remove the Terrain Horizon?"
    static let removeButton = "Remove"
    static let keepButton = "Keep"
    static let removeMessage = "The site goes back to its recorded skyline, or to an open horizon. You can compute the "
        + "terrain horizon again, which downloads the elevation data again."
    static let cancelled = "Cancelled. Nothing was changed."
    static let unreadable = "The elevation data could not be turned into a skyline."
    static let computing = "Computing the skyline\u{2026}"

    /// About how many megabytes one tile file is.
    static let tileMegabytes = 11

    /// The share of void samples from which the summary mentions them.
    static let voidNoteShare = 0.01

    /// "Computed · highest 9° in the south" for a site with a terrain horizon; "Computed · partial: 4 of 6 tiles ·
    /// highest 9° in the south" when the tile limit left some of the surroundings out.
    static func status(_ profile: HorizonProfile, tiles: TerrainTileMemory.Entry? = nil) -> String {
        var parts = ["Computed"]
        if let tiles { parts.append("partial: \(tiles.used) of \(tiles.needed) tiles") }
        parts.append(HorizonText.highest(profile))
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The status of the terrain horizon stored with `site`, or "Not computed".
    static func status(of site: SavedSite) -> String {
        guard let profile = site.terrainHorizon else { return notComputed }
        return status(profile, tiles: TerrainTileMemory.recall(for: site))
    }

    /// What the confirmation says before `tileCount` tiles are downloaded.
    static func confirmMessage(tileCount: Int) -> String {
        let tiles = tileCount == 1 ? "1 elevation tile" : "\(tileCount) elevation tiles"
        return "Lodestar will download \(tiles) of about \(tileMegabytes) MB each from AWS Open Data, work out the skyline "
            + "and delete the tiles. The tile server sees your IP address and which 1\u{00B0} tiles you request. This uses "
            + "mobile data when you are not on Wi-Fi."
    }

    /// The progress line while the loader works.
    static func progress(_ progress: TerrainHorizonLoader.Progress) -> String {
        switch progress {
        case .downloading(let index, let count, let tile):
            return "Downloading elevation tile \(index) of \(count) (\(tile.name))\u{2026}"
        case .reading(let index, let count, let tile):
            return "Reading elevation tile \(index) of \(count) (\(tile.name))\u{2026}"
        }
    }

    /// "Use 412 m as the Site Elevation".
    static func useElevation(_ meters: Int) -> String { "Use \(meters) m as the Site Elevation" }

    /// The lines that say what the computation did and what it could not do.
    static func summary(of result: TerrainHorizonResult, tilesUsed: Int, unavailable: [TerrainTileKey]) -> TerrainSummary {
        var lines = ["Terrain horizon computed from \(tilesUsed == 1 ? "1 elevation tile" : "\(tilesUsed) elevation tiles")."]
        let ground = result.groundElevationMeters.map { Int($0.rounded()) }
        if let ground { lines.append("The elevation data puts the ground at the site at \(ground) m.") }
        if !unavailable.isEmpty {
            lines.append("No elevation data for \(names(unavailable)) (open sea or outside the tile set): nothing there is "
                         + "in the skyline.")
        }
        let skipped = skippedTiles(of: result, unavailable: unavailable)
        if !skipped.isEmpty {
            let kilometres = Int((result.minimumCoveredRangeMeters / 1000).rounded())
            lines.append("Not downloaded (only the \(TerrainHorizonLoader.maximumTiles) nearest tiles are used): "
                         + "\(names(skipped)). The skyline reaches \(kilometres) km in the worst direction.")
        }
        if result.voidSampleShare >= voidNoteShare {
            lines.append("Some elevation samples were missing (water or gaps) and count as sea level.")
        }
        return TerrainSummary(lines: lines, groundElevationMeters: ground)
    }

    /// The tiles within reach that were not downloaded because of `TerrainHorizonLoader.maximumTiles`, not counting the
    /// ones the provider has no file for.
    static func skippedTiles(of result: TerrainHorizonResult, unavailable: [TerrainTileKey]) -> [TerrainTileKey] {
        result.missingTiles.filter { !unavailable.contains($0) }
    }

    /// "N47E007", "N47E007 and N46E008", "N47E007, N46E008 and N46E007".
    static func names(_ keys: [TerrainTileKey]) -> String {
        let names = keys.map(\.name)
        guard names.count > 1 else { return names.joined() }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}

/// How many of the tiles a site's terrain horizon needs were used, remembered next to the terrain horizon when the
/// tile limit left some out. The stored terrain horizon is only the 360 altitudes, so, like `HorizonCoverageMemory`,
/// this lives in this device's preferences together with a fingerprint of the terrain horizon it belongs to; a terrain
/// horizon from elsewhere (a restore, another version) simply has nothing to say about its tiles.
enum TerrainTileMemory {
    /// What is remembered with a partial terrain horizon.
    struct Entry: Equatable {
        /// The tiles that were used or have no data (open sea): all but the ones the limit left out.
        let used: Int
        /// The tiles within reach of the site.
        let needed: Int
    }

    private static func key(_ siteID: UUID) -> String {
        "lodestar.terrain.tiles.\(siteID.uuidString)"
    }

    /// What is remembered with `site`'s terrain horizon, or `nil` when it is complete, nothing is remembered or the
    /// terrain horizon has changed since.
    static func recall(for site: SavedSite) -> Entry? {
        guard let profile = site.terrainHorizon, let text = UserDefaults.standard.string(forKey: key(site.id)) else {
            return nil
        }
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == HorizonCoverageMemory.fingerprint(of: profile),
              let used = Int(parts[1]), let needed = Int(parts[2]), 0 <= used, used < needed else { return nil }
        return Entry(used: used, needed: needed)
    }

    /// Remembers that `profile`, the terrain horizon of the site `siteID`, was worked out with `skipped` of `needed`
    /// tiles left out because of the tile limit; forgets what was remembered when none was.
    static func store(siteID: UUID, profile: HorizonProfile, needed: Int, skipped: Int) {
        guard skipped > 0, skipped <= needed else {
            forget(siteID: siteID)
            return
        }
        UserDefaults.standard.set("\(HorizonCoverageMemory.fingerprint(of: profile)):\(needed - skipped):\(needed)",
                                  forKey: key(siteID))
    }

    /// Drops what is remembered for the site `siteID`.
    static func forget(siteID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(siteID))
    }
}
