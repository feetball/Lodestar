import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The guide texts of the events of Jupiter (the Great Red Spot, the moons) and of the planets' stations.
final class EventsGuideJupiterTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_786_564_800)

    private func makeGuide(_ details: EventDetails, southern: Bool = false) -> EventsGuide {
        let event = AstronomicalEvent(date: moment, details: details, visibility: nil)
        return EventsGuide.make(for: EventsEntry(event: event, moonInterference: nil), isSouthernHemisphere: southern)
    }

    private func moonGuide(_ moon: GalileanMoon = .io, _ phenomenon: GalileanPhenomenon) -> EventsGuide {
        makeGuide(.jupiterMoonEvent(GalileanMoonEvent(moon: moon, phenomenon: phenomenon, edge: .start, date: moment)))
    }

    // MARK: The Great Red Spot

    func testTheGreatRedSpotGuideExplainsTheTransitAndHowToTimeTheSession() {
        let details = EventDetails.greatRedSpotTransit(GreatRedSpotTransit(
            date: moment, longitude: 91, wellPlaced: DateInterval(start: moment.addingTimeInterval(-3_000), duration: 6_000)))
        let guide = makeGuide(details)
        XCTAssertTrue(guide.about.hasPrefix("The Great Red Spot is a storm in Jupiter"))
        XCTAssertTrue(guide.about.contains("9 hours 56 minutes"))
        XCTAssertTrue(guide.why.contains("within about 50 minutes of its transit"))
        XCTAssertEqual(guide.tips.count, 4)
        XCTAssertEqual(guide.tips.first, "Start recording 50 minutes before the transit time and stop 50 minutes after it.")
        XCTAssertTrue(guide.tips[1].contains("36\u{00B0} an hour"))
        XCTAssertTrue(guide.tips[3].contains("Settings"))
    }

    func testTheGreatRedSpotGuideIsTheSameInBothHemispheres() {
        let details = EventDetails.greatRedSpotTransit(GreatRedSpotTransit(
            date: moment, longitude: 91, wellPlaced: DateInterval(start: moment, duration: 6_000)))
        XCTAssertEqual(makeGuide(details, southern: false), makeGuide(details, southern: true))
    }

    // MARK: The moons

    func testATransitGuideSaysTheMoonIsHardToSeeAndTheShadowIsTheBetterTarget() {
        let guide = moonGuide(.europa, .transit)
        XCTAssertTrue(guide.about.hasPrefix("Europa passes in front of Jupiter."))
        XCTAssertTrue(guide.about.contains("its shadow is the better target"))
    }

    func testAShadowTransitGuideDescribesTheBlackDot() {
        let guide = moonGuide(.ganymede, .shadowTransit)
        XCTAssertTrue(guide.about.hasPrefix("The shadow of Ganymede falls on Jupiter"))
        XCTAssertTrue(guide.about.contains("small, sharp black dot"))
    }

    func testAnOccultationGuideSaysTheMoonIsHiddenByTheDisc() {
        let guide = moonGuide(.callisto, .occultation)
        XCTAssertTrue(guide.about.hasPrefix("Callisto passes behind Jupiter and is hidden by the disc"))
    }

    func testAnEclipseGuideSaysTheMoonFadesInJupitersShadow() {
        let guide = moonGuide(.io, .eclipse)
        XCTAssertTrue(guide.about.hasPrefix("Io moves into Jupiter\u{2019}s shadow and fades from view"))
    }

    func testEveryMoonGuideStatesTheAccuracyOfTheTimesAndHasThreeTips() {
        for phenomenon in GalileanPhenomenon.allCases {
            let guide = moonGuide(.io, phenomenon)
            XCTAssertTrue(guide.about.hasSuffix("Times are worked out with a simple method and are good to about 5 minutes."),
                          "\(phenomenon)")
            XCTAssertFalse(guide.why.isEmpty)
            XCTAssertEqual(guide.tips.count, 3, "\(phenomenon)")
        }
    }

    // MARK: The stations

    func testAStationThatBeginsTheRetrogradeLoopNamesThePlanetAndTheWestwardTurn() {
        let guide = makeGuide(.planetStation(PlanetStation(planet: .mars, kind: .retrogradeBegins, longitude: 120)))
        XCTAssertTrue(guide.about.hasPrefix("Mars stands still among the stars for a few days: its eastward motion stops "
                                            + "and it starts to move west."))
        XCTAssertTrue(guide.why.contains("photograph the same star field every week or two"))
        XCTAssertEqual(guide.tips.count, 3)
    }

    func testAStationThatEndsTheLoopSaysTheMotionTurnsEastAgain() {
        let guide = makeGuide(.planetStation(PlanetStation(planet: .jupiter, kind: .directMotionResumes, longitude: 300)))
        XCTAssertTrue(guide.about.hasPrefix("Jupiter stands still among the stars for a few days: its westward motion stops "
                                            + "and it moves east again."))
        XCTAssertTrue(guide.about.contains("the Earth overtakes it, or it overtakes us"))
    }
}
