import XCTest
import LodestarKit
@testable import AppCore

/// A small synthetic catalog (built from the JSON of the real data files) with objects that have the designations the
/// row texts care about, plus one comet.
private enum ObjectsFormatFixture {
    private static let loaded: Result<Catalog, Error> = Result { try ObjectsFormatFixture.makeCatalog() }

    /// The decimal separator the number formatting of `AppFormat` uses.
    static var point: String { Locale.current.decimalSeparator ?? "." }

    static func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try loaded.get().object(id: id), id)
    }

    private static func file(_ key: String, _ records: [String]) -> Data {
        Data(#"{"schema":1,"\#(key)":[\#(records.joined(separator: ","))]}"#.utf8)
    }

    private static func makeCatalog() throws -> Catalog {
        let stars = [
            // Five designations: x Ori, 24 Ori, HR 2061, HD 39801, HIP 1001.
            #"{"hip":1001,"hr":2061,"hd":39801,"f":24,"b":"x","n":"Alpha Test","c":"Ori","ra":10.0,"de":20.0,"m":0.5}"#,
            // No proper name: it is called "x Ori", its other designation is HIP 1002.
            #"{"hip":1002,"b":"x","c":"Ori","ra":11.0,"de":20.0,"m":2.0}"#,
        ]
        let deepSky = [
            #"{"id":"M31","m":31,"ngc":[224],"names":["Andromeda Galaxy"],"t":"G","ra":10.68,"de":41.27,"c":"And","vm":3.4,"maj":178,"min":63,"p":1}"#,
            #"{"id":"NGC7000","ngc":[7000],"cat":["C20","Sh2-117","B10","Mel22"],"names":["North America Nebula"],"t":"HII","ra":314.7,"de":44.3,"c":"Cyg","vm":4.0,"maj":120,"min":100,"p":2}"#,
            #"{"id":"NGC891","ngc":[891],"t":"G","ra":35.64,"de":42.35,"c":"And","vm":10.8,"maj":13,"min":3,"p":3}"#,
            // The common name differs from the designation only by case.
            #"{"id":"M45","m":45,"names":["m 45"],"t":"OCl","ra":56.75,"de":24.1,"c":"Tau","vm":1.6,"p":1}"#,
            #"{"id":"B33","names":["Horsehead Nebula"],"t":"DrkN","ra":85.25,"de":-2.46,"c":"Ori","maj":6,"min":4,"p":2}"#,
        ]
        let constellations = [
            #"{"abbr":"And","name":"Andromeda","genitive":"Andromedae","label":[10.0,40.0],"lines":[[[10.0,30.0],[20.0,40.0]]]}"#,
            #"{"abbr":"Ori","name":"Orion","genitive":"Orionis","label":[83.0,5.0],"lines":[[[80.0,0.0],[85.0,10.0]]]}"#,
            #"{"abbr":"Cyg","name":"Cygnus","genitive":"Cygni","label":[310.0,40.0],"lines":[[[300.0,30.0],[320.0,50.0]]]}"#,
        ]
        let milkyWay = [#"{"level":1,"polygons":[[[10,10],[20,10],[20,20]]],"holes":[]}"#]
        let base = try Catalog(starsData: file("stars", stars), dsosData: file("objects", deepSky),
                               constellationsData: file("constellations", constellations),
                               milkyWayData: file("levels", milkyWay))
        let orbit = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: 1, eccentricity: 0.5, inclination: 20,
                                                    argumentOfPerihelion: 30, longitudeOfAscendingNode: 40,
                                                    perihelionJulianDayTT: 2_461_000, epochJulianDayTT: 2_461_200.5))
        let magnitudes = try XCTUnwrap(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 10))
        let comet = try XCTUnwrap(SmallBody(designation: "C/2099 A1", name: "Test Comet", kind: .comet, number: nil,
                                            orbit: orbit, photometry: .comet(magnitudes)))
        return base.withSmallBodies([comet])
    }

    // MARK: Positions

    static let reference = Date(timeIntervalSince1970: 1_792_526_400) // 2026-10-20 20:00 UTC

    static func position(altitude: Double = 34.4, azimuth: Double = 135, nextRise: Date? = nil,
                         neverRises: Bool = false, noRiseInWindow: Bool = false, magnitude: Double? = nil,
                         computedAt: Date = reference, isAbove: Bool? = nil, behindSkyline: Bool = false,
                         usesSkyline: Bool = false) -> ObjectSkyPosition {
        ObjectSkyPosition(altitude: altitude, azimuth: azimuth, nextRise: nextRise, neverRises: neverRises,
                          noRiseInWindow: noRiseInWindow, magnitude: magnitude, computedAt: computedAt,
                          isAboveHorizon: isAbove ?? (altitude > 0), isBehindSkyline: behindSkyline,
                          usesSkyline: usesSkyline)
    }

    /// 2026-10-20 at the given UTC time.
    static func utc(day: Int = 20, hour: Int, minute: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.gmt
        return try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour,
                                                                 minute: minute)))
    }
}

final class ObjectsFormatTests: XCTestCase {
    private let dot = "\u{00B7}"

    // MARK: Designations

    func testTheExtraDesignationIsTheFirstOneThatDiffersFromTheName() throws {
        XCTAssertEqual(ObjectsFormat.extraDesignation(of: try ObjectsFormatFixture.object("dso.M31")), "M 31")
        XCTAssertEqual(ObjectsFormat.extraDesignation(of: try ObjectsFormatFixture.object("dso.NGC7000")), "NGC 7000")
        XCTAssertEqual(ObjectsFormat.extraDesignation(of: try ObjectsFormatFixture.object("star.hip1001")), "x Ori")
        XCTAssertEqual(ObjectsFormat.extraDesignation(of: try ObjectsFormatFixture.object("comet.C/2099 A1")), "C/2099 A1")
    }

    func testThereIsNoExtraDesignationWhenTheNameIsTheDesignation() throws {
        XCTAssertNil(ObjectsFormat.extraDesignation(of: try ObjectsFormatFixture.object("dso.NGC891")))
        XCTAssertNil(ObjectsFormat.extraDesignation(of: try ObjectsFormatFixture.object("star.hip1002")))
    }

    func testTheNameIsComparedIgnoringCase() throws {
        // The object is called "m 45" and its designation is "M 45".
        let pleiades = try ObjectsFormatFixture.object("dso.M45")
        XCTAssertEqual(pleiades.name, "m 45")
        XCTAssertEqual(pleiades.designations, ["M 45"])
        XCTAssertNil(ObjectsFormat.extraDesignation(of: pleiades))
        XCTAssertNil(ObjectsFormat.designationsLine(of: pleiades))
        XCTAssertNil(ObjectsFormat.moreDesignations(of: pleiades))
    }

    func testThereIsNoExtraDesignationWithoutDesignations() throws {
        XCTAssertNil(ObjectsFormat.extraDesignation(of: try ObjectsFormatFixture.object("planet.mars")))
        XCTAssertNil(ObjectsFormat.extraDesignation(of: try ObjectsFormatFixture.object("sun")))
    }

    func testTheDesignationsLineJoinsTheDesignationsThatDifferFromTheName() throws {
        XCTAssertEqual(ObjectsFormat.designationsLine(of: try ObjectsFormatFixture.object("dso.M31")),
                       "M 31 \(dot) NGC 224")
        XCTAssertEqual(ObjectsFormat.designationsLine(of: try ObjectsFormatFixture.object("star.hip1002")), "HIP 1002")
    }

    func testTheDesignationsLineHoldsAtMostFour() throws {
        // NGC 7000 has five designations; the fifth (Melotte 22) is left out.
        XCTAssertEqual(try ObjectsFormatFixture.object("dso.NGC7000").designations.count, 5)
        XCTAssertEqual(ObjectsFormat.designationsLine(of: try ObjectsFormatFixture.object("dso.NGC7000")),
                       "NGC 7000 \(dot) Caldwell 20 \(dot) Sh2-117 \(dot) Barnard 10")
        // The star has x Ori, 24 Ori, HR 2061, HD 39801 and HIP 1001.
        XCTAssertEqual(ObjectsFormat.designationsLine(of: try ObjectsFormatFixture.object("star.hip1001")),
                       "x Ori \(dot) 24 Ori \(dot) HR 2061 \(dot) HD 39801")
    }

    func testTheDesignationsLineIsMissingWhenThereIsNothingToAdd() throws {
        XCTAssertNil(ObjectsFormat.designationsLine(of: try ObjectsFormatFixture.object("dso.NGC891")))
        XCTAssertNil(ObjectsFormat.designationsLine(of: try ObjectsFormatFixture.object("planet.mars")))
    }

    func testMoreDesignationsSkipTheFirstOneAndHoldAtMostThree() throws {
        XCTAssertEqual(ObjectsFormat.moreDesignations(of: try ObjectsFormatFixture.object("dso.M31")), "NGC 224")
        XCTAssertEqual(ObjectsFormat.moreDesignations(of: try ObjectsFormatFixture.object("dso.NGC7000")),
                       "Caldwell 20 \(dot) Sh2-117 \(dot) Barnard 10")
    }

    func testMoreDesignationsExistOnlyForDeepSkyObjectsWithMoreThanOne() throws {
        XCTAssertNil(ObjectsFormat.moreDesignations(of: try ObjectsFormatFixture.object("dso.NGC891")))
        XCTAssertNil(ObjectsFormat.moreDesignations(of: try ObjectsFormatFixture.object("dso.B33")),
                     "Barnard 33 is the only designation and is shown as the extra one")
        XCTAssertNil(ObjectsFormat.moreDesignations(of: try ObjectsFormatFixture.object("star.hip1001")),
                     "only deep-sky objects have them")
        XCTAssertNil(ObjectsFormat.moreDesignations(of: try ObjectsFormatFixture.object("comet.C/2099 A1")))
    }

    func testTheCatalogueLineAddsTheProminenceOfADeepSkyObject() throws {
        let northAmerica = try ObjectsFormatFixture.object("dso.NGC7000")
        XCTAssertEqual(ObjectsFormat.catalogueLine(of: northAmerica, showsProminence: true),
                       "Prominent \(dot) Caldwell 20 \(dot) Sh2-117 \(dot) Barnard 10")
        XCTAssertEqual(ObjectsFormat.catalogueLine(of: northAmerica, showsProminence: false),
                       "Caldwell 20 \(dot) Sh2-117 \(dot) Barnard 10")
        let andromeda = try ObjectsFormatFixture.object("dso.M31")
        XCTAssertEqual(ObjectsFormat.catalogueLine(of: andromeda, showsProminence: true), "Showpiece \(dot) NGC 224")
        XCTAssertEqual(ObjectsFormat.catalogueLine(of: andromeda, showsProminence: false), "NGC 224")
    }

    func testTheCatalogueLineCanBeTheProminenceAlone() throws {
        XCTAssertEqual(ObjectsFormat.catalogueLine(of: try ObjectsFormatFixture.object("dso.NGC891"), showsProminence: true),
                       "Notable")
        XCTAssertEqual(ObjectsFormat.catalogueLine(of: try ObjectsFormatFixture.object("dso.B33"), showsProminence: true),
                       "Prominent")
        XCTAssertNil(ObjectsFormat.catalogueLine(of: try ObjectsFormatFixture.object("dso.NGC891"), showsProminence: false))
    }

    func testTheCatalogueLineIsEmptyForObjectsThatAreNotDeepSky() throws {
        XCTAssertNil(ObjectsFormat.catalogueLine(of: try ObjectsFormatFixture.object("star.hip1001"), showsProminence: true))
        XCTAssertNil(ObjectsFormat.catalogueLine(of: try ObjectsFormatFixture.object("planet.mars"), showsProminence: true))
        XCTAssertNil(ObjectsFormat.catalogueLine(of: try ObjectsFormatFixture.object("comet.C/2099 A1"), showsProminence: true))
    }

    // MARK: Subtitles

    func testTheSubtitleHasTypeConstellationAndMagnitude() throws {
        let point = ObjectsFormatFixture.point
        let andromeda = try ObjectsFormatFixture.object("dso.M31")
        XCTAssertEqual(ObjectsFormat.subtitle(of: andromeda, magnitude: nil), "Galaxy \(dot) Andromeda \(dot) mag 3\(point)4")
        XCTAssertEqual(ObjectsFormat.subtitle(of: try ObjectsFormatFixture.object("star.hip1001"), magnitude: nil),
                       "Star \(dot) Orion \(dot) mag 0\(point)5")
    }

    func testTheSpokenSubtitleUsesCommasAndWritesMagnitudeOut() throws {
        let point = ObjectsFormatFixture.point
        let andromeda = try ObjectsFormatFixture.object("dso.M31")
        XCTAssertEqual(ObjectsFormat.subtitle(of: andromeda, magnitude: nil, spoken: true),
                       "Galaxy, Andromeda, magnitude 3\(point)4")
    }

    func testAGivenMagnitudeReplacesTheCatalogMagnitude() throws {
        let point = ObjectsFormatFixture.point
        let andromeda = try ObjectsFormatFixture.object("dso.M31")
        XCTAssertEqual(ObjectsFormat.subtitle(of: andromeda, magnitude: 4.6, spoken: false),
                       "Galaxy \(dot) Andromeda \(dot) mag 4\(point)6")
    }

    func testTheSubtitleLeavesOutWhatIsNotKnown() throws {
        // A dark nebula has no magnitude; a planet has neither a constellation nor a catalog magnitude.
        XCTAssertEqual(ObjectsFormat.subtitle(of: try ObjectsFormatFixture.object("dso.B33"), magnitude: nil),
                       "Dark Nebula \(dot) Orion")
        XCTAssertEqual(ObjectsFormat.subtitle(of: try ObjectsFormatFixture.object("planet.mars"), magnitude: nil), "Planet")
        XCTAssertEqual(ObjectsFormat.subtitle(of: try ObjectsFormatFixture.object("dso.M45"), magnitude: nil),
                       "Open Cluster \(dot) mag 1\(ObjectsFormatFixture.point)6")
    }

    func testThePlanetGetsItsCurrentMagnitudeWithATrueMinusSign() throws {
        let point = ObjectsFormatFixture.point
        let mars = try ObjectsFormatFixture.object("planet.mars")
        XCTAssertEqual(ObjectsFormat.subtitle(of: mars, magnitude: -1.5), "Planet \(dot) mag \u{2212}1\(point)5")
        XCTAssertEqual(ObjectsFormat.subtitle(of: mars, magnitude: 1.5, spoken: true), "Planet, magnitude 1\(point)5")
        XCTAssertEqual(ObjectsFormat.subtitle(of: try ObjectsFormatFixture.object("sun"), magnitude: -26.7),
                       "Sun \(dot) mag \u{2212}26\(point)7")
    }

    func testACometOrAsteroidTakesItsSubtitleFromItsPosition() throws {
        let comet = try ObjectsFormatFixture.object("comet.C/2099 A1")
        // Before the position is known it is just the kind.
        XCTAssertEqual(ObjectsFormat.subtitle(of: comet, magnitude: nil), "Comet")
        XCTAssertEqual(ObjectsFormat.subtitle(of: comet, magnitude: nil, spoken: true), "Comet")
        // Computed, but the orbit cannot be evaluated: no current orbit.
        let withoutOrbit = ObjectsFormatFixture.position()
        XCTAssertNil(withoutOrbit.smallBody)
        XCTAssertEqual(ObjectsFormat.subtitle(of: comet, magnitude: nil, position: withoutOrbit),
                       "Comet\u{00A0}\(dot) no current orbit")
        XCTAssertEqual(ObjectsFormat.subtitle(of: comet, magnitude: nil, spoken: true, position: withoutOrbit),
                       "Comet, no current orbit")
    }

    func testACometWithAnOrbitHasItsMagnitudeAndElongationInTheSubtitle() throws {
        let comet = try ObjectsFormatFixture.object("comet.C/2099 A1")
        let observer = Observer(location: GeographicLocation(latitude: 40, longitude: -105, elevation: 1600))
        let positions = ObjectsPositionCalculator.positions(for: [comet], observer: observer,
                                                            date: ObjectsFormatFixture.reference)
        let position = try XCTUnwrap(positions[comet.id])
        let info = try XCTUnwrap(position.smallBody)
        XCTAssertEqual(ObjectsFormat.subtitle(of: comet, magnitude: nil, position: position),
                       SmallBodyText.subtitle(of: comet, info: info, isComputed: true))
        XCTAssertEqual(ObjectsFormat.subtitle(of: comet, magnitude: nil, spoken: true, position: position),
                       SmallBodyText.subtitle(of: comet, info: info, isComputed: true, spoken: true))
        XCTAssertTrue(ObjectsFormat.subtitle(of: comet, magnitude: nil, position: position).hasPrefix("Comet"))
    }

    // MARK: Altitude and direction

    func testAltitudeAndDirectionShowsAnArrowTheRoundedAltitudeAndTheCompassPoint() {
        XCTAssertEqual(ObjectsFormat.altitudeAndDirection(of: ObjectsFormatFixture.position(altitude: 34.4, azimuth: 135)),
                       "\u{2191}34\u{00B0} SE")
        XCTAssertEqual(ObjectsFormat.altitudeAndDirection(of: ObjectsFormatFixture.position(altitude: 34.6, azimuth: 135)),
                       "\u{2191}35\u{00B0} SE")
        XCTAssertEqual(ObjectsFormat.altitudeAndDirection(of: ObjectsFormatFixture.position(altitude: 0.2, azimuth: 0)),
                       "\u{2191}0\u{00B0} N")
    }

    func testAltitudeAndDirectionCoversTheCompass() {
        func text(_ azimuth: Double) -> String {
            ObjectsFormat.altitudeAndDirection(of: ObjectsFormatFixture.position(altitude: 10, azimuth: azimuth))
        }
        XCTAssertEqual(text(0), "\u{2191}10\u{00B0} N")
        XCTAssertEqual(text(45), "\u{2191}10\u{00B0} NE")
        XCTAssertEqual(text(90), "\u{2191}10\u{00B0} E")
        XCTAssertEqual(text(180), "\u{2191}10\u{00B0} S")
        XCTAssertEqual(text(202.5), "\u{2191}10\u{00B0} SSW")
        XCTAssertEqual(text(270), "\u{2191}10\u{00B0} W")
        XCTAssertEqual(text(359), "\u{2191}10\u{00B0} N")
    }

    // MARK: Rising

    func testHiddenTextTellsWhetherTheSkylineOrTheHorizonHidesTheObject() {
        XCTAssertEqual(ObjectsFormat.hiddenText(for: ObjectsFormatFixture.position(altitude: 5, isAbove: false,
                                                                                    behindSkyline: true)),
                       "Behind skyline")
        XCTAssertEqual(ObjectsFormat.hiddenText(for: ObjectsFormatFixture.position(altitude: -5)), "Below horizon")
    }

    func testAnObjectThatNeverRisesSaysSo() {
        let open = ObjectsFormatFixture.position(altitude: -50, neverRises: true)
        XCTAssertEqual(ObjectsFormat.risingText(for: open, in: .gmt), "Never rises here")
        let skyline = ObjectsFormatFixture.position(altitude: 20, neverRises: true, isAbove: false, behindSkyline: true,
                                                    usesSkyline: true)
        XCTAssertEqual(ObjectsFormat.risingText(for: skyline, in: .gmt), "Never clears the skyline")
    }

    func testAMovingObjectWithoutARisingInTheWindowSaysItWillNotRiseWithinADay() {
        let open = ObjectsFormatFixture.position(altitude: -30, noRiseInWindow: true)
        XCTAssertEqual(ObjectsFormat.risingText(for: open, in: .gmt), "Won't rise within a day")
        let skyline = ObjectsFormatFixture.position(altitude: -30, noRiseInWindow: true, usesSkyline: true)
        XCTAssertEqual(ObjectsFormat.risingText(for: skyline, in: .gmt), "Won't clear within a day")
    }

    func testNeverRisingWinsOverTheRisingTime() throws {
        let rise = try ObjectsFormatFixture.utc(hour: 22)
        let position = ObjectsFormatFixture.position(altitude: -50, nextRise: rise, neverRises: true)
        XCTAssertEqual(ObjectsFormat.risingText(for: position, in: .gmt), "Never rises here")
    }

    func testThereIsNoRisingTextWithoutARising() {
        XCTAssertNil(ObjectsFormat.risingText(for: ObjectsFormatFixture.position(altitude: -10), in: .gmt))
        XCTAssertNil(ObjectsFormat.risingText(for: ObjectsFormatFixture.position(altitude: 40), in: .gmt))
    }

    func testARisingLaterTheSameDayGivesJustTheTime() throws {
        let rise = try ObjectsFormatFixture.utc(hour: 21, minute: 30)
        let text = try XCTUnwrap(ObjectsFormat.risingText(
            for: ObjectsFormatFixture.position(altitude: -10, nextRise: rise), in: .gmt))
        XCTAssertEqual(text, "Rises " + AppFormat.time(rise, in: .gmt))
        XCTAssertTrue(text.contains("21:30") || text.contains("9:30"), text)
        XCTAssertFalse(text.contains("tomorrow"))
    }

    func testARisingTheNextDayIsCalledTomorrow() throws {
        let rise = try ObjectsFormatFixture.utc(day: 21, hour: 2, minute: 10)
        let text = try XCTUnwrap(ObjectsFormat.risingText(
            for: ObjectsFormatFixture.position(altitude: -10, nextRise: rise), in: .gmt))
        XCTAssertEqual(text, "Rises tomorrow " + AppFormat.time(rise, in: .gmt))
        XCTAssertTrue(text.contains("2:10"), text)
    }

    func testARisingTwoDaysAheadGivesTheDateAndTime() throws {
        let rise = try ObjectsFormatFixture.utc(day: 22, hour: 3)
        let text = try XCTUnwrap(ObjectsFormat.risingText(
            for: ObjectsFormatFixture.position(altitude: -10, nextRise: rise), in: .gmt))
        XCTAssertEqual(text, "Rises " + AppFormat.dateTime(rise, in: .gmt))
        XCTAssertFalse(text.contains("tomorrow"))
    }

    func testARisingBeforeTheComputationDayIsStillJustATime() throws {
        let rise = try ObjectsFormatFixture.utc(day: 19, hour: 23)
        let text = try XCTUnwrap(ObjectsFormat.risingText(
            for: ObjectsFormatFixture.position(altitude: -10, nextRise: rise), in: .gmt))
        XCTAssertEqual(text, "Rises " + AppFormat.time(rise, in: .gmt))
    }

    func testClearingTheSkylineUsesItsOwnVerb() throws {
        let today = try ObjectsFormatFixture.utc(hour: 21, minute: 30)
        let tomorrow = try ObjectsFormatFixture.utc(day: 21, hour: 2, minute: 10)
        let later = try ObjectsFormatFixture.utc(day: 23, hour: 3)
        func text(_ rise: Date) throws -> String {
            try XCTUnwrap(ObjectsFormat.risingText(
                for: ObjectsFormatFixture.position(altitude: 10, nextRise: rise, isAbove: false, behindSkyline: true,
                                                   usesSkyline: true), in: .gmt))
        }
        XCTAssertEqual(try text(today), "Clears skyline " + AppFormat.time(today, in: .gmt))
        XCTAssertEqual(try text(tomorrow), "Clears skyline tomorrow " + AppFormat.time(tomorrow, in: .gmt))
        XCTAssertEqual(try text(later), "Clears skyline " + AppFormat.dateTime(later, in: .gmt))
    }

    func testTheDayIsCountedInTheGivenTimeZone() throws {
        // 23:30 UTC on the 20th and 00:30 UTC on the 21st: tomorrow in London time, the same evening in Los Angeles.
        let computedAt = try ObjectsFormatFixture.utc(hour: 23, minute: 30)
        let rise = try ObjectsFormatFixture.utc(day: 21, hour: 0, minute: 30)
        let position = ObjectsFormatFixture.position(altitude: -10, nextRise: rise, computedAt: computedAt)
        let utc = try XCTUnwrap(ObjectsFormat.risingText(for: position, in: .gmt))
        XCTAssertTrue(utc.hasPrefix("Rises tomorrow "), utc)
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let local = try XCTUnwrap(ObjectsFormat.risingText(for: position, in: losAngeles))
        XCTAssertEqual(local, "Rises " + AppFormat.time(rise, in: losAngeles))
        XCTAssertFalse(local.contains("tomorrow"))
    }

    // MARK: Spoken summary

    func testTheSpokenSummaryNamesTheObjectItsDesignationItsTypeAndItsDesignations() throws {
        let point = ObjectsFormatFixture.point
        let andromeda = try ObjectsFormatFixture.object("dso.M31")
        XCTAssertEqual(ObjectsFormat.spokenSummary(of: andromeda, position: nil, isFavorite: false, in: .gmt),
                       "Andromeda Galaxy, M 31, Galaxy, Andromeda, magnitude 3\(point)4, NGC 224")
    }

    func testTheSpokenSummaryCanSayHowProminentTheObjectIs() throws {
        let point = ObjectsFormatFixture.point
        let andromeda = try ObjectsFormatFixture.object("dso.M31")
        XCTAssertEqual(ObjectsFormat.spokenSummary(of: andromeda, position: nil, isFavorite: false, in: .gmt,
                                                   showsProminence: true),
                       "Andromeda Galaxy, M 31, Galaxy, Andromeda, magnitude 3\(point)4, Showpiece, NGC 224")
    }

    func testTheSpokenSummaryOfAnObjectWithNothingExtra() throws {
        let point = ObjectsFormatFixture.point
        XCTAssertEqual(ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("dso.M45"), position: nil,
                                                   isFavorite: false, in: .gmt),
                       "m 45, Open Cluster, magnitude 1\(point)6")
        XCTAssertEqual(ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("planet.mars"), position: nil,
                                                   isFavorite: false, in: .gmt),
                       "Mars, Planet")
    }

    func testTheSpokenSummaryDescribesAnObjectAboveTheHorizon() throws {
        let point = ObjectsFormatFixture.point
        let position = ObjectsFormatFixture.position(altitude: 34.4, azimuth: 135)
        XCTAssertEqual(ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("dso.M31"), position: position,
                                                   isFavorite: false, in: .gmt),
                       "Andromeda Galaxy, M 31, Galaxy, Andromeda, magnitude 3\(point)4, NGC 224, "
                           + "34\u{00B0} above the horizon, southeast")
    }

    func testTheSpokenSummaryUsesThePositionsMagnitudeForAPlanet() throws {
        let point = ObjectsFormatFixture.point
        let position = ObjectsFormatFixture.position(altitude: 20, azimuth: 270, magnitude: -1.5)
        XCTAssertEqual(ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("planet.mars"), position: position,
                                                   isFavorite: false, in: .gmt),
                       "Mars, Planet, magnitude \u{2212}1\(point)5, 20\u{00B0} above the horizon, west")
    }

    func testTheSpokenSummaryOfAnObjectBelowTheHorizonSaysWhenItRises() throws {
        let rise = try ObjectsFormatFixture.utc(day: 21, hour: 2, minute: 10)
        let position = ObjectsFormatFixture.position(altitude: -20, nextRise: rise)
        let rising = try XCTUnwrap(ObjectsFormat.risingText(for: position, in: .gmt))
        let text = ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("dso.NGC891"), position: position,
                                               isFavorite: false, in: .gmt)
        XCTAssertTrue(text.hasSuffix(", Below the horizon, " + rising.lowercased()), text)
        XCTAssertTrue(text.hasPrefix("NGC 891, Galaxy, Andromeda, magnitude 10"), text)
    }

    func testTheSpokenSummaryOfAnObjectBelowTheHorizonWithoutARising() throws {
        let position = ObjectsFormatFixture.position(altitude: -20)
        let text = ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("dso.NGC891"), position: position,
                                               isFavorite: false, in: .gmt)
        XCTAssertTrue(text.hasSuffix(", Below the horizon"), text)
    }

    func testTheSpokenSummaryOfAnObjectThatNeverRisesSaysSo() throws {
        let position = ObjectsFormatFixture.position(altitude: -50, neverRises: true)
        let text = ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("dso.M45"), position: position,
                                               isFavorite: false, in: .gmt)
        XCTAssertTrue(text.hasSuffix(", Below the horizon, never rises here"), text)
    }

    func testTheSpokenSummaryOfAnObjectBehindTheSkyline() throws {
        let rise = try ObjectsFormatFixture.utc(hour: 22)
        let position = ObjectsFormatFixture.position(altitude: 8, nextRise: rise, isAbove: false, behindSkyline: true,
                                                     usesSkyline: true)
        let text = ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("dso.M45"), position: position,
                                               isFavorite: false, in: .gmt)
        XCTAssertTrue(text.hasSuffix(", Behind the skyline, clears skyline " + AppFormat.time(rise, in: .gmt).lowercased()), text)
    }

    func testTheSpokenSummaryEndsWithFavoriteForAFavorite() throws {
        let plain = ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("planet.mars"), position: nil,
                                                isFavorite: false, in: .gmt)
        let favorite = ObjectsFormat.spokenSummary(of: try ObjectsFormatFixture.object("planet.mars"), position: nil,
                                                   isFavorite: true, in: .gmt)
        XCTAssertEqual(favorite, plain + ", Favorite")
        let positioned = ObjectsFormat.spokenSummary(
            of: try ObjectsFormatFixture.object("planet.mars"), position: ObjectsFormatFixture.position(altitude: 20, azimuth: 0),
            isFavorite: true, in: .gmt)
        XCTAssertTrue(positioned.hasSuffix("above the horizon, north, Favorite"), positioned)
    }

    func testTheSpokenSummaryOfACometUsesItsCommonName() throws {
        let comet = try ObjectsFormatFixture.object("comet.C/2099 A1")
        XCTAssertEqual(ObjectsFormat.spokenSummary(of: comet, position: nil, isFavorite: false, in: .gmt),
                       "Test Comet, C/2099 A1, Comet")
        XCTAssertEqual(ObjectsFormat.spokenSummary(of: comet, position: nil, isFavorite: true, in: .gmt),
                       "Test Comet, C/2099 A1, Comet, Favorite")
    }
}
