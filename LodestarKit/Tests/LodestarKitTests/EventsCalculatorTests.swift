import XCTest
@testable import LodestarKit

/// The calendar as a whole: kinds, options, ordering, bounds, visibility and aim targets.
final class EventsCalculatorTests: XCTestCase {
    private typealias Support = EventsTestSupport

    private let year2026 = (from: EventsTestSupport.utc("2026-01-01T00:00:00Z"), to: EventsTestSupport.utc("2026-12-31T23:59:59Z"))

    private func count(_ events: [AstronomicalEvent], _ kind: EventKind) -> Int { events.filter { $0.kind == kind }.count }

    /// `true` for events without a visibility and for those the observer can see.
    private func canBeSeen(_ event: AstronomicalEvent) -> Bool {
        guard let visibility = event.visibility else { return true }
        return visibility.isObservable
    }

    func testTheYear2026HoldsTheExpectedEvents() {
        let events = EventCalculator.events(from: year2026.from, to: year2026.to)
        XCTAssertEqual(count(events, .meteorShower), 18)
        XCTAssertEqual(count(events, .season), 4)
        XCTAssertEqual(count(events, .lunarEclipse), 2)
        XCTAssertEqual(count(events, .solarEclipse), 2)
        // Jupiter 10 Jan, Neptune 26 Sep, Saturn 4 Oct, Uranus 25 Nov (Mars has no opposition in 2026).
        XCTAssertEqual(count(events, .opposition), 4)
        // Mercury 19 Feb E, 3 Apr W, 15 Jun E, 2 Aug W, 12 Oct E, 20 Nov W and Venus 15 Aug E.
        XCTAssertEqual(count(events, .greatestElongation), 7)
        XCTAssertEqual(count(events, .fullMoonSpecial), 6)
        XCTAssertEqual(count(events, .earthApsis), 0)
        XCTAssertTrue((100...140).contains(count(events, .conjunction)))
        XCTAssertTrue(events.allSatisfy { $0.visibility == nil })
    }

    func testEventsAreSortedByDateWithTiesByKind() {
        let events = EventCalculator.events(from: year2026.from, to: year2026.to)
        let order = EventKind.allCases
        for index in 1..<events.count {
            let previous = events[index - 1]
            let current = events[index]
            XCTAssertTrue(current.date >= previous.date)
            if current.date == previous.date {
                XCTAssertTrue((order.firstIndex(of: current.kind) ?? 0) >= (order.firstIndex(of: previous.kind) ?? 0))
            }
        }
        XCTAssertTrue(events.allSatisfy { $0.date >= year2026.from && $0.date <= year2026.to })
    }

    func testKindsSelectTheFinders() {
        for kind in EventKind.allCases {
            let events = EventCalculator.events(from: year2026.from, to: year2026.to, observer: nil, options: EventOptions(kinds: [kind]))
            XCTAssertTrue(!events.isEmpty || kind == .earthApsis, kind.rawValue)
            XCTAssertTrue(events.allSatisfy { $0.kind == kind }, kind.rawValue)
        }
        XCTAssertTrue(EventCalculator.events(from: year2026.from, to: year2026.to, observer: nil, options: EventOptions(kinds: [])).isEmpty)
        let two = EventCalculator.events(from: year2026.from, to: year2026.to, observer: nil,
                                         options: EventOptions(kinds: [.lunarEclipse, .solarEclipse]))
        XCTAssertEqual(two.count, 4)
        XCTAssertEqual(two.map(\.kind), [.solarEclipse, .lunarEclipse, .solarEclipse, .lunarEclipse])
    }

    func testTheCalculatorAgreesWithTheFinders() {
        let all = EventCalculator.events(from: year2026.from, to: year2026.to)
        XCTAssertEqual(LunarEclipseFinder.events(from: year2026.from, to: year2026.to), all.filter { $0.kind == .lunarEclipse })
        XCTAssertEqual(FullMoonSpecialFinder.events(from: year2026.from, to: year2026.to), all.filter { $0.kind == .fullMoonSpecial })
        XCTAssertEqual(SeasonFinder.events(from: year2026.from, to: year2026.to), all.filter { $0.kind == .season })
        XCTAssertEqual(MeteorShowerFinder.events(from: year2026.from, to: year2026.to), all.filter { $0.kind == .meteorShower })
        XCTAssertEqual(ConjunctionFinder.events(from: year2026.from, to: year2026.to), all.filter { $0.kind == .conjunction })
        // Running it twice gives the same list.
        XCTAssertEqual(all, EventCalculator.events(from: year2026.from, to: year2026.to))
    }

    func testInvalidAndLongRanges() {
        let moment = Support.utc("2026-03-20T14:46:00Z")
        XCTAssertTrue(EventCalculator.events(from: moment, to: moment.addingTimeInterval(-1)).isEmpty)
        XCTAssertTrue(EventCalculator.events(from: moment, to: moment).isEmpty)
        // A range of a century is cut to ten years: 40 seasons, not 400.
        let seasons = EventOptions(kinds: [.season])
        let start = Support.utc("2026-01-01T00:00:00Z")
        let long = EventCalculator.events(from: start, to: Support.utc("2126-01-01T00:00:00Z"), observer: nil, options: seasons)
        XCTAssertTrue((39...41).contains(long.count), "\(long.count)")
        XCTAssertTrue((long.last?.date ?? .distantFuture) <= start.addingTimeInterval(EventCalculator.maximumSpanDays * 86_400))
        XCTAssertEqual(EventCalculator.maximumSpanDays, 3_660.0)
        // A non-finite instant gives nothing.
        XCTAssertTrue(EventCalculator.events(from: Date(timeIntervalSince1970: .infinity), to: Date(timeIntervalSince1970: .infinity)).isEmpty)
        XCTAssertTrue(EventCalculator.events(from: Date(timeIntervalSince1970: -.infinity), to: moment).isEmpty)
        XCTAssertTrue(EventCalculator.events(from: Date(timeIntervalSince1970: .nan), to: moment).isEmpty)
    }

    func testExtremeDatesAreHandled() {
        // The calculator works in the years 1 to 4001; anything outside gives an empty list, inside it computes.
        let outside = Date(timeIntervalSince1970: -1.6e11)
        let farFuture = Date(timeIntervalSince1970: 1.0e11)
        XCTAssertTrue(EventCalculator.events(from: outside, to: outside.addingTimeInterval(86_400 * 400)).isEmpty)
        XCTAssertTrue(EventCalculator.events(from: farFuture, to: farFuture.addingTimeInterval(86_400)).isEmpty)
        XCTAssertTrue(EventCalculator.events(from: Date.distantPast.addingTimeInterval(-86_400),
                                             to: Date.distantPast.addingTimeInterval(86_400)).isEmpty)
        let seasons = EventOptions(kinds: [.season, .lunarEclipse, .meteorShower])
        let early = EventCalculator.events(from: Date.distantPast.addingTimeInterval(86_400 * 30),
                                           to: Date.distantPast.addingTimeInterval(86_400 * 400),
                                           observer: Support.dallas.observer, options: seasons)
        XCTAssertEqual(count(early, .season), 4)
        let late = EventCalculator.events(from: Date.distantFuture.addingTimeInterval(-86_400 * 400),
                                          to: Date.distantFuture.addingTimeInterval(-86_400 * 30),
                                          observer: Support.dallas.observer, options: seasons)
        XCTAssertEqual(count(late, .season), 4)
        XCTAssertTrue(count(late, .meteorShower) > 10)
    }

    func testOptionsAreNormalized() {
        let defaults = EventOptions()
        XCTAssertEqual(defaults.kinds, EventKind.defaultKinds)
        XCTAssertEqual(defaults.planetConjunctionThreshold, 3.0)
        XCTAssertEqual(defaults.moonConjunctionThreshold, 5.0)
        XCTAssertEqual(defaults.minimumSolarElongation, 10.0)
        XCTAssertEqual(defaults.minimumAltitude, 10.0)
        XCTAssertNil(defaults.timeZone)
        XCTAssertFalse(defaults.visibleOnly)
        XCTAssertEqual(defaults, EventOptions())
        let bad = EventOptions(planetConjunctionThreshold: .nan, moonConjunctionThreshold: .infinity,
                               minimumSolarElongation: -4, minimumAltitude: 200)
        XCTAssertEqual(bad.planetConjunctionThreshold, 3.0)
        XCTAssertEqual(bad.moonConjunctionThreshold, 5.0)
        XCTAssertEqual(bad.minimumSolarElongation, 0.0)
        XCTAssertEqual(bad.minimumAltitude, 90.0)
        XCTAssertEqual(EventOptions(planetConjunctionThreshold: 99).planetConjunctionThreshold, 30.0)
    }

    func testEventKindRawValuesAndCodable() throws {
        XCTAssertEqual(EventKind.allCases.map(\.rawValue),
                       ["meteorShower", "conjunction", "opposition", "greatestElongation", "earthApsis", "season",
                        "fullMoonSpecial", "lunarEclipse", "solarEclipse"])
        for kind in EventKind.allCases {
            XCTAssertEqual(EventKind(rawValue: kind.rawValue), kind)
            let encoded = String(decoding: try JSONEncoder().encode(kind), as: UTF8.self)
            XCTAssertEqual(encoded, "\"\(kind.rawValue)\"")
            XCTAssertEqual(try JSONDecoder().decode(EventKind.self, from: Data(encoded.utf8)), kind)
            XCTAssertFalse(kind.displayName.isEmpty)
        }
        XCTAssertNil(EventKind(rawValue: "eclipse"))
        XCTAssertEqual(EventKind.defaultKinds.count, EventKind.allCases.count - 1)
        func encoded<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
        XCTAssertEqual(try encoded(EclipseContact.p1), "\"P1\"")
        XCTAssertEqual(EclipseContact(rawValue: "maximum"), .maximum)
        XCTAssertEqual(try encoded(LunarEclipseKind.total), "\"total\"")
        XCTAssertEqual(try encoded(SolarEclipseKind.hybrid), "\"hybrid\"")
        XCTAssertEqual(try encoded(SeasonKind.juneSolstice), "\"juneSolstice\"")
    }

    func testEventTitlesAreReadable() {
        let events = EventCalculator.events(from: Support.utc("2025-01-01T00:00:00Z"), to: Support.utc("2026-12-31T23:59:59Z"),
                                            observer: nil,
                                            options: EventOptions(kinds: Set(EventKind.allCases), planetConjunctionThreshold: 1,
                                                                  moonConjunctionThreshold: 0))
        let titles = Set(events.map(\.title))
        for expected in ["Perseids peak", "Venus and Jupiter", "Mars at opposition", "Venus at greatest eastern elongation",
                         "Mercury at greatest western elongation", "Earth at perihelion", "Earth at aphelion", "June solstice",
                         "March equinox", "Micromoon and Blue Moon", "Supermoon", "Total lunar eclipse", "Partial lunar eclipse",
                         "Annular solar eclipse", "Total solar eclipse", "Saturn at opposition"] {
            XCTAssertTrue(titles.contains(expected), "missing \(expected) in \(titles)")
        }
        XCTAssertTrue(events.allSatisfy { !$0.title.isEmpty })
    }

    // MARK: Visibility

    private let dallasYear = (from: EventsTestSupport.utc("2026-10-18T00:00:00Z"), to: EventsTestSupport.utc("2027-10-18T00:00:00Z"))
    private let chicago = TimeZone(identifier: "America/Chicago")

    private func dallasEvents(_ options: EventOptions? = nil) -> [AstronomicalEvent] {
        EventCalculator.events(from: dallasYear.from, to: dallasYear.to, observer: Support.dallas.observer,
                               options: options ?? EventOptions(timeZone: chicago))
    }

    func testVisibilityComesWithAnObserver() {
        let events = dallasEvents()
        XCTAssertTrue(events.count > 100)
        for event in events {
            switch event.kind {
            case .season, .earthApsis: XCTAssertNil(event.visibility, event.kind.rawValue)
            default: XCTAssertNotNil(event.visibility, "\(event.kind.rawValue) \(event.date)")
            }
        }
        for visibility in events.compactMap(\.visibility) {
            XCTAssertEqual(visibility.isDark, visibility.sunAltitude < -18)
            XCTAssertEqual(visibility.isObservable, visibility.bestWindow != nil)
            XCTAssertEqual(visibility.bestWindow != nil, visibility.bestTime != nil)
            XCTAssertTrue(visibility.altitude >= -90 && visibility.altitude <= 90)
            XCTAssertTrue(visibility.azimuth >= 0 && visibility.azimuth < 360)
        }
    }

    func testWindowsLieInTheNightOfTheEvent() {
        let observer = Support.dallas.observer
        for event in dallasEvents() {
            guard let visibility = event.visibility, let window = visibility.bestWindow else { continue }
            guard let best = visibility.bestTime else {
                XCTFail("\(event.kind.rawValue) has a window but no best time")
                continue
            }
            XCTAssertTrue(best >= window.start && best <= window.end, "\(event.kind.rawValue) \(event.date)")
            if event.kind == .solarEclipse || event.kind == .lunarEclipse { continue }
            // Night windows: within a day of the event, with the Sun below the darkness limit and the target up.
            XCTAssertTrue(abs(Support.seconds(window.start, event.date)) < 86_400, "\(event.kind.rawValue) \(event.date) \(window.start)")
            let sun = SkyFrame(date: best, observer: observer).horizontal(of: .sun, refraction: false).altitude
            XCTAssertTrue(sun <= visibility.darknessLimit + 0.01, "\(event.kind.rawValue) \(event.date): Sun at \(sun)")
        }
    }

    func testTargetIsAboveTheMinimumAltitudeInTheWindow() {
        let observer = Support.dallas.observer
        let options = EventOptions(timeZone: chicago, minimumAltitude: 25)
        var checked = 0
        for event in dallasEvents(options) {
            guard let visibility = event.visibility, let window = visibility.bestWindow else { continue }
            let frame = SkyFrame(date: visibility.bestTime ?? window.start, observer: observer)
            let altitude: Double
            switch event.details {
            case let .meteorShower(peak): altitude = frame.horizontal(j2000: peak.radiant, properMotion: nil, refraction: false).altitude
            case let .opposition(opposition): altitude = frame.horizontal(of: opposition.planet, refraction: false).altitude
            case let .greatestElongation(elongation): altitude = frame.horizontal(of: elongation.planet, refraction: false).altitude
            case .fullMoonSpecial: altitude = frame.horizontal(of: .moon, refraction: false).altitude
            default: continue
            }
            XCTAssertTrue(altitude >= 25.0 - 0.2, "\(event.kind.rawValue) \(event.date): \(altitude)")
            checked += 1
        }
        XCTAssertTrue(checked > 10)
    }

    func testVisibleOnlyDropsWhatCannotBeSeen() {
        let all = dallasEvents()
        let visible = dallasEvents(EventOptions(timeZone: chicago, visibleOnly: true))
        XCTAssertTrue(visible.count < all.count)
        XCTAssertTrue(visible.allSatisfy { canBeSeen($0) })
        // Equinoxes and solstices have no visibility and stay.
        XCTAssertEqual(count(all, .season), count(visible, .season))
        // Everything in the full list that is observable is in the short one.
        XCTAssertEqual(all.filter { canBeSeen($0) }.count, visible.count)
        // visibleOnly means nothing without an observer.
        let without = EventCalculator.events(from: dallasYear.from, to: dallasYear.to, observer: nil, options: EventOptions(visibleOnly: true))
        XCTAssertEqual(without.count, EventCalculator.events(from: dallasYear.from, to: dallasYear.to).count)
    }

    func testVisibilityOfAnEventComputedWithoutAnObserver() throws {
        let options = EventOptions(timeZone: chicago)
        let plain = EventCalculator.events(from: dallasYear.from, to: dallasYear.to, observer: nil, options: options)
        let observed = dallasEvents(options)
        XCTAssertEqual(plain.count, observed.count)
        let observer = Support.dallas.observer
        for index in stride(from: 0, to: plain.count, by: 7) {
            XCTAssertEqual(observed[index].visibility, EventCalculator.visibility(of: plain[index], observer: observer, options: options),
                           "\(plain[index].kind) \(plain[index].date)")
        }
        // Equinoxes have none.
        let season = try XCTUnwrap(plain.first { $0.kind == .season })
        XCTAssertNil(EventCalculator.visibility(of: season, observer: observer, options: options))
        // A solar eclipse without local circumstances gets them computed on demand.
        let eclipses = EventCalculator.events(from: Support.utc("2026-08-12T00:00:00Z"), to: Support.utc("2026-08-13T00:00:00Z"),
                                              observer: nil, options: EventOptions(kinds: [.solarEclipse]))
        let burgos = try XCTUnwrap(EventCalculator.visibility(of: eclipses[0], observer: Support.burgos.observer))
        XCTAssertTrue(burgos.isObservable && burgos.contacts.count == 5)
    }

    func testTimeZoneOptionAndItsDefault() throws {
        XCTAssertEqual(EventVisibilityCalculator.defaultZone(for: nil).secondsFromGMT(), 0)
        XCTAssertEqual(EventVisibilityCalculator.defaultZone(for: Support.dallas.observer).secondsFromGMT(), -6 * 3600)
        XCTAssertEqual(EventVisibilityCalculator.defaultZone(for: Support.sydney.observer).secondsFromGMT(), 10 * 3600)
        XCTAssertEqual(EventVisibilityCalculator.defaultZone(for: Observer(location: GeographicLocation(latitude: 0, longitude: 179.9))).secondsFromGMT(), 12 * 3600)
        XCTAssertEqual(EventVisibilityCalculator.defaultZone(for: Observer(location: GeographicLocation(latitude: 0, longitude: -179.9))).secondsFromGMT(), -12 * 3600)
        // The viewing window follows the zone's night: the same event with an eastern and a western zone differs by the
        // noon-to-noon cut, but not when the event is in the middle of a night in both.
        let event = try XCTUnwrap(EventCalculator.events(from: Support.utc("2026-12-14T00:00:00Z"), to: Support.utc("2026-12-15T00:00:00Z"),
                                                         observer: nil, options: EventOptions(kinds: [.meteorShower])).first)
        let withChicago = EventCalculator.visibility(of: event, observer: Support.dallas.observer, options: EventOptions(timeZone: chicago))
        let derived = EventCalculator.visibility(of: event, observer: Support.dallas.observer, options: EventOptions())
        XCTAssertEqual(withChicago?.sunAltitude, derived?.sunAltitude)
        XCTAssertNotNil(withChicago?.bestWindow)
    }

    func testPolarObserversAndTheSouthernHemisphere() throws {
        let options = EventOptions(kinds: [.meteorShower, .opposition, .fullMoonSpecial])
        // Tromsø (69.65N) in June has no astronomical night: the Daytime Arietids (7 June) have no window and nothing breaks.
        let tromso = Observer(location: GeographicLocation(latitude: 69.65, longitude: 18.96, elevation: 0))
        let june = EventCalculator.events(from: Support.utc("2026-06-01T00:00:00Z"), to: Support.utc("2026-07-31T00:00:00Z"),
                                          observer: tromso, options: options)
        XCTAssertTrue(!june.isEmpty)
        for event in june where event.kind == .meteorShower {
            XCTAssertNil(event.visibility?.bestWindow, "\(event.date)")
        }
        // Tromsø in December has dark all day: the Geminid window is the whole night.
        let december = EventCalculator.events(from: Support.utc("2026-12-13T00:00:00Z"), to: Support.utc("2026-12-16T00:00:00Z"),
                                              observer: tromso, options: options)
        let geminids = try XCTUnwrap(december.first { $0.kind == .meteorShower }?.visibility)
        XCTAssertNotNil(geminids.bestWindow)
        // Sydney sees the Geminid radiant low in the north.
        let sydney = EventCalculator.events(from: Support.utc("2026-12-13T00:00:00Z"), to: Support.utc("2026-12-16T00:00:00Z"),
                                            observer: Support.sydney.observer, options: options)
        XCTAssertNotNil(sydney.first { $0.kind == .meteorShower })
    }

    // MARK: Aim targets

    func testAimTargetsPerKind() {
        let events = EventCalculator.events(from: year2026.from, to: year2026.to, observer: nil,
                                            options: EventOptions(kinds: Set(EventKind.allCases)))
        for event in events {
            let targets = event.aimTargets
            switch event.details {
            case let .meteorShower(peak): XCTAssertEqual(targets, [.radiant(peak.shower)])
            case let .conjunction(conjunction):
                XCTAssertEqual(targets.count, 2)
                XCTAssertEqual(targets, [conjunction.first.aimTarget, conjunction.second.aimTarget])
            case let .opposition(opposition): XCTAssertEqual(targets, [.body(opposition.planet)])
            case let .greatestElongation(elongation): XCTAssertEqual(targets, [.body(elongation.planet)])
            case .fullMoonSpecial, .lunarEclipse: XCTAssertEqual(targets, [.body(.moon)])
            case .solarEclipse: XCTAssertEqual(targets, [.body(.sun)])
            case .season, .earthApsis: XCTAssertTrue(targets.isEmpty)
            }
        }
    }

    func testAimDirectionFramesAConjunction() throws {
        // Venus and Jupiter on 2026-06-09 19:48 UT, 1.6° apart, seen from Dallas (afternoon: the numbers do not care).
        let events = EventCalculator.events(from: Support.utc("2026-06-09T12:00:00Z"), to: Support.utc("2026-06-10T00:00:00Z"), observer: nil,
                                            options: EventOptions(kinds: [.conjunction], planetConjunctionThreshold: 2, moonConjunctionThreshold: 0))
        let conjunction = try XCTUnwrap(events.first {
            if case let .conjunction(value) = $0.details { return value.first == .body(.venus) }
            return false
        })
        let frame = SkyFrame(date: conjunction.date, observer: Support.dallas.observer)
        let aim = try XCTUnwrap(conjunction.aimDirection(in: frame, refraction: false))
        let venus = frame.horizontal(of: .venus, refraction: false)
        let jupiter = frame.horizontal(of: .jupiter, refraction: false)
        let half = venus.angularSeparation(to: jupiter) / 2
        Support.assertNear(half, aim.angularSeparation(to: venus), tolerance: 0.01, "to Venus")
        Support.assertNear(half, aim.angularSeparation(to: jupiter), tolerance: 0.01, "to Jupiter")
        // One target: the target itself; none: nothing.
        let opposition = try XCTUnwrap(EventCalculator.events(from: Support.utc("2026-01-10T00:00:00Z"), to: Support.utc("2026-01-11T00:00:00Z"),
                                                              observer: nil, options: EventOptions(kinds: [.opposition])).first)
        let jupiterFrame = SkyFrame(date: opposition.date, observer: Support.dallas.observer)
        XCTAssertEqual(opposition.aimDirection(in: jupiterFrame), jupiterFrame.horizontal(of: .jupiter, refraction: true))
        let season = try XCTUnwrap(EventCalculator.events(from: Support.utc("2026-03-20T00:00:00Z"), to: Support.utc("2026-03-21T00:00:00Z"),
                                                          observer: nil, options: EventOptions(kinds: [.season])).first)
        XCTAssertNil(season.aimDirection(in: jupiterFrame))
        XCTAssertTrue(season.aimTargets.isEmpty)
    }

    func testAimTargetsResolveToTheSky() {
        let frame = SkyFrame(date: Support.utc("2026-06-09T20:00:00Z"), observer: Support.boulder.observer)
        XCTAssertEqual(AimTarget.body(.moon).horizontal(in: frame), frame.horizontal(of: .moon, refraction: true))
        let regulus = AimTarget.fixed(ReferenceStar.regulus.position, ReferenceStar.regulus.properMotion)
        XCTAssertEqual(regulus.horizontal(in: frame, refraction: false),
                       frame.horizontal(j2000: ReferenceStar.regulus.position, properMotion: ReferenceStar.regulus.properMotion, refraction: false))
    }

    // MARK: Cost

    func testAYearCostsWellUnderASecond() {
        // The brief: a whole year for one observer in well under a second on a phone. A desktop needs about 0.2 s once
        // warm (see API.md); the bound here is loose because the tests run in a debug build.
        let warmUp = EventCalculator.events(from: Support.utc("2026-10-18T00:00:00Z"), to: Support.utc("2026-11-18T00:00:00Z"),
                                            observer: Support.dallas.observer)
        XCTAssertTrue(!warmUp.isEmpty)
        let start = Date()
        let events = EventCalculator.events(from: dallasYear.from, to: dallasYear.to, observer: Support.dallas.observer)
        let seconds = Date().timeIntervalSince(start)
        XCTAssertTrue(events.count > 100)
        XCTAssertTrue(seconds < 10.0, "a year with an observer took \(seconds) s")
    }
}
