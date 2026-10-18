import Foundation

/// A point of the galactic plane.
public struct MilkyWayPoint: Hashable, Sendable {
    /// The galactic longitude in degrees, [0, 360); 0° is the galactic centre.
    public let galacticLongitude: Double
    /// Where the point stands in the sky.
    public let horizontal: HorizontalCoordinate
}

/// The Milky Way above the horizon at one moment.
///
/// Created by `MilkyWayPanorama.arch` only.
public struct MilkyWayArch: Hashable, Sendable {
    /// The part of the galactic plane (galactic latitude 0) above `minimumAltitude` as a polyline in azimuth and
    /// altitude, in order of increasing galactic longitude. Always one connected stretch: the plane is a great
    /// circle, so half of it is up. Empty when none of it is.
    public let path: [MilkyWayPoint]
    /// The highest point of `path`, or nil if the path is empty.
    public let highestPoint: MilkyWayPoint?
    /// The angle between the galactic plane and the horizon in degrees, [0, 90]: the altitude of the highest
    /// point of a full arch. 0 means the plane lies along the horizon, 90 that it passes through the zenith.
    public let inclination: Double
    /// Where the galactic centre (galactic longitude 0, latitude 0) stands, possibly below the horizon.
    public let core: HorizontalCoordinate
    /// The angle in degrees, [0, 90], between the galactic plane and the horizontal direction at the galactic
    /// centre: 0 where the plane runs along the horizon there, 90 where it stands upright. Nil when the centre
    /// is within about 0.06 degrees of the zenith or the nadir, where "horizontal" has no direction.
    public let coreTilt: Double?
    /// The altitude above which `path` was built, in degrees.
    public let minimumAltitude: Double

    /// A horizontal panorama box that covers the part of the arch above `minimumAltitude`, for
    /// `MosaicPlanner.plan`.
    ///
    /// The azimuth range runs from the arch's smallest to its largest azimuth, followed along the path so
    /// that an arch passing near the zenith is measured correctly, and both are widened by `margin`. The
    /// altitude range runs from the lowest to the highest point, widened by `margin` and limited to the sky.
    /// The box is at least one degree wide and one degree high.
    ///
    /// - Parameters:
    ///   - minimumAltitude: Points lower than this are left out, in degrees (not finite: 5°). Raising it
    ///     excludes the murky horizon and narrows the azimuth span.
    ///   - margin: The margin in degrees on every side, [0, 45] (not finite: 5°).
    /// - Returns: The region, or nil if no point of the path is above `minimumAltitude`.
    public func panoramaRegion(minimumAltitude: Double = MilkyWayPanorama.defaultPanoramaMinimumAltitude,
                               margin: Double = MilkyWayPanorama.defaultPanoramaMargin) -> MosaicRegion? {
        let floorAltitude = minimumAltitude.isFinite
            ? AstroMath.clamp(minimumAltitude, -90, 90)
            : MilkyWayPanorama.defaultPanoramaMinimumAltitude
        let border = margin.isFinite ? AstroMath.clamp(margin, 0, 45) : MilkyWayPanorama.defaultPanoramaMargin
        let points = path.filter { $0.horizontal.altitude >= floorAltitude }
        guard !points.isEmpty else { return nil }
        var unwrapped = points[0].horizontal.azimuth
        var lowestAzimuth = unwrapped
        var highestAzimuth = unwrapped
        var lowestAltitude = points[0].horizontal.altitude
        var highestAltitude = lowestAltitude
        for index in 1..<max(points.count, 1) {
            unwrapped += AstroMath.normalizeSignedDegrees(points[index].horizontal.azimuth - points[index - 1].horizontal.azimuth)
            lowestAzimuth = min(lowestAzimuth, unwrapped)
            highestAzimuth = max(highestAzimuth, unwrapped)
            lowestAltitude = min(lowestAltitude, points[index].horizontal.altitude)
            highestAltitude = max(highestAltitude, points[index].horizontal.altitude)
        }
        var lower = AstroMath.clamp(lowestAltitude - border, -90, 90)
        var upper = AstroMath.clamp(highestAltitude + border, -90, 90)
        if upper - lower < 1 {
            upper = min(90, lower + 1)
            lower = upper - 1
        }
        return .horizontal(azimuthStart: AstroMath.normalizeDegrees(lowestAzimuth - border),
                           azimuthSpan: min(360, max(1, (highestAzimuth - lowestAzimuth) + 2 * border)),
                           minimumAltitude: lower, maximumAltitude: upper)
    }
}

/// A moment at which the Milky Way's core is well placed, with the state of the sky then.
public struct MilkyWayMoment: Hashable, Sendable {
    /// The instant.
    public let date: Date
    /// The geometric altitude of the galactic centre in degrees.
    public let coreAltitude: Double
    /// The azimuth of the galactic centre in degrees from north through east.
    public let coreAzimuth: Double
    /// The tilt of the galactic plane at the centre, see `MilkyWayArch.coreTilt`.
    public let coreTilt: Double?
    /// The inclination of the galactic plane to the horizon, see `MilkyWayArch.inclination`.
    public let inclination: Double
}

/// The best moments of a night for the Milky Way's core and arch. Any of them is nil when the core never
/// rises high enough in the time searched.
public struct MilkyWayBestTimes: Hashable, Sendable {
    /// When the galactic centre is highest.
    public let coreHighest: MilkyWayMoment?
    /// When the galactic plane lies flattest along the horizon at the centre (smallest tilt).
    public let mostHorizontal: MilkyWayMoment?
    /// When the galactic plane stands steepest at the centre (largest tilt).
    public let mostVertical: MilkyWayMoment?
}

/// Helpers for photographing the Milky Way as a panorama: the arch above the horizon, a panorama box that
/// covers it, and the best times of a night.
///
/// "Tilt" is measured at the galactic centre: the angle between the galactic plane's direction there and the
/// horizontal direction (the one along the horizon). Where the centre is up, a small tilt means the plane
/// runs along the horizon past it, as in the spring pre-dawn Milky Way that lies flat above the south-eastern
/// horizon, and a large tilt means the plane rises steeply from the horizon through it, as in the upright core of
/// an autumn evening.
public enum MilkyWayPanorama {
    /// The default spacing of the sampled galactic longitudes in degrees.
    public static let defaultLongitudeStep = 1.0

    /// The default lowest altitude of a panorama box in degrees: below it the haze hides the Milky Way.
    public static let defaultPanoramaMinimumAltitude = 5.0

    /// The default margin around a panorama box in degrees.
    public static let defaultPanoramaMargin = 5.0

    /// The sampling step of the best-time search in seconds.
    static let searchStep = 600.0

    /// The most samples the best-time search takes within one interval.
    static let maximumSamplesPerInterval = 5_000

    private static let coreDirection = CoordinateTransforms.equatorialJ2000ToGalacticMatrix.r0

    private static let planeTangent = CoordinateTransforms.equatorialJ2000ToGalacticMatrix.r1

    private static let poleDirection = CoordinateTransforms.equatorialJ2000ToGalacticMatrix.r2

    /// The Milky Way above the horizon for the instant and observer of `frame`.
    ///
    /// Samples the galactic plane every `longitudeStep` degrees of galactic longitude (360 points by default),
    /// so a call costs a few hundred horizontal conversions: well under a millisecond.
    ///
    /// - Parameters:
    ///   - frame: The instant and observer.
    ///   - minimumAltitude: Points lower than this are left out of the path, in degrees, limited to [−90, 90]
    ///     (not finite: 0).
    ///   - longitudeStep: The spacing of the samples in degrees, limited to [0.25, 10] (not finite or not
    ///     positive: 1).
    ///   - refraction: Whether to raise the altitudes by atmospheric refraction.
    public static func arch(frame: SkyFrame, minimumAltitude: Double = 0, longitudeStep: Double = MilkyWayPanorama.defaultLongitudeStep,
                            refraction: Bool = true) -> MilkyWayArch {
        let floorAltitude = minimumAltitude.isFinite ? AstroMath.clamp(minimumAltitude, -90, 90) : 0
        let step = longitudeStep.isFinite && longitudeStep > 0
            ? AstroMath.clamp(longitudeStep, 0.25, 10)
            : defaultLongitudeStep
        let count = Int(ceil(360 / step - 1e-9))
        let samples = (0..<count).map { index -> MilkyWayPoint in
            let longitude = Double(index) * step
            let place = CoordinateTransforms.galacticToEquatorialJ2000(GalacticCoordinate(longitude: longitude, latitude: 0))
            return MilkyWayPoint(galacticLongitude: longitude,
                                 horizontal: frame.horizontal(j2000: place, properMotion: nil, refraction: refraction))
        }
        let up = samples.map { $0.horizontal.altitude >= floorAltitude }

        var first = -1
        for index in 0..<count where up[index] && !up[(index + count - 1) % count] {
            first = index
            break
        }
        var path = [MilkyWayPoint]()
        if first >= 0 {
            var index = first
            while up[index % count] && path.count < count {
                path.append(samples[index % count])
                index += 1
            }
        } else if up.allSatisfy({ $0 }) {
            path.append(contentsOf: samples)
        }

        let normal = frame.horizontalVector(j2000UnitVector: poleDirection).normalized
        let towardsZenith = Vector3(0, 0, 1) - normal * normal.z
        var highest: MilkyWayPoint?
        if towardsZenith.length > 1e-9 {
            let geometric = HorizontalCoordinate(vector: towardsZenith.normalized)
            let apparent = refraction ? SkyFrame.refracted(geometric, atmosphere: frame.observer.atmosphere) : geometric
            if apparent.altitude >= floorAltitude {
                let galactic = CoordinateTransforms.equatorialJ2000ToGalactic(frame.j2000(fromHorizontal: geometric, refracted: false))
                highest = MilkyWayPoint(galacticLongitude: galactic.longitude, horizontal: apparent)
            }
        } else {
            for point in path {
                if let best = highest {
                    if point.horizontal.altitude > best.horizontal.altitude { highest = point }
                } else {
                    highest = point
                }
            }
        }

        let core = frame.horizontal(j2000: EquatorialCoordinate(vector: coreDirection), properMotion: nil, refraction: refraction)
        return MilkyWayArch(path: path, highestPoint: highest, inclination: AstroMath.acosDeg(abs(normal.z)), core: core,
                            coreTilt: tilt(frame: frame, core: frame.horizontalVector(j2000UnitVector: coreDirection).normalized),
                            minimumAltitude: floorAltitude)
    }

    /// The best moments for the Milky Way's core within a night, from its `NightSummary`.
    ///
    /// - Parameters:
    ///   - summary: The night.
    ///   - darkness: Which dark hours to search: astronomical darkness or the part with the Moon down.
    ///   - minimumCoreAltitude: The lowest altitude, in degrees, at which the core counts as usable.
    public static func bestTimes(summary: NightSummary, darkness: DarknessKind = .astronomical,
                                 minimumCoreAltitude: Double = MilkyWayCoreVisibility.minimumAltitude) -> MilkyWayBestTimes {
        bestTimes(observer: summary.observer, intervals: summary.darkness(darkness), minimumCoreAltitude: minimumCoreAltitude)
    }

    /// The best moments for the Milky Way's core within `intervals`.
    ///
    /// The core is sampled every ten minutes and the best samples are refined by a golden-section search. A
    /// moment only counts while the core is at least `minimumCoreAltitude` high. The three results are
    /// - `coreHighest`: the greatest core altitude;
    /// - `mostHorizontal`: the smallest tilt of the galactic plane at the core;
    /// - `mostVertical`: the largest tilt.
    ///
    /// An hour of search costs about six conversions; a whole night, around a hundred microseconds each.
    ///
    /// - Parameters:
    ///   - observer: The place of observation.
    ///   - intervals: The times to search, for example the dark hours of a night.
    ///   - minimumCoreAltitude: The lowest usable core altitude in degrees (not finite: 10).
    public static func bestTimes(observer: Observer, intervals: [DateInterval],
                                 minimumCoreAltitude: Double = MilkyWayCoreVisibility.minimumAltitude) -> MilkyWayBestTimes {
        let floorAltitude = minimumCoreAltitude.isFinite
            ? AstroMath.clamp(minimumCoreAltitude, -90, 90)
            : MilkyWayCoreVisibility.minimumAltitude
        let objectives: [(CoreState) -> Double] = [
            { state in state.altitude >= floorAltitude ? state.altitude : -Double.infinity },
            { state in
                if let tilt = state.tilt, state.altitude >= floorAltitude { return -tilt }
                return -Double.infinity
            },
            { state in
                if let tilt = state.tilt, state.altitude >= floorAltitude { return tilt }
                return -Double.infinity
            },
        ]
        let moments = objectives.map { best(observer: observer, intervals: intervals, score: $0) }
        return MilkyWayBestTimes(coreHighest: moments[0], mostHorizontal: moments[1], mostVertical: moments[2])
    }

    // MARK: Search

    /// The state of the core and the plane at one instant.
    struct CoreState {
        let date: Date
        let altitude: Double
        let azimuth: Double
        let tilt: Double?
        let inclination: Double
    }

    static func state(observer: Observer, date: Date) -> CoreState {
        let frame = SkyFrame(date: date, observer: observer)
        let core = frame.horizontalVector(j2000UnitVector: coreDirection).normalized
        let normal = frame.horizontalVector(j2000UnitVector: poleDirection).normalized
        let horizontal = HorizontalCoordinate(vector: core)
        return CoreState(date: date, altitude: horizontal.altitude, azimuth: horizontal.azimuth,
                         tilt: tilt(frame: frame, core: core), inclination: AstroMath.acosDeg(abs(normal.z)))
    }

    /// The angle between the plane's direction at the core and the horizontal direction there; nil near the zenith.
    private static func tilt(frame: SkyFrame, core: Vector3) -> Double? {
        let horizontalLength = hypot(core.x, core.y)
        guard horizontalLength > 0.001 else { return nil }
        let rotated = frame.j2000ToHorizontal * planeTangent
        let tangent = (rotated - core * rotated.dot(core)).normalized
        let level = Vector3(-core.y, core.x, 0) / horizontalLength
        return AstroMath.acosDeg(min(1, abs(tangent.dot(level))))
    }

    private static func best(observer: Observer, intervals: [DateInterval], score: (CoreState) -> Double) -> MilkyWayMoment? {
        var bestScore = -Double.infinity
        var bestInterval: DateInterval?
        var bestOffset = 0.0
        var bestStep = 0.0
        for interval in intervals {
            let duration = interval.duration
            let count = duration > 0 ? Int(min(Double(maximumSamplesPerInterval), ceil(duration / searchStep))) : 0
            let step = count > 0 ? duration / Double(count) : 0
            for index in 0...count {
                let offset = Double(index) * step
                let value = score(state(observer: observer, date: interval.start.addingTimeInterval(offset)))
                if value > bestScore {
                    bestScore = value
                    bestInterval = interval
                    bestOffset = offset
                    bestStep = step
                }
            }
        }
        guard let interval = bestInterval else { return nil }

        // Golden-section search for the maximum around the best sample.
        let ratio = 0.618_033_988_749_894_9
        var low = max(0, bestOffset - bestStep)
        var high = min(interval.duration, bestOffset + bestStep)
        func evaluate(_ offset: Double) -> Double {
            score(state(observer: observer, date: interval.start.addingTimeInterval(offset)))
        }
        var c = high - ratio * (high - low)
        var d = low + ratio * (high - low)
        var fc = evaluate(c)
        var fd = evaluate(d)
        for _ in 0..<40 {
            if fc > fd {
                high = d
                d = c
                fd = fc
                c = high - ratio * (high - low)
                fc = evaluate(c)
            } else {
                low = c
                c = d
                fc = fd
                d = low + ratio * (high - low)
                fd = evaluate(d)
            }
        }
        let refined = (low + high) / 2
        let offset = evaluate(refined) >= bestScore ? refined : bestOffset
        let result = state(observer: observer, date: interval.start.addingTimeInterval(offset))
        return MilkyWayMoment(date: result.date, coreAltitude: result.altitude, coreAzimuth: result.azimuth,
                              coreTilt: result.tilt, inclination: result.inclination)
    }
}
