import Foundation
import LodestarKit

/// What the sky views draw, for one instant and observer: every visible thing as an apparent
/// (refracted) unit vector in the local East–North–Up frame.
///
/// Building a snapshot touches every catalog object, so it runs off the main actor every few
/// seconds; drawing a frame then only rotates and projects these vectors.
struct SkySnapshot: Sendable {
    struct Star: Sendable {
        let id: String
        let direction: Vector3
        let magnitude: Double
        let colorIndex: Double?
        let name: String?
    }

    /// The Sun, the Moon or a planet.
    struct Body: Sendable, Identifiable {
        let object: CelestialObject
        let direction: Vector3
        let horizontal: HorizontalCoordinate
        let magnitude: Double?
        /// Apparent diameter in degrees.
        let angularDiameter: Double
        let illuminatedFraction: Double?
        let isWaxing: Bool?
        var id: String { object.id }
    }

    struct DeepSky: Sendable, Identifiable {
        let object: CelestialObject
        let direction: Vector3
        /// Major axis in degrees, when known.
        let majorAxis: Double?
        var id: String { object.id }
    }

    struct ConstellationFigure: Sendable, Identifiable {
        let abbreviation: String
        let name: String
        let label: Vector3
        let lines: [[Vector3]]
        var id: String { abbreviation }
    }

    struct MilkyWayBand: Sendable {
        /// 1 = faint outer glow … 5 = brightest core.
        let level: Int
        let polygons: [[Vector3]]
        let holes: [[Vector3]]
    }

    /// The current target's apparent position.
    struct Target: Sendable {
        let object: CelestialObject
        let direction: Vector3
        let horizontal: HorizontalCoordinate
    }

    let date: Date
    let observer: Observer
    /// Brightest first.
    let stars: [Star]
    let bodies: [Body]
    let deepSky: [DeepSky]
    let constellations: [ConstellationFigure]
    let milkyWay: [MilkyWayBand]
    let target: Target?

    /// The local frame used to build the snapshot (for horizon/grid drawing and inverse lookups).
    var frame: SkyFrame { SkyFrame(date: date, observer: observer) }
}

/// Which layers to include and how deep to go.
struct SkySnapshotOptions: Sendable, Equatable {
    var starMagnitudeLimit: Double = 5
    var includeConstellations = true
    var includeDeepSky = true
    var includeMilkyWay = true
    /// Deep-sky objects fainter than this are left out (objects without a magnitude are kept).
    var deepSkyMagnitudeLimit: Double = 10
}

enum SkySnapshotBuilder {
    /// Below this geometric altitude refraction is zero, so the vector is used as is.
    private static let refractionFloor = AstroMath.sinDeg(-5)

    /// Computes the snapshot. Pure and `Sendable`-safe: call it from a detached task.
    static func build(catalog: Catalog, observer: Observer, date: Date,
                      options: SkySnapshotOptions, target: CelestialObject?) -> SkySnapshot {
        let frame = SkyFrame(date: date, observer: observer)
        let atmosphere = observer.atmosphere

        func apparent(_ geometric: Vector3) -> Vector3 {
            guard geometric.z > refractionFloor else { return geometric }
            return SkyFrame.refracted(HorizontalCoordinate(vector: geometric), atmosphere: atmosphere).unitVector
        }
        func direction(ofJ2000 position: EquatorialCoordinate) -> Vector3 {
            apparent(frame.horizontalVector(j2000UnitVector: position.unitVector))
        }

        let stars = catalog.renderStars
            .prefix { $0.magnitude <= options.starMagnitudeLimit }
            .map { star in
                SkySnapshot.Star(id: star.id, direction: apparent(frame.horizontalVector(j2000UnitVector: star.unitVector)),
                     magnitude: star.magnitude, colorIndex: star.colorIndex, name: star.name)
            }

        let bodies: [SkySnapshot.Body] = SolarSystemBody.allCases.compactMap { body in
            guard let object = catalog.object(id: objectID(for: body)) else { return nil }
            let state = frame.state(of: body)
            let horizontal = frame.horizontal(of: body, refraction: true)
            return SkySnapshot.Body(object: object, direction: horizontal.unitVector, horizontal: horizontal,
                        magnitude: state.apparentMagnitude, angularDiameter: state.angularDiameterArcseconds / 3600,
                        illuminatedFraction: state.illuminatedFraction, isWaxing: state.isWaxing)
        }

        var deepSky: [SkySnapshot.DeepSky] = []
        if options.includeDeepSky {
            for object in catalog.listedObjects {
                guard case .fixed(let position, _) = object.position,
                      [.galaxies, .nebulae, .clusters, .special].contains(object.group) else { continue }
                if let magnitude = object.magnitude, magnitude > options.deepSkyMagnitudeLimit { continue }
                deepSky.append(SkySnapshot.DeepSky(object: object, direction: direction(ofJ2000: position),
                                       majorAxis: object.angularSize.map { $0.majorArcminutes / 60 }))
            }
        }

        let constellations: [SkySnapshot.ConstellationFigure] = options.includeConstellations
            ? catalog.constellations.map { constellation in
                SkySnapshot.ConstellationFigure(abbreviation: constellation.abbreviation, name: constellation.name,
                                    label: direction(ofJ2000: constellation.labelPosition),
                                    lines: constellation.lines.map { $0.map(direction(ofJ2000:)) })
            }
            : []

        let milkyWay: [SkySnapshot.MilkyWayBand] = options.includeMilkyWay
            ? catalog.milkyWay.levels.map { level in
                SkySnapshot.MilkyWayBand(level: level.level,
                             polygons: level.polygons.map { $0.map(direction(ofJ2000:)) },
                             holes: level.holes.map { $0.map(direction(ofJ2000:)) })
            }
            : []

        let targetPosition = target.map { object in
            let horizontal = frame.horizontal(of: object, refraction: true)
            return SkySnapshot.Target(object: object, direction: horizontal.unitVector, horizontal: horizontal)
        }

        return SkySnapshot(date: date, observer: observer, stars: stars, bodies: bodies, deepSky: deepSky,
                           constellations: constellations, milkyWay: milkyWay, target: targetPosition)
    }

    /// Catalog identifier of a solar-system body ("sun", "moon", "planet.mars").
    static func objectID(for body: SolarSystemBody) -> String {
        switch body {
        case .sun: return "sun"
        case .moon: return "moon"
        default: return "planet.\(body.rawValue)"
        }
    }
}
