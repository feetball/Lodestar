import Foundation

extension SkyFrame {
    /// Horizontal coordinates of an object at this frame's instant.
    ///
    /// Fixed objects include proper motion, aberration and precession; solar-system bodies are
    /// topocentric; the celestial poles are the poles of date.
    ///
    /// - Parameter refraction: Whether to raise the altitude by atmospheric refraction.
    public func horizontal(of object: CelestialObject, refraction: Bool = true) -> HorizontalCoordinate {
        switch object.position {
        case .fixed(let coordinate, let properMotion):
            horizontal(j2000: coordinate, properMotion: properMotion, refraction: refraction)
        case .solarSystem(let body):
            horizontal(of: body, refraction: refraction)
        case .celestialPole(let north):
            horizontalOfCelestialPole(north: north, refraction: refraction)
        }
    }

    /// The apparent place of an object in the true equatorial frame of date.
    ///
    /// Fixed objects get proper motion, aberration, precession and nutation; solar-system bodies
    /// are topocentric (parallax matters for the Moon); a celestial pole is at right ascension 0°
    /// and declination ±90°.
    public func apparentEquatorial(of object: CelestialObject) -> EquatorialCoordinate {
        switch object.position {
        case .fixed(let coordinate, let properMotion):
            apparentPlace(j2000: coordinate, properMotion: properMotion)
        case .solarSystem(let body):
            topocentricEquatorial(of: body)
        case .celestialPole(let north):
            EquatorialCoordinate(rightAscension: 0, declination: north ? 90 : -90)
        }
    }

    /// The size an object has at this frame's instant.
    ///
    /// For the Sun, the Moon and the planets this is the apparent diameter of the disc, which varies
    /// with distance (the Moon between about 29′ and 34′); for other objects it is the catalog
    /// size, which may be `nil`.
    public func currentAngularSize(of object: CelestialObject) -> AngularSize? {
        guard case .solarSystem(let body) = object.position else { return object.angularSize }
        let diameter = state(of: body).angularDiameterArcseconds / 60
        return AngularSize(majorArcminutes: diameter, minorArcminutes: diameter)
    }

    /// The magnitude an object has at this frame's instant.
    ///
    /// The apparent magnitude from the ephemeris for the Sun, the Moon and the planets (the Moon's
    /// depends on its phase); the catalog magnitude for other objects, which may be `nil`.
    public func currentMagnitude(of object: CelestialObject) -> Double? {
        guard case .solarSystem(let body) = object.position else { return object.magnitude }
        return state(of: body).apparentMagnitude
    }
}

extension RiseSetCalculator {
    /// The first rise, transit and set of an object inside `interval`.
    ///
    /// Stars, deep-sky objects and planets use `standardHorizonAltitude`, the Sun `sunHorizonAltitude`
    /// and the Moon its upper limb (see `riseTransitSet(for:observer:within:)` for a body).
    ///
    /// A celestial pole never rises or sets: the result is `alwaysUp` when the pole is above
    /// the standard horizon altitude for the observer's latitude and `alwaysDown` otherwise, has no
    /// rise, transit or set, and reports the pole's constant altitude as `transitAltitude`.
    public static func riseTransitSet(for object: CelestialObject, observer: Observer,
                                      within interval: DateInterval) -> RiseTransitSet {
        switch object.position {
        case .fixed(let coordinate, let properMotion):
            return riseTransitSet(forJ2000: coordinate, properMotion: properMotion, observer: observer,
                                  within: interval)
        case .solarSystem(let body):
            return riseTransitSet(for: body, observer: observer, within: interval)
        case .celestialPole(let north):
            // The altitude of the pole of date is the geodetic latitude, to the precision of this app.
            let altitude = north ? observer.location.latitude : -observer.location.latitude
            return RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: altitude,
                                  circumstance: altitude >= standardHorizonAltitude ? .alwaysUp : .alwaysDown)
        }
    }
}
