import SwiftUI
import LodestarKit

// The celestial layers: Milky Way, constellations, deep-sky objects, stars, the Sun, the Moon and the planets.
extension SkyOverlayRenderer {
    // MARK: Milky Way

    func drawMilkyWay(in context: GraphicsContext) {
        guard configuration.showMilkyWay, let layers = content?.milkyWay else { return }
        for layer in layers {
            var path = Path()
            for ring in layer.rings where boresight.angle(to: ring.center) <= ring.radius + viewRadius {
                let outline = frustum.clip(polygon: ring.vertices)
                guard outline.count >= 3 else { continue }
                path.addLines(projector.points(outline).compactMap { $0 })
                path.closeSubpath()
            }
            if !path.isEmpty {
                context.fill(path, with: .color(palette.milkyWay), style: FillStyle(eoFill: true))
            }
        }
    }

    // MARK: Constellations

    mutating func drawConstellations(in context: GraphicsContext) {
        guard let figures = content?.snapshot.constellations, !figures.isEmpty else { return }
        if configuration.showConstellationLines {
            var world = AimWorldPath()
            for figure in figures {
                for line in figure.lines {
                    world.addPolyline(line, frustum: frustum)
                }
            }
            context.stroke(world.path(projecting: projector), with: .color(palette.constellationLine), lineWidth: 1)
        }
        if configuration.showConstellationNames {
            let style = AimLabelStyle(size: 11, weight: .medium, color: palette.constellationLabel)
            for (figure, point) in zip(figures, projector.points(figures.map(\.label))) {
                if let point, isVisible(point, margin: 0) {
                    addLabel(figure.name.uppercased(), near: point, style: style, priority: 5)
                }
            }
        }
    }

    // MARK: Deep-sky objects

    /// Fainter objects are left out the wider the view, so a wide view stays readable.
    static func deepSkyMagnitudeCutoff(forFieldOfView fieldOfView: Double) -> Double {
        switch fieldOfView {
        case 70...: return 7
        case 40...: return 8.5
        case 20...: return 10
        default: return .infinity
        }
    }

    /// Names are shown in views narrower than this many degrees.
    static let deepSkyNameFieldOfView = 40.0
    /// The most deep-sky names shown at once.
    static let deepSkyNameLimit = 12

    mutating func drawDeepSky(in context: GraphicsContext) {
        guard configuration.showDeepSkyObjects, let markers = content?.deepSky, !markers.isEmpty else { return }
        let cutoff = Self.deepSkyMagnitudeCutoff(forFieldOfView: fieldOfView)
        let shown = Array(markers.prefix { ($0.magnitude ?? .infinity) <= cutoff })
        var outlines = Path()
        var namesShown = 0
        let nameStyle = AimLabelStyle(size: 11, weight: .regular, color: palette.deepSkyMarker)
        for (marker, point) in zip(shown, projector.points(shown.map(\.direction))) {
            guard let point, isVisible(point, margin: 16) else { continue }
            let extent = min(max(marker.diameter * pointsPerDegree, 8), 44)
            outlines.addPath(symbol(for: marker.shape, at: point, extent: extent))
            if fieldOfView < Self.deepSkyNameFieldOfView, namesShown < Self.deepSkyNameLimit {
                addLabel(marker.name, near: point, offset: CGSize(width: 0, height: extent / 2 + 10), style: nameStyle,
                         priority: 6)
                namesShown += 1
            }
        }
        context.stroke(outlines, with: .color(palette.deepSkyMarker), lineWidth: 1)
    }

    /// The chart symbol for a deep-sky object: ellipse for galaxies, circle with a dot for clusters, square for
    /// nebulae.
    private func symbol(for shape: AimDeepSkyMarker.Shape, at center: CGPoint, extent: CGFloat) -> Path {
        let half = extent / 2
        switch shape {
        case .ellipse:
            let rect = CGRect(x: -half, y: -half * 0.5, width: extent, height: half)
            let placement = CGAffineTransform(rotationAngle: -.pi / 6).concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            return Path(ellipseIn: rect).applying(placement)
        case .clusterDot:
            var path = ellipse(at: center, radius: half)
            path.addPath(ellipse(at: center, radius: 1.2))
            return path
        case .square:
            return Path(CGRect(x: center.x - half * 0.8, y: center.y - half * 0.8, width: extent * 0.8, height: extent * 0.8))
        case .circle:
            return ellipse(at: center, radius: half * 0.8)
        }
    }

    // MARK: Stars

    /// Radius in points of the stars in each brightness class.
    private static let starRadii: [CGFloat] = [3.6, 3.0, 2.5, 2.0, 1.6, 1.25, 1.0]
    /// Opacity of the stars in each brightness class.
    private static let starOpacities: [Double] = [1, 1, 1, 0.95, 0.9, 0.8, 0.65]
    /// B−V colour index standing for each tint class.
    private static let tintColorIndices: [Double] = [0, 0.6, 1.4]
    /// Stars below the horizon are drawn this much fainter.
    private static let belowHorizonOpacity = 0.35
    /// Stars with names shown at once.
    private static let starNameLimit = 14

    mutating func drawStars(in context: GraphicsContext) {
        guard let content else { return }
        for group in content.starGroups {
            let radius = Self.starRadii[min(group.brightness, Self.starRadii.count - 1)]
            var path = Path()
            for case let point? in projector.points(group.directions) where isVisible(point) {
                path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
            guard !path.isEmpty else { continue }
            let opacity = Self.starOpacities[min(group.brightness, Self.starOpacities.count - 1)]
                * (group.isBelowHorizon ? Self.belowHorizonOpacity : 1)
            let tint = Self.tintColorIndices[min(group.tint, Self.tintColorIndices.count - 1)]
            context.fill(path, with: .color(palette.starColor(colorIndex: tint).opacity(opacity)))
        }
        let style = AimLabelStyle(size: 11, weight: .regular, color: palette.primaryText.opacity(0.9))
        var namesShown = 0
        for (star, point) in zip(content.namedStars, projector.points(content.namedStars.map(\.direction))) {
            guard namesShown < Self.starNameLimit, let point, isVisible(point, margin: 0), star.direction.z >= 0 else { continue }
            addLabel(star.name, near: point, offset: CGSize(width: 0, height: -14), style: style, priority: 4)
            namesShown += 1
        }
    }

    // MARK: Sun, Moon and planets

    mutating func drawBodies(in context: GraphicsContext) {
        guard let bodies = content?.snapshot.bodies else { return }
        let sun = bodies.first { $0.object.category == .sun }
        let style = AimLabelStyle(size: 12, weight: .semibold, color: palette.planetMarker)
        for (body, point) in zip(bodies, projector.points(bodies.map(\.direction))) {
            guard let point, isVisible(point, margin: 24) else { continue }
            let opacity = body.direction.z < 0 ? 0.5 : 1
            let color = palette.planetMarker.opacity(opacity)
            let disc = body.angularDiameter * pointsPerDegree / 2
            let radius: CGFloat
            switch body.object.category {
            case .moon:
                radius = CGFloat(max(disc, 8))
                drawMoon(body, at: point, radius: radius, litAngle: litLimbAngle(of: body, towards: sun, from: point),
                         color: color, in: context)
            case .sun:
                radius = CGFloat(max(disc, 7))
                context.fill(ellipse(at: point, radius: radius), with: .color(color))
                context.stroke(ellipse(at: point, radius: radius + 4), with: .color(color), lineWidth: 1)
            default:
                radius = CGFloat(min(max(3.4 - 0.35 * (body.magnitude ?? 2), 2.5), 6.5))
                context.fill(ellipse(at: point, radius: radius), with: .color(color))
                context.stroke(ellipse(at: point, radius: radius + 3), with: .color(color.opacity(0.6)), lineWidth: 0.75)
            }
            addLabel(body.object.name, near: point, offset: CGSize(width: 0, height: radius + 13), style: style, priority: 1)
        }
    }

    /// The screen angle (radians, clockwise from screen-right) of the direction in which the Moon's bright limb
    /// points, which is towards the Sun.
    private func litLimbAngle(of moon: SkySnapshot.Body, towards sun: SkySnapshot.Body?, from point: CGPoint) -> Double {
        guard let sun else { return 0 }
        let towardsSun = sun.direction - moon.direction * moon.direction.dot(sun.direction)
        guard towardsSun.length > 1e-6 else { return 0 }
        let probe = moon.direction + towardsSun.normalized * 0.02
        guard let end = projector.point(probe) else { return 0 }
        return atan2(Double(end.y - point.y), Double(end.x - point.x))
    }

    /// The Moon as a disc with its lit part drawn from the illuminated fraction.
    private func drawMoon(_ moon: SkySnapshot.Body, at center: CGPoint, radius: CGFloat, litAngle: Double, color: Color,
                          in context: GraphicsContext) {
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .radians(litAngle))
        let disc = ellipse(at: .zero, radius: radius)
        layer.fill(disc, with: .color(color.opacity(0.22)))
        // The lit area lies between the bright limb (right half circle) and the terminator (half ellipse whose
        // width follows the phase: it bulges left when more than half is lit and right when less).
        let squeeze = 2 * (moon.illuminatedFraction ?? 1) - 1
        var lit = Path()
        let steps = 16
        for step in 0...steps {
            let t = Double.pi * Double(step) / Double(steps)
            let point = CGPoint(x: radius * CGFloat(sin(t)), y: -radius * CGFloat(cos(t)))
            if step == 0 { lit.move(to: point) } else { lit.addLine(to: point) }
        }
        for step in 0...steps {
            let t = Double.pi * (1 - Double(step) / Double(steps))
            lit.addLine(to: CGPoint(x: -radius * CGFloat(squeeze * sin(t)), y: -radius * CGFloat(cos(t))))
        }
        lit.closeSubpath()
        layer.fill(lit, with: .color(color))
        layer.stroke(disc, with: .color(color), lineWidth: 1)
    }
}
