import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Features/Mount/MountTargets.swift: what the mount control works out about a target before it sends it (the J2000 place, the
/// altitude now and a minute from now, the Sun refusal) and the words about how far and which way a slew turns the mount.
final class MountNetTargetsTests: XCTestCase {
    /// 2026-10-18 04:00 UTC: night in Colorado.
    private static let night = Date(timeIntervalSince1970: 1_792_296_000)
    /// 2026-10-18 19:00 UTC: 13 minutes after local apparent noon in Boulder.
    private static let noon = Date(timeIntervalSince1970: 1_792_350_000)
    private static let observer = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    private static let catalog = Result { try Catalog.loadBundled() }

    private func loadedCatalog() throws -> Catalog { try Self.catalog.get() }

    private func frame(_ date: Date = MountNetTargetsTests.night) -> SkyFrame {
        SkyFrame(date: date, observer: Self.observer)
    }

    /// The angle between two azimuths, degrees, however they wrap.
    private func azimuthDifference(_ first: Double, _ second: Double) -> Double {
        abs(AstroMath.normalizeSignedDegrees(first - second))
    }

    private func star(_ name: String, hours: Double, declination: Double) -> CelestialObject {
        CelestialObject.custom(name: name, j2000: EquatorialCoordinate(rightAscensionHours: hours, declination: declination))
    }

    /// A place of the sky given by where it stands for the observer at `night` (no refraction).
    private func place(azimuth: Double, altitude: Double) -> EquatorialCoordinate {
        frame().j2000(fromHorizontal: HorizontalCoordinate(azimuth: azimuth, altitude: altitude), refracted: false)
    }

    private func target(azimuth: Double, altitude: Double) -> MountResolvedTarget {
        let object = CelestialObject.custom(name: "Test", j2000: place(azimuth: azimuth, altitude: altitude))
        return MountTargets.resolve(object, observer: Self.observer, date: Self.night)
    }

    private func makePlan(from start: (azimuth: Double, altitude: Double)?, to end: (azimuth: Double, altitude: Double)) -> MountSlewPlan {
        MountSlewPlan(target: target(azimuth: end.azimuth, altitude: end.altitude),
                      mountPosition: start.map { place(azimuth: $0.azimuth, altitude: $0.altitude) },
                      observer: Self.observer, date: Self.night)
    }

    // MARK: Constants

    func testTheLookaheadIsTheOneTheEngineUses() {
        XCTAssertEqual(MountTargets.lookaheadSeconds, 60.0)
        XCTAssertEqual(MountTargets.lookaheadSeconds, MountSettings.standard.horizonLookaheadSeconds)
    }

    func testTheSunRefusalSaysWhy() {
        XCTAssertTrue(MountTargets.sunRefusal.hasPrefix("Lodestar never slews a mount to the Sun."), MountTargets.sunRefusal)
        XCTAssertTrue(MountTargets.sunRefusal.contains("certified solar filter"), MountTargets.sunRefusal)
        XCTAssertTrue(MountTargets.sunRefusal.hasSuffix("destroys eyesight and equipment."), MountTargets.sunRefusal)
    }

    // MARK: The Sun

    func testOnlyTheSunIsTheSun() throws {
        let catalog = try loadedCatalog()
        XCTAssertTrue(MountTargets.isSun(try XCTUnwrap(catalog.object(id: "sun"))))
        XCTAssertFalse(MountTargets.isSun(try XCTUnwrap(catalog.object(id: "moon"))))
        XCTAssertFalse(MountTargets.isSun(try XCTUnwrap(catalog.object(id: "planet.mars"))))
        XCTAssertFalse(MountTargets.isSun(try XCTUnwrap(catalog.object(id: "star.hip32349"))), "Sirius")
        XCTAssertFalse(MountTargets.isSun(star("Not the Sun", hours: 12, declination: 0)))
    }

    // MARK: Fixed places

    func testAFixedObjectKeepsItsCatalogPlace() {
        let object = star("Vega", hours: 18.6156, declination: 38.7837)
        let resolved = MountTargets.resolve(object, observer: Self.observer, date: Self.night)
        XCTAssertEqual(resolved.j2000, object.j2000)
        XCTAssertNil(resolved.properMotion)
        XCTAssertEqual(resolved.object.id, object.id)
    }

    func testAStarThatSetsIsLowestAMinuteFromNow() {
        // Vega is in the north-west, 43 degrees up and going down at about 0.18 degrees a minute.
        let resolved = MountTargets.resolve(star("Vega", hours: 18.6156, declination: 38.7837), observer: Self.observer, date: Self.night)
        XCTAssertEqual(resolved.altitude, 42.9, accuracy: 1.5)
        XCTAssertEqual(resolved.azimuth, 289.6, accuracy: 3.0)
        let drop = resolved.altitude - resolved.lowestAltitude
        XCTAssertGreaterThan(drop, 0.10)
        XCTAssertLessThan(drop, 0.30)
    }

    func testAStarThatRisesIsLowestRightNow() {
        // Capella is low in the north-east and climbing.
        let resolved = MountTargets.resolve(star("Capella", hours: 5.2782, declination: 45.998), observer: Self.observer, date: Self.night)
        XCTAssertEqual(resolved.altitude, 23.0, accuracy: 1.5)
        XCTAssertEqual(resolved.azimuth, 48.4, accuracy: 3.0)
        XCTAssertEqual(resolved.lowestAltitude, resolved.altitude)
    }

    func testTheAltitudeIsGeometricAndNotRefracted() {
        // 0.2 degrees up as the geometry has it; refraction would show it at about 0.7.
        let resolved = target(azimuth: 90, altitude: 0.2)
        XCTAssertEqual(resolved.altitude, 0.2, accuracy: 0.01)
        XCTAssertLessThan(resolved.altitude, 0.4)
    }

    func testBelowTheHorizonIsNegative() {
        let resolved = target(azimuth: 200, altitude: -12)
        XCTAssertEqual(resolved.altitude, -12, accuracy: 0.01)
        XCTAssertLessThanOrEqual(resolved.lowestAltitude, resolved.altitude)
        XCTAssertEqual(resolved.azimuth, 200, accuracy: 0.05)
    }

    func testTheLowestAltitudeNeverExceedsTheAltitudeNow() {
        for (azimuth, altitude) in [(10.0, 30.0), (100.0, 60.0), (190.0, 45.0), (280.0, 20.0), (350.0, 5.0)] {
            let resolved = target(azimuth: azimuth, altitude: altitude)
            XCTAssertLessThanOrEqual(resolved.lowestAltitude, resolved.altitude, "azimuth \(azimuth)")
            XCTAssertEqual(resolved.azimuth, azimuth, accuracy: 0.05)
            XCTAssertEqual(resolved.altitude, altitude, accuracy: 0.05)
        }
    }

    func testTheProperMotionOfACatalogStarIsKept() throws {
        let vega = try XCTUnwrap(try loadedCatalog().object(id: "star.hip91262"))
        guard case .fixed(let coordinate, let motion) = vega.position else { return XCTFail("Vega is a fixed object") }
        let resolved = MountTargets.resolve(vega, observer: Self.observer, date: Self.night)
        XCTAssertEqual(resolved.j2000, coordinate)
        XCTAssertEqual(resolved.properMotion, motion)
        // The place now is the one with the proper motion applied, as the sky frame has it.
        let expected = frame().horizontal(j2000: coordinate, properMotion: motion, refraction: false)
        XCTAssertEqual(resolved.altitude, expected.altitude, accuracy: 1e-9)
        XCTAssertEqual(resolved.azimuth, expected.azimuth, accuracy: 1e-9)
        XCTAssertEqual(resolved.altitude, 42.9, accuracy: 1.5)
    }

    // MARK: Moving objects and the poles

    func testTheSunAtNoonIsHighInTheSouth() throws {
        let sun = try XCTUnwrap(try loadedCatalog().object(id: "sun"))
        let resolved = MountTargets.resolve(sun, observer: Self.observer, date: Self.noon)
        XCTAssertEqual(resolved.altitude, 40.3, accuracy: 1.5)
        XCTAssertGreaterThan(resolved.azimuth, 180.0)
        XCTAssertLessThan(resolved.azimuth, 190.0)
        XCTAssertNil(resolved.properMotion)
        // Its place among the stars: right ascension about 13.5 hours, declination about -9.6 degrees.
        XCTAssertEqual(resolved.j2000.rightAscensionHours, 13.48, accuracy: 0.15)
        XCTAssertEqual(resolved.j2000.declination, -9.6, accuracy: 0.6)
    }

    func testTheSunIsBelowTheHorizonAtNight() throws {
        let sun = try XCTUnwrap(try loadedCatalog().object(id: "sun"))
        let resolved = MountTargets.resolve(sun, observer: Self.observer, date: Self.night)
        XCTAssertLessThan(resolved.altitude, -20.0)
    }

    func testAMovingObjectIsPinnedToItsPlaceNow() throws {
        let moon = try XCTUnwrap(try loadedCatalog().object(id: "moon"))
        let resolved = MountTargets.resolve(moon, observer: Self.observer, date: Self.night)
        let now = frame().horizontal(of: moon, refraction: false)
        XCTAssertEqual(resolved.altitude, now.altitude, accuracy: 0.01)
        XCTAssertLessThan(azimuthDifference(resolved.azimuth, now.azimuth), 0.01)
        XCTAssertNil(resolved.properMotion)
        XCTAssertEqual(resolved.object.id, "moon")
        // Treated as a fixed place, so a minute from now it is where the sky has moved that place to.
        let later = frame(Self.night.addingTimeInterval(MountTargets.lookaheadSeconds))
            .horizontal(j2000: resolved.j2000, properMotion: nil, refraction: false)
        XCTAssertEqual(resolved.lowestAltitude, min(resolved.altitude, later.altitude), accuracy: 1e-9)
    }

    func testAPlanetGetsAPlaceToo() throws {
        let mars = try XCTUnwrap(try loadedCatalog().object(id: "planet.mars"))
        let resolved = MountTargets.resolve(mars, observer: Self.observer, date: Self.night)
        let now = frame().horizontal(of: mars, refraction: false)
        XCTAssertEqual(resolved.altitude, now.altitude, accuracy: 0.01)
        XCTAssertNil(resolved.properMotion)
        XCTAssertTrue((0.0...360.0).contains(resolved.j2000.rightAscension))
        XCTAssertTrue((-90.0...90.0).contains(resolved.j2000.declination))
    }

    func testTheNorthCelestialPoleStandsAtTheLatitude() throws {
        let pole = try XCTUnwrap(try loadedCatalog().object(id: "special.ncp"))
        let resolved = MountTargets.resolve(pole, observer: Self.observer, date: Self.night)
        XCTAssertEqual(resolved.altitude, 40.015, accuracy: 0.02)
        XCTAssertLessThan(azimuthDifference(resolved.azimuth, 0), 0.05)
        // It does not move, so a minute from now is no lower.
        XCTAssertEqual(resolved.lowestAltitude, resolved.altitude, accuracy: 0.01)
        // The pole of date lies a third of a degree from the J2000 pole.
        XCTAssertGreaterThan(resolved.j2000.declination, 89.5)
        XCTAssertLessThan(resolved.j2000.declination, 89.9)
    }

    // MARK: Slew plans

    func testWithoutAMountPositionThePlanKnowsNothing() {
        let plan = makePlan(from: nil, to: (azimuth: 270, altitude: 55))
        XCTAssertNil(plan.start)
        XCTAssertNil(plan.separation)
        XCTAssertNil(plan.azimuthTurn)
        XCTAssertNil(plan.altitudeChange)
        XCTAssertEqual(plan.distanceText, "From wherever it points now.")
        XCTAssertNil(plan.directionText)
    }

    func testThePlanMeasuresTheTurnAndTheClimb() throws {
        let plan = makePlan(from: (azimuth: 180, altitude: 40), to: (azimuth: 270, altitude: 55))
        let start = try XCTUnwrap(plan.start)
        XCTAssertEqual(start.altitude, 40, accuracy: 0.01)
        XCTAssertEqual(start.azimuth, 180, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(plan.azimuthTurn), 90, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(plan.altitudeChange), 15, accuracy: 0.05)
        // Great-circle distance between a place due south at 40 degrees and one due west at 55 degrees.
        XCTAssertEqual(try XCTUnwrap(plan.separation), 58.2, accuracy: 0.2)
    }

    func testTheDistanceIsTold() {
        let plan = makePlan(from: (azimuth: 180, altitude: 40), to: (azimuth: 270, altitude: 55))
        XCTAssertEqual(plan.distanceText, "About 58\u{00B0} across the sky.")
    }

    func testAClockwiseTurnWhileRising() {
        let plan = makePlan(from: (azimuth: 180, altitude: 40), to: (azimuth: 270, altitude: 55))
        XCTAssertEqual(plan.directionText, "It turns 90\u{00B0} clockwise seen from above and rises 15\u{00B0}.")
    }

    func testACounterClockwiseTurnWhileDropping() throws {
        let plan = makePlan(from: (azimuth: 270, altitude: 55), to: (azimuth: 180, altitude: 40))
        XCTAssertEqual(try XCTUnwrap(plan.azimuthTurn), -90, accuracy: 0.05)
        XCTAssertEqual(plan.directionText, "It turns 90\u{00B0} counter-clockwise seen from above and drops 15\u{00B0}.")
    }

    func testTheTurnTakesTheShortWayAcrossNorth() throws {
        let across = makePlan(from: (azimuth: 350, altitude: 45), to: (azimuth: 10, altitude: 45))
        XCTAssertEqual(try XCTUnwrap(across.azimuthTurn), 20, accuracy: 0.05)
        XCTAssertEqual(across.directionText, "It turns 20\u{00B0} clockwise seen from above.")
        let back = makePlan(from: (azimuth: 10, altitude: 45), to: (azimuth: 350, altitude: 45))
        XCTAssertEqual(try XCTUnwrap(back.azimuthTurn), -20, accuracy: 0.05)
        XCTAssertEqual(back.directionText, "It turns 20\u{00B0} counter-clockwise seen from above.")
    }

    func testOnlyAClimbIsMentionedWhenThereIsNoTurn() {
        let up = makePlan(from: (azimuth: 200, altitude: 30), to: (azimuth: 200, altitude: 42))
        XCTAssertEqual(up.directionText, "It rises 12\u{00B0}.")
        let down = makePlan(from: (azimuth: 200, altitude: 42), to: (azimuth: 200, altitude: 30))
        XCTAssertEqual(down.directionText, "It drops 12\u{00B0}.")
    }

    func testSmallAnglesAreShownWithADecimal() {
        let small = makePlan(from: (azimuth: 180, altitude: 40), to: (azimuth: 183, altitude: 40))
        XCTAssertEqual(small.directionText, "It turns 3.0\u{00B0} clockwise seen from above.")
    }

    func testATurnOfMoreThanADegreeIsMentionedAndOneOfLessIsNot() {
        let more = makePlan(from: (azimuth: 180, altitude: 40), to: (azimuth: 181.2, altitude: 40))
        XCTAssertEqual(more.directionText, "It turns 1.2\u{00B0} clockwise seen from above.")
        let less = makePlan(from: (azimuth: 180, altitude: 40), to: (azimuth: 180.8, altitude: 40))
        XCTAssertEqual(less.directionText, "It moves only a little.")
    }

    func testAChangeOfLessThanADegreeInBothIsOnlyALittle() {
        let plan = makePlan(from: (azimuth: 180, altitude: 40), to: (azimuth: 180.5, altitude: 40.5))
        XCTAssertEqual(plan.directionText, "It moves only a little.")
    }

    func testPointingAtTheTargetAlreadyIsOnlyALittle() throws {
        let plan = makePlan(from: (azimuth: 120, altitude: 35), to: (azimuth: 120, altitude: 35))
        XCTAssertEqual(try XCTUnwrap(plan.separation), 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(plan.azimuthTurn), 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(plan.altitudeChange), 0, accuracy: 0.01)
        XCTAssertEqual(plan.directionText, "It moves only a little.")
        XCTAssertTrue(plan.distanceText.hasPrefix("About "), plan.distanceText)
        XCTAssertTrue(plan.distanceText.hasSuffix(" across the sky."), plan.distanceText)
    }

    func testThePlanKeepsItsTarget() {
        let plan = makePlan(from: (azimuth: 180, altitude: 40), to: (azimuth: 270, altitude: 55))
        XCTAssertEqual(plan.target.altitude, 55, accuracy: 0.05)
        XCTAssertEqual(plan.target.azimuth, 270, accuracy: 0.05)
    }

    func testTheSeparationIsTheSameBothWays() throws {
        let forward = makePlan(from: (azimuth: 20, altitude: 30), to: (azimuth: 140, altitude: 60))
        let backward = makePlan(from: (azimuth: 140, altitude: 60), to: (azimuth: 20, altitude: 30))
        XCTAssertEqual(try XCTUnwrap(forward.separation), try XCTUnwrap(backward.separation), accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(forward.azimuthTurn), -(try XCTUnwrap(backward.azimuthTurn)), accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(forward.altitudeChange), -(try XCTUnwrap(backward.altitudeChange)), accuracy: 1e-6)
    }
}
