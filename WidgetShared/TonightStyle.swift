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

/// A phase symbol of the Moon, mirrored south of the equator where the lit side is on the other hand.
struct TonightMoonGlyph: View {
    let symbolName: String
    let isSouthernHemisphere: Bool

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.monochrome)
            .scaleEffect(x: isSouthernHemisphere ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }
}
