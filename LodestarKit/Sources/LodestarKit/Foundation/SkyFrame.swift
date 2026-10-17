import Foundation

/// Proper motion of a star in milliarcseconds per year, J2000 catalog convention.
public struct ProperMotion: Hashable, Codable, Sendable {
    /// μα* = μα · cos δ (as in Hipparcos), mas/yr.
    public let raMilliarcsecondsPerYear: Double
    /// μδ, mas/yr.
    public let decMilliarcsecondsPerYear: Double

    public init(raMilliarcsecondsPerYear: Double, decMilliarcsecondsPerYear: Double) {
        self.raMilliarcsecondsPerYear = raMilliarcsecondsPerYear.isFinite ? raMilliarcsecondsPerYear : 0
        self.decMilliarcsecondsPerYear = decMilliarcsecondsPerYear.isFinite ? decMilliarcsecondsPerYear : 0
    }

    /// Applies the motion to a J2000.0 catalog place over `years` Julian years, working on the
    /// unit vector so there is no singularity at the poles.
    public func apply(to position: EquatorialCoordinate, years: Double) -> EquatorialCoordinate {
        EquatorialCoordinate(vector: applyToUnitVector(of: position, years: years))
    }

    func applyToUnitVector(of position: EquatorialCoordinate, years: Double) -> Vector3 {
        let masToRadians = 1 / (AstroMath.arcsecondsPerRadian * 1000)
        let sa = AstroMath.sinDeg(position.rightAscension), ca = AstroMath.cosDeg(position.rightAscension)
        let sd = AstroMath.sinDeg(position.declination), cd = AstroMath.cosDeg(position.declination)
        let towardsEast = Vector3(-sa, ca, 0)
        let towardsNorth = Vector3(-sd * ca, -sd * sa, cd)
        let displacement = towardsEast * (raMilliarcsecondsPerYear * masToRadians * years)
            + towardsNorth * (decMilliarcsecondsPerYear * masToRadians * years)
        return (position.unitVector + displacement).normalized
    }
}

/// Where and under which conditions the sky is observed.
public struct Observer: Hashable, Codable, Sendable {
    public var location: GeographicLocation
    public var atmosphere: Atmosphere

    public init(location: GeographicLocation, atmosphere: Atmosphere = .standard) {
        self.location = location
        self.atmosphere = atmosphere
    }
}

/// Everything needed to turn catalog or ephemeris positions into horizontal coordinates for one
/// instant and observer. Building a frame is cheap (a few microseconds); reuse one frame for all
/// objects drawn at that instant.
///
/// Pipeline for fixed objects (stars, deep-sky objects): J2000 catalog place → proper motion →
/// annual aberration → precession → nutation → (apparent place of date) → local sidereal time and
/// latitude → horizontal → optional refraction. Light deflection, annual parallax, diurnal
/// aberration and polar motion are neglected (all ≤ 1″).
public struct SkyFrame: Sendable {
    /// Earth equatorial radius used for the observer's geocentric position (km).
    public static let earthEquatorialRadiusKilometers = 6378.14
    /// Kilometres per astronomical unit.
    public static let kilometersPerAU = 149_597_870.7

    public let date: Date
    public let julianDate: JulianDate
    public let observer: Observer
    public let nutation: Nutation
    /// Mean obliquity of date (degrees).
    public let meanObliquity: Double
    /// True obliquity of date (degrees).
    public let trueObliquity: Double
    /// Greenwich apparent sidereal time (degrees).
    public let greenwichApparentSiderealTime: Double
    /// Local apparent sidereal time (degrees).
    public let localApparentSiderealTime: Double
    /// J2000 → mean equator & equinox of date.
    public let precessionMatrix: Matrix3
    /// J2000 → true equator & equinox of date.
    public let precessionNutationMatrix: Matrix3
    /// True equatorial of date → local ENU horizon frame.
    public let equatorialOfDateToHorizontal: Matrix3
    /// J2000 → local ENU horizon frame (precession, nutation and Earth rotation combined).
    public let j2000ToHorizontal: Matrix3
    /// Earth's orbital velocity β = v/c in the J2000 frame (for annual aberration).
    public let earthVelocity: Vector3
    /// Observer's geocentric position in AU, true equator & equinox of date.
    public let observerPositionOfDate: Vector3

    public init(date: Date, observer: Observer) {
        self.init(julianDate: JulianDate(date: date), observer: observer)
    }

    public init(julianDate jd: JulianDate, observer: Observer) {
        self.date = jd.date
        self.julianDate = jd
        self.observer = observer
        let nutation = Nutation(julianDate: jd)
        self.nutation = nutation
        let meanObliquity = Obliquity.mean(jd)
        self.meanObliquity = meanObliquity
        let trueObliquity = meanObliquity + nutation.obliquity
        self.trueObliquity = trueObliquity
        let gast = SiderealTime.greenwichApparent(jd, nutation: nutation, trueObliquity: trueObliquity)
        self.greenwichApparentSiderealTime = gast
        let last = AstroMath.normalizeDegrees(gast + observer.location.longitude)
        self.localApparentSiderealTime = last

        let precession = Precession.matrixFromJ2000(to: jd)
        self.precessionMatrix = precession
        let precessionNutation = nutation.matrix(meanObliquity: meanObliquity) * precession
        self.precessionNutationMatrix = precessionNutation
        let toHorizontal = CoordinateTransforms.localEquatorialToHorizontal(latitude: observer.location.latitude)
            * Matrix3.frameRotationZ(AstroMath.radians(last))
        self.equatorialOfDateToHorizontal = toHorizontal
        self.j2000ToHorizontal = toHorizontal * precessionNutation
        self.earthVelocity = Aberration.earthVelocity(jd)
        self.observerPositionOfDate = Self.geocentricObserverPosition(location: observer.location,
                                                                      localSiderealTime: last)
    }

    // MARK: Fixed objects

    /// Apparent place (true equator & equinox of date, geocentric) of a J2000 catalog position.
    public func apparentPlace(j2000: EquatorialCoordinate, properMotion: ProperMotion? = nil) -> EquatorialCoordinate {
        EquatorialCoordinate(vector: precessionNutationMatrix * aberratedDirection(j2000: j2000, properMotion: properMotion))
    }

    /// Horizontal coordinates of a J2000 catalog position, optionally including refraction.
    public func horizontal(j2000: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                           refraction: Bool = true) -> HorizontalCoordinate {
        let geometric = HorizontalCoordinate(vector: j2000ToHorizontal * aberratedDirection(j2000: j2000, properMotion: properMotion))
        return refraction ? Self.refracted(geometric, atmosphere: observer.atmosphere) : geometric
    }

    /// Fast path for rendering many objects: ENU unit vector of a J2000 unit vector, with
    /// aberration but without proper motion or refraction.
    public func horizontalVector(j2000UnitVector: Vector3) -> Vector3 {
        j2000ToHorizontal * Aberration.apply(to: j2000UnitVector, earthVelocity: earthVelocity)
    }

    // MARK: Solar-system bodies

    /// Topocentric apparent place (true equator & equinox of date) of a body whose geocentric
    /// J2000 position (AU) already includes light-time and aberration.
    public func topocentricEquatorial(geocentricJ2000: Vector3) -> EquatorialCoordinate {
        EquatorialCoordinate(vector: precessionNutationMatrix * geocentricJ2000 - observerPositionOfDate)
    }

    /// Topocentric horizontal coordinates of a body whose geocentric J2000 position (AU) already
    /// includes light-time and aberration.
    public func horizontal(geocentricJ2000: Vector3, refraction: Bool = true) -> HorizontalCoordinate {
        let topocentric = precessionNutationMatrix * geocentricJ2000 - observerPositionOfDate
        let geometric = HorizontalCoordinate(vector: equatorialOfDateToHorizontal * topocentric)
        return refraction ? Self.refracted(geometric, atmosphere: observer.atmosphere) : geometric
    }

    // MARK: Celestial poles

    /// Horizontal coordinates of the true celestial pole of date.
    public func horizontalOfCelestialPole(north: Bool, refraction: Bool = true) -> HorizontalCoordinate {
        let pole = Vector3(0, 0, north ? 1 : -1)
        let geometric = HorizontalCoordinate(vector: equatorialOfDateToHorizontal * pole)
        return refraction ? Self.refracted(geometric, atmosphere: observer.atmosphere) : geometric
    }

    // MARK: Inverse and helpers

    /// The J2000 position seen in direction `horizontal` (e.g. "what is the camera pointing at").
    /// Removes refraction when `refracted` is true and first-order aberration; ignores parallax.
    public func j2000(fromHorizontal horizontal: HorizontalCoordinate, refracted: Bool) -> EquatorialCoordinate {
        let altitude = refracted
            ? Refraction.trueAltitude(apparentAltitude: horizontal.altitude, atmosphere: observer.atmosphere)
            : horizontal.altitude
        let geometric = HorizontalCoordinate(azimuth: horizontal.azimuth, altitude: altitude)
        let apparentJ2000 = j2000ToHorizontal.transposed * geometric.unitVector
        return EquatorialCoordinate(vector: Aberration.remove(from: apparentJ2000, earthVelocity: earthVelocity))
    }

    /// Local hour angle in degrees, (-180, 180], of an apparent right ascension of date.
    public func hourAngle(apparentRightAscension: Double) -> Double {
        AstroMath.normalizeSignedDegrees(localApparentSiderealTime - apparentRightAscension)
    }

    /// Julian years of TT elapsed since J2000.0 (the catalog epoch).
    public var yearsSinceJ2000: Double { (julianDate.tt - JulianDate.j2000) / 365.25 }

    /// `horizontal` with its altitude raised by atmospheric refraction.
    public static func refracted(_ horizontal: HorizontalCoordinate, atmosphere: Atmosphere) -> HorizontalCoordinate {
        HorizontalCoordinate(azimuth: horizontal.azimuth,
                             altitude: Refraction.apparentAltitude(trueAltitude: horizontal.altitude, atmosphere: atmosphere))
    }

    private func aberratedDirection(j2000: EquatorialCoordinate, properMotion: ProperMotion?) -> Vector3 {
        let mean = properMotion?.applyToUnitVector(of: j2000, years: yearsSinceJ2000) ?? j2000.unitVector
        return Aberration.apply(to: mean, earthVelocity: earthVelocity)
    }

    /// Observer's geocentric position (Meeus ch. 11) in AU in the true equatorial frame of date.
    static func geocentricObserverPosition(location: GeographicLocation, localSiderealTime: Double) -> Vector3 {
        let flattening = 1 / 298.257
        let axisRatio = 1 - flattening
        let latitude = AstroMath.radians(location.latitude)
        let u = atan(axisRatio * tan(latitude))
        let heightRatio = location.elevation / (earthEquatorialRadiusKilometers * 1000)
        let rhoSin = axisRatio * sin(u) + heightRatio * sin(latitude)
        let rhoCos = cos(u) + heightRatio * cos(latitude)
        let scale = earthEquatorialRadiusKilometers / kilometersPerAU
        let theta = AstroMath.radians(localSiderealTime)
        return Vector3(rhoCos * cos(theta), rhoCos * sin(theta), rhoSin) * scale
    }
}
