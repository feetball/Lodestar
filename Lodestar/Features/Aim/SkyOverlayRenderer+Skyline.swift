import SwiftUI
import LodestarKit

// The ground below the site's recorded skyline.
extension SkyOverlayRenderer {
    /// Opacity of the ground's shade over whatever lies behind it: the camera picture and the sky.
    private static let groundShade = 0.7

    /// Shades the ground below the skyline in the palette's background colour, and draws the skyline itself. Nothing is
    /// drawn for an open horizon.
    func drawSkyline(in context: GraphicsContext) {
        guard let skyline = content?.skyline else { return }
        var ground = Path()
        for wedge in skyline.wedges where boresight.angle(to: wedge.center) <= wedge.radius + viewRadius {
            let visible = frustum.clip(polygon: wedge.vertices)
            guard visible.count >= 3 else { continue }
            ground.addLines(projector.points(visible).compactMap { $0 })
            ground.closeSubpath()
        }
        if !ground.isEmpty {
            context.fill(ground, with: .color(palette.background.opacity(Self.groundShade)))
        }
        var line = AimWorldPath()
        line.addPolyline(skyline.line, frustum: frustum)
        context.stroke(line.path(projecting: projector), with: .color(palette.horizonLine),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }
}
