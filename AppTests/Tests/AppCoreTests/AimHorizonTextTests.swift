import LodestarKit
import XCTest
@testable import AppCore

/// The words and numbers of the horizon screens: the status of a skyline, where it is highest, the stretches still to
/// sweep and the distance between two places. The coverage that is remembered per site lives in the device's
/// preferences and is only read here, for sites that cannot have anything stored.
final class AimHorizonTextTests: XCTestCase {
    private let dot = "\u{00B7}"
    private let degree = "\u{00B0}"
    private let dash = "\u{2013}"

    // MARK: Helpers

    /// A skyline at `base` degrees with the given bins raised to `altitude`.
    private func profile(raising bins: [Int], to altitude: Double, base: Double = 0) throws -> HorizonProfile {
        var values = [Double](repeating: base, count: HorizonProfile.binCount)
        for bin in bins { values[bin] = altitude }
        return try XCTUnwrap(HorizonProfile(altitudes: values))
    }

    /// A gap that starts at the lower edge of bin `first` and spans `count` bins, as the recorder reports gaps.
    private func gap(from first: Int, bins count: Int) -> AzimuthRange {
        AzimuthRange(start: Double(first) - 0.5, length: Double(count))
    }

    // MARK: Status

    func testWithoutASkylineTheHorizonIsOpen() {
        XCTAssertEqual(HorizonText.openHorizon, "Open horizon")
        XCTAssertEqual(HorizonText.status(of: nil, coverage: nil), "Open horizon")
        XCTAssertEqual(HorizonText.status(of: nil, coverage: 0.9), "Open horizon")
    }

    func testAFlatSkylineIsAnOpenHorizonWhateverTheCoverage() {
        XCTAssertEqual(HorizonText.status(of: HorizonProfile.flat, coverage: nil), "Open horizon")
        XCTAssertEqual(HorizonText.status(of: HorizonProfile.flat, coverage: 1.0), "Open horizon")
    }

    func testARecordedSkylineSaysHowMuchWasCoveredAndWhereItIsHighest() throws {
        let hill = try profile(raising: Array(85...95), to: 14)
        XCTAssertEqual(HorizonText.status(of: hill, coverage: 0.86),
                       "Recorded \(dot) 86% covered \(dot) highest 14\(degree) in the east")
    }

    func testTheCoverageIsLeftOutWhenItIsNotKnown() throws {
        let hill = try profile(raising: Array(85...95), to: 14)
        XCTAssertEqual(HorizonText.status(of: hill, coverage: nil), "Recorded \(dot) highest 14\(degree) in the east")
    }

    func testTheCoverageIsShownInWholePercents() throws {
        let hill = try profile(raising: Array(85...95), to: 14)
        XCTAssertEqual(HorizonText.status(of: hill, coverage: 0.0), "Recorded \(dot) 0% covered \(dot) highest 14\(degree) in the east")
        XCTAssertEqual(HorizonText.status(of: hill, coverage: 0.5), "Recorded \(dot) 50% covered \(dot) highest 14\(degree) in the east")
        XCTAssertEqual(HorizonText.status(of: hill, coverage: 1.0), "Recorded \(dot) 100% covered \(dot) highest 14\(degree) in the east")
    }

    func testASkylineAtOneAltitudeIsHighestAllRound() {
        XCTAssertEqual(HorizonText.status(of: HorizonProfile.constant(5), coverage: nil), "Recorded \(dot) highest 5\(degree) all round")
    }

    func testASkylineThatStaysBelowTheHorizonHasANegativeHighestPoint() {
        XCTAssertEqual(HorizonText.status(of: HorizonProfile.constant(-2), coverage: nil), "Recorded \(dot) highest \u{2212}2\(degree) all round")
    }

    func testTheStatusOfASiteFollowsItsStoredSkylineWithoutCoverage() throws {
        let hill = try profile(raising: Array(85...95), to: 14)
        let open = try XCTUnwrap(SavedSite(name: "Field", latitude: 40, longitude: -105))
        XCTAssertEqual(HorizonText.status(of: open), "Open horizon")
        // A new site has no coverage remembered, so only the skyline is described.
        let wooded = try XCTUnwrap(SavedSite(name: "Woods", latitude: 40, longitude: -105, horizon: hill))
        XCTAssertEqual(HorizonText.status(of: wooded), "Recorded \(dot) highest 14\(degree) in the east")
    }

    // MARK: Where it is highest

    func testTheHighestPlaceIsTheDirectionOfTheHighestBins() throws {
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: [90], to: 14)), "in the east")
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: [180], to: 14)), "in the south")
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: Array(260...280), to: 14)), "in the west")
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: Array(40...50), to: 14)), "in the northeast")
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: Array(220...230), to: 14)), "in the southwest")
    }

    func testAHillThatRunsThroughNorthIsInTheNorth() throws {
        // Bins 350…359 and 0…10 are one hill across the wrap from 359 to 0 degrees.
        let across = try profile(raising: Array(350...359) + Array(0...10), to: 14)
        XCTAssertEqual(HorizonText.highestPlace(across), "in the north")
        let justBefore = try profile(raising: [359], to: 14)
        XCTAssertEqual(HorizonText.highestPlace(justBefore), "in the north")
        let justAfter = try profile(raising: [1], to: 14)
        XCTAssertEqual(HorizonText.highestPlace(justAfter), "in the north")
    }

    func testOnlyTheBinsAtTheMaximumCount() throws {
        // 13.9 is a tenth below the maximum: out of the 0.05 tolerance, so only the east counts.
        var values = [Double](repeating: 0, count: HorizonProfile.binCount)
        values[90] = 14.0
        values[270] = 13.9
        let skyline = try XCTUnwrap(HorizonProfile(altitudes: values))
        XCTAssertEqual(HorizonText.highestPlace(skyline), "in the east")
    }

    func testTwoEqualPeaksOnOppositeSidesAreHighestAllRound() throws {
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: [90, 270], to: 14)), "all round")
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: [0, 90, 180, 270], to: 14)), "all round")
    }

    func testAHighStretchIsAPlaceUntilItSpreadsRoundMostOfTheCircle() throws {
        // A stretch of 280 degrees still has a clear direction (its middle) ...
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: Array(0...279), to: 14)), "in the southeast")
        // ... one of 300 degrees averages out to less than a fifth of its bins: about as high everywhere.
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: Array(0...299), to: 14)), "all round")
        // Half the circle is plainly a direction.
        XCTAssertEqual(HorizonText.highestPlace(try profile(raising: Array(0...179), to: 14)), "in the east")
    }

    func testTheHighestPartOfAFlatLookingProfileWithOneLowPointIsAllRound() throws {
        var values = [Double](repeating: 6, count: HorizonProfile.binCount)
        values[100] = 5.5
        let skyline = try XCTUnwrap(HorizonProfile(altitudes: values))
        XCTAssertEqual(HorizonText.highestPlace(skyline), "all round")
        XCTAssertEqual(HorizonText.highest(skyline), "highest 6\(degree) all round")
    }

    func testTheHighestPointIsNamedWithItsAltitudeInWholeDegrees() throws {
        let hill = try profile(raising: [90], to: 14.4)
        XCTAssertEqual(HorizonText.highest(hill), "highest 14\(degree) in the east")
        let higher = try profile(raising: [90], to: 14.6)
        XCTAssertEqual(HorizonText.highest(higher), "highest 15\(degree) in the east")
    }

    // MARK: Directions

    func testAnAzimuthIsNamedByTheNearestOfTheEightMainDirections() {
        let expected: [(Double, String)] = [
            (0, "north"), (44, "northeast"), (45, "northeast"), (90, "east"), (135, "southeast"), (180, "south"),
            (225, "southwest"), (270, "west"), (315, "northwest"), (359, "north"),
        ]
        for (azimuth, name) in expected {
            XCTAssertEqual(HorizonText.direction(of: azimuth), name, "azimuth \(azimuth)")
        }
    }

    func testTheSectorsOfTheDirectionsMeetHalfWayBetweenThem() {
        XCTAssertEqual(HorizonText.direction(of: 22.4), "north")
        XCTAssertEqual(HorizonText.direction(of: 22.5), "northeast")
        XCTAssertEqual(HorizonText.direction(of: 67.4), "northeast")
        XCTAssertEqual(HorizonText.direction(of: 67.5), "east")
        XCTAssertEqual(HorizonText.direction(of: 337.4), "northwest")
        XCTAssertEqual(HorizonText.direction(of: 337.5), "north")
    }

    func testAzimuthsOutsideTheCircleAreWrapped() {
        XCTAssertEqual(HorizonText.direction(of: 360), "north")
        XCTAssertEqual(HorizonText.direction(of: -45), "northwest")
        XCTAssertEqual(HorizonText.direction(of: -90), "west")
        XCTAssertEqual(HorizonText.direction(of: 405), "northeast")
        XCTAssertEqual(HorizonText.direction(of: 720 + 180), "south")
    }

    // MARK: Gaps

    func testAGapIsGivenAsTheWholeDegreesItCovers() {
        XCTAssertEqual(HorizonText.gapText(gap(from: 80, bins: 16)), "80\(degree)\(dash)95\(degree)")
        XCTAssertEqual(HorizonText.gapText(gap(from: 200, bins: 61)), "200\(degree)\(dash)260\(degree)")
        XCTAssertEqual(HorizonText.gapText(gap(from: 1, bins: 2)), "1\(degree)\(dash)2\(degree)")
    }

    func testAGapOfOneDegreeIsGivenOnce() {
        XCTAssertEqual(HorizonText.gapText(gap(from: 80, bins: 1)), "80\(degree)")
        XCTAssertEqual(HorizonText.gapText(gap(from: 0, bins: 1)), "0\(degree)")
        XCTAssertEqual(HorizonText.gapText(gap(from: 359, bins: 1)), "359\(degree)")
    }

    func testAGapThatRunsThroughNorthWrapsFrom359To0() {
        XCTAssertEqual(HorizonText.gapText(gap(from: 359, bins: 3)), "359\(degree)\(dash)1\(degree)")
        XCTAssertEqual(HorizonText.gapText(gap(from: 350, bins: 22)), "350\(degree)\(dash)11\(degree)")
        XCTAssertEqual(HorizonText.gapText(AzimuthRange(start: 359.5, length: 2)), "0\(degree)\(dash)1\(degree)")
        // A range that starts below 0 is moved into the circle first.
        XCTAssertEqual(HorizonText.gapText(AzimuthRange(start: -0.5, length: 3)), "0\(degree)\(dash)2\(degree)")
    }

    func testAGapThatStartsAtNorthAndEndsAt359() {
        XCTAssertEqual(HorizonText.gapText(gap(from: 0, bins: 360)), "0\(degree)\(dash)359\(degree)")
        XCTAssertEqual(HorizonText.gapText(gap(from: 0, bins: 10)), "0\(degree)\(dash)9\(degree)")
    }

    func testNoGapsGiveNoText() {
        XCTAssertEqual(HorizonText.gapsText([]), "")
    }

    func testUpToThreeGapsAreListed() {
        XCTAssertEqual(HorizonText.gapsText([gap(from: 80, bins: 16)]), "80\(degree)\(dash)95\(degree)")
        XCTAssertEqual(HorizonText.gapsText([gap(from: 80, bins: 16), gap(from: 200, bins: 61)]),
                       "80\(degree)\(dash)95\(degree), 200\(degree)\(dash)260\(degree)")
        XCTAssertEqual(HorizonText.gapsText([gap(from: 80, bins: 16), gap(from: 200, bins: 61), gap(from: 300, bins: 11)]),
                       "80\(degree)\(dash)95\(degree), 200\(degree)\(dash)260\(degree), 300\(degree)\(dash)310\(degree)")
    }

    func testMoreThanThreeGapsEndWithHowManyAreLeftOut() {
        let first = gap(from: 80, bins: 16)
        let second = gap(from: 200, bins: 61)
        let third = gap(from: 300, bins: 11)
        let listed = "80\(degree)\(dash)95\(degree), 200\(degree)\(dash)260\(degree), 300\(degree)\(dash)310\(degree)"
        XCTAssertEqual(HorizonText.gapsText([first, second, third, gap(from: 10, bins: 5)]), "\(listed) and 1 more")
        XCTAssertEqual(HorizonText.gapsText([first, second, third, gap(from: 10, bins: 5), gap(from: 30, bins: 1)]),
                       "\(listed) and 2 more")
    }

    // MARK: Distance

    func testThePointsAtTheSamePlaceAreZeroMetresApart() {
        let place = GeographicLocation(latitude: 40.015, longitude: -105.27)
        XCTAssertEqual(HorizonText.distanceMetres(place, place), 0.0, accuracy: 1e-9)
    }

    func testADegreeOfLatitudeIsAbout111Kilometres() {
        let a = GeographicLocation(latitude: 40, longitude: -105)
        let b = GeographicLocation(latitude: 41, longitude: -105)
        // On the sphere of 6371 km radius: pi / 180 × 6 371 000 m.
        XCTAssertEqual(HorizonText.distanceMetres(a, b), 111_194.93, accuracy: 0.5)
        XCTAssertEqual(HorizonText.distanceMetres(b, a), HorizonText.distanceMetres(a, b), accuracy: 1e-6)
    }

    func testADegreeOfLongitudeAtTheEquatorIsTheSame() {
        let a = GeographicLocation(latitude: 0, longitude: 10)
        let b = GeographicLocation(latitude: 0, longitude: 11)
        XCTAssertEqual(HorizonText.distanceMetres(a, b), 111_194.93, accuracy: 0.5)
    }

    func testADegreeOfLongitudeIsShorterTowardTheNorth() {
        let a = GeographicLocation(latitude: 60, longitude: 10)
        let b = GeographicLocation(latitude: 60, longitude: 11)
        XCTAssertEqual(HorizonText.distanceMetres(a, b), 111_194.93 * AstroMath.cosDeg(60), accuracy: 20.0)
    }

    func testAQuarterOfTheEarthAndHalfOfItAreMeasuredRight() {
        let origin = GeographicLocation(latitude: 0, longitude: 0)
        let pole = GeographicLocation(latitude: 90, longitude: 0)
        XCTAssertEqual(HorizonText.distanceMetres(origin, pole), 10_007_543.4, accuracy: 1.0)
        let opposite = GeographicLocation(latitude: 0, longitude: 180)
        XCTAssertEqual(HorizonText.distanceMetres(origin, opposite), 20_015_086.8, accuracy: 1.0)
    }

    func testTheDistanceAcrossTheDateLineIsTheShortWay() {
        let west = GeographicLocation(latitude: 0, longitude: 179.5)
        let east = GeographicLocation(latitude: 0, longitude: -179.5)
        XCTAssertEqual(HorizonText.distanceMetres(west, east), 111_194.93, accuracy: 0.5)
    }

    // MARK: The coverage remembered with a skyline

    func testTheFingerprintOfAFlatSkylineIsStable() {
        XCTAssertEqual(HorizonCoverageMemory.fingerprint(of: HorizonProfile.flat), "a987b600a8b7fb65")
    }

    func testTheFingerprintsOfKnownSkylinesAreStable() throws {
        // FNV-1a over the altitudes in tenths of a degree as two bytes each, lowest byte first. Worked out outside the
        // app: a change here means every stored coverage would be forgotten.
        XCTAssertEqual(HorizonCoverageMemory.fingerprint(of: try profile(raising: Array(85...95), to: 14)), "6777641fae180f49")
        XCTAssertEqual(HorizonCoverageMemory.fingerprint(of: try profile(raising: [90], to: 14)), "45b505bbf4e396a9")
        XCTAssertEqual(HorizonCoverageMemory.fingerprint(of: HorizonProfile.constant(-5)), "cc46e81a38c92fd5")
    }

    func testTheFingerprintChangesWithTheSmallestStepOfTheSkyline() throws {
        let hill = try profile(raising: [90], to: 14.0)
        let higher = try profile(raising: [90], to: 14.1)
        let moved = try profile(raising: [91], to: 14.0)
        let prints = Set([HorizonCoverageMemory.fingerprint(of: hill), HorizonCoverageMemory.fingerprint(of: higher),
                          HorizonCoverageMemory.fingerprint(of: moved), HorizonCoverageMemory.fingerprint(of: HorizonProfile.flat)])
        XCTAssertEqual(prints.count, 4)
        XCTAssertEqual(HorizonCoverageMemory.fingerprint(of: hill),
                       HorizonCoverageMemory.fingerprint(of: try profile(raising: [90], to: 14.0)))
    }

    func testNothingIsRememberedForASiteThatNeverHadACoverageStored() throws {
        let hill = try profile(raising: Array(85...95), to: 14)
        let open = try XCTUnwrap(SavedSite(name: "Field", latitude: 40, longitude: -105))
        let wooded = try XCTUnwrap(SavedSite(name: "Woods", latitude: 40, longitude: -105, horizon: hill))
        XCTAssertNil(HorizonCoverageMemory.recall(for: open))
        XCTAssertNil(HorizonCoverageMemory.entry(for: open))
        // The identifier of the site is new, so there is nothing under its key.
        XCTAssertNil(HorizonCoverageMemory.recall(for: wooded))
        XCTAssertNil(HorizonCoverageMemory.entry(for: wooded))
        XCTAssertNil(HorizonCoverageMemory.merged(sweep: [Bool](repeating: true, count: HorizonProfile.binCount), over: wooded))
    }
}
