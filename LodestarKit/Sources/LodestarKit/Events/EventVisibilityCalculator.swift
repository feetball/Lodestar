import Foundation

/// How dark the sky must be for the viewing window of an event; the values are the Sun's altitude limits.
enum DarknessLevel {
    /// After sunset (the Sun's centre below −0.8333°).
    case sunset
    /// After the end of civil twilight (below −6°).
    case civil
    /// After the end of astronomical twilight (below −18°).
    case astronomical

    /// The Sun altitude limit in degrees.
    var altitude: Double {
        switch self {
        case .sunset: RiseSetCalculator.sunHorizonAltitude
        case .civil: TwilightCalculator.civilAltitude
        case .astronomical: TwilightCalculator.astronomicalAltitude
        }
    }

    /// The part of `night` in which the Sun is below `altitude`; `nil` when it never is.
    func interval(of night: NightTwilight) -> DateInterval? {
        let dusk: Date?
        let dawn: Date?
        switch self {
        case .sunset:
            dusk = night.sunset
            dawn = night.sunrise
        case .civil:
            dusk = night.civilDusk
            dawn = night.civilDawn
        case .astronomical:
            dusk = night.astronomicalDusk
            dawn = night.astronomicalDawn
        }
        if let dusk, let dawn { return dawn > dusk ? DateInterval(start: dusk, end: dawn) : nil }
        if let dusk { return DateInterval(start: dusk, end: night.interval.end) }
        if let dawn { return DateInterval(start: night.interval.start, end: dawn) }
        return night.sunAltitudeAtMidnight < altitude ? night.interval : nil
    }
}

/// Works out how well one observer can see events. Holds the nights it has already computed, so create one per run and
/// do not share it between threads.
final class EventVisibilityCalculator {
    private static let windowStep = 15.0 / 1440
    private static let eclipseStep = 5.0 / 1440

    private let observer: Observer
    private let options: EventOptions
    private let timeZone: TimeZone
    private var nights = [Date: NightTwilight]()

    init(observer: Observer, options: EventOptions, timeZone: TimeZone) {
        self.observer = observer
        self.options = options
        self.timeZone = timeZone
    }

    /// The zone used when the options name none: UTC without an observer, else the whole-hour offset nearest the longitude.
    static func defaultZone(for observer: Observer?) -> TimeZone {
        guard let observer else { return .gmt }
        let hours = (observer.location.longitude / 15).rounded(.toNearestOrAwayFromZero)
        guard hours.isFinite else { return .gmt }
        return TimeZone(secondsFromGMT: Int(AstroMath.clamp(hours, -12, 12)) * 3600) ?? .gmt
    }

    /// The visibility of `event` for the observer, or `nil` for events that are not seen in the sky.
    func visibility(of event: AstronomicalEvent) -> EventVisibility? {
        switch event.details {
        case let .meteorShower(peak):
            let position = peak.radiant
            return night(event.date, level: .astronomical) { $0.horizontal(j2000: position, properMotion: nil, refraction: false) }
        case let .conjunction(conjunction):
            return self.conjunction(event.date, conjunction)
        case let .opposition(opposition):
            return planet(event.date, opposition.planet)
        case let .greatestElongation(elongation):
            return planet(event.date, elongation.planet)
        case .fullMoonSpecial:
            return night(event.date, level: .sunset) { $0.horizontal(of: .moon, refraction: false) }
        case let .lunarEclipse(eclipse):
            return lunarEclipse(eclipse)
        case let .solarEclipse(eclipse):
            return solarEclipse(eclipse)
        case .earthApsis, .season:
            return nil
        }
    }

    private func planet(_ date: Date, _ body: SolarSystemBody) -> EventVisibility {
        night(date, level: .civil, position: fixed(.body(body), at: JulianDate(date: date)))
    }

    private func conjunction(_ date: Date, _ conjunction: Conjunction) -> EventVisibility {
        let jd = JulianDate(date: date)
        if conjunction.involvesMoon { return night(date, level: .civil, position: fixed(conjunction.second, at: jd)) }
        let first = fixed(conjunction.first, at: jd)
        let second = fixed(conjunction.second, at: jd)
        return night(date, level: .civil) { HorizontalCoordinate(vector: first($0).unitVector + second($0).unitVector) }
    }

    /// The place of a planet or star as it is at `jd`; planets keep their position for the whole night.
    private func fixed(_ target: ConjunctionTarget, at jd: JulianDate) -> (SkyFrame) -> HorizontalCoordinate {
        switch target {
        case let .body(body):
            let vector = Ephemeris.geocentricJ2000(of: body, at: jd)
            return { $0.horizontal(geocentricJ2000: vector, refraction: false) }
        case let .star(star):
            let position = star.position
            let motion = star.properMotion
            return { $0.horizontal(j2000: position, properMotion: motion, refraction: false) }
        }
    }

    /// The visibility of a subject that stays up through the night, with the window inside the dark part of the night.
    private func night(_ date: Date, level: DarknessLevel,
                       position: (SkyFrame) -> HorizontalCoordinate) -> EventVisibility {
        let frame = SkyFrame(date: date, observer: observer)
        let subject = position(frame)
        let sunAltitude = frame.horizontal(of: .sun, refraction: false).altitude
        var window: DateInterval?
        var bestTime: Date?
        if let dark = level.interval(of: twilight(date)) {
            let result = AltitudeWindow.best(start: EventSearch.ut(dark.start), end: EventSearch.ut(dark.end),
                                             step: Self.windowStep, threshold: options.minimumAltitude) {
                position(SkyFrame(julianDate: JulianDate(ut: $0), observer: observer)).altitude
            }
            if let result {
                window = DateInterval(start: EventSearch.instant(result.start), end: EventSearch.instant(result.end))
                bestTime = EventSearch.instant(result.peakTime)
            }
        }
        return EventVisibility(altitude: subject.altitude, azimuth: subject.azimuth, sunAltitude: sunAltitude,
                               isDark: sunAltitude < TwilightCalculator.astronomicalAltitude, bestWindow: window,
                               bestTime: bestTime, darknessLimit: level.altitude, contacts: [])
    }

    private func lunarEclipse(_ eclipse: LunarEclipse) -> EventVisibility {
        let horizon = RiseSetCalculator.standardHorizonAltitude
        func moon(_ time: Date) -> HorizontalCoordinate {
            SkyFrame(date: time, observer: observer).horizontal(of: .moon, refraction: false)
        }
        let contacts = eclipse.contacts.map { contact -> ContactVisibility in
            let place = moon(contact.time)
            return ContactVisibility(contact: contact.contact, time: contact.time, altitude: place.altitude,
                                     azimuth: place.azimuth)
        }
        let first = eclipse.u1 ?? eclipse.p1
        let last = eclipse.u4 ?? eclipse.p4
        let result = AltitudeWindow.best(start: EventSearch.ut(first), end: EventSearch.ut(last),
                                         step: Self.eclipseStep, threshold: horizon) {
            SkyFrame(julianDate: JulianDate(ut: $0), observer: observer).horizontal(of: .moon, refraction: false).altitude
        }
        var window: DateInterval?
        var bestTime: Date?
        if let result {
            window = DateInterval(start: EventSearch.instant(result.start), end: EventSearch.instant(result.end))
            let greatest = EventSearch.ut(eclipse.greatest)
            bestTime = greatest >= result.start && greatest <= result.end ? eclipse.greatest : EventSearch.instant(result.peakTime)
        }
        let atGreatest = moon(eclipse.greatest)
        let sunAltitude = SkyFrame(date: eclipse.greatest, observer: observer).horizontal(of: .sun, refraction: false).altitude
        return EventVisibility(altitude: atGreatest.altitude, azimuth: atGreatest.azimuth, sunAltitude: sunAltitude,
                               isDark: sunAltitude < TwilightCalculator.astronomicalAltitude, bestWindow: window,
                               bestTime: bestTime, darknessLimit: 0, contacts: contacts)
    }

    private func solarEclipse(_ eclipse: SolarEclipse) -> EventVisibility {
        let local = eclipse.local ?? SolarEclipseFinder.localCircumstances(of: eclipse, observer: observer)
        let reference = local.maximum ?? eclipse.greatest
        func sun(_ time: Date) -> HorizontalCoordinate {
            SkyFrame(date: time, observer: observer).horizontal(of: .sun, refraction: false)
        }
        var contacts = [ContactVisibility]()
        let entries: [(EclipseContact, Date?)] = [
            (.c1, local.c1), (.c2, local.c2), (.maximum, local.maximum), (.c3, local.c3), (.c4, local.c4),
        ]
        for (contact, time) in entries {
            guard let time else { continue }
            let place = sun(time)
            contacts.append(ContactVisibility(contact: contact, time: time, altitude: place.altitude, azimuth: place.azimuth))
        }
        let place = sun(reference)
        return EventVisibility(altitude: place.altitude, azimuth: place.azimuth, sunAltitude: place.altitude,
                               isDark: place.altitude < TwilightCalculator.astronomicalAltitude,
                               bestWindow: local.visibleInterval,
                               bestTime: local.visibleInterval != nil ? local.maximum : nil,
                               darknessLimit: 0, contacts: contacts)
    }

    /// The night (local noon to noon) that contains `date`. The day is decided by comparing `date` with its own local noon
    /// rather than by shifting 12 absolute hours, which lands an hour off on the 23- and 25-hour days of a time change.
    private func twilight(_ date: Date) -> NightTwilight {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let own = TwilightCalculator.nightInterval(startingOn: date, timeZone: timeZone)
        let reference = date >= own.start ? date
            : (calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400))
        let key = TwilightCalculator.nightInterval(startingOn: reference, timeZone: timeZone).start
        if let known = nights[key] { return known }
        let night = TwilightCalculator.night(startingOn: reference, observer: observer, timeZone: timeZone)
        nights[key] = night
        return night
    }
}
