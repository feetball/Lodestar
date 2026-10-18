import SwiftUI

/// The app's look for widgets: the dark navy of its "normal" palette with the gold accent. These are the
/// `Palette.normal` values of the app; widgets follow the system, so there is no night-mode variant. In the tinted
/// and vibrant rendering modes the system recolours whatever is marked `widgetAccentable()`.
enum TonightStyle {
    static let background = Color(red: 0.020, green: 0.027, blue: 0.051)
    static let surfaceRaised = Color(red: 0.094, green: 0.114, blue: 0.172)
    static let primaryText = Color(red: 0.949, green: 0.957, blue: 0.973)
    static let secondaryText = Color(red: 0.655, green: 0.686, blue: 0.761)
    static let tertiaryText = Color(red: 0.420, green: 0.451, blue: 0.537)
    static let accent = Color(red: 0.961, green: 0.722, blue: 0.255)

    /// The widget background: a soft glow in the top corner fading into the deep night colour.
    static var gradient: LinearGradient {
        LinearGradient(colors: [surfaceRaised, background], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The Moon's phase drawn the way the app's Tonight card and the Android widgets draw it: the lit part is bounded by
/// the limb of the lit side and the terminator, an ellipse as wide as the phase says, inside the outline of the whole
/// disc. Phases are drawn as seen from the northern hemisphere (the lit side of a waxing Moon on the right) and
/// mirrored south of the equator. It is painted in the foreground style, so the system can tint it.
struct TonightMoonDisc: View {
    let fraction: Double
    let isWaxing: Bool
    let isSouthernHemisphere: Bool
    /// The side of the square it is drawn in, in points.
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.foreground)
                .opacity(0.2)
            TonightMoonLitShape(fraction: fraction, isMirrored: isWaxing == isSouthernHemisphere)
                .fill(.foreground)
            Circle()
                .strokeBorder(.foreground, lineWidth: max(size * 0.07, 0.8))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The lit part of the Moon's disc.
struct TonightMoonLitShape: Shape {
    /// The lit fraction of the disc, 0 (new) to 1 (full).
    let fraction: Double
    /// Whether the lit side is on the left.
    let isMirrored: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let lit = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        // The terminator's half width: the radius at new and full Moon, 0 at the quarters; it bulges towards the lit
        // side for a crescent and away from it for a gibbous Moon.
        let reach = radius * CGFloat(1 - 2 * lit)
        let side: CGFloat = isMirrored ? -1 : 1
        let steps = 48
        var path = Path()
        for step in 0...steps {
            let angle = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
            let point = CGPoint(x: center.x + side * radius * CGFloat(cos(angle)),
                                y: center.y + radius * CGFloat(sin(angle)))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        for step in 0...steps {
            let angle = Double.pi * Double(step) / Double(steps)
            path.addLine(to: CGPoint(x: center.x + side * reach * CGFloat(sin(angle)),
                                     y: center.y + radius * CGFloat(cos(angle))))
        }
        path.closeSubpath()
        return path
    }
}
