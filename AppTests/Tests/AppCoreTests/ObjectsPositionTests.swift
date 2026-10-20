import XCTest
import LodestarKit
@testable import AppCore

/// A tiny synthetic catalog (the Sun, the planets and the poles are always in it) with one comet, and observers.
private enum ObjectsPositionFixture {
    private static let loaded: Result<Catalog, Error> = Result { try ObjectsPositionFixture.makeCatalog() }

    static func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try loaded.get().object(id: id), id)
    }

    private static func file(_ key: String, _ records: [String]) -> Data {
        Data(#"{"schema":1,"\#(key)":[\#(records.joined(separator: ","))]}"#.utf8)
    }

    private static func makeCatalog() throws -> Catalog {
        let stars = [#"{"hip":1001,"n":"Alpha Test","c":"Ori","ra":10.0,"de":20.0,"m":0.5}"#]
        let deepSky = [#"{"id":"M31","m":31,"ngc":[224],"names":["Andromeda Galaxy"],"t":"G","ra":10.68,"de":41.27,"c":"And","vm":3.4,"p":1}"#]
        let constellations = [
            #"{"abbr":"And","name":"Andromeda","genitive":"Andromedae","label":[10.0,40.0],"lines":[[[10.0,30.0],[20.0,40.0]]]}"#,
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

    /// A custom target at a J2000 place.
    static func target(_ rightAscension: Double, _ declination: Double) -> CelestialObject {
        CelestialObject.custom(name: "Target", j2000: EquatorialCoordinate(rightAscension: rightAscension,
                                                                           declination: declination))
    }

    static let denver = Observer(location: GeographicLocation(latitude: 40, longitude: -105, elevation: 1600))
    static let sydney = Observer(location: GeographicLocation(latitude: -34, longitude: 151, elevation: 20))
    static let svalbard = Observer(location: GeographicLocation(latitude: 80, longitude: 15, elevation: 0))

    /// 2026-10-21 03:00 UTC.
    static let evening = Date(timeIntervalSince1970: 1_792_551_600)
    /// 2026-12-21 12:00 UTC.
    static let polarNoon = Date(timeIntervalSince1970: 1_797_854_400)

    /// The interval in which the next rising is looked for.
    static func window(from date: Date) -> DateInterval {
        DateInterval(start: date, duration: ObjectsPositionCalculator.riseSearchWindow)
    }
}

// MARK: - The calculator

final class ObjectsPositionCalculatorTests: XCTestCase {
    private func position(of object: CelestialObject, observer: Observer = ObjectsPositionFixture.denver,
                          skyline: HorizonProfile? = nil, date: Date = ObjectsPositionFixture.evening) throws -> ObjectSkyPosition {
        let positions = ObjectsPositionCalculator.positions(for: [object], observer: observer, skyline: skyline, date: date)
        return try XCTUnwrap(positions[object.id])
    }

    func testTheSearchWindowIsTwentyFiveHours() {
        XCTAssertEqual(ObjectsPositionCalculator.riseSearchWindow, 25 * 3600)
    }

    func testNoObjectsGiveNoPositions() {
        XCTAssertTrue(ObjectsPositionCalculator.positions(for: [], observer: ObjectsPositionFixture.denver,
                                                          date: ObjectsPositionFixture.evening).isEmpty)
    }

    func testEveryObjectGetsAPositionKeyedByItsIdentifier() throws {
        let objects = [try ObjectsPositionFixture.object("sun"), try ObjectsPositionFixture.object("dso.M31"),
                       ObjectsPositionFixture.target(30, 0)]
        let positions = ObjectsPositionCalculator.positions(for: objects, observer: ObjectsPositionFixture.denver,
                                                            date: ObjectsPositionFixture.evening)
        XCTAssertEqual(Set(positions.keys), Set(objects.map(\.id)))
    }

    func testAnObjectListedTwiceHasOnePosition() throws {
        let object = ObjectsPositionFixture.target(30, 0)
        let positions = ObjectsPositionCalculator.positions(for: [object, object], observer: ObjectsPositionFixture.denver,
                                                            date: ObjectsPositionFixture.evening)
        XCTAssertEqual(positions.count, 1)
    }

    // MARK: A star-like object

    func testThePositionIsTheRefractedPlaceInTheObserversSky() throws {
        let object = ObjectsPositionFixture.target(30, 0)
        let result = try position(of: object)
        let horizontal = SkyFrame(date: ObjectsPositionFixture.evening, observer: ObjectsPositionFixture.denver)
            .horizontal(of: object, refraction: true)
        XCTAssertEqual(result.altitude, horizontal.altitude, accuracy: 1e-9)
        XCTAssertEqual(result.azimuth, horizontal.azimuth, accuracy: 1e-9)
        XCTAssertEqual(result.computedAt, ObjectsPositionFixture.evening)
        XCTAssertEqual(result.isAboveHorizon, horizontal.altitude > 0)
        XCTAssertFalse(result.isBehindSkyline)
        XCTAssertFalse(result.usesSkyline)
    }

    func testAStarLikeObjectHasNoMagnitudeAndNoSmallBodyInfo() throws {
        // The catalog magnitude of a star or deep-sky object is not repeated in the position.
        let andromeda = try position(of: try ObjectsPositionFixture.object("dso.M31"))
        XCTAssertNil(andromeda.magnitude)
        XCTAssertNil(andromeda.smallBody)
        let star = try position(of: try ObjectsPositionFixture.object("star.hip1001"))
        XCTAssertNil(star.magnitude)
    }

    func testAnObjectThatRisesGetsItsNextRisingWithinTheWindow() throws {
        let object = ObjectsPositionFixture.target(30, 0)
        let result = try position(of: object)
        let expected = RiseSetCalculator.riseTransitSet(
            for: object, observer: ObjectsPositionFixture.denver,
            within: ObjectsPositionFixture.window(from: ObjectsPositionFixture.evening)).rise
        XCTAssertNotNil(expected)
        XCTAssertEqual(result.nextRise, expected)
        XCTAssertFalse(result.neverRises)
        XCTAssertFalse(result.noRiseInWindow)
        if let rise = result.nextRise {
            XCTAssertGreaterThan(rise, ObjectsPositionFixture.evening)
            XCTAssertLessThanOrEqual(rise, ObjectsPositionFixture.evening.addingTimeInterval(25 * 3600))
        }
    }

    func testACircumpolarObjectIsAlwaysUpAndHasNoRising() throws {
        // Declination +80 never gets below 30 degrees at latitude 40.
        let result = try position(of: ObjectsPositionFixture.target(30, 80))
        XCTAssertTrue(result.isAboveHorizon)
        XCTAssertGreaterThan(result.altitude, 25)
        XCTAssertNil(result.nextRise)
        XCTAssertFalse(result.neverRises)
        XCTAssertFalse(result.noRiseInWindow)
    }

    func testAnObjectThatStaysBelowTheHorizonNeverRises() throws {
        // Declination -80 never gets above -30 degrees at latitude 40.
        let result = try position(of: ObjectsPositionFixture.target(30, -80))
        XCTAssertFalse(result.isAboveHorizon)
        XCTAssertLessThan(result.altitude, -25)
        XCTAssertNil(result.nextRise)
        XCTAssertTrue(result.neverRises)
        XCTAssertFalse(result.noRiseInWindow)
        XCTAssertFalse(result.isBehindSkyline)
    }

    // MARK: The poles

    func testTheNorthPoleIsAtTheLatitudeAndNeverSets() throws {
        let result = try position(of: try ObjectsPositionFixture.object("special.ncp"))
        XCTAssertEqual(result.altitude, 40, accuracy: 0.1)
        XCTAssertTrue(result.isAboveHorizon)
        XCTAssertNil(result.nextRise)
        XCTAssertFalse(result.neverRises)
        XCTAssertFalse(result.noRiseInWindow)
        let wrapped = min(result.azimuth, 360 - result.azimuth)
        XCTAssertEqual(wrapped, 0, accuracy: 0.01, "due north")
    }

    func testTheSouthPoleNeverRisesForAnObserverInTheNorth() throws {
        let result = try position(of: try ObjectsPositionFixture.object("special.scp"))
        XCTAssertEqual(result.altitude, -40, accuracy: 0.1)
        XCTAssertFalse(result.isAboveHorizon)
        XCTAssertTrue(result.neverRises)
        XCTAssertFalse(result.noRiseInWindow)
    }

    func testTheSouthPoleIsUpForAnObserverInTheSouth() throws {
        let result = try position(of: try ObjectsPositionFixture.object("special.scp"), observer: ObjectsPositionFixture.sydney)
        XCTAssertEqual(result.altitude, 34, accuracy: 0.1)
        XCTAssertTrue(result.isAboveHorizon)
        XCTAssertFalse(result.neverRises)
    }

    // MARK: Solar-system bodies

    func testTheSunAndThePlanetsCarryTheirCurrentMagnitude() throws {
        let frame = SkyFrame(date: ObjectsPositionFixture.evening, observer: ObjectsPositionFixture.denver)
        for id in ["sun", "moon", "planet.mars", "planet.jupiter"] {
            let object = try ObjectsPositionFixture.object(id)
            let result = try position(of: object)
            let expected = try XCTUnwrap(frame.currentMagnitude(of: object), id)
            XCTAssertEqual(try XCTUnwrap(result.magnitude, id), expected, accuracy: 1e-9, id)
        }
        let sun = try XCTUnwrap(try position(of: try ObjectsPositionFixture.object("sun")).magnitude)
        XCTAssertEqual(sun, -26.7, accuracy: 0.5)
    }

    func testAMovingBodyThatDoesNotRiseWithinTheWindowIsNotCalledNeverRising() throws {
        // At 80 degrees north at the winter solstice the Sun stays below the horizon all day: it moves, so that says
        // nothing about later days.
        let sun = try ObjectsPositionFixture.object("sun")
        let result = try position(of: sun, observer: ObjectsPositionFixture.svalbard, date: ObjectsPositionFixture.polarNoon)
        XCTAssertFalse(result.isAboveHorizon)
        XCTAssertTrue(result.noRiseInWindow)
        XCTAssertFalse(result.neverRises)
        XCTAssertNil(result.nextRise)
    }

    func testTheSunRisesAtMiddleLatitudes() throws {
        let result = try position(of: try ObjectsPositionFixture.object("sun"))
        XCTAssertNotNil(result.nextRise)
        XCTAssertFalse(result.noRiseInWindow)
        XCTAssertFalse(result.neverRises)
    }

    func testACometCarriesItsDistancesAndItsMagnitude() throws {
        let comet = try ObjectsPositionFixture.object("comet.C/2099 A1")
        let body = try XCTUnwrap(comet.smallBody)
        let frame = SkyFrame(date: ObjectsPositionFixture.evening, observer: ObjectsPositionFixture.denver)
        let result = try position(of: comet)
        let info = try XCTUnwrap(result.smallBody)
        XCTAssertEqual(info, SmallBodyInfo.compute(body, frame: frame))
        XCTAssertEqual(info.body.id, "comet.C/2099 A1")
        XCTAssertEqual(try XCTUnwrap(result.magnitude), try XCTUnwrap(frame.currentMagnitude(of: comet)), accuracy: 1e-9)
        let horizontal = try XCTUnwrap(frame.horizontal(of: body, refraction: true))
        XCTAssertEqual(result.altitude, horizontal.altitude, accuracy: 1e-9)
    }

    // MARK: A recorded skyline

    func testAnObjectAlwaysBehindTheSkylineNeverClearsIt() throws {
        // Declination +80 stays between 30 and 50 degrees; a 60-degree skyline hides it for good.
        let result = try position(of: ObjectsPositionFixture.target(30, 80), skyline: HorizonProfile.constant(60))
        XCTAssertTrue(result.usesSkyline)
        XCTAssertFalse(result.isAboveHorizon)
        XCTAssertTrue(result.isBehindSkyline)
        XCTAssertTrue(result.neverRises)
        XCTAssertFalse(result.noRiseInWindow)
        XCTAssertNil(result.nextRise)
        XCTAssertGreaterThan(result.altitude, 25, "it is above the horizon itself")
    }

    func testAnObjectAlwaysAboveTheSkylineIsUp() throws {
        let result = try position(of: ObjectsPositionFixture.target(30, 80), skyline: HorizonProfile.constant(10))
        XCTAssertTrue(result.usesSkyline)
        XCTAssertTrue(result.isAboveHorizon)
        XCTAssertFalse(result.isBehindSkyline)
        XCTAssertFalse(result.neverRises)
        XCTAssertNil(result.nextRise)
    }

    func testAnObjectBelowTheHorizonIsNotBehindTheSkyline() throws {
        let result = try position(of: ObjectsPositionFixture.target(30, -80), skyline: HorizonProfile.constant(10))
        XCTAssertFalse(result.isAboveHorizon)
        XCTAssertFalse(result.isBehindSkyline, "it is below the horizon, not hidden by the skyline")
        XCTAssertTrue(result.neverRises)
    }

    func testTheRisingOverASkylineIsTheObjectClearingIt() throws {
        let object = ObjectsPositionFixture.target(30, 0)
        let profile = HorizonProfile.constant(10)
        let result = try position(of: object, skyline: profile)
        let visibility = HorizonVisibility(profile: profile)
        let expected = visibility.riseTransitSet(forJ2000: EquatorialCoordinate(rightAscension: 30, declination: 0),
                                                 observer: ObjectsPositionFixture.denver,
                                                 within: ObjectsPositionFixture.window(from: ObjectsPositionFixture.evening))
        XCTAssertEqual(result.nextRise, expected.rise)
        let horizontal = SkyFrame(date: ObjectsPositionFixture.evening, observer: ObjectsPositionFixture.denver)
            .horizontal(of: object, refraction: true)
        XCTAssertEqual(result.isAboveHorizon, visibility.isVisible(altitude: horizontal.altitude,
                                                                   azimuth: horizontal.azimuth, refracted: true))
        XCTAssertTrue(result.usesSkyline)
    }

    func testPositionsOfTheSameInstantAreEqualAndOthersAreNot() throws {
        let object = ObjectsPositionFixture.target(30, 0)
        let first = try position(of: object)
        XCTAssertEqual(first, try position(of: object))
        XCTAssertNotEqual(first, try position(of: object, date: ObjectsPositionFixture.evening.addingTimeInterval(600)))
    }
}

// MARK: - The model

@MainActor
final class ObjectsPositionModelTests: XCTestCase {
    private let first = ObjectsPositionFixture.target(30, 0)
    private let second = ObjectsPositionFixture.target(100, 45)

    /// Polls until `condition` holds, giving the position computation (a detached task) time to finish.
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(30)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    /// Runs `keepFresh` until `condition` holds (or time runs out), then cancels it.
    private func run(_ model: ObjectsPositionModel, observer: Observer = ObjectsPositionFixture.denver,
                     skyline: HorizonProfile? = nil, clock: SkyClock, tracking objects: [CelestialObject],
                     until condition: @MainActor () -> Bool) async -> Bool {
        let task = Task {
            await model.keepFresh(observer: observer, skyline: skyline, clock: clock, tracking: { objects })
        }
        let reached = await waitUntil(condition)
        task.cancel()
        await task.value
        return reached
    }

    func testTheConstants() {
        XCTAssertEqual(ObjectsPositionModel.refreshInterval, .seconds(30))
        XCTAssertEqual(ObjectsPositionModel.reuseAge, 25)
    }

    func testANewModelKnowsNoPositions() {
        let model = ObjectsPositionModel()
        XCTAssertTrue(model.positions.isEmpty)
        XCTAssertNil(model.position(for: first.id))
    }

    func testKeepFreshComputesThePositionsOfTheTrackedObjects() async throws {
        let model = ObjectsPositionModel()
        let clock = SkyClock()
        let reached = await run(model, clock: clock, tracking: [first, second]) { model.positions.count == 2 }
        XCTAssertTrue(reached)
        let expected = ObjectsPositionCalculator.positions(for: [first, second], observer: ObjectsPositionFixture.denver,
                                                           skyline: nil, date: clock.now)
        XCTAssertEqual(model.positions, expected)
        XCTAssertEqual(model.position(for: first.id), expected[first.id])
        XCTAssertEqual(model.position(for: second.id)?.computedAt, clock.now)
        XCTAssertNil(model.position(for: "not.tracked"))
    }

    func testATaskCancelledBeforeItStartsComputesNothing() async {
        let model = ObjectsPositionModel()
        let clock = SkyClock()
        let objects = [first]
        let task = Task {
            await model.keepFresh(observer: ObjectsPositionFixture.denver, skyline: nil, clock: clock,
                                  tracking: { objects })
        }
        task.cancel()
        await task.value
        XCTAssertTrue(model.positions.isEmpty)
    }

    func testNothingTrackedLeavesThePositionsEmpty() async {
        let model = ObjectsPositionModel()
        let clock = SkyClock()
        let nothing: [CelestialObject] = []
        let task = Task {
            await model.keepFresh(observer: ObjectsPositionFixture.denver, skyline: nil, clock: clock,
                                  tracking: { nothing })
        }
        // Give the first pass time to run: nothing is outdated, so nothing is computed.
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value
        XCTAssertTrue(model.positions.isEmpty)
    }

    func testAnotherPlaceReplacesEveryPosition() async {
        let model = ObjectsPositionModel()
        let clock = SkyClock()
        let one = await run(model, clock: clock, tracking: [first, second]) { model.positions.count == 2 }
        XCTAssertTrue(one)
        // Another observer: only the objects now tracked are kept, and they are computed for the new place.
        let two = await run(model, observer: ObjectsPositionFixture.sydney, clock: clock, tracking: [first]) {
            model.positions.count == 1
        }
        XCTAssertTrue(two)
        let expected = ObjectsPositionCalculator.positions(for: [first], observer: ObjectsPositionFixture.sydney,
                                                           skyline: nil, date: clock.now)
        XCTAssertEqual(model.positions, expected)
        XCTAssertNil(model.position(for: second.id))
    }

    func testAnotherSkylineReplacesEveryPosition() async {
        let model = ObjectsPositionModel()
        let clock = SkyClock()
        let one = await run(model, clock: clock, tracking: [first]) { model.positions.count == 1 }
        XCTAssertTrue(one)
        XCTAssertEqual(model.position(for: first.id)?.usesSkyline, false)
        let skyline = HorizonProfile.constant(10)
        let two = await run(model, skyline: skyline, clock: clock, tracking: [first, second]) {
            model.positions.count == 2
        }
        XCTAssertTrue(two)
        XCTAssertEqual(model.position(for: first.id)?.usesSkyline, true)
        XCTAssertEqual(model.position(for: second.id)?.usesSkyline, true)
    }

    func testNewlyTrackedObjectsAreAddedAndTheOthersKeepTheirPositions() async {
        let model = ObjectsPositionModel()
        let clock = SkyClock()
        let one = await run(model, clock: clock, tracking: [first]) { model.positions.count == 1 }
        XCTAssertTrue(one)
        let before = model.position(for: first.id)
        // The same place: the first object's position is still fresh and stays; the second is computed.
        let two = await run(model, clock: clock, tracking: [second]) { model.positions.count == 2 }
        XCTAssertTrue(two)
        XCTAssertEqual(model.position(for: first.id), before)
        XCTAssertNotNil(model.position(for: second.id))
    }

    func testClearForgetsEveryPosition() async {
        let model = ObjectsPositionModel()
        let clock = SkyClock()
        let one = await run(model, clock: clock, tracking: [first, second]) { model.positions.count == 2 }
        XCTAssertTrue(one)
        model.clear()
        XCTAssertTrue(model.positions.isEmpty)
        XCTAssertNil(model.position(for: first.id))
        // Positions can be computed again afterwards.
        let two = await run(model, clock: clock, tracking: [second]) { model.positions.count == 1 }
        XCTAssertTrue(two)
        XCTAssertNil(model.position(for: first.id))
        XCTAssertNotNil(model.position(for: second.id))
    }

    func testKeepFreshComputesForTheClocksNowAndTheSkylineGiven() async {
        let model = ObjectsPositionModel()
        let clock = SkyClock()
        let profile = HorizonProfile.constant(60)
        let high = ObjectsPositionFixture.target(30, 80)
        let reached = await run(model, skyline: profile, clock: clock, tracking: [high]) { model.positions.count == 1 }
        XCTAssertTrue(reached)
        let position = model.position(for: high.id)
        XCTAssertEqual(position?.usesSkyline, true)
        XCTAssertEqual(position?.isBehindSkyline, true)
        XCTAssertEqual(position?.neverRises, true)
        XCTAssertEqual(position?.computedAt, clock.now)
    }

    #if DEBUG
    // The clock can be frozen at an instant only in debug builds, which is how `swift test` builds.

    private func frozenClock(at date: Date) -> SkyClock {
        let clock = SkyClock()
        clock.freeze(at: date)
        return clock
    }

    func testPositionsComputedLessThanTwentyFiveSecondsAgoAreReused() async {
        let model = ObjectsPositionModel()
        let start = ObjectsPositionFixture.evening
        let one = await run(model, clock: frozenClock(at: start), tracking: [first]) { model.positions.count == 1 }
        XCTAssertTrue(one)
        XCTAssertEqual(model.position(for: first.id)?.computedAt, start)
        // Ten seconds later the tracked set grows: the first position is reused, the new one is computed now.
        let later = start.addingTimeInterval(10)
        let two = await run(model, clock: frozenClock(at: later), tracking: [first, second]) { model.positions.count == 2 }
        XCTAssertTrue(two)
        XCTAssertEqual(model.position(for: first.id)?.computedAt, start)
        XCTAssertEqual(model.position(for: second.id)?.computedAt, later)
    }

    func testAPositionExactlyTwentyFiveSecondsOldIsStillReused() async {
        let model = ObjectsPositionModel()
        let start = ObjectsPositionFixture.evening
        let one = await run(model, clock: frozenClock(at: start), tracking: [first]) { model.positions.count == 1 }
        XCTAssertTrue(one)
        let later = start.addingTimeInterval(25)
        let two = await run(model, clock: frozenClock(at: later), tracking: [first, second]) { model.positions.count == 2 }
        XCTAssertTrue(two)
        XCTAssertEqual(model.position(for: first.id)?.computedAt, start, "25 s old is not older than the reuse age")
        XCTAssertEqual(model.position(for: second.id)?.computedAt, later)
    }

    func testPositionsOlderThanTwentyFiveSecondsAreComputedAgain() async {
        let model = ObjectsPositionModel()
        let start = ObjectsPositionFixture.evening
        let one = await run(model, clock: frozenClock(at: start), tracking: [first, second]) { model.positions.count == 2 }
        XCTAssertTrue(one)
        // 26 s later both are stale.
        let later = start.addingTimeInterval(26)
        let two = await run(model, clock: frozenClock(at: later), tracking: [first, second]) {
            model.position(for: first.id)?.computedAt == later && model.position(for: second.id)?.computedAt == later
        }
        XCTAssertTrue(two)
        XCTAssertEqual(model.positions.count, 2)
    }

    func testOnlyTheStalePositionsAreComputedAgain() async {
        let model = ObjectsPositionModel()
        let start = ObjectsPositionFixture.evening
        let one = await run(model, clock: frozenClock(at: start), tracking: [first]) { model.positions.count == 1 }
        XCTAssertTrue(one)
        let middle = start.addingTimeInterval(20)
        let two = await run(model, clock: frozenClock(at: middle), tracking: [first, second]) { model.positions.count == 2 }
        XCTAssertTrue(two)
        // At +30 s the first is 30 s old (stale) and the second 10 s old (fresh).
        let end = start.addingTimeInterval(30)
        let three = await run(model, clock: frozenClock(at: end), tracking: [first, second]) {
            model.position(for: first.id)?.computedAt == end
        }
        XCTAssertTrue(three)
        XCTAssertEqual(model.position(for: second.id)?.computedAt, middle)
    }
    #endif
}
