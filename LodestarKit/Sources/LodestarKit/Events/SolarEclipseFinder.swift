import Foundation

/// The kind of a solar eclipse over the whole Earth.
public enum SolarEclipseKind: String, CaseIterable, Sendable, Hashable, Codable {
    /// The Moon's shadow axis misses the Earth, or the umbra and antumbra never touch it.
    case partial
    /// The Moon appears smaller than the Sun everywhere along the path.
    case annular
    /// The Moon appears larger than the Sun everywhere along the path.
    case total
    /// Annular at the ends of the path and total in the middle.
    case hybrid

    /// The English name, e.g. "Annular".
    public var displayName: String {
        switch self {
        case .partial: "Partial"
        case .annular: "Annular"
        case .total: "Total"
        case .hybrid: "Hybrid"
        }
    }
}

/// What an observer sees of a solar eclipse.
public enum LocalSolarEclipseKind: String, CaseIterable, Sendable, Hashable, Codable {
    /// No eclipse is seen: the Moon does not touch the Sun, or the Sun is below the horizon throughout.
    case none
    /// Only a partial eclipse is seen.
    case partial
    /// The Moon is centred on the Sun but smaller: a ring remains.
    case annular
    /// The Moon covers the Sun completely.
    case total
}

/// A solar eclipse at one place, from the topocentric positions of the Sun and the Moon.
///
/// The contact times (C1 to C4) and the geometry are those of the discs of the Sun and the Moon as seen from the
/// observer, without regard to the horizon; `kind`, `maximum`, `magnitude`, `obscuration` and the Sun's position refer
/// to what can be seen: when the Sun rises or sets during the eclipse, `maximum` is the best visible moment (the
/// greatest eclipse if the Sun is up then, otherwise the sunrise or the sunset).
public struct LocalSolarCircumstances: Sendable, Hashable {
    /// What is seen; `LocalSolarEclipseKind.none` when the Moon never touches the Sun here or the Sun is below the
    /// horizon (centre lower than −0.8333°) for all of the eclipse.
    public let kind: LocalSolarEclipseKind
    /// First contact: the Moon begins to cover the Sun; `nil` when the Moon never touches the Sun.
    public let c1: Date?
    /// Second contact: totality or annularity begins; `nil` unless the Moon is centred on the Sun here.
    public let c2: Date?
    /// The moment of the greatest visible eclipse; `nil` when the Moon never touches the Sun.
    public let maximum: Date?
    /// Third contact: totality or annularity ends; `nil` unless the Moon is centred on the Sun here.
    public let c3: Date?
    /// Fourth contact: the Moon leaves the Sun; `nil` when the Moon never touches the Sun.
    public let c4: Date?
    /// The fraction of the Sun's diameter covered at `maximum` (1 or more for a total eclipse, less than 1 for an
    /// annular one), as in the tables of the U.S. Naval Observatory; 0 for none.
    public let magnitude: Double
    /// The fraction of the Sun's disc area covered at `maximum`, [0, 1].
    public let obscuration: Double
    /// The Sun's geometric altitude at `maximum` in degrees; `nil` for none without a contact.
    public let sunAltitude: Double?
    /// The Sun's azimuth at `maximum` in degrees from north through east; `nil` for none without a contact.
    public let sunAzimuth: Double?
    /// Seconds between C2 and C3; 0 without a central phase.
    public let centralDuration: Double
    /// The part of the eclipse with the Sun above the horizon; `nil` when there is none.
    public let visibleInterval: DateInterval?

    public init(kind: LocalSolarEclipseKind, c1: Date?, c2: Date?, maximum: Date?, c3: Date?, c4: Date?,
                magnitude: Double, obscuration: Double, sunAltitude: Double?, sunAzimuth: Double?,
                centralDuration: Double, visibleInterval: DateInterval?) {
        self.kind = kind
        self.c1 = c1
        self.c2 = c2
        self.maximum = maximum
        self.c3 = c3
        self.c4 = c4
        self.magnitude = magnitude
        self.obscuration = obscuration
        self.sunAltitude = sunAltitude
        self.sunAzimuth = sunAzimuth
        self.centralDuration = centralDuration
        self.visibleInterval = visibleInterval
    }
}

/// A solar eclipse; the event's date is `greatest`.
public struct SolarEclipse: Sendable, Hashable {
    /// The kind of eclipse over the whole Earth.
    public let kind: SolarEclipseKind
    /// The instant of the greatest eclipse: the shadow axis is nearest the Earth's centre.
    public let greatest: Date
    /// The least distance of the shadow axis from the Earth's centre in Earth equatorial radii, positive when it
    /// passes north of the centre.
    public let gamma: Double
    /// The magnitude at the greatest eclipse as in the NASA/Espenak catalog: the ratio of the Moon's to the Sun's
    /// apparent diameter for a central eclipse and the fraction of the Sun's diameter covered otherwise.
    public let greatestMagnitude: Double
    /// `true` when the axis of the shadow touches the Earth, so a total, annular or hybrid eclipse occurs somewhere
    /// (the global flag).
    public let isCentral: Bool
    /// The eclipse at the observer's place; `nil` without an observer.
    public let local: LocalSolarCircumstances?

    public init(kind: SolarEclipseKind, greatest: Date, gamma: Double, greatestMagnitude: Double, isCentral: Bool,
                local: LocalSolarCircumstances?) {
        self.kind = kind
        self.greatest = greatest
        self.gamma = gamma
        self.greatestMagnitude = greatestMagnitude
        self.isCentral = isCentral
        self.local = local
    }

    /// The eclipse with `local` replaced.
    func withLocal(_ local: LocalSolarCircumstances?) -> SolarEclipse {
        SolarEclipse(kind: kind, greatest: greatest, gamma: gamma, greatestMagnitude: greatestMagnitude,
                     isCentral: isCentral, local: local)
    }
}

/// The Moon's shadow cone at one instant, with the axis through the centres of the Sun and the Moon (geocentric apparent
/// positions, kilometres).
struct SolarShadow {
    let ut: Double
    /// Distance of the Earth's centre from the shadow axis.
    let axisDistance: Double
    /// Radius of the penumbra in the fundamental plane (through the Earth's centre, perpendicular to the axis).
    let penumbraRadius: Double
    /// Radius of the umbra in that plane; negative when the cone ends before it (the antumbra of an annular eclipse).
    let umbraRadius: Double
    /// Tangent of the half-angle of the umbra cone.
    let umbraTangent: Double
    /// Tangent of the half-angle of the penumbra cone.
    let penumbraTangent: Double
    /// Distance from the Moon's centre to the fundamental plane along the axis.
    let planeDistance: Double
    /// Distance between the centres of the Sun and the Moon.
    let sunMoonDistance: Double
    /// `true` when the axis passes north of the Earth's centre (north of the equator of J2000).
    let isNorth: Bool

    init(ut: Double) {
        self.ut = ut
        let jd = JulianDate(ut: ut)
        let sun = Ephemeris.geocentricJ2000(of: .sun, at: jd) * SkyFrame.kilometersPerAU
        let moon = Ephemeris.geocentricJ2000(of: .moon, at: jd) * SkyFrame.kilometersPerAU
        let between = moon - sun
        let distance = between.length
        let direction = between / distance
        let sunRadius = SolarSystemBody.sun.meanRadiusKilometers
        let moonRadius = SolarSystemBody.moon.meanRadiusKilometers
        let penumbraSine = (sunRadius + moonRadius) / distance
        let umbraSine = (sunRadius - moonRadius) / distance
        let penumbraCosine = (1 - penumbraSine * penumbraSine).squareRoot()
        let umbraCosine = (1 - umbraSine * umbraSine).squareRoot()
        penumbraTangent = penumbraSine / penumbraCosine
        umbraTangent = umbraSine / umbraCosine
        let toPlane = -moon.dot(direction)
        planeDistance = toPlane
        sunMoonDistance = distance
        penumbraRadius = moonRadius / penumbraCosine + toPlane * penumbraTangent
        umbraRadius = moonRadius / umbraCosine - toPlane * umbraTangent
        axisDistance = moon.cross(direction).length
        isNorth = (moon + direction * toPlane).z >= 0
    }
}

/// What the observer sees of the Sun and the Moon at one instant (angles in degrees).
private struct SolarView {
    let separation: Double
    let sunRadius: Double
    let moonRadius: Double
    let sunAltitude: Double
    let sunAzimuth: Double

    init(ut: Double, observer: Observer) {
        let frame = SkyFrame(julianDate: JulianDate(ut: ut), observer: observer)
        let sun = frame.precessionNutationMatrix * Ephemeris.geocentricJ2000(of: .sun, at: frame.julianDate)
            - frame.observerPositionOfDate
        let moon = frame.precessionNutationMatrix * Ephemeris.geocentricJ2000(of: .moon, at: frame.julianDate)
            - frame.observerPositionOfDate
        separation = sun.angle(to: moon)
        sunRadius = AstroMath.asinDeg(SolarSystemBody.sun.meanRadiusKilometers / (sun.length * SkyFrame.kilometersPerAU))
        moonRadius = AstroMath.asinDeg(SolarSystemBody.moon.meanRadiusKilometers / (moon.length * SkyFrame.kilometersPerAU))
        let horizontal = HorizontalCoordinate(vector: frame.equatorialOfDateToHorizontal * sun)
        sunAltitude = horizontal.altitude
        sunAzimuth = horizontal.azimuth
    }

    /// The fraction of the Sun's diameter covered.
    var magnitude: Double { DiscOverlap.magnitude(sunRadius: sunRadius, moonRadius: moonRadius, separation: separation) }

    /// The fraction of the Sun's disc area covered.
    var obscuration: Double { DiscOverlap.obscuration(sunRadius: sunRadius, moonRadius: moonRadius, separation: separation) }
}

/// The geometry of the Moon's disc in front of the Sun's.
enum DiscOverlap {
    /// The fraction of the Sun's diameter covered by the Moon's disc: (r☉ + r☾ − d) / 2 r☉, at least 0 (above 1 when the
    /// Moon covers the whole Sun and more).
    static func magnitude(sunRadius: Double, moonRadius: Double, separation: Double) -> Double {
        AstroMath.clamp((sunRadius + moonRadius - separation) / (2 * sunRadius), 0, Double.greatestFiniteMagnitude)
    }

    /// The fraction of the area of the Sun's disc (radius `sunRadius`) covered by the Moon's disc (radius `moonRadius`)
    /// whose centre is `separation` away (all in the same unit): the area of the lens of two circles over the Sun's area.
    static func obscuration(sunRadius: Double, moonRadius: Double, separation: Double) -> Double {
        if separation >= sunRadius + moonRadius { return 0 }
        if separation <= abs(sunRadius - moonRadius) {
            return moonRadius >= sunRadius ? 1 : (moonRadius / sunRadius) * (moonRadius / sunRadius)
        }
        let d = separation
        let first = acos(AstroMath.clamp((d * d + sunRadius * sunRadius - moonRadius * moonRadius) / (2 * d * sunRadius), -1, 1))
        let second = acos(AstroMath.clamp((d * d + moonRadius * moonRadius - sunRadius * sunRadius) / (2 * d * moonRadius), -1, 1))
        let kite = max(0, (-d + sunRadius + moonRadius) * (d + sunRadius - moonRadius)
            * (d - sunRadius + moonRadius) * (d + sunRadius + moonRadius)).squareRoot()
        let area = sunRadius * sunRadius * first + moonRadius * moonRadius * second - 0.5 * kite
        return AstroMath.clamp(area / (Double.pi * sunRadius * sunRadius), 0, 1)
    }
}

/// Finds solar eclipses and computes their local circumstances.
///
/// **Global.** For each new Moon whose ecliptic latitude is below 1.75° the greatest eclipse is the instant at which the
/// axis through the centres of the Sun and the Moon passes nearest the Earth's centre (golden-section search). The
/// shadow cone gives γ and the radii of the penumbra and umbra in the fundamental plane, and the kind follows J. Meeus,
/// *Astronomical Algorithms*, ch. 54: central if |γ| < 0.9972, then total when the umbra reaches the plane, hybrid when
/// it falls short by less than the depth of the Earth's surface at γ and annular when it falls further short; partial
/// otherwise.
///
/// **Local.** The separation of the topocentric apparent positions of the Sun's and the Moon's centres is sampled every
/// 20 minutes within ±7.2 hours of the greatest eclipse; the maximum is found by golden-section search, the contacts by
/// Brent's method on the separation minus the sum (C1, C4) or the difference (C2, C3) of the apparent radii.
///
/// Cost: about 3 ms per eclipse for the global circumstances and about 2 ms per observer.
public enum SolarEclipseFinder {
    /// The ecliptic latitude of the Moon in degrees above which a new Moon is not examined.
    private static let latitudeLimit = 1.75
    private static let searchHalfWindow = 0.2
    private static let greatestTolerance = 1e-6
    private static let centralLimit = 0.9972
    private static let localHalfWindow = 0.3
    private static let localStep = 20.0 / 1440
    private static let visibleStep = 10.0 / 1440
    private static let contactTolerance = 1e-6

    /// The solar eclipses with the greatest eclipse from `from` to `to` (both inclusive), as events without visibility,
    /// in time order. With an `observer` each carries its `SolarEclipse.local` circumstances.
    public static func events(from: Date, to: Date, observer: Observer? = nil) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let end = EventSearch.limitedEnd(from: from, to: to)
        return events(from: from, to: end, observer: observer, phases: PhaseTable(from: from, to: end))
    }

    static func events(from: Date, to: Date, observer: Observer?, phases: PhaseTable) -> [AstronomicalEvent] {
        var found = [AstronomicalEvent]()
        for newMoon in phases.newMoons {
            guard let eclipse = eclipse(newMoon: newMoon) else { continue }
            if eclipse.greatest < from || eclipse.greatest > to { continue }
            let complete = observer.map { eclipse.withLocal(localCircumstances(of: eclipse, observer: $0)) } ?? eclipse
            found.append(AstronomicalEvent(date: complete.greatest, details: .solarEclipse(complete), visibility: nil))
        }
        return found
    }

    /// The eclipse of the new Moon at `newMoon` without local circumstances, or `nil` when the Moon's shadow misses the Earth.
    static func eclipse(newMoon: Date) -> SolarEclipse? {
        let ut0 = EventSearch.ut(newMoon)
        let moon = Ephemeris.geocentricJ2000(of: .moon, at: JulianDate(ut: ut0))
        if abs(AstroMath.asinDeg(moon.dot(LunarShadow.eclipticNorth) / moon.length)) > latitudeLimit { return nil }
        let greatestUT = EventSearch.minimum(of: { SolarShadow(ut: $0).axisDistance }, lower: ut0 - searchHalfWindow,
                                             upper: ut0 + searchHalfWindow, tolerance: greatestTolerance).time
        let shadow = SolarShadow(ut: greatestUT)
        let earthRadius = SkyFrame.earthEquatorialRadiusKilometers
        let absoluteGamma = shadow.axisDistance / earthRadius
        if absoluteGamma >= 1 + shadow.penumbraRadius / earthRadius { return nil }
        let gamma = shadow.isNorth ? absoluteGamma : -absoluteGamma
        let u = -shadow.umbraRadius / earthRadius
        let isCentralPath = absoluteGamma < centralLimit
        let kind: SolarEclipseKind
        if isCentralPath {
            let depth = shadow.umbraTangent * (1 - absoluteGamma * absoluteGamma).squareRoot()
            kind = u < 0 ? .total : (u > depth ? .annular : .hybrid)
        } else if absoluteGamma < centralLimit + abs(u) {
            kind = u < 0 ? .total : .annular
        } else {
            kind = .partial
        }
        let magnitude: Double
        if isCentralPath {
            let surface = shadow.planeDistance - (earthRadius * earthRadius - shadow.axisDistance * shadow.axisDistance).squareRoot()
            let sunRadius = SolarSystemBody.sun.meanRadiusKilometers
            let moonRadius = SolarSystemBody.moon.meanRadiusKilometers
            magnitude = moonRadius * (shadow.sunMoonDistance + surface) / (sunRadius * surface)
        } else {
            let offset = max(shadow.axisDistance - earthRadius, 0)
            magnitude = (shadow.penumbraRadius - offset) / (shadow.penumbraRadius - shadow.umbraRadius)
        }
        return SolarEclipse(kind: kind, greatest: EventSearch.instant(greatestUT), gamma: gamma,
                            greatestMagnitude: magnitude, isCentral: isCentralPath && kind != .partial, local: nil)
    }

    /// The circumstances of `eclipse` at `observer`'s place; costs about 2 ms.
    public static func localCircumstances(of eclipse: SolarEclipse, observer: Observer) -> LocalSolarCircumstances {
        let centre = EventSearch.ut(eclipse.greatest)
        guard centre.isFinite else {
            return LocalSolarCircumstances(kind: .none, c1: nil, c2: nil, maximum: nil, c3: nil, c4: nil, magnitude: 0,
                                           obscuration: 0, sunAltitude: nil, sunAzimuth: nil, centralDuration: 0,
                                           visibleInterval: nil)
        }
        let start = centre - localHalfWindow
        let end = centre + localHalfWindow
        let count = EventSearch.intervalCount(span: end - start, step: localStep)
        let times = (0...count).map { start + (end - start) * Double($0) / Double(count) }
        let views = times.map { SolarView(ut: $0, observer: observer) }
        var lowest = 0
        for index in 1...count where views[index].separation < views[lowest].separation {
            lowest = index
        }
        let peak = EventSearch.minimum(of: { SolarView(ut: $0, observer: observer).separation },
                                       lower: times[max(lowest - 1, 0)], upper: times[min(lowest + 1, count)],
                                       tolerance: greatestTolerance).time
        let closest = SolarView(ut: peak, observer: observer)
        if closest.separation >= closest.sunRadius + closest.moonRadius {
            return LocalSolarCircumstances(kind: .none, c1: nil, c2: nil, maximum: nil, c3: nil, c4: nil, magnitude: 0,
                                           obscuration: 0, sunAltitude: nil, sunAzimuth: nil, centralDuration: 0,
                                           visibleInterval: nil)
        }

        func contactMargin(_ ut: Double) -> Double {
            let view = SolarView(ut: ut, observer: observer)
            return view.separation - (view.sunRadius + view.moonRadius)
        }

        func centralMargin(_ ut: Double) -> Double {
            let view = SolarView(ut: ut, observer: observer)
            return view.separation - abs(view.moonRadius - view.sunRadius)
        }

        let firstContact = EventSearch.root(of: contactMargin, lower: start, upper: peak, tolerance: contactTolerance) ?? start
        let lastContact = EventSearch.root(of: contactMargin, lower: peak, upper: end, tolerance: contactTolerance) ?? end
        var secondContact: Double?
        var thirdContact: Double?
        if closest.separation < abs(closest.moonRadius - closest.sunRadius) {
            secondContact = EventSearch.root(of: centralMargin, lower: firstContact, upper: peak, tolerance: contactTolerance)
            thirdContact = EventSearch.root(of: centralMargin, lower: peak, upper: lastContact, tolerance: contactTolerance)
        }

        let horizon = RiseSetCalculator.sunHorizonAltitude
        let window = AltitudeWindow.best(start: firstContact, end: lastContact, step: visibleStep, threshold: horizon) {
            SolarView(ut: $0, observer: observer).sunAltitude
        }
        let maximum = window.map { AstroMath.clamp(peak, $0.start, $0.end) } ?? peak
        let view = SolarView(ut: maximum, observer: observer)
        var centralVisible = false
        if let window, let secondContact, let thirdContact {
            centralVisible = secondContact <= window.end && thirdContact >= window.start
        }
        let kind: LocalSolarEclipseKind
        if window == nil {
            kind = .none
        } else if centralVisible {
            kind = closest.moonRadius > closest.sunRadius ? .total : .annular
        } else {
            kind = .partial
        }
        var centralDuration = 0.0
        if let secondContact, let thirdContact {
            centralDuration = (thirdContact - secondContact) * JulianDate.secondsPerDay
        }
        return LocalSolarCircumstances(
            kind: kind,
            c1: EventSearch.instant(firstContact),
            c2: secondContact.map { EventSearch.instant($0) },
            maximum: EventSearch.instant(maximum),
            c3: thirdContact.map { EventSearch.instant($0) },
            c4: EventSearch.instant(lastContact),
            magnitude: view.magnitude,
            obscuration: view.obscuration,
            sunAltitude: view.sunAltitude,
            sunAzimuth: view.sunAzimuth,
            centralDuration: centralDuration,
            visibleInterval: window.map { DateInterval(start: EventSearch.instant($0.start), end: EventSearch.instant($0.end)) })
    }
}
