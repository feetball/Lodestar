import XCTest
@testable import LodestarKit

/// The SGP4 verification vectors are in `Sgp4VerificationTests`; these tests cover the rest of the propagator API.
final class Sgp4PropagatorTests: XCTestCase {
    private typealias Support = SatelliteTestSupport

    func testStatesMatchThePythonSgp4PackageForEveryOrbitType() throws {
        // The `sgp4` package (Brandon Rhodes' port of the same reference code) for the element sets of the
        // CelesTrak snapshot, at times from 12 hours before to two weeks after the epoch.
        let satellites = try Support.referenceSatellites()
        let reference = try Support.jsonObject("satellite_reference.json")
        var worstPosition = 0.0
        var worstVelocity = 0.0
        let states = Support.list(reference, "sgp4States")
        XCTAssertEqual(states.count, 48)
        for entry in states {
            let id = Support.text(entry, "satellite")
            let minutes = Support.number(entry, "minutes")
            let result = try XCTUnwrap(satellites[id]).propagator.propagate(minutesSinceEpoch: minutes)
            XCTAssertEqual(Int(Support.number(entry, "error")), 0)
            let state = try XCTUnwrap(result.state, "\(id) at \(minutes) min")
            let position = Support.numbers(entry, "position")
            let velocity = Support.numbers(entry, "velocity")
            worstPosition = max(worstPosition, max(abs(state.position.x - position[0]), max(abs(state.position.y - position[1]), abs(state.position.z - position[2]))))
            worstVelocity = max(worstVelocity, max(abs(state.velocity.x - velocity[0]), max(abs(state.velocity.y - velocity[1]), abs(state.velocity.z - velocity[2]))))
        }
        print("sgp4 package: worst position difference \(worstPosition) km, velocity \(worstVelocity) km/s")
        XCTAssertLessThan(worstPosition, 1e-7)
        XCTAssertLessThan(worstVelocity, 1e-10)
    }

    func testTheOrbitTypesAreRecognized() throws {
        let satellites = try Support.referenceSatellites()
        func propagator(_ id: String) throws -> Sgp4Propagator { try XCTUnwrap(satellites[id]).propagator }
        XCTAssertFalse(try propagator("iss").isDeepSpace)
        XCTAssertFalse(try propagator("starlink").isDeepSpace)
        XCTAssertFalse(try propagator("polar").isDeepSpace)
        XCTAssertTrue(try propagator("gps").isDeepSpace)
        XCTAssertTrue(try propagator("molniya").isDeepSpace)
        XCTAssertTrue(try propagator("geo").isDeepSpace)
        let iss = try propagator("iss")
        XCTAssertTrue((380.0...440.0).contains(iss.perigeeAltitudeKilometers), "perigee \(iss.perigeeAltitudeKilometers)")
        XCTAssertTrue((iss.perigeeAltitudeKilometers...450.0).contains(iss.apogeeAltitudeKilometers))
        XCTAssertTrue((1.05...1.07).contains(iss.semiMajorAxisEarthRadii))
        let molniya = try propagator("molniya")
        XCTAssertGreaterThan(molniya.apogeeAltitudeKilometers, 35_000.0)
        XCTAssertLessThan(molniya.perigeeAltitudeKilometers, 2_500.0)
    }

    func testTheResultDoesNotDependOnTheOrderOfTheCalls() throws {
        // The reference resumes its resonance integration from the previous call; this port restarts it, which
        // must give the same numbers whatever was asked before.
        let satellites = try Support.referenceSatellites()
        for id in ["molniya", "geo", "gps", "iss"] {
            let propagator = try XCTUnwrap(satellites[id]).propagator
            let times = [3000.0, 100.0, -500.0, 3000.0, 20_000.0, 3000.0, -20_000.0, 0.0, 3000.0]
            let first = times.map { propagator.propagate(minutesSinceEpoch: $0).state }
            let again = Array(times.reversed().map { propagator.propagate(minutesSinceEpoch: $0).state }.reversed())
            XCTAssertEqual(first, again, id)
            XCTAssertEqual(first[0], first[3])
            XCTAssertEqual(first[0], first[5])
            XCTAssertEqual(first[0], first[8])
            XCTAssertEqual(first[0], Sgp4Propagator(elements: propagator.elements).propagate(minutesSinceEpoch: 3000.0).state)
        }
    }

    func testStateAtADateUsesTheEpoch() throws {
        let propagator = try XCTUnwrap(Support.referenceSatellites()["iss"]).propagator
        let epoch = propagator.elements.epoch
        XCTAssertEqual(propagator.propagate(minutesSinceEpoch: 0.0), propagator.state(at: epoch))
        XCTAssertEqual(propagator.minutesSince(epoch), 0.0, accuracy: 1e-9)
        XCTAssertEqual(propagator.minutesSince(epoch.addingTimeInterval(5400.0)), 90.0, accuracy: 1e-9)
        let later = try XCTUnwrap(propagator.state(at: epoch.addingTimeInterval(5400.0)).state)
        let direct = try XCTUnwrap(propagator.propagate(minutesSinceEpoch: 90.0).state)
        XCTAssertEqual(direct.position.x, later.position.x, accuracy: 1e-6)
        XCTAssertEqual(direct.velocity.z, later.velocity.z, accuracy: 1e-9)
    }

    func testTheIssStaysOnItsOrbit() throws {
        let propagator = try XCTUnwrap(Support.referenceSatellites()["iss"]).propagator
        for minutes in [0.0, 30.0, 90.0, 1000.0, -2000.0] {
            let state = try XCTUnwrap(propagator.propagate(minutesSinceEpoch: minutes).state)
            let radius = state.position.length
            XCTAssertTrue((6_700.0...6_850.0).contains(radius), "radius \(radius) at \(minutes)")
            let speed = state.velocity.length
            XCTAssertTrue((7.6...7.7).contains(speed), "speed \(speed) at \(minutes)")
            // Angular momentum is perpendicular to the position and has the orbit's inclination.
            let momentum = state.position.cross(state.velocity)
            XCTAssertEqual(AstroMath.degrees(acos(momentum.z / momentum.length)), 51.64, accuracy: 0.05)
        }
    }

    func testFailuresAreReportedWithTheReferencesCodes() throws {
        let propagator = try XCTUnwrap(Support.referenceSatellites()["iss"]).propagator
        XCTAssertEqual(propagator.propagate(minutesSinceEpoch: .nan).error, .nonFiniteState)
        XCTAssertEqual(propagator.propagate(minutesSinceEpoch: .infinity).error, .nonFiniteState)
        XCTAssertEqual(propagator.propagate(minutesSinceEpoch: Sgp4Propagator.maximumMinutesFromEpoch * 1.01).error, .timeOutOfRange)
        XCTAssertEqual(propagator.propagate(minutesSinceEpoch: -2e7).error, .timeOutOfRange)
        XCTAssertNil(propagator.propagate(minutesSinceEpoch: .nan).state)
        XCTAssertNil(propagator.propagate(minutesSinceEpoch: 0.0).error)
        XCTAssertEqual(Sgp4Error.allCases.map(\.rawValue), [1, 2, 3, 4, 6, 7, 8])
        XCTAssertEqual(Sgp4Error(rawValue: 6), .decayed)
        XCTAssertNil(Sgp4Error(rawValue: 5))
        XCTAssertEqual(Sgp4Error.decayed.code, 6)
        // A satellite a day after its elements say it re-entered.
        let decayed = try OrbitalElements(
            catalogNumber: 28872, epoch: Support.date(1_133_226_000.0), meanMotion: 16.46015938, eccentricity: 0.0303955,
            inclination: 96.4736, rightAscensionOfAscendingNode: 157.9986, argumentOfPericenter: 244.0492,
            meanAnomaly: 110.6523, bstar: 0.24476e-3, meanMotionDot: 0.25992681
        )
        XCTAssertEqual(Sgp4Propagator(elements: decayed).propagate(minutesSinceEpoch: 60.0).error, .decayed)
    }

    func testResultsAreImmutableValues() throws {
        let satellites = try Support.referenceSatellites()
        let a = try XCTUnwrap(satellites["molniya"]).propagator
        let b = Sgp4Propagator(elements: a.elements)
        XCTAssertEqual(a.propagate(minutesSinceEpoch: 1234.5), b.propagate(minutesSinceEpoch: 1234.5))
        XCTAssertEqual(a.semiMajorAxisEarthRadii, b.semiMajorAxisEarthRadii, accuracy: 0.0)
        XCTAssertGreaterThan(a.maximumSpeedKilometersPerSecond, 9.0)  // Molniya: 10 km/s at perigee
        XCTAssertTrue((7.7...9.0).contains(try XCTUnwrap(satellites["iss"]).propagator.maximumSpeedKilometersPerSecond))
    }
}
