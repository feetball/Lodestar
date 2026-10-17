import SwiftUI
import LodestarKit

/// A small drawing of a phone mount, seen the way the photographer sees it. Drawn with palette colours only.
struct MountIllustration: View {
    /// Coordinate space of the drawing code below.
    private static let drawingSize: CGFloat = 64

    @Environment(\.palette) private var palette
    let layout: MountLayout
    var side: CGFloat = 56

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / Self.drawingSize
            context.scaleBy(x: scale, y: scale)
            switch layout {
            case .backCamera(let rotation): drawBackCamera(&context, rotation: rotation)
            case .flatOnTop(let topEdgeForward): drawFlatOnTop(&context, topEdgeForward: topEdgeForward)
            case .custom: drawCustom(&context)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var lineStyle: StrokeStyle {
        StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
    }

    /// The camera seen from behind (its lens, a circle with a cross, points away from the viewer) with the phone on
    /// top of it, turned by `rotation` degrees; the small bar marks the phone's top edge.
    private func drawBackCamera(_ context: inout GraphicsContext, rotation: Double) {
        let body = Path(roundedRect: CGRect(x: 6, y: 41, width: 52, height: 20), cornerRadius: 4)
        context.fill(body, with: .color(palette.surfaceRaised))
        context.stroke(body, with: .color(palette.stroke), style: lineStyle)
        context.stroke(Path(roundedRect: CGRect(x: 25, y: 37, width: 14, height: 5), cornerRadius: 2),
                       with: .color(palette.stroke), style: lineStyle)
        context.stroke(Path(ellipseIn: CGRect(x: 25, y: 44, width: 14, height: 14)),
                       with: .color(palette.accent), style: lineStyle)
        var cross = Path()
        cross.move(to: CGPoint(x: 29, y: 48))
        cross.addLine(to: CGPoint(x: 35, y: 54))
        cross.move(to: CGPoint(x: 35, y: 48))
        cross.addLine(to: CGPoint(x: 29, y: 54))
        context.stroke(cross, with: .color(palette.accent), style: lineStyle)

        var phone = context
        phone.translateBy(x: 32, y: 19)
        phone.rotate(by: .degrees(rotation))
        let screen = Path(roundedRect: CGRect(x: -9, y: -16, width: 18, height: 32), cornerRadius: 4)
        phone.fill(screen, with: .color(palette.surface))
        phone.stroke(screen, with: .color(palette.primaryText), style: lineStyle)
        phone.fill(Path(roundedRect: CGRect(x: -3.5, y: -13, width: 7, height: 2.5), cornerRadius: 1.25),
                   with: .color(palette.primaryText))
    }

    /// The camera from the side, the lens pointing right (the photographer stands on the left), with the phone
    /// lying on top; the dot marks the phone's top edge and the arrow the direction of the lens.
    private func drawFlatOnTop(_ context: inout GraphicsContext, topEdgeForward: Bool) {
        let body = Path(roundedRect: CGRect(x: 6, y: 35, width: 34, height: 22), cornerRadius: 3)
        context.fill(body, with: .color(palette.surfaceRaised))
        context.stroke(body, with: .color(palette.stroke), style: lineStyle)
        let lens = Path(roundedRect: CGRect(x: 40, y: 39, width: 16, height: 14), cornerRadius: 2)
        context.fill(lens, with: .color(palette.surfaceRaised))
        context.stroke(lens, with: .color(palette.stroke), style: lineStyle)

        let phone = Path(roundedRect: CGRect(x: 9, y: 28, width: 29, height: 5), cornerRadius: 1.5)
        context.fill(phone, with: .color(palette.surface))
        context.stroke(phone, with: .color(palette.primaryText), style: lineStyle)
        let markerX: CGFloat = topEdgeForward ? 34.5 : 12.5
        context.fill(Path(ellipseIn: CGRect(x: markerX - 1.75, y: 28.75, width: 3.5, height: 3.5)),
                     with: .color(palette.primaryText))

        var arrow = Path()
        arrow.move(to: CGPoint(x: 42, y: 20))
        arrow.addLine(to: CGPoint(x: 58, y: 20))
        arrow.move(to: CGPoint(x: 54, y: 16.5))
        arrow.addLine(to: CGPoint(x: 58, y: 20))
        arrow.addLine(to: CGPoint(x: 54, y: 23.5))
        context.stroke(arrow, with: .color(palette.accent), style: lineStyle)
    }

    private func drawCustom(_ context: inout GraphicsContext) {
        let phone = Path(roundedRect: CGRect(x: 22, y: 10, width: 20, height: 36), cornerRadius: 4)
        context.stroke(phone, with: .color(palette.primaryText), style: lineStyle)
        var axis = Path()
        axis.move(to: CGPoint(x: 32, y: 52))
        axis.addLine(to: CGPoint(x: 32, y: 60))
        context.stroke(axis, with: .color(palette.accent), style: lineStyle)
    }
}
