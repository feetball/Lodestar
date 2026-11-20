import Foundation
import XCTest
@testable import AppCore

/// While the Comets feed is off (the default) there is no comet data, so the Tonight card and the list of comets must say
/// that comets are off and where to switch them on, not that "no comet is brighter than magnitude 10" ("bright comets are
/// rare"). The decision is a pure function of whether the feed is on; the views pass `app.online.isEnabled(.comets)`.
final class FixOnlineCometsOffTests: XCTestCase {
    private let off = "Comets are switched off, so Lodestar has no comet data. Switch on Comets in Settings \u{25B8} Online Data "
        + "to see which comets are bright."

    // MARK: The Tonight card

    func testTheCardSaysCometsAreOffWhileTheFeedIsOff() {
        let message = SmallBodyTonightPlanner.emptyCardMessage(cometsAreOn: false)
        XCTAssertEqual(message, off)
        XCTAssertEqual(message, SmallBodyText.cometsOffMessage)
        XCTAssertFalse(message.contains("brighter than"))
        XCTAssertFalse(message.contains("rare"))
        // It says where to switch them on.
        XCTAssertTrue(message.contains("Settings"))
        XCTAssertTrue(message.contains("Online Data"))
        XCTAssertTrue(message.contains("Comets"))
    }

    func testTheCardKeepsItsSentenceWhileTheFeedIsOn() {
        XCTAssertEqual(SmallBodyTonightPlanner.emptyCardMessage(cometsAreOn: true),
                       "No comet is brighter than magnitude 10 tonight. That is normal; bright comets are rare.")
    }

    // MARK: The list

    func testTheListOfCometsSaysCometsAreOffWhileTheFeedIsOff() {
        for period in SmallBodyListPeriod.allCases {
            XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: period, limit: 10, kind: .comets, cometsAreOn: false), off,
                           "\(period)")
        }
        XCTAssertEqual(SmallBodyBrightLists.emptyTitle(kind: .comets, cometsAreOn: false), "Comets Are Off")
        XCTAssertEqual(SmallBodyBrightLists.emptyTitle(kind: .comets, cometsAreOn: false), SmallBodyText.cometsOffTitle)
    }

    func testTheListOfBothNamesTheAsteroidsAndSaysCometsAreOff() {
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .now, limit: 10, kind: .both, cometsAreOn: false),
                       "No asteroid is brighter than magnitude 10 right now. " + off)
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .thisMonth, limit: 8, kind: .both, cometsAreOn: false),
                       "No asteroid is brighter than magnitude 8 in the next 31 days. " + off)
        // Asteroids are listed whatever the feed does, so the title is the ordinary one.
        XCTAssertEqual(SmallBodyBrightLists.emptyTitle(kind: .both, cometsAreOn: false), "Nothing Bright")
    }

    func testTheListOfAsteroidsDoesNotDependOnTheCometsFeed() {
        for period in SmallBodyListPeriod.allCases {
            XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: period, limit: 6, kind: .asteroids, cometsAreOn: false),
                           SmallBodyBrightLists.emptyMessage(period: period, limit: 6, kind: .asteroids, cometsAreOn: true),
                           "\(period)")
        }
        XCTAssertEqual(SmallBodyBrightLists.emptyTitle(kind: .asteroids, cometsAreOn: false), "Nothing Bright")
    }

    func testTheListKeepsItsSentencesWhileTheFeedIsOn() {
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .now, limit: 10, kind: .comets, cometsAreOn: true),
                       "No comet is brighter than magnitude 10 right now. That is normal; bright comets are rare.")
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .thisMonth, limit: 8, kind: .both, cometsAreOn: true),
                       "No comet or asteroid is brighter than magnitude 8 in the next 31 days. "
                       + "That is normal; bright comets are rare.")
        XCTAssertEqual(SmallBodyBrightLists.emptyTitle(kind: .comets, cometsAreOn: true), "Nothing Bright")
        XCTAssertEqual(SmallBodyBrightLists.emptyTitle(kind: .both, cometsAreOn: true), "Nothing Bright")
    }

    func testWithoutTheFlagTheOrdinarySentencesAreUnchanged() {
        XCTAssertEqual(SmallBodyBrightLists.emptyMessage(period: .now, limit: 10, kind: .comets),
                       "No comet is brighter than magnitude 10 right now. That is normal; bright comets are rare.")
        XCTAssertEqual(SmallBodyBrightLists.emptyTitle(kind: .comets), "Nothing Bright")
    }
}
