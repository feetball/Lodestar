import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `HorizonCoverageMemory` against a defaults suite of its own: the share of the circle a sweep reached, remembered per site
/// next to a fingerprint of the skyline it belongs to, and the degrees that were swept (90 hex digits, four degrees each, the
/// lowest degree in the lowest bit). A site is only ever remembered while its skyline is the one that was stored.
final class OnlineNetHorizonCoverageTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppCoreTests.OnlineNetHorizon.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Helpers

    /// A skyline at 0° with the given bins raised to `altitude`.
    private func skyline(raising bins: ClosedRange<Int>, to altitude: Double = 14) throws -> HorizonProfile {
        var values = [Double](repeating: 0, count: HorizonProfile.binCount)
        for bin in bins { values[bin] = altitude }
        return try XCTUnwrap(HorizonProfile(altitudes: values))
    }

    /// A saved site with `horizon` (a flat or absent skyline is an open horizon).
    private func site(_ horizon: HorizonProfile?, id: UUID = UUID()) throws -> SavedSite {
        try XCTUnwrap(SavedSite(id: id, name: "Test site", latitude: 40, longitude: -105, horizon: horizon))
    }

    /// The circle with the degrees in `range` swept.
    private func swept(_ range: Range<Int>) -> [Bool] {
        (0..<HorizonProfile.binCount).map { range.contains($0) }
    }

    /// The circle with exactly the degrees in `degrees` swept.
    private func swept(only degrees: [Int]) -> [Bool] {
        (0..<HorizonProfile.binCount).map { degrees.contains($0) }
    }

    private func key(_ id: UUID) -> String { "lodestar.horizon.coverage.\(id.uuidString)" }

    /// The text kept in the defaults for the site `id`.
    private func stored(_ id: UUID) -> String? { defaults.string(forKey: key(id)) }

    private func fingerprint(_ profile: HorizonProfile) -> String { HorizonCoverageMemory.fingerprint(of: profile) }

    private func remember(_ site: SavedSite, coverage: Double, mask: [Bool]? = nil) {
        HorizonCoverageMemory.store(siteID: site.id, horizon: site.horizon, coverage: coverage, mask: mask, defaults: defaults)
    }

    private func recall(_ site: SavedSite) -> Double? {
        HorizonCoverageMemory.recall(for: site, defaults: defaults)
    }

    private func entry(_ site: SavedSite) -> HorizonCoverageMemory.Entry? {
        HorizonCoverageMemory.entry(for: site, defaults: defaults)
    }

    private func merged(_ mask: [Bool], over site: SavedSite) -> HorizonCoverageMemory.Entry? {
        HorizonCoverageMemory.merged(sweep: mask, over: site, defaults: defaults)
    }

    private func zeros(_ count: Int) -> String { String(repeating: "0", count: count) }

    // MARK: Storing and recalling

    func testNothingIsRememberedUntilSomethingIsStored() throws {
        let hill = try site(try skyline(raising: 85...95))
        XCTAssertNil(recall(hill))
        XCTAssertNil(entry(hill))
    }

    func testAStoredCoverageIsRecalled() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.86)
        XCTAssertEqual(recall(hill), 0.86)
        XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 0.86, mask: nil))
    }

    func testTheStoredTextIsTheFingerprintAndTheCoverage() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        remember(hill, coverage: 0.86)
        XCTAssertEqual(stored(hill.id), "\(fingerprint(profile)):0.86")
    }

    func testCoveragesOfNothingAndOfTheWholeCircleAreRemembered() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0)
        XCTAssertEqual(recall(hill), 0.0)
        remember(hill, coverage: 1)
        XCTAssertEqual(recall(hill), 1.0)
    }

    func testACoverageThatIsNotRoundIsRememberedExactly() throws {
        let hill = try site(try skyline(raising: 85...95))
        let coverage = 310.0 / 360.0
        remember(hill, coverage: coverage)
        XCTAssertEqual(recall(hill), coverage)
    }

    func testStoringAgainReplacesTheEarlierCoverage() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.3)
        remember(hill, coverage: 0.6)
        XCTAssertEqual(recall(hill), 0.6)
    }

    func testStoringWithoutTheDegreesDropsTheDegreesStoredBefore() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        XCTAssertNotNil(entry(hill)?.mask)
        remember(hill, coverage: 0.4)
        XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 0.4, mask: nil))
    }

    func testStoredDegreesComeBackAsTheyWentIn() throws {
        let hill = try site(try skyline(raising: 85...95))
        let pattern = (0..<HorizonProfile.binCount).map { $0 % 7 == 0 || $0 % 11 == 3 }
        remember(hill, coverage: 0.4, mask: pattern)
        let back = try XCTUnwrap(entry(hill))
        XCTAssertEqual(back.coverage, 0.4)
        XCTAssertEqual(back.mask, pattern)
    }

    func testNoDegreesAndAllDegreesAreEachNinetyHexDigits() throws {
        let hill = try site(try skyline(raising: 85...95))
        let stamp = fingerprint(try XCTUnwrap(hill.horizon))
        remember(hill, coverage: 0, mask: swept(0..<0))
        XCTAssertEqual(stored(hill.id), "\(stamp):0.0:\(zeros(90))")
        remember(hill, coverage: 1, mask: swept(0..<360))
        XCTAssertEqual(stored(hill.id), "\(stamp):1.0:\(String(repeating: "f", count: 90))")
    }

    func testTheLowestDegreeOfADigitIsItsLowestBit() throws {
        let hill = try site(try skyline(raising: 85...95))
        let stamp = fingerprint(try XCTUnwrap(hill.horizon))
        let cases: [(degrees: [Int], digits: String)] = [
            ([0], "1" + zeros(89)),
            ([1], "2" + zeros(89)),
            ([2], "4" + zeros(89)),
            ([3], "8" + zeros(89)),
            ([0, 1, 2, 3], "f" + zeros(89)),
            ([4], "0" + "1" + zeros(88)),
            ([7], "0" + "8" + zeros(88)),
            ([356, 358], zeros(89) + "5"),
            ([359], zeros(89) + "8"),
        ]
        for (degrees, digits) in cases {
            remember(hill, coverage: 0.5, mask: swept(only: degrees))
            XCTAssertEqual(stored(hill.id), "\(stamp):0.5:\(digits)", "degrees \(degrees)")
        }
    }

    func testAQuarterCircleFillsTheFirstTwentyTwoDigitsAndHalfOfTheNext() throws {
        let hill = try site(try skyline(raising: 85...95))
        let stamp = fingerprint(try XCTUnwrap(hill.horizon))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        // Degrees 0…87 are 22 full digits; 88 and 89 are the two lowest bits of the 23rd.
        XCTAssertEqual(stored(hill.id), "\(stamp):0.25:\(String(repeating: "f", count: 22))3\(zeros(67))")
        remember(hill, coverage: 0.5, mask: swept(0..<180))
        XCTAssertEqual(stored(hill.id), "\(stamp):0.5:\(String(repeating: "f", count: 45))\(zeros(45))")
    }

    func testDegreesThatAreNotExactlyOneCircleLongAreNotStored() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        for count in [0, 1, 359, 361, 720] {
            remember(hill, coverage: 0.5, mask: [Bool](repeating: true, count: count))
            XCTAssertEqual(stored(hill.id), "\(fingerprint(profile)):0.5", "\(count) degrees")
            XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 0.5, mask: nil), "\(count) degrees")
        }
    }

    func testACoverageOutsideZeroToOneIsStoredButNeverRecalled() throws {
        let hill = try site(try skyline(raising: 85...95))
        for coverage in [1.5, -0.5, Double.nan, Double.infinity] {
            remember(hill, coverage: coverage)
            XCTAssertNotNil(stored(hill.id), "\(coverage)")
            XCTAssertNil(recall(hill), "\(coverage)")
            XCTAssertNil(entry(hill), "\(coverage)")
        }
    }

    // MARK: Forgetting

    func testForgettingDropsTheCoverage() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.7, mask: swept(0..<90))
        HorizonCoverageMemory.forget(siteID: hill.id, defaults: defaults)
        XCTAssertNil(recall(hill))
        XCTAssertNil(entry(hill))
        XCTAssertNil(stored(hill.id))
    }

    func testForgettingASiteLeavesTheOtherSitesAlone() throws {
        let profile = try skyline(raising: 85...95)
        let first = try site(profile)
        let second = try site(profile)
        remember(first, coverage: 0.3)
        remember(second, coverage: 0.9)
        HorizonCoverageMemory.forget(siteID: first.id, defaults: defaults)
        XCTAssertNil(recall(first))
        XCTAssertEqual(recall(second), 0.9)
    }

    func testForgettingASiteThatWasNeverStoredIsHarmless() throws {
        let hill = try site(try skyline(raising: 85...95))
        HorizonCoverageMemory.forget(siteID: hill.id, defaults: defaults)
        XCTAssertNil(recall(hill))
    }

    func testStoringForASiteWithoutASkylineForgetsWhatWasThere() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.7, mask: swept(0..<90))
        XCTAssertNotNil(stored(hill.id))
        // The skyline was removed: the site is stored with no horizon, which forgets its coverage.
        HorizonCoverageMemory.store(siteID: hill.id, horizon: nil, coverage: 1, mask: swept(0..<360), defaults: defaults)
        XCTAssertNil(stored(hill.id))
        XCTAssertNil(recall(hill))
    }

    func testStoringForASiteWithoutASkylineStoresNothingNew() throws {
        let clear = try site(nil)
        HorizonCoverageMemory.store(siteID: clear.id, horizon: nil, coverage: 0.5, defaults: defaults)
        XCTAssertNil(stored(clear.id))
        XCTAssertNil(recall(clear))
    }

    // MARK: The skyline it belongs to

    func testASiteWithoutASkylineRemembersNothing() throws {
        let id = UUID()
        let hill = try site(try skyline(raising: 85...95), id: id)
        remember(hill, coverage: 0.7)
        XCTAssertNotNil(stored(id))
        // The same site once its skyline is gone: there is nothing to attach the coverage to.
        let clear = try site(nil, id: id)
        XCTAssertNil(clear.horizon)
        XCTAssertNil(recall(clear))
        XCTAssertNil(entry(clear))
    }

    func testAFlatSkylineIsNoSkylineAtAll() throws {
        let clear = try site(HorizonProfile.flat)
        XCTAssertNil(clear.horizon)
        XCTAssertNil(recall(clear))
        XCTAssertNil(merged(swept(0..<360), over: clear))
    }

    func testAChangedSkylineForgets() throws {
        let id = UUID()
        let original = try site(try skyline(raising: 85...95), id: id)
        remember(original, coverage: 0.7, mask: swept(0..<90))
        XCTAssertEqual(recall(original), 0.7)
        let variants = [
            try skyline(raising: 85...95, to: 14.1),
            try skyline(raising: 86...96),
            try skyline(raising: 85...94),
            try skyline(raising: 0...3),
        ]
        for variant in variants {
            let changed = try site(variant, id: id)
            XCTAssertNil(recall(changed))
            XCTAssertNil(entry(changed))
            XCTAssertNil(merged(swept(0..<360), over: changed))
        }
    }

    func testASkylineChangedInASavedSiteIsNotRecalled() throws {
        var hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.7)
        hill.horizon = try skyline(raising: 85...95, to: 20)
        XCTAssertNil(recall(hill))
    }

    func testTheSameSkylineIsRecalledAfterTheSiteIsSavedAndLoaded() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.7, mask: swept(0..<90))
        let data = try JSONEncoder().encode(hill)
        let loaded = try JSONDecoder().decode(SavedSite.self, from: data)
        XCTAssertEqual(loaded.horizon, hill.horizon)
        XCTAssertEqual(recall(loaded), 0.7)
        XCTAssertEqual(entry(loaded)?.mask, swept(0..<90))
    }

    func testTheSameSkylineBuiltAgainFromItsAltitudesIsRecalled() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        remember(hill, coverage: 0.7)
        let rebuilt = try site(try XCTUnwrap(HorizonProfile(altitudes: profile.altitudes)), id: hill.id)
        XCTAssertEqual(recall(rebuilt), 0.7)
    }

    // MARK: Text that cannot be read

    func testTextWithoutACoverageIsIgnored() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        let stamp = fingerprint(profile)
        for text in ["", "garbage", stamp, "\(stamp):", "\(stamp):abc", ":0.5", "::"] {
            defaults.set(text, forKey: key(hill.id))
            XCTAssertNil(recall(hill), "'\(text)'")
            XCTAssertNil(entry(hill), "'\(text)'")
        }
    }

    func testAValueThatIsNotTextIsIgnored() throws {
        let hill = try site(try skyline(raising: 85...95))
        defaults.set(["not", "text"], forKey: key(hill.id))
        XCTAssertNil(recall(hill))
    }

    func testACoverageOutsideZeroToOneInTheTextIsIgnored() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        for coverage in ["1.0000001", "-0.0000001", "2", "-1", "nan", "inf", "-inf"] {
            defaults.set("\(fingerprint(profile)):\(coverage)", forKey: key(hill.id))
            XCTAssertNil(recall(hill), coverage)
        }
    }

    func testTheCoverageBoundsThemselvesAreAccepted() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        defaults.set("\(fingerprint(profile)):0", forKey: key(hill.id))
        XCTAssertEqual(recall(hill), 0.0)
        defaults.set("\(fingerprint(profile)):1", forKey: key(hill.id))
        XCTAssertEqual(recall(hill), 1.0)
    }

    func testTextOfAnotherSkylineIsIgnored() throws {
        let hill = try site(try skyline(raising: 85...95))
        defaults.set("0000000000000000:0.5", forKey: key(hill.id))
        XCTAssertNil(recall(hill))
        // A fingerprint cut short is not the fingerprint of the skyline.
        let cutOff = String(fingerprint(try XCTUnwrap(hill.horizon)).prefix(13))
        defaults.set("\(cutOff):0.5", forKey: key(hill.id))
        XCTAssertNil(recall(hill))
    }

    func testDegreesWithTooFewOrTooManyDigitsAreDroppedAndTheCoverageStays() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        for count in [0, 1, 45, 89, 91, 180] {
            defaults.set("\(fingerprint(profile)):0.5:\(String(repeating: "f", count: count))", forKey: key(hill.id))
            XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 0.5, mask: nil), "\(count) digits")
        }
    }

    func testDegreesWithADigitThatIsNotHexadecimalAreDropped() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        let digits89 = String(repeating: "f", count: 89)
        let digits44 = String(repeating: "f", count: 44)
        let digits45 = String(repeating: "f", count: 45)
        let broken: [String] = ["g" + digits89, digits89 + "z", digits44 + "-" + digits45]
        for bad in broken {
            XCTAssertEqual(bad.count, 90)
            defaults.set("\(fingerprint(profile)):0.5:\(bad)", forKey: key(hill.id))
            XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 0.5, mask: nil), bad)
        }
    }

    func testDegreesInCapitalHexadecimalAreRead() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        defaults.set("\(fingerprint(profile)):1.0:\(String(repeating: "F", count: 90))", forKey: key(hill.id))
        XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 1.0, mask: swept(0..<360)))
    }

    func testAnEmptyDegreesFieldLeavesTheCoverage() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        defaults.set("\(fingerprint(profile)):0.5:", forKey: key(hill.id))
        XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 0.5, mask: nil))
    }

    func testAnExtraFieldAfterTheDegreesSpoilsOnlyTheDegrees() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        defaults.set("\(fingerprint(profile)):0.5:\(String(repeating: "f", count: 90)):extra", forKey: key(hill.id))
        XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 0.5, mask: nil))
    }

    func testDegreesCutShortByATruncatedWriteAreDropped() throws {
        let profile = try skyline(raising: 85...95)
        let hill = try site(profile)
        remember(hill, coverage: 0.5, mask: swept(0..<180))
        let whole = try XCTUnwrap(stored(hill.id))
        // The last digit missing: the coverage is still good, the degrees no longer are.
        defaults.set(String(whole.dropLast()), forKey: key(hill.id))
        XCTAssertEqual(entry(hill), HorizonCoverageMemory.Entry(coverage: 0.5, mask: nil))
        // Cut right after the fingerprint's colon: no coverage is left.
        defaults.set(String(whole.prefix(fingerprint(profile).count + 1)), forKey: key(hill.id))
        XCTAssertNil(entry(hill))
        // Cut inside the fingerprint: it no longer matches the skyline.
        defaults.set(String(whole.prefix(fingerprint(profile).count - 3)), forKey: key(hill.id))
        XCTAssertNil(entry(hill))
    }

    // MARK: Adding up sweeps

    func testNothingIsMergedWhenNothingIsRemembered() throws {
        let hill = try site(try skyline(raising: 85...95))
        XCTAssertNil(merged(swept(0..<90), over: hill))
    }

    func testNothingIsMergedOverASiteWithoutASkyline() throws {
        let id = UUID()
        remember(try site(try skyline(raising: 85...95), id: id), coverage: 0.5, mask: swept(0..<180))
        XCTAssertNil(merged(swept(0..<90), over: try site(nil, id: id)))
    }

    func testWithoutStoredDegreesTheLargerShareIsAllThatIsKnown() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.3)
        // The sweep reached half the circle: more than the 30% remembered.
        XCTAssertEqual(merged(swept(0..<180), over: hill), HorizonCoverageMemory.Entry(coverage: 0.5, mask: nil))
        // The sweep reached a tenth: the remembered 30% stays.
        XCTAssertEqual(merged(swept(0..<36), over: hill), HorizonCoverageMemory.Entry(coverage: 0.3, mask: nil))
    }

    func testWithoutStoredDegreesEqualSharesStayTheSame() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25)
        XCTAssertEqual(merged(swept(100..<190), over: hill), HorizonCoverageMemory.Entry(coverage: 0.25, mask: nil))
    }

    func testStoredDegreesAndTheSweepAreAddedUp() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        let result = try XCTUnwrap(merged(swept(180..<270), over: hill))
        XCTAssertEqual(result.coverage, 0.5, accuracy: 1e-12)
        XCTAssertEqual(result.mask, (0..<360).map { $0 < 90 || ($0 >= 180 && $0 < 270) })
    }

    func testADegreeSweptTwiceIsCountedOnce() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.5, mask: swept(0..<180))
        let result = try XCTUnwrap(merged(swept(90..<270), over: hill))
        XCTAssertEqual(result.coverage, 0.75, accuracy: 1e-12)
        XCTAssertEqual(result.mask, swept(0..<270))
    }

    func testASweepOfTheSameDegreesChangesNothing() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        let result = try XCTUnwrap(merged(swept(0..<90), over: hill))
        XCTAssertEqual(result.coverage, 0.25, accuracy: 1e-12)
        XCTAssertEqual(result.mask, swept(0..<90))
    }

    func testASweepOfNothingKeepsTheStoredCircle() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        let result = try XCTUnwrap(merged(swept(0..<0), over: hill))
        XCTAssertEqual(result.coverage, 0.25, accuracy: 1e-12)
        XCTAssertEqual(result.mask, swept(0..<90))
    }

    func testAWholeCircleSweepCoversEverything() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        let result = try XCTUnwrap(merged(swept(0..<360), over: hill))
        XCTAssertEqual(result.coverage, 1.0, accuracy: 1e-12)
        XCTAssertEqual(result.mask, swept(0..<360))
    }

    func testASweepNotOneCircleLongFallsBackToTheLargerShare() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        // 359 degrees cannot be lined up with the stored circle: only the shares can be compared.
        let nearlyAll = try XCTUnwrap(merged([Bool](repeating: true, count: 359), over: hill))
        XCTAssertEqual(nearlyAll.coverage, 359.0 / 360.0, accuracy: 1e-12)
        XCTAssertNil(nearlyAll.mask)
        let nothing = try XCTUnwrap(merged([], over: hill))
        XCTAssertEqual(nothing.coverage, 0.25, accuracy: 1e-12)
        XCTAssertNil(nothing.mask)
    }

    func testMergingStoresNothing() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        let before = stored(hill.id)
        _ = merged(swept(180..<270), over: hill)
        XCTAssertEqual(stored(hill.id), before)
        XCTAssertEqual(recall(hill), 0.25)
    }

    func testAMergedEntryCanBeStoredAndReadBack() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.25, mask: swept(0..<90))
        let result = try XCTUnwrap(merged(swept(180..<270), over: hill))
        remember(hill, coverage: result.coverage, mask: result.mask)
        XCTAssertEqual(entry(hill), result)
        // And the next sweep adds to the sum of the two.
        let next = try XCTUnwrap(merged(swept(90..<180), over: hill))
        XCTAssertEqual(next.coverage, 0.75, accuracy: 1e-12)
    }

    // MARK: Separate memories

    func testEverySiteHasItsOwnEntry() throws {
        let profile = try skyline(raising: 85...95)
        let first = try site(profile)
        let second = try site(profile)
        remember(first, coverage: 0.2, mask: swept(0..<72))
        remember(second, coverage: 0.8)
        XCTAssertEqual(recall(first), 0.2)
        XCTAssertNotNil(entry(first)?.mask)
        XCTAssertEqual(recall(second), 0.8)
        XCTAssertNil(entry(second)?.mask)
    }

    func testTheMemoryLivesInTheDefaultsThatWerePassed() throws {
        let hill = try site(try skyline(raising: 85...95))
        remember(hill, coverage: 0.7)
        let otherName = "AppCoreTests.OnlineNetHorizon.other.\(UUID().uuidString)"
        let other = try XCTUnwrap(UserDefaults(suiteName: otherName))
        defer { other.removePersistentDomain(forName: otherName) }
        XCTAssertNil(HorizonCoverageMemory.recall(for: hill, defaults: other))
        XCTAssertNil(HorizonCoverageMemory.entry(for: hill, defaults: other))
        XCTAssertNil(HorizonCoverageMemory.merged(sweep: swept(0..<90), over: hill, defaults: other))
        HorizonCoverageMemory.store(siteID: hill.id, horizon: hill.horizon, coverage: 0.1, defaults: other)
        XCTAssertEqual(HorizonCoverageMemory.recall(for: hill, defaults: other), 0.1)
        // Neither suite saw the other's value.
        XCTAssertEqual(recall(hill), 0.7)
        HorizonCoverageMemory.forget(siteID: hill.id, defaults: other)
        XCTAssertEqual(recall(hill), 0.7)
        XCTAssertNil(HorizonCoverageMemory.recall(for: hill, defaults: other))
    }
}
