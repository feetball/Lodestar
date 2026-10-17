import Foundation

/// What the night holds for an astrophotographer at one place: twilight, the Moon, the dark hours,
/// the Milky Way's core and the planets.
///
/// The night runs from local noon of the starting date to local noon of the next day. Altitudes are
/// geometric (no refraction). "Astronomical darkness" is the time the Sun is more than 18° below the
/// horizon; "dark" (`darknessIntervals`) additionally requires the Moon to be below the horizon.
public struct NightSummary: Sendable, Hashable {
    /// The place the summary was computed for.
    public let observer: Observer
    /// Local noon of the starting date to local noon of the next day.
    public let night: DateInterval
    /// Sunset, the three twilights and sunrise.
    public let twilight: NightTwilight
    /// The instant at which the Moon's phase and the planets' magnitudes were evaluated: astronomical
    /// dusk, or solar midnight when the Sun does not set below −18° that evening.
    public let referenceDate: Date
    /// The Moon's phase and the times it is above the horizon.
    public let moon: MoonSummary
    /// The times the Sun is more than 18° below the horizon, in time order.
    ///
    /// Empty when the Sun does not get that low, as in high-latitude summers (then
    /// `hasAstronomicalDarkness` is `false`); the whole night in polar winter.
    public let astronomicalDarknessIntervals: [DateInterval]
    /// The times of astronomical darkness during which the Moon is also below the horizon, in time order.
    public let darknessIntervals: [DateInterval]
    /// When the Galactic Centre can be photographed.
    public let milkyWayCore: MilkyWayCoreVisibility
    /// Mercury to Neptune, in that order.
    public let planets: [PlanetVisibility]

    /// `false` when the Sun never gets 18° below the horizon during the night.
    public var hasAstronomicalDarkness: Bool { !astronomicalDarknessIntervals.isEmpty }

    /// The hours of astronomical darkness, whether or not the Moon is up.
    public var astronomicalDarkHours: Double {
        NightPlanner.IntervalSet.totalDuration(of: astronomicalDarknessIntervals) / 3600
    }

    /// The hours of astronomical darkness with the Moon below the horizon.
    public var moonFreeDarkHours: Double {
        NightPlanner.IntervalSet.totalDuration(of: darknessIntervals) / 3600
    }

    /// The dark intervals of the given kind.
    public func darkness(_ kind: DarknessKind) -> [DateInterval] {
        switch kind {
        case .astronomical: astronomicalDarknessIntervals
        case .moonFree: darknessIntervals
        }
    }

    /// Creates a summary from its parts.
    public init(observer: Observer, night: DateInterval, twilight: NightTwilight, referenceDate: Date,
                moon: MoonSummary, astronomicalDarknessIntervals: [DateInterval], darknessIntervals: [DateInterval],
                milkyWayCore: MilkyWayCoreVisibility, planets: [PlanetVisibility]) {
        self.observer = observer
        self.night = night
        self.twilight = twilight
        self.referenceDate = referenceDate
        self.moon = moon
        self.astronomicalDarknessIntervals = astronomicalDarknessIntervals
        self.darknessIntervals = darknessIntervals
        self.milkyWayCore = milkyWayCore
        self.planets = planets
    }
}

/// The Moon during one night.
public struct MoonSummary: Sendable, Hashable {
    /// The phase at `NightSummary.referenceDate` (`phase.date`).
    public let phase: MoonPhaseInfo
    /// The first rise, transit and set within the night. The horizon is the Moon's upper limb after
    /// standard refraction, as in `RiseSetCalculator`.
    public let riseTransitSet: RiseTransitSet
    /// Every stretch of the night in which the Moon is above the horizon, in time order.
    public let upIntervals: [DateInterval]

    /// The fraction of the visible disc that is sunlit, [0, 1].
    public var illuminatedFraction: Double { phase.illuminatedFraction }

    /// Creates a Moon summary.
    public init(phase: MoonPhaseInfo, riseTransitSet: RiseTransitSet, upIntervals: [DateInterval]) {
        self.phase = phase
        self.riseTransitSet = riseTransitSet
        self.upIntervals = upIntervals
    }
}

/// When the core of the Milky Way, the Galactic Centre in Sagittarius, can be photographed.
///
/// The core counts as visible while it is at least `minimumAltitude` above the horizon during
/// astronomical darkness.
public struct MilkyWayCoreVisibility: Sendable, Hashable {
    /// The altitude, in degrees, from which the core counts as visible.
    public static let minimumAltitude = 10.0

    /// The Galactic Centre's J2000 position: the radio source Sagittarius A*,
    /// 17h 45m 40.04s, −29° 00′ 28.1″.
    static let galacticCentre = EquatorialCoordinate(rightAscensionHours: 17 + 45.0 / 60 + 40.04 / 3600,
                                                     declination: -(29 + 28.1 / 3600))

    /// When the core rises, culminates and sets within the night, with the horizon at −0.5667°.
    public let riseTransitSet: RiseTransitSet
    /// The stretches of astronomical darkness in which the core is at least `minimumAltitude`
    /// high, whether or not the Moon is up.
    public let visibleIntervals: [DateInterval]
    /// The parts of `visibleIntervals` in which the Moon is below the horizon.
    public let moonFreeVisibleIntervals: [DateInterval]
    /// The best moment to photograph the core: when it is highest, within `moonFreeVisibleIntervals`
    /// if there are any and otherwise within `visibleIntervals`. `nil` when the core is never visible.
    public let bestTime: Date?
    /// The core's geometric altitude at `bestTime`, in degrees.
    public let maxAltitude: Double?
    /// The core's azimuth at `bestTime`, in degrees from north through east.
    public let bestAzimuth: Double?

    /// Creates a Milky Way core summary.
    public init(riseTransitSet: RiseTransitSet, visibleIntervals: [DateInterval],
                moonFreeVisibleIntervals: [DateInterval], bestTime: Date?, maxAltitude: Double?,
                bestAzimuth: Double?) {
        self.riseTransitSet = riseTransitSet
        self.visibleIntervals = visibleIntervals
        self.moonFreeVisibleIntervals = moonFreeVisibleIntervals
        self.bestTime = bestTime
        self.maxAltitude = maxAltitude
        self.bestAzimuth = bestAzimuth
    }
}

/// One planet during a night.
///
/// A planet is visible while it is at least `minimumAltitude` above the horizon during astronomical
/// darkness; the Moon is ignored because planets are bright. Mercury and Venus stay close to the Sun
/// and are mostly seen in twilight, before or after the dark hours; `riseTransitSet` still shows when
/// they set or rise.
public struct PlanetVisibility: Sendable, Hashable {
    /// The altitude, in degrees, from which a planet counts as visible.
    public static let minimumAltitude = 10.0

    /// The planet.
    public let body: SolarSystemBody
    /// When the planet rises, culminates and sets within the night.
    public let riseTransitSet: RiseTransitSet
    /// The stretches of astronomical darkness in which the planet is at least `minimumAltitude` high.
    public let visibleIntervals: [DateInterval]
    /// The planet's highest geometric altitude during astronomical darkness, in degrees. Negative when
    /// it stays below the horizon; `nil` when there is no astronomical darkness.
    public let maxAltitudeDuringDarkness: Double?
    /// The planet's apparent visual magnitude at `NightSummary.referenceDate`.
    public let magnitude: Double?

    /// `true` when the planet is at least `minimumAltitude` high at some time during astronomical darkness.
    public var visibleDuringDarkness: Bool { !visibleIntervals.isEmpty }

    /// Creates a planet record.
    public init(body: SolarSystemBody, riseTransitSet: RiseTransitSet, visibleIntervals: [DateInterval],
                maxAltitudeDuringDarkness: Double?, magnitude: Double?) {
        self.body = body
        self.riseTransitSet = riseTransitSet
        self.visibleIntervals = visibleIntervals
        self.maxAltitudeDuringDarkness = maxAltitudeDuringDarkness
        self.magnitude = magnitude
    }
}
