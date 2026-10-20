import SwiftUI
import LodestarKit

/// The all-sky chart: draws a `SkyChartContent` through a `PlanisphereViewport`.
///
/// Orientation: the zenith is at the centre of the horizon circle, north is at the top and east to
/// the left, as when lying down and looking up. A frame only transforms and fills what the content
/// already holds: line and polygon paths come ready-made, and the renderer turns the few dozen labels
/// that fit on the screen into text and places them.
///
/// The labels are drawn directly, like the labels of the Aim screen, and not as canvas symbols: the symbols of a
/// canvas are a view graph of their own, one view for every label of the scene (several hundred), and SwiftUI stopped
/// the app with an assertion inside its symbol handling when the Sky tab opened.
struct PlanisphereCanvas: View, Equatable {
    let content: SkyChartContent
    let viewport: PlanisphereViewport
    let palette: Palette
    let layers: SkyChartLayerOptions
    /// Where the selected object is, in the local frame; it gets a ring.
    let selectedDirection: Vector3?
    /// The step of the mosaic being shot, or `nil` without one.
    let mosaic: MosaicDisplay?

    nonisolated static func == (lhs: PlanisphereCanvas, rhs: PlanisphereCanvas) -> Bool {
        lhs.content == rhs.content && lhs.viewport == rhs.viewport && lhs.palette == rhs.palette
            && lhs.layers == rhs.layers && lhs.selectedDirection == rhs.selectedDirection && lhs.mosaic == rhs.mosaic
    }

    var body: some View {
        let renderer = PlanisphereRenderer(content: content, viewport: viewport, palette: palette, layers: layers,
                                           selectedDirection: selectedDirection, mosaic: mosaic)
        Canvas { context, _ in
            renderer.draw(into: &context)
        }
        .accessibilityHidden(true)
    }
}

extension SkyChartLabel.Style {
    var font: Font {
        switch self {
        case .constellation: return .system(size: 9.5, weight: .regular)
        case .star: return .system(size: 10.5, weight: .medium)
        case .deepSky: return .system(size: 10, weight: .regular)
        case .body: return .system(size: 11.5, weight: .semibold)
        case .target: return .system(size: 12, weight: .bold)
        }
    }

    var kerning: CGFloat {
        self == .constellation ? 0.8 : 0
    }

    func color(in palette: Palette) -> Color {
        switch self {
        case .constellation: return palette.constellationLabel
        case .star: return palette.secondaryText
        case .deepSky: return palette.deepSkyMarker
        case .body: return palette.primaryText
        case .target: return palette.guidance
        }
    }
}
