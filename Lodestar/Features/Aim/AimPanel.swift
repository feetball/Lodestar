import SwiftUI

extension View {
    /// A translucent card for the panels over the sky, so the picture stays visible behind it. A card with a lot of
    /// text on it (the mount's, the target's) takes a higher `opacity`, so the sky's labels and rings do not read
    /// through its words.
    func aimPanel(_ palette: Palette, padding: CGFloat = 10, opacity: Double = 0.88) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.surface.opacity(opacity)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.stroke, lineWidth: 0.5))
    }
}

/// A square-ish control for the bar at the bottom: a symbol over a caption, filled when its function is on.
struct AimControlButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var isOn = false
    var minHeight: CGFloat = 54

    /// A disabled button dims its label and its edge, not its plate, so the sky behind it does not show through.
    private var dimming: Double { isEnabled ? 1 : 0.4 }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? palette.onAccent : palette.accent)
            .opacity(dimming)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOn ? palette.accent.opacity(dimming) : palette.surface.opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOn ? Color.clear : palette.stroke.opacity(dimming), lineWidth: 0.75))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
