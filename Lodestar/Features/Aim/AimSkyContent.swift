import Foundation
import LodestarKit

/// A rebuilt sky as the overlay draws it: the shared snapshot plus drawing groups derived from it, made together off
/// the main actor so a frame only projects and paints.
struct AimSkyContent: Sendable {
    let snapshot: SkySnapshot
    /// Stars grouped by brightness and tint, so each group is painted with one fill.
    let starGroups: [AimStarGroup]
    /// Stars that have a proper name, brightest first.
    let namedStars: [AimNamedStar]
    /// Brightest first.
    let deepSky: [AimDeepSkyMarker]
    /// One layer per Milky Way brightness level, faintest first.
    let milkyWay: [AimMilkyWayLayer]

    /// Stars brighter than this get a name label.
    private static let namedStarMagnitudeLimit = 3.0

    /// Builds the snapshot and the groups. Pure: call it from a detached task.
    static func build(catalog: Catalog, inputs: AimSkyInputs, date: Date) -> AimSkyContent {
        AimSkyContent(snapshot: SkySnapshotBuilder.build(catalog: catalog, observer: inputs.observer, date: date,
                                                         options: inputs.options, target: inputs.target))
    }

    init(snapshot: SkySnapshot) {
        self.snapshot = snapshot
        var groups: [AimStarGroup.Key: [Vector3]] = [:]
        var named: [AimNamedStar] = []
        for star in snapshot.stars {
            let key = AimStarGroup.Key(brightness: AimStarGroup.brightness(of: star.magnitude),
                                       tint: AimStarGroup.tint(of: star.colorIndex),
                                       isBelowHorizon: star.direction.z < 0)
            groups[key, default: []].append(star.direction)
            if let name = star.name, star.magnitude <= Self.namedStarMagnitudeLimit {
                named.append(AimNamedStar(name: name, direction: star.direction, magnitude: star.magnitude))
            }
        }
        // Faint stars first, so brighter ones are painted over them.
        starGroups = groups.map { AimStarGroup(key: $0.key, directions: $0.value) }
            .sorted { ($0.brightness, $0.tint, $0.isBelowHorizon ? 1 : 0) > ($1.brightness, $1.tint, $1.isBelowHorizon ? 1 : 0) }
        namedStars = named
        deepSky = snapshot.deepSky.map(AimDeepSkyMarker.init(_:))
            .sorted { ($0.magnitude ?? .infinity) < ($1.magnitude ?? .infinity) }
        milkyWay = AimMilkyWayLayer.layers(from: snapshot.milkyWay, frame: snapshot.frame)
    }
}

/// Stars of one look: the same brightness class and tint, above or below the horizon.
struct AimStarGroup: Sendable {
    struct Key: Hashable {
        let brightness: Int
        let tint: Int
        let isBelowHorizon: Bool
    }

    /// Brightness classes: 0 for magnitudes below 0, up to the last class for magnitudes of 5 and fainter.
    static let brightnessLevels = 7

    let brightness: Int
    /// 0 for blue-white stars, 1 for white ones, 2 for orange ones.
    let tint: Int
    let isBelowHorizon: Bool
    let directions: [Vector3]

    init(key: Key, directions: [Vector3]) {
        brightness = key.brightness
        tint = key.tint
        isBelowHorizon = key.isBelowHorizon
        self.directions = directions
    }

    static func brightness(of magnitude: Double) -> Int {
        guard magnitude.isFinite else { return brightnessLevels - 1 }
        return min(max(Int(min(max(magnitude, -30), 30).rounded(.down)) + 1, 0), brightnessLevels - 1)
    }

    static func tint(of colorIndex: Double?) -> Int {
        guard let colorIndex, colorIndex.isFinite else { return 1 }
        if colorIndex < 0.3 { return 0 }
        return colorIndex < 0.95 ? 1 : 2
    }
}

struct AimNamedStar: Sendable {
    let name: String
    let direction: Vector3
    let magnitude: Double
}

/// A deep-sky object as a chart symbol.
struct AimDeepSkyMarker: Sendable {
    enum Shape: Sendable {
        /// Galaxies.
        case ellipse
        /// Star clusters and associations.
        case clusterDot
        /// Nebulae and supernova remnants.
        case square
        case circle
    }

    let name: String
    let direction: Vector3
    let shape: Shape
    /// Major axis in degrees; 0 when unknown.
    let diameter: Double
    let magnitude: Double?

    init(_ deepSky: SkySnapshot.DeepSky) {
        name = deepSky.object.name
        direction = deepSky.direction
        diameter = deepSky.majorAxis ?? 0
        magnitude = deepSky.object.magnitude
        switch deepSky.object.category {
        case .galaxy, .galaxyGroup:
            shape = .ellipse
        case .openCluster, .globularCluster, .starAssociation:
            shape = .clusterDot
        case .emissionNebula, .reflectionNebula, .darkNebula, .nebula, .planetaryNebula, .supernovaRemnant,
             .clusterWithNebula:
            shape = .square
        default:
            shape = .circle
        }
    }
}
