import XCTest
@testable import LodestarKit

/// `Satellite`, `SatelliteLook` and the Aim-screen support: where the satellite is, now and at culmination.
final class SatelliteTests: XCTestCase {
    private typealias Support = SatelliteTestSupport
    private let boulder = SatelliteTestSupport.boulder

    private func iss() throws -> Satellite { try XCTUnwrap(Support.referenceSatellites()["iss"]) }

    // The pass of 2026-10-18 11:23:54 - 11:30:40 UTC over Boulder: culmination 74.95 degrees at 11:27:16; the ISS
    // leaves the Earth's shadow at 11:27:45 and the sky is dark (Skyfield: SatelliteReferenceTests).
    private func culminationPass() throws -> SatellitePass {
        let finder = SatellitePassFinder(observer: boulder, interval: DateInterval(start: Support.iso("2026-10-18T11:00:00Z"), duration: 3600.0))
        let passes = finder.passes(of: try iss())
        XCTAssertEqual(passes.count, 1)
        return try XCTUnwrap(passes.first)
    }

    func testLookAtCulminationMatchesThePass() throws {
        let pass = try culminationPass()
        let satellite = try iss()
        let look = try XCTUnwrap(satellite.look(at: pass.culmination.date, observer: boulder))
        XCTAssertEqual(look.altitude, pass.culmination.altitude, accuracy: 1e-6)
        XCTAssertEqual(look.azimuth, pass.culmination.azimuth, accuracy: 1e-6)
        XCTAssertEqual(look.rangeKilometers, pass.culmination.rangeKilometers, accuracy: 1e-6)
        XCTAssertEqual(look.altitude, 74.95, accuracy: 0.01)
        // Refraction raises the apparent altitude by a few arcseconds at this height, and the direction is a unit vector.
        XCTAssertTrue(look.apparentAltitude > look.altitude && look.apparentAltitude - look.altitude < 0.01)
        XCTAssertEqual(look.direction.length, 1.0, accuracy: 1e-12)
        XCTAssertEqual(look.apparentDirection.length, 1.0, accuracy: 1e-12)
        XCTAssertLessThan(look.direction.angle(to: look.apparentDirection), 0.01)
        XCTAssertEqual(look.azimuth, look.horizontal.azimuth, accuracy: 0.0)
        XCTAssertEqual(look.apparentAltitude, look.apparentHorizontal.altitude, accuracy: 0.0)
        // Near the zenith the satellite is closest: range rate about zero, angular speed about 1 degree per second.
        XCTAssertLessThan(abs(look.rangeRateKilometersPerSecond), 0.5)
        XCTAssertTrue((0.8...1.5).contains(look.angularSpeed), "angular speed \(look.angularSpeed)")
        XCTAssertTrue((400.0...460.0).contains(look.rangeKilometers))
        XCTAssertEqual(satellite.catalogNumber, 25544)
        XCTAssertEqual(satellite.name, "ISS (ZARYA)")
        XCTAssertEqual(look.date, pass.culmination.date)
    }

    func testVisibilityFollowsSunlightAndTwilight() throws {
        let satellite = try iss()
        let inShadow = try XCTUnwrap(satellite.look(at: Support.iso("2026-10-18T11:26:30Z"), observer: boulder))
        XCTAssertTrue(!inShadow.isSunlit && inShadow.illuminatedFraction == 0.0)
        XCTAssertTrue(inShadow.observerIsDark())
        XCTAssertFalse(inShadow.isVisible())
        XCTAssertNil(inShadow.magnitude)

        let lit = try XCTUnwrap(satellite.look(at: Support.iso("2026-10-18T11:29:00Z"), observer: boulder))
        XCTAssertTrue(lit.isSunlit && lit.illuminatedFraction == 1.0)
        XCTAssertTrue(lit.observerIsDark() && lit.isAboveHorizon && lit.isVisible())
        XCTAssertLessThan(lit.sunAltitude, -6.0)
        XCTAssertFalse(lit.observerIsDark(darknessSunAltitude: -90.0))
        XCTAssertFalse(lit.isVisible(darknessSunAltitude: -90.0))

        // Daytime: lit, above the horizon, but the observer's sky is bright.
        let day = try XCTUnwrap(satellite.look(at: Support.iso("2026-10-18T17:57:19Z"), observer: boulder))
        XCTAssertTrue(day.isSunlit && day.isAboveHorizon && !day.observerIsDark() && !day.isVisible())
        XCTAssertGreaterThan(day.sunAltitude, 20.0)
        XCTAssertTrue(day.isVisible(darknessSunAltitude: 90.0))

        // Below the horizon.
        let below = try XCTUnwrap(satellite.look(at: Support.iso("2026-10-18T12:30:00Z"), observer: boulder))
        XCTAssertTrue(!below.isAboveHorizon && !below.isVisible(darknessSunAltitude: 90.0))
    }

    func testMagnitudeNeedsAnIntrinsicMagnitudeAndSunlight() throws {
        let satellites = try Support.referenceSatellites()
        let satellite = try XCTUnwrap(satellites["iss"])
        let time = Support.iso("2026-10-18T11:29:00Z")
        let lit = try XCTUnwrap(satellite.look(at: time, observer: boulder))
        let magnitude = try XCTUnwrap(lit.magnitude)
        let expected = try XCTUnwrap(SatelliteBrightness.apparentMagnitude(
            intrinsicMagnitude: -1.8, rangeKilometers: lit.rangeKilometers, phaseAngle: lit.phaseAngle, illuminatedFraction: lit.illuminatedFraction
        ))
        XCTAssertEqual(magnitude, expected, accuracy: 1e-12)
        XCTAssertTrue((-5.5...0.0).contains(magnitude), "magnitude \(magnitude)")
        XCTAssertTrue((0.0...180.0).contains(lit.phaseAngle))

        let starlink = try XCTUnwrap(satellites["starlink"])
        XCTAssertNil(starlink.look(at: time, observer: boulder)?.magnitude)
        let custom = Satellite(elements: starlink.elements, intrinsicMagnitude: 4.0)
        XCTAssertNotNil(custom.look(at: time, observer: boulder)?.magnitude)
        XCTAssertNil(Satellite(elements: satellite.elements, intrinsicMagnitude: nil).look(at: time, observer: boulder)?.magnitude)
        XCTAssertEqual(satellite.intrinsicMagnitude, -1.8)
        XCTAssertEqual(try XCTUnwrap(satellites["css"]).intrinsicMagnitude, 0.0)
        XCTAssertEqual(try XCTUnwrap(satellites["hst"]).intrinsicMagnitude, 2.2)
        XCTAssertNil(try XCTUnwrap(satellites["polar"]).intrinsicMagnitude)
    }

    func testLookIsMissingWhereSgp4Fails() throws {
        let satellite = try iss()
        XCTAssertNil(satellite.look(at: Support.iso("2050-01-01T00:00:00Z"), observer: boulder))
        XCTAssertNotNil(satellite.look(at: Support.iso("2026-10-20T00:00:00Z"), observer: boulder))
    }

    func testASharedSkyGivesTheSameLooks() throws {
        let time = Support.iso("2026-10-18T11:29:00Z")
        let context = SatelliteSkyContext(date: time, observer: boulder)
        for satellite in try Support.referenceSatellites().values {
            XCTAssertEqual(satellite.look(at: time, observer: boulder), satellite.look(in: context))
        }
        XCTAssertEqual(context.date, time)
        XCTAssertTrue(context.sunAltitude < -6.0 && context.isDark())
        XCTAssertFalse(context.isDark(darknessSunAltitude: -30.0))
        XCTAssertEqual(context.sunPosition, SatelliteFrames.sunPosition(at: time))
    }

    func testTrackSamplesTheSkyAtAFixedStep() throws {
        let satellite = try iss()
        let start = Support.iso("2026-10-18T11:24:00Z")
        let end = Support.iso("2026-10-18T11:30:00Z")
        let track = satellite.track(from: start, to: end, step: 30.0, observer: boulder)
        XCTAssertEqual(track.count, 13)
        for (index, look) in track.enumerated() {
            XCTAssertEqual(look.date.timeIntervalSince1970, start.timeIntervalSince1970 + 30.0 * Double(index), accuracy: 1e-6)
            XCTAssertEqual(try XCTUnwrap(satellite.look(at: look.date, observer: boulder)).azimuth, look.azimuth, accuracy: 1e-9)
        }
        XCTAssertTrue(try XCTUnwrap(track.first).altitude > 10.0 && (try XCTUnwrap(track.first).altitude) < 20.0)
        XCTAssertGreaterThan(track.map(\.altitude).max() ?? 0, 70.0)
        // The shadow ends in the middle of the track.
        XCTAssertTrue(try !XCTUnwrap(track.first).isSunlit && (try XCTUnwrap(track.last).isSunlit))
        var changes = 0
        for index in 1..<track.count where track[index - 1].isSunlit != track[index].isSunlit { changes += 1 }
        XCTAssertEqual(changes, 1)

        XCTAssertTrue(satellite.track(from: end, to: start, step: 30.0, observer: boulder).isEmpty)
        XCTAssertEqual(satellite.track(from: start, to: start, step: 30.0, observer: boulder).count, 1)
        // The step is clamped to 0.1 ... 3600 s, the number of points to 20 000, an unusable step becomes 1 s.
        XCTAssertEqual(satellite.track(from: start, to: start.addingTimeInterval(180.0), step: 0.0, observer: boulder).count, 1801)
        XCTAssertEqual(satellite.track(from: start, to: start.addingTimeInterval(86_400.0), step: 0.1, observer: boulder).count, Satellite.maximumTrackPoints)
        XCTAssertEqual(satellite.track(from: start, to: start.addingTimeInterval(180.0), step: .nan, observer: boulder).count, 181)
        XCTAssertEqual(satellite.track(from: start, to: start.addingTimeInterval(4000.0), step: 100_000.0, observer: boulder).count, 2)
    }

    func testTheAimTargetIsAPointOnTheTrack() throws {
        // The Aim screen shows where to wait: the apparent position at some time, and where the pass peaks.
        let satellite = try iss()
        let pass = try culminationPass()
        let wait = pass.culmination.date.addingTimeInterval(-40.0)
        let waiting = try XCTUnwrap(satellite.look(at: wait, observer: boulder))
        let culminating = try XCTUnwrap(satellite.look(at: pass.culmination.date, observer: boulder))
        let separation = waiting.apparentHorizontal.angularSeparation(to: culminating.apparentHorizontal)
        XCTAssertTrue((20.0...60.0).contains(separation), "40 s before the zenith the ISS is \(separation) degrees away")
        XCTAssertEqual(pass.culmination.horizontal.angularSeparation(to: culminating.horizontal), 0.0, accuracy: 1e-6)
        XCTAssertEqual(pass.culmination.direction.length, 1.0, accuracy: 1e-12)
        XCTAssertEqual(pass.culmination.direction.x, culminating.direction.x, accuracy: 1e-9)
    }

    func testNameFallsBackToTheCatalogNumber() throws {
        let unnamed = try OrbitalElements(
            catalogNumber: 12345, epoch: Support.date(1_792_294_095.0), meanMotion: 15.5, eccentricity: 0.001,
            inclination: 51.6, rightAscensionOfAscendingNode: 10.0, argumentOfPericenter: 20.0, meanAnomaly: 30.0
        )
        XCTAssertEqual(Satellite(elements: unnamed).name, "NORAD 12345")
    }
}
