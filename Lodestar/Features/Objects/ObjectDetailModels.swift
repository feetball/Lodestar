import Foundation
import LodestarKit

/// How far away an object is, in the unit that suits it.
enum ObjectDetailDistance: Sendable, Equatable {
    case kilometers(Double)
    case astronomicalUnits(Double)
    case lightYears(Double)

    /// The distance for display, such as "384,400 km", "1.52 AU" or "2.5 million light-years".
    var text: String {
        switch self {
        case .kilometers(let value):
            return "\(value.formatted(.number.precision(.fractionLength(0)))) km"
        case .astronomicalUnits(let value):
            return "\(value.formatted(.number.precision(.fractionLength(2)))) AU"
        case .lightYears(let value) where value >= 1_000_000:
            return "\((value / 1_000_000).formatted(.number.precision(.fractionLength(1)))) million light-years"
        case .lightYears(let value) where value < 100:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) light-years"
        case .lightYears(let value):
            return "\(value.formatted(.number.precision(.fractionLength(0)))) light-years"
        }
    }
}

/// What changes from minute to minute about an object: where it is, how bright, how large and how lit.
struct ObjectDetailCurrent: Sendable {
    let date: Date
    /// Apparent position in the observer's sky, refraction included, as the Aim screen shows it.
    let horizontal: HorizontalCoordinate
    /// Apparent place on the true equator and equinox of date.
    let equatorial: EquatorialCoordinate
    /// The visual magnitude now (it changes for the Sun, the Moon and the planets).
    let magnitude: Double?
    /// The size now (it changes for the Sun, the Moon and the planets).
    let angularSize: AngularSize?
    let distance: ObjectDetailDistance?
    /// The sunlit fraction of the disc; `nil` for the Sun and for objects without phases.
    let illuminatedFraction: Double?
    /// The Moon's phase; set only for the Moon.
    let moonPhase: MoonPhaseInfo?
    /// `true` when the object is above the horizon but hidden behind the site's recorded skyline.
    let isBehindSkyline: Bool
    /// `true` for a comet or an asteroid, whose distances and warnings are in `smallBody`.
    var isSmallBody = false
    /// A comet's or asteroid's distances, elongation, phase, magnitude estimate, warnings and tail; `nil` when its
    /// orbit cannot be evaluated.
    var smallBody: SmallBodyDetail?
}

/// One point of the altitude curve.
struct ObjectDetailAltitudeSample: Sendable, Identifiable {
    let date: Date
    /// Apparent altitude in degrees.
    let altitude: Double

    var id: Date { date }
}

/// A stretch of the night in which the sky is lit to a certain degree by the Sun.
struct ObjectDetailTwilightBand: Sendable, Identifiable {
    let interval: DateInterval
    /// 1 = astronomical twilight, 2 = nautical twilight, 3 = civil twilight, 4 = daylight.
    let brightness: Int

    var id: Date { interval.start }
}

/// The highest point of an object during the dark hours.
struct ObjectDetailPeak: Sendable, Equatable {
    let date: Date
    /// Apparent altitude in degrees.
    let altitude: Double
}

/// Rising, culmination and setting of an object for one night, with the data behind the altitude chart.
///
/// A night runs from local noon to local noon (see `TwilightCalculator`).
struct ObjectDetailNight: Sendable {
    /// Local noon to local noon.
    let interval: DateInterval
    /// Sunset to sunrise: the stretch the chart shows.
    let chartRange: DateInterval
    let twilight: NightTwilight
    /// The hours of astronomical darkness, if the Sun gets that low.
    let darkness: DateInterval?
    /// The object's rise, transit and set within `interval`, with the horizon of `RiseSetCalculator` (or the site's
    /// skyline, see `appliesSkyline`).
    let events: RiseTransitSet
    /// Apparent altitude at transit.
    let transitAltitude: Double?
    /// The apparent altitude every ten minutes across `chartRange`.
    let samples: [ObjectDetailAltitudeSample]
    let twilightBands: [ObjectDetailTwilightBand]
    /// The instants of the time axis labels, on local hours.
    let hourTicks: [Date]
    /// Where the object is highest while it is dark; `nil` when there is no darkness, or, with a skyline, when the
    /// object stays behind it.
    let bestInDarkness: ObjectDetailPeak?
    /// Whether the site's recorded skyline decided `events` and `bestInDarkness`: then a rise is the object clearing
    /// the skyline and a set is it sinking behind it.
    let appliesSkyline: Bool

    /// When this night is over and "tonight" means the next one.
    var expiry: Date { twilight.sunrise ?? interval.end }

    /// The rising, culmination and setting that fall in the night, in the order they happen.
    var timeline: [ObjectDetailEvent] {
        let candidates = [(ObjectDetailEvent.Kind.rise, events.rise), (.transit, events.transit), (.set, events.set)]
        return candidates
            .compactMap { kind, date in date.map { ObjectDetailEvent(kind: kind, date: $0) } }
            .sorted { $0.date < $1.date }
    }
}

/// The object rising, culminating or setting.
struct ObjectDetailEvent: Sendable, Identifiable {
    enum Kind: String, Sendable {
        case rise, transit, set
    }

    let kind: Kind
    let date: Date

    var id: String { kind.rawValue }
}

/// How much the Moon is likely to disturb a shot of the object.
struct ObjectDetailMoonConditions: Sendable, Equatable {
    enum Impact: Sendable {
        case moonDown, minor, moderate, severe
    }

    /// The instant the conditions were evaluated for.
    let date: Date
    /// Whether `date` is the present moment (otherwise it is the object's best time tonight).
    let isNow: Bool
    /// Angular distance between the object and the Moon, in degrees.
    let separation: Double
    let illuminatedFraction: Double
    let impact: Impact
}

/// Everything the detail screen computes for an object and an observer.
struct ObjectDetailSnapshot: Sendable {
    let current: ObjectDetailCurrent
    let night: ObjectDetailNight
    /// `nil` for the Sun and the Moon.
    let moon: ObjectDetailMoonConditions?
}

/// The inputs of `ObjectDetailCalculator.snapshot(for:)`.
struct ObjectDetailInput: Sendable {
    let object: CelestialObject
    let context: ObserverContext
    let date: Date
    /// The night computed for an earlier snapshot, reused while it is still the current night.
    let previousNight: ObjectDetailNight?
}

/// How much of the camera frame an extended object covers.
struct ObjectDetailFraming: Sendable, Equatable {
    /// How much neighbouring panels of a mosaic overlap, as a fraction of a panel.
    static let mosaicOverlap = 0.2

    /// The object's major axis divided by the frame's long side.
    let majorFraction: Double
    /// The object's minor axis divided by the frame's short side.
    let minorFraction: Double

    /// The larger of the two fractions: how full the frame is along the tightest dimension.
    var fillFraction: Double { max(majorFraction, minorFraction) }
    var fitsInFrame: Bool { fillFraction <= 1 }
    /// Panels needed along the frame's long side to cover the object with overlapping panels.
    var longSidePanels: Int { Self.panels(covering: majorFraction) }
    /// Panels needed along the frame's short side to cover the object with overlapping panels.
    var shortSidePanels: Int { Self.panels(covering: minorFraction) }

    private static func panels(covering fraction: Double) -> Int {
        guard fraction > 1 else { return 1 }
        let extra = ((fraction - 1) / (1 - mosaicOverlap)).rounded(.up)
        return Int(min(1 + extra, 99))
    }
}

/// How an object fits the user's lens and how long an exposure can be before stars trail.
struct ObjectDetailPhotography: Sendable {
    /// The frame of the user's camera and lens, in landscape orientation.
    let frame: FrameSize
    /// `nil` for objects without a known angular size.
    let framing: ObjectDetailFraming?
    /// `nil` for the Sun and the Moon, for which star trails do not matter.
    let npf: ExposureEstimate?
    let rule500: ExposureEstimate?
}
