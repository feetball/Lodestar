import SwiftUI

/// How a label on the sky looks.
struct AimLabelStyle {
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
}

/// Collects the labels of a frame and draws as many as the budget allows, most important first, skipping any that
/// would overlap one already drawn. Labels are turned with the HUD so they read upright for a sideways phone.
struct AimLabelQueue {
    /// The most labels drawn in one frame.
    static let budget = 40

    private struct Request {
        let text: String
        let center: CGPoint
        let style: AimLabelStyle
        let priority: Int
    }

    private var requests: [Request] = []

    /// Asks for `text` to be centred on `center`. Lower `priority` values are drawn first.
    mutating func add(_ text: String, at center: CGPoint, style: AimLabelStyle, priority: Int) {
        requests.append(Request(text: text, center: center, style: style, priority: priority))
    }

    func draw(in context: GraphicsContext, bounds: CGRect, rotation: AimHUDRotation) {
        var occupied: [CGRect] = []
        let ordered = requests.enumerated()
            .sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }
            .map(\.element)
        for request in ordered {
            guard occupied.count < Self.budget else { break }
            guard !request.text.isEmpty, bounds.contains(request.center) else { continue }
            var text = context.resolve(Text(request.text).font(.system(size: request.style.size, weight: request.style.weight)))
            text.shading = .color(request.style.color)
            let measured = text.measure(in: CGSize(width: 260, height: 60))
            let size = rotation.swapsAxes ? CGSize(width: measured.height, height: measured.width) : measured
            let box = CGRect(x: request.center.x - size.width / 2 - 3, y: request.center.y - size.height / 2 - 2,
                             width: size.width + 6, height: size.height + 4)
            guard !occupied.contains(where: { $0.intersects(box) }) else { continue }
            occupied.append(box)
            var layer = context
            layer.translateBy(x: request.center.x, y: request.center.y)
            if rotation != .upright { layer.rotate(by: .degrees(rotation.degrees)) }
            layer.draw(text, at: .zero, anchor: .center)
        }
    }
}
