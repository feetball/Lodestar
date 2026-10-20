import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Features/Mount/MountAlignmentSuggestions.swift: which bright stars are offered for aligning a mount, and which of them are
/// suggested next.
final class MountNetAlignmentSuggestionsTests: XCTestCase {
    /// 2026-10-18 04:00 UTC: local sidereal time 22.76 hours in Boulder, 15.86 hours in Sydney.
    private static let night = Date(timeIntervalSince1970: 1_792_296_000)
    private static let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    private static let sydney = Observer(location: GeographicLocation(latitude: -33.8688, longitude: 151.2093, elevation: 20))
    private static let catalog = Result { try Catalog.loadBundled() }

    private func loadedCatalog() throws -> Catalog { try Self.catalog.get() }

    private func candidateIDs(_ observer: Observer, at date: Date = MountNetAlignmentSuggestionsTests.night) throws -> Set<String> {
        Set(MountAlignmentSuggestions.candidates(catalog: try loadedCatalog(), observer: observer, date: date).map(\.id))
    }

    // MARK: The constants

    func testTheLimitsAreTheOnesTheDocumentationNames() {
        XCTAssertEqual(MountAlignmentSuggestions.minimumAltitude, 25.0)
        XCTAssertEqual(MountAlignmentSuggestions.maximumAltitude, 75.0)
        XCTAssertEqual(MountAlignmentSuggestions.maximumDeclination, 80.0)
        XCTAssertEqual(MountAlignmentSuggestions.starMagnitudeLimit, 2.5)
        XCTAssertEqual(MountAlignmentSuggestions.minimumSeparation, 30.0)
        XCTAssertEqual(MountAlignmentSuggestions.count, 3)
    }

    // MARK: Which stars are candidates

    func testBrightStarsHighEnoughAreOffered() throws {
        let ids = try candidateIDs(Self.boulder)
        XCTAssertTrue(ids.contains("star.hip91262"), "Vega, 43 degrees up in the north-west")
        XCTAssertTrue(ids.contains("star.hip97649"), "Altair, 40 degrees up")
        XCTAssertTrue(ids.contains("star.hip102098"), "Deneb, 67 degrees up")
        XCTAssertTrue(ids.contains("star.hip15863"), "Mirfak, 41 degrees up")
        XCTAssertTrue(ids.contains("star.hip107315"), "Enif, 57 degrees up")
    }

    func testStarsLowerThanTwentyFiveDegreesAreLeftOut() throws {
        let ids = try candidateIDs(Self.boulder)
        XCTAssertFalse(ids.contains("star.hip24608"), "Capella is 23 degrees up")
        XCTAssertFalse(ids.contains("star.hip86032"), "Rasalhague is 17 degrees up")
    }

    func testStarsBelowTheHorizonAreLeftOut() throws {
        let ids = try candidateIDs(Self.boulder)
        XCTAssertFalse(ids.contains("star.hip69673"), "Arcturus has set")
        XCTAssertFalse(ids.contains("star.hip32349"), "Sirius has not risen")
    }

    func testStarsHigherThanSeventyFiveDegreesAreLeftOut() throws {
        let ids = try candidateIDs(Self.boulder)
        XCTAssertFalse(ids.contains("star.hip113881"), "Scheat is 77 degrees up, nearly overhead")
    }

    func testStarsCloseToThePoleAreLeftOutWhateverTheirAltitude() throws {
        // Polaris is bright and stands about 40 degrees up from Boulder, but it is 0.7 degrees from the pole.
        let ids = try candidateIDs(Self.boulder)
        XCTAssertFalse(ids.contains("star.hip11767"))
    }

    func testFaintStarsAreNeverOffered() throws {
        let candidates = MountAlignmentSuggestions.candidates(catalog: try loadedCatalog(), observer: Self.boulder, date: Self.night)
        XCTAssertFalse(candidates.isEmpty)
        for candidate in candidates {
            XCTAssertLessThanOrEqual(candidate.magnitude, 2.5, candidate.object.name)
        }
    }

    func testEveryCandidateIsInTheGoodPartOfTheSky() throws {
        for observer in [Self.boulder, Self.sydney] {
            let candidates = MountAlignmentSuggestions.candidates(catalog: try loadedCatalog(), observer: observer, date: Self.night)
            XCTAssertGreaterThan(candidates.count, 5)
            for candidate in candidates {
                XCTAssertTrue((25.0...75.0).contains(candidate.horizontal.altitude), "\(candidate.object.name) \(candidate.horizontal)")
                XCTAssertLessThanOrEqual(abs(candidate.j2000.declination), 80.0, candidate.object.name)
                XCTAssertEqual(candidate.id, candidate.object.id)
                XCTAssertEqual(candidate.j2000, candidate.object.j2000, candidate.object.name)
            }
        }
    }

    func testCandidatesComeBrightestFirst() throws {
        let candidates = MountAlignmentSuggestions.candidates(catalog: try loadedCatalog(), observer: Self.boulder, date: Self.night)
        let magnitudes = candidates.map(\.magnitude)
        XCTAssertEqual(magnitudes, magnitudes.sorted())
        XCTAssertEqual(candidates.first?.object.id, "star.hip91262", "Vega is the brightest star that is up")
    }

    func testACandidateKnowsWhereItStandsNow() throws {
        let candidates = MountAlignmentSuggestions.candidates(catalog: try loadedCatalog(), observer: Self.boulder, date: Self.night)
        let vega = try XCTUnwrap(candidates.first { $0.object.id == "star.hip91262" })
        XCTAssertEqual(vega.magnitude, 0.03, accuracy: 0.01)
        XCTAssertEqual(vega.horizontal.altitude, 43.0, accuracy: 1.5)
        XCTAssertEqual(vega.horizontal.azimuth, 289.6, accuracy: 3.0)
        XCTAssertEqual(vega.j2000.rightAscension, 279.2347, accuracy: 0.001)
        XCTAssertEqual(vega.j2000.declination, 38.7837, accuracy: 0.001)
        XCTAssertEqual(vega.object.name, "Vega")
    }

    func testAnObserverInTheSouthGetsSouthernStars() throws {
        let ids = try candidateIDs(Self.sydney)
        XCTAssertTrue(ids.contains("star.hip60718"), "Acrux, 47 degrees up")
        XCTAssertTrue(ids.contains("star.hip100751"), "Peacock, 39 degrees up")
        XCTAssertFalse(ids.contains("star.hip91262"), "Vega is 8 degrees up from Sydney")
        XCTAssertFalse(ids.contains("star.hip11767"), "Polaris never rises there")
    }

    func testTheCandidatesChangeWithTheHour() throws {
        // Twelve hours later Vega is almost down and Capella has climbed.
        let later = Self.night.addingTimeInterval(12 * 3600)
        let ids = try candidateIDs(Self.boulder, at: later)
        XCTAssertFalse(ids.contains("star.hip91262"))
        XCTAssertTrue(ids.contains("star.hip24608"), "Capella, 32 degrees up")
    }

    // MARK: Suggestions

    private func candidate(_ name: String, rightAscension: Double, declination: Double = 0, magnitude: Double,
                           altitude: Double = 50) -> MountStarCandidate {
        let place = EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
        return MountStarCandidate(object: CelestialObject.custom(name: name, j2000: place), j2000: place,
                                  horizontal: HorizontalCoordinate(azimuth: 180, altitude: altitude), magnitude: magnitude)
    }

    private func names(_ suggestions: [MountStarSuggestion]) -> [String] {
        suggestions.map(\.candidate.object.name)
    }

    func testWithNothingToChooseFromThereIsNothingToSuggest() {
        XCTAssertTrue(MountAlignmentSuggestions.suggest([], used: []).isEmpty)
        XCTAssertTrue(MountAlignmentSuggestions.suggest([], used: [EquatorialCoordinate(rightAscension: 10, declination: 10)]).isEmpty)
    }

    func testTheFirstStarIsTheBrightestOneNearFiftyDegrees() {
        let candidates = [
            candidate("B", rightAscension: 10, magnitude: 1.0),
            candidate("A", rightAscension: 20, magnitude: 0.0),
            candidate("C", rightAscension: 30, magnitude: 0.5, altitude: 80),
            candidate("D", rightAscension: 40, magnitude: 0.5),
        ]
        // Scores: A 0, D -4 (half a magnitude is 4 points), B -8, C -4 - 6 (30 degrees from 50 costs 6 points).
        XCTAssertEqual(names(MountAlignmentSuggestions.suggest(candidates, used: [], count: 4)), ["A", "D", "B", "C"])
    }

    func testBrightnessCanOutweighAHeightFarFromFifty() {
        let candidates = [
            candidate("High and plain", rightAscension: 10, magnitude: 0.0),
            candidate("Low but brilliant", rightAscension: 20, magnitude: -1.0, altitude: 20),
        ]
        // 8 points for a magnitude against 6 for being 30 degrees away from the best height.
        XCTAssertEqual(names(MountAlignmentSuggestions.suggest(candidates, used: [])), ["Low but brilliant", "High and plain"])
    }

    func testAtEqualBrightnessTheStarNearerFiftyDegreesWins() {
        let candidates = [
            candidate("Seventy", rightAscension: 10, magnitude: 1.0, altitude: 70),
            candidate("Fifty-two", rightAscension: 20, magnitude: 1.0, altitude: 52),
        ]
        XCTAssertEqual(names(MountAlignmentSuggestions.suggest(candidates, used: [])), ["Fifty-two", "Seventy"])
    }

    func testTheFirstSuggestionsHaveNoSeparation() {
        let candidates = [candidate("A", rightAscension: 10, magnitude: 0.0), candidate("B", rightAscension: 20, magnitude: 1.0)]
        for suggestion in MountAlignmentSuggestions.suggest(candidates, used: []) {
            XCTAssertNil(suggestion.separationDegrees)
        }
    }

    func testOnlyTheBestThreeAreSuggestedUnlessMoreAreAsked() {
        let candidates = (0..<6).map { candidate("Star \($0)", rightAscension: Double($0) * 10, magnitude: Double($0)) }
        XCTAssertEqual(names(MountAlignmentSuggestions.suggest(candidates, used: [])), ["Star 0", "Star 1", "Star 2"])
        XCTAssertEqual(names(MountAlignmentSuggestions.suggest(candidates, used: [], count: 1)), ["Star 0"])
        XCTAssertEqual(MountAlignmentSuggestions.suggest(candidates, used: [], count: 0).count, 0)
        XCTAssertEqual(MountAlignmentSuggestions.suggest(candidates, used: [], count: 10).count, 6)
    }

    func testFewerCandidatesThanTheCountAreAllSuggested() {
        let candidates = [candidate("Only", rightAscension: 10, magnitude: 0.0)]
        XCTAssertEqual(names(MountAlignmentSuggestions.suggest(candidates, used: [])), ["Only"])
    }

    func testAfterTheFirstStarTheFarthestOnesComeFirst() {
        let used = [EquatorialCoordinate(rightAscension: 0, declination: 0)]
        let candidates = [
            candidate("P", rightAscension: 45, magnitude: 1.0),
            candidate("Q", rightAscension: 100, magnitude: 2.0),
            candidate("R", rightAscension: 95, magnitude: 0.0),
            candidate("S", rightAscension: 30.1, magnitude: -1.0),
        ]
        // Scores: R 90 (the separation counts up to 90 degrees), Q 90 - 16 = 74, S 30.1 + 8 = 38.1, P 45 - 8 = 37.
        let suggestions = MountAlignmentSuggestions.suggest(candidates, used: used, count: 4)
        XCTAssertEqual(names(suggestions), ["R", "Q", "S", "P"])
        let separations = suggestions.compactMap(\.separationDegrees)
        XCTAssertEqual(separations.count, 4)
        XCTAssertEqual(separations[0], 95.0, accuracy: 1e-6)
        XCTAssertEqual(separations[1], 100.0, accuracy: 1e-6)
        XCTAssertEqual(separations[2], 30.1, accuracy: 1e-6)
        XCTAssertEqual(separations[3], 45.0, accuracy: 1e-6)
    }

    func testStarsCloserThanThirtyDegreesToAUsedStarAreNotSuggested() {
        let used = [EquatorialCoordinate(rightAscension: 0, declination: 0)]
        let candidates = [
            candidate("Same place", rightAscension: 0, magnitude: -2.0),
            candidate("Ten away", rightAscension: 10, magnitude: -2.0),
            candidate("Just inside", rightAscension: 29.9, magnitude: -2.0),
            candidate("Just outside", rightAscension: 30.1, magnitude: 3.0),
        ]
        XCTAssertEqual(names(MountAlignmentSuggestions.suggest(candidates, used: used)), ["Just outside"])
    }

    func testBeyondNinetyDegreesOnlyBrightnessDecides() {
        let used = [EquatorialCoordinate(rightAscension: 0, declination: 0)]
        let candidates = [
            candidate("Far and faint", rightAscension: 170, magnitude: 1.0),
            candidate("Farther is no better", rightAscension: 100, magnitude: 0.5),
        ]
        // Both count as 90 degrees away: 90 - 8 = 82 against 90 - 4 = 86.
        let suggestions = MountAlignmentSuggestions.suggest(candidates, used: used)
        XCTAssertEqual(names(suggestions), ["Farther is no better", "Far and faint"])
        // The separation that is reported is the real one.
        XCTAssertEqual(suggestions[0].separationDegrees ?? 0, 100.0, accuracy: 1e-6)
        XCTAssertEqual(suggestions[1].separationDegrees ?? 0, 170.0, accuracy: 1e-6)
    }

    func testTheNearestUsedStarCounts() {
        let used = [EquatorialCoordinate(rightAscension: 0, declination: 0), EquatorialCoordinate(rightAscension: 90, declination: 0)]
        let candidates = [
            candidate("Between", rightAscension: 45, magnitude: 0.0),
            candidate("Opposite", rightAscension: 180, magnitude: 0.0),
            candidate("Beside the second", rightAscension: 100, magnitude: -5.0),
        ]
        let suggestions = MountAlignmentSuggestions.suggest(candidates, used: used)
        // Ten degrees from the second star rules the third out however bright; 180 degrees from the first is 90 from the second.
        XCTAssertEqual(names(suggestions), ["Opposite", "Between"])
        XCTAssertEqual(suggestions[0].separationDegrees ?? 0, 90.0, accuracy: 1e-6)
        XCTAssertEqual(suggestions[1].separationDegrees ?? 0, 45.0, accuracy: 1e-6)
    }

    func testSeparationIsMeasuredOnTheSphereNotInRightAscension() {
        // Two places 60 degrees apart in right ascension but at declination 80 are only about 10 degrees apart.
        let used = [EquatorialCoordinate(rightAscension: 0, declination: 80)]
        let candidates = [candidate("Near the pole", rightAscension: 60, declination: 80, magnitude: 0.0)]
        XCTAssertTrue(MountAlignmentSuggestions.suggest(candidates, used: used).isEmpty)
    }

    func testASuggestionIsIdentifiedByItsStar() throws {
        let star = candidate("Id", rightAscension: 10, magnitude: 1.0)
        let suggestion = try XCTUnwrap(MountAlignmentSuggestions.suggest([star], used: []).first)
        XCTAssertEqual(suggestion.id, star.id)
        XCTAssertEqual(suggestion.candidate.id, star.object.id)
        XCTAssertEqual(star.id, star.object.id)
    }
}
