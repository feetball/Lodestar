import Foundation

/// Where a satellite is, and how it looks, at one instant for one observer.
///
/// Created by `Satellite.look`. All angles are in degrees.
public struct SatelliteLook: Hashable, Sendable {
    /// The instant.
    public let date: Date
    /// Azimuth from true north through east, [0, 360).
    public let azimuth: Double
    /// Geometric altitude above the horizon (no refraction), [-90, 90].
    public let altitude: Double
    /// Altitude as seen through the atmosphere of the observer's `Atmosphere`.
    public let apparentAltitude: Double
    /// Distance from the observer.
    public let rangeKilometers: Double
    /// Rate of change of the range (positive when receding).
    public let rangeRateKilometersPerSecond: Double
    /// How fast the satellite moves across the sky, in degrees per second.
    public let angularSpeed: Double
    /// The visible fraction of the Sun's disc as seen from the satellite, 0 ... 1 (`EarthShadow`).
    public let illuminatedFraction: Double
    /// The Sun-satellite-observer angle, 0 (full) ... 180.
    public let phaseAngle: Double
    /// The geometric altitude of the Sun's centre for the observer.
    public let sunAltitude: Double
    /// The apparent magnitude (`SatelliteBrightness`); `nil` when the intrinsic magnitude is unknown or the
    /// satellite is not lit.
    public let magnitude: Double?
    /// The TEME position (km) and velocity (km/s) the look was computed from.
    public let temeState: TemeState

    public init(
        date: Date, azimuth: Double, altitude: Double, apparentAltitude: Double, rangeKilometers: Double,
        rangeRateKilometersPerSecond: Double, angularSpeed: Double, illuminatedFraction: Double, phaseAngle: Double,
        sunAltitude: Double, magnitude: Double?, temeState: TemeState
    ) {
        self.date = date
        self.azimuth = azimuth
        self.altitude = altitude
        self.apparentAltitude = apparentAltitude
        self.rangeKilometers = rangeKilometers
        self.rangeRateKilometersPerSecond = rangeRateKilometersPerSecond
        self.angularSpeed = angularSpeed
        self.illuminatedFraction = illuminatedFraction
        self.phaseAngle = phaseAngle
        self.sunAltitude = sunAltitude
        self.magnitude = magnitude
        self.temeState = temeState
    }

    /// The geometric direction as azimuth and altitude.
    public var horizontal: HorizontalCoordinate { HorizontalCoordinate(azimuth: azimuth, altitude: altitude) }

    /// The direction as the observer sees it, with refraction. Point the camera here.
    public var apparentHorizontal: HorizontalCoordinate { HorizontalCoordinate(azimuth: azimuth, altitude: apparentAltitude) }

    /// The geometric direction as an ENU unit vector (x east, y north, z up).
    public var direction: Vector3 { horizontal.unitVector }

    /// The refracted direction as an ENU unit vector: the one a camera needs to point along.
    public var apparentDirection: Vector3 { apparentHorizontal.unitVector }

    /// `true` when the satellite is above the geometric horizon.
    public var isAboveHorizon: Bool { altitude > 0.0 }

    /// `true` when at least half of the Sun's disc is visible from the satellite (`EarthShadow.sunlitThreshold`).
    public var isSunlit: Bool { illuminatedFraction >= EarthShadow.sunlitThreshold }

    /// `true` when the Sun is below `darknessSunAltitude` (default -6°, the end of civil twilight).
    public func observerIsDark(darknessSunAltitude: Double = SatellitePassFinder.defaultDarknessSunAltitude) -> Bool {
        sunAltitude < darknessSunAltitude
    }

    /// `true` when the satellite can be seen: above the horizon, sunlit, and the observer in darkness.
    public func isVisible(darknessSunAltitude: Double = SatellitePassFinder.defaultDarknessSunAltitude) -> Bool {
        isAboveHorizon && isSunlit && observerIsDark(darknessSunAltitude: darknessSunAltitude)
    }
}

/// The sky for one observer at one instant: the sidereal angle, the Sun and the observer's frame, computed once and
/// shared by many satellites (`Satellite.look`). Building one costs about 40 microseconds (mostly the Sun's
/// ephemeris); evaluating a satellite against it about 2 microseconds.
public struct SatelliteSkyContext: Sendable {
    /// The instant.
    public let date: Date
    /// The observer.
    public let observer: Observer
    let geometry: SatelliteObserverGeometry
    let time: Double
    let gmst: Double
    /// The Sun's TEME position in kilometres.
    public let sunPosition: Vector3
    /// The geometric altitude of the Sun's centre for the observer, in degrees.
    public let sunAltitude: Double

    public init(date: Date, observer: Observer) {
        self.date = date
        self.observer = observer
        let geometry = SatelliteObserverGeometry(observer: observer)
        self.geometry = geometry
        let time = date.timeIntervalSinceReferenceDate
        self.time = time
        let gmst = Sgp4Time.greenwichSiderealTime(SatelliteFrames.julianDateUt(time))
        self.gmst = gmst
        let sun = SatelliteSunTrack.exact(time)
        self.sunPosition = sun
        self.sunAltitude = AstroMath.asinDeg(geometry.directionOf(sun.x, sun.y, sun.z, gmst).z)
    }

    /// `true` when the Sun is below `darknessSunAltitude` (default -6°, the end of civil twilight).
    public func isDark(darknessSunAltitude: Double = SatellitePassFinder.defaultDarknessSunAltitude) -> Bool {
        sunAltitude < darknessSunAltitude
    }
}

/// A satellite: its element set, an SGP4 propagator and, when known, its intrinsic magnitude.
///
/// Immutable and thread safe. Construction costs the propagator's initialization (about 3 microseconds). Equality
/// is identity.
public final class Satellite: Sendable {
    /// The most points `track` returns.
    public static let maximumTrackPoints = 20_000
    /// The longest span `track` covers, in days.
    public static let maximumTrackDays = 30.0

    /// The element set.
    public let elements: OrbitalElements
    /// The magnitude at 1000 km and 90° phase (`SatelliteBrightness`); `nil` if unknown.
    public let intrinsicMagnitude: Double?
    /// The SGP4 propagator for `elements`.
    public let propagator: Sgp4Propagator

    /// Creates a satellite. `intrinsicMagnitude` defaults to the built-in value for the catalog number, if there is one.
    public init(elements: OrbitalElements, intrinsicMagnitude: Double?) {
        self.elements = elements
        self.intrinsicMagnitude = intrinsicMagnitude
        self.propagator = Sgp4Propagator(elements: elements)
    }

    /// Creates a satellite with the built-in intrinsic magnitude of its catalog number, if there is one.
    public convenience init(elements: OrbitalElements) {
        self.init(elements: elements, intrinsicMagnitude: SatelliteBrightness.intrinsicMagnitude(catalogNumber: elements.catalogNumber))
    }

    /// The object name, or "NORAD <number>" when the element set has none.
    public var name: String { elements.name ?? "NORAD \(elements.catalogNumber)" }

    /// The NORAD catalog number.
    public var catalogNumber: Int { elements.catalogNumber }

    /// Where the satellite is in the sky and how it looks at `date`, for `observer`. Builds a `SatelliteSkyContext`
    /// (about 40 microseconds); use `look(in:)` to evaluate many satellites at one instant.
    ///
    /// - Returns: the look, or `nil` when SGP4 cannot propagate to `date` (a decayed satellite, a time too far
    ///   from the epoch).
    public func look(at date: Date, observer: Observer) -> SatelliteLook? {
        look(in: SatelliteSkyContext(date: date, observer: observer))
    }

    /// `look(at:observer:)` against a prepared sky.
    public func look(in context: SatelliteSkyContext) -> SatelliteLook? {
        var state = [Double](repeating: 0, count: 6)
        return SatelliteEvaluator.look(
            self, context.geometry, context.time, context.gmst, context.sunPosition, context.sunAltitude, &state
        )
    }

    /// The looks at times from `start` to `end` every `step` seconds, for drawing a track or choosing where to
    /// wait. Times where SGP4 fails are left out. At most 20 000 points and 30 days are produced; the Sun is
    /// interpolated from hourly nodes.
    ///
    /// - Parameter step: Seconds between points, clamped to 0.1 ... 3600.
    public func track(from start: Date, to end: Date, step: Double, observer: Observer) -> [SatelliteLook] {
        let startTime = start.timeIntervalSinceReferenceDate
        let endTime = end.timeIntervalSinceReferenceDate
        guard endTime >= startTime, startTime.isFinite, endTime.isFinite else { return [] }
        let interval = step.isFinite ? AstroMath.clamp(step, 0.1, 3_600.0) : 1.0
        let points = min((endTime - startTime) / interval, Double(Self.maximumTrackPoints), Self.maximumTrackDays * 86_400.0 / interval)
        let count = min(Int(points) + 1, Self.maximumTrackPoints)
        let evaluator = SatelliteEvaluator(
            observer: observer,
            sunTrack: SatelliteSunTrack.create(start: startTime, end: startTime + Double(count - 1) * interval)
        )
        var state = [Double](repeating: 0, count: 6)
        var looks: [SatelliteLook] = []
        looks.reserveCapacity(count)
        for index in 0..<count {
            let time = startTime + Double(index) * interval
            if let look = evaluator.look(self, time, &state) { looks.append(look) }
        }
        return looks
    }
}

/// Evaluates satellites for one observer; shares the observer geometry and the Sun between evaluations.
struct SatelliteEvaluator: Sendable {
    let observer: Observer
    let geometry: SatelliteObserverGeometry
    private let sunTrack: SatelliteSunTrack?

    init(observer: Observer, sunTrack: SatelliteSunTrack?) {
        self.observer = observer
        self.geometry = SatelliteObserverGeometry(observer: observer)
        self.sunTrack = sunTrack
    }

    /// The Sun's TEME position at `time` (seconds since the reference date).
    func sunPosition(_ time: Double) -> Vector3 { sunTrack?.position(time) ?? SatelliteSunTrack.exact(time) }

    /// The Sun's geometric altitude for the observer, in degrees.
    func sunAltitude(_ sun: Vector3, _ gmst: Double) -> Double {
        AstroMath.asinDeg(geometry.directionOf(sun.x, sun.y, sun.z, gmst).z)
    }

    func gmst(_ time: Double) -> Double { Sgp4Time.greenwichSiderealTime(SatelliteFrames.julianDateUt(time)) }

    /// The complete look of `satellite` at `time`, or `nil` if SGP4 fails.
    func look(_ satellite: Satellite, _ time: Double, _ state: inout [Double]) -> SatelliteLook? {
        let gmst = gmst(time)
        let sun = sunPosition(time)
        return Self.look(satellite, geometry, time, gmst, sun, sunAltitude(sun, gmst), &state)
    }

    static func look(
        _ satellite: Satellite,
        _ geometry: SatelliteObserverGeometry,
        _ time: Double,
        _ gmst: Double,
        _ sun: Vector3,
        _ sunAltitude: Double,
        _ state: inout [Double]
    ) -> SatelliteLook? {
        let propagator = satellite.propagator
        let minutes = (time - propagator.epochReferenceSeconds) / 60.0
        if propagator.propagateRaw(minutes, into: &state) != 0 { return nil }
        let topocentric = geometry.look(state[0], state[1], state[2], state[3], state[4], state[5], gmst)
        let fraction = EarthShadow.illuminatedFraction(state[0], state[1], state[2], sun.x, sun.y, sun.z)
        let sunDirection = geometry.directionOf(sun.x, sun.y, sun.z, gmst)
        let phase = SatelliteVectorMath.angleBetween(
            -topocentric.east, -topocentric.north, -topocentric.up,
            sunDirection.x, sunDirection.y, sunDirection.z
        )
        let altitude = topocentric.altitude
        let across = max(topocentric.relativeSpeed * topocentric.relativeSpeed - topocentric.rangeRate * topocentric.rangeRate, 0.0).squareRoot()
        let magnitude = satellite.intrinsicMagnitude.flatMap {
            SatelliteBrightness.apparentMagnitude(
                intrinsicMagnitude: $0, rangeKilometers: topocentric.range, phaseAngle: phase, illuminatedFraction: fraction
            )
        }
        return SatelliteLook(
            date: Date(timeIntervalSinceReferenceDate: time),
            azimuth: topocentric.azimuth,
            altitude: altitude,
            apparentAltitude: Refraction.apparentAltitude(trueAltitude: altitude, atmosphere: geometry.observer.atmosphere),
            rangeKilometers: topocentric.range,
            rangeRateKilometersPerSecond: topocentric.rangeRate,
            angularSpeed: AstroMath.degrees(across / topocentric.range),
            illuminatedFraction: fraction,
            phaseAngle: phase,
            sunAltitude: sunAltitude,
            magnitude: magnitude,
            temeState: TemeState(
                position: Vector3(state[0], state[1], state[2]),
                velocity: Vector3(state[3], state[4], state[5])
            )
        )
    }
}
