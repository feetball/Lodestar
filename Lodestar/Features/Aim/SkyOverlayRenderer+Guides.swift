import SwiftUI
import LodestarKit

// The guides drawn over the sky: altitude/azimuth grid, horizon with compass points, DSLR frame, target marker with
// its edge indicator, and the phone's reticle.
extension SkyOverlayRenderer {
    // MARK: Grid

    mutating func drawGrid(in context: GraphicsContext) {
        guard fieldOfView <= Self.gridMaximumFieldOfView else { return }
        let direction = HorizontalCoordinate(vector: boresight)
        let style = AimLabelStyle(size: 10, weight: .regular, color: palette.secondaryText.opacity(0.75))
        var world = AimWorldPath()
        for circle in AimSkyGrid.altitudeCircles where abs(circle.altitude - direction.altitude) <= viewRadius + 2 {
            world.addPolyline(circle.points, closed: true, frustum: frustum)
            let labelDirection = HorizontalCoordinate(azimuth: direction.azimuth, altitude: circle.altitude).unitVector
            if let point = projector.point(labelDirection), isVisible(point, margin: 0) {
                addLabel(AngleFormatter.formatDegrees(circle.altitude, decimals: 0), near: point,
                         offset: CGSize(width: 22, height: -8), style: style, priority: 7)
            }
        }
        for line in AimSkyGrid.azimuthLines {
            world.addPolyline(line, frustum: frustum)
        }
        context.stroke(world.path(projecting: projector), with: .color(palette.gridLine), lineWidth: 0.75)
    }

    // MARK: Horizon

    /// Degrees of azimuth are labelled in views narrower than this many degrees.
    private static let azimuthLabelFieldOfView = 30.0

    mutating func drawHorizon(in context: GraphicsContext) {
        var line = AimWorldPath()
        line.addPolyline(AimSkyGrid.horizon, closed: true, frustum: frustum)
        context.stroke(line.path(projecting: projector), with: .color(palette.horizonLine), lineWidth: 1.5)

        // Ticks stand on the horizon: 5 points high every 5°, 9 points every 10°.
        let focalLength = projector.projection.focalLength
        let up = Vector3(0, 0, 1)
        var ticks = AimWorldPath()
        for tick in AimSkyGrid.horizonTicks {
            ticks.addSegment(from: tick.base, to: tick.base + up * ((tick.isMajor ? 9 : 5) / focalLength), frustum: frustum)
        }
        context.stroke(ticks.path(projecting: projector), with: .color(palette.horizonLine), lineWidth: 1)

        let cardinalStyle = AimLabelStyle(size: 17, weight: .bold, color: palette.primaryText)
        let intercardinalStyle = AimLabelStyle(size: 12, weight: .semibold, color: palette.secondaryText)
        for (label, point) in zip(AimSkyGrid.compassLabels, projector.points(AimSkyGrid.compassLabels.map(\.direction))) {
            if let point, isVisible(point, margin: 0) {
                addLabel(label.text, near: point, offset: CGSize(width: 0, height: label.isCardinal ? -19 : -16),
                         style: label.isCardinal ? cardinalStyle : intercardinalStyle, priority: 2)
            }
        }
        guard fieldOfView <= Self.azimuthLabelFieldOfView else { return }
        let degreeStyle = AimLabelStyle(size: 10, weight: .regular, color: palette.secondaryText.opacity(0.8))
        let majorTicks = AimSkyGrid.horizonTicks.enumerated().filter { $0.element.isMajor && $0.offset % 18 != 0 }
        for (tick, point) in zip(majorTicks, projector.points(majorTicks.map(\.element.base))) {
            if let point, isVisible(point, margin: 0) {
                addLabel(AngleFormatter.formatDegrees(Double(tick.offset) * 5, decimals: 0), near: point,
                         offset: CGSize(width: 0, height: 16), style: degreeStyle, priority: 8)
            }
        }
    }

    // MARK: DSLR frame

    mutating func drawDSLRFrame(in context: GraphicsContext) {
        let outline = PinholeProjection.dslrFrameOutline(solution: frame.pointing,
                                                         horizontalFOV: configuration.lensFrame.horizontal,
                                                         verticalFOV: configuration.lensFrame.vertical,
                                                         samplesPerEdge: 4)
        var world = AimWorldPath()
        world.addPolyline(outline, closed: true, frustum: frustum)
        context.stroke(world.path(projecting: projector), with: .color(palette.dslrFrame),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        guard let center = projector.point(frame.pointing.boresightVector), isVisible(center, margin: 0) else { return }
        var crosshair = Path()
        crosshair.move(to: CGPoint(x: center.x - 9, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + 9, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 9))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + 9))
        context.stroke(crosshair, with: .color(palette.dslrFrame), lineWidth: 1.5)
    }

    // MARK: Target

    /// Distance in points from the left and right edges at which the off-screen indicator sits.
    private static let edgeSideInset: CGFloat = 36
    /// Distances from the top and bottom edges, which leave room for the status chips and the control panel.
    private static let edgeTopInset: CGFloat = 96
    private static let edgeBottomInset: CGFloat = 240

    /// Draws the ring on what the guidance leads to: the panel of a mosaic being shot, else the satellite, else the target.
    mutating func drawTarget(in context: GraphicsContext) {
        let aim: (direction: Vector3, name: String)
        if let panel = frame.mosaic, let mosaic {
            aim = (panel.aim.horizontal.unitVector, "Panel \(min(mosaic.step + 1, mosaic.count))")
        } else if let satellite = frame.satellite {
            aim = (satellite.direction, satellite.label)
        } else if let target = frame.target {
            aim = (target.direction, SmallBodyText.displayName(target.object))
        } else {
            return
        }
        let isOnTarget = frame.guidance?.state == .onTarget
        let color = isOnTarget ? palette.positive : palette.guidance
        guard let point = projector.point(aim.direction), isVisible(point, margin: 0) else {
            drawEdgeIndicator(toward: aim.direction, color: color, in: context)
            return
        }
        // A pulsing ring marks the target; once the camera is on it the ring stops and thickens.
        let pulse = isOnTarget ? 0 : 3 * sin(time * 2 * .pi / 1.6)
        let radius = CGFloat(21 + pulse)
        context.stroke(ellipse(at: point, radius: radius), with: .color(color), lineWidth: isOnTarget ? 3.5 : 2)
        context.fill(ellipse(at: point, radius: 2.5), with: .color(color))
        addLabel(aim.name, near: point, offset: CGSize(width: 0, height: -(radius + 15)),
                 style: AimLabelStyle(size: 14, weight: .bold, color: color), priority: 0)
    }

    /// An arrow at the screen edge in the direction of a target that is not in view, with its distance.
    mutating func drawEdgeIndicator(toward direction: Vector3, color: Color, in context: GraphicsContext) {
        let device = worldToDevice * direction
        var heading = CGVector(dx: device.x, dy: -device.y)
        let length = hypot(heading.dx, heading.dy)
        heading = length > 1e-6 ? CGVector(dx: heading.dx / length, dy: heading.dy / length) : CGVector(dx: 0, dy: -1)

        let bounds = CGRect(x: Self.edgeSideInset, y: Self.edgeTopInset, width: size.width - 2 * Self.edgeSideInset,
                            height: size.height - Self.edgeTopInset - Self.edgeBottomInset)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var distance = CGFloat.infinity
        if heading.dx > 0.001 {
            distance = min(distance, (bounds.maxX - center.x) / heading.dx)
        } else if heading.dx < -0.001 {
            distance = min(distance, (bounds.minX - center.x) / heading.dx)
        }
        if heading.dy > 0.001 {
            distance = min(distance, (bounds.maxY - center.y) / heading.dy)
        } else if heading.dy < -0.001 {
            distance = min(distance, (bounds.minY - center.y) / heading.dy)
        }
        guard distance.isFinite else { return }
        distance = max(distance, 0)
        let tip = CGPoint(x: center.x + heading.dx * distance, y: center.y + heading.dy * distance)

        var arrow = Path()
        arrow.move(to: CGPoint(x: 16, y: 0))
        arrow.addLine(to: CGPoint(x: -9, y: -12))
        arrow.addLine(to: CGPoint(x: -3, y: 0))
        arrow.addLine(to: CGPoint(x: -9, y: 12))
        arrow.closeSubpath()
        var layer = context
        layer.translateBy(x: tip.x, y: tip.y)
        layer.rotate(by: .radians(atan2(Double(heading.dy), Double(heading.dx))))
        layer.fill(arrow, with: .color(color))
        layer.stroke(arrow, with: .color(.black.opacity(0.5)), lineWidth: 1)

        let separation = AimFormat.angle(boresight.angle(to: direction))
        // On a backing, so a star or a line behind the number does not read as part of it.
        let style = AimLabelStyle(size: 14, weight: .bold, color: color, backing: palette.background.opacity(0.72))
        labels.add(separation, at: CGPoint(x: tip.x - heading.dx * 38, y: tip.y - heading.dy * 38), style: style, priority: 3)
    }

    // MARK: Reticle

    /// The phone camera's axis: a ring with four ticks at the centre of the screen.
    func drawReticle(in context: GraphicsContext) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let color = palette.primaryText.opacity(0.7)
        context.stroke(ellipse(at: center, radius: 15), with: .color(color), lineWidth: 1)
        context.fill(ellipse(at: center, radius: 1.5), with: .color(color))
        var ticks = Path()
        for quarter in 0..<4 {
            let angle = Double(quarter) * .pi / 2
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            ticks.move(to: CGPoint(x: center.x + direction.dx * 15, y: center.y + direction.dy * 15))
            ticks.addLine(to: CGPoint(x: center.x + direction.dx * 23, y: center.y + direction.dy * 23))
        }
        context.stroke(ticks, with: .color(color), lineWidth: 1)
    }
}
