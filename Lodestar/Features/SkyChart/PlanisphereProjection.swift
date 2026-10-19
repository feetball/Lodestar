import Foundation
import LodestarKit

/// The planisphere's chart space and the geometry shared by the scene builder and the views.
///
/// The chart shows the whole sky as seen lying on one's back and looking up: the zenith is the
/// centre, the horizon is the unit circle, **north is at the top and east is to the left**
/// (azimuth grows counter-clockwise, like a star wheel held overhead). The projection is the
/// azimuthal stereographic one, `r = tan(zenithDistance / 2)`: conformal, so small shapes keep
/// their shape, with the horizon at radius 1 and the 30° and 60° altitude circles at 0.577 and
/// 0.268. Chart points use x to the right and y downwards, so `PlanisphereViewport` can scale
/// them straight onto the screen.
enum PlanisphereProjection {
    /// Directions farther from the zenith than this chart radius (altitude below about −71°) are
    /// pulled back onto the circle of this radius. The nadir lies at infinity; the pulled-back
    /// part of a polygon is never visible, it only has to keep the polygon's topology intact.
    static let retractionRadius = 6.0

    /// The chart point of an East–North–Up direction. The direction must be above the nadir.
    static func chartPoint(_ direction: Vector3) -> CGPoint {
        let denominator = 1 + direction.z
        return CGPoint(x: -direction.x / denominator, y: -direction.y / denominator)
    }

    /// Like `chartPoint(_:)`, but a direction farther than `retractionRadius` from the zenith is
    /// moved along its ray onto that circle, so the result is always finite.
    static func retractedChartPoint(_ direction: Vector3) -> CGPoint {
        let denominator = 1 + direction.z
        let horizontalSquared = direction.x * direction.x + direction.y * direction.y
        if denominator > 0, horizontalSquared <= retractionRadius * retractionRadius * denominator * denominator {
            return CGPoint(x: -direction.x / denominator, y: -direction.y / denominator)
        }
        let horizontal = horizontalSquared.squareRoot()
        guard horizontal > 1e-12 else { return CGPoint(x: 0, y: retractionRadius) }
        return CGPoint(x: -direction.x / horizontal * retractionRadius, y: -direction.y / horizontal * retractionRadius)
    }

    /// The East–North–Up unit vector of a chart point: the inverse of `chartPoint(_:)`.
    static func direction(ofChartPoint point: CGPoint) -> Vector3 {
        let x = Double(point.x), y = Double(point.y)
        let squared = x * x + y * y
        let scale = 2 / (1 + squared)
        return Vector3(-x * scale, -y * scale, (1 - squared) / (1 + squared))
    }

    /// The chart radius of a circle of constant altitude (degrees); 1 for the horizon.
    static func radius(ofAltitude altitude: Double) -> Double {
        AstroMath.tanDeg((90 - altitude) / 2)
    }

    /// The unit chart vector pointing towards an azimuth (degrees from north through east).
    static func unitVector(towardsAzimuth azimuth: Double) -> CGPoint {
        CGPoint(x: -AstroMath.sinDeg(azimuth), y: -AstroMath.cosDeg(azimuth))
    }

    // MARK: Polylines above the horizon

    /// The parts of the polyline through `vertices` that lie above the horizon, as chart points.
    ///
    /// Consecutive vertices are joined by great-circle arcs, subdivided so that no step exceeds
    /// `maximumStep` degrees; an arc that crosses the horizon is cut exactly there.
    static func visiblePolylines(through vertices: [Vector3], maximumStep: Double = 4) -> [[CGPoint]] {
        guard let first = vertices.first else { return [] }
        var clipper = PlanisphereHorizonClipper()
        clipper.append(first)
        var previous = first
        for vertex in vertices.dropFirst() {
            forEachArcSample(from: previous, to: vertex, maximumStep: maximumStep) { clipper.append($0) }
            previous = vertex
        }
        return clipper.finish()
    }

    // MARK: Filled rings

    /// A closed ring of directions as a chart polygon (its closing edge is implicit).
    ///
    /// Edges are great-circle arcs subdivided to at most `maximumStep` degrees. Parts of the ring
    /// that dip towards the nadir are pulled onto the retraction circle, and where the ring runs
    /// along that circle it follows it, so the polygon keeps the topology of the projected ring
    /// and fills correctly inside the horizon circle.
    static func ring(through vertices: [Vector3], maximumStep: Double = 2) -> [CGPoint] {
        guard vertices.count >= 3 else { return [] }
        var points = [retractedChartPoint(vertices[0])]
        for index in vertices.indices {
            let next = vertices[(index + 1) % vertices.count]
            forEachArcSample(from: vertices[index], to: next, maximumStep: maximumStep) { sample in
                let point = retractedChartPoint(sample)
                if let last = points.last, isOnRetractionCircle(last), isOnRetractionCircle(point) {
                    points.append(contentsOf: retractionArc(from: last, to: point))
                }
                points.append(point)
            }
        }
        points.removeLast() // the closing sample repeats the first vertex
        return points
    }

    /// Whether `point` lies inside `ring` (even–odd rule, ring closed implicitly).
    static func contains(_ point: CGPoint, inRing ring: [CGPoint]) -> Bool {
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let a = ring[index], b = ring[previous]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside = !inside
            }
            previous = index
        }
        return inside
    }

    // MARK: Helpers

    /// Calls `body` with the directions along the great-circle arc from `a` to `b`, excluding `a`
    /// and including `b`, at most `maximumStep` degrees apart.
    private static func forEachArcSample(from a: Vector3, to b: Vector3, maximumStep: Double,
                                         _ body: (Vector3) -> Void) {
        let angle = a.angle(to: b)
        // Nearly opposite directions have no unique arc; step straight to the end.
        let steps = angle > 170 ? 1 : max(1, Int((angle / maximumStep).rounded(.up)))
        for step in 1..<steps {
            body((a * Double(steps - step) + b * Double(step)).normalized)
        }
        body(b)
    }

    private static func isOnRetractionCircle(_ point: CGPoint) -> Bool {
        point.x * point.x + point.y * point.y >= retractionRadius * retractionRadius * (1 - 1e-9)
    }

    /// Points strictly between `a` and `b` along the retraction circle, the short way round.
    private static func retractionArc(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let sweep = atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
        let steps = Int((abs(sweep) / (Double.pi / 12)).rounded(.up))
        guard steps > 1 else { return [] }
        let start = atan2(a.y, a.x)
        return (1..<steps).map { step in
            let angle = start + sweep * Double(step) / Double(steps)
            return CGPoint(x: retractionRadius * cos(angle), y: retractionRadius * sin(angle))
        }
    }
}

/// Rectangles around a centre, for markers and labels.
enum PlanisphereBounds {
    /// The square of side `2 * radius` around `center`.
    static func square(around center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }

    /// The rectangle of `size` around `center`.
    static func rect(around center: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

/// Collects the above-horizon pieces of a polyline whose samples arrive in order.
private struct PlanisphereHorizonClipper {
    private var polylines: [[CGPoint]] = []
    private var current: [CGPoint] = []
    private var previous: Vector3?

    mutating func append(_ direction: Vector3) {
        defer { previous = direction }
        let isVisible = direction.z >= 0
        guard let last = previous else {
            if isVisible { current = [PlanisphereProjection.chartPoint(direction)] }
            return
        }
        switch (last.z >= 0, isVisible) {
        case (true, true):
            current.append(PlanisphereProjection.chartPoint(direction))
        case (true, false):
            current.append(PlanisphereProjection.chartPoint(Self.horizonCrossing(last, direction)))
            flush()
        case (false, true):
            current = [PlanisphereProjection.chartPoint(Self.horizonCrossing(last, direction)),
                       PlanisphereProjection.chartPoint(direction)]
        case (false, false):
            break
        }
    }

    mutating func finish() -> [[CGPoint]] {
        flush()
        return polylines
    }

    private mutating func flush() {
        if current.count >= 2 { polylines.append(current) }
        current = []
    }

    /// Where the short arc from `a` (above the horizon) to `b` (below) or the reverse meets the horizon.
    private static func horizonCrossing(_ a: Vector3, _ b: Vector3) -> Vector3 {
        let fraction = a.z / (a.z - b.z)
        return (a + (b - a) * fraction).normalized
    }
}

/// How the chart is placed on the screen: size of the view, zoom, pan and rotation.
///
/// At zoom 1 the horizon circle fills the shorter side of the view, less a margin for the
/// cardinal letters. Panning moves the circle's centre; `rotation` turns the chart clockwise so
/// that the chosen azimuth points up (0 keeps north at the top).
struct PlanisphereViewport: Equatable, Sendable {
    /// Space kept free around the horizon circle at zoom 1, for the cardinal letters.
    static let rimMargin: CGFloat = 26
    /// At the strongest zoom a phone screen spans about 17° of sky near the zenith (less towards the horizon, where the
    /// projection stretches), enough to frame a short telephoto lens.
    static let zoomRange: ClosedRange<CGFloat> = 1...15

    let size: CGSize
    let zoom: CGFloat
    let pan: CGSize
    /// Clockwise rotation of the chart on the screen, in radians.
    let rotation: Double
    /// Screen points per chart unit: the radius of the horizon circle.
    let radius: CGFloat
    /// Screen position of the zenith.
    let center: CGPoint
    /// Cosine and sine of `rotation`.
    let cosine: CGFloat
    let sine: CGFloat

    init(size: CGSize, zoom: CGFloat = 1, pan: CGSize = .zero, rotation: Double = 0) {
        self.size = size
        self.zoom = zoom
        self.pan = pan
        self.rotation = rotation
        radius = Self.baseRadius(in: size) * zoom
        center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
        cosine = CGFloat(cos(rotation))
        sine = CGFloat(sin(rotation))
    }

    /// The horizon circle's radius at zoom 1.
    static func baseRadius(in size: CGSize) -> CGFloat {
        max(40, min(size.width, size.height) / 2 - rimMargin)
    }

    /// The square that bounds the horizon circle on the screen.
    var discRect: CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }

    /// The screen position of a chart point.
    func screen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * (point.x * cosine - point.y * sine),
                y: center.y + radius * (point.x * sine + point.y * cosine))
    }

    /// The chart point at a screen position: the inverse of `screen(_:)`.
    func chartPoint(atScreen position: CGPoint) -> CGPoint {
        let dx = (position.x - center.x) / radius
        let dy = (position.y - center.y) / radius
        return CGPoint(x: dx * cosine + dy * sine, y: dy * cosine - dx * sine)
    }

    /// The middle of the view, where a camera frame fixed on the screen sits.
    var middle: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Screen points per radian of sky at a chart point (the stereographic scale grows towards the horizon).
    func pointsPerRadian(at point: CGPoint) -> CGFloat {
        radius * (1 + point.x * point.x + point.y * point.y) / 2
    }

    /// The screen position `extra` points outside the horizon circle, towards `azimuth` (degrees).
    func rimPoint(azimuth: Double, outside extra: CGFloat) -> CGPoint {
        let direction = PlanisphereProjection.unitVector(towardsAzimuth: azimuth)
        let scale = 1 + extra / radius
        return screen(CGPoint(x: direction.x * scale, y: direction.y * scale))
    }

    // MARK: Zoom and pan

    /// The pan that keeps the chart point under `anchor` (a screen position) in place while the
    /// zoom changes from `oldZoom` to `newZoom`.
    static func pan(_ pan: CGSize, keeping anchor: CGPoint, fixedIn size: CGSize,
                    from oldZoom: CGFloat, to newZoom: CGFloat) -> CGSize {
        let ratio = newZoom / oldZoom
        let dx = anchor.x - size.width / 2
        let dy = anchor.y - size.height / 2
        return CGSize(width: dx - ratio * (dx - pan.width), height: dy - ratio * (dy - pan.height))
    }

    /// `pan` limited to the distance the zoomed chart overhangs the view, `baseRadius * (zoom - 1)`,
    /// so the middle of the view always stays on the chart; at zoom 1 the chart cannot be moved.
    /// With `reachesHorizon` (a camera frame fixed in the middle of the view) the limit is the radius of
    /// the horizon circle instead, so the middle can be moved anywhere on the sky, even at zoom 1.
    static func clampedPan(_ pan: CGSize, zoom: CGFloat, in size: CGSize, reachesHorizon: Bool = false) -> CGSize {
        let limit = baseRadius(in: size) * (reachesHorizon ? zoom : zoom - 1)
        let length = (pan.width * pan.width + pan.height * pan.height).squareRoot()
        guard length > limit else { return pan }
        guard limit > 0 else { return .zero }
        let scale = limit / length
        return CGSize(width: pan.width * scale, height: pan.height * scale)
    }
}
