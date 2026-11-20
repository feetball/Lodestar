import Foundation
@testable import LodestarKit

/// Synthetic elevation tiles for the terrain tests: no file and no network is needed.
enum TerrainTestSupport {
    /// Metres per degree of arc on the sphere of `TerrainHorizon.earthRadiusMeters`.
    static let metersPerDegree = 6_371_008.8 * Double.pi / 180

    /// The bytes of a tile with `side` × `side` samples, `sample` giving the elevation of a row (from the north) and a column.
    static func bytes(side: Int, sample: (_ row: Int, _ column: Int) -> Int) -> Data {
        var out = [UInt8](repeating: 0, count: side * side * 2)
        for row in 0..<side {
            for column in 0..<side {
                let value = sample(row, column)
                let index = 2 * (row * side + column)
                out[index] = UInt8(truncatingIfNeeded: value >> 8)
                out[index + 1] = UInt8(truncatingIfNeeded: value)
            }
        }
        return Data(out)
    }

    /// A 1201 × 1201 tile whose samples are `elevation` at their latitude and longitude, rounded to whole metres.
    static func tile(latitude: Int, longitude: Int, elevation: (Double, Double) -> Double) throws -> TerrainTile {
        let side = TerrainTile.lowResolutionSamples
        let intervals = Double(side - 1)
        let data = bytes(side: side) { row, column in
            Int(elevation(Double(latitude) + 1 - Double(row) / intervals, Double(longitude) + Double(column) / intervals)
                .rounded())
        }
        return try TerrainTile.parse(latitude: latitude, longitude: longitude, bytes: data)
    }

    /// A tile at the same `meters` everywhere.
    static func flatTile(latitude: Int, longitude: Int, meters: Int) throws -> TerrainTile {
        try tile(latitude: latitude, longitude: longitude) { _, _ in Double(meters) }
    }

    /// The point `distance` metres from (`latitude`, `longitude`) along `azimuth` on the sphere, as (latitude, longitude).
    static func destination(latitude: Double, longitude: Double, azimuth: Double,
                            distance: Double) -> (latitude: Double, longitude: Double) {
        let delta = distance / TerrainHorizon.earthRadiusMeters
        let phi = AstroMath.radians(latitude)
        let theta = AstroMath.radians(azimuth)
        let phi2 = asin(sin(phi) * cos(delta) + cos(phi) * sin(delta) * cos(theta))
        let lambda = AstroMath.radians(longitude)
            + atan2(sin(theta) * sin(delta) * cos(phi), cos(delta) - sin(phi) * sin(phi2))
        return (AstroMath.degrees(phi2), AstroMath.degrees(lambda))
    }

    /// A round hill: `height` metres at the apex, falling to 0 m at `radius` metres as `1 − (r / radius)²`.
    static func dome(apexLatitude: Double, apexLongitude: Double, height: Double = 300,
                     radius: Double = 3000) -> (Double, Double) -> Double {
        { latitude, longitude in
            let north = (latitude - apexLatitude) * metersPerDegree
            let east = (longitude - apexLongitude) * metersPerDegree * AstroMath.cosDeg(apexLatitude)
            let fraction = hypot(north, east) / radius
            return fraction >= 1 ? 0 : height * (1 - fraction * fraction)
        }
    }

    /// The highest apparent altitude along the ray from (`latitude`, `longitude`) at `azimuth`, computed straight from the
    /// landscape `elevation` (not from a tile: no sampling, no rounding): the same steps and the same formula as the engine,
    /// for an eye 2 m above `ground`.
    static func expectedSkyline(latitude: Double, longitude: Double, azimuth: Double, ground: Double,
                                elevation: (Double, Double) -> Double) -> Double {
        TerrainHorizon.sampleDistances(maximumDistanceMeters: TerrainHorizon.defaultMaximumDistanceMeters).map { distance in
            let point = destination(latitude: latitude, longitude: longitude, azimuth: azimuth, distance: distance)
            return TerrainHorizon.apparentAltitude(heightDifferenceMeters: elevation(point.latitude, point.longitude) - (ground + 2),
                                                   distanceMeters: distance)
        }.max() ?? 0
    }

    /// The dip of the horizon over flat ground for an eye `eye` metres high, in degrees (negative): `−√(2h / R′)`.
    static func flatDip(eye: Double) -> Double {
        let effective = TerrainHorizon.earthRadiusMeters / (1 - TerrainHorizon.refractionCoefficient)
        return -AstroMath.degrees((2 * eye / effective).squareRoot())
    }
}
