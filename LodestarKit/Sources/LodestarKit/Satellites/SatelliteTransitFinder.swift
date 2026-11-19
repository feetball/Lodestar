import Foundation

/// Where to stand to see a satellite cross the middle of the Sun's or the Moon's disc.
public struct SatelliteTransitCentreline: Hashable, Sendable {
    /// The place on the centreline (same elevation as the observer), where the satellite's centre crosses the
    /// body's centre at `SatelliteTransit.date`.
    public let location: GeographicLocation
    /// Ground distance from the observer to `location`.
    public let distanceMeters: Double
    /// Direction from the observer to `location`, degrees from true north through east, [0, 360).
    public let bearing: Double
    /// What is left of the centre-to-centre separation at `location` at `SatelliteTransit.date`, in degrees
    /// (below 0.01 by construction).
    public let separation: Double

    public init(location: GeographicLocation, distanceMeters: Double, bearing: Double, separation: Double) {
        self.location = location
        self.distanceMeters = distanceMeters
        self.bearing = bearing
        self.separation = separation
    }
}

/// One transit, or near transit, of a satellite in front of the Sun or the Moon, found by
/// `SatelliteTransitFinder`. All angles are in degrees and geometric (no refraction); the body's direction is
/// topocentric.
public struct SatelliteTransit: Hashable, Sendable {
    /// The satellite's NORAD number.
    public let catalogNumber: Int
    /// The satellite's name.
    public let name: String
    /// `.sun` or `.moon`.
    public let body: SolarSystemBody
    /// The moment of the smallest separation, seen from the observer's site (to 0.01 s). The same moment holds on
    /// the `centreline`.
    public let date: Date
    /// The smallest centre-to-centre separation between the satellite and the body as seen from the site.
    public let minimumSeparation: Double
    /// `true` when the satellite's disc overlaps the body's disc as seen from the site (`minimumSeparation` <
    /// `bodyAngularRadius` + half of `satelliteAngularSize`).
    public let isFromSite: Bool
    /// The body's angular radius for the observer (the Moon's depends on its distance and the observer's parallax).
    public let bodyAngularRadius: Double
    /// The satellite's angular extent at `date` from its span (see `SatelliteTransitFinder.satelliteSpanMeters`)
    /// and its range.
    public let satelliteAngularSize: Double
    /// The distance to the satellite at `date`.
    public let satelliteRangeKilometers: Double
    /// The speed of the satellite across the body's disc, relative to the body, in degrees per second.
    public let angularSpeed: Double
    /// The body's geometric altitude at `date`.
    public let bodyAltitude: Double
    /// The body's azimuth at `date`, from north through east, [0, 360).
    public let bodyAzimuth: Double
    /// The Sun's geometric altitude at `date`.
    public let sunAltitude: Double
    /// `true` when the Sun's centre is above -0.833° (the Sun is up).
    public let isDaylight: Bool
    /// `true` when the Sun is below `SatellitePassFinder.defaultDarknessSunAltitude` (-6°).
    public let isNight: Bool
    /// How long the satellite's centre is inside the body's disc as seen from the site: the chord at
    /// `minimumSeparation` divided by `angularSpeed`; 0 when the centre never enters the disc.
    public let siteDurationSeconds: Double
    /// The longest crossing: the disc's diameter divided by the angular speed at the `centreline` (at the site
    /// when there is none). The satellite's own size (about 3 % of the Sun's disc) is not added.
    public let centrelineDurationSeconds: Double
    /// The place of the central transit, or `nil` when it is farther than the search's ground distance.
    public let centreline: SatelliteTransitCentreline?

    public init(
        catalogNumber: Int, name: String, body: SolarSystemBody, date: Date, minimumSeparation: Double,
        isFromSite: Bool, bodyAngularRadius: Double, satelliteAngularSize: Double, satelliteRangeKilometers: Double,
        angularSpeed: Double, bodyAltitude: Double, bodyAzimuth: Double, sunAltitude: Double, isDaylight: Bool,
        isNight: Bool, siteDurationSeconds: Double, centrelineDurationSeconds: Double,
        centreline: SatelliteTransitCentreline?
    ) {
        self.catalogNumber = catalogNumber
        self.name = name
        self.body = body
        self.date = date
        self.minimumSeparation = minimumSeparation
        self.isFromSite = isFromSite
        self.bodyAngularRadius = bodyAngularRadius
        self.satelliteAngularSize = satelliteAngularSize
        self.satelliteRangeKilometers = satelliteRangeKilometers
        self.angularSpeed = angularSpeed
        self.bodyAltitude = bodyAltitude
        self.bodyAzimuth = bodyAzimuth
        self.sunAltitude = sunAltitude
        self.isDaylight = isDaylight
        self.isNight = isNight
        self.siteDurationSeconds = siteDurationSeconds
        self.centrelineDurationSeconds = centrelineDurationSeconds
        self.centreline = centreline
    }
}

/// Finds the transits of a satellite (the ISS, the Chinese space station) across the Sun or the Moon.
///
/// **Method.** `SatellitePassFinder` gives the passes above 3° (daylight passes included: it does not filter by
/// darkness); the body must be above 3° as well. Over each pass the angular separation between the satellite and
/// the centre of the body (both topocentric: the satellite from SGP4, the body from the engine's ephemeris
/// interpolated from hourly nodes, with parallax) is sampled every 2 s, every local minimum is refined by a
/// golden-section search to 0.01 s, and kept when the satellite's disc overlaps the body's (a transit from the
/// site) or when the centreline is near enough. The centreline is the place on the ground from where the satellite
/// crosses the body's centre at the same moment: the separation vector `(Δaz·cos alt, Δalt)` is evaluated for
/// observers displaced 1 km north and 1 km east (and the opposite way), the 2×2 linear system for the ground
/// displacement that zeroes it is solved, and the step is repeated twice more from the new place. The displaced
/// observers keep the elevation of the original one; terrain is not known to the engine.
///
/// **Cost.** Bounded by passes × samples: about 100 samples per pass and a few hundred evaluations (2 µs each) per
/// kept candidate. A 14-day search for the ISS takes about 20 ms on a desktop and well under a second on a phone.
///
/// **Accuracy.** The element set decides: an along-track error of a few km grows 1–3 km a day for the ISS, which
/// is 0.3 s a day of timing and a few km of centreline position. Use element sets that are a day or two old and
/// check again on the day.
public enum SatelliteTransitFinder {
    /// The default ground distance in metres within which the centreline is reported, 50 km.
    public static let defaultMaxGroundDistanceMeters = 50_000.0
    /// The largest ground distance accepted, 200 km.
    public static let maximumGroundDistanceMeters = 200_000.0
    /// The altitude in degrees the body and the satellite must exceed, 3°.
    public static let minimumBodyAltitude = 3.0
    /// The longest window searched, in days.
    public static let maximumWindowDays = SatellitePassFinder.maximumWindowDays
    /// The Sun's altitude in degrees above which it counts as daylight, -0.833° (upper limb at the refracted horizon).
    public static let daylightSunAltitude = -0.833

    /// The span of a satellite in metres, from a small table keyed by NORAD number (default 50 m): the ISS and its
    /// modules 109 m (the solar-array truss, NASA); the Chinese space station and its modules 55 m (approximate
    /// overall size of the T-shaped station).
    public static func satelliteSpanMeters(catalogNumber: Int) -> Double {
        switch catalogNumber {
        case 25544, 36086, 49044: return 109.0
        case 48274, 53239, 54216: return 55.0
        default: return 50.0
        }
    }

    /// The transits of `satellite` across `body` seen from `observer` or from a place within
    /// `maxGroundDistanceMeters` of it, between `from` and `to`, in chronological order.
    ///
    /// - Parameters:
    ///   - body: `.sun` or `.moon`; any other body gives an empty array.
    ///   - maxGroundDistanceMeters: How far to look for the centreline, clamped to 0 ... `maximumGroundDistanceMeters`.
    ///     With 0 only transits from the site itself are returned.
    /// - Returns: the transits; empty when the window is empty or not finite, or when SGP4 cannot propagate the
    ///   satellite. The window is limited to `maximumWindowDays`.
    public static func transits(
        satellite: Satellite,
        body: SolarSystemBody,
        observer: Observer,
        from: Date,
        to: Date,
        maxGroundDistanceMeters: Double = SatelliteTransitFinder.defaultMaxGroundDistanceMeters
    ) -> [SatelliteTransit] {
        guard body == .sun || body == .moon else { return [] }
        let start = from.timeIntervalSinceReferenceDate
        let requestedEnd = to.timeIntervalSinceReferenceDate
        guard start.isFinite, requestedEnd.isFinite, requestedEnd > start else { return [] }
        let end = min(requestedEnd, start + maximumWindowDays * JulianDate.secondsPerDay)
        let ground = maxGroundDistanceMeters.isFinite
            ? AstroMath.clamp(maxGroundDistanceMeters, 0.0, maximumGroundDistanceMeters)
            : defaultMaxGroundDistanceMeters
        let finder = SatellitePassFinder(
            observer: observer,
            interval: DateInterval(start: from, end: Date(timeIntervalSinceReferenceDate: end)),
            minimumAltitude: minimumBodyAltitude
        )
        let passes = finder.passes(of: satellite)
        if passes.isEmpty { return [] }
        let search = SatelliteTransitSearch(
            satellite: satellite, body: body, observer: observer,
            track: SatelliteTransitBodyTrack.create(body: body, start: start, end: end), maxGround: ground
        )
        var transits: [SatelliteTransit] = []
        for pass in passes { search.search(pass, into: &transits) }
        transits.sort { $0.date < $1.date }
        return transits
    }
}

/// The body's TEME position, interpolated like `SatelliteSunTrack` (hourly nodes, cubic Lagrange): the Moon moves
/// 0.55° an hour and the interpolation error is about 0.1 m. Times are seconds since the Foundation reference date.
struct SatelliteTransitBodyTrack: Sendable {
    /// Seconds between nodes.
    static let spacing = 3_600.0
    /// The most nodes a track holds.
    static let maximumNodeCount = 5_000

    private let origin: Double
    private let nodes: [Vector3]

    private init(origin: Double, nodes: [Vector3]) {
        self.origin = origin
        self.nodes = nodes
    }

    /// The body's TEME position at `time` in kilometres (the time should lie in the interval given to `create`).
    func position(_ time: Double) -> Vector3 {
        let scaled = ((time - origin) / Self.spacing).rounded(.down)
        let raw = scaled.isFinite ? Int(min(max(scaled, -1.0e6), 1.0e6)) : 0
        let base = min(max(raw, 1), nodes.count - 3)
        let u = (time - origin) / Self.spacing - Double(base)
        let w0 = -u * (u - 1) * (u - 2) / 6
        let w1 = (u + 1) * (u - 1) * (u - 2) / 2
        let w2 = -(u + 1) * u * (u - 2) / 2
        let w3 = (u + 1) * u * (u - 1) / 6
        let n0 = nodes[base - 1]
        let n1 = nodes[base]
        let n2 = nodes[base + 1]
        let n3 = nodes[base + 2]
        return Vector3(
            n0.x * w0 + n1.x * w1 + n2.x * w2 + n3.x * w3,
            n0.y * w0 + n1.y * w1 + n2.y * w2 + n3.y * w3,
            n0.z * w0 + n1.z * w1 + n2.z * w2 + n3.z * w3
        )
    }

    /// The track of `body` for `[start, end]` (seconds since the reference date).
    static func create(body: SolarSystemBody, start: Double, end: Double) -> SatelliteTransitBodyTrack {
        let from = start.isFinite ? start : 0.0
        let to = end.isFinite ? max(end, from) : from
        let first = (from / spacing).rounded(.down) * spacing - spacing
        let last = (to / spacing).rounded(.up) * spacing + 2 * spacing
        let count = min(max(5, Int(min((last - first) / spacing, Double(maximumNodeCount))) + 1), maximumNodeCount)
        let nodes = (0..<count).map { exact(body: body, time: first + Double($0) * spacing) }
        return SatelliteTransitBodyTrack(origin: first, nodes: nodes)
    }

    /// The geocentric apparent position of `body` (Sun or Moon) in TEME at `time`, in kilometres, from the ephemeris.
    static func exact(body: SolarSystemBody, time: Double) -> Vector3 {
        if body == .sun { return SatelliteSunTrack.exact(time) }
        let jd = JulianDate(date: Date(timeIntervalSinceReferenceDate: time))
        let bodyJ2000 = Ephemeris.geocentricJ2000(of: body, at: jd)
        let nutation = Nutation(julianDate: jd)
        let meanObliquity = Obliquity.mean(jd)
        let trueObliquity = meanObliquity + nutation.obliquity
        let equationOfTheEquinoxes = nutation.longitude * AstroMath.cosDeg(trueObliquity)
        let toTrueOfDate = nutation.matrix(meanObliquity: meanObliquity) * Precession.matrixFromJ2000(to: jd)
        let toTeme = Matrix3.frameRotationZ(AstroMath.radians(equationOfTheEquinoxes)) * toTrueOfDate
        return (toTeme * bodyJ2000) * SkyFrame.kilometersPerAU
    }
}

/// One satellite's transit search for one body and observer. Local state only; one instance per call.
final class SatelliteTransitSearch {
    private let satellite: Satellite
    private let body: SolarSystemBody
    private let observer: Observer
    private let track: SatelliteTransitBodyTrack
    private let maxGround: Double
    private let propagator: Sgp4Propagator
    private let site: SatelliteObserverGeometry
    private var state = [Double](repeating: 0, count: 6)
    private var look = [Double](repeating: 0, count: 8)
    private let bodyRadiusKilometers: Double
    private let maximumSpeed: Double
    private let spanMeters: Double
    private var offsetX = 0.0
    private var offsetY = 0.0

    private static let failedSeparation = 1_000.0
    private static let coarseStep = 2.0
    private static let timeTolerance = 0.01
    private static let speedHalfStep = 0.5
    private static let shortPass = 1_800.0
    private static let altitudeMargin = 0.5
    private static let coarseBodyRadius = 0.3
    private static let reachMargin = 0.02
    private static let centrelineBaseline = 1_000.0
    private static let centrelineIterations = 3
    private static let centrelineConvergence = 1.0e-6
    private static let centrelineTolerance = 0.01
    private static let maximumStep = 1_000_000.0

    /// What `measure` finds at one place and moment.
    private struct Measure {
        let separation: Double
        let bodyRadius: Double
        let range: Double
        let speed: Double
        let bodyAltitude: Double
        let bodyAzimuth: Double
    }

    /// The place on the ground `centreline` found.
    private struct Centreline {
        let place: SatelliteTransitCentreline
        let measure: Measure
    }

    init(satellite: Satellite, body: SolarSystemBody, observer: Observer, track: SatelliteTransitBodyTrack, maxGround: Double) {
        self.satellite = satellite
        self.body = body
        self.observer = observer
        self.track = track
        self.maxGround = maxGround
        self.propagator = satellite.propagator
        self.site = SatelliteObserverGeometry(observer: observer)
        self.bodyRadiusKilometers = body.meanRadiusKilometers
        self.maximumSpeed = satellite.propagator.maximumSpeedKilometersPerSecond
        self.spanMeters = SatelliteTransitFinder.satelliteSpanMeters(catalogNumber: satellite.catalogNumber)
    }

    /// Fills `look` with the satellite's ENU unit vector (0-2) and range in kilometres (3), and the body's
    /// topocentric ENU unit vector (4-6) and distance in kilometres (7), for `geometry` at `time`. `false` where
    /// SGP4 fails.
    private func evaluate(_ geometry: SatelliteObserverGeometry, _ time: Double) -> Bool {
        let minutes = (time - propagator.epochReferenceSeconds) / 60.0
        if propagator.propagateRaw(minutes, into: &state) != 0 { return false }
        let gmst = Sgp4Time.greenwichSiderealTime(SatelliteFrames.julianDateUt(time))
        let topocentric = geometry.look(state[0], state[1], state[2], state[3], state[4], state[5], gmst)
        let range = topocentric.range
        if !(range > 0.0) { return false }
        look[0] = topocentric.east / range
        look[1] = topocentric.north / range
        look[2] = topocentric.up / range
        look[3] = range
        let position = track.position(time)
        let c = cos(gmst)
        let s = sin(gmst)
        let ex = c * position.x + s * position.y
        let ey = -s * position.x + c * position.y
        let dx = ex - geometry.x
        let dy = ey - geometry.y
        let dz = position.z - geometry.z
        let distance = (dx * dx + dy * dy + dz * dz).squareRoot()
        if !(distance > 0.0) { return false }
        look[4] = (geometry.eastX * dx + geometry.eastY * dy) / distance
        look[5] = (geometry.northX * dx + geometry.northY * dy + geometry.northZ * dz) / distance
        look[6] = (geometry.upX * dx + geometry.upY * dy + geometry.upZ * dz) / distance
        look[7] = distance
        return true
    }

    /// The angle between the satellite and the body's centre in `look`, degrees.
    private func lookSeparation() -> Double {
        SatelliteVectorMath.angleBetween(look[0], look[1], look[2], look[4], look[5], look[6])
    }

    /// The separation at `time` seen from the site; large where SGP4 fails.
    private func separationAt(_ time: Double) -> Double {
        evaluate(site, time) ? lookSeparation() : Self.failedSeparation
    }

    /// Sets `offsetX`, `offsetY` to the satellite's offset from the body's centre in the body's tangent plane, in
    /// degrees (x towards increasing azimuth, y towards increasing altitude), for what `look` holds.
    private func computeOffset() {
        let bx = look[4]
        let by = look[5]
        let bz = look[6]
        let horizontal = (bx * bx + by * by).squareRoot()
        let sinAzimuth = horizontal > 1.0e-9 ? bx / horizontal : 0.0
        let cosAzimuth = horizontal > 1.0e-9 ? by / horizontal : 1.0
        let dot = look[0] * bx + look[1] * by + look[2] * bz
        let across = look[0] * cosAzimuth - look[1] * sinAzimuth
        let up = -look[0] * bz * sinAzimuth - look[1] * bz * cosAzimuth + look[2] * horizontal
        offsetX = AstroMath.degrees(atan2(across, dot))
        offsetY = AstroMath.degrees(atan2(up, dot))
    }

    /// Sets the offset for `geometry` at `time`; `false` where SGP4 fails.
    private func offsetAt(_ geometry: SatelliteObserverGeometry, _ time: Double) -> Bool {
        if !evaluate(geometry, time) { return false }
        computeOffset()
        return true
    }

    /// The geometry of the transit for `geometry` at `time`, or `nil` where SGP4 fails.
    private func measure(_ geometry: SatelliteObserverGeometry, _ time: Double) -> Measure? {
        if !evaluate(geometry, time) { return nil }
        let separation = lookSeparation()
        let bodyRadius = AstroMath.degrees(asin(min(bodyRadiusKilometers / look[7], 1.0)))
        let range = look[3]
        let bodyAltitude = AstroMath.asinDeg(look[6])
        let bodyAzimuth = look[4] == 0.0 && look[5] == 0.0 ? 0.0 : AstroMath.normalizeDegrees(AstroMath.atan2Deg(look[4], look[5]))
        if !offsetAt(geometry, time - Self.speedHalfStep) { return nil }
        let x1 = offsetX
        let y1 = offsetY
        if !offsetAt(geometry, time + Self.speedHalfStep) { return nil }
        let dx = offsetX - x1
        let dy = offsetY - y1
        let speed = (dx * dx + dy * dy).squareRoot() / (2.0 * Self.speedHalfStep)
        return Measure(
            separation: separation, bodyRadius: bodyRadius, range: range, speed: speed,
            bodyAltitude: bodyAltitude, bodyAzimuth: bodyAzimuth
        )
    }

    /// The extra separation, in degrees, that a displacement of up to the search's ground distance can cancel at `range` km.
    private func reach(_ range: Double) -> Double {
        let meters = range * 1000.0
        return AstroMath.degrees(atan2(maxGround, max(meters - maxGround, 0.2 * meters))) + Self.reachMargin
    }

    /// Appends the transits of `pass` to `into`.
    func search(_ pass: SatellitePass, into: inout [SatelliteTransit]) {
        let begin = pass.rise.date.timeIntervalSinceReferenceDate
        let finish = pass.set.date.timeIntervalSinceReferenceDate
        let duration = finish - begin
        guard duration > 0.0 else { return }
        // The body moves less than 0.1 degree in the 20 minutes a low-orbit pass lasts: a pass with the body far
        // below the limit at both ends and in the middle has nothing to find.
        if duration <= Self.shortPass {
            var highest = -90.0
            for fraction in [0.0, 0.5, 1.0] {
                if evaluate(site, begin + fraction * duration) { highest = max(highest, AstroMath.asinDeg(look[6])) }
            }
            if highest < SatelliteTransitFinder.minimumBodyAltitude - Self.altitudeMargin { return }
        }
        let count = max(1, Int((duration / Self.coarseStep).rounded(.up)))
        let step = duration / Double(count)
        var separations = [Double](repeating: 0, count: count + 1)
        for index in 0...count { separations[index] = separationAt(begin + Double(index) * step) }
        for index in 0...count {
            let value = separations[index]
            if value >= Self.failedSeparation { continue }
            let before = index > 0 ? separations[index - 1] : Double.infinity
            let after = index < count ? separations[index + 1] : Double.infinity
            if !(value < before && value <= after) { continue }
            let time = begin + Double(index) * step
            if !evaluate(site, time) { continue }
            let speedBound = AstroMath.degrees(maximumSpeed / look[3])
            if value > Self.coarseBodyRadius + reach(look[3]) + 0.5 * speedBound * step { continue }
            let low = index > 0 ? time - step : time
            let high = index < count ? time + step : time
            let refined = high > low
                ? SatelliteSearch.maximize({ -self.separationAt($0) }, low, high, Self.timeTolerance)
                : time
            if let transit = transit(at: refined) { into.append(transit) }
        }
    }

    /// The transit whose closest approach seen from the site is at `time`, or `nil` if there is none worth reporting.
    private func transit(at time: Double) -> SatelliteTransit? {
        guard let here = measure(site, time) else { return nil }
        if here.bodyAltitude < SatelliteTransitFinder.minimumBodyAltitude { return nil }
        let satelliteSize = AstroMath.degrees(spanMeters / (here.range * 1000.0))
        let overlap = here.bodyRadius + 0.5 * satelliteSize
        let isFromSite = here.separation < overlap
        if !isFromSite && here.separation > overlap + reach(here.range) { return nil }
        let central = centreline(at: time)
        if !isFromSite && central == nil { return nil }
        let sun = SatelliteSunTrack.exact(time)
        let sunAltitude = AstroMath.asinDeg(
            site.directionOf(sun.x, sun.y, sun.z, Sgp4Time.greenwichSiderealTime(SatelliteFrames.julianDateUt(time))).z
        )
        let siteChord: Double
        if isFromSite {
            let half = here.bodyRadius * here.bodyRadius - here.separation * here.separation
            siteChord = 2.0 * max(half, 0.0).squareRoot()
        } else {
            siteChord = 0.0
        }
        let longest = central?.measure ?? here
        return SatelliteTransit(
            catalogNumber: satellite.catalogNumber,
            name: satellite.name,
            body: body,
            date: Date(timeIntervalSinceReferenceDate: time),
            minimumSeparation: here.separation,
            isFromSite: isFromSite,
            bodyAngularRadius: here.bodyRadius,
            satelliteAngularSize: satelliteSize,
            satelliteRangeKilometers: here.range,
            angularSpeed: here.speed,
            bodyAltitude: here.bodyAltitude,
            bodyAzimuth: here.bodyAzimuth,
            sunAltitude: sunAltitude,
            isDaylight: sunAltitude > SatelliteTransitFinder.daylightSunAltitude,
            isNight: sunAltitude < SatellitePassFinder.defaultDarknessSunAltitude,
            siteDurationSeconds: here.speed > 0.0 ? siteChord / here.speed : 0.0,
            centrelineDurationSeconds: longest.speed > 0.0 ? 2.0 * longest.bodyRadius / longest.speed : 0.0,
            centreline: central?.place
        )
    }

    /// The place on the ground, within the search's ground distance, from where the satellite crosses the body's
    /// centre at `time`; `nil` when there is none, or the iteration does not converge.
    private func centreline(at time: Double) -> Centreline? {
        var latitude = observer.location.latitude
        var longitude = observer.location.longitude
        let elevation = observer.location.elevation
        var geometry = site
        for _ in 0..<Self.centrelineIterations {
            if !offsetAt(geometry, time) { return nil }
            let fx = offsetX
            let fy = offsetY
            if (fx * fx + fy * fy).squareRoot() < Self.centrelineConvergence { break }
            let eastForward = offsetAt(displaced(latitude, longitude, elevation, 0.0, Self.centrelineBaseline), time)
            let eastForwardX = offsetX
            let eastForwardY = offsetY
            let eastBackward = offsetAt(displaced(latitude, longitude, elevation, 0.0, -Self.centrelineBaseline), time)
            let eastBackwardX = offsetX
            let eastBackwardY = offsetY
            let northForward = offsetAt(displaced(latitude, longitude, elevation, Self.centrelineBaseline, 0.0), time)
            let northForwardX = offsetX
            let northForwardY = offsetY
            let northBackward = offsetAt(displaced(latitude, longitude, elevation, -Self.centrelineBaseline, 0.0), time)
            let northBackwardX = offsetX
            let northBackwardY = offsetY
            if !eastForward || !eastBackward || !northForward || !northBackward { return nil }
            // The columns of the Jacobian: how the offset changes per metre east and per metre north.
            let a = (eastForwardX - eastBackwardX) / (2.0 * Self.centrelineBaseline)
            let c = (eastForwardY - eastBackwardY) / (2.0 * Self.centrelineBaseline)
            let b = (northForwardX - northBackwardX) / (2.0 * Self.centrelineBaseline)
            let d = (northForwardY - northBackwardY) / (2.0 * Self.centrelineBaseline)
            let determinant = a * d - b * c
            if !(abs(determinant) > 1.0e-18) { return nil }
            let stepEast = -(d * fx - b * fy) / determinant
            let stepNorth = -(-c * fx + a * fy) / determinant
            if !stepEast.isFinite || !stepNorth.isFinite || (stepEast * stepEast + stepNorth * stepNorth).squareRoot() > Self.maximumStep {
                return nil
            }
            let next = moved(latitude, longitude, elevation, stepNorth, stepEast)
            latitude = next.latitude
            longitude = next.longitude
            geometry = SatelliteObserverGeometry(observer: Observer(location: next, atmosphere: observer.atmosphere))
        }
        guard let measured = measure(geometry, time) else { return nil }
        if !(measured.separation <= Self.centrelineTolerance) { return nil }
        let here = SatelliteFrames.earthFixedPosition(of: observer.location)
        let place = GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation)
        let there = SatelliteFrames.earthFixedPosition(of: place)
        let dx = there.x - here.x
        let dy = there.y - here.y
        let dz = there.z - here.z
        let east = site.eastX * dx + site.eastY * dy
        let north = site.northX * dx + site.northY * dy + site.northZ * dz
        let distance = (east * east + north * north).squareRoot()
        if distance > maxGround { return nil }
        let bearing = distance > 0.0 ? AstroMath.normalizeDegrees(AstroMath.atan2Deg(east, north)) : 0.0
        return Centreline(
            place: SatelliteTransitCentreline(
                location: place, distanceMeters: distance, bearing: bearing, separation: measured.separation
            ),
            measure: measured
        )
    }

    /// The observer geometry of a place `north` and `east` metres from the one at `latitude`, `longitude`.
    private func displaced(
        _ latitude: Double, _ longitude: Double, _ elevation: Double, _ north: Double, _ east: Double
    ) -> SatelliteObserverGeometry {
        SatelliteObserverGeometry(
            observer: Observer(location: moved(latitude, longitude, elevation, north, east), atmosphere: observer.atmosphere)
        )
    }

    /// The place `north` and `east` metres from the one at `latitude`, `longitude` (a step on the ellipsoid's local grid).
    private func moved(
        _ latitude: Double, _ longitude: Double, _ elevation: Double, _ north: Double, _ east: Double
    ) -> GeographicLocation {
        let eccentricitySquared = SatelliteFrames.earthFlattening * (2.0 - SatelliteFrames.earthFlattening)
        let sine = AstroMath.sinDeg(latitude)
        let factor = 1.0 - eccentricitySquared * sine * sine
        let equatorial = SatelliteFrames.earthEquatorialRadiusKilometers * 1000.0
        let primeVertical = equatorial / factor.squareRoot()
        let meridional = equatorial * (1.0 - eccentricitySquared) / (factor * factor.squareRoot())
        let cosine = max(AstroMath.cosDeg(latitude), 1.0e-6)
        return GeographicLocation(
            latitude: latitude + AstroMath.degrees(north / meridional),
            longitude: longitude + AstroMath.degrees(east / (primeVertical * cosine)),
            elevation: elevation
        )
    }
}
