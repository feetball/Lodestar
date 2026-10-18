import Foundation

/// Why SGP4 could not produce a state. Codes 1 to 6 are those of the reference implementation; the last two are
/// added by this port.
public enum Sgp4Error: Int, Hashable, Sendable, CaseIterable, Error {
    /// The mean eccentricity reached 1 (or fell below -0.001): the orbit is not elliptic any more.
    case meanEccentricityInvalid = 1
    /// The mean motion is not positive.
    case meanMotionNotPositive = 2
    /// The eccentricity with the lunar-solar periodic terms is outside 0 ... 1.
    case perturbedEccentricityInvalid = 3
    /// The semi-latus rectum is negative.
    case semiLatusRectumNegative = 4
    /// The satellite has decayed: its radius is below one Earth radius.
    case decayed = 6
    /// The computed state is not finite, or the requested time is not a finite number.
    case nonFiniteState = 7
    /// The requested time is more than `Sgp4Propagator.maximumMinutesFromEpoch` from the epoch.
    case timeOutOfRange = 8

    /// The reference's error code (same as `rawValue`).
    public var code: Int { rawValue }
}

/// A satellite's position and velocity in the TEME frame (true equator, mean equinox of date), the frame SGP4
/// works in.
public struct TemeState: Hashable, Sendable {
    /// Position in kilometres.
    public let position: Vector3
    /// Velocity in kilometres per second.
    public let velocity: Vector3

    public init(position: Vector3, velocity: Vector3) {
        self.position = position
        self.velocity = velocity
    }
}

/// The outcome of one SGP4 evaluation: a state or the reason there is none.
public enum Sgp4Result: Hashable, Sendable {
    /// A successful evaluation.
    case success(TemeState)
    /// A failed evaluation.
    case failure(Sgp4Error)

    /// The state, or `nil` for a failure.
    public var state: TemeState? {
        if case .success(let state) = self { return state }
        return nil
    }

    /// The error, or `nil` for a success.
    public var error: Sgp4Error? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

/// Everything `sgp4init` computes and `sgp4` needs. Written only while the propagator is built.
struct Sgp4Record {
    // Gravity constants (WGS-72)
    var radiusEarthKm = 0.0
    var xke = 0.0
    var tumin = 0.0
    var j2 = 0.0
    var j3 = 0.0
    var j4 = 0.0
    var j3oj2 = 0.0

    // Elements (radians, radians per minute)
    var bstar = 0.0
    var inclo = 0.0
    var nodeo = 0.0
    var ecco = 0.0
    var argpo = 0.0
    var mo = 0.0
    var noKozai = 0.0
    var noUnkozai = 0.0

    // Near earth
    var isimp = 0
    var isDeepSpace = false
    var aycof = 0.0
    var con41 = 0.0
    var cc1 = 0.0
    var cc4 = 0.0
    var cc5 = 0.0
    var d2 = 0.0
    var d3 = 0.0
    var d4 = 0.0
    var delmo = 0.0
    var eta = 0.0
    var argpdot = 0.0
    var omgcof = 0.0
    var sinmao = 0.0
    var t2cof = 0.0
    var t3cof = 0.0
    var t4cof = 0.0
    var t5cof = 0.0
    var x1mth2 = 0.0
    var x7thm1 = 0.0
    var mdot = 0.0
    var nodedot = 0.0
    var xlcof = 0.0
    var xmcof = 0.0
    var nodecf = 0.0

    // Deep space
    var irez = 0
    var d2201 = 0.0
    var d2211 = 0.0
    var d3210 = 0.0
    var d3222 = 0.0
    var d4410 = 0.0
    var d4422 = 0.0
    var d5220 = 0.0
    var d5232 = 0.0
    var d5421 = 0.0
    var d5433 = 0.0
    var dedt = 0.0
    var del1 = 0.0
    var del2 = 0.0
    var del3 = 0.0
    var didt = 0.0
    var dmdt = 0.0
    var dnodt = 0.0
    var domdt = 0.0
    var e3 = 0.0
    var ee2 = 0.0
    var peo = 0.0
    var pgho = 0.0
    var pho = 0.0
    var pinco = 0.0
    var plo = 0.0
    var se2 = 0.0
    var se3 = 0.0
    var sgh2 = 0.0
    var sgh3 = 0.0
    var sgh4 = 0.0
    var sh2 = 0.0
    var sh3 = 0.0
    var si2 = 0.0
    var si3 = 0.0
    var sl2 = 0.0
    var sl3 = 0.0
    var sl4 = 0.0
    var gsto = 0.0
    var xfact = 0.0
    var xgh2 = 0.0
    var xgh3 = 0.0
    var xgh4 = 0.0
    var xh2 = 0.0
    var xh3 = 0.0
    var xi2 = 0.0
    var xi3 = 0.0
    var xl2 = 0.0
    var xl3 = 0.0
    var xl4 = 0.0
    var xlamo = 0.0
    var zmol = 0.0
    var zmos = 0.0

    // Derived
    var semiMajorAxis = 0.0
}

/// The SGP4/SDP4 analytic orbit propagator for NORAD mean elements (TLE and GP data), a port of the public-domain
/// reference implementation by Vallado, Crawford, Hujsak and Kelso ("Revisiting Spacetrack Report #3", AIAA
/// 2006-6753; the C++ code of 2020-07-13, which the Python `sgp4` package also follows).
///
/// - **Near-earth** (period below 225 minutes) and **deep-space** (SDP4: lunar-solar terms and the half-day and
///   one-day resonances) orbits are both handled.
/// - Constants are WGS-72 (as the elements were fitted with) and the operation mode is the reference's `'i'`
///   (improved); the older AFSPC mode is not offered.
/// - The reference stores the deep-space integrator's progress in the element record and resumes from it. This
///   port restarts the integration at the epoch on every call (at most `|t| / 720` steps), which the reference does
///   itself whenever time reverses, and which gives the same numbers; in return a propagator is immutable and safe
///   to use from several threads.
///
/// Cost: construction about 2.5 microseconds (6 for deep-space orbits); `propagate` about 0.6 microseconds near
/// Earth, 3 microseconds in deep space.
///
/// Accuracy: SGP4 reproduces the mean-element theory, not the real orbit. Expect an along-track error of a few
/// kilometres at the epoch that grows by 1 to 3 km per day for low orbits, faster when the object is manoeuvring
/// or the atmosphere is disturbed (see `OrbitalElements.ageDays`).
public final class Sgp4Propagator: Sendable {
    /// The largest |time from the epoch| accepted, in minutes (about 19 years).
    public static let maximumMinutesFromEpoch = 1.0e7

    /// The element set this propagator was built from.
    public let elements: OrbitalElements
    private let record: Sgp4Record

    /// `true` for orbits with a period of 225 minutes or more, which use the SDP4 lunar-solar and resonance terms.
    public var isDeepSpace: Bool { record.isDeepSpace }

    /// The semi-major axis of the mean orbit in Earth radii (the reference's `a`, after removing the Kozai mean).
    public var semiMajorAxisEarthRadii: Double { record.semiMajorAxis }

    /// The perigee altitude of the mean orbit above the WGS-72 equatorial radius, in kilometres.
    public var perigeeAltitudeKilometers: Double {
        (record.semiMajorAxis * (1.0 - record.ecco) - 1.0) * record.radiusEarthKm
    }

    /// The apogee altitude of the mean orbit above the WGS-72 equatorial radius, in kilometres.
    public var apogeeAltitudeKilometers: Double {
        (record.semiMajorAxis * (1.0 + record.ecco) - 1.0) * record.radiusEarthKm
    }

    /// An upper bound of the satellite's speed relative to the rotating Earth in kilometres per second: the
    /// perigee speed of the mean orbit with 5 % margin plus the Earth's rotation at apogee. Search routines use it
    /// to bound how far the satellite can move in a given time.
    let maximumSpeedKilometersPerSecond: Double

    /// The epoch of the elements as seconds since the Foundation reference date (2001-01-01T00:00:00Z).
    let epochReferenceSeconds: Double

    public init(elements: OrbitalElements) {
        self.elements = elements
        let record = Sgp4Initializer.initialize(elements)
        self.record = record
        let axis = record.semiMajorAxis * record.radiusEarthKm
        let perigeeSpeed = (398600.8 * (1.0 + record.ecco) / (axis * (1.0 - record.ecco))).squareRoot()
        self.maximumSpeedKilometersPerSecond = 1.05 * perigeeSpeed + SatelliteFrames.earthRotationRate * axis * (1.0 + record.ecco)
        self.epochReferenceSeconds = elements.epoch.timeIntervalSinceReferenceDate
    }

    /// The state `minutesSinceEpoch` minutes after the epoch of the elements (negative: before it).
    ///
    /// - Returns: the TEME state, or the reason SGP4 failed (a decayed satellite, an impossible orbit, a time more
    ///   than `maximumMinutesFromEpoch` away).
    public func propagate(minutesSinceEpoch: Double) -> Sgp4Result {
        var out = [Double](repeating: 0, count: 6)
        let code = propagateRaw(minutesSinceEpoch, into: &out)
        if code != 0 { return .failure(Sgp4Error(rawValue: code) ?? .nonFiniteState) }
        return .success(TemeState(
            position: Vector3(out[0], out[1], out[2]),
            velocity: Vector3(out[3], out[4], out[5])
        ))
    }

    /// The state at `date`.
    public func state(at date: Date) -> Sgp4Result { propagate(minutesSinceEpoch: minutesSince(date)) }

    /// Minutes from the epoch of the elements to `date`.
    public func minutesSince(_ date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate - epochReferenceSeconds) / 60.0
    }

    /// Allocation-free `propagate`: writes position (km) to `out[0...2]` and velocity (km/s) to `out[3...5]` and
    /// returns 0, or an `Sgp4Error` code (nothing is written then). The port of the reference's `sgp4`.
    func propagateRaw(_ minutesSinceEpoch: Double, into out: inout [Double]) -> Int {
        if !minutesSinceEpoch.isFinite { return Sgp4Error.nonFiniteState.rawValue }
        if abs(minutesSinceEpoch) > Self.maximumMinutesFromEpoch { return Sgp4Error.timeOutOfRange.rawValue }
        let code = Sgp4Core.propagate(record, minutesSinceEpoch, &out)
        if code != 0 { return code }
        for index in 0..<6 where !out[index].isFinite { return Sgp4Error.nonFiniteState.rawValue }
        return 0
    }
}

/// Greenwich sidereal time and other time helpers of the SGP4 reference.
enum Sgp4Time {
    /// Greenwich sidereal time from the reference's `gstime_SGP4`, in radians [0, 2π), for a Julian Date in UT1.
    static func greenwichSiderealTime(_ julianDateUt1: Double) -> Double {
        let twoPi = 2.0 * Double.pi
        let deg2rad = Double.pi / 180.0
        let tut1 = (julianDateUt1 - 2451545.0) / 36525.0
        var temp = -6.2e-6 * tut1 * tut1 * tut1 + 0.093104 * tut1 * tut1 +
            (876600.0 * 3600 + 8640184.812866) * tut1 + 67310.54841
        temp = (temp * deg2rad / 240.0).truncatingRemainder(dividingBy: twoPi)
        if temp < 0.0 { temp += twoPi }
        return temp
    }
}

/// The reference's `sgp4init`: turns an element set into the propagation constants.
enum Sgp4Initializer {
    static func initialize(_ elements: OrbitalElements) -> Sgp4Record {
        var satrec = Sgp4Record()
        let deg2rad = Double.pi / 180.0
        let xpdotp = 1440.0 / (2.0 * Double.pi)

        // getgravconst(wgs72)
        satrec.radiusEarthKm = 6378.135
        let mus = 398600.8
        satrec.xke = 60.0 / sqrt(satrec.radiusEarthKm * satrec.radiusEarthKm * satrec.radiusEarthKm / mus)
        satrec.tumin = 1.0 / satrec.xke
        satrec.j2 = 0.001082616
        satrec.j3 = -0.00000253881
        satrec.j4 = -0.00000165597
        satrec.j3oj2 = satrec.j3 / satrec.j2

        // twoline2rv's unit conversions
        satrec.bstar = elements.bstar
        satrec.noKozai = elements.meanMotion / xpdotp
        satrec.inclo = elements.inclination * deg2rad
        satrec.nodeo = elements.rightAscensionOfAscendingNode * deg2rad
        satrec.argpo = elements.argumentOfPericenter * deg2rad
        satrec.mo = elements.meanAnomaly * deg2rad
        satrec.ecco = elements.eccentricity
        let epoch = elements.sgp4EpochDays

        let ss = 78.0 / satrec.radiusEarthKm + 1.0
        let qzms2ttemp = (120.0 - 78.0) / satrec.radiusEarthKm
        let qzms2t = qzms2ttemp * qzms2ttemp * qzms2ttemp * qzms2ttemp
        let x2o3 = 2.0 / 3.0
        let temp4 = 1.5e-12

        // initl
        let eccsq = satrec.ecco * satrec.ecco
        let omeosq = 1.0 - eccsq
        let rteosq = sqrt(omeosq)
        let cosio = cos(satrec.inclo)
        let cosio2 = cosio * cosio

        // un-kozai the mean motion
        let ak = pow(satrec.xke / satrec.noKozai, x2o3)
        let d1 = 0.75 * satrec.j2 * (3.0 * cosio2 - 1.0) / (rteosq * omeosq)
        var del = d1 / (ak * ak)
        let adel = ak * (1.0 - del * del - del * (1.0 / 3.0 + 134.0 * del * del / 81.0))
        del = d1 / (adel * adel)
        satrec.noUnkozai = satrec.noKozai / (1.0 + del)

        let ao = pow(satrec.xke / satrec.noUnkozai, x2o3)
        let sinio = sin(satrec.inclo)
        let po = ao * omeosq
        let con42 = 1.0 - 5.0 * cosio2
        satrec.con41 = -con42 - cosio2 - cosio2
        let posq = po * po
        let rp = ao * (1.0 - satrec.ecco)
        satrec.gsto = Sgp4Time.greenwichSiderealTime(epoch + OrbitalElements.sgp4EpochOffset)

        satrec.semiMajorAxis = pow(satrec.noUnkozai * satrec.tumin, -2.0 / 3.0)

        if omeosq >= 0.0 || satrec.noUnkozai >= 0.0 {
            satrec.isimp = 0
            if rp < (220.0 / satrec.radiusEarthKm + 1.0) { satrec.isimp = 1 }
            var sfour = ss
            var qzms24 = qzms2t
            let perige = (rp - 1.0) * satrec.radiusEarthKm

            // for perigees below 156 km, s and qoms2t are altered
            if perige < 156.0 {
                sfour = perige - 78.0
                if perige < 98.0 { sfour = 20.0 }
                let qzms24temp = (120.0 - sfour) / satrec.radiusEarthKm
                qzms24 = qzms24temp * qzms24temp * qzms24temp * qzms24temp
                sfour = sfour / satrec.radiusEarthKm + 1.0
            }
            let pinvsq = 1.0 / posq

            let tsi = 1.0 / (ao - sfour)
            satrec.eta = ao * satrec.ecco * tsi
            let etasq = satrec.eta * satrec.eta
            let eeta = satrec.ecco * satrec.eta
            let psisq = abs(1.0 - etasq)
            let coef = qzms24 * pow(tsi, 4.0)
            let coef1 = coef / pow(psisq, 3.5)
            let cc2 = coef1 * satrec.noUnkozai * (
                ao * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq)) +
                    0.375 * satrec.j2 * tsi / psisq * satrec.con41 * (8.0 + 3.0 * etasq * (8.0 + etasq))
                )
            satrec.cc1 = satrec.bstar * cc2
            var cc3 = 0.0
            if satrec.ecco > 1.0e-4 {
                cc3 = -2.0 * coef * tsi * satrec.j3oj2 * satrec.noUnkozai * sinio / satrec.ecco
            }
            satrec.x1mth2 = 1.0 - cosio2
            satrec.cc4 = 2.0 * satrec.noUnkozai * coef1 * ao * omeosq * (
                satrec.eta * (2.0 + 0.5 * etasq) + satrec.ecco * (0.5 + 2.0 * etasq) -
                    satrec.j2 * tsi / (ao * psisq) * (
                        -3.0 * satrec.con41 * (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta)) +
                            0.75 * satrec.x1mth2 * (2.0 * etasq - eeta * (1.0 + etasq)) * cos(2.0 * satrec.argpo)
                        )
                )
            satrec.cc5 = 2.0 * coef1 * ao * omeosq * (1.0 + 2.75 * (etasq + eeta) + eeta * etasq)
            let cosio4 = cosio2 * cosio2
            let temp1 = 1.5 * satrec.j2 * pinvsq * satrec.noUnkozai
            let temp2 = 0.5 * temp1 * satrec.j2 * pinvsq
            let temp3 = -0.46875 * satrec.j4 * pinvsq * pinvsq * satrec.noUnkozai
            satrec.mdot = satrec.noUnkozai + 0.5 * temp1 * rteosq * satrec.con41 +
                0.0625 * temp2 * rteosq * (13.0 - 78.0 * cosio2 + 137.0 * cosio4)
            satrec.argpdot = -0.5 * temp1 * con42 + 0.0625 * temp2 * (7.0 - 114.0 * cosio2 + 395.0 * cosio4) +
                temp3 * (3.0 - 36.0 * cosio2 + 49.0 * cosio4)
            let xhdot1 = -temp1 * cosio
            satrec.nodedot = xhdot1 + (0.5 * temp2 * (4.0 - 19.0 * cosio2) + 2.0 * temp3 * (3.0 - 7.0 * cosio2)) * cosio
            let xpidot = satrec.argpdot + satrec.nodedot
            satrec.omgcof = satrec.bstar * cc3 * cos(satrec.argpo)
            satrec.xmcof = 0.0
            if satrec.ecco > 1.0e-4 { satrec.xmcof = -x2o3 * coef * satrec.bstar / eeta }
            satrec.nodecf = 3.5 * omeosq * xhdot1 * satrec.cc1
            satrec.t2cof = 1.5 * satrec.cc1
            // sgp4fix for divide by zero with xinco = 180 deg
            if abs(cosio + 1.0) > 1.5e-12 {
                satrec.xlcof = -0.25 * satrec.j3oj2 * sinio * (3.0 + 5.0 * cosio) / (1.0 + cosio)
            } else {
                satrec.xlcof = -0.25 * satrec.j3oj2 * sinio * (3.0 + 5.0 * cosio) / temp4
            }
            satrec.aycof = -0.5 * satrec.j3oj2 * sinio
            let delmotemp = 1.0 + satrec.eta * cos(satrec.mo)
            satrec.delmo = delmotemp * delmotemp * delmotemp
            satrec.sinmao = sin(satrec.mo)
            satrec.x7thm1 = 7.0 * cosio2 - 1.0

            // deep space initialization
            if (2 * Double.pi / satrec.noUnkozai) >= 225.0 {
                satrec.isDeepSpace = true
                satrec.isimp = 1
                let tc = 0.0

                var common = Sgp4DeepSpaceCommon()
                common.compute(
                    epoch: epoch, ep: satrec.ecco, argpp: satrec.argpo, tc: tc, inclp: satrec.inclo, nodep: satrec.nodeo,
                    np: satrec.noUnkozai
                )
                satrec.e3 = common.e3
                satrec.ee2 = common.ee2
                satrec.peo = common.peo
                satrec.pgho = common.pgho
                satrec.pho = common.pho
                satrec.pinco = common.pinco
                satrec.plo = common.plo
                satrec.se2 = common.se2
                satrec.se3 = common.se3
                satrec.sgh2 = common.sgh2
                satrec.sgh3 = common.sgh3
                satrec.sgh4 = common.sgh4
                satrec.sh2 = common.sh2
                satrec.sh3 = common.sh3
                satrec.si2 = common.si2
                satrec.si3 = common.si3
                satrec.sl2 = common.sl2
                satrec.sl3 = common.sl3
                satrec.sl4 = common.sl4
                satrec.xgh2 = common.xgh2
                satrec.xgh3 = common.xgh3
                satrec.xgh4 = common.xgh4
                satrec.xh2 = common.xh2
                satrec.xh3 = common.xh3
                satrec.xi2 = common.xi2
                satrec.xi3 = common.xi3
                satrec.xl2 = common.xl2
                satrec.xl3 = common.xl3
                satrec.xl4 = common.xl4
                satrec.zmol = common.zmol
                satrec.zmos = common.zmos
                // The reference calls dpper here with init = 'y', which leaves every value unchanged.

                var resonance = Sgp4DeepSpaceResonance()
                resonance.compute(
                    xke: satrec.xke,
                    common: common,
                    argpo: satrec.argpo,
                    t: 0.0,
                    tc: tc,
                    gsto: satrec.gsto,
                    mo: satrec.mo,
                    mdot: satrec.mdot,
                    no: satrec.noUnkozai,
                    nodeo: satrec.nodeo,
                    nodedot: satrec.nodedot,
                    xpidot: xpidot,
                    ecco: satrec.ecco,
                    eccsq: eccsq,
                    inclo: satrec.inclo
                )
                satrec.irez = resonance.irez
                satrec.d2201 = resonance.d2201
                satrec.d2211 = resonance.d2211
                satrec.d3210 = resonance.d3210
                satrec.d3222 = resonance.d3222
                satrec.d4410 = resonance.d4410
                satrec.d4422 = resonance.d4422
                satrec.d5220 = resonance.d5220
                satrec.d5232 = resonance.d5232
                satrec.d5421 = resonance.d5421
                satrec.d5433 = resonance.d5433
                satrec.dedt = resonance.dedt
                satrec.didt = resonance.didt
                satrec.dmdt = resonance.dmdt
                satrec.dnodt = resonance.dnodt
                satrec.domdt = resonance.domdt
                satrec.del1 = resonance.del1
                satrec.del2 = resonance.del2
                satrec.del3 = resonance.del3
                satrec.xfact = resonance.xfact
                satrec.xlamo = resonance.xlamo
            }

            // set variables if not deep space
            if satrec.isimp != 1 {
                let cc1sq = satrec.cc1 * satrec.cc1
                satrec.d2 = 4.0 * ao * tsi * cc1sq
                let temp = satrec.d2 * tsi * satrec.cc1 / 3.0
                satrec.d3 = (17.0 * ao + sfour) * temp
                satrec.d4 = 0.5 * temp * ao * tsi * (221.0 * ao + 31.0 * sfour) * satrec.cc1
                satrec.t3cof = satrec.d2 + 2.0 * cc1sq
                satrec.t4cof = 0.25 * (3.0 * satrec.d3 + satrec.cc1 * (12.0 * satrec.d2 + 10.0 * cc1sq))
                satrec.t5cof = 0.2 * (
                    3.0 * satrec.d4 + 12.0 * satrec.cc1 * satrec.d3 + 6.0 * satrec.d2 * satrec.d2 +
                        15.0 * cc1sq * (2.0 * satrec.d2 + cc1sq)
                    )
            }
        }
        return satrec
    }
}

/// The reference's `sgp4`: propagation of an initialized record.
enum Sgp4Core {
    static func propagate(_ satrec: Sgp4Record, _ tsince: Double, _ out: inout [Double]) -> Int {
        let twopi = 2.0 * Double.pi
        let x2o3 = 2.0 / 3.0
        let temp4 = 1.5e-12
        let vkmpersec = satrec.radiusEarthKm * satrec.xke / 60.0

        // The values the reference recomputes for deep-space orbits are local here.
        var aycof = satrec.aycof
        var xlcof = satrec.xlcof
        var con41 = satrec.con41
        var x1mth2 = satrec.x1mth2
        var x7thm1 = satrec.x7thm1

        let t = tsince

        // update for secular gravity and atmospheric drag
        let xmdf = satrec.mo + satrec.mdot * t
        let argpdf = satrec.argpo + satrec.argpdot * t
        let nodedf = satrec.nodeo + satrec.nodedot * t
        var argpm = argpdf
        var mm = xmdf
        let t2 = t * t
        var nodem = nodedf + satrec.nodecf * t2
        var tempa = 1.0 - satrec.cc1 * t
        var tempe = satrec.bstar * satrec.cc4 * t
        var templ = satrec.t2cof * t2

        if satrec.isimp != 1 {
            let delomg = satrec.omgcof * t
            let delmtemp = 1.0 + satrec.eta * cos(xmdf)
            let delm = satrec.xmcof * (delmtemp * delmtemp * delmtemp - satrec.delmo)
            let temp = delomg + delm
            mm = xmdf + temp
            argpm = argpdf - temp
            let t3 = t2 * t
            let t4 = t3 * t
            tempa = tempa - satrec.d2 * t2 - satrec.d3 * t3 - satrec.d4 * t4
            tempe = tempe + satrec.bstar * satrec.cc5 * (sin(mm) - satrec.sinmao)
            templ = templ + satrec.t3cof * t3 + t4 * (satrec.t4cof + t * satrec.t5cof)
        }

        var nm = satrec.noUnkozai
        var em = satrec.ecco
        var inclm = satrec.inclo
        if satrec.isDeepSpace {
            let secular = Sgp4DeepSpace.secular(
                record: satrec, t: t, emIn: em, argpmIn: argpm, inclmIn: inclm, mmIn: mm, nodemIn: nodem, nmIn: nm
            )
            em = secular.em
            argpm = secular.argpm
            inclm = secular.inclm
            mm = secular.mm
            nodem = secular.nodem
            nm = secular.nm
        }

        if nm <= 0.0 { return 2 }
        let am = pow(satrec.xke / nm, x2o3) * tempa * tempa
        nm = satrec.xke / pow(am, 1.5)
        em = em - tempe

        // fix tolerance for error recognition
        if em >= 1.0 || em < -0.001 { return 1 }
        // fix tolerance to avoid a divide by zero
        if em < 1.0e-6 { em = 1.0e-6 }
        mm = mm + satrec.noUnkozai * templ
        var xlm = mm + argpm + nodem

        nodem = nodem.truncatingRemainder(dividingBy: twopi)
        argpm = argpm.truncatingRemainder(dividingBy: twopi)
        xlm = xlm.truncatingRemainder(dividingBy: twopi)
        mm = (xlm - argpm - nodem).truncatingRemainder(dividingBy: twopi)

        // compute extra mean quantities
        let sinim = sin(inclm)
        let cosim = cos(inclm)

        // add lunar-solar periodics
        var ep = em
        var xincp = inclm
        var argpp = argpm
        var nodep = nodem
        var mp = mm
        var sinip = sinim
        var cosip = cosim
        if satrec.isDeepSpace {
            let perturbed = Sgp4DeepSpace.periodics(
                record: satrec, t: t, epIn: ep, inclpIn: xincp, nodepIn: nodep, argppIn: argpp, mpIn: mp
            )
            ep = perturbed.ep
            xincp = perturbed.inclp
            nodep = perturbed.nodep
            argpp = perturbed.argpp
            mp = perturbed.mp
            if xincp < 0.0 {
                xincp = -xincp
                nodep = nodep + Double.pi
                argpp = argpp - Double.pi
            }
            if ep < 0.0 || ep > 1.0 { return 3 }
        }

        // long period periodics
        if satrec.isDeepSpace {
            sinip = sin(xincp)
            cosip = cos(xincp)
            aycof = -0.5 * satrec.j3oj2 * sinip
            // sgp4fix for divide by zero for xincp = 180 deg
            if abs(cosip + 1.0) > 1.5e-12 {
                xlcof = -0.25 * satrec.j3oj2 * sinip * (3.0 + 5.0 * cosip) / (1.0 + cosip)
            } else {
                xlcof = -0.25 * satrec.j3oj2 * sinip * (3.0 + 5.0 * cosip) / temp4
            }
        }
        let axnl = ep * cos(argpp)
        var temp = 1.0 / (am * (1.0 - ep * ep))
        let aynl = ep * sin(argpp) + temp * aycof
        let xl = mp + argpp + nodep + temp * xlcof * axnl

        // solve kepler's equation
        let u = (xl - nodep).truncatingRemainder(dividingBy: twopi)
        var eo1 = u
        var tem5 = 9999.9
        var ktr = 1
        var sineo1 = 0.0
        var coseo1 = 0.0
        while abs(tem5) >= 1.0e-12 && ktr <= 10 {
            sineo1 = sin(eo1)
            coseo1 = cos(eo1)
            tem5 = 1.0 - coseo1 * axnl - sineo1 * aynl
            tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
            if abs(tem5) >= 0.95 { tem5 = tem5 > 0.0 ? 0.95 : -0.95 }
            eo1 = eo1 + tem5
            ktr = ktr + 1
        }

        // short period preliminary quantities
        let ecose = axnl * coseo1 + aynl * sineo1
        let esine = axnl * sineo1 - aynl * coseo1
        let el2 = axnl * axnl + aynl * aynl
        let pl = am * (1.0 - el2)
        if pl < 0.0 { return 4 }

        let rl = am * (1.0 - ecose)
        let rdotl = sqrt(am) * esine / rl
        let rvdotl = sqrt(pl) / rl
        let betal = sqrt(1.0 - el2)
        temp = esine / (1.0 + betal)
        let sinu = am / rl * (sineo1 - aynl - axnl * temp)
        let cosu = am / rl * (coseo1 - axnl + aynl * temp)
        var su = atan2(sinu, cosu)
        let sin2u = (cosu + cosu) * sinu
        let cos2u = 1.0 - 2.0 * sinu * sinu
        temp = 1.0 / pl
        let temp1 = 0.5 * satrec.j2 * temp
        let temp2 = temp1 * temp

        // update for short period periodics
        if satrec.isDeepSpace {
            let cosisq = cosip * cosip
            con41 = 3.0 * cosisq - 1.0
            x1mth2 = 1.0 - cosisq
            x7thm1 = 7.0 * cosisq - 1.0
        }
        let mrt = rl * (1.0 - 1.5 * temp2 * betal * con41) + 0.5 * temp1 * x1mth2 * cos2u
        su = su - 0.25 * temp2 * x7thm1 * sin2u
        let xnode = nodep + 1.5 * temp2 * cosip * sin2u
        let xinc = xincp + 1.5 * temp2 * cosip * sinip * cos2u
        let mvt = rdotl - nm * temp1 * x1mth2 * sin2u / satrec.xke
        let rvdot = rvdotl + nm * temp1 * (x1mth2 * cos2u + 1.5 * con41) / satrec.xke

        // orientation vectors
        let sinsu = sin(su)
        let cossu = cos(su)
        let snod = sin(xnode)
        let cnod = cos(xnode)
        let sini = sin(xinc)
        let cosi = cos(xinc)
        let xmx = -snod * cosi
        let xmy = cnod * cosi
        let ux = xmx * sinsu + cnod * cossu
        let uy = xmy * sinsu + snod * cossu
        let uz = sini * sinsu
        let vx = xmx * cossu - cnod * sinsu
        let vy = xmy * cossu - snod * sinsu
        let vz = sini * cossu

        // sgp4fix for decaying satellites
        if mrt < 1.0 { return 6 }

        // position and velocity (in km and km/sec)
        out[0] = (mrt * ux) * satrec.radiusEarthKm
        out[1] = (mrt * uy) * satrec.radiusEarthKm
        out[2] = (mrt * uz) * satrec.radiusEarthKm
        out[3] = (mvt * ux + rvdot * vx) * vkmpersec
        out[4] = (mvt * uy + rvdot * vy) * vkmpersec
        out[5] = (mvt * uz + rvdot * vz) * vkmpersec
        return 0
    }
}
