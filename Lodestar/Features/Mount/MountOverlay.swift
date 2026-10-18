import SwiftUI
import LodestarKit

/// Where the connected mount points, as the Aim overlay draws it.
struct AimMountMarker: Sendable {
    /// The direction in the local sky (east, north, up), with refraction, like the other things the overlay draws.
    let direction: Vector3
    /// The mount is slewing or nudging.
    let isMoving: Bool
}

extension AimViewModel {
    /// The marker for the mount's reported position, or `nil` without a connected mount or a location. Cheap enough to ask
    /// for every frame: the direction is worked out at most once a second.
    func mountMarker() -> AimMountMarker? {
        // Most people have no mount: answer that before doing any work.
        let service = MountService.shared
        guard service.isConnected, let observer = app.observerContext?.observer,
              let found = service.overlayDirection(observer: observer, at: Date()) else { return nil }
        return AimMountMarker(direction: found.direction, isMoving: found.isMoving)
    }
}

// The mount's marker: a diamond with a dot, labelled "Mount". Off the screen it gets the same arrow at the edge as the target.
extension SkyOverlayRenderer {
    mutating func drawMountMarker(in context: GraphicsContext) {
        guard let marker = mountMarker else { return }
        let color = palette.deepSkyMarker
        guard let point = projector.point(marker.direction), isVisible(point, margin: 0) else {
            drawEdgeIndicator(toward: marker.direction, color: color, in: context)
            return
        }
        let radius: CGFloat = 17
        var diamond = Path()
        diamond.move(to: CGPoint(x: point.x, y: point.y - radius))
        diamond.addLine(to: CGPoint(x: point.x + radius, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + radius))
        diamond.addLine(to: CGPoint(x: point.x - radius, y: point.y))
        diamond.closeSubpath()
        context.stroke(diamond, with: .color(color),
                       style: StrokeStyle(lineWidth: marker.isMoving ? 2 : 3, lineJoin: .round))
        context.fill(ellipse(at: point, radius: 2), with: .color(color))
        addLabel("Mount", near: point, offset: CGSize(width: 0, height: radius + 14),
                 style: AimLabelStyle(size: 12, weight: .bold, color: color), priority: 1)
    }
}
