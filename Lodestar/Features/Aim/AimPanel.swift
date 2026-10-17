import SwiftUI

extension View {
    /// A translucent card for the panels over the sky, so the picture stays visible behind it.
    func aimPanel(_ palette: Palette, padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.surface.opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.stroke, lineWidth: 0.5))
    }
}

/// A square-ish control for the bar at the bottom: a symbol over a caption, filled when its function is on.
struct AimControlButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var isOn = false
    var minHeight: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? palette.onAccent : palette.accent)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOn ? palette.accent : palette.surface.opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOn ? Color.clear : palette.stroke, lineWidth: 0.75))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
