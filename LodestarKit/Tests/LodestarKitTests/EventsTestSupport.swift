import XCTest
@testable import LodestarKit

/// Sites, instants and assertions shared by the Events tests.
enum EventsTestSupport {
    /// An observing site: name, latitude, east longitude and elevation in metres.
    struct Site {
        let name: String
        let latitude: Double
        let longitude: Double
        let elevation: Double

        init(_ name: String, _ latitude: Double, _ longitude: Double, _ elevation: Double = 0) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.elevation = elevation
        }

        var observer: Observer {
            Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation))
        }
    }

    static let dallas = Site("Dallas", 32.7767, -96.7970, 150)
    static let newYork = Site("New York", 40.7128, -74.0060, 10)
    static let burgos = Site("Burgos", 42.3439, -3.6969, 860)
    static let luxor = Site("Luxor", 25.6872, 32.6396, 75)
    static let albuquerque = Site("Albuquerque", 35.0844, -106.6504, 1600)
    static let london = Site("London", 51.5074, -0.1278, 10)
    static let madrid = Site("Madrid", 40.4168, -3.7038, 650)
    static let canaryIslands = Site("Canary Islands", 28.0, -15.0, 10)
    static let antarctica = Site("Antarctica", -66.5, 110.5, 0)
    static let tokyo = Site("Tokyo", 35.0, 139.7, 10)
    static let buenosAires = Site("Buenos Aires", -34.6, -58.4, 25)
    static let losAngeles = Site("Los Angeles", 34.0522, -118.2437, 90)
    static let moscow = Site("Moscow", 55.7558, 37.6173, 150)
    static let boulder = Site("Boulder", 40.0, -105.27, 1650)
    static let sydney = Site("Sydney", -33.87, 151.21, 0)

    /// The instant of an ISO-8601 UTC string such as `2025-03-14T06:58:42Z`.
    static func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: .nan)
    }

    /// The ISO-8601 UTC string of an instant.
    static func text(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Seconds from `b` to `a`.
    static func seconds(_ a: Date, _ b: Date) -> Double { a.timeIntervalSince(b) }

    /// Asserts that `actual` is within `tolerance` seconds of the instant `expected`.
    static func assertInstant(_ expected: String, _ actual: Date?, tolerance: Double, _ label: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("\(label): no instant", file: file, line: line)
            return
        }
        let difference = seconds(actual, utc(expected))
        XCTAssertTrue(abs(difference) <= tolerance,
                      "\(label): \(text(actual)) is \(difference) s from \(expected) (tolerance \(tolerance))",
                      file: file, line: line)
    }

    /// Asserts that `actual` is within `tolerance` of `expected`.
    static func assertNear(_ expected: Double, _ actual: Double, tolerance: Double, _ label: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(abs(expected - actual) <= tolerance, "\(label): \(actual) differs from \(expected) by more than \(tolerance)",
                      file: file, line: line)
    }

    /// The meteor shower peaks among `events`, each with its event.
    static func peaks(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, MeteorShowerPeak)] {
        events.compactMap { event in
            if case let .meteorShower(peak) = event.details { return (event, peak) }
            return nil
        }
    }

    /// The conjunctions among `events`, each with its event.
    static func conjunctions(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, Conjunction)] {
        events.compactMap { event in
            if case let .conjunction(conjunction) = event.details { return (event, conjunction) }
            return nil
        }
    }

    /// The oppositions among `events`, each with its event.
    static func oppositions(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, Opposition)] {
        events.compactMap { event in
            if case let .opposition(opposition) = event.details { return (event, opposition) }
            return nil
        }
    }

    /// The greatest elongations among `events`, each with its event.
    static func elongations(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, GreatestElongation)] {
        events.compactMap { event in
            if case let .greatestElongation(elongation) = event.details { return (event, elongation) }
            return nil
        }
    }

    /// The apsides among `events`, each with its event.
    static func apsides(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, EarthApsis)] {
        events.compactMap { event in
            if case let .earthApsis(apsis) = event.details { return (event, apsis) }
            return nil
        }
    }

    /// The equinoxes and solstices among `events`, each with its event.
    static func seasons(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, Season)] {
        events.compactMap { event in
            if case let .season(season) = event.details { return (event, season) }
            return nil
        }
    }

    /// The special full Moons among `events`, each with its event.
    static func specials(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, FullMoonSpecial)] {
        events.compactMap { event in
            if case let .fullMoonSpecial(special) = event.details { return (event, special) }
            return nil
        }
    }

    /// The lunar eclipses among `events`, each with its event.
    static func lunarEclipses(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, LunarEclipse)] {
        events.compactMap { event in
            if case let .lunarEclipse(eclipse) = event.details { return (event, eclipse) }
            return nil
        }
    }

    /// The solar eclipses among `events`, each with its event.
    static func solarEclipses(_ events: [AstronomicalEvent]) -> [(AstronomicalEvent, SolarEclipse)] {
        events.compactMap { event in
            if case let .solarEclipse(eclipse) = event.details { return (event, eclipse) }
            return nil
        }
    }
}
