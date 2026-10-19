import SwiftUI
import LodestarKit

// The panels of the mosaic being shot.
extension SkyOverlayRenderer {
    /// The most panel numbers written at once.
    private static let panelNumberLimit = 24
    /// Panels narrower than this many points on the screen get no number.
    private static let panelNumberMinimumWidth = 36.0

    /// Outlines every panel: the one being aimed at is highlighted and tinted, panels already shot are dimmed, the next
    /// one is dashed, the rest are drawn lightly. The numbers are places in the shooting order.
    mutating func drawMosaic(in context: GraphicsContext) {
        guard let mosaic, let panels = content?.snapshot.mosaic, !panels.isEmpty else { return }
        var done = AimWorldPath(), next = AimWorldPath(), later = AimWorldPath(), current = AimWorldPath()
        var currentFill = Path()
        var numbered = 0
        let numberStyle = AimLabelStyle(size: 12, weight: .semibold, color: palette.dslrFrame)
        let panelWidth = min(configuration.lensFrame.horizontal, configuration.lensFrame.vertical) * pointsPerDegree
        for panel in panels {
            switch mosaic.state(ofShootingPosition: panel.shootingPosition) {
            case .done:
                done.addPolyline(panel.corners, closed: true, frustum: frustum)
                continue
            case .current:
                current.addPolyline(panel.corners, closed: true, frustum: frustum)
                let visible = frustum.clip(polygon: panel.corners)
                if visible.count >= 3 {
                    currentFill.addLines(projector.points(visible).compactMap { $0 })
                    currentFill.closeSubpath()
                }
                continue
            case .next:
                next.addPolyline(panel.corners, closed: true, frustum: frustum)
            case .later:
                later.addPolyline(panel.corners, closed: true, frustum: frustum)
            }
            if numbered < Self.panelNumberLimit, panelWidth >= Self.panelNumberMinimumWidth,
               let point = projector.point(panel.center), isVisible(point, margin: 0) {
                addLabel("\(panel.shootingPosition + 1)", near: point, style: numberStyle, priority: 9)
                numbered += 1
            }
        }
        context.fill(currentFill, with: .color(palette.guidance.opacity(0.14)))
        context.stroke(done.path(projecting: projector), with: .color(palette.positive.opacity(0.4)), lineWidth: 1)
        context.stroke(later.path(projecting: projector), with: .color(palette.dslrFrame.opacity(0.4)), lineWidth: 1)
        context.stroke(next.path(projecting: projector), with: .color(palette.dslrFrame.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        context.stroke(current.path(projecting: projector), with: .color(palette.guidance),
                       style: StrokeStyle(lineWidth: 3, lineJoin: .round))
    }
}
