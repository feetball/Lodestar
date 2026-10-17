import SwiftUI
import LodestarKit

/// Which layers of the chart are drawn.
struct SkyChartLayerOptions: Equatable {
    var constellationLines = true
    var constellationNames = true
    var milkyWay = true
    var deepSkyObjects = true
    var starNames = true
    var altitudeGrid = true
    var cameraView = true
}

/// Builders for the simple shapes the chart draws.
enum PlanisphereShapes {
    /// The circle of `radius` around `center`.
    static func circle(around center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: PlanisphereBounds.square(around: center, radius: radius))
    }

    /// The polyline through `points`, as one subpath that is closed when `closed` is set.
    static func polyline(_ points: [CGPoint], closed: Bool = false) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if closed { path.closeSubpath() }
        return path
    }

    /// Four short lines that point away from `center` along the screen axes, each running from
    /// `inner` to `outer` points from the centre: the ticks of a reticle or crosshair.
    static func axisTicks(around center: CGPoint, from inner: CGFloat, to outer: CGFloat) -> Path {
        var path = Path()
        for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            let direction = CGPoint(x: dx, y: dy)
            path.move(to: CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner))
            path.addLine(to: CGPoint(x: center.x + direction.x * outer, y: center.y + direction.y * outer))
        }
        return path
    }
}

/// The line and polygon geometry of a scene as paths in chart space, built once per scene so that a
/// frame only has to transform them onto the screen.
struct SkyChartPaths: Sendable {
    /// One path per Milky Way level, to be filled with the even–odd rule. A level that inverts its
    /// fill (see `SkyChartMilkyWayLevel`) includes a square that covers the whole chart.
    let milkyWay: [Path]
    let constellationLines: Path

    init(scene: SkyChartScene) {
        milkyWay = scene.milkyWay.map { level in
            var path = Path()
            for ring in level.rings {
                path.addPath(PlanisphereShapes.polyline(ring, closed: true))
            }
            if level.invertsFill {
                path.addRect(CGRect(x: -2, y: -2, width: 4, height: 4))
            }
            return path
        }
        var lines = Path()
        for polyline in scene.constellationLines {
            lines.addPath(PlanisphereShapes.polyline(polyline))
        }
        constellationLines = lines
    }
}

/// A scene with its cached paths.
struct SkyChartContent: Sendable, Equatable {
    let scene: SkyChartScene
    let paths: SkyChartPaths
    /// Unique among the contents a model produces; contents are equal when their revisions are.
    let revision: Int

    static func == (lhs: SkyChartContent, rhs: SkyChartContent) -> Bool {
        lhs.revision == rhs.revision
    }
}

extension PlanisphereViewport {
    /// The transform that maps chart points onto the screen.
    var transform: CGAffineTransform {
        CGAffineTransform(a: radius * cosine, b: radius * sine, c: -radius * sine, d: radius * cosine,
                          tx: center.x, ty: center.y)
    }

    /// A small arrow on the horizon circle that points outwards at `azimuth`: how the chart shows
    /// something that is below the horizon.
    func rimArrow(towards azimuth: Double) -> Path {
        var arrow = Path()
        arrow.move(to: rimPoint(azimuth: azimuth, outside: 12))
        arrow.addLine(to: rimPoint(azimuth: azimuth - 3.5, outside: 2))
        arrow.addLine(to: rimPoint(azimuth: azimuth + 3.5, outside: 2))
        arrow.closeSubpath()
        return arrow
    }
}
