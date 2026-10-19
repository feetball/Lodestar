import XCTest
import LodestarKit
@testable import TonightCore

/// Places and dates shared by the widget tests.
enum TonightTestSupport {
    static let boulder = place(40.0, -105.27, 1650, "America/Denver")
    static let sydney = place(-33.87, 151.21, 20, "Australia/Sydney")
    static let tromso = place(69.65, 18.96, 10, "Europe/Oslo")
    /// Close enough to the pole for the Sun to stay below -18° all through the December solstice day.
    static let nearPole = place(85, 15, 0, "UTC")

    private static func place(_ latitude: Double, _ longitude: Double, _ elevation: Double,
                              _ zone: String) -> TonightPlace {
        guard let place = TonightPlace(latitude: latitude, longitude: longitude, elevation: elevation,
                                       timeZoneIdentifier: zone) else {
            preconditionFailure("invalid test place")
        }
        return place
    }

    /// A moment on a local calendar day.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0,
                     in place: TonightPlace) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                                hour: hour, minute: minute)))
    }

    /// The night an entry describes.
    static func night(_ entry: TonightEntry, file: StaticString = #filePath, line: UInt = #line) throws -> TonightNight {
        guard case .night(let night) = entry.content else {
            throw XCTSkip("the entry has no night", file: file, line: line)
        }
        return night
    }

    /// The summary of the night that starts on the local date of `instant`.
    static func summary(startingOn instant: Date, in place: TonightPlace) -> NightSummary {
        NightPlanner.summary(nightStartingOn: instant, observer: place.observer, timeZone: place.timeZone)
    }
}
