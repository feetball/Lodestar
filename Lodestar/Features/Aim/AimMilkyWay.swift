import Foundation
import LodestarKit

/// A closed outline of the Milky Way, with the cap that contains it for quick rejection.
struct AimMilkyWayRing: Sendable {
    /// Rings wider than this (radius in degrees) are cut up first: their closing edges after clipping would approach
    /// half a circle, which a rectilinear view cannot represent.
    static let maximumRadius = 60.0

    let vertices: [Vector3]
    let center: Vector3
    /// Largest angle in degrees between `center` and a vertex.
    let radius: Double

    init?(vertices: [Vector3]) {
        guard vertices.count >= 3 else { return nil }
        let center = vertices.reduce(Vector3.zero, +).normalized
        guard center != .zero else { return nil }
        let radius = vertices.map { center.angle(to: $0) }.max() ?? 0
        guard radius <= Self.maximumRadius else { return nil }
        self.vertices = vertices
        self.center = center
        self.radius = radius
    }
}

/// The outlines of one Milky Way brightness level: filled areas and the holes cut out of them (even-odd rule).
struct AimMilkyWayLayer: Sendable {
    let rings: [AimMilkyWayRing]

    /// The drawable layers of the snapshot's bands. The outer glow circles the whole sky in one outline; it is cut
    /// into strips of galactic longitude, which together fill the same area. A band that still cannot be prepared is
    /// left out as a whole, because its holes would otherwise be filled on their own.
    static func layers(from bands: [SkySnapshot.MilkyWayBand], frame: SkyFrame) -> [AimMilkyWayLayer] {
        bands.compactMap { band in
            var rings: [AimMilkyWayRing] = []
            for outline in band.polygons + band.holes {
                if let ring = AimMilkyWayRing(vertices: outline) {
                    rings.append(ring)
                    continue
                }
                let strips = AimGalacticStrips.pieces(of: outline, frame: frame)
                let stripRings = strips.compactMap(AimMilkyWayRing.init(vertices:))
                guard !stripRings.isEmpty, stripRings.count == strips.count else { return nil }
                rings += stripRings
            }
            return rings.isEmpty ? nil : AimMilkyWayLayer(rings: rings)
        }
    }
}

/// Cuts an outline that runs all the way around the sky into pieces of limited width.
///
/// In galactic coordinates, with the longitude unrolled so it grows continuously along the outline, the outline of the
/// Milky Way is a simple polygon, and cutting it at multiples of `width` degrees of longitude gives pieces that
/// are compact on the sphere. Their shared edges are meridians, which are great-circle arcs like the rest.
enum AimGalacticStrips {
    /// The width of a piece in degrees of galactic longitude.
    static let width = 60.0

    private struct Point {
        var longitude: Double
        var latitude: Double
    }

    /// The pieces as rings of ENU directions; empty when the outline is degenerate.
    static func pieces(of ring: [Vector3], frame: SkyFrame) -> [[Vector3]] {
        guard ring.count >= 3 else { return [] }
        let toJ2000 = frame.j2000ToHorizontal.transposed
        var outline: [Point] = []
        var turns = 0.0
        var previousLongitude: Double?
        for vertex in ring {
            let galactic = CoordinateTransforms.equatorialJ2000ToGalactic(EquatorialCoordinate(vector: toJ2000 * vertex))
            if let previousLongitude {
                let step = galactic.longitude - previousLongitude
                if step > 180 {
                    turns -= 360
                } else if step < -180 {
                    turns += 360
                }
            }
            previousLongitude = galactic.longitude
            outline.append(Point(longitude: galactic.longitude + turns, latitude: galactic.latitude))
        }
        let longitudes = outline.map(\.longitude)
        guard let first = longitudes.min(), let last = longitudes.max(), last - first < 4 * 360 else { return [] }

        var pieces: [[Vector3]] = []
        var start = (first / width).rounded(.down) * width
        while start < last {
            let piece = clip(clip(outline, at: start, keepingAbove: true), at: start + width, keepingAbove: false)
            if piece.count >= 3 {
                pieces.append(piece.map { direction(of: $0, frame: frame) })
            }
            start += width
        }
        return pieces
    }

    /// Sutherland–Hodgman against the line of constant longitude `boundary`.
    private static func clip(_ polygon: [Point], at boundary: Double, keepingAbove: Bool) -> [Point] {
        guard let last = polygon.last else { return [] }
        let sign = keepingAbove ? 1.0 : -1.0
        var output: [Point] = []
        var previous = last
        var previousDistance = sign * (previous.longitude - boundary)
        for current in polygon {
            let distance = sign * (current.longitude - boundary)
            if distance >= 0 {
                if previousDistance < 0 { output.append(crossing(previous, current, previousDistance, distance)) }
                output.append(current)
            } else if previousDistance >= 0 {
                output.append(crossing(previous, current, previousDistance, distance))
            }
            previous = current
            previousDistance = distance
        }
        return output
    }

    private static func crossing(_ a: Point, _ b: Point, _ da: Double, _ db: Double) -> Point {
        let t = da / (da - db)
        return Point(longitude: a.longitude + (b.longitude - a.longitude) * t,
                     latitude: a.latitude + (b.latitude - a.latitude) * t)
    }

    private static func direction(of point: Point, frame: SkyFrame) -> Vector3 {
        let galactic = GalacticCoordinate(longitude: point.longitude, latitude: point.latitude)
        return frame.horizontalVector(j2000UnitVector: CoordinateTransforms.galacticToEquatorialJ2000(galactic).unitVector)
    }
}
