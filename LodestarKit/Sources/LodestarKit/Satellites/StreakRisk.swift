import Foundation

/// The camera's field of view on the sky, in the horizon (ENU) frame: a rectangle of a rectilinear lens.
///
/// The frame has an optical axis (`boresight`), an upward and a rightward axis of the picture, and a width and
/// height in degrees (the angles across the sensor's width and height, as `FieldOfView` computes them). A
/// direction is in the frame when its gnomonic (tangent-plane) coordinates `x = (d·right)/(d·boresight)`,
/// `y = (d·up)/(d·boresight)` satisfy `|x| ≤ tan(width/2)` and `|y| ≤ tan(height/2)`.
///
/// **Roll.** 0° means the picture's horizontal edges are level (the camera held in landscape orientation on a
/// level tripod head); a positive roll turns the camera clockwise as the photographer sees it, as in
/// `PointingSolution.roll`. A portrait frame is a landscape frame with swapped width and height or a roll of 90°.
/// Looking at the zenith or nadir, "level" has no meaning and the picture's up is north.
public struct CameraFrame: Hashable, Sendable {
    /// The largest accepted width or height, in degrees (a rectilinear lens cannot reach 180°).
    public static let maximumFieldOfView = 170.0

    /// The optical axis as an ENU unit vector.
    public let boresight: Vector3
    /// The picture's upward direction, an ENU unit vector perpendicular to `boresight`.
    public let up: Vector3
    /// The picture's rightward direction (`boresight × up`).
    public let right: Vector3
    /// The angle across the picture's width.
    public let widthDegrees: Double
    /// The angle across the picture's height.
    public let heightDegrees: Double

    /// `tan(width / 2)`: the half-width of the picture on the tangent plane.
    let halfWidth: Double
    /// `tan(height / 2)`: the half-height of the picture on the tangent plane.
    let halfHeight: Double

    private init(boresight: Vector3, up: Vector3, right: Vector3, widthDegrees: Double, heightDegrees: Double) {
        self.boresight = boresight
        self.up = up
        self.right = right
        self.widthDegrees = widthDegrees
        self.heightDegrees = heightDegrees
        self.halfWidth = tan(AstroMath.radians(widthDegrees) / 2.0)
        self.halfHeight = tan(AstroMath.radians(heightDegrees) / 2.0)
    }

    /// Creates a frame looking along `boresight` with the given size and roll.
    ///
    /// - Parameters:
    ///   - widthDegrees: Angle across the width, above 0 and at most `maximumFieldOfView`.
    ///   - heightDegrees: Angle across the height, same range.
    ///   - rollDegrees: Clockwise roll of the camera in degrees (see the type description).
    /// - Returns: the frame, or `nil` if a value is not finite or out of range.
    public init?(boresight: HorizontalCoordinate, widthDegrees: Double, heightDegrees: Double, rollDegrees: Double = 0.0) {
        guard Self.validSize(widthDegrees, heightDegrees), rollDegrees.isFinite else { return nil }
        let forward = boresight.unitVector
        var level = Vector3(0.0, 0.0, 1.0) - forward * forward.z
        if level.length < 1.0e-6 { level = Vector3(0.0, 1.0, 0.0) - forward * forward.y }
        let upLevel = level.normalized
        let rightLevel = forward.cross(upLevel)
        let c = AstroMath.cosDeg(rollDegrees)
        let s = AstroMath.sinDeg(rollDegrees)
        let up = upLevel * c + rightLevel * s
        let right = rightLevel * c - upLevel * s
        self.init(boresight: forward, up: up, right: right, widthDegrees: widthDegrees, heightDegrees: heightDegrees)
    }

    /// Creates a frame from the pointing the Aim screen measured (its optical axis, up and right vectors).
    ///
    /// - Returns: the frame, or `nil` if a size is not finite or out of range.
    public init?(solution: PointingSolution, widthDegrees: Double, heightDegrees: Double) {
        guard Self.validSize(widthDegrees, heightDegrees) else { return nil }
        self.init(
            boresight: solution.boresightVector.normalized,
            up: solution.cameraUpVector.normalized,
            right: solution.cameraRightVector.normalized,
            widthDegrees: widthDegrees,
            heightDegrees: heightDegrees
        )
    }

    private static func validSize(_ widthDegrees: Double, _ heightDegrees: Double) -> Bool {
        widthDegrees.isFinite && heightDegrees.isFinite && widthDegrees > 0.0 && heightDegrees > 0.0
            && widthDegrees <= maximumFieldOfView && heightDegrees <= maximumFieldOfView
    }

    /// The angle from the optical axis to a corner of the picture, in degrees.
    public var cornerAngle: Double {
        AstroMath.degrees(atan((halfWidth * halfWidth + halfHeight * halfHeight).squareRoot()))
    }

    /// The optical axis as azimuth and altitude.
    public var boresightCoordinate: HorizontalCoordinate { HorizontalCoordinate(vector: boresight) }

    /// The position of a direction on the picture, `x` and `y` scaled so that the edges are at ±1 (`x` to the
    /// right, `y` upward); `nil` for a direction at or behind the plane of the camera.
    public func position(of direction: Vector3) -> FramePosition? {
        let depth = direction.dot(boresight)
        if !(depth > 1.0e-9) { return nil }
        return FramePosition(x: direction.dot(right) / depth / halfWidth, y: direction.dot(up) / depth / halfHeight)
    }

    /// `true` when the direction (any non-zero ENU vector) is inside the picture.
    public func contains(_ direction: Vector3) -> Bool {
        guard let p = position(of: direction) else { return false }
        return p.x >= -1.0 && p.x <= 1.0 && p.y >= -1.0 && p.y <= 1.0
    }
}

/// A position on the picture: `x` to the right and `y` upward, each −1 ... +1 from edge to edge inside the frame.
public struct FramePosition: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Where a satellite enters or leaves the picture.
public struct CrossingPoint: Hashable, Sendable {
    /// The instant.
    public let date: Date
    /// The satellite's azimuth in degrees.
    public let azimuth: Double
    /// The satellite's geometric altitude in degrees.
    public let altitude: Double
    /// Its position on the picture (on the edge, ±1 in at least one coordinate; `nil` if it could not be computed).
    public let position: FramePosition?

    public init(date: Date, azimuth: Double, altitude: Double, position: FramePosition?) {
        self.date = date
        self.azimuth = azimuth
        self.altitude = altitude
        self.position = position
    }
}

/// A sunlit satellite crossing the picture during an exposure.
public struct SatelliteCrossing: Sendable {
    /// The satellite.
    public let satellite: Satellite
    /// Where the streak starts: the satellite enters the picture, rises above the horizon or leaves the Earth's
    /// shadow, whichever happens last.
    public let entry: CrossingPoint
    /// Where the streak ends.
    public let exit: CrossingPoint
    /// `true` when the streak is already under way when the exposure starts (`entry` is then the exposure's start).
    public let startsBeforeExposure: Bool
    /// `true` when it continues after the exposure ends (`exit` is the exposure's end).
    public let endsAfterExposure: Bool
    /// The apparent magnitude in the middle of the crossing, if the intrinsic magnitude is known.
    public let magnitude: Double?

    public init(
        satellite: Satellite, entry: CrossingPoint, exit: CrossingPoint, startsBeforeExposure: Bool,
        endsAfterExposure: Bool, magnitude: Double?
    ) {
        self.satellite = satellite
        self.entry = entry
        self.exit = exit
        self.startsBeforeExposure = startsBeforeExposure
        self.endsAfterExposure = endsAfterExposure
        self.magnitude = magnitude
    }

    /// Seconds the satellite spends in the picture during the exposure.
    public var duration: Double { exit.date.timeIntervalSince(entry.date) }
}

/// Settings of `StreakRisk.assess`.
public struct StreakOptions: Hashable, Sendable {
    /// Satellites below this geometric altitude (degrees) do not count as streaks; 0 is the horizon.
    public var minimumAltitude: Double
    /// The altitude above which satellites are counted for `StreakAssessment.sunlitAboveSummaryAltitudeCount`
    /// ("sunlit satellites above 20° right now").
    public var summaryAltitude: Double
    /// The time span in seconds over which `StreakAssessment.crossingsPerMinute` is estimated; the exposure is
    /// used if it is longer.
    public var rateWindow: Double
    /// When set, a crossing whose magnitude is known and fainter than this is dropped (satellites with an unknown
    /// magnitude always stay).
    public var limitingMagnitude: Double?

    public init(minimumAltitude: Double = 0.0, summaryAltitude: Double = 20.0, rateWindow: Double = 120.0, limitingMagnitude: Double? = nil) {
        self.minimumAltitude = minimumAltitude
        self.summaryAltitude = summaryAltitude
        self.rateWindow = rateWindow
        self.limitingMagnitude = limitingMagnitude
    }
}

/// The streak risk of an exposure.
public struct StreakAssessment: Sendable {
    /// The sunlit satellites that cross the picture during the exposure, by entry time.
    public let crossings: [SatelliteCrossing]
    /// How many satellites SGP4 could propagate to the start of the exposure.
    public let evaluatedCount: Int
    /// How many of them are above the horizon at the start.
    public let aboveHorizonCount: Int
    /// How many are sunlit and higher than `StreakOptions.summaryAltitude` at the start: the number to show as
    /// "N sunlit satellites above 20° right now".
    public let sunlitAboveSummaryAltitudeCount: Int
    /// How many sunlit satellites cross the picture per minute, estimated from the crossings that begin within
    /// `StreakOptions.rateWindow` (or the exposure) after the start.
    public let crossingsPerMinute: Double
    /// The span in seconds that estimate covers.
    public let rateWindow: Double

    public init(
        crossings: [SatelliteCrossing], evaluatedCount: Int, aboveHorizonCount: Int,
        sunlitAboveSummaryAltitudeCount: Int, crossingsPerMinute: Double, rateWindow: Double
    ) {
        self.crossings = crossings
        self.evaluatedCount = evaluatedCount
        self.aboveHorizonCount = aboveHorizonCount
        self.sunlitAboveSummaryAltitudeCount = sunlitAboveSummaryAltitudeCount
        self.crossingsPerMinute = crossingsPerMinute
        self.rateWindow = rateWindow
    }

    /// The chance of at least one streak in an exposure of `exposureSeconds`, if crossings come at random at the
    /// estimated rate: `1 - exp(-rate · t)`.
    public func probabilityOfStreak(exposureSeconds: Double) -> Double {
        if !exposureSeconds.isFinite || exposureSeconds <= 0.0 { return 0.0 }
        return 1.0 - exp(-crossingsPerMinute * exposureSeconds / 60.0)
    }
}

/// Predicts which satellites will streak through a camera frame during an exposure, and how many to expect.
///
/// **Method.** At the start of the exposure every satellite is propagated once and counted (above the horizon,
/// sunlit above 20°, ...). A *prefilter* then drops every satellite that cannot reach the frame, the sunlight and
/// the sky above the minimum altitude within the window: a satellite at range `ρ` moves at most `v·T` kilometres
/// in `T` seconds (`v` is an upper bound of its speed), so its direction changes by at most `asin(v·T/ρ)`. The
/// survivors are sampled on a step that moves them by at most half the frame's smaller side (never more than 3°),
/// and consecutive samples are joined by a straight line on the gnomonic picture plane (great circles are straight
/// there), clipped against the frame, the horizon and the shadow's edge, which gives entry and exit times to a
/// fraction of the step. The Sun comes from hourly nodes of the ephemeris.
///
/// **Cost.** About 3 microseconds per satellite for the prefilter: 10 000 Starlink element sets take 30 to
/// 90 ms on a desktop and well under a second on a phone. The fine check adds about 1 microsecond per sample
/// and survivor; a very wide frame (a 14 mm lens) keeps a few hundred survivors for tens of milliseconds more.
///
/// Set up the satellites once (`Satellite(...)` costs 3 microseconds each) and reuse the list.
public enum StreakRisk {
    /// The most satellites one call evaluates.
    public static let maximumSatelliteCount = 100_000
    /// The longest exposure window evaluated, in seconds.
    public static let maximumExposureSeconds = 3_600.0

    /// Evaluates `satellites` for an exposure.
    ///
    /// - Parameters:
    ///   - satellites: The satellites to consider, e.g. a CelesTrak group.
    ///   - observer: The observer.
    ///   - frame: The camera frame.
    ///   - exposure: The exposure: its start and duration (clipped to `maximumExposureSeconds`).
    ///   - options: Thresholds and the window for the rate.
    public static func assess(
        _ satellites: [Satellite],
        observer: Observer,
        frame: CameraFrame,
        exposure: DateInterval,
        options: StreakOptions = StreakOptions()
    ) -> StreakAssessment {
        let start = exposure.start.timeIntervalSinceReferenceDate
        let duration = exposure.duration.isFinite ? min(max(exposure.duration, 0.0), maximumExposureSeconds) : 0.0
        let rateWindow = options.rateWindow.isFinite ? AstroMath.clamp(options.rateWindow, 1.0, maximumExposureSeconds) : 120.0
        let window = max(duration, rateWindow)
        let evaluator = StreakEvaluator(observer: observer, frame: frame, start: start, duration: duration, window: window, options: options)
        var evaluated = 0
        var above = 0
        var sunlitAbove = 0
        var raw: [RawCrossing] = []
        let limit = min(satellites.count, maximumSatelliteCount)
        for index in 0..<limit {
            let outcome = evaluator.evaluate(satellites[index], &raw)
            if outcome.evaluated { evaluated += 1 }
            if outcome.aboveHorizon { above += 1 }
            if outcome.sunlitAboveSummaryAltitude { sunlitAbove += 1 }
        }

        var crossings: [SatelliteCrossing] = []
        var startedInWindow = 0
        let exposureEnd = start + duration
        for item in raw {
            if item.start < start + rateWindow { startedInWindow += 1 }
            if item.end < start || item.start > exposureEnd { continue }
            guard let crossing = evaluator.crossing(item, exposureEnd: exposureEnd) else { continue }
            crossings.append(crossing)
        }
        crossings.sort { $0.entry.date < $1.entry.date }
        return StreakAssessment(
            crossings: crossings,
            evaluatedCount: evaluated,
            aboveHorizonCount: above,
            sunlitAboveSummaryAltitudeCount: sunlitAbove,
            crossingsPerMinute: Double(startedInWindow) * 60.0 / rateWindow,
            rateWindow: rateWindow
        )
    }
}

/// A run of continuous visibility in the picture, in seconds since the reference date.
struct RawCrossing {
    let satellite: Satellite
    let start: Double
    let end: Double
}

/// What the first look at a satellite found.
struct StreakOutcome {
    let evaluated: Bool
    let aboveHorizon: Bool
    let sunlitAboveSummaryAltitude: Bool
}

/// Evaluates satellites for one exposure; holds the Sun track and the observer's frame.
final class StreakEvaluator {
    private let frame: CameraFrame
    private let start: Double
    private let window: Double
    private let options: StreakOptions
    private let evaluator: SatelliteEvaluator
    private let geometry: SatelliteObserverGeometry
    private var state = [Double](repeating: 0, count: 6)
    private let minimumAltitude: Double
    private let summaryAltitude: Double
    private let gmstStart: Double
    private let sunStart: Vector3
    private let sunEnd: Vector3
    private let gmstEnd: Double
    private let cornerRadians: Double
    private let sampleArc: Double
    private let threshold = EarthShadow.sunlitThreshold

    private static let minimumStep = 0.05
    private static let maximumStep = 5.0
    private static let minimumRangeKilometers = 150.0
    private static let joinTolerance = 1.0e-6
    /// Windows up to this many seconds use the shadow shortcut of the prefilter.
    private static let shadowShortcutLimit = 1_200.0

    init(observer: Observer, frame: CameraFrame, start: Double, duration: Double, window: Double, options: StreakOptions) {
        self.frame = frame
        self.start = start
        self.window = window
        self.options = options
        self.evaluator = SatelliteEvaluator(observer: observer, sunTrack: SatelliteSunTrack.create(start: start, end: start + window))
        self.geometry = evaluator.geometry
        self.minimumAltitude = options.minimumAltitude.isFinite ? options.minimumAltitude : 0.0
        self.summaryAltitude = options.summaryAltitude.isFinite ? options.summaryAltitude : 20.0
        self.gmstStart = evaluator.gmst(start)
        self.sunStart = evaluator.sunPosition(start)
        self.sunEnd = evaluator.sunPosition(start + window)
        self.gmstEnd = evaluator.gmst(start + window)
        self.cornerRadians = AstroMath.radians(frame.cornerAngle)
        self.sampleArc = AstroMath.clamp(0.5 * min(frame.widthDegrees, frame.heightDegrees), 0.2, 3.0)
    }

    func evaluate(_ satellite: Satellite, _ output: inout [RawCrossing]) -> StreakOutcome {
        let propagator = satellite.propagator
        let minutes = (start - propagator.epochReferenceSeconds) / 60.0
        if propagator.propagateRaw(minutes, into: &state) != 0 {
            return StreakOutcome(evaluated: false, aboveHorizon: false, sunlitAboveSummaryAltitude: false)
        }
        let topocentric = geometry.look(state[0], state[1], state[2], state[3], state[4], state[5], gmstStart)
        let altitude = topocentric.altitude
        let fraction = EarthShadow.illuminatedFraction(state[0], state[1], state[2], sunStart.x, sunStart.y, sunStart.z)
        let outcome = StreakOutcome(
            evaluated: true,
            aboveHorizon: altitude > 0.0,
            sunlitAboveSummaryAltitude: altitude >= summaryAltitude && fraction >= threshold
        )

        // Prefilter: how far can the direction to the satellite turn within the window?
        let maximumSpeed = propagator.maximumSpeedKilometersPerSecond
        let reach = asin(min(1.0, maximumSpeed * window / topocentric.range))
        let direction = Vector3(topocentric.east, topocentric.north, topocentric.up) / topocentric.range
        let separation = acos(AstroMath.clamp(direction.dot(frame.boresight), -1.0, 1.0))
        if separation - reach > cornerRadians { return outcome }
        if altitude + AstroMath.degrees(reach) < minimumAltitude { return outcome }
        if fraction < threshold && window <= Self.shadowShortcutLimit {
            // In shadow now: a low-orbit satellite is lit for an hour at a stretch, so one that is also in
            // shadow at the end of a short window cannot have been lit in between.
            let endMinutes = (start + window - propagator.epochReferenceSeconds) / 60.0
            if propagator.propagateRaw(endMinutes, into: &state) == 0 {
                let endFraction = EarthShadow.illuminatedFraction(state[0], state[1], state[2], sunEnd.x, sunEnd.y, sunEnd.z)
                if endFraction < threshold { return outcome }
            }
        }
        scan(satellite, topocentric, &output)
        return outcome
    }

    /// Samples the satellite through the window and appends the runs inside the frame, above the horizon and lit.
    private func scan(_ satellite: Satellite, _ first: SatelliteTopocentric, _ output: inout [RawCrossing]) {
        let propagator = satellite.propagator
        let maximumSpeed = propagator.maximumSpeedKilometersPerSecond
        let lowestRange = max(first.range - maximumSpeed * window, Self.minimumRangeKilometers)
        let maximumRate = AstroMath.degrees(maximumSpeed / lowestRange)
        let step = AstroMath.clamp(sampleArc / maximumRate, Self.minimumStep, Self.maximumStep)
        let count = max(1, Int((window / step).rounded(.up)))
        let interval = window / Double(count)

        var previousX = 0.0
        var previousY = 0.0
        var previousValid = false
        var previousAltitude = 0.0
        var previousFraction = 0.0
        var runStart = Double.nan
        var runEnd = Double.nan
        var clipper = SegmentClipper()
        var restriction = LinearRestriction()
        for index in 0...count {
            let time = start + Double(index) * interval
            let minutes = (time - propagator.epochReferenceSeconds) / 60.0
            if propagator.propagateRaw(minutes, into: &state) != 0 {
                previousValid = false
                continue
            }
            let gmst = index == 0 ? gmstStart : (index == count ? gmstEnd : evaluator.gmst(time))
            let sun = index == 0 ? sunStart : evaluator.sunPosition(time)
            let topocentric = geometry.look(state[0], state[1], state[2], state[3], state[4], state[5], gmst)
            let altitude = topocentric.altitude
            let fraction = EarthShadow.illuminatedFraction(state[0], state[1], state[2], sun.x, sun.y, sun.z)
            let ex = topocentric.east / topocentric.range
            let ey = topocentric.north / topocentric.range
            let ez = topocentric.up / topocentric.range
            let depth = ex * frame.boresight.x + ey * frame.boresight.y + ez * frame.boresight.z
            let valid = depth > 1.0e-9
            let x = valid ? (ex * frame.right.x + ey * frame.right.y + ez * frame.right.z) / depth / frame.halfWidth : 0.0
            let y = valid ? (ex * frame.up.x + ey * frame.up.y + ez * frame.up.z) / depth / frame.halfHeight : 0.0

            if index > 0 && valid && previousValid && clipper.clip(previousX, previousY, x, y) {
                var low = clipper.low
                var high = clipper.high
                if restriction.restrict(from: previousAltitude, to: altitude, limit: minimumAltitude) {
                    low = max(low, restriction.low)
                    high = min(high, restriction.high)
                    if restriction.restrict(from: previousFraction, to: fraction, limit: threshold) {
                        low = max(low, restriction.low)
                        high = min(high, restriction.high)
                    } else {
                        high = -1.0
                    }
                } else {
                    high = -1.0
                }
                if low <= high {
                    let from = time - interval + low * interval
                    let to = time - interval + high * interval
                    if !runStart.isNaN && from <= runEnd + Self.joinTolerance {
                        runEnd = to
                    } else {
                        if !runStart.isNaN { output.append(RawCrossing(satellite: satellite, start: runStart, end: runEnd)) }
                        runStart = from
                        runEnd = to
                    }
                }
            }
            previousX = x
            previousY = y
            previousValid = valid
            previousAltitude = altitude
            previousFraction = fraction
        }
        if !runStart.isNaN { output.append(RawCrossing(satellite: satellite, start: runStart, end: runEnd)) }
    }

    /// Builds the reported crossing for the part of `raw` inside the exposure, or `nil` if it is filtered out.
    func crossing(_ raw: RawCrossing, exposureEnd: Double) -> SatelliteCrossing? {
        let from = max(raw.start, start)
        let to = min(raw.end, exposureEnd)
        if from > to { return nil }
        let middle = 0.5 * (from + to)
        guard let entry = point(raw.satellite, from), let exit = point(raw.satellite, to) else { return nil }
        var magnitude: Double?
        if raw.satellite.intrinsicMagnitude != nil {
            magnitude = evaluator.look(raw.satellite, middle, &state)?.magnitude
        }
        if let limit = options.limitingMagnitude, let magnitude, magnitude > limit { return nil }
        return SatelliteCrossing(
            satellite: raw.satellite,
            entry: entry,
            exit: exit,
            startsBeforeExposure: raw.start <= start + Self.joinTolerance,
            endsAfterExposure: raw.end >= exposureEnd - Self.joinTolerance,
            magnitude: magnitude
        )
    }

    private func point(_ satellite: Satellite, _ time: Double) -> CrossingPoint? {
        guard let look = evaluator.look(satellite, time, &state) else { return nil }
        return CrossingPoint(date: look.date, azimuth: look.azimuth, altitude: look.altitude, position: frame.position(of: look.direction))
    }
}

/// Clips segments against the square |x| ≤ 1, |y| ≤ 1 (Liang-Barsky) without allocating: `clip` leaves the
/// parameters of the part inside in `low` and `high`.
struct SegmentClipper {
    private(set) var low = 0.0
    private(set) var high = 1.0

    /// Clips the segment (x0, y0) - (x1, y1); returns `false` if it lies outside the square.
    mutating func clip(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
        low = 0.0
        high = 1.0
        let dx = x1 - x0
        let dy = y1 - y0
        return edge(-dx, x0 + 1.0) && edge(dx, 1.0 - x0) && edge(-dy, y0 + 1.0) && edge(dy, 1.0 - y0)
    }

    private mutating func edge(_ p: Double, _ q: Double) -> Bool {
        if p == 0.0 { return q >= 0.0 }
        let r = q / p
        if p < 0.0 {
            if r > high { return false }
            if r > low { low = r }
        } else {
            if r < low { return false }
            if r < high { high = r }
        }
        return true
    }
}

/// The part of a step on which a quantity that goes linearly from `from` to `to` is at least `limit`.
/// `restrict` leaves the parameters in `low` and `high` and returns `false` if there is none.
struct LinearRestriction {
    private(set) var low = 0.0
    private(set) var high = 1.0

    mutating func restrict(from: Double, to: Double, limit: Double) -> Bool {
        if from >= limit && to >= limit {
            low = 0.0
            high = 1.0
            return true
        }
        if from < limit && to < limit { return false }
        let crossing = (limit - from) / (to - from)
        if from < limit {
            low = crossing
            high = 1.0
        } else {
            low = 0.0
            high = crossing
        }
        return true
    }
}
