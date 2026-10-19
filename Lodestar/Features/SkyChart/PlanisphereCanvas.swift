import SwiftUI
import LodestarKit

/// The all-sky chart: draws a `SkyChartContent` through a `PlanisphereViewport`.
///
/// Orientation: the zenith is at the centre of the horizon circle, north is at the top and east to
/// the left, as when lying down and looking up. A frame only transforms and fills what the content
/// already holds: line and polygon paths come ready-made, and the text labels are canvas symbols
/// that the renderer looks up by id and places.
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
        } symbols: {
            PlanisphereSymbols(content: content, palette: palette, mosaic: mosaic)
        }
        .accessibilityHidden(true)
    }
}

/// The text labels of the chart as canvas symbols.
///
/// Symbols are views in the canvas's own graph, so the labels are laid out when they change, not
/// when the canvas redraws. They sit in a view of their own that is equal for as long as the scene
/// and palette are, so zooming and panning do not even rebuild them.
private struct PlanisphereSymbols: View, Equatable {
    let content: SkyChartContent
    let palette: Palette
    let mosaic: MosaicDisplay?

    nonisolated static func == (lhs: PlanisphereSymbols, rhs: PlanisphereSymbols) -> Bool {
        lhs.content == rhs.content && lhs.palette == rhs.palette && lhs.mosaic == rhs.mosaic
    }

    var body: some View {
        ForEach(content.scene.labels) { label in
            Text(label.text)
                .font(label.style.font)
                .kerning(label.style.kerning)
                .textCase(label.style == .constellation ? .uppercase : nil)
                .foregroundStyle(label.style.color(in: palette))
                .tag(label.id)
        }
        if let mosaic, mosaic.step < mosaic.count {
            Text("Panel \(mosaic.step + 1) of \(mosaic.count)")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(palette.guidance)
                .tag(PlanisphereRenderer.mosaicLabelID)
        }
        ForEach(PlanisphereCardinal.all) { cardinal in
            Text(cardinal.title)
                .font(.system(size: cardinal.isPrincipal ? 16 : 11, weight: .bold))
                .foregroundStyle(cardinal.title == "N" ? palette.accent : palette.primaryText)
                .tag(cardinal.id)
        }
        ForEach(PlanisphereRenderer.altitudeCircles, id: \.self) { altitude in
            Text(verbatim: "\(Int(altitude))\u{00B0}")
                .font(.system(size: 9))
                .foregroundStyle(palette.tertiaryText)
                .tag(PlanisphereRenderer.altitudeLabelID(altitude))
        }
    }
}

private extension SkyChartLabel.Style {
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
