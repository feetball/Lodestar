import Foundation

/// The kinds of astronomical events the calculator finds.
public enum EventKind: String, CaseIterable, Sendable, Hashable, Codable {
    /// The peak of a meteor shower from the IMO working list.
    case meteorShower
    /// A close approach of the Moon or a planet to another planet, a bright ecliptic star or the Pleiades.
    case conjunction
    /// A superior planet (Mars to Neptune) opposite the Sun.
    case opposition
    /// The greatest elongation of Mercury or Venus from the Sun.
    case greatestElongation
    /// The Earth's perihelion or aphelion.
    case earthApsis
    /// An equinox or a solstice.
    case season
    /// A full Moon that is a supermoon, a micromoon or a blue moon.
    case fullMoonSpecial
    /// A penumbral, partial or total lunar eclipse.
    case lunarEclipse
    /// A partial, annular, total or hybrid solar eclipse.
    case solarEclipse

    /// Every kind except `earthApsis`, which is optional.
    public static let defaultKinds: Set<EventKind> = Set(allCases.filter { $0 != .earthApsis })

    /// The English name, e.g. "Lunar eclipse".
    public var displayName: String {
        switch self {
        case .meteorShower: "Meteor shower"
        case .conjunction: "Conjunction"
        case .opposition: "Opposition"
        case .greatestElongation: "Greatest elongation"
        case .earthApsis: "Perihelion or aphelion"
        case .season: "Equinox or solstice"
        case .fullMoonSpecial: "Special full Moon"
        case .lunarEclipse: "Lunar eclipse"
        case .solarEclipse: "Solar eclipse"
        }
    }
}

/// What to search for and how strictly. The initializer replaces non-finite values with the defaults and clamps the
/// rest into range.
public struct EventOptions: Sendable, Hashable {
    /// The kinds of events to include; `EventKind.defaultKinds` (everything except the Earth's apsides).
    public let kinds: Set<EventKind>
    /// Largest minimum separation in degrees of a planet–planet pair that counts as a conjunction, 0…30, default 3.
    public let planetConjunctionThreshold: Double
    /// Largest minimum geocentric separation in degrees of the Moon from a planet, a bright star or the Pleiades,
    /// 0…30, default 5.
    public let moonConjunctionThreshold: Double
    /// Conjunctions closer than this to the Sun (degrees, 0…90, default 10) are dropped because they cannot be seen.
    public let minimumSolarElongation: Double
    /// The zone that defines calendar months (blue moons) and the local noon-to-noon nights used for viewing
    /// windows; `nil` means UTC without an observer and the nearest whole-hour zone of the observer's longitude with one.
    public let timeZone: TimeZone?
    /// The altitude in degrees (0…90, default 10) a target must reach for a viewing window.
    public let minimumAltitude: Double
    /// Drops events that the observer cannot see (no viewing window); has no effect without an observer or for
    /// events without a visibility (equinoxes, solstices, apsides).
    public let visibleOnly: Bool

    public init(kinds: Set<EventKind> = EventKind.defaultKinds, planetConjunctionThreshold: Double = 3,
                moonConjunctionThreshold: Double = 5, minimumSolarElongation: Double = 10,
                timeZone: TimeZone? = nil, minimumAltitude: Double = 10, visibleOnly: Bool = false) {
        self.kinds = kinds
        self.planetConjunctionThreshold = Self.normalized(planetConjunctionThreshold, fallback: 3, lower: 0, upper: 30)
        self.moonConjunctionThreshold = Self.normalized(moonConjunctionThreshold, fallback: 5, lower: 0, upper: 30)
        self.minimumSolarElongation = Self.normalized(minimumSolarElongation, fallback: 10, lower: 0, upper: 90)
        self.timeZone = timeZone
        self.minimumAltitude = Self.normalized(minimumAltitude, fallback: 10, lower: 0, upper: 90)
        self.visibleOnly = visibleOnly
    }

    private static func normalized(_ value: Double, fallback: Double, lower: Double, upper: Double) -> Double {
        value.isFinite ? AstroMath.clamp(value, lower, upper) : fallback
    }
}

/// The points of an eclipse at which an observer's altitude is reported.
public enum EclipseContact: String, CaseIterable, Sendable, Hashable, Codable {
    /// Lunar: the Moon touches the penumbra.
    case p1 = "P1"
    /// Lunar: the Moon touches the umbra.
    case u1 = "U1"
    /// Lunar: the Moon is completely inside the umbra.
    case u2 = "U2"
    /// Lunar: the greatest eclipse.
    case greatest
    /// Lunar: the Moon starts to leave the umbra completely.
    case u3 = "U3"
    /// Lunar: the Moon leaves the umbra.
    case u4 = "U4"
    /// Lunar: the Moon leaves the penumbra.
    case p4 = "P4"
    /// Solar: the Moon first touches the Sun.
    case c1 = "C1"
    /// Solar: the central phase (totality or annularity) begins.
    case c2 = "C2"
    /// Solar: the maximum eclipse.
    case maximum
    /// Solar: the central phase ends.
    case c3 = "C3"
    /// Solar: the Moon last touches the Sun.
    case c4 = "C4"
}

/// Where the eclipsed body stands for an observer at one contact.
public struct ContactVisibility: Sendable, Hashable {
    /// Which contact.
    public let contact: EclipseContact
    /// The instant of the contact.
    public let time: Date
    /// Geometric topocentric altitude of the Moon (lunar) or the Sun (solar) in degrees; negative below the horizon.
    public let altitude: Double
    /// Azimuth in degrees from north through east, [0, 360).
    public let azimuth: Double

    public init(contact: EclipseContact, time: Date, altitude: Double, azimuth: Double) {
        self.contact = contact
        self.time = time
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// How well an event can be seen from one place.
///
/// The *subject* is the radiant of a meteor shower, the Sun or the Moon for an eclipse, the Moon for a special full
/// Moon, the planet for an opposition or an elongation, and for a conjunction the planet or star (for the Moon with a
/// planet or a star) or the midpoint of the two planets. Altitudes are geometric (no refraction).
public struct EventVisibility: Sendable, Hashable {
    /// Altitude of the subject at the event's instant, degrees (the Moon or Sun at greatest eclipse or maximum for eclipses).
    public let altitude: Double
    /// Azimuth of the subject at that instant, degrees from north through east.
    public let azimuth: Double
    /// The Sun's geometric altitude at that instant, degrees.
    public let sunAltitude: Double
    /// `true` when the Sun is below −18° (astronomical darkness) at that instant.
    public let isDark: Bool
    /// The viewing window of the night that contains the event (the local noon-to-noon interval, see
    /// `EventOptions.timeZone`): the stretch around the subject's highest point in which it is above
    /// `EventOptions.minimumAltitude` and the Sun is lower than `darknessLimit`. For eclipses it is the part of the
    /// eclipse during which the Moon or Sun is above the horizon. `nil` when there is none.
    public let bestWindow: DateInterval?
    /// The instant of the subject's greatest altitude inside `bestWindow` (the maximum for a solar eclipse, the
    /// greatest eclipse when visible for a lunar one).
    public let bestTime: Date?
    /// The Sun altitude the window required: −18° for meteor showers, −6° for conjunctions, oppositions and
    /// elongations, −0.8333° (sunset) for special full Moons, and 0° for eclipses (not applied).
    public let darknessLimit: Double
    /// Altitude and azimuth at each contact of an eclipse; empty for other events.
    public let contacts: [ContactVisibility]

    /// `true` when there is a viewing window.
    public var isObservable: Bool { bestWindow != nil }

    public init(altitude: Double, azimuth: Double, sunAltitude: Double, isDark: Bool, bestWindow: DateInterval?,
                bestTime: Date?, darknessLimit: Double, contacts: [ContactVisibility]) {
        self.altitude = altitude
        self.azimuth = azimuth
        self.sunAltitude = sunAltitude
        self.isDark = isDark
        self.bestWindow = bestWindow
        self.bestTime = bestTime
        self.darknessLimit = darknessLimit
        self.contacts = contacts
    }
}

/// Something a camera can be pointed at to photograph an event. Resolve it to the sky with `horizontal(in:refraction:)`.
public enum AimTarget: Sendable, Hashable {
    /// The Sun, the Moon or a planet.
    case body(SolarSystemBody)
    /// A fixed catalog place, J2000, with the proper motion of a star when it has one.
    case fixed(EquatorialCoordinate, ProperMotion?)
    /// The radiant of a meteor shower, drifting with the date of the frame.
    case radiant(MeteorShower)

    /// Topocentric horizontal coordinates of the target in `frame`, optionally including refraction.
    public func horizontal(in frame: SkyFrame, refraction: Bool = true) -> HorizontalCoordinate {
        switch self {
        case let .body(body):
            return frame.horizontal(of: body, refraction: refraction)
        case let .fixed(position, properMotion):
            return frame.horizontal(j2000: position, properMotion: properMotion, refraction: refraction)
        case let .radiant(shower):
            return frame.horizontal(j2000: shower.radiant(at: frame.date), properMotion: nil, refraction: refraction)
        }
    }
}

/// What kind of event it is and its numbers. Each case wraps one payload type; `kind` names it.
public enum EventDetails: Sendable, Hashable {
    /// A meteor shower peak.
    case meteorShower(MeteorShowerPeak)
    /// A conjunction.
    case conjunction(Conjunction)
    /// An opposition.
    case opposition(Opposition)
    /// A greatest elongation.
    case greatestElongation(GreatestElongation)
    /// The Earth's perihelion or aphelion.
    case earthApsis(EarthApsis)
    /// An equinox or a solstice.
    case season(Season)
    /// A supermoon, micromoon or blue moon.
    case fullMoonSpecial(FullMoonSpecial)
    /// A lunar eclipse.
    case lunarEclipse(LunarEclipse)
    /// A solar eclipse.
    case solarEclipse(SolarEclipse)

    /// The kind of event these details describe.
    public var kind: EventKind {
        switch self {
        case .meteorShower: .meteorShower
        case .conjunction: .conjunction
        case .opposition: .opposition
        case .greatestElongation: .greatestElongation
        case .earthApsis: .earthApsis
        case .season: .season
        case .fullMoonSpecial: .fullMoonSpecial
        case .lunarEclipse: .lunarEclipse
        case .solarEclipse: .solarEclipse
        }
    }
}

/// One astronomical event.
public struct AstronomicalEvent: Sendable, Hashable {
    /// The event's instant: the peak of a meteor shower, the minimum separation of a conjunction, the opposition, the
    /// greatest elongation, the apsis, the equinox or solstice, the full Moon, the greatest eclipse of a lunar eclipse
    /// and the greatest eclipse (anywhere on Earth) of a solar eclipse.
    public let date: Date
    /// The kind and the numbers of the event.
    public let details: EventDetails
    /// How well the observer can see it; `nil` without an observer and for equinoxes, solstices and apsides, which
    /// are not seen in the sky.
    public let visibility: EventVisibility?

    public init(date: Date, details: EventDetails, visibility: EventVisibility?) {
        self.date = date
        self.details = details
        self.visibility = visibility
    }

    /// The event with `visibility` replaced.
    func withVisibility(_ visibility: EventVisibility?) -> AstronomicalEvent {
        AstronomicalEvent(date: date, details: details, visibility: visibility)
    }

    /// The kind of event.
    public var kind: EventKind { details.kind }

    /// A short English title for lists, e.g. "Perseids peak", "Venus and Jupiter", "Total lunar eclipse" or
    /// "June solstice". The UI localizes from `details` instead.
    public var title: String {
        switch details {
        case let .meteorShower(peak): "\(peak.shower.name) peak"
        case let .conjunction(conjunction): "\(conjunction.first.displayName) and \(conjunction.second.displayName)"
        case let .opposition(opposition): "\(opposition.planet.displayName) at opposition"
        case let .greatestElongation(elongation):
            "\(elongation.planet.displayName) at greatest \(elongation.direction.displayName.lowercased()) elongation"
        case let .earthApsis(apsis): "Earth at \(apsis.kind.displayName.lowercased())"
        case let .season(season): season.kind.displayName
        case let .fullMoonSpecial(special): special.categories.map(\.displayName).joined(separator: " and ")
        case let .lunarEclipse(eclipse): "\(eclipse.kind.displayName) lunar eclipse"
        case let .solarEclipse(eclipse): "\(eclipse.kind.displayName) solar eclipse"
        }
    }

    /// What to point a camera at, main subject first: the radiant of a meteor shower, the two bodies of a conjunction
    /// (the Moon first), the planet of an opposition or an elongation, the Moon for a lunar eclipse or a special full
    /// Moon and the Sun for a solar eclipse. Empty for equinoxes, solstices and apsides.
    public var aimTargets: [AimTarget] {
        switch details {
        case let .meteorShower(peak): [.radiant(peak.shower)]
        case let .conjunction(conjunction): [conjunction.first.aimTarget, conjunction.second.aimTarget]
        case let .opposition(opposition): [.body(opposition.planet)]
        case let .greatestElongation(elongation): [.body(elongation.planet)]
        case .earthApsis: []
        case .season: []
        case .fullMoonSpecial: [.body(.moon)]
        case .lunarEclipse: [.body(.moon)]
        case .solarEclipse: [.body(.sun)]
        }
    }

    /// Where to aim in `frame` to frame the event: the position of the single target or the midpoint of the two bodies
    /// of a conjunction; `nil` when the event has no target.
    public func aimDirection(in frame: SkyFrame, refraction: Bool = true) -> HorizontalCoordinate? {
        let targets = aimTargets
        if targets.isEmpty { return nil }
        if targets.count == 1 { return targets[0].horizontal(in: frame, refraction: refraction) }
        var sum = Vector3.zero
        for target in targets {
            sum += target.horizontal(in: frame, refraction: refraction).unitVector
        }
        return HorizontalCoordinate(vector: sum)
    }
}
