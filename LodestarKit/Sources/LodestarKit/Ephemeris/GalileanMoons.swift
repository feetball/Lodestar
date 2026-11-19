import Foundation

/// One of Jupiter's four Galilean moons.
public enum GalileanMoon: String, CaseIterable, Sendable, Hashable, Codable {
    /// Io (I), 1.77 days around Jupiter, 5.9 Jupiter radii out.
    case io
    /// Europa (II), 3.55 days, 9.4 Jupiter radii.
    case europa
    /// Ganymede (III), 7.15 days, 15.0 Jupiter radii.
    case ganymede
    /// Callisto (IV), 16.69 days, 26.4 Jupiter radii.
    case callisto

    /// The English name, e.g. "Io".
    public var displayName: String {
        switch self {
        case .io: "Io"
        case .europa: "Europa"
        case .ganymede: "Ganymede"
        case .callisto: "Callisto"
        }
    }

    /// The one-letter initial used in diagrams: "I", "E", "G" or "C".
    public var initial: String {
        switch self {
        case .io: "I"
        case .europa: "E"
        case .ganymede: "G"
        case .callisto: "C"
        }
    }
}

/// What a Galilean moon does relative to Jupiter's disc.
public enum GalileanPhenomenon: String, CaseIterable, Sendable, Hashable, Codable {
    /// The moon crosses in front of Jupiter's disc.
    case transit
    /// The moon's shadow falls on the visible disc of Jupiter.
    case shadowTransit
    /// The moon passes behind Jupiter's disc.
    case occultation
    /// The moon is inside Jupiter's shadow.
    case eclipse
}

/// Which end of a phenomenon an event marks.
public enum GalileanEdge: String, CaseIterable, Sendable, Hashable, Codable {
    /// The phenomenon begins.
    case start
    /// The phenomenon ends.
    case end
}

/// Where a moon's shadow falls on the visible disc, in the axes of `GalileanMoonPosition`.
public struct GalileanShadow: Sendable, Hashable {
    /// Offset from the disc centre along Jupiter's equator in Jupiter equatorial radii, positive west.
    public let x: Double
    /// Offset along Jupiter's rotation axis, positive north.
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A Galilean moon as seen from the Earth.
///
/// The axes follow Jupiter's rotation, as in a drawing of the planet with its equator horizontal: `x` runs along the
/// equator, positive to the west (the side of the sky where the Sun sets; for an inverting telescope it is on the left
/// of a northern observer's view), `y` along the rotation axis, positive to the north, `z` towards the Earth. Jupiter's
/// disc is taken round with a radius of 1 (the 6 % flattening is ignored).
public struct GalileanMoonPosition: Sendable, Hashable {
    /// Which moon.
    public let moon: GalileanMoon
    /// Offset from Jupiter's centre in Jupiter equatorial radii, positive west.
    public let x: Double
    /// Offset along the rotation axis in Jupiter radii, positive north.
    public let y: Double
    /// Offset towards the Earth in Jupiter radii: positive when the moon is nearer to us than Jupiter.
    public let z: Double
    /// Where the centre of the moon's shadow falls on the part of the disc that faces the Earth, or `nil` when the
    /// shadow misses it or lands on the far side.
    public let shadow: GalileanShadow?
    /// `true` when the moon is inside Jupiter's shadow (a cylinder one radius wide).
    public let isEclipsed: Bool

    public init(moon: GalileanMoon, x: Double, y: Double, z: Double, shadow: GalileanShadow?, isEclipsed: Bool) {
        self.moon = moon
        self.x = x
        self.y = y
        self.z = z
        self.shadow = shadow
        self.isEclipsed = isEclipsed
    }

    /// `true` when the moon is in front of Jupiter's disc.
    public var isInTransit: Bool { z > 0 && x * x + y * y < 1 }

    /// `true` when the moon is hidden behind Jupiter's disc.
    public var isBehindDisc: Bool { z < 0 && x * x + y * y < 1 }
}

/// The four moons at one instant.
public struct GalileanMoonsState: Sendable, Hashable {
    /// Planetocentric declination of the Earth in degrees (the book's low-accuracy value).
    public let earthDeclination: Double
    /// Planetocentric declination of the Sun in degrees.
    public let sunDeclination: Double
    /// Io, Europa, Ganymede and Callisto, in that order.
    public let moons: [GalileanMoonPosition]

    public init(earthDeclination: Double, sunDeclination: Double, moons: [GalileanMoonPosition]) {
        self.earthDeclination = earthDeclination
        self.sunDeclination = sunDeclination
        self.moons = moons
    }
}

/// A start or an end of a moon phenomenon.
public struct GalileanMoonEvent: Sendable, Hashable {
    /// Which moon.
    public let moon: GalileanMoon
    /// What it does.
    public let phenomenon: GalileanPhenomenon
    /// Whether the phenomenon begins or ends.
    public let edge: GalileanEdge
    /// The instant, with the accuracy stated at `GalileanMoons.accuracyMinutes`.
    public let date: Date

    public init(moon: GalileanMoon, phenomenon: GalileanPhenomenon, edge: GalileanEdge, date: Date) {
        self.moon = moon
        self.phenomenon = phenomenon
        self.edge = edge
        self.date = date
    }

    /// A short English sentence, e.g. "Io's shadow enters the disc" or "Europa goes behind Jupiter".
    public var title: String {
        let name = moon.displayName
        let starts = edge == .start
        switch phenomenon {
        case .transit: return starts ? "\(name) enters the disc" : "\(name) leaves the disc"
        case .shadowTransit: return starts ? "\(name)'s shadow enters the disc" : "\(name)'s shadow leaves the disc"
        case .occultation: return starts ? "\(name) goes behind Jupiter" : "\(name) reappears from behind Jupiter"
        case .eclipse: return starts ? "\(name) enters Jupiter's shadow" : "\(name) leaves Jupiter's shadow"
        }
    }
}

/// The Galilean moons of Jupiter by the low-accuracy method of Jean Meeus, *Astronomical Algorithms*, 2nd ed.,
/// chapter 44: each moon moves on a circle in Jupiter's equatorial plane with periodic corrections, seen from the Earth
/// through the planet's declination. The same circles seen from the Sun give the shadows.
///
/// The positions are good to about 0.1 Jupiter radius, which is the `accuracyMinutes` of the event times: against JPL's
/// satellite ephemeris (Horizons, jup365) the 139 phenomena of three six-day windows between 2026 November and 2027
/// February came within 1.8 minutes rms and 6 minutes at the worst (Callisto), see the tests.
public enum GalileanMoons {
    /// About how far the event times can be off, in minutes: the moons' offsets are good to about 0.1 Jupiter radius.
    public static let accuracyMinutes = 5.0

    /// The longest interval, in days, that `events(from:to:)` searches; longer intervals are cut at this length.
    public static let maximumSpanDays = 30.0

    /// The sampling step of `events(from:to:)` in seconds.
    public static let sampleSeconds = 60.0

    /// The positions of the four moons at `julianDate` (its TT drives the theory).
    public static func positions(at julianDate: JulianDate) -> GalileanMoonsState {
        positions(tt: julianDate.tt)
    }

    private static func positions(tt: Double) -> GalileanMoonsState {
        let d = tt - JulianDate.j2000
        let v = AstroMath.radians(172.74 + 0.00111588 * d)
        let m = AstroMath.radians(357.529 + 0.9856003 * d)
        let sinV = sin(v)
        let n = AstroMath.radians(20.02 + 0.0830853 * d + 0.329 * sinV)
        let j = AstroMath.radians(66.115 + 0.9025179 * d - 0.329 * sinV)
        let a = AstroMath.radians(1.915) * sin(m) + AstroMath.radians(0.02) * sin(2 * m)
        let b = AstroMath.radians(5.555) * sin(n) + AstroMath.radians(0.168) * sin(2 * n)
        let k = j + a - b
        let earthSun = 1.00014 - 0.01671 * cos(m) - 0.00014 * cos(2 * m)
        let sunJupiter = 5.20872 - 0.25208 * cos(n) - 0.00611 * cos(2 * n)
        let delta = (sunJupiter * sunJupiter + earthSun * earthSun - 2 * sunJupiter * earthSun * cos(k)).squareRoot()
        let psi = asin(AstroMath.clamp(earthSun / delta * sin(k), -1.0, 1.0))
        let lambda = AstroMath.radians(34.35 + 0.083091 * d + 0.329 * sinV) + b
        let sunDeclination = AstroMath.radians(3.12) * sin(lambda + AstroMath.radians(42.8))
        let earthTermPhase: Double = AstroMath.radians(2.22) * sin(psi) * cos(lambda + AstroMath.radians(22.0))
        let earthTermDistance: Double = AstroMath.radians(1.3) * (sunJupiter - delta) / delta
            * sin(lambda - AstroMath.radians(100.5))
        let earthDeclination = sunDeclination - earthTermPhase - earthTermDistance
        let dd = d - delta / 173
        let u1 = AstroMath.radians(163.8069 + 203.4058646 * dd) + psi - b
        let u2 = AstroMath.radians(358.414 + 101.2916335 * dd) + psi - b
        let u3 = AstroMath.radians(5.7176 + 50.234518 * dd) + psi - b
        let u4 = AstroMath.radians(224.8092 + 21.48798 * dd) + psi - b
        let g = AstroMath.radians(331.18 + 50.310482 * dd)
        let h = AstroMath.radians(87.45 + 21.569231 * dd)
        let c1 = AstroMath.radians(0.473) * sin(2 * (u1 - u2))
        let c2 = AstroMath.radians(1.065) * sin(2 * (u2 - u3))
        let c3 = AstroMath.radians(0.165) * sin(g)
        let c4 = AstroMath.radians(0.843) * sin(h)
        let r1 = 5.9057 - 0.0244 * cos(2 * (u1 - u2))
        let r2 = 9.3966 - 0.0882 * cos(2 * (u2 - u3))
        let r3 = 14.9883 - 0.0216 * cos(g)
        let r4 = 26.3627 - 0.1939 * cos(h)
        let geometry = Geometry(earthDeclination: earthDeclination, sunDeclination: sunDeclination, psi: psi)
        return GalileanMoonsState(
            earthDeclination: AstroMath.degrees(earthDeclination),
            sunDeclination: AstroMath.degrees(sunDeclination),
            moons: [
                geometry.position(.io, u: u1 + c1, r: r1),
                geometry.position(.europa, u: u2 + c2, r: r2),
                geometry.position(.ganymede, u: u3 + c3, r: r3),
                geometry.position(.callisto, u: u4 + c4, r: r4),
            ])
    }

    /// The geometry shared by the four moons: the declinations of the Earth and the Sun and the angle at Jupiter between
    /// them. A moon at orbital longitude `u` (from the Earth side) and distance `r` stands at
    /// `r (sin u, 0, cos u)` in axes (west, north, towards the Earth's side of the equatorial plane).
    private struct Geometry {
        let sinEarth: Double
        let cosEarth: Double
        let sunWest: Double
        let sunNorth: Double
        let sunToward: Double

        init(earthDeclination: Double, sunDeclination: Double, psi: Double) {
            sinEarth = sin(earthDeclination)
            cosEarth = cos(earthDeclination)
            let cosSun = cos(sunDeclination)
            sunWest = cosSun * sin(psi)
            sunNorth = sin(sunDeclination)
            sunToward = cosSun * cos(psi)
        }

        func position(_ moon: GalileanMoon, u: Double, r: Double) -> GalileanMoonPosition {
            let west = r * sin(u)
            let toward = r * cos(u)
            let x = west
            let y = -toward * sinEarth
            let z = toward * cosEarth
            // Along the sunlight: positive when the moon is on the Sun's side of Jupiter.
            let alongSun = west * sunWest + toward * sunToward
            let offAxis = r * r - alongSun * alongSun
            var shadow: GalileanShadow?
            var isEclipsed = false
            if offAxis < 1 {
                if alongSun > 0 {
                    // The shadow runs away from the Sun and meets the sphere after `reach`.
                    let reach = alongSun - (1 - offAxis).squareRoot()
                    let hitWest = west - reach * sunWest
                    let hitNorth = -reach * sunNorth
                    let hitToward = toward - reach * sunToward
                    let hitFront = hitNorth * sinEarth + hitToward * cosEarth
                    if hitFront > 0 {
                        shadow = GalileanShadow(x: hitWest, y: hitNorth * cosEarth - hitToward * sinEarth)
                    }
                } else {
                    isEclipsed = true
                }
            }
            return GalileanMoonPosition(moon: moon, x: x, y: y, z: z, shadow: shadow, isEclipsed: isEclipsed)
        }
    }

    /// The starts and ends of the transits, shadow transits, occultations and eclipses of the four moons from `from` to
    /// `to`, in time order. Intervals longer than `maximumSpanDays` are cut short; an interval that is reversed or outside
    /// the years 1 to 4001 gives nothing. A phenomenon already under way at `from` has no start event.
    ///
    /// The moons are sampled every `sampleSeconds` and each change is refined by bisection to under a second. The times
    /// are only as good as the positions: about `accuracyMinutes` minutes. Cost: about 1 ms for a day.
    public static func events(from: Date, to: Date) -> [GalileanMoonEvent] {
        let first = from.timeIntervalSinceReferenceDate
        let last = to.timeIntervalSinceReferenceDate
        guard first.isFinite, last.isFinite, first >= Date.distantPast.timeIntervalSinceReferenceDate,
              last <= Date.distantFuture.timeIntervalSinceReferenceDate, last >= first else { return [] }
        let startSeconds = from.timeIntervalSince1970
        let endSeconds = min(to.timeIntervalSince1970, startSeconds + maximumSpanDays * JulianDate.secondsPerDay)
        let deltaDays = JulianDate(date: from).deltaT / JulianDate.secondsPerDay
        func flags(_ seconds: Double) -> Int {
            let state = positions(tt: seconds / JulianDate.secondsPerDay + JulianDate.unixEpoch + deltaDays)
            var mask = 0
            for (index, moon) in state.moons.enumerated() {
                if moon.isInTransit { mask |= 1 << (index * 4) }
                if moon.shadow != nil { mask |= 1 << (index * 4 + 1) }
                if moon.isBehindDisc { mask |= 1 << (index * 4 + 2) }
                if moon.isEclipsed { mask |= 1 << (index * 4 + 3) }
            }
            return mask
        }
        let count = max(1, Int(((endSeconds - startSeconds) / sampleSeconds).rounded(.up)))
        var found = [GalileanMoonEvent]()
        var previousSeconds = startSeconds
        var previous = flags(startSeconds)
        for index in 1...count {
            let seconds = min(startSeconds + Double(index) * sampleSeconds, endSeconds)
            let current = flags(seconds)
            let changed = previous ^ current
            if changed != 0 {
                for bit in 0..<16 where (changed & (1 << bit)) != 0 {
                    var low = previousSeconds
                    var high = seconds
                    let before = previous & (1 << bit)
                    while high - low > 0.5 {
                        let middle = (low + high) / 2
                        if (flags(middle) & (1 << bit)) == before { low = middle } else { high = middle }
                    }
                    found.append(GalileanMoonEvent(
                        moon: GalileanMoon.allCases[bit / 4], phenomenon: GalileanPhenomenon.allCases[bit % 4],
                        edge: before == 0 ? .start : .end, date: Date(timeIntervalSince1970: (low + high) / 2)))
                }
            }
            previousSeconds = seconds
            previous = current
        }
        return found.enumerated().sorted { first, second in
            first.element.date != second.element.date ? first.element.date < second.element.date
                : first.offset < second.offset
        }.map(\.element)
    }
}
