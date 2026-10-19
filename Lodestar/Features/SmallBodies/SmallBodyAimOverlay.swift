import SwiftUI
import LodestarKit

/// The comets and asteroids of the Aim overlay.
extension SkyOverlayRenderer {
    /// The most names written in one frame.
    private static let smallBodyNameLimit = 6
    /// Bodies below the horizon are drawn this much fainter, like the stars below it.
    private static let smallBodyBelowHorizonOpacity = 0.4

    /// Draws a dot for each comet and asteroid of the sky (bigger for the brighter) and, for a comet, a ring and a
    /// short line along its ion tail. Bodies the recorded skyline hides are left out; the target is named by the
    /// reticle. Each body is projected once; the shapes of a group go into one path.
    mutating func drawSmallBodies(in context: GraphicsContext) {
        guard let content, !content.snapshot.smallBodies.isEmpty else { return }
        let mask = content.skyline?.mask
        let targetID = content.snapshot.target?.object.id
        let cometStyle = AimLabelStyle(size: 11, weight: .medium, color: SmallBodyMarkerStyle.color(palette, isComet: true))
        let asteroidStyle = AimLabelStyle(size: 11, weight: .medium,
                                          color: SmallBodyMarkerStyle.color(palette, isComet: false))
        // Comets and asteroids, each above and below the horizon.
        var groups = [SmallBodyPaths](repeating: SmallBodyPaths(), count: 4)
        var names = 0
        for marker in content.snapshot.smallBodies {
            if let mask, mask.isBelow(marker.direction) { continue }
            guard let point = projector.point(marker.direction), isVisible(point, margin: 40) else { continue }
            let radius = SmallBodyMarkerStyle.dotRadius(magnitude: marker.magnitude, isComet: marker.isComet)
            let isBelow = marker.direction.z < 0
            let index = (marker.isComet ? 0 : 2) + (isBelow ? 1 : 0)
            if marker.isComet {
                if let end = marker.tailEnd, let tipPoint = projector.point(end) {
                    let dx = tipPoint.x - point.x, dy = tipPoint.y - point.y
                    let length = hypot(dx, dy)
                    if length > 1e-3 {
                        let tail = SmallBodyMarkerStyle.tailLength(magnitude: marker.magnitude)
                        groups[index].tails.move(to: point)
                        groups[index].tails.addLine(to: CGPoint(x: point.x + dx * tail / length,
                                                                y: point.y + dy * tail / length))
                    }
                }
                groups[index].rings.addEllipse(in: CGRect(x: point.x - radius - 2.5, y: point.y - radius - 2.5,
                                                          width: (radius + 2.5) * 2, height: (radius + 2.5) * 2))
            }
            groups[index].dots.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                                     width: radius * 2, height: radius * 2))
            if marker.id != targetID, names < Self.smallBodyNameLimit,
               SmallBodyMarkerStyle.isNamed(magnitude: marker.magnitude, fieldOfView: fieldOfView) {
                addLabel(SmallBodyText.displayName(marker.object), near: point,
                         offset: CGSize(width: 0, height: radius + 12), style: marker.isComet ? cometStyle : asteroidStyle,
                         priority: 3)
                names += 1
            }
        }
        for (index, group) in groups.enumerated() where !group.dots.isEmpty {
            let color = SmallBodyMarkerStyle.color(palette, isComet: index < 2)
                .opacity(index % 2 == 1 ? Self.smallBodyBelowHorizonOpacity : 1)
            if !group.tails.isEmpty {
                context.stroke(group.tails, with: .color(color.opacity(0.75)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            if !group.rings.isEmpty {
                context.stroke(group.rings, with: .color(color.opacity(0.5)), lineWidth: 1)
            }
            context.fill(group.dots, with: .color(color))
        }
    }
}

/// The shapes of one group of markers.
private struct SmallBodyPaths {
    var dots = Path()
    var rings = Path()
    var tails = Path()
}
