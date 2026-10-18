import SwiftUI
import LodestarKit

/// A comet or an asteroid on the planisphere: a dot and, for a comet, the direction of its ion tail. The coordinates
/// are chart coordinates (zenith at the origin, horizon radius 1).
struct SkyChartSmallBodyMarker: Sendable, Identifiable {
    let object: CelestialObject
    let point: CGPoint
    /// The chart point one degree along the tail of a comet; `nil` for an asteroid or a tail with no direction.
    let tailPoint: CGPoint?
    let magnitude: Double?
    let horizontal: HorizontalCoordinate
    let isComet: Bool
    let isTarget: Bool

    var id: String { object.id }
    var name: String { SmallBodyText.displayName(object) }
}

/// Turns the snapshot's comets and asteroids into chart markers, labels and pickables.
enum SmallBodyChartMarkers {
    /// The most bodies the screen-reader summary names.
    private static let spokenLimit = 5

    /// The markers of the bodies above the horizon.
    static func build(_ markers: [SkySnapshot.SmallBodyMarker], targetID: String?) -> [SkyChartSmallBodyMarker] {
        markers.filter { $0.direction.z >= 0 }.map { marker in
            SkyChartSmallBodyMarker(
                object: marker.object, point: PlanisphereProjection.chartPoint(marker.direction),
                tailPoint: marker.tailEnd.map(PlanisphereProjection.retractedChartPoint),
                magnitude: marker.magnitude, horizontal: marker.horizontal, isComet: marker.isComet,
                isTarget: marker.id == targetID)
        }
    }

    /// The names. The target already has its own label; the others appear from the zoom their brightness needs.
    static func labels(_ markers: [SkyChartSmallBodyMarker]) -> [SkyChartLabel] {
        markers.filter { !$0.isTarget }.map { marker in
            let rank = Int(min(max(marker.magnitude ?? 12, -30), 30))
            return SkyChartLabel(id: "smallBody.\(marker.id)", text: marker.name, style: .body, point: marker.point,
                                 priority: (marker.isComet ? 75 : 55) - rank,
                                 minimumZoom: SmallBodyMarkerStyle.labelZoom(magnitude: marker.magnitude), offset: 9)
        }
    }

    static func pickables(_ markers: [SkyChartSmallBodyMarker]) -> [SkyChartPickable] {
        markers.map { SkyChartPickable(id: $0.id, kind: .smallBody, point: $0.point, object: $0.object) }
    }

    /// "Comets and asteroids above the horizon. Tsuchinshan-ATLAS, comet, altitude 34 degrees, southwest. \u{2026}", or
    /// `nil` when none is shown.
    static func spokenSummary(_ markers: [SkyChartSmallBodyMarker]) -> String? {
        guard !markers.isEmpty else { return nil }
        let named = markers.prefix(spokenLimit).map(description).joined(separator: " ")
        let more = markers.count > spokenLimit ? " And \(markers.count - spokenLimit) more." : ""
        return "Comets and asteroids above the horizon. \(named)\(more)"
    }

    /// "Tsuchinshan-ATLAS, comet, altitude 34 degrees, southwest."
    static func description(_ marker: SkyChartSmallBodyMarker) -> String {
        let direction = AngleFormatter.compassPoint(azimuth: marker.horizontal.azimuth).fullName.lowercased()
        let kind = marker.object.category.displayName.lowercased()
        return "\(marker.name), \(kind), altitude \(Int(marker.horizontal.altitude.rounded())) degrees, \(direction)."
    }
}

extension PlanisphereRenderer {
    /// Draws the comets and asteroids of the scene: a dot for each, with a ring and a short line along the ion tail
    /// for a comet. Everything goes into four paths, so a frame makes no shape per body. Returns the rectangles the
    /// markers occupy, so that labels keep clear of them.
    func drawSmallBodies(_ context: inout GraphicsContext) -> [CGRect] {
        let markers = content.scene.smallBodies
        guard !markers.isEmpty else { return [] }
        let bounds = CGRect(origin: .zero, size: viewport.size).insetBy(dx: -12, dy: -12)
        var cometDots = Path(), asteroidDots = Path(), rings = Path(), tails = Path()
        var occupied: [CGRect] = []
        occupied.reserveCapacity(markers.count)
        for marker in markers {
            let center = viewport.screen(marker.point)
            guard bounds.contains(center) else { continue }
            let radius = SmallBodyMarkerStyle.dotRadius(magnitude: marker.magnitude, isComet: marker.isComet)
            var reach = radius
            if marker.isComet {
                if let tailPoint = marker.tailPoint {
                    let end = viewport.screen(tailPoint)
                    let dx = end.x - center.x, dy = end.y - center.y
                    let length = hypot(dx, dy)
                    if length > 1e-3 {
                        let tail = SmallBodyMarkerStyle.tailLength(magnitude: marker.magnitude)
                        tails.move(to: center)
                        tails.addLine(to: CGPoint(x: center.x + dx * tail / length, y: center.y + dy * tail / length))
                        reach = max(reach, tail)
                    }
                }
                rings.addEllipse(in: PlanisphereBounds.square(around: center, radius: radius + 2.5))
                cometDots.addEllipse(in: PlanisphereBounds.square(around: center, radius: radius))
            } else {
                asteroidDots.addEllipse(in: PlanisphereBounds.square(around: center, radius: radius))
            }
            occupied.append(PlanisphereBounds.square(around: center, radius: max(reach, radius + 2.5)))
        }
        let cometColor = SmallBodyMarkerStyle.color(palette, isComet: true)
        let asteroidColor = SmallBodyMarkerStyle.color(palette, isComet: false)
        context.stroke(tails, with: .color(cometColor.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        context.stroke(rings, with: .color(cometColor.opacity(0.5)), lineWidth: 1)
        context.fill(cometDots, with: .color(cometColor))
        context.fill(asteroidDots, with: .color(asteroidColor))
        return occupied
    }
}

extension SmallBodyMarkerStyle {
    /// The marker's colour: icy blue for a comet, the quiet text colour for an asteroid. Palette colours only.
    static func color(_ palette: Palette, isComet: Bool) -> Color {
        isComet ? palette.deepSkyMarker : palette.secondaryText
    }
}
