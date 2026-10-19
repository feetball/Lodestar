import SwiftUI
import LodestarKit

/// A compass direction written around the horizon circle.
struct PlanisphereCardinal: Identifiable {
    let title: String
    let azimuth: Double
    var id: String { "cardinal.\(title)" }
    var isPrincipal: Bool { title.count == 1 }

    static let all: [PlanisphereCardinal] = [
        PlanisphereCardinal(title: "N", azimuth: 0), PlanisphereCardinal(title: "NE", azimuth: 45),
        PlanisphereCardinal(title: "E", azimuth: 90), PlanisphereCardinal(title: "SE", azimuth: 135),
        PlanisphereCardinal(title: "S", azimuth: 180), PlanisphereCardinal(title: "SW", azimuth: 225),
        PlanisphereCardinal(title: "W", azimuth: 270), PlanisphereCardinal(title: "NW", azimuth: 315),
    ]
}

/// Draws the chart. A plain value so the canvas closure captures everything it needs by copy.
struct PlanisphereRenderer {
    /// Altitudes (degrees) of the circles drawn inside the horizon circle.
    static let altitudeCircles: [Double] = [30, 60]
    /// The most text labels placed in one frame.
    private static let labelLimit = 90

    let content: SkyChartContent
    let viewport: PlanisphereViewport
    let palette: Palette
    let layers: SkyChartLayerOptions
    let selectedDirection: Vector3?
    /// The step of the mosaic being shot, or `nil` without one.
    let mosaic: MosaicDisplay?

    /// The zoom from which the chart draws obscure deep-sky objects (prominence 4).
    private static let obscureMinimumZoom: CGFloat = 2

    /// Opacity of the ground's shade over the sky behind the skyline.
    private static let groundShade = 0.7

    private var scene: SkyChartScene { content.scene }

    /// The screen, grown a little so that markers half outside it are still drawn.
    private var visibleBounds: CGRect {
        CGRect(origin: .zero, size: viewport.size).insetBy(dx: -12, dy: -12)
    }

    static func altitudeLabelID(_ altitude: Double) -> String {
        "altitude.\(Int(altitude))"
    }

    /// The id of the canvas symbol that names the mosaic panel being shot.
    static let mosaicLabelID = "mosaic.panel"

    /// Draws the whole chart. The compass letters and ticks go first, then the sky inside the horizon
    /// circle (on a copy of the context that is clipped to it), then the horizon ring and the labels.
    func draw(into context: inout GraphicsContext) {
        let disc = Path(ellipseIn: viewport.discRect)
        context.fill(disc, with: .color(palette.surface))
        var occupied = drawRim(&context)

        var sky = context
        sky.clip(to: disc)
        if layers.milkyWay { drawMilkyWay(&sky) }
        if layers.altitudeGrid { drawGrid(&sky) }
        if layers.constellationLines { drawConstellationLines(&sky) }
        drawStars(&sky)
        if layers.deepSkyObjects { drawDeepSky(&sky) }
        occupied += drawBodies(&sky)
        occupied += drawSmallBodies(&sky)
        drawSkyline(&sky)
        occupied += drawMosaic(&sky)
        occupied += drawTarget(&sky)
        drawSelection(&sky)

        context.stroke(disc, with: .color(palette.horizonLine), lineWidth: 1.5)
        drawTargetRimIndicator(&context)
        drawAltitudeLabels(&context)
        drawLabels(&context, occupied: occupied)
        drawMosaicLabel(&context)
    }

    // MARK: Sky

    private func drawMilkyWay(_ context: inout GraphicsContext) {
        let transform = viewport.transform
        for path in content.paths.milkyWay {
            context.fill(path.applying(transform), with: .color(palette.milkyWay), style: FillStyle(eoFill: true))
        }
    }

    private func drawGrid(_ context: inout GraphicsContext) {
        let dashed = StrokeStyle(lineWidth: 0.75, dash: [2, 4])
        for altitude in Self.altitudeCircles {
            let radius = viewport.radius * CGFloat(PlanisphereProjection.radius(ofAltitude: altitude))
            let circle = PlanisphereShapes.circle(around: viewport.center, radius: radius)
            context.stroke(circle, with: .color(palette.gridLine), style: dashed)
        }
        var axes = Path()
        for azimuth in stride(from: 0.0, to: 360.0, by: 90.0) {
            axes.move(to: viewport.center)
            axes.addLine(to: viewport.rimPoint(azimuth: azimuth, outside: 0))
        }
        context.stroke(axes, with: .color(palette.gridLine), lineWidth: 0.75)
    }

    private func drawConstellationLines(_ context: inout GraphicsContext) {
        context.stroke(content.paths.constellationLines.applying(viewport.transform),
                       with: .color(palette.constellationLine), lineWidth: 1)
    }

    /// Stars are filled in batches of equal size and colour; the brightest also get a soft halo.
    private func drawStars(_ context: inout GraphicsContext) {
        let bounds = visibleBounds
        for group in scene.starGroups {
            let diameter = SkyChartStarStyle.diameters[group.sizeClass]
            let radius = diameter / 2
            var dots = Path()
            var halos = Path()
            for point in group.points {
                let center = viewport.screen(point)
                guard bounds.contains(center) else { continue }
                let dot = PlanisphereBounds.square(around: center, radius: radius)
                if diameter < 2 { dots.addRect(dot) } else { dots.addEllipse(in: dot) }
                if diameter >= 4 {
                    halos.addEllipse(in: dot.insetBy(dx: -radius * 1.2, dy: -radius * 1.2))
                }
            }
            let color = palette.starColor(colorIndex: SkyChartStarStyle.colorIndices[group.colorClass])
            if !halos.isEmpty {
                context.fill(halos, with: .color(color.opacity(0.16)))
            }
            context.fill(dots, with: .color(color.opacity(SkyChartStarStyle.opacities[group.sizeClass])))
        }
    }

    /// Galaxies are drawn as ellipses, nebulae as rounded squares and clusters as circles; dark nebulae are dashed and
    /// fainter. The scene holds the objects up to the prominence chosen in Settings; the least prominent wait for zoom.
    private func drawDeepSky(_ context: inout GraphicsContext) {
        let bounds = visibleBounds
        var galaxies = Path(), nebulae = Path(), clusters = Path(), darkNebulae = Path()
        // Obscure objects (prominence 4) appear once the chart is zoomed in.
        let showsObscure = viewport.zoom >= Self.obscureMinimumZoom
        for object in scene.deepSky where showsObscure || object.prominence < 4 {
            let center = viewport.screen(object.point)
            guard bounds.contains(center) else { continue }
            let extent = (object.extent ?? 0) * Double(viewport.pointsPerRadian(at: object.point))
            // Zoomed in, large objects are drawn at their true size (as far as the screen allows), so they can be
            // framed against the camera's frame.
            let size = CGFloat(min(max(extent, 5), 48 * max(1, Double(viewport.zoom) / 2)))
            switch object.group {
            case .galaxies:
                let outline = CGSize(width: size, height: size * 0.6)
                galaxies.addEllipse(in: PlanisphereBounds.rect(around: center, size: outline))
            case .nebulae:
                let square = PlanisphereBounds.square(around: center, radius: size / 2)
                if object.isDark {
                    darkNebulae.addRoundedRect(in: square, cornerSize: CGSize(width: 1.5, height: 1.5))
                } else {
                    nebulae.addRoundedRect(in: square, cornerSize: CGSize(width: 1.5, height: 1.5))
                }
            default:
                clusters.addEllipse(in: PlanisphereBounds.square(around: center, radius: size / 2))
            }
        }
        let style = StrokeStyle(lineWidth: 1)
        context.stroke(galaxies, with: .color(palette.deepSkyMarker), style: style)
        context.stroke(nebulae, with: .color(palette.deepSkyMarker), style: style)
        context.stroke(clusters, with: .color(palette.deepSkyMarker), style: style)
        context.stroke(darkNebulae, with: .color(palette.deepSkyMarker.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    // MARK: Skyline and mosaic

    /// Shades the ground below the recorded skyline and draws the skyline; nothing for an open horizon.
    private func drawSkyline(_ context: inout GraphicsContext) {
        guard let skyline = scene.skyline else { return }
        let transform = viewport.transform
        context.fill(skyline.ground.applying(transform), with: .color(palette.background.opacity(Self.groundShade)),
                     style: FillStyle(eoFill: true))
        context.stroke(skyline.line.applying(transform), with: .color(palette.horizonLine),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }

    /// Outlines the panels of the mosaic: the current one is filled and heavy, panels already shot are dim, the next one
    /// is dashed. Returns the rectangle the current panel's name takes, so labels keep clear of it.
    private func drawMosaic(_ context: inout GraphicsContext) -> [CGRect] {
        guard let mosaic, !scene.mosaic.isEmpty else { return [] }
        var done = Path(), later = Path(), next = Path(), current = Path(), currentFill = Path()
        var currentCenter: CGPoint?
        for panel in scene.mosaic {
            switch mosaic.state(ofShootingPosition: panel.shootingPosition) {
            case .done: done.addPath(panel.outline)
            case .later: later.addPath(panel.outline)
            case .next: next.addPath(panel.outline)
            case .current:
                current.addPath(panel.outline)
                if let fill = panel.fill { currentFill.addPath(fill) }
                currentCenter = panel.center
            }
        }
        let transform = viewport.transform
        context.fill(currentFill.applying(transform), with: .color(palette.guidance.opacity(0.16)))
        context.stroke(done.applying(transform), with: .color(palette.positive.opacity(0.4)), lineWidth: 1)
        context.stroke(later.applying(transform), with: .color(palette.dslrFrame.opacity(0.4)), lineWidth: 1)
        context.stroke(next.applying(transform), with: .color(palette.dslrFrame.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        context.stroke(current.applying(transform), with: .color(palette.guidance),
                       style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        guard let currentCenter else { return [] }
        let center = viewport.screen(currentCenter)
        return visibleBounds.contains(center) ? [PlanisphereBounds.square(around: center, radius: 30)] : []
    }

    /// Names the current panel, "Panel 3 of 12", at its centre.
    private func drawMosaicLabel(_ context: inout GraphicsContext) {
        guard let mosaic, mosaic.step < mosaic.count,
              let center = scene.mosaic.first(where: { $0.shootingPosition == mosaic.step })?.center,
              let symbol = context.resolveSymbol(id: Self.mosaicLabelID) else { return }
        let point = viewport.screen(center)
        guard visibleBounds.contains(point), hypot(point.x - viewport.center.x, point.y - viewport.center.y) < viewport.radius
        else { return }
        context.draw(symbol, at: point, anchor: .center)
    }

    // MARK: Solar system

    /// Draws the Sun, Moon and planets; returns the screen rectangles they occupy.
    private func drawBodies(_ context: inout GraphicsContext) -> [CGRect] {
        var occupied: [CGRect] = []
        for body in scene.bodies where body.isAboveHorizon {
            let center = viewport.screen(body.point)
            guard visibleBounds.contains(center) else { continue }
            switch body.kind {
            case .sun: drawSun(&context, at: center)
            case .moon: drawMoon(&context, body, at: center)
            case .planet: drawPlanet(&context, body, at: center)
            }
            occupied.append(PlanisphereBounds.square(around: center, radius: 8))
        }
        return occupied
    }

    private func drawSun(_ context: inout GraphicsContext, at center: CGPoint) {
        var rays = Path()
        for step in 0..<8 {
            let angle = Double(step) * Double.pi / 4
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            rays.move(to: CGPoint(x: center.x + direction.x * 8.5, y: center.y + direction.y * 8.5))
            rays.addLine(to: CGPoint(x: center.x + direction.x * 12, y: center.y + direction.y * 12))
        }
        context.stroke(rays, with: .color(palette.accent), lineWidth: 1.5)
        context.fill(PlanisphereShapes.circle(around: center, radius: 6), with: .color(palette.accent))
    }

    /// The Moon as a disc with its lit part, turned towards the Sun.
    private func drawMoon(_ context: inout GraphicsContext, _ moon: SkyChartBodyMarker, at center: CGPoint) {
        let radius: CGFloat = 7.5
        let disc = PlanisphereShapes.circle(around: center, radius: radius)
        context.fill(disc, with: .color(palette.surfaceRaised))
        let outline = SkyChartMoonShape.litOutline(center: center, radius: radius,
                                                   fraction: moon.illuminatedFraction ?? 0.5,
                                                   towardsSun: moon.towardsSunAngle + viewport.rotation)
        context.fill(PlanisphereShapes.polyline(outline, closed: true), with: .color(palette.planetMarker))
        context.stroke(disc, with: .color(palette.planetMarker.opacity(0.7)), lineWidth: 1)
    }

    private func drawPlanet(_ context: inout GraphicsContext, _ planet: SkyChartBodyMarker, at center: CGPoint) {
        let radius = CGFloat(min(max(3.4 - 0.5 * (planet.magnitude ?? 1), 2.5), 5))
        context.fill(PlanisphereShapes.circle(around: center, radius: radius), with: .color(palette.planetMarker))
    }

    // MARK: Target and selection

    /// Draws the reticle on the target when it is above the horizon; returns the rectangle it occupies.
    private func drawTarget(_ context: inout GraphicsContext) -> [CGRect] {
        guard let target = scene.target, target.isAboveHorizon else { return [] }
        let center = viewport.screen(PlanisphereProjection.chartPoint(target.direction))
        guard visibleBounds.contains(center) else { return [] }
        let radius: CGFloat = 11
        let tick: CGFloat = 6
        var reticle = PlanisphereShapes.circle(around: center, radius: radius)
        reticle.addPath(PlanisphereShapes.axisTicks(around: center, from: radius, to: radius + tick))
        context.stroke(reticle, with: .color(palette.guidance), lineWidth: 2)
        return [PlanisphereBounds.square(around: center, radius: radius + tick)]
    }

    /// A target below the horizon is shown as an arrow on the horizon circle, towards its azimuth.
    private func drawTargetRimIndicator(_ context: inout GraphicsContext) {
        guard let target = scene.target, !target.isAboveHorizon else { return }
        context.fill(viewport.rimArrow(towards: target.horizontal.azimuth), with: .color(palette.guidance))
    }

    private func drawSelection(_ context: inout GraphicsContext) {
        guard let direction = selectedDirection, direction.z >= 0 else { return }
        let center = viewport.screen(PlanisphereProjection.chartPoint(direction))
        guard visibleBounds.contains(center) else { return }
        let radius: CGFloat = 15
        context.stroke(PlanisphereShapes.circle(around: center, radius: radius),
                       with: .color(palette.primaryText), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }

    // MARK: Rim and labels

    /// Draws the tick marks and compass letters around the horizon circle; returns the letters' rectangles.
    private func drawRim(_ context: inout GraphicsContext) -> [CGRect] {
        var ticks = Path()
        for azimuth in stride(from: 0, to: 360, by: 10) {
            let length: CGFloat = azimuth % 30 == 0 ? 7 : 4
            ticks.move(to: viewport.rimPoint(azimuth: Double(azimuth), outside: 0))
            ticks.addLine(to: viewport.rimPoint(azimuth: Double(azimuth), outside: length))
        }
        context.stroke(ticks, with: .color(palette.horizonLine), lineWidth: 1)

        var occupied: [CGRect] = []
        for cardinal in PlanisphereCardinal.all {
            let center = viewport.rimPoint(azimuth: cardinal.azimuth, outside: cardinal.isPrincipal ? 17 : 15)
            guard visibleBounds.contains(center), let symbol = context.resolveSymbol(id: cardinal.id) else { continue }
            context.draw(symbol, at: center, anchor: .center)
            occupied.append(PlanisphereBounds.rect(around: center, size: symbol.size))
        }
        return occupied
    }

    /// Writes the altitude of each circle of the grid next to it, towards south-south-east.
    private func drawAltitudeLabels(_ context: inout GraphicsContext) {
        guard layers.altitudeGrid else { return }
        let direction = PlanisphereProjection.unitVector(towardsAzimuth: 157.5)
        for altitude in Self.altitudeCircles {
            let radius = CGFloat(PlanisphereProjection.radius(ofAltitude: altitude))
            let center = viewport.screen(CGPoint(x: direction.x * radius, y: direction.y * radius))
            let id = Self.altitudeLabelID(altitude)
            guard visibleBounds.contains(center), let symbol = context.resolveSymbol(id: id) else { continue }
            context.draw(symbol, at: center, anchor: .center)
        }
    }

    /// Places the text labels in priority order, skipping any that would overlap one already placed or
    /// run off the screen. A label that does not fit beside its point tries the other side of it, then
    /// above and below.
    private func drawLabels(_ context: inout GraphicsContext, occupied initial: [CGRect]) {
        var occupied = initial
        var placed = 0
        let screen = CGRect(origin: .zero, size: viewport.size).insetBy(dx: 2, dy: 2)
        let center = viewport.center
        let limit = viewport.radius
        for label in scene.labels where label.minimumZoom <= viewport.zoom && isEnabled(label.style) {
            let anchor = viewport.screen(label.point)
            guard visibleBounds.contains(anchor), hypot(anchor.x - center.x, anchor.y - center.y) < limit,
                  let symbol = context.resolveSymbol(id: label.id) else { continue }
            let size = symbol.size
            let free = candidateOrigins(for: label, around: anchor, size: size).first { origin in
                let rect = CGRect(origin: origin, size: size)
                let padded = rect.insetBy(dx: -3, dy: -1.5)
                return screen.contains(rect) && !occupied.contains { $0.intersects(padded) }
            }
            guard let origin = free else { continue }
            occupied.append(CGRect(origin: origin, size: size))
            context.draw(symbol, at: origin, anchor: .topLeading)
            placed += 1
            if placed >= Self.labelLimit { break }
        }
    }

    /// Where the top-left corner of a label of `size` can go: centred on its point when the label has
    /// no offset, otherwise to the right of the point, then left, above and below.
    private func candidateOrigins(for label: SkyChartLabel, around anchor: CGPoint, size: CGSize) -> [CGPoint] {
        let top = anchor.y - size.height / 2
        guard label.offset > 0 else { return [CGPoint(x: anchor.x - size.width / 2, y: top)] }
        let gap = label.offset
        return [CGPoint(x: anchor.x + gap, y: top),
                CGPoint(x: anchor.x - gap - size.width, y: top),
                CGPoint(x: anchor.x - size.width / 2, y: anchor.y - gap - size.height / 2),
                CGPoint(x: anchor.x - size.width / 2, y: anchor.y + gap - size.height / 2)]
    }

    private func isEnabled(_ style: SkyChartLabel.Style) -> Bool {
        switch style {
        case .constellation: return layers.constellationNames
        case .star: return layers.starNames
        case .deepSky: return layers.deepSkyObjects
        case .body, .target: return true
        }
    }
}
