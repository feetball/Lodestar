import Foundation

/// The kind of a lunar eclipse.
public enum LunarEclipseKind: String, CaseIterable, Sendable, Hashable, Codable {
    /// The Moon only passes through the penumbra.
    case penumbral
    /// Part of the Moon enters the umbra.
    case partial
    /// The whole Moon enters the umbra.
    case total

    /// The English name, e.g. "Total".
    public var displayName: String {
        switch self {
        case .penumbral: "Penumbral"
        case .partial: "Partial"
        case .total: "Total"
        }
    }
}

/// The instant of one contact of an eclipse.
public struct EclipseContactTime: Sendable, Hashable {
    /// Which contact.
    public let contact: EclipseContact
    /// The instant.
    public let time: Date

    public init(contact: EclipseContact, time: Date) {
        self.contact = contact
        self.time = time
    }
}

/// A lunar eclipse as seen from the Earth's centre; the event's date is `greatest`.
///
/// The shadow follows Danjon's rule as used in the NASA/Espenak canon: the Earth's radius is enlarged by 1 % to account
/// for the atmosphere (the umbra grows by 1.4 %). The magnitudes are those of the canon: the fraction of the Moon's
/// diameter inside the umbra (negative before the Moon reaches it) and the penumbra.
public struct LunarEclipse: Sendable, Hashable {
    /// Penumbral, partial or total.
    public let kind: LunarEclipseKind
    /// Least distance of the Moon's centre from the shadow axis, in units of the Moon's equatorial horizontal
    /// parallax, positive when the Moon passes north of the axis.
    public let gamma: Double
    /// The penumbral magnitude at the greatest eclipse.
    public let penumbralMagnitude: Double
    /// The umbral magnitude at the greatest eclipse; negative for a penumbral eclipse.
    public let umbralMagnitude: Double
    /// The Moon enters the penumbra.
    public let p1: Date
    /// The Moon enters the umbra; `nil` for a penumbral eclipse.
    public let u1: Date?
    /// The Moon is completely in the umbra; `nil` unless total.
    public let u2: Date?
    /// The Moon's centre is nearest the axis of the shadow.
    public let greatest: Date
    /// The Moon starts to leave the umbra completely; `nil` unless total.
    public let u3: Date?
    /// The Moon leaves the umbra; `nil` for a penumbral eclipse.
    public let u4: Date?
    /// The Moon leaves the penumbra.
    public let p4: Date

    public init(kind: LunarEclipseKind, gamma: Double, penumbralMagnitude: Double, umbralMagnitude: Double, p1: Date,
                u1: Date?, u2: Date?, greatest: Date, u3: Date?, u4: Date?, p4: Date) {
        self.kind = kind
        self.gamma = gamma
        self.penumbralMagnitude = penumbralMagnitude
        self.umbralMagnitude = umbralMagnitude
        self.p1 = p1
        self.u1 = u1
        self.u2 = u2
        self.greatest = greatest
        self.u3 = u3
        self.u4 = u4
        self.p4 = p4
    }

    /// The contacts that exist, in time order.
    public var contacts: [EclipseContactTime] {
        var all = [EclipseContactTime(contact: .p1, time: p1)]
        if let u1 { all.append(EclipseContactTime(contact: .u1, time: u1)) }
        if let u2 { all.append(EclipseContactTime(contact: .u2, time: u2)) }
        all.append(EclipseContactTime(contact: .greatest, time: greatest))
        if let u3 { all.append(EclipseContactTime(contact: .u3, time: u3)) }
        if let u4 { all.append(EclipseContactTime(contact: .u4, time: u4)) }
        all.append(EclipseContactTime(contact: .p4, time: p4))
        return all
    }

    /// Seconds between the first and last penumbral contact.
    public var penumbralDuration: Double { p4.timeIntervalSince(p1) }

    /// Seconds between the first and last umbral contact; 0 for a penumbral eclipse.
    public var partialDuration: Double {
        if let u1, let u4 { return u4.timeIntervalSince(u1) }
        return 0
    }

    /// Seconds of totality; 0 unless total.
    public var totalDuration: Double {
        if let u2, let u3 { return u3.timeIntervalSince(u2) }
        return 0
    }
}

/// The Earth's shadow and the Moon at one instant, as seen from the Earth's centre (angles in degrees).
struct LunarShadow {
    /// Danjon's rule: the Earth's radius is enlarged by 1 % for the atmosphere.
    static let shadowEnlargement = 1.01

    /// The north pole of the ecliptic of J2000.0 in the J2000 equatorial frame.
    static let eclipticNorth = Vector3(0, -sin(AstroMath.radians(Obliquity.j2000)), cos(AstroMath.radians(Obliquity.j2000)))

    let ut: Double
    /// Angular distance of the Moon's centre from the shadow axis (the point opposite the Sun).
    let separation: Double
    /// Angular radius of the umbra at the Moon's distance, with the atmospheric enlargement.
    let umbra: Double
    /// Angular radius of the penumbra at the Moon's distance, with the atmospheric enlargement.
    let penumbra: Double
    /// The Moon's angular semidiameter.
    let moonRadius: Double
    /// The Moon's equatorial horizontal parallax (without enlargement).
    let parallax: Double
    /// `true` when the Moon is north of the axis (ecliptic north).
    let isNorth: Bool

    init(ut: Double) {
        self.ut = ut
        let jd = JulianDate(ut: ut)
        let sun = Ephemeris.geocentricJ2000(of: .sun, at: jd) * SkyFrame.kilometersPerAU
        let moon = Ephemeris.geocentricJ2000(of: .moon, at: jd) * SkyFrame.kilometersPerAU
        let sunDistance = sun.length
        let moonDistance = moon.length
        let axis = -sun / sunDistance
        separation = moon.angle(to: axis)
        let earthRadius = SkyFrame.earthEquatorialRadiusKilometers * Self.shadowEnlargement
        let moonParallax = AstroMath.asinDeg(earthRadius / moonDistance)
        let sunParallax = AstroMath.asinDeg(earthRadius / sunDistance)
        let sunRadius = AstroMath.asinDeg(SolarSystemBody.sun.meanRadiusKilometers / sunDistance)
        umbra = moonParallax + sunParallax - sunRadius
        penumbra = moonParallax + sunParallax + sunRadius
        moonRadius = AstroMath.asinDeg(SolarSystemBody.moon.meanRadiusKilometers / moonDistance)
        parallax = AstroMath.asinDeg(SkyFrame.earthEquatorialRadiusKilometers / moonDistance)
        let offset = moon - axis * moon.dot(axis)
        isNorth = offset.dot(Self.eclipticNorth) >= 0
    }
}

/// Finds lunar eclipses: penumbral, partial and total, with the contacts P1, U1, U2, greatest, U3, U4 and P4.
///
/// For each full Moon whose ecliptic latitude is below 1.7° the greatest eclipse is the minimum of the Moon's
/// angular distance from the anti-solar point (golden-section search), and each contact is the root (Brent) of that
/// distance minus the sum or difference of the Moon's semidiameter and the shadow's radius. The positions are the
/// geocentric apparent places of `Ephemeris`. Cost: about 2 ms per eclipse, plus the phases.
public enum LunarEclipseFinder {
    private static let latitudeLimit = 1.7
    private static let searchHalfWindow = 0.15
    private static let contactHalfWindow = 0.25
    private static let greatestTolerance = 1e-6
    private static let contactTolerance = 1e-6

    /// The lunar eclipses with the greatest eclipse from `from` to `to` (both inclusive), as events without visibility.
    public static func events(from: Date, to: Date) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let end = EventSearch.limitedEnd(from: from, to: to)
        return events(from: from, to: end, phases: PhaseTable(from: from, to: end))
    }

    static func events(from: Date, to: Date, phases: PhaseTable) -> [AstronomicalEvent] {
        var found = [AstronomicalEvent]()
        for full in phases.fullMoons {
            guard let eclipse = eclipse(full: full) else { continue }
            if eclipse.greatest < from || eclipse.greatest > to { continue }
            found.append(AstronomicalEvent(date: eclipse.greatest, details: .lunarEclipse(eclipse), visibility: nil))
        }
        return found
    }

    /// The lunar eclipse of the full Moon at `full`, or `nil` when the Moon misses the penumbra.
    static func eclipse(full: Date) -> LunarEclipse? {
        let ut0 = EventSearch.ut(full)
        let moon = Ephemeris.geocentricJ2000(of: .moon, at: JulianDate(ut: ut0))
        if abs(AstroMath.asinDeg(moon.dot(LunarShadow.eclipticNorth) / moon.length)) > latitudeLimit { return nil }
        let greatestUT = EventSearch.minimum(of: { LunarShadow(ut: $0).separation }, lower: ut0 - searchHalfWindow,
                                             upper: ut0 + searchHalfWindow, tolerance: greatestTolerance).time
        let greatest = LunarShadow(ut: greatestUT)
        if greatest.separation >= greatest.penumbra + greatest.moonRadius { return nil }

        let penumbralMagnitude = (greatest.penumbra + greatest.moonRadius - greatest.separation) / (2 * greatest.moonRadius)
        let umbralMagnitude = (greatest.umbra + greatest.moonRadius - greatest.separation) / (2 * greatest.moonRadius)
        let hasUmbra = umbralMagnitude > 0
        let isTotal = greatest.separation < greatest.umbra - greatest.moonRadius

        func contact(before: Bool, margin: (LunarShadow) -> Double) -> Date? {
            let lower = before ? greatestUT - contactHalfWindow : greatestUT
            let upper = before ? greatestUT : greatestUT + contactHalfWindow
            let root = EventSearch.root(of: { time in
                let shadow = LunarShadow(ut: time)
                return shadow.separation - margin(shadow)
            }, lower: lower, upper: upper, tolerance: contactTolerance)
            return root.map { EventSearch.instant($0) }
        }

        guard let penumbralBegin = contact(before: true, margin: { $0.penumbra + $0.moonRadius }),
              let penumbralEnd = contact(before: false, margin: { $0.penumbra + $0.moonRadius }) else { return nil }
        let partialBegin = hasUmbra ? contact(before: true, margin: { $0.umbra + $0.moonRadius }) : nil
        let partialEnd = hasUmbra ? contact(before: false, margin: { $0.umbra + $0.moonRadius }) : nil
        let totalBegin = isTotal ? contact(before: true, margin: { $0.umbra - $0.moonRadius }) : nil
        let totalEnd = isTotal ? contact(before: false, margin: { $0.umbra - $0.moonRadius }) : nil
        let gamma = (greatest.isNorth ? 1.0 : -1.0) * greatest.separation / greatest.parallax
        return LunarEclipse(
            kind: isTotal ? .total : (hasUmbra ? .partial : .penumbral),
            gamma: gamma,
            penumbralMagnitude: penumbralMagnitude,
            umbralMagnitude: umbralMagnitude,
            p1: penumbralBegin,
            u1: partialBegin,
            u2: totalBegin,
            greatest: EventSearch.instant(greatestUT),
            u3: totalEnd,
            u4: partialEnd,
            p4: penumbralEnd)
    }
}
