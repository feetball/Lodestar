import Foundation
import LodestarKit

/// The site's recorded skyline, prepared for the overlay: the line as directions, the ground below it cut into narrow
/// wedges that reach down to the nadir, and the mask that tells whether a direction is hidden behind it. Made once per
/// sky rebuild, off the main actor.
struct AimSkyline: Sendable {
    /// A piece of the ground: the skyline between two azimuths and the nadir. Its edges are great-circle arcs, so it can
    /// be clipped to the view and projected like the Milky Way's outlines.
    struct Wedge: Sendable {
        let vertices: [Vector3]
        /// The middle of the piece and the largest angle in degrees from it to a vertex, for quick rejection.
        let center: Vector3
        let radius: Double
    }

    /// Azimuth covered by one wedge, in degrees.
    static let wedgeWidth = 5

    let profile: HorizonProfile
    let mask: HorizonMask
    /// The skyline every degree of azimuth; the last point repeats the first, so the line closes.
    let line: [Vector3]
    /// The ground below the skyline, fill them together.
    let wedges: [Wedge]

    init(profile: HorizonProfile) {
        self.profile = profile
        mask = HorizonMask(profile: profile)
        line = profile.polyline(from: 0, to: 360, step: 1).map {
            HorizontalCoordinate(azimuth: $0.azimuth, altitude: $0.altitude).unitVector
        }
        let nadir = Vector3(0, 0, -1)
        var wedges: [Wedge] = []
        for start in stride(from: 0, to: line.count - 1, by: Self.wedgeWidth) {
            let end = min(start + Self.wedgeWidth, line.count - 1)
            let vertices = Array(line[start...end]) + [nadir]
            let center = vertices.reduce(Vector3.zero, +).normalized
            guard center != .zero else { continue }
            wedges.append(Wedge(vertices: vertices, center: center,
                                radius: vertices.map { center.angle(to: $0) }.max() ?? 0))
        }
        self.wedges = wedges
    }

    /// The highest altitude of the skyline in degrees.
    var highestAltitude: Double { profile.maximumAltitude }
}
