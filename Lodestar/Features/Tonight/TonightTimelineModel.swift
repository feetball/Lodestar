import Foundation
import LodestarKit

/// How much of the Sun's light reaches the sky, from full night to day.
enum TonightSkyLevel: Int, CaseIterable, Sendable {
    case night, astronomical, nautical, civil, day

    /// The level of the sky while the Sun's centre is at `sunAltitude` degrees.
    init(sunAltitude: Double) {
        if sunAltitude <= TwilightCalculator.astronomicalAltitude {
            self = .night
        } else if sunAltitude <= TwilightCalculator.nauticalAltitude {
            self = .astronomical
        } else if sunAltitude <= TwilightCalculator.civilAltitude {
            self = .nautical
        } else if sunAltitude <= RiseSetCalculator.sunHorizonAltitude {
            self = .civil
        } else {
            self = .day
        }
    }

    var title: String {
        switch self {
        case .night: return "Night"
        case .astronomical: return "Astronomical"
        case .nautical: return "Nautical"
        case .civil: return "Civil"
        case .day: return "Day"
        }
    }

    /// How strongly the timeline fills the level: more for a brighter sky, nothing for full night.
    var fillOpacity: Double {
        switch self {
        case .night: return 0
        case .astronomical: return 0.16
        case .nautical: return 0.36
        case .civil: return 0.6
        case .day: return 0.9
        }
    }
}

/// The stretches of one night that the darkness timeline draws, ready for drawing.
struct TonightTimelineModel: Sendable {
    /// One stretch of the sky at a single level.
    struct Band: Sendable {
        let interval: DateInterval
        let level: TonightSkyLevel
    }

    /// Sunset to sunrise; the whole night when the Sun does not set or does not rise.
    let range: DateInterval
    /// The sky's level through `range`, in time order, without gaps.
    let bands: [Band]
    /// When the Moon is above the horizon.
    let moonUp: [DateInterval]
    /// Astronomical darkness with the Moon below the horizon.
    let dark: [DateInterval]
    /// When the Galactic Centre is high enough in the dark.
    let coreVisible: [DateInterval]
    /// The part of `coreVisible` in which the Moon is down too.
    let coreMoonFree: [DateInterval]
    /// A whole hour on the time axis.
    struct HourTick: Sendable {
        let date: Date
        /// The hour of the day, 0–23, in the night's time zone.
        let hour: Int
    }

    /// Every whole hour inside `range`; the drawing labels as many as fit.
    let hourTicks: [HourTick]

    init(summary: NightSummary, timeZone: TimeZone) {
        let twilight = summary.twilight
        let start = twilight.sunset ?? twilight.interval.start
        let range = DateInterval(start: start, end: max(twilight.sunrise ?? twilight.interval.end, start))
        self.range = range
        bands = Self.bands(over: range, twilight: twilight, observer: summary.observer)
        moonUp = Self.clipped(summary.moon.upIntervals, to: range)
        dark = Self.clipped(summary.darknessIntervals, to: range)
        coreVisible = Self.clipped(summary.milkyWayCore.visibleIntervals, to: range)
        coreMoonFree = Self.clipped(summary.milkyWayCore.moonFreeVisibleIntervals, to: range)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        hourTicks = Self.hourTicks(in: range, calendar: calendar)
    }

    // MARK: Construction

    /// The sky level between each pair of twilight events, judged by the Sun's altitude in the middle of
    /// the stretch so that it is right even where an event never happens (white nights, polar winter).
    private static func bands(over range: DateInterval, twilight: NightTwilight, observer: Observer) -> [Band] {
        guard range.duration > 0 else { return [] }
        let events = [twilight.sunset, twilight.civilDusk, twilight.nauticalDusk, twilight.astronomicalDusk,
                      twilight.astronomicalDawn, twilight.nauticalDawn, twilight.civilDawn, twilight.sunrise]
            .compactMap { $0 }
            .filter { $0 > range.start && $0 < range.end }
            .sorted()
        let cuts = [range.start] + events + [range.end]
        var bands: [Band] = []
        for (from, to) in zip(cuts, cuts.dropFirst()) where to > from {
            let middle = from.addingTimeInterval(to.timeIntervalSince(from) / 2)
            let sun = SkyFrame(date: middle, observer: observer).horizontal(of: .sun, refraction: false)
            let level = TonightSkyLevel(sunAltitude: sun.altitude)
            if let last = bands.last, last.level == level {
                bands[bands.count - 1] = Band(interval: DateInterval(start: last.interval.start, end: to), level: level)
            } else {
                bands.append(Band(interval: DateInterval(start: from, end: to), level: level))
            }
        }
        return bands
    }

    /// The parts of `intervals` that lie inside `range`.
    private static func clipped(_ intervals: [DateInterval], to range: DateInterval) -> [DateInterval] {
        intervals.compactMap { $0.intersection(with: range) }.filter { $0.duration > 0 }
    }

    /// The whole hours inside `range`.
    private static func hourTicks(in range: DateInterval, calendar: Calendar) -> [HourTick] {
        var ticks: [HourTick] = []
        var cursor = range.start
        for _ in 0..<48 {
            guard let next = calendar.nextDate(after: cursor, matching: DateComponents(minute: 0, second: 0),
                                               matchingPolicy: .nextTime),
                  next < range.end else { break }
            ticks.append(HourTick(date: next, hour: calendar.component(.hour, from: next)))
            cursor = next
        }
        return ticks
    }

    /// Hours between labels so that labels `labelWidth` points wide keep a `gap` between them on an axis that
    /// gives each hour `pointsPerHour`: every hour, or every second, third, fourth, sixth or twelfth hour.
    static func labelSpacing(pointsPerHour: CGFloat, labelWidth: CGFloat, gap: CGFloat) -> Int {
        [1, 2, 3, 4, 6].first { pointsPerHour * CGFloat($0) >= labelWidth + gap } ?? 12
    }
}
