// WorldMagneticModel.swift
//
// The NOAA/BGS World Magnetic Model 2025 (WMM2025): a degree-12 spherical-harmonic model of the
// Earth's main magnetic field, valid from 2025.0 to 2030.0. It gives the magnetic declination
// needed to turn a compass heading into a true heading, and the expected field strength against
// which a magnetometer reading can be checked for local interference.
//
// Algorithm: Chulliat et al., "The US/UK World Magnetic Model for 2025-2030: Technical Report",
// NOAA NCEI, 2025, https://doi.org/10.25923/prbc-s316, section 1.2 (equation numbers below refer
// to that report). Coefficients: NOAA NCEI, https://doi.org/10.25921/aqfd-sd83 (public domain).

import Foundation

// MARK: - Field elements

/// The geomagnetic field vector at one point, in the local geodetic north-east-down frame.
///
/// All seven classical magnetic elements follow from the three components `north`, `east` and
/// `down`, so they are stored once and the remaining elements are derived from them.
public struct MagneticFieldElements: Sendable, Hashable {
    /// Northward component X, in nanotesla.
    public let north: Double
    /// Eastward component Y, in nanotesla.
    public let east: Double
    /// Downward component Z, in nanotesla (positive into the Earth).
    public let down: Double

    /// Creates field elements from the north, east and down components, in nanotesla.
    public init(north: Double, east: Double, down: Double) {
        self.north = north
        self.east = east
        self.down = down
    }

    /// Horizontal intensity H, in nanotesla.
    public var horizontalIntensity: Double { hypot(north, east) }

    /// Total intensity F, in nanotesla. Compare it with a magnetometer's field magnitude
    /// (1 microtesla = 1000 nT) to detect magnetic interference.
    public var totalIntensity: Double { hypot(horizontalIntensity, down) }

    /// Declination D in degrees, the angle from true north to magnetic north, in [-180, 180].
    /// East is positive: `trueHeading = magneticHeading + declination`.
    ///
    /// The declination is poorly conditioned where the horizontal intensity is small, near the
    /// magnetic poles; see ``compassReliability``.
    public var declination: Double { atan2(east, north) * Self.degreesPerRadian }

    /// Inclination (dip) I in degrees, in [-90, 90]. Positive when the field points into the Earth.
    public var inclination: Double { atan2(down, horizontalIntensity) * Self.degreesPerRadian }

    /// Whether all components are finite. The model returns non-finite elements only for
    /// non-finite input.
    public var isValid: Bool { north.isFinite && east.isFinite && down.isFinite }

    /// How far a compass can be trusted here, from NOAA's horizontal-intensity thresholds for the
    /// WMM Blackout Zones (technical report, section 1.8). Non-finite elements report `.blackout`.
    public var compassReliability: CompassReliability {
        let horizontal = horizontalIntensity
        if horizontal >= Self.cautionZoneThreshold { return .reliable }
        if horizontal >= Self.blackoutZoneThreshold { return .caution }
        return .blackout
    }

    private static let degreesPerRadian = 180 / Double.pi
    private static let blackoutZoneThreshold = 2000.0
    private static let cautionZoneThreshold = 6000.0
}

/// How far a magnetic compass can be trusted, judged by the horizontal field intensity.
public enum CompassReliability: Sendable, Hashable {
    /// Horizontal intensity of 6000 nT or more, outside the zones around the magnetic poles.
    case reliable
    /// Horizontal intensity from 2000 nT up to 6000 nT: the Caution Zone around a magnetic pole,
    /// where compass accuracy degrades increasingly and declination errors can exceed 1 degree.
    case caution
    /// Horizontal intensity below 2000 nT: the Blackout Zone, where a compass must not be trusted
    /// and declination errors of up to 180 degrees occur.
    case blackout
}

// MARK: - Model

/// A degree-12 spherical-harmonic model of the Earth's main magnetic field.
///
/// Use ``wmm2025`` for the World Magnetic Model 2025. The model is a pure value: evaluation has no
/// side effects and may be called from any thread.
///
/// The WMM describes the main (core) field only. Its typical global RMS error at the Earth's surface
/// is about 0.4 degrees in declination and 130 nT in total intensity (technical report, table 16),
/// dominated by the crustal field it does not include. Local anomalies, and ferromagnetic material
/// or electronics near a magnetometer, can change a reading by much more than that.
public struct WorldMagneticModel: Sendable {
    /// The World Magnetic Model 2025, valid from 2025.0 to 2030.0.
    public static let wmm2025 = WorldMagneticModel(
        epoch: WMM2025Coefficients.epoch,
        rows: WMM2025Coefficients.rows
    )

    /// The reference epoch t0 of the main-field coefficients, in decimal years.
    public let epoch: Double
    /// The start of the validity interval, in decimal years.
    public let validFrom: Double
    /// The end of the validity interval, in decimal years. The model is not valid at this instant
    /// or later: WMM2025 is to be used from 1 January 2025 through 31 December 2029.
    public let validUntil: Double

    private let maximumDegree: Int
    private let mainFieldG: [Double]
    private let mainFieldH: [Double]
    private let secularVariationG: [Double]
    private let secularVariationH: [Double]

    /// Creates a model from coefficient rows. Pairs of degree and order that no row names are zero.
    ///
    /// - Precondition: Each row has a degree of at least 1 and an order from 0 through its degree.
    init(epoch: Double, rows: [CoefficientRow]) {
        let degree = rows.reduce(0) { max($0, $1.degree) }
        precondition(degree >= 1, "A magnetic model needs at least one coefficient of degree 1")
        let count = LegendreTable.entryCount(maximumDegree: degree)
        var g = [Double](repeating: 0, count: count)
        var h = g
        var gDot = g
        var hDot = g
        for row in rows {
            precondition(row.degree >= 1 && (0...row.degree).contains(row.order), "Invalid degree or order")
            let index = LegendreTable.index(degree: row.degree, order: row.order)
            g[index] = row.g
            h[index] = row.h
            gDot[index] = row.gDot
            hDot[index] = row.hDot
        }
        self.epoch = epoch
        self.validFrom = epoch
        self.validUntil = epoch + Self.validityYears
        self.maximumDegree = degree
        self.mainFieldG = g
        self.mainFieldH = h
        self.secularVariationG = gDot
        self.secularVariationH = hDot
    }

    /// Reports whether `decimalYear` lies within the interval for which the model is valid.
    /// A non-finite year is never valid.
    public func isWithinValidity(decimalYear: Double) -> Bool {
        decimalYear >= validFrom && decimalYear < validUntil
    }

    /// Evaluates the model at a point.
    ///
    /// Out-of-range input is brought into range rather than rejected: `latitude` is clamped to
    /// [-90, 90], `longitude` is wrapped into [-180, 180] and `altitudeMeters` is clamped to the
    /// range of the model, 1 km below to 850 km above the ellipsoid. A non-finite argument yields
    /// elements for which ``MagneticFieldElements/isValid`` is false.
    ///
    /// A `decimalYear` outside the validity interval is extrapolated linearly and is
    /// increasingly unreliable; check ``isWithinValidity(decimalYear:)``.
    ///
    /// The geographic poles are supported. There the north direction is defined as the limit of
    /// the north direction along the meridian of `longitude`, so the declination at a pole
    /// depends on the longitude supplied (technical report, section 1.4).
    ///
    /// - Parameters:
    ///   - latitude: Geodetic latitude in degrees, north positive.
    ///   - longitude: Longitude in degrees, east positive.
    ///   - altitudeMeters: Height above the WGS 84 ellipsoid in meters. A height above mean sea
    ///     level is adequate: the geoid lies within about 110 m of the ellipsoid, which changes the
    ///     field by only a few nanotesla.
    ///   - decimalYear: The time as a decimal year, for example 2026.5; see ``decimalYear(from:)``.
    /// - Returns: The field in the local geodetic north-east-down frame.
    public func field(
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double,
        decimalYear: Double
    ) -> MagneticFieldElements {
        guard latitude.isFinite, longitude.isFinite, altitudeMeters.isFinite, decimalYear.isFinite else {
            return MagneticFieldElements(north: .nan, east: .nan, down: .nan)
        }
        let clampedLatitude = min(max(latitude, -90), 90)
        let wrappedLongitude = longitude.remainder(dividingBy: 360)
        let clampedAltitude = min(max(altitudeMeters, Self.minimumAltitudeMeters), Self.maximumAltitudeMeters)

        let position = GeocentricPosition(
            geodeticLatitudeDegrees: clampedLatitude,
            heightKilometers: clampedAltitude / 1000
        )
        let geocentric = synthesize(
            sinLatitude: position.sinLatitude,
            cosLatitude: position.cosLatitude,
            longitudeRadians: wrappedLongitude * Double.pi / 180,
            radiusKilometers: position.radiusKilometers,
            decimalYear: decimalYear
        )

        // Equation (17): rotate the geocentric components into the geodetic frame.
        return MagneticFieldElements(
            north: geocentric.north * position.rotationCosine - geocentric.down * position.rotationSine,
            east: geocentric.east,
            down: geocentric.north * position.rotationSine + geocentric.down * position.rotationCosine
        )
    }

    /// Converts a date to a decimal year: the UTC calendar year plus the elapsed fraction of that
    /// year, so that midday UTC on 2 July 2025 is exactly 2025.5. Leap seconds are ignored, as in
    /// POSIX time.
    ///
    /// Returns `nan` for a date that is not finite or lies more than about 300,000 years from 1970.
    public static func decimalYear(from date: Date) -> Double {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, abs(seconds) <= maximumConvertibleSeconds else { return .nan }

        // The mean Gregorian year estimate is at most one year off; the loops correct it.
        var year = 1970 + Int((seconds / (365.2425 * secondsPerDay)).rounded(.down))
        var start = unixSeconds(atStartOfYear: year)
        while seconds < start {
            year -= 1
            start = unixSeconds(atStartOfYear: year)
        }
        var end = unixSeconds(atStartOfYear: year + 1)
        while seconds >= end {
            year += 1
            start = end
            end = unixSeconds(atStartOfYear: year + 1)
        }
        return Double(year) + (seconds - start) / (end - start)
    }

    // MARK: Spherical-harmonic synthesis

    /// Evaluates the geocentric field components X', Y', Z' (equations 9 to 12), in nanotesla.
    ///
    /// The east component divides by cos(phi'). Instead of special-casing the poles, the
    /// `LegendreTable` supplies P(sin phi') / cos(phi') from a recurrence that never divides,
    /// which equals the limit the technical report prescribes at the poles (section 1.4).
    ///
    /// - Parameters:
    ///   - sinLatitude: sin(phi') of the geocentric latitude.
    ///   - cosLatitude: cos(phi') of the geocentric latitude; zero at the poles.
    ///   - longitudeRadians: Longitude in radians.
    ///   - radiusKilometers: Distance from the Earth's center in kilometers.
    ///   - decimalYear: Time in decimal years.
    func synthesize(
        sinLatitude: Double,
        cosLatitude: Double,
        longitudeRadians: Double,
        radiusKilometers: Double,
        decimalYear: Double
    ) -> (north: Double, east: Double, down: Double) {
        let table = LegendreTable(
            maximumDegree: maximumDegree,
            sinLatitude: sinLatitude,
            cosLatitude: cosLatitude
        )
        let elapsedYears = decimalYear - epoch
        let radiusRatio = Self.referenceRadiusKilometers / radiusKilometers
        let cosines = (0...maximumDegree).map { cos(Double($0) * longitudeRadians) }
        let sines = (0...maximumDegree).map { sin(Double($0) * longitudeRadians) }

        var north = 0.0
        var east = 0.0
        var down = 0.0
        for degree in 1...maximumDegree {
            let radialFactor = pow(radiusRatio, Double(degree + 2))  // (a/r)^(n+2)
            for order in 0...degree {
                let index = LegendreTable.index(degree: degree, order: order)
                // Equation (9): time-adjusted Gauss coefficients.
                let g = mainFieldG[index] + elapsedYears * secularVariationG[index]
                let h = mainFieldH[index] + elapsedYears * secularVariationH[index]
                let cosine = cosines[order]
                let sine = sines[order]

                let cosineTerm = g * cosine + h * sine
                north -= radialFactor * cosineTerm * table.latitudeDerivative[index]
                east += radialFactor * Double(order) * (g * sine - h * cosine) * table.overCosine[index]
                down -= radialFactor * Double(degree + 1) * cosineTerm * table.value[index]
            }
        }
        return (north, east, down)
    }

    // MARK: Constants

    /// The geomagnetic reference radius a, in kilometers.
    private static let referenceRadiusKilometers = 6371.2
    /// Valid heights above the ellipsoid, in meters (MIL-PRF-89500B).
    private static let minimumAltitudeMeters = -1_000.0
    private static let maximumAltitudeMeters = 850_000.0
    /// How long a WMM epoch is valid, in years.
    private static let validityYears = 5.0

    private static let secondsPerDay = 86_400.0
    /// Dates farther than this from 1970, about 316,000 years, are not converted to a decimal year.
    private static let maximumConvertibleSeconds = 1e13
    /// Days from 0001-01-01 to 1970-01-01 in the proleptic Gregorian calendar.
    private static let daysFromYearOneToUnixEpoch = 719_162

    // MARK: Calendar helpers

    /// Seconds since 1970-01-01T00:00:00Z of the first instant of `year` (proleptic Gregorian).
    private static func unixSeconds(atStartOfYear year: Int) -> Double {
        let elapsedYears = year - 1
        let days = 365 * elapsedYears
            + floorDivide(elapsedYears, 4) - floorDivide(elapsedYears, 100) + floorDivide(elapsedYears, 400)
            - daysFromYearOneToUnixEpoch
        return Double(days) * secondsPerDay
    }

    /// Integer division of `dividend` by a positive `divisor`, rounding toward negative infinity.
    private static func floorDivide(_ dividend: Int, _ divisor: Int) -> Int {
        let quotient = dividend / divisor
        return dividend % divisor < 0 ? quotient - 1 : quotient
    }
}

// MARK: - Supporting types

extension WorldMagneticModel {
    /// One line of a WMM coefficient file: the Gauss coefficients of one degree and order.
    struct CoefficientRow: Sendable, Hashable {
        /// Degree n, at least 1.
        let degree: Int
        /// Order m, from 0 through `degree`.
        let order: Int
        /// Cosine coefficient g at the model epoch, in nT.
        let g: Double
        /// Sine coefficient h at the model epoch, in nT. Zero for order 0.
        let h: Double
        /// Secular variation of `g`, in nT per year.
        let gDot: Double
        /// Secular variation of `h`, in nT per year. Zero for order 0.
        let hDot: Double
    }

    /// A point in geocentric spherical coordinates, derived from geodetic latitude and height.
    struct GeocentricPosition: Sendable {
        /// sin(phi') of the geocentric latitude.
        let sinLatitude: Double
        /// cos(phi') of the geocentric latitude.
        let cosLatitude: Double
        /// Distance from the Earth's center, in kilometers.
        let radiusKilometers: Double
        /// cos(phi' - phi), the rotation from the geocentric to the geodetic frame.
        let rotationCosine: Double
        /// sin(phi' - phi), the rotation from the geocentric to the geodetic frame.
        let rotationSine: Double

        /// Converts a point on or above the WGS 84 ellipsoid (equations 7 and 8).
        ///
        /// - Parameters:
        ///   - geodeticLatitudeDegrees: Geodetic latitude phi in degrees.
        ///   - heightKilometers: Height above the ellipsoid in kilometers.
        init(geodeticLatitudeDegrees: Double, heightKilometers: Double) {
            let latitude = geodeticLatitudeDegrees * Double.pi / 180
            let sinGeodetic = sin(latitude)
            let cosGeodetic = cos(latitude)
            let primeVerticalRadius = Self.semiMajorAxisKilometers
                / (1 - Self.eccentricitySquared * sinGeodetic * sinGeodetic).squareRoot()
            let distanceFromAxis = (primeVerticalRadius + heightKilometers) * cosGeodetic
            let heightAboveEquator = (primeVerticalRadius * (1 - Self.eccentricitySquared) + heightKilometers)
                * sinGeodetic

            radiusKilometers = hypot(distanceFromAxis, heightAboveEquator)
            sinLatitude = heightAboveEquator / radiusKilometers
            cosLatitude = distanceFromAxis / radiusKilometers
            rotationCosine = cosLatitude * cosGeodetic + sinLatitude * sinGeodetic
            rotationSine = sinLatitude * cosGeodetic - cosLatitude * sinGeodetic
        }

        /// WGS 84 semi-major axis A, in kilometers.
        private static let semiMajorAxisKilometers = 6378.137
        /// WGS 84 flattening f, from the defining reciprocal 1/f = 298.257223563.
        private static let flattening = 1 / 298.257223563
        /// WGS 84 first eccentricity squared, e^2 = f (2 - f).
        private static let eccentricitySquared = flattening * (2 - flattening)
    }

    /// Schmidt semi-normalized associated Legendre functions of sin(phi'), for every degree and order
    /// up to a maximum, with the two companions the field equations need.
    ///
    /// The functions follow equations (5) and (6) of the technical report: without the Condon-Shortley
    /// phase and with the factor sqrt(2 (n-m)! / (n+m)!) for orders above zero. All three tables come
    /// from three-term recurrences that contain no division by cos(phi'), so they are exact at the
    /// poles.
    struct LegendreTable {
        /// P(n, m)(sin phi').
        private(set) var value: [Double]
        /// The derivative of P(n, m)(sin phi') with respect to the latitude phi', the quantity of
        /// equation (16).
        private(set) var latitudeDerivative: [Double]
        /// P(n, m)(sin phi') / cos(phi') for orders m >= 1; zero for m = 0, which no formula needs.
        /// It tends to a finite limit at the poles.
        private(set) var overCosine: [Double]

        /// The number of (degree, order) pairs, including degree 0, up to `maximumDegree`.
        static func entryCount(maximumDegree: Int) -> Int {
            (maximumDegree + 1) * (maximumDegree + 2) / 2
        }

        /// The position of the pair (`degree`, `order`) in the flat arrays.
        static func index(degree: Int, order: Int) -> Int {
            degree * (degree + 1) / 2 + order
        }

        /// Computes the table for a geocentric latitude given by its sine and cosine.
        ///
        /// - Parameters:
        ///   - maximumDegree: The highest degree needed, at least 1.
        ///   - sinLatitude: sin(phi').
        ///   - cosLatitude: cos(phi'), non-negative.
        init(maximumDegree: Int, sinLatitude s: Double, cosLatitude c: Double) {
            let count = Self.entryCount(maximumDegree: maximumDegree)
            var p = [Double](repeating: 0, count: count)
            var dp = p
            var q = p
            p[0] = 1

            for degree in 1...maximumDegree {
                let n = Double(degree)

                // Sectoral functions (m = n) from the one of the previous degree.
                let sectoral = Self.index(degree: degree, order: degree)
                let previousSectoral = Self.index(degree: degree - 1, order: degree - 1)
                if degree == 1 {
                    p[sectoral] = c
                    dp[sectoral] = -s
                    q[sectoral] = 1
                } else {
                    let factor = ((2 * n - 1) / (2 * n)).squareRoot()
                    p[sectoral] = factor * c * p[previousSectoral]
                    dp[sectoral] = factor * (c * dp[previousSectoral] - s * p[previousSectoral])
                    q[sectoral] = factor * p[previousSectoral]
                }

                // All other orders (m < n) from the two previous degrees of the same order.
                for order in 0..<degree {
                    let m = Double(order)
                    let inverseRoot = 1 / (n * n - m * m).squareRoot()
                    let a = (2 * n - 1) * inverseRoot
                    let one = Self.index(degree: degree - 1, order: order)
                    var pValue = a * s * p[one]
                    var dpValue = a * (s * dp[one] + c * p[one])
                    var qValue = a * s * q[one]
                    if order <= degree - 2 {
                        let b = ((n - 1) * (n - 1) - m * m).squareRoot() * inverseRoot
                        let two = Self.index(degree: degree - 2, order: order)
                        pValue -= b * p[two]
                        dpValue -= b * dp[two]
                        qValue -= b * q[two]
                    }
                    let index = Self.index(degree: degree, order: order)
                    p[index] = pValue
                    dp[index] = dpValue
                    q[index] = qValue
                }
            }
            value = p
            latitudeDerivative = dp
            overCosine = q
        }
    }
}
