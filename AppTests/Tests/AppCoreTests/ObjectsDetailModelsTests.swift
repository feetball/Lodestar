import XCTest
import LodestarKit
@testable import AppCore

final class ObjectsDetailDistanceTests: XCTestCase {
    /// The digits of a formatted number, whatever the grouping and decimal separators of the language are.
    private func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    private var point: String { Locale.current.decimalSeparator ?? "." }

    func testDistancesCompareByUnitAndValue() {
        XCTAssertEqual(ObjectDetailDistance.kilometers(1), ObjectDetailDistance.kilometers(1))
        XCTAssertNotEqual(ObjectDetailDistance.kilometers(1), ObjectDetailDistance.kilometers(2))
        XCTAssertNotEqual(ObjectDetailDistance.kilometers(1), ObjectDetailDistance.astronomicalUnits(1))
        XCTAssertNotEqual(ObjectDetailDistance.astronomicalUnits(1), ObjectDetailDistance.lightYears(1))
    }

    func testKilometersAreRoundedToWholeNumbers() {
        let text = ObjectDetailDistance.kilometers(384_400.4).text
        XCTAssertTrue(text.hasSuffix(" km"), text)
        XCTAssertEqual(digits(text), "384400")
        XCTAssertFalse(text.contains(point), "no decimals: \(text)")
        XCTAssertEqual(digits(ObjectDetailDistance.kilometers(356_999.6).text), "357000")
        XCTAssertEqual(ObjectDetailDistance.kilometers(0).text, "0 km")
    }

    func testAstronomicalUnitsHaveTwoDecimals() {
        let text = ObjectDetailDistance.astronomicalUnits(1.5234).text
        XCTAssertTrue(text.hasSuffix(" AU"), text)
        XCTAssertEqual(digits(text), "152")
        XCTAssertTrue(text.contains(point), text)
        XCTAssertEqual(digits(ObjectDetailDistance.astronomicalUnits(0.9833).text), "098")
        XCTAssertEqual(digits(ObjectDetailDistance.astronomicalUnits(5).text), "500", "always two decimals")
    }

    func testMillionsOfLightYearsHaveOneDecimal() {
        let text = ObjectDetailDistance.lightYears(2_537_000).text
        XCTAssertTrue(text.hasSuffix(" million light-years"), text)
        XCTAssertEqual(digits(text), "25")
        XCTAssertTrue(text.contains(point), text)
        XCTAssertEqual(digits(ObjectDetailDistance.lightYears(1_000_000).text), "10", "1.0 million")
        XCTAssertEqual(digits(ObjectDetailDistance.lightYears(13_000_000_000).text), "130000")
    }

    func testBelowAMillionLightYearsAreWholeNumbers() {
        let text = ObjectDetailDistance.lightYears(430).text
        XCTAssertEqual(text.hasSuffix(" light-years"), true, text)
        XCTAssertFalse(text.contains("million"))
        XCTAssertEqual(digits(text), "430")
        XCTAssertEqual(digits(ObjectDetailDistance.lightYears(100).text), "100")
        XCTAssertEqual(digits(ObjectDetailDistance.lightYears(999_999).text), "999999")
        XCTAssertFalse(ObjectDetailDistance.lightYears(999_999).text.contains("million"))
    }

    func testNearbyStarsHaveAtMostOneDecimal() {
        let near = ObjectDetailDistance.lightYears(4.37).text
        XCTAssertTrue(near.hasSuffix(" light-years"), near)
        XCTAssertEqual(digits(near), "44")
        XCTAssertTrue(near.contains(point), near)
        // A whole number has no decimal.
        let whole = ObjectDetailDistance.lightYears(4.0).text
        XCTAssertEqual(digits(whole), "4")
        XCTAssertFalse(whole.contains(point), whole)
        XCTAssertEqual(digits(ObjectDetailDistance.lightYears(99.94).text), "999")
    }

    func testTheLimitBetweenTheDecimalAndTheWholeNumberFormsIsAtOneHundred() {
        XCTAssertTrue(ObjectDetailDistance.lightYears(99.4).text.contains(point))
        XCTAssertFalse(ObjectDetailDistance.lightYears(100.4).text.contains(point))
        XCTAssertEqual(digits(ObjectDetailDistance.lightYears(100.4).text), "100")
    }
}

final class ObjectsDetailFramingTests: XCTestCase {
    func testTheMosaicOverlapIsAFifth() {
        XCTAssertEqual(ObjectDetailFraming.mosaicOverlap, 0.2)
    }

    func testTheFillFractionIsTheLargerOfTheTwo() {
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 0.5, minorFraction: 0.2).fillFraction, 0.5)
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 0.3, minorFraction: 0.9).fillFraction, 0.9)
    }

    func testAnObjectFitsWhenItFillsAtMostTheWholeFrame() {
        XCTAssertTrue(ObjectDetailFraming(majorFraction: 0.5, minorFraction: 0.2).fitsInFrame)
        XCTAssertTrue(ObjectDetailFraming(majorFraction: 1.0, minorFraction: 0.2).fitsInFrame)
        XCTAssertTrue(ObjectDetailFraming(majorFraction: 0.2, minorFraction: 1.0).fitsInFrame)
        XCTAssertFalse(ObjectDetailFraming(majorFraction: 1.0001, minorFraction: 0.2).fitsInFrame)
        XCTAssertFalse(ObjectDetailFraming(majorFraction: 0.2, minorFraction: 1.5).fitsInFrame)
    }

    func testAnObjectThatFitsNeedsOnePanel() {
        let framing = ObjectDetailFraming(majorFraction: 0.5, minorFraction: 1.0)
        XCTAssertEqual(framing.longSidePanels, 1)
        XCTAssertEqual(framing.shortSidePanels, 1)
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 0, minorFraction: 0).longSidePanels, 1)
    }

    func testPanelsOverlapByAFifth() {
        // Each extra panel adds 0.8 of a frame: 1.1 needs 2, 2.0 needs 3 (1 + ceil(1.0 / 0.8) = 3), 2.7 needs 4.
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 1.1, minorFraction: 0).longSidePanels, 2)
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 1.5, minorFraction: 0).longSidePanels, 2)
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 2.0, minorFraction: 0).longSidePanels, 3)
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 2.7, minorFraction: 0).longSidePanels, 4)
    }

    func testTheTwoSidesAreCountedSeparately() {
        let framing = ObjectDetailFraming(majorFraction: 2.0, minorFraction: 1.1)
        XCTAssertEqual(framing.longSidePanels, 3)
        XCTAssertEqual(framing.shortSidePanels, 2)
        XCTAssertFalse(framing.fitsInFrame)
    }

    func testThePanelCountIsCappedAtNinetyNine() {
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 1_000, minorFraction: 0).longSidePanels, 99)
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 79.2, minorFraction: 0).longSidePanels, 99)
        XCTAssertEqual(ObjectDetailFraming(majorFraction: .infinity, minorFraction: 0).longSidePanels, 99)
    }

    func testAFractionThatIsNotANumberNeedsOnePanel() {
        XCTAssertEqual(ObjectDetailFraming(majorFraction: .nan, minorFraction: .nan).longSidePanels, 1)
    }

    func testFramingsCompareByTheirFractions() {
        XCTAssertEqual(ObjectDetailFraming(majorFraction: 0.5, minorFraction: 0.25),
                       ObjectDetailFraming(majorFraction: 0.5, minorFraction: 0.25))
        XCTAssertNotEqual(ObjectDetailFraming(majorFraction: 0.5, minorFraction: 0.25),
                          ObjectDetailFraming(majorFraction: 0.5, minorFraction: 0.3))
    }
}

final class ObjectsDetailNightModelTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_792_519_200) // 2026-10-20 18:00 UTC

    private func night(rise: TimeInterval?, transit: TimeInterval?, set: TimeInterval?,
                       sunrise: TimeInterval? = nil) -> ObjectDetailNight {
        func date(_ offset: TimeInterval?) -> Date? { offset.map { start.addingTimeInterval($0) } }
        let interval = DateInterval(start: start, duration: 86_400)
        let twilight = NightTwilight(sunset: nil, civilDusk: nil, nauticalDusk: nil, astronomicalDusk: nil,
                                     astronomicalDawn: nil, nauticalDawn: nil, civilDawn: nil, sunrise: date(sunrise),
                                     interval: interval, solarMidnight: start.addingTimeInterval(43_200),
                                     sunAltitudeAtMidnight: -40)
        return ObjectDetailNight(
            interval: interval, chartRange: interval, twilight: twilight, darkness: nil,
            events: RiseTransitSet(rise: date(rise), transit: date(transit), set: date(set), transitAltitude: 50,
                                   circumstance: .normal),
            transitAltitude: 50, samples: [], twilightBands: [], hourTicks: [], bestInDarkness: nil, appliesSkyline: false)
    }

    func testTheTimelineListsRiseTransitAndSetInOrder() {
        let timeline = night(rise: 3_600, transit: 7_200, set: 10_800).timeline
        XCTAssertEqual(timeline.map(\.kind), [.rise, .transit, .set])
        XCTAssertEqual(timeline.map(\.date), [3_600, 7_200, 10_800].map { start.addingTimeInterval($0) })
    }

    func testTheTimelineIsSortedByTimeNotByKind() {
        // An object that is up at dusk sets first and rises later; the culmination comes between.
        let timeline = night(rise: 10_800, transit: 3_600, set: 7_200).timeline
        XCTAssertEqual(timeline.map(\.kind), [.transit, .set, .rise])
    }

    func testTheTimelineLeavesOutMissingEvents() {
        XCTAssertEqual(night(rise: nil, transit: 5_000, set: nil).timeline.map(\.kind), [.transit])
        XCTAssertEqual(night(rise: 1_000, transit: nil, set: 9_000).timeline.map(\.kind), [.rise, .set])
        XCTAssertTrue(night(rise: nil, transit: nil, set: nil).timeline.isEmpty)
    }

    func testAnEventsIdentifierIsItsKind() {
        let timeline = night(rise: 1_000, transit: 2_000, set: 3_000).timeline
        XCTAssertEqual(timeline.map(\.id), ["rise", "transit", "set"])
        XCTAssertEqual(ObjectDetailEvent.Kind.rise.rawValue, "rise")
        XCTAssertEqual(ObjectDetailEvent.Kind.transit.rawValue, "transit")
        XCTAssertEqual(ObjectDetailEvent.Kind.set.rawValue, "set")
    }

    func testTheNightExpiresAtSunriseOrAtTheEndOfTheInterval() {
        let withSunrise = night(rise: nil, transit: nil, set: nil, sunrise: 46_800)
        XCTAssertEqual(withSunrise.expiry, start.addingTimeInterval(46_800))
        let withoutSunrise = night(rise: nil, transit: nil, set: nil)
        XCTAssertEqual(withoutSunrise.expiry, start.addingTimeInterval(86_400))
    }

    func testAltitudeSamplesBandsAndPeaksIdentifyThemselvesByTheirDates() {
        let date = Date(timeIntervalSince1970: 1_234)
        XCTAssertEqual(ObjectDetailAltitudeSample(date: date, altitude: 10).id, date)
        let band = ObjectDetailTwilightBand(interval: DateInterval(start: date, duration: 600), brightness: 2)
        XCTAssertEqual(band.id, date)
        XCTAssertEqual(ObjectDetailPeak(date: date, altitude: 40), ObjectDetailPeak(date: date, altitude: 40))
        XCTAssertNotEqual(ObjectDetailPeak(date: date, altitude: 40), ObjectDetailPeak(date: date, altitude: 41))
    }
}
