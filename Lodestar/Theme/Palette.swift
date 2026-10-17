import SwiftUI

/// The colours used throughout the app. Lodestar has two palettes: a dark "normal" palette and a
/// pure-red "night" palette that preserves dark adaptation (no green or blue light at all).
struct Palette: Equatable {
    var isNight: Bool
    /// Screen background.
    var background: Color
    /// Cards, panels and list rows.
    var surface: Color
    /// Raised elements on top of `surface` (selected rows, buttons).
    var surfaceRaised: Color
    /// Hairlines and card borders.
    var stroke: Color
    var primaryText: Color
    var secondaryText: Color
    var tertiaryText: Color
    /// Interactive elements and highlights.
    var accent: Color
    /// Foreground drawn on top of `accent` fills.
    var onAccent: Color
    /// Guidance arrows and the target marker.
    var guidance: Color
    /// "On target" state.
    var positive: Color
    var warning: Color
    var critical: Color
    // Sky overlay
    var constellationLine: Color
    var constellationLabel: Color
    var horizonLine: Color
    var gridLine: Color
    var deepSkyMarker: Color
    var planetMarker: Color
    var milkyWay: Color
    var dslrFrame: Color

    /// Star colour for a B−V colour index (normal mode), or a red of matching brightness at night.
    func starColor(colorIndex: Double?) -> Color {
        if isNight { return guidance }
        guard let bv = colorIndex, bv.isFinite else { return Color(white: 0.95) }
        // Approximate B−V → sRGB tint, kept pale so faint stars stay legible.
        let t = min(max((bv + 0.3) / 2.0, 0), 1)
        let red = 0.72 + 0.28 * min(1, t * 1.6)
        let green = 0.80 + 0.12 * (1 - abs(t - 0.4) * 1.6)
        let blue = 1.0 - 0.55 * t
        return Color(red: red, green: max(0.6, min(green, 1)), blue: max(0.45, blue))
    }

    static let normal = Palette(
        isNight: false,
        background: Color(red: 0.020, green: 0.027, blue: 0.051),
        surface: Color(red: 0.063, green: 0.078, blue: 0.122),
        surfaceRaised: Color(red: 0.094, green: 0.114, blue: 0.172),
        stroke: Color(red: 0.149, green: 0.188, blue: 0.290),
        primaryText: Color(red: 0.949, green: 0.957, blue: 0.973),
        secondaryText: Color(red: 0.655, green: 0.686, blue: 0.761),
        tertiaryText: Color(red: 0.420, green: 0.451, blue: 0.537),
        accent: Color(red: 0.961, green: 0.722, blue: 0.255),
        onAccent: Color(red: 0.08, green: 0.06, blue: 0.02),
        guidance: Color(red: 0.961, green: 0.722, blue: 0.255),
        positive: Color(red: 0.298, green: 0.851, blue: 0.392),
        warning: Color(red: 1.0, green: 0.624, blue: 0.039),
        critical: Color(red: 1.0, green: 0.271, blue: 0.227),
        constellationLine: Color(red: 0.47, green: 0.55, blue: 0.80).opacity(0.45),
        constellationLabel: Color(red: 0.55, green: 0.62, blue: 0.85).opacity(0.8),
        horizonLine: Color(red: 0.30, green: 0.62, blue: 0.95).opacity(0.8),
        gridLine: Color(white: 1).opacity(0.10),
        deepSkyMarker: Color(red: 0.55, green: 0.80, blue: 0.95),
        planetMarker: Color(red: 1.0, green: 0.80, blue: 0.45),
        milkyWay: Color(red: 0.70, green: 0.75, blue: 0.95).opacity(0.10),
        dslrFrame: Color(red: 0.961, green: 0.722, blue: 0.255).opacity(0.9)
    )

    /// Pure-red palette. `intensity` (0.25…1) scales every element's brightness.
    static func night(intensity: Double) -> Palette {
        let k = min(max(intensity, 0.25), 1)
        func red(_ level: Double, _ opacity: Double = 1) -> Color {
            Color(red: min(1, level * k), green: 0, blue: 0).opacity(opacity)
        }
        return Palette(
            isNight: true,
            background: .black,
            surface: red(0.10),
            surfaceRaised: red(0.16),
            stroke: red(0.26),
            primaryText: red(0.92),
            secondaryText: red(0.66),
            tertiaryText: red(0.44),
            accent: red(1.0),
            onAccent: .black,
            guidance: red(1.0),
            positive: red(1.0),
            warning: red(0.85),
            critical: red(1.0),
            constellationLine: red(0.55, 0.55),
            constellationLabel: red(0.6, 0.8),
            horizonLine: red(0.7, 0.8),
            gridLine: red(0.5, 0.18),
            deepSkyMarker: red(0.8),
            planetMarker: red(1.0),
            milkyWay: red(0.6, 0.10),
            dslrFrame: red(0.9, 0.9)
        )
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.normal
}

extension EnvironmentValues {
    /// The active colour palette (normal or night). Set once at the root of each window/sheet.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
