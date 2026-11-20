import Foundation
import XCTest
@testable import AppCore

/// `SkyClock`: the time-travel offset, its limit of one year either way, and returning to now.
///
/// The clock has no injectable time source; the screenshot-mode `freeze(at:)` (debug builds only) stands in for
/// one, so the exact-value tests are compiled in debug builds, where `swift test` runs. The tests outside
/// `#if DEBUG` hold whatever the wall clock says.
@MainActor
final class SettingsSkyClockTests: XCTestCase {
    /// The farthest the clock travels in either direction: 366 days.
    private let limit: TimeInterval = 366 * 86_400

    // MARK: Independent of the wall clock

    func testANewClockIsLive() {
        let clock = SkyClock()
        XCTAssertEqual(clock.offset, 0)
        XCTAssertTrue(clock.isLive)
        XCTAssertEqual(clock.displayDate, clock.now)
    }

    func testTravellingMoreThanAYearBackClampsToMinusOneYear() {
        let clock = SkyClock()
        clock.travel(to: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(clock.offset, -limit)
        XCTAssertEqual(clock.offset, -31_622_400)
        XCTAssertFalse(clock.isLive)
    }

    func testTravellingMoreThanAYearAheadClampsToPlusOneYear() {
        let clock = SkyClock()
        clock.travel(to: Date(timeIntervalSince1970: 4_000_000_000))
        XCTAssertEqual(clock.offset, limit)
        XCTAssertFalse(clock.isLive)
    }

    func testReturningToNowClearsAClampedOffset() {
        let clock = SkyClock()
        clock.travel(to: Date(timeIntervalSince1970: 4_000_000_000))
        clock.returnToNow()
        XCTAssertEqual(clock.offset, 0)
        XCTAssertTrue(clock.isLive)
        XCTAssertEqual(clock.displayDate, clock.now)
    }

    func testStartingAndStoppingTheClockKeepsTheOffsetAndShowsTheCurrentTime() {
        let clock = SkyClock()
        clock.travel(to: Date(timeIntervalSince1970: 4_000_000_000))
        clock.start()
        clock.start() // a second start is ignored
        XCTAssertEqual(clock.offset, limit)
        XCTAssertLessThan(abs(clock.now.timeIntervalSinceNow), 60)
        clock.stop()
        clock.stop() // stopping a stopped clock is harmless
        XCTAssertEqual(clock.offset, limit)
    }

    // MARK: With the clock held still

    #if DEBUG
    private let frozen = Date(timeIntervalSince1970: 1_700_000_000)

    private func frozenClock() -> SkyClock {
        let clock = SkyClock()
        clock.freeze(at: frozen)
        return clock
    }

    func testFreezingStopsTheClockAtThatInstant() {
        let clock = frozenClock()
        XCTAssertEqual(clock.now, frozen)
        XCTAssertEqual(clock.displayDate, frozen)
        XCTAssertTrue(clock.isLive)
    }

    func testAFrozenClockStaysAtItsInstantWhenStarted() {
        let clock = frozenClock()
        clock.start()
        XCTAssertEqual(clock.now, frozen)
        clock.stop()
        XCTAssertEqual(clock.now, frozen)
    }

    func testFreezingAgainMovesTheInstantAndKeepsTheOffset() {
        let clock = frozenClock()
        clock.travel(by: 600)
        let later = frozen.addingTimeInterval(86_400)
        clock.freeze(at: later)
        XCTAssertEqual(clock.now, later)
        XCTAssertEqual(clock.offset, 600)
        XCTAssertEqual(clock.displayDate, later.addingTimeInterval(600))
    }

    func testTravellingToAnInstantSetsTheOffsetFromNow() {
        let clock = frozenClock()
        clock.travel(to: frozen.addingTimeInterval(3_600))
        XCTAssertEqual(clock.offset, 3_600)
        XCTAssertEqual(clock.displayDate, frozen.addingTimeInterval(3_600))
        XCTAssertEqual(clock.now, frozen)
        XCTAssertFalse(clock.isLive)
    }

    func testTravellingToThePastGivesANegativeOffset() {
        let clock = frozenClock()
        clock.travel(to: frozen.addingTimeInterval(-7_200))
        XCTAssertEqual(clock.offset, -7_200)
        XCTAssertEqual(clock.displayDate, frozen.addingTimeInterval(-7_200))
    }

    func testTravellingToNowIsLiveAgain() {
        let clock = frozenClock()
        clock.travel(by: 1_000)
        clock.travel(to: frozen)
        XCTAssertEqual(clock.offset, 0)
        XCTAssertTrue(clock.isLive)
    }

    func testTravellingByShiftsTheOffsetFromWhereItIs() {
        let clock = frozenClock()
        clock.travel(by: 3_600)
        XCTAssertEqual(clock.offset, 3_600)
        clock.travel(by: 3_600)
        XCTAssertEqual(clock.offset, 7_200)
        clock.travel(by: -10_800)
        XCTAssertEqual(clock.offset, -3_600)
        XCTAssertEqual(clock.displayDate, frozen.addingTimeInterval(-3_600))
    }

    func testTravellingByZeroKeepsTheClockLive() {
        let clock = frozenClock()
        clock.travel(by: 0)
        XCTAssertEqual(clock.offset, 0)
        XCTAssertTrue(clock.isLive)
    }

    func testTheOffsetIsLimitedToAYearInEitherDirection() {
        let forward = frozenClock()
        forward.travel(by: 400 * 86_400)
        XCTAssertEqual(forward.offset, limit)
        let back = frozenClock()
        back.travel(by: -400 * 86_400)
        XCTAssertEqual(back.offset, -limit)
    }

    func testTheLimitItselfIsReachableButNotPassed() {
        let clock = frozenClock()
        clock.travel(to: frozen.addingTimeInterval(limit))
        XCTAssertEqual(clock.offset, limit)
        clock.travel(to: frozen.addingTimeInterval(limit + 1))
        XCTAssertEqual(clock.offset, limit)
        clock.travel(to: frozen.addingTimeInterval(-limit))
        XCTAssertEqual(clock.offset, -limit)
        clock.travel(to: frozen.addingTimeInterval(-limit - 1))
        XCTAssertEqual(clock.offset, -limit)
    }

    func testTravellingFurtherAtTheLimitStaysAtTheLimitButAStepBackMoves() {
        let clock = frozenClock()
        clock.travel(by: 400 * 86_400)
        clock.travel(by: 86_400)
        XCTAssertEqual(clock.offset, limit)
        clock.travel(by: -1_000)
        XCTAssertEqual(clock.offset, limit - 1_000)
    }

    func testReturningToNowClearsTheOffsetAndShowsTheWallClock() {
        let clock = frozenClock()
        clock.travel(by: 5_000)
        XCTAssertFalse(clock.isLive)
        clock.returnToNow()
        XCTAssertEqual(clock.offset, 0)
        XCTAssertTrue(clock.isLive)
        XCTAssertEqual(clock.now, frozen)
        XCTAssertEqual(clock.displayDate, frozen)
    }

    func testReturningToNowOnALiveClockChangesNothing() {
        let clock = frozenClock()
        clock.returnToNow()
        XCTAssertEqual(clock.offset, 0)
        XCTAssertEqual(clock.displayDate, frozen)
    }
    #endif
}
