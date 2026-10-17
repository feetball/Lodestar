import Foundation
import LodestarKit

/// Dot sizes and colours of the stars on the chart. Stars are drawn in batches that share a size
/// class and a colour class, so a frame needs one fill per batch instead of one per star.
enum SkyChartStarStyle {
    /// Dot diameters in points, faintest class first.
    static let diameters: [CGFloat] = [1.0, 1.4, 1.9, 2.5, 3.2, 4.0, 4.9, 6.0]
    /// Dot opacities, faintest class first.
    static let opacities: [Double] = [0.55, 0.65, 0.75, 0.85, 0.92, 1, 1, 1]
    /// A representative B−V colour index for each colour class: blue-white, white, yellow-white, orange, red.
    static let colorIndices: [Double] = [-0.15, 0.2, 0.65, 1.0, 1.6]

    /// The size class of a star: 0 for magnitude 6 and fainter, 7 for the brightest stars.
    static func sizeClass(magnitude: Double) -> Int {
        guard magnitude.isFinite else { return 0 }
        return Int(min(max((7 - magnitude).rounded(.down), 0), Double(diameters.count - 1)))
    }

    /// The colour class for a B−V colour index; stars without one count as white.
    static func colorClass(colorIndex: Double?) -> Int {
        guard let colorIndex, colorIndex.isFinite else { return 1 }
        switch colorIndex {
        case ..<0.0: return 0
        case ..<0.45: return 1
        case ..<0.8: return 2
        case ..<1.2: return 3
        default: return 4
        }
    }
}

/// Stars that share a dot size and colour, as chart points.
struct SkyChartStarGroup: Sendable {
    let sizeClass: Int
    let colorClass: Int
    let points: [CGPoint]
}

/// One brightness level of the Milky Way as chart polygons.
struct SkyChartMilkyWayLevel: Sendable {
    let level: Int
    /// Filled rings and holes; fill them together with the even–odd rule.
    let rings: [[CGPoint]]
    /// `true` when an odd number of the rings enclose the nadir, which the projection sends to
    /// infinity: the sky the level covers is then everything *outside* those rings, so the even–odd
    /// fill has to be run over a large square as well.
    let invertsFill: Bool
}

/// The Sun, the Moon or a planet.
struct SkyChartBodyMarker: Sendable, Identifiable {
    enum Kind: Sendable {
        case sun, moon, planet
    }

    let object: CelestialObject
    let kind: Kind
    let point: CGPoint
    let horizontal: HorizontalCoordinate
    let magnitude: Double?
    /// The lit fraction of the disc, when known.
    let illuminatedFraction: Double?
    /// The direction of the Sun seen from the body on the chart, in radians (chart axes, y down).
    /// Where the lit side of the Moon points.
    let towardsSunAngle: Double

    var id: String { object.id }
    var name: String { object.name }
    var isAboveHorizon: Bool { horizontal.altitude >= 0 }
}

/// A deep-sky object.
struct SkyChartDeepSkyMarker: Sendable, Identifiable {
    let id: String
    let point: CGPoint
    let group: ObjectGroup
    /// Apparent magnitude; objects without one count as 9.5 when deciding what to show.
    let magnitude: Double?
    /// The object's largest dimension in radians, when known.
    let extent: Double?
}

/// The aiming target.
struct SkyChartTargetMarker: Sendable {
    let object: CelestialObject
    let direction: Vector3
    let horizontal: HorizontalCoordinate

    var isAboveHorizon: Bool { direction.z >= 0 }
}

/// A text label on the chart.
struct SkyChartLabel: Sendable, Identifiable {
    enum Style: Sendable {
        case constellation, star, deepSky, body, target
    }

    /// Unique among the labels of a scene; also the id of the label's canvas symbol.
    let id: String
    let text: String
    let style: Style
    let point: CGPoint
    /// Labels that would overlap are resolved in favour of the higher priority.
    let priority: Int
    /// The label only appears once the chart is zoomed in this far.
    let minimumZoom: CGFloat
    /// Distance in points between the labelled point and the label; the label sits beside the
    /// point when this is positive and is centred on it when zero.
    let offset: CGFloat

    /// Orders labels by priority, then by id so that equal priorities keep a stable order between scenes.
    static func isHigherPriority(_ a: SkyChartLabel, _ b: SkyChartLabel) -> Bool {
        a.priority != b.priority ? a.priority > b.priority : a.id < b.id
    }
}

/// Something a tap can select.
struct SkyChartPickable: Sendable {
    enum Kind: Sendable {
        case target, body, deepSky, star

        /// Scales the distance to a tap: objects that are rarer or more important win ties.
        var distanceBias: CGFloat {
            switch self {
            case .target, .body: return 0.5
            case .deepSky: return 0.8
            case .star: return 1
            }
        }
    }

    let id: String
    let kind: Kind
    let point: CGPoint
    /// The object itself when the snapshot has it; stars are looked up in the catalog by `id`.
    let object: CelestialObject?
}

/// Everything the planisphere draws for one instant and observer, in chart space: derived from a
/// `SkySnapshot` off the main actor and rotated, scaled and clipped by the views.
struct SkyChartScene: Sendable {
    let date: Date
    let observer: Observer
    /// Faintest first, so brighter dots are drawn on top.
    let starGroups: [SkyChartStarGroup]
    let constellationLines: [[CGPoint]]
    let milkyWay: [SkyChartMilkyWayLevel]
    /// The Sun, Moon and planets, including those below the horizon.
    let bodies: [SkyChartBodyMarker]
    let deepSky: [SkyChartDeepSkyMarker]
    let target: SkyChartTargetMarker?
    /// Highest priority first.
    let labels: [SkyChartLabel]
    let pickables: [SkyChartPickable]
}

extension SkyChartScene {
    /// The thing a tap at `location` selects: the nearest pickable within `tolerance` points, where
    /// a planet or the target counts as closer than a star at the same distance.
    func pickable(near location: CGPoint, in viewport: PlanisphereViewport,
                  tolerance: CGFloat = 24) -> SkyChartPickable? {
        var best: (pickable: SkyChartPickable, score: CGFloat)?
        for pickable in pickables {
            let point = viewport.screen(pickable.point)
            let distance = hypot(point.x - location.x, point.y - location.y)
            guard distance <= tolerance else { continue }
            let score: CGFloat = distance * pickable.kind.distanceBias
            if let current = best, current.score <= score { continue }
            best = (pickable, score)
        }
        return best?.pickable
    }
}

/// Turns a `SkySnapshot` into a `SkyChartScene`. Pure, so it runs on any thread.
enum SkyChartSceneBuilder {
    /// The most labels of each kind a scene carries; the views place as many as fit.
    private static let constellationLabelLimit = 60
    private static let starLabelLimit = 30
    private static let deepSkyLabelLimit = 50
    /// Only stars at least this bright get a name label.
    private static let starLabelMagnitude = 3.2
    /// Label anchors this far above the horizon (sine of the altitude) or higher are kept.
    private static let labelHorizon = 0.03

    static func build(from snapshot: SkySnapshot) -> SkyChartScene {
        let sun = snapshot.bodies.first { $0.object.id == "sun" }
        let bodies = snapshot.bodies.map { bodyMarker($0, sun: sun) }
        let deepSky = deepSkyMarkers(snapshot.deepSky)
        let target = snapshot.target.map {
            SkyChartTargetMarker(object: $0.object, direction: $0.direction, horizontal: $0.horizontal)
        }
        let (constellationLines, constellationLabels) = constellations(snapshot.constellations)

        var labels = constellationLabels
        labels += starLabels(snapshot.stars)
        labels += deepSkyLabels(snapshot.deepSky)
        labels += bodies.filter(\.isAboveHorizon).map(bodyLabel)
        if let target, target.isAboveHorizon {
            labels.append(SkyChartLabel(id: "target.\(target.object.id)", text: target.object.name, style: .target,
                                        point: PlanisphereProjection.chartPoint(target.direction),
                                        priority: 100, minimumZoom: 1, offset: 22))
        }
        labels.sort(by: SkyChartLabel.isHigherPriority)

        return SkyChartScene(
            date: snapshot.date, observer: snapshot.observer,
            starGroups: starGroups(snapshot.stars),
            constellationLines: constellationLines,
            milkyWay: milkyWay(snapshot),
            bodies: bodies, deepSky: deepSky, target: target,
            labels: labels,
            pickables: pickables(snapshot, bodies: bodies, target: target))
    }

    // MARK: Stars

    private static func starGroups(_ stars: [SkySnapshot.Star]) -> [SkyChartStarGroup] {
        let colorCount = SkyChartStarStyle.colorIndices.count
        var batches: [Int: [CGPoint]] = [:]
        for star in stars where star.direction.z >= 0 {
            let key = SkyChartStarStyle.sizeClass(magnitude: star.magnitude) * colorCount
                + SkyChartStarStyle.colorClass(colorIndex: star.colorIndex)
            batches[key, default: []].append(PlanisphereProjection.chartPoint(star.direction))
        }
        return batches.sorted { $0.key < $1.key }.map { key, points in
            SkyChartStarGroup(sizeClass: key / colorCount, colorClass: key % colorCount, points: points)
        }
    }

    private static func starLabels(_ stars: [SkySnapshot.Star]) -> [SkyChartLabel] {
        let named = stars.filter {
            $0.name != nil && $0.direction.z > labelHorizon && $0.magnitude <= starLabelMagnitude
        }
        let brightest = named.sorted { $0.magnitude != $1.magnitude ? $0.magnitude < $1.magnitude : $0.id < $1.id }
        return brightest.prefix(starLabelLimit).compactMap { star in
            guard let name = star.name else { return nil }
            let zoom: CGFloat = star.magnitude <= 1.5 ? 1 : (star.magnitude <= 2.4 ? 1.6 : 2.5)
            return SkyChartLabel(id: "star.\(star.id)", text: name, style: .star,
                                 point: PlanisphereProjection.chartPoint(star.direction),
                                 priority: 50 + Int(((starLabelMagnitude - star.magnitude) * 4).rounded()),
                                 minimumZoom: zoom, offset: 6)
        }
    }

    // MARK: Constellations

    private static func constellations(_ figures: [SkySnapshot.ConstellationFigure])
        -> (lines: [[CGPoint]], labels: [SkyChartLabel]) {
        var lines: [[CGPoint]] = []
        var labels: [SkyChartLabel] = []
        for figure in figures {
            for line in figure.lines {
                lines += PlanisphereProjection.visiblePolylines(through: line)
            }
            guard figure.label.z > labelHorizon else { continue }
            let size = figure.lines.reduce(0) { $0 + $1.count }
            labels.append(SkyChartLabel(id: "constellation.\(figure.abbreviation)", text: figure.name,
                                        style: .constellation, point: PlanisphereProjection.chartPoint(figure.label),
                                        priority: 20 + min(size, 60) / 4, minimumZoom: 1, offset: 0))
        }
        labels.sort(by: SkyChartLabel.isHigherPriority)
        return (lines, Array(labels.prefix(constellationLabelLimit)))
    }

    // MARK: Milky Way

    private static func milkyWay(_ snapshot: SkySnapshot) -> [SkyChartMilkyWayLevel] {
        guard !snapshot.milkyWay.isEmpty else { return [] }
        // The celestial pole above the horizon lies outside every Milky Way outline; the outline
        // rings that enclose it in the projection are the ones that enclose the nadir instead.
        let pole = snapshot.frame.horizontalOfCelestialPole(north: snapshot.observer.location.latitude >= 0,
                                                            refraction: true)
        let reference = PlanisphereProjection.retractedChartPoint(pole.unitVector)
        return snapshot.milkyWay.map { band in
            let rings = (band.polygons + band.holes)
                .map { PlanisphereProjection.ring(through: $0) }
                .filter { !$0.isEmpty }
            let enclosing = rings.filter { PlanisphereProjection.contains(reference, inRing: $0) }.count
            return SkyChartMilkyWayLevel(level: band.level, rings: rings, invertsFill: enclosing % 2 == 1)
        }
    }

    // MARK: Solar system

    private static func bodyMarker(_ body: SkySnapshot.Body, sun: SkySnapshot.Body?) -> SkyChartBodyMarker {
        let kind: SkyChartBodyMarker.Kind
        switch body.object.category {
        case .sun: kind = .sun
        case .moon: kind = .moon
        default: kind = .planet
        }
        let point = PlanisphereProjection.retractedChartPoint(body.direction)
        return SkyChartBodyMarker(
            object: body.object, kind: kind, point: point, horizontal: body.horizontal,
            magnitude: body.magnitude, illuminatedFraction: body.illuminatedFraction,
            towardsSunAngle: sun.map { towardsAngle(from: body.direction, to: $0.direction) } ?? 0)
    }

    /// The direction on the chart in which the great circle from `origin` to `other` leaves `origin`.
    private static func towardsAngle(from origin: Vector3, to other: Vector3) -> Double {
        let tangent = (other - origin * origin.dot(other)).normalized
        guard tangent != .zero else { return 0 }
        let here = PlanisphereProjection.retractedChartPoint(origin)
        let ahead = PlanisphereProjection.retractedChartPoint((origin + tangent * 0.01).normalized)
        return atan2(Double(ahead.y - here.y), Double(ahead.x - here.x))
    }

    private static func bodyLabel(_ body: SkyChartBodyMarker) -> SkyChartLabel {
        SkyChartLabel(id: "body.\(body.id)", text: body.name, style: .body, point: body.point,
                      priority: body.kind == .planet ? 90 : 95, minimumZoom: 1, offset: 12)
    }

    // MARK: Deep-sky objects

    private static func deepSkyMarkers(_ objects: [SkySnapshot.DeepSky]) -> [SkyChartDeepSkyMarker] {
        objects.filter { $0.direction.z >= 0 }.map { item in
            SkyChartDeepSkyMarker(id: item.object.id, point: PlanisphereProjection.chartPoint(item.direction),
                                  group: item.object.group, magnitude: item.object.magnitude,
                                  extent: item.majorAxis.map { AstroMath.radians($0) })
        }
    }

    private static func deepSkyLabels(_ objects: [SkySnapshot.DeepSky]) -> [SkyChartLabel] {
        let visible = objects.filter { $0.direction.z > labelHorizon }
        let brightest = visible.sorted {
            let (a, b) = (rankingMagnitude($0.object), rankingMagnitude($1.object))
            return a != b ? a < b : $0.object.id < $1.object.id
        }
        return brightest.prefix(deepSkyLabelLimit).map { item in
            let magnitude = rankingMagnitude(item.object)
            let zoom: CGFloat = magnitude <= 5 ? 1.8 : (magnitude <= 7 ? 2.8 : (magnitude <= 9 ? 4 : 5))
            return SkyChartLabel(id: "deepSky.\(item.object.id)", text: item.object.name, style: .deepSky,
                                 point: PlanisphereProjection.chartPoint(item.direction),
                                 priority: 25 - Int(min(magnitude, 20) / 2), minimumZoom: zoom, offset: 7)
        }
    }

    /// The magnitude used to rank deep-sky objects; 99 when it is unknown.
    private static func rankingMagnitude(_ object: CelestialObject) -> Double {
        guard let magnitude = object.magnitude, magnitude.isFinite else { return 99 }
        return magnitude
    }

    // MARK: Picking

    private static func pickables(_ snapshot: SkySnapshot, bodies: [SkyChartBodyMarker],
                                  target: SkyChartTargetMarker?) -> [SkyChartPickable] {
        var result: [SkyChartPickable] = []
        if let target, target.isAboveHorizon {
            result.append(SkyChartPickable(id: target.object.id, kind: .target,
                                           point: PlanisphereProjection.chartPoint(target.direction),
                                           object: target.object))
        }
        for body in bodies where body.isAboveHorizon {
            result.append(SkyChartPickable(id: body.id, kind: .body, point: body.point, object: body.object))
        }
        for item in snapshot.deepSky where item.direction.z >= 0 {
            result.append(SkyChartPickable(id: item.object.id, kind: .deepSky,
                                           point: PlanisphereProjection.chartPoint(item.direction),
                                           object: item.object))
        }
        for star in snapshot.stars where star.direction.z >= 0 {
            result.append(SkyChartPickable(id: star.id, kind: .star,
                                           point: PlanisphereProjection.chartPoint(star.direction), object: nil))
        }
        return result
    }
}
