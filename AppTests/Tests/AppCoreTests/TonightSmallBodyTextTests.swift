import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The words of the comet and asteroid screens (`SmallBodyText`) and what they say about a body at one instant
/// (`SmallBodyInfo`, `SmallBodyTail`, `SmallBodyDetail`).
///
/// The bodies are real MPC orbit lines of 2026-10-18, the lines of the LodestarKit tests. On 2026-10-18T12:00:00Z
/// 161P/Hartley-IRAS stands 110 degrees from the Sun at magnitude 9.7.
final class TonightSmallBodyTextTests: XCTestCase {
    private let nbsp = "\u{00A0}"
    private let dot = "\u{00B7}"
    /// 2026-10-18T12:00:00Z.
    private let noon = Date(timeIntervalSince1970: 1_792_324_800)
    /// 2026-10-19T02:00:00Z, an evening in Colorado.
    private let evening = Date(timeIntervalSince1970: 1_792_375_200)
    private let boulder = Observer(location: GeographicLocation(latitude: 40.0, longitude: -105.27, elevation: 1650))

    private func requirePointDecimals() throws {
        try XCTSkipUnless(3.4.formatted(.number.precision(.fractionLength(1))) == "3.4",
                          "numbers are not written with a decimal point in this locale")
    }

    private func requireEnglishDates() throws {
        let probe = Date(timeIntervalSince1970: 1_609_804_800)
            .formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
        try XCTSkipUnless(probe == "Jan 5, 2021", "dates are not written like \"Jan 5, 2021\" in this locale")
    }

    private func comet(_ line: String) throws -> SmallBody {
        try CometElementsParser.parseLine(line)
    }

    private func asteroid(_ line: String) throws -> SmallBody {
        try MinorPlanetElementsParser.parseLine(line)
    }

    private func hartley() throws -> SmallBody {
        try comet("0161P         2026 11 27.1783  1.265109  0.836180   47.0652    1.4736   95.7919  20261017   8.5  6.0  161P/Hartley-IRAS                                        MPEC 2026-TP0")
    }

    private func tsuchinshanAtlas() throws -> SmallBody {
        try comet("    CK23A030  2024 09 27.8337  0.391312  1.000180  308.5842   21.6759  139.0991  20261017   6.5  3.2  C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2026-O98")
    }

    private func vesta() throws -> SmallBody {
        try asteroid("00004    3.25  0.15 K2669  81.19019  151.46856  103.70135    7.14393  0.0902037  0.27161836   2.3613660  0 E2026-T23  7610 112 1821-2025 0.84 M-p 18k Pan        4000      (4) Vesta              20250624")
    }

    private func yr4() throws -> SmallBody {
        try asteroid("K24Y04R 23.93  0.15 K2669 139.21182  134.36645  271.36696    3.40806  0.6613330  0.24696810   2.5159894  1 E2026-TG8   509   2 2024-2026 0.46 M-v 3Ek Pan        0803          2024 YR4           20260226")
    }

    /// 1991 TT, an asteroid whose orbit file has no absolute magnitude.
    private func withoutMagnitude() throws -> SmallBody {
        try asteroid("J91T00T 99.99  0.15 K2669 176.22907  218.04073  192.31551   14.79902  0.1614954  0.75483638   1.1946321  7 E2026-TC5     6   1    3 days 0.86 M-v 3Ek Pan        2804          1991 TT            19911009")
    }

    private func info(_ body: SmallBody, magnitude: Double? = 7.44, elongation: Double = 62.0,
                      ageDays: Double = 1.0) -> SmallBodyInfo {
        SmallBodyInfo(body: body, earthDistanceAU: 1.2, sunDistanceAU: 1.5, elongation: elongation, phaseAngle: 40,
                      magnitude: magnitude, isPhotographable: true, elementsAgeDays: ageDays)
    }

    // MARK: Names

    func testACometAndAnAsteroidAreSmallBodiesAndACustomTargetIsNot() throws {
        XCTAssertTrue(SmallBodyText.isSmallBody(CelestialObject(smallBody: try hartley())))
        XCTAssertTrue(SmallBodyText.isSmallBody(CelestialObject(smallBody: try vesta())))
        let custom = CelestialObject.custom(name: "My target", j2000: EquatorialCoordinate(rightAscension: 10, declination: 20))
        XCTAssertFalse(SmallBodyText.isSmallBody(custom))
    }

    func testTheDisplayNameOfASmallBodyIsItsCommonNameElseItsDesignation() throws {
        XCTAssertEqual(SmallBodyText.displayName(CelestialObject(smallBody: try vesta())), "Vesta")
        XCTAssertEqual(SmallBodyText.displayName(CelestialObject(smallBody: try hartley())), "Hartley-IRAS")
        XCTAssertEqual(SmallBodyText.displayName(CelestialObject(smallBody: try tsuchinshanAtlas())), "Tsuchinshan-ATLAS")
        XCTAssertEqual(SmallBodyText.displayName(CelestialObject(smallBody: try yr4())), "2024 YR4")
    }

    func testTheDisplayNameOfAnyOtherObjectIsItsName() {
        let custom = CelestialObject.custom(name: "My target", j2000: EquatorialCoordinate(rightAscension: 10, declination: 20))
        XCTAssertEqual(SmallBodyText.displayName(custom), "My target")
    }

    func testTheKindOfAnIdentifier() {
        XCTAssertEqual(SmallBodyText.kind(ofID: "comet.12P"), .comet)
        XCTAssertEqual(SmallBodyText.kind(ofID: "comet.C/2023 A3"), .comet)
        XCTAssertEqual(SmallBodyText.kind(ofID: "asteroid.4"), .asteroid)
        XCTAssertEqual(SmallBodyText.kind(ofID: "asteroid.2024 YR4"), .asteroid)
        XCTAssertNil(SmallBodyText.kind(ofID: "dso.M31"))
        XCTAssertNil(SmallBodyText.kind(ofID: "planet.mars"))
        XCTAssertNil(SmallBodyText.kind(ofID: "comet"))
        XCTAssertNil(SmallBodyText.kind(ofID: ""))
    }

    func testTheDesignationInAnIdentifierFollowsTheFirstDot() {
        XCTAssertEqual(SmallBodyText.designation(ofID: "comet.12P"), "12P")
        XCTAssertEqual(SmallBodyText.designation(ofID: "comet.C/2023 A3"), "C/2023 A3")
        XCTAssertEqual(SmallBodyText.designation(ofID: "asteroid.2024 YR4"), "2024 YR4")
        XCTAssertEqual(SmallBodyText.designation(ofID: "comet.P/2020 K9.x"), "P/2020 K9.x")
        XCTAssertEqual(SmallBodyText.designation(ofID: "comet."), "")
    }

    func testAnIdentifierWithoutADotIsItsOwnDesignation() {
        XCTAssertEqual(SmallBodyText.designation(ofID: "nodot"), "nodot")
        XCTAssertEqual(SmallBodyText.designation(ofID: ""), "")
    }

    // MARK: Numbers

    func testMagnitudeNumberHasOneDecimalAndATrueMinusSign() throws {
        try requirePointDecimals()
        XCTAssertEqual(SmallBodyText.magnitudeNumber(7.44), "7.4")
        XCTAssertEqual(SmallBodyText.magnitudeNumber(7.46), "7.5")
        XCTAssertEqual(SmallBodyText.magnitudeNumber(12), "12.0")
        XCTAssertEqual(SmallBodyText.magnitudeNumber(0), "0.0")
        XCTAssertEqual(SmallBodyText.magnitudeNumber(-0.3), "\u{2212}0.3")
        XCTAssertEqual(SmallBodyText.magnitudeNumber(-12.34), "\u{2212}12.3")
    }

    func testAMagnitudeThatRoundsToZeroHasNoMinusSign() throws {
        try requirePointDecimals()
        XCTAssertEqual(SmallBodyText.magnitudeNumber(-0.04), "0.0")
    }

    func testMagnitudeIsWrittenAsAnEstimate() throws {
        try requirePointDecimals()
        XCTAssertEqual(SmallBodyText.magnitude(7.44), "mag \u{2248} 7.4")
        XCTAssertEqual(SmallBodyText.magnitude(-1.26), "mag \u{2248} \u{2212}1.3")
        XCTAssertEqual(SmallBodyText.magnitude(7.44, sentence: true), "mag \u{2248} 7.4")
    }

    func testAnUnknownMagnitudeSaysThereIsNoBrightnessData() {
        XCTAssertEqual(SmallBodyText.magnitude(nil), "no brightness data")
        XCTAssertEqual(SmallBodyText.magnitude(nil, sentence: true), "No brightness data")
        XCTAssertEqual(SmallBodyText.magnitude(Double.nan), "no brightness data")
        XCTAssertEqual(SmallBodyText.magnitude(Double.infinity, sentence: true), "No brightness data")
        XCTAssertEqual(SmallBodyText.magnitude(-Double.infinity), "no brightness data")
    }

    func testElongationIsWholeDegreesFromTheSun() {
        XCTAssertEqual(SmallBodyText.elongation(62.4), "62\u{00B0} from the Sun")
        XCTAssertEqual(SmallBodyText.elongation(62.6), "63\u{00B0} from the Sun")
        XCTAssertEqual(SmallBodyText.elongation(0), "0\u{00B0} from the Sun")
        XCTAssertEqual(SmallBodyText.elongation(180), "180\u{00B0} from the Sun")
    }

    // MARK: Warnings

    func testWarningsReadInsideALineAndAsASentenceOfTheirOwn() {
        XCTAssertEqual(SmallBodyText.warning(.twilightGlow), "in the twilight glow")
        XCTAssertEqual(SmallBodyText.warning(.positionApproximate), "position approximate")
        XCTAssertEqual(SmallBodyText.warning(.noBrightnessData), "no brightness data")
        XCTAssertEqual(SmallBodyText.sentence(.twilightGlow), "In the twilight glow")
        XCTAssertEqual(SmallBodyText.sentence(.positionApproximate), "Position approximate")
        XCTAssertEqual(SmallBodyText.sentence(.noBrightnessData), "No brightness data")
    }

    func testCapitalisingOnlyChangesTheFirstLetter() {
        XCTAssertEqual(SmallBodyText.capitalized("abc def"), "Abc def")
        XCTAssertEqual(SmallBodyText.capitalized("Abc"), "Abc")
        XCTAssertEqual(SmallBodyText.capitalized("x"), "X")
        XCTAssertEqual(SmallBodyText.capitalized(""), "")
        XCTAssertEqual(SmallBodyText.capitalized("1 abc"), "1 abc")
    }

    // MARK: Rows

    func testTheSubtitleHasKindMagnitudeAndElongation() throws {
        try requirePointDecimals()
        let body = try hartley()
        let text = SmallBodyText.subtitle(of: CelestialObject(smallBody: body), info: info(body), isComputed: true)
        let expected = ["Comet", "mag\(nbsp)\u{2248}\(nbsp)7.4", "62\u{00B0} from\(nbsp)the\(nbsp)Sun"]
            .joined(separator: "\(nbsp)\(dot) ")
        XCTAssertEqual(text, expected)
    }

    func testTheSubtitleOfAnAsteroidNamesTheKind() throws {
        let body = try withoutMagnitude()
        let text = SmallBodyText.subtitle(of: CelestialObject(smallBody: body), info: info(body, magnitude: nil),
                                          isComputed: true)
        XCTAssertEqual(text, ["Asteroid", "no brightness data", "62\u{00B0} from\(nbsp)the\(nbsp)Sun"]
            .joined(separator: "\(nbsp)\(dot) "))
    }

    func testTheSubtitleListsTheWarningsAfterTheNumbers() throws {
        let body = try hartley()
        // 20 degrees from the Sun, and elements 100 days old (a comet's limit is 60).
        let warned = info(body, magnitude: nil, elongation: 20, ageDays: 100)
        let text = SmallBodyText.subtitle(of: CelestialObject(smallBody: body), info: warned, isComputed: true)
        // "no brightness data" is said once, by the magnitude part, and not again as a warning.
        let expected = ["Comet", "no brightness data", "20\u{00B0} from\(nbsp)the\(nbsp)Sun", "in the twilight glow",
                        "position approximate"].joined(separator: "\(nbsp)\(dot) ")
        XCTAssertEqual(text, expected)
    }

    func testTheSubtitleCanLeaveTheWarningsOut() throws {
        let body = try hartley()
        let warned = info(body, magnitude: nil, elongation: 20, ageDays: 100)
        let text = SmallBodyText.subtitle(of: CelestialObject(smallBody: body), info: warned, isComputed: true,
                                          withWarnings: false)
        XCTAssertEqual(text, ["Comet", "no brightness data", "20\u{00B0} from\(nbsp)the\(nbsp)Sun"]
            .joined(separator: "\(nbsp)\(dot) "))
    }

    func testWithoutAnOrbitTheSubtitleSaysSoOnceThePositionIsComputed() throws {
        let object = CelestialObject(smallBody: try hartley())
        XCTAssertEqual(SmallBodyText.subtitle(of: object, info: nil, isComputed: false), "Comet")
        XCTAssertEqual(SmallBodyText.subtitle(of: object, info: nil, isComputed: true),
                       "Comet\(nbsp)\(dot) no current orbit")
    }

    func testTheSpokenSubtitleUsesCommasAndWordsInsteadOfSymbols() throws {
        try requirePointDecimals()
        let body = try hartley()
        let warned = info(body, magnitude: 7.44, elongation: 20, ageDays: 100)
        let text = SmallBodyText.subtitle(of: CelestialObject(smallBody: body), info: warned, isComputed: true,
                                          spoken: true)
        XCTAssertEqual(text, "Comet, magnitude about 7.4, 20 degrees from the Sun, in the twilight glow, position approximate")
    }

    func testTheSpokenSubtitleWithoutAnOrbit() throws {
        let object = CelestialObject(smallBody: try vesta())
        XCTAssertEqual(SmallBodyText.subtitle(of: object, info: nil, isComputed: true, spoken: true),
                       "Asteroid, no current orbit")
    }

    func testTheSummaryIsTheSubtitleOfAComputedBody() throws {
        let body = try hartley()
        let object = CelestialObject(smallBody: body)
        let known = info(body, magnitude: nil)
        XCTAssertEqual(SmallBodyText.summary(of: object, info: known),
                       SmallBodyText.subtitle(of: object, info: known, isComputed: true))
        XCTAssertEqual(SmallBodyText.summary(of: object, info: nil),
                       SmallBodyText.subtitle(of: object, info: nil, isComputed: true))
    }

    func testTheSummaryAtADateIsComputedFromTheOrbit() throws {
        try requirePointDecimals()
        let object = CelestialObject(smallBody: try hartley())
        let text = SmallBodyText.summary(of: object, at: noon)
        XCTAssertTrue(text.hasPrefix("Comet\(nbsp)\(dot) mag\(nbsp)\u{2248}\(nbsp)9.7"), text)
        XCTAssertTrue(text.hasSuffix("110\u{00B0} from\(nbsp)the\(nbsp)Sun"), text)
    }

    func testTheSummaryOfAnyOtherObjectIsJustItsKind() {
        let custom = CelestialObject.custom(name: "My target", j2000: EquatorialCoordinate(rightAscension: 10, declination: 20))
        XCTAssertEqual(SmallBodyText.summary(of: custom, at: noon), "Custom Target")
    }

    // MARK: Detail

    func testTheDateOfTheElementsIsTheCalendarDayOfTheDynamicalTimeClock() throws {
        try requireEnglishDates()
        XCTAssertEqual(SmallBodyText.elementsDate(of: try hartley()), "Oct 17, 2026")
        // Vesta's elements are for 9 June 2026 ("K2669").
        XCTAssertEqual(SmallBodyText.elementsDate(of: try vesta()), "Jun 9, 2026")
    }

    func testTailDirectionRoundsHalvesUpAndNamesTheSide() {
        XCTAssertEqual(SmallBodyText.tailDirection(0), "Straight up")
        XCTAssertEqual(SmallBodyText.tailDirection(0.4), "Straight up")
        XCTAssertEqual(SmallBodyText.tailDirection(-0.4), "Straight up")
        XCTAssertEqual(SmallBodyText.tailDirection(0.5), "1\u{00B0} to the right of up")
        XCTAssertEqual(SmallBodyText.tailDirection(-0.5), "1\u{00B0} to the left of up")
        XCTAssertEqual(SmallBodyText.tailDirection(35), "35\u{00B0} to the right of up")
        XCTAssertEqual(SmallBodyText.tailDirection(-20), "20\u{00B0} to the left of up")
        XCTAssertEqual(SmallBodyText.tailDirection(90), "90\u{00B0} to the right of up")
    }

    func testTailDirectionStraightDown() {
        XCTAssertEqual(SmallBodyText.tailDirection(180), "Straight down")
        XCTAssertEqual(SmallBodyText.tailDirection(-180), "Straight down")
        XCTAssertEqual(SmallBodyText.tailDirection(179.6), "Straight down")
        XCTAssertEqual(SmallBodyText.tailDirection(179.4), "179\u{00B0} to the right of up")
    }

    func testCameraTiltNamesTheDirectionOfTheTurn() {
        XCTAssertEqual(SmallBodyText.cameraTilt(0), "None needed")
        XCTAssertEqual(SmallBodyText.cameraTilt(0.4), "None needed")
        XCTAssertEqual(SmallBodyText.cameraTilt(-0.4), "None needed")
        XCTAssertEqual(SmallBodyText.cameraTilt(12), "12\u{00B0} clockwise")
        XCTAssertEqual(SmallBodyText.cameraTilt(-12), "12\u{00B0} counter-clockwise")
        XCTAssertEqual(SmallBodyText.cameraTilt(44.5), "45\u{00B0} clockwise")
        XCTAssertEqual(SmallBodyText.cameraTilt(-45), "45\u{00B0} counter-clockwise")
    }

    func testRoundedHalfUp() {
        XCTAssertEqual(SmallBodyText.roundedHalfUp(2.5), 3)
        XCTAssertEqual(SmallBodyText.roundedHalfUp(2.4), 2)
        XCTAssertEqual(SmallBodyText.roundedHalfUp(0), 0)
        XCTAssertEqual(SmallBodyText.roundedHalfUp(-2.5), -2)
        XCTAssertEqual(SmallBodyText.roundedHalfUp(-2.6), -3)
    }

    func testAMosaicCannotFollowAMovingBody() throws {
        let object = CelestialObject(smallBody: try vesta())
        XCTAssertEqual(SmallBodyText.mosaicRefusal(for: object),
                       "Vesta moves among the stars, so a mosaic cannot follow it. Plan a custom size instead.")
    }

    func testTextsTheAndroidAppSharesStayAsTheyAre() {
        XCTAssertEqual(SmallBodyText.noBrightnessData, "no brightness data")
        XCTAssertEqual(SmallBodyText.twilightGlow, "in the twilight glow")
        XCTAssertEqual(SmallBodyText.positionApproximate, "position approximate")
        XCTAssertEqual(SmallBodyText.noCurrentOrbit, "no current orbit")
        XCTAssertEqual(SmallBodyText.photographable, "Photographable")
        XCTAssertEqual(SmallBodyText.tailTitle, "Ion tail direction (approximate)")
        XCTAssertEqual(SmallBodyText.tailForeshortened, "Seen almost end-on, so the tail is short and hard to make out.")
        XCTAssertEqual(SmallBodyText.targetsNote,
                       "Comets and asteroids come first when they are bright and high enough tonight.")
        XCTAssertEqual(SmallBodyText.footnote,
                       "Magnitudes are estimates, good to a magnitude or two. Only bodies at least 25\u{00B0} from the Sun are listed.")
    }

    // MARK: SmallBodyInfo

    func testTheThresholdsOfTheWarnings() {
        XCTAssertEqual(SmallBodyInfo.twilightElongation, 25)
        XCTAssertEqual(SmallBodyInfo.cometElementsAgeDays, 60)
        XCTAssertEqual(SmallBodyInfo.asteroidElementsAgeDays, 365)
        XCTAssertEqual(SmallBodyInfo.maximumElementsAgeDays(of: .comet), 60)
        XCTAssertEqual(SmallBodyInfo.maximumElementsAgeDays(of: .asteroid), 365)
    }

    func testABodyJustInsideTheTwilightLimitIsInTheGlow() throws {
        let body = try hartley()
        XCTAssertTrue(info(body, elongation: 24.99).isInTwilightGlow)
        XCTAssertFalse(info(body, elongation: 25).isInTwilightGlow)
        XCTAssertFalse(info(body, elongation: 90).isInTwilightGlow)
    }

    func testCometElementsAreApproximateAfterSixtyDays() throws {
        let body = try hartley()
        XCTAssertFalse(info(body, ageDays: 60).hasApproximatePosition)
        XCTAssertTrue(info(body, ageDays: 60.001).hasApproximatePosition)
        XCTAssertFalse(info(body, ageDays: 0).hasApproximatePosition)
    }

    func testAsteroidElementsAreApproximateAfterAYear() throws {
        let body = try vesta()
        XCTAssertFalse(info(body, ageDays: 100).hasApproximatePosition, "a comet of that age would be approximate")
        XCTAssertFalse(info(body, ageDays: 365).hasApproximatePosition)
        XCTAssertTrue(info(body, ageDays: 365.001).hasApproximatePosition)
    }

    func testAMissingMagnitudeIsReported() throws {
        let body = try withoutMagnitude()
        XCTAssertTrue(info(body, magnitude: nil).hasNoBrightnessData)
        XCTAssertFalse(info(body, magnitude: 15).hasNoBrightnessData)
    }

    func testWarningsComeMostImportantFirst() throws {
        let body = try hartley()
        XCTAssertEqual(info(body, magnitude: nil, elongation: 10, ageDays: 400).warnings,
                       [.twilightGlow, .positionApproximate, .noBrightnessData])
        XCTAssertEqual(info(body, magnitude: 9, elongation: 10, ageDays: 400).warnings,
                       [.twilightGlow, .positionApproximate])
        XCTAssertEqual(info(body, magnitude: nil, elongation: 90, ageDays: 1).warnings, [.noBrightnessData])
        XCTAssertEqual(info(body, magnitude: 9, elongation: 90, ageDays: 1).warnings, [])
    }

    func testTheInfoOfACometAtADateMatchesTheEphemeris() throws {
        let body = try hartley()
        let found = try XCTUnwrap(SmallBodyInfo.compute(body, at: noon))
        let state = try XCTUnwrap(SmallBodyEphemeris.state(of: body, at: JulianDate(date: noon)))
        XCTAssertEqual(found.body, body)
        XCTAssertEqual(found.earthDistanceAU, state.distanceAU, accuracy: 1e-12)
        XCTAssertEqual(found.sunDistanceAU, state.heliocentricDistanceAU, accuracy: 1e-12)
        XCTAssertEqual(found.elongation, state.elongation, accuracy: 1e-12)
        XCTAssertEqual(found.phaseAngle, state.phaseAngle, accuracy: 1e-12)
        XCTAssertEqual(found.magnitude, state.apparentMagnitude)
        XCTAssertEqual(found.isPhotographable, state.isPhotographable())
        XCTAssertEqual(found.elementsAgeDays, abs(state.julianDate.tt - body.orbit.epochJulianDayTT), accuracy: 1e-9)
    }

    func testTheInfoOfHartleyIrasOnTheEighteenthOfOctober() throws {
        let found = try XCTUnwrap(SmallBodyInfo.compute(try hartley(), at: noon))
        XCTAssertEqual(try XCTUnwrap(found.magnitude), 9.72, accuracy: 0.05)
        XCTAssertEqual(found.elongation, 110.3, accuracy: 0.5)
        XCTAssertTrue(found.isPhotographable)
        // The elements are for 17 October 0h, a day and a half earlier.
        XCTAssertEqual(found.elementsAgeDays, 1.5, accuracy: 0.05)
        XCTAssertGreaterThan(found.earthDistanceAU, 0)
        XCTAssertGreaterThan(found.sunDistanceAU, 0)
        XCTAssertEqual(found.warnings, [])
    }

    func testTheInfoOfABodyWithoutMagnitudeParameters() throws {
        let found = try XCTUnwrap(SmallBodyInfo.compute(try withoutMagnitude(), at: noon))
        XCTAssertNil(found.magnitude)
        XCTAssertFalse(found.isPhotographable)
        XCTAssertTrue(found.warnings.contains(.noBrightnessData))
    }

    func testTheInfoAtAFrameIsTheInfoAtItsInstant() throws {
        let body = try hartley()
        let frame = SkyFrame(date: evening, observer: boulder)
        let viaFrame = try XCTUnwrap(SmallBodyInfo.compute(body, frame: frame))
        let viaDate = try XCTUnwrap(SmallBodyInfo.compute(body, at: evening))
        XCTAssertEqual(viaFrame.elongation, viaDate.elongation, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(viaFrame.magnitude), try XCTUnwrap(viaDate.magnitude), accuracy: 1e-6)
        XCTAssertEqual(viaFrame.elementsAgeDays, viaDate.elementsAgeDays, accuracy: 1e-6)
    }

    // MARK: SmallBodyTail

    func testTheCameraTiltPutsTheTailAlongASideOfTheFrame() {
        func tilt(_ angle: Double) -> Double { SmallBodyTail(angleFromVertical: angle, phaseAngle: 90).cameraTilt }
        XCTAssertEqual(tilt(0), 0, accuracy: 1e-9)
        XCTAssertEqual(tilt(30), 30, accuracy: 1e-9)
        XCTAssertEqual(tilt(44), 44, accuracy: 1e-9)
        XCTAssertEqual(tilt(46), -44, accuracy: 1e-9)
        XCTAssertEqual(tilt(90), 0, accuracy: 1e-9)
        XCTAssertEqual(tilt(135), -45, accuracy: 1e-9)
        XCTAssertEqual(tilt(180), 0, accuracy: 1e-9)
        XCTAssertEqual(tilt(-30), -30, accuracy: 1e-9)
        XCTAssertEqual(tilt(-170), 10, accuracy: 1e-9)
    }

    func testTheCameraTiltIsNeverMoreThanFortyFiveDegrees() {
        var angle = -180.0
        while angle <= 180.0 {
            let tilt = SmallBodyTail(angleFromVertical: angle, phaseAngle: 90).cameraTilt
            XCTAssertLessThanOrEqual(abs(tilt), 45.0 + 1e-9, "angle \(angle)")
            angle += 7.5
        }
    }

    func testATailSeenAlmostEndOnIsForeshortened() {
        XCTAssertEqual(SmallBodyTail.foreshortenedPhase, 15)
        func foreshortened(_ phase: Double) -> Bool {
            SmallBodyTail(angleFromVertical: 0, phaseAngle: phase).isForeshortened
        }
        XCTAssertTrue(foreshortened(0))
        XCTAssertTrue(foreshortened(14.9))
        XCTAssertFalse(foreshortened(15))
        XCTAssertFalse(foreshortened(90))
        XCTAssertFalse(foreshortened(165))
        XCTAssertTrue(foreshortened(165.1))
        XCTAssertTrue(foreshortened(180))
    }

    func testOnlyACometHasATail() throws {
        let frame = SkyFrame(date: evening, observer: boulder)
        let cometState = try XCTUnwrap(frame.state(of: try hartley()))
        let asteroidState = try XCTUnwrap(frame.state(of: try vesta()))
        let tail = try XCTUnwrap(SmallBodyTail.compute(cometState, frame: frame))
        XCTAssertNil(SmallBodyTail.compute(asteroidState, frame: frame))
        XCTAssertEqual(tail.phaseAngle, cometState.phaseAngle, accuracy: 1e-12)
        XCTAssertGreaterThan(tail.angleFromVertical, -180)
        XCTAssertLessThanOrEqual(tail.angleFromVertical, 180)
        XCTAssertEqual(tail.angleFromVertical,
                       try XCTUnwrap(SmallBodyEphemeris.tailAngleFromVertical(of: cometState, in: frame)),
                       accuracy: 1e-12)
    }

    // MARK: SmallBodyDetail

    func testTheDetailOfACometHasATail() throws {
        let frame = SkyFrame(date: evening, observer: boulder)
        let detail = try XCTUnwrap(SmallBodyDetail.compute(try hartley(), frame: frame))
        XCTAssertNotNil(detail.tail)
        let info = try XCTUnwrap(SmallBodyInfo.compute(try hartley(), frame: frame))
        XCTAssertEqual(detail.info.elongation, info.elongation, accuracy: 1e-9)
        XCTAssertEqual(detail.tail?.phaseAngle, detail.info.phaseAngle)
    }

    func testTheDetailOfAnAsteroidHasNoTail() throws {
        let frame = SkyFrame(date: evening, observer: boulder)
        let detail = try XCTUnwrap(SmallBodyDetail.compute(try vesta(), frame: frame))
        XCTAssertNil(detail.tail)
        XCTAssertEqual(detail.info.body.id, "asteroid.4")
    }
}
