import XCTest
@testable import LodestarKit

/// Camera advice for meteor showers.
///
/// References: the ring geometry is checked against the spherical triangle zenith, radiant, view (law of cosines:
/// `sin alt = sin h · cos R + cos h · sin R · cos θ` for a view at distance R and position angle θ from a radiant at
/// altitude h); the rates against the IMO definition of the zenithal hourly rate, `ZHR = HR · r^(6.5 − lm) / sin h`
/// (Rendtel and Arlt (eds.), *Handbook for Meteor Observers*), and the frame's solid angle against the rectangular
/// pyramid `4 · asin(sin(w/2) · sin(h/2))`, which is 4π/6 sr for a 90° × 90° frame (one face of a cube seen from its
/// centre). Sites and instants come from the 2026 IMO calendar used by `EventsMeteorShowerTests`.
final class EventsMeteorCameraAdviceTests: XCTestCase {
    private typealias Support = EventsTestSupport

    private let boulder = Support.boulder.observer
    private let fullFrame24 = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8)

    private func perseids() throws -> MeteorShower {
        try XCTUnwrap(MeteorShower.withCode("PER"))
    }

    /// The shower with another population index.
    private func shower(_ base: MeteorShower, populationIndex: Double) -> MeteorShower {
        MeteorShower(code: base.code, iauNumber: base.iauNumber, name: base.name,
                     activityStartMonth: base.activityStartMonth, activityStartDay: base.activityStartDay,
                     activityEndMonth: base.activityEndMonth, activityEndDay: base.activityEndDay,
                     peakSolarLongitude: base.peakSolarLongitude, zhr: base.zhr, radiant: base.radiant,
                     radiantDriftRightAscension: base.radiantDriftRightAscension,
                     radiantDriftDeclination: base.radiantDriftDeclination, velocity: base.velocity,
                     populationIndex: populationIndex)
    }

    /// The altitude of the view at position angle `angle` on the ring of `radius` around a radiant `height` up.
    private func ringAltitude(height: Double, radius: Double, angle: Double) -> Double {
        AstroMath.asinDeg(AstroMath.sinDeg(height) * AstroMath.cosDeg(radius)
                          + AstroMath.cosDeg(height) * AstroMath.sinDeg(radius) * AstroMath.cosDeg(angle))
    }

    /// The azimuth distance of that view from the radiant, from the spherical law of cosines for the side R.
    private func ringAzimuthOffset(height: Double, radius: Double, altitude: Double) -> Double {
        AstroMath.acosDeg((AstroMath.cosDeg(radius) - AstroMath.sinDeg(height) * AstroMath.sinDeg(altitude))
                          / (AstroMath.cosDeg(height) * AstroMath.cosDeg(altitude)))
    }

    // MARK: Direction

    func testTheRingPicksTheDirectionNearestTheBestAltitude() throws {
        // A radiant due south, 60° up. The ring at 40° reaches 55.5° at position angles 60° and 300° (the ring is
        // symmetric about the meridian): the equal scores resolve to the smaller angle, to the west of the radiant.
        let radiant = HorizontalCoordinate(azimuth: 180, altitude: 60)
        let choice = try XCTUnwrap(MeteorCameraAdvice.choose(radiant: radiant, moon: nil))
        let altitude = ringAltitude(height: 60, radius: 40, angle: 60)
        Support.assertNear(55.5, altitude, tolerance: 0.05, "reference altitude")
        XCTAssertEqual(choice.positionAngle, 60)
        Support.assertNear(altitude, choice.direction.altitude, tolerance: 1e-9, "altitude")
        Support.assertNear(180 + ringAzimuthOffset(height: 60, radius: 40, altitude: altitude), choice.direction.azimuth,
                           tolerance: 1e-9, "azimuth")
        Support.assertNear(40, choice.separationFromRadiant, tolerance: 1e-9, "separation from the radiant")
        Support.assertNear(40, choice.direction.angularSeparation(to: radiant), tolerance: 1e-9,
                           "separation by the coordinates")
        XCTAssertNil(choice.moonSeparation)
        XCTAssertFalse(choice.isSteeredByMoon)
    }

    func testTheMoonTwentyDegreesAwayMovesTheViewToTheOtherSide() throws {
        let radiant = HorizontalCoordinate(azimuth: 180, altitude: 60)
        let plain = try XCTUnwrap(MeteorCameraAdvice.choose(radiant: radiant, moon: nil))
        // A full Moon 20° from the plain pick, straight above it.
        let moonPlace = HorizontalCoordinate(azimuth: plain.direction.azimuth, altitude: plain.direction.altitude + 20)
        Support.assertNear(20, moonPlace.angularSeparation(to: plain.direction), tolerance: 1e-9, "Moon distance")
        let moon = MeteorCameraMoon(direction: moonPlace, illuminatedFraction: 1)
        let choice = try XCTUnwrap(MeteorCameraAdvice.choose(radiant: radiant, moon: moon))
        // The mirror image on the east side: same height, far from the Moon.
        XCTAssertEqual(choice.positionAngle, 300)
        Support.assertNear(plain.direction.altitude, choice.direction.altitude, tolerance: 1e-9, "same altitude")
        Support.assertNear(360 - plain.direction.azimuth, choice.direction.azimuth, tolerance: 1e-9, "mirrored azimuth")
        XCTAssertTrue(choice.direction.altitude > MeteorCameraAdvice.minimumAltitude)
        let separation = try XCTUnwrap(choice.moonSeparation)
        Support.assertNear(choice.direction.angularSeparation(to: moonPlace), separation, tolerance: 1e-9, "Moon separation")
        XCTAssertTrue(separation > MeteorCameraAdvice.moonInfluenceRadius)
        Support.assertNear(40, choice.separationFromRadiant, tolerance: 1e-9, "separation from the radiant")
        XCTAssertTrue(choice.isSteeredByMoon)
    }

    func testTheMoonOnlyCountsWhenItIsUpAndNear() throws {
        let radiant = HorizontalCoordinate(azimuth: 180, altitude: 60)
        let plain = try XCTUnwrap(MeteorCameraAdvice.choose(radiant: radiant, moon: nil))
        // Below the horizon, however bright and close, it is ignored.
        let setMoon = MeteorCameraMoon(direction: HorizontalCoordinate(azimuth: plain.direction.azimuth, altitude: -5),
                                       illuminatedFraction: 1)
        XCTAssertEqual(plain, try XCTUnwrap(MeteorCameraAdvice.choose(radiant: radiant, moon: setMoon)))
        // A new Moon (nothing lit) costs nothing even when it stands in the view.
        let dark = try XCTUnwrap(MeteorCameraAdvice.choose(
            radiant: radiant, moon: MeteorCameraMoon(direction: plain.direction, illuminatedFraction: 0)))
        XCTAssertEqual(plain.direction, dark.direction)
        XCTAssertFalse(dark.isSteeredByMoon)
        // A bright Moon far from every direction on the ring that can be picked leaves the choice alone.
        let farMoon = MeteorCameraMoon(direction: HorizontalCoordinate(azimuth: plain.direction.azimuth + 180, altitude: 10),
                                       illuminatedFraction: 1)
        let far = try XCTUnwrap(MeteorCameraAdvice.choose(radiant: radiant, moon: farMoon))
        XCTAssertEqual(plain.direction, far.direction)
        XCTAssertFalse(far.isSteeredByMoon)
        XCTAssertTrue(try XCTUnwrap(far.moonSeparation) > MeteorCameraAdvice.moonInfluenceRadius)
        // A Moon that is not a number is ignored like a Moon that is down.
        let notANumber = MeteorCameraMoon(direction: plain.direction, illuminatedFraction: .nan)
        XCTAssertEqual(plain.direction, try XCTUnwrap(MeteorCameraAdvice.choose(radiant: radiant, moon: notANumber)).direction)
    }

    func testTheAltitudePreferencePeaksAt55AndEndsAt25And85() {
        XCTAssertEqual(MeteorCameraAdvice.altitudePreference(55), 1)
        XCTAssertEqual(MeteorCameraAdvice.altitudePreference(25), 0)
        XCTAssertEqual(MeteorCameraAdvice.altitudePreference(85), 0)
        XCTAssertEqual(MeteorCameraAdvice.altitudePreference(40), 0.5, accuracy: 1e-12)
        XCTAssertEqual(MeteorCameraAdvice.altitudePreference(70), 0.5, accuracy: 1e-12)
        XCTAssertEqual(MeteorCameraAdvice.altitudePreference(10), 0)
        XCTAssertEqual(MeteorCameraAdvice.altitudePreference(90), 0)
    }

    func testRadiantAtTheZenithGivesTheNorthSide() throws {
        // Every direction on the ring is 50° up: the first one, north, is taken.
        let choice = try XCTUnwrap(MeteorCameraAdvice.choose(radiant: HorizontalCoordinate(azimuth: 0, altitude: 90), moon: nil))
        XCTAssertEqual(choice.positionAngle, 0)
        Support.assertNear(50, choice.direction.altitude, tolerance: 1e-9, "altitude")
        Support.assertNear(0, choice.direction.azimuth, tolerance: 1e-9, "azimuth")
        Support.assertNear(40, choice.separationFromRadiant, tolerance: 1e-9, "separation")
    }

    func testALowRadiantStillGivesAHighView() throws {
        // At −10° the ring reaches 30°: the one direction above 25° is offered (the vertical circle, towards the zenith).
        let choice = try XCTUnwrap(MeteorCameraAdvice.choose(radiant: HorizontalCoordinate(azimuth: 90, altitude: -10), moon: nil))
        XCTAssertEqual(choice.positionAngle, 0)
        Support.assertNear(30, choice.direction.altitude, tolerance: 1e-9, "altitude")
        Support.assertNear(90, choice.direction.azimuth, tolerance: 1e-9, "azimuth")
        // Lower than −10° the chooser refuses; at −45° the ring does not even reach 25°.
        XCTAssertNil(MeteorCameraAdvice.choose(radiant: HorizontalCoordinate(azimuth: 90, altitude: -10.01), moon: nil))
        XCTAssertNil(MeteorCameraAdvice.choose(radiant: HorizontalCoordinate(azimuth: 90, altitude: -45), moon: nil))
        XCTAssertNil(MeteorCameraAdvice.choose(radiant: HorizontalCoordinate(azimuth: .nan, altitude: .nan), moon: nil))
    }

    func testTheAdviceForThePerseidsAtBoulder() throws {
        // 04:00 MDT on August 13, 2026 (New Moon on August 12): the radiant is 58° up in the north-east.
        let perseids = try perseids()
        let date = Support.utc("2026-08-13T10:00:00Z")
        let advice = try XCTUnwrap(MeteorCameraAdvice.bestAim(shower: perseids, observer: boulder, at: date))
        let frame = SkyFrame(date: date, observer: boulder)
        let radiant = frame.horizontal(j2000: perseids.radiant(at: date), properMotion: nil, refraction: false)
        XCTAssertTrue(radiant.altitude > 55 && radiant.altitude < 60, "\(radiant.altitude)")
        Support.assertNear(40, advice.separationFromRadiant, tolerance: 1e-9, "separation")
        Support.assertNear(40, HorizontalCoordinate(azimuth: advice.azimuth, altitude: advice.altitude).angularSeparation(to: radiant),
                           tolerance: 1e-9, "separation by the coordinates")
        XCTAssertTrue(advice.altitude > 50 && advice.altitude < 60, "\(advice.altitude)")
        XCTAssertTrue(advice.azimuth >= 0 && advice.azimuth < 360)
        // The aim point is a J2000 place: 40° from the J2000 radiant, and back in the sky where the advice says.
        Support.assertNear(40, advice.aimPoint.angularSeparation(to: perseids.radiant(at: date)), tolerance: 0.01, "J2000 separation")
        let back = frame.horizontal(j2000: advice.aimPoint, properMotion: nil, refraction: false)
        Support.assertNear(advice.altitude, back.altitude, tolerance: 0.01, "altitude of the aim point")
        Support.assertNear(advice.azimuth, back.azimuth, tolerance: 0.01, "azimuth of the aim point")
        // The Moon is a 1 % crescent below the horizon.
        XCTAssertEqual(advice.moonNote, "The Moon is below the horizon.")
        XCTAssertEqual(advice.reason,
                       "Meteors trail longest about 40\u{00B0} from the radiant. This view is high enough to clear the horizon haze.")
        // Without the Moon the view is the same and there is no note.
        let without = try XCTUnwrap(MeteorCameraAdvice.bestAim(shower: perseids, observer: boulder, at: date, moonConsidered: false))
        XCTAssertNil(without.moonNote)
        XCTAssertEqual(MeteorAimAdvice(azimuth: advice.azimuth, altitude: advice.altitude,
                                       separationFromRadiant: advice.separationFromRadiant, aimPoint: advice.aimPoint,
                                       moonNote: nil, reason: advice.reason), without)
    }

    func testABrightMoonHighInTheSkyIsNamedInTheNote() throws {
        // The Quadrantids at the Full Moon of January 3, 2026, 03:00 MST: the Moon is 52° up in the west, 71° from the view.
        let quadrantids = try XCTUnwrap(MeteorShower.withCode("QUA"))
        let date = Support.utc("2026-01-03T10:00:00Z")
        let advice = try XCTUnwrap(MeteorCameraAdvice.bestAim(shower: quadrantids, observer: boulder, at: date))
        let moonNote = try XCTUnwrap(advice.moonNote)
        let frame = SkyFrame(date: date, observer: boulder)
        let moon = frame.horizontal(of: .moon, refraction: false)
        let separation = moon.angularSeparation(to: HorizontalCoordinate(azimuth: advice.azimuth, altitude: advice.altitude))
        XCTAssertEqual(moonNote, "The Moon is \(Int(moon.altitude.rounded()))\u{00B0} up, \(Int(separation.rounded()))\u{00B0} from this view, 100% lit.")
        XCTAssertTrue(separation > 60, "\(separation)")
    }

    func testARealMoonSteersTheViewAwayFromIt() throws {
        // The Aurigids, September 1, 2026, 03:30 MDT: the Moon is 81 % lit and 64° up in the south; the plain pick,
        // east-south-east of the radiant, is 22° from it, so the view goes to the north side instead.
        let aurigids = try XCTUnwrap(MeteorShower.withCode("AUR"))
        let date = Support.utc("2026-09-01T09:30:00Z")
        let with = try XCTUnwrap(MeteorCameraAdvice.bestAim(shower: aurigids, observer: boulder, at: date))
        let without = try XCTUnwrap(MeteorCameraAdvice.bestAim(shower: aurigids, observer: boulder, at: date, moonConsidered: false))
        let moon = SkyFrame(date: date, observer: boulder).horizontal(of: .moon, refraction: false)
        XCTAssertTrue(moon.altitude > 60)
        let withSeparation = moon.angularSeparation(to: HorizontalCoordinate(azimuth: with.azimuth, altitude: with.altitude))
        let withoutSeparation = moon.angularSeparation(to: HorizontalCoordinate(azimuth: without.azimuth, altitude: without.altitude))
        XCTAssertTrue(withoutSeparation < 40, "\(withoutSeparation)")
        XCTAssertTrue(withSeparation > 50, "\(withSeparation)")
        Support.assertNear(40, with.separationFromRadiant, tolerance: 1e-9, "separation from the radiant")
        XCTAssertTrue(with.reason.hasSuffix("This view is high in the sky and turned away from the Moon."), with.reason)
        XCTAssertTrue(try XCTUnwrap(with.moonNote).contains("% lit."))
        XCTAssertFalse((with.moonNote ?? "").contains("close enough"))
    }

    func testTheMoonNote() {
        let choiceAway = MeteorCameraChoice(direction: HorizontalCoordinate(azimuth: 100, altitude: 55), positionAngle: 60,
                                            separationFromRadiant: 40, moonSeparation: 72.4, isSteeredByMoon: false)
        let choiceNear = MeteorCameraChoice(direction: HorizontalCoordinate(azimuth: 100, altitude: 55), positionAngle: 60,
                                            separationFromRadiant: 40, moonSeparation: 19.5, isSteeredByMoon: false)
        let up = MeteorCameraMoon(direction: HorizontalCoordinate(azimuth: 250, altitude: 40.4), illuminatedFraction: 0.8)
        XCTAssertEqual(MeteorCameraAdvice.moonNote(up, choice: choiceAway),
                       "The Moon is 40\u{00B0} up, 72\u{00B0} from this view, 80% lit.")
        XCTAssertEqual(MeteorCameraAdvice.moonNote(up, choice: choiceNear),
                       "The Moon is 40\u{00B0} up, 20\u{00B0} from this view, 80% lit. It is close enough to wash out the fainter meteors.")
        // A thin Moon close to the view is not worth a warning.
        XCTAssertEqual(
            MeteorCameraAdvice.moonNote(MeteorCameraMoon(direction: HorizontalCoordinate(azimuth: 250, altitude: 40.4),
                                                         illuminatedFraction: 0.1), choice: choiceNear),
            "The Moon is 40\u{00B0} up, 20\u{00B0} from this view, 10% lit.")
        XCTAssertEqual(
            MeteorCameraAdvice.moonNote(MeteorCameraMoon(direction: HorizontalCoordinate(azimuth: 250, altitude: -3),
                                                         illuminatedFraction: 1), choice: choiceAway),
            "The Moon is below the horizon.")
    }

    func testNothingToAdviseWhenTheRadiantStaysFarBelowTheHorizon() throws {
        // At 66.5°S the Perseid radiant (+58°) never gets above −34°.
        let perseids = try perseids()
        let antarctica = Support.antarctica.observer
        for hour in stride(from: 0, to: 24, by: 3) {
            let date = Support.utc("2026-08-13T00:00:00Z").addingTimeInterval(Double(hour) * 3600)
            XCTAssertNil(MeteorCameraAdvice.bestAim(shower: perseids, observer: antarctica, at: date))
        }
    }

    func testAShowerWithBadValuesGivesNoAdviceInsteadOfTrapping() {
        let broken = MeteorShower(code: "BAD", iauNumber: 0, name: "Broken", activityStartMonth: 13, activityStartDay: 40,
                                  activityEndMonth: 0, activityEndDay: 0, peakSolarLongitude: .nan, zhr: 0,
                                  radiant: EquatorialCoordinate(rightAscension: 400, declination: 120),
                                  radiantDriftRightAscension: .nan, radiantDriftDeclination: .infinity, velocity: .nan,
                                  populationIndex: .nan)
        let date = Support.utc("2026-08-13T10:00:00Z")
        _ = broken.radiant(at: date)
        _ = MeteorCameraAdvice.bestAim(shower: broken, observer: boulder, at: date)
        _ = MeteorCameraAdvice.bestAim(shower: broken, observer: boulder, at: date, moonConsidered: false)
        XCTAssertEqual(MeteorCameraAdvice.observedHourlyRate(shower: broken, radiantAltitude: 60), 0)
        XCTAssertEqual(MeteorCameraAdvice.expectedInFrame(observedHourlyRate: 50, shower: broken, setup: fullFrame24), 0)
        XCTAssertNil(MeteorCameraAdvice.meanMinutesPerMeteor(observedHourlyRate: 50, shower: broken, setup: fullFrame24))
    }

    // MARK: Count

    func testObservedRateIsTheZenithalRateTimesSineOfTheAltitude() throws {
        let perseids = try perseids()
        Support.assertNear(100, MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 90),
                           tolerance: 1e-9, "radiant at the zenith")
        Support.assertNear(50, MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 30),
                           tolerance: 1e-9, "radiant at 30°")
        Support.assertNear(100 * sin(60 * Double.pi / 180), MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 60),
                           tolerance: 1e-9, "radiant at 60°")
        XCTAssertEqual(MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 120), 100, accuracy: 1e-9)
        // The IMO definition read backwards: a sky with a limiting magnitude one worse than perfect shows 1/r of the meteors.
        Support.assertNear(86.60254037844386 / 2.2,
                           MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 60, limitingMagnitude: 5.5),
                           tolerance: 1e-9, "lm 5.5")
        Support.assertNear(86.60254037844386 * 2.2,
                           MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 60, limitingMagnitude: 7.5),
                           tolerance: 1e-9, "lm 7.5")
    }

    func testObservedRateIsZeroWithTheRadiantBelowTheHorizon() throws {
        let perseids = try perseids()
        XCTAssertEqual(MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 0), 0)
        XCTAssertEqual(MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: -0.001), 0)
        XCTAssertEqual(MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: -45), 0)
        XCTAssertEqual(MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: .nan), 0)
        XCTAssertEqual(MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: .infinity), 0)
        XCTAssertEqual(MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 60, limitingMagnitude: .nan), 0)
    }

    func testTheFrameSolidAngle() {
        // 24 mm on full frame: 73.74° × 53.13° (tan(w/2) = 18/24, tan(h/2) = 12/24), a pyramid of 1.0866 sr, 17.3 % of the sky above.
        Support.assertNear(1.086628494710296, MeteorCameraAdvice.frameSolidAngle(of: fullFrame24), tolerance: 1e-9, "24 mm full frame")
        // One face of a cube seen from its centre.
        Support.assertNear(4 * Double.pi / 6, MeteorCameraAdvice.frameSolidAngle(frame: FrameSize(horizontal: 90, vertical: 90, diagonal: 120)),
                           tolerance: 1e-12, "90° × 90°")
        // A frame almost 180° wide each way is nearly the whole half sky.
        Support.assertNear(2 * Double.pi, MeteorCameraAdvice.frameSolidAngle(frame: FrameSize(horizontal: 179.999, vertical: 179.999, diagonal: 180)),
                           tolerance: 1e-3, "nearly the half sky")
        // Not a frame: nothing.
        XCTAssertEqual(MeteorCameraAdvice.frameSolidAngle(frame: FrameSize(horizontal: 180, vertical: 90, diagonal: 180)), 0)
        XCTAssertEqual(MeteorCameraAdvice.frameSolidAngle(frame: FrameSize(horizontal: 0, vertical: 90, diagonal: 90)), 0)
        XCTAssertEqual(MeteorCameraAdvice.frameSolidAngle(frame: FrameSize(horizontal: .nan, vertical: 90, diagonal: 90)), 0)
        // Wider lenses cover more, a smaller sensor less.
        let wide = MeteorCameraAdvice.frameSolidAngle(of: LensSetup(sensor: .fullFrame, focalLengthMillimeters: 14, aperture: 2.8))
        let narrow = MeteorCameraAdvice.frameSolidAngle(of: LensSetup(sensor: .fullFrame, focalLengthMillimeters: 50, aperture: 1.8))
        let crop = MeteorCameraAdvice.frameSolidAngle(of: LensSetup(sensor: .apsC, focalLengthMillimeters: 24, aperture: 2.8))
        XCTAssertTrue(wide > MeteorCameraAdvice.frameSolidAngle(of: fullFrame24) && MeteorCameraAdvice.frameSolidAngle(of: fullFrame24) > narrow)
        XCTAssertTrue(crop < MeteorCameraAdvice.frameSolidAngle(of: fullFrame24))
    }

    func testExpectedPerseidsInAFullFrame24mmFrame() throws {
        // ZHR 100, radiant 60° up, r = 2.2, 24 mm full frame. The eye sees 100 · sin 60° = 86.60 an hour; the frame is
        // 1.0866 / 2π = 17.29 % of the sky; a camera that reaches magnitude 2 loses r^4.5 = 34.7 of every 34.7
        // + 1 meteors: 86.60 · 0.17294 · 2.2^−4.5 = 0.4311 an hour, one meteor every 2.3 hours (139.2 minutes).
        let perseids = try perseids()
        let observed = MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: 60)
        let expected = MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: perseids, setup: fullFrame24)
        let byHand = 100 * sin(60 * Double.pi / 180) * (4 * asin(0.6 * (12 / (720.0).squareRoot()))) / (2 * Double.pi) * pow(2.2, -4.5)
        Support.assertNear(byHand, expected, tolerance: 1e-12, "closed form")
        Support.assertNear(0.43105212360156964, expected, tolerance: 1e-9, "Perseids, 24 mm full frame")
        let minutes = try XCTUnwrap(MeteorCameraAdvice.meanMinutesPerMeteor(observedHourlyRate: observed, shower: perseids, setup: fullFrame24))
        Support.assertNear(139.19430322876505, minutes, tolerance: 1e-6, "minutes per meteor")
        // The camera limit and the eye limit are the documented ones.
        XCTAssertEqual(MeteorCameraAdvice.cameraLimitingMagnitude, 2.0)
        XCTAssertEqual(MeteorCameraAdvice.eyeLimitingMagnitude, 6.5)
    }

    func testNoMeteorsExpectedWithTheRadiantBelowTheHorizon() throws {
        let perseids = try perseids()
        let observed = MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: -5)
        XCTAssertEqual(MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: perseids, setup: fullFrame24), 0)
        XCTAssertNil(MeteorCameraAdvice.meanMinutesPerMeteor(observedHourlyRate: observed, shower: perseids, setup: fullFrame24))
    }

    func testTheExpectedCountScalesWithTheFrameAndTheShower() throws {
        let perseids = try perseids()
        let observed = 80.0
        let wide = MeteorCameraAdvice.expectedInFrame(
            observedHourlyRate: observed, shower: perseids,
            setup: LensSetup(sensor: .fullFrame, focalLengthMillimeters: 14, aperture: 2.8))
        let normal = MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: perseids, setup: fullFrame24)
        let tele = MeteorCameraAdvice.expectedInFrame(
            observedHourlyRate: observed, shower: perseids,
            setup: LensSetup(sensor: .fullFrame, focalLengthMillimeters: 85, aperture: 1.8))
        XCTAssertTrue(wide > normal && normal > tele && tele > 0)
        // Twice the observed rate, twice the count.
        Support.assertNear(2 * normal, MeteorCameraAdvice.expectedInFrame(observedHourlyRate: 2 * observed, shower: perseids, setup: fullFrame24),
                           tolerance: 1e-12, "linear in the rate")
        // A shower with a steeper mass distribution (higher r) loses more to the camera's limit.
        let steep = shower(perseids, populationIndex: 3.0)
        XCTAssertTrue(MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: steep, setup: fullFrame24) < normal)
        Support.assertNear(normal * pow(3.0 / 2.2, -4.5),
                           MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: steep, setup: fullFrame24),
                           tolerance: 1e-12, "population index")
        // Rates that are not usable count nothing.
        for bad in [-1.0, 0.0, Double.nan, Double.infinity] {
            XCTAssertEqual(MeteorCameraAdvice.expectedInFrame(observedHourlyRate: bad, shower: perseids, setup: fullFrame24), 0, "\(bad)")
        }
        XCTAssertEqual(MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: shower(perseids, populationIndex: 0), setup: fullFrame24), 0)
        XCTAssertEqual(MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: shower(perseids, populationIndex: .nan), setup: fullFrame24), 0)
    }

    // MARK: Best time

    /// The altitude of the radiant at `time` at `observer`.
    private func radiantAltitude(_ shower: MeteorShower, _ observer: Observer, _ time: Date) -> Double {
        SkyFrame(date: time, observer: observer).horizontal(j2000: shower.radiant(at: time), properMotion: nil, refraction: false).altitude
    }

    func testBestTimeIsTheEndOfDarknessWhenTheRadiantKeepsRising() throws {
        // Perseids, Boulder, night of August 12 to 13, 2026: the radiant culminates at about 05:00 MDT, after astronomical
        // dawn, so it is still climbing when the dark ends and the end of the dark interval is the best time.
        let perseids = try perseids()
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let summary = NightPlanner.summary(nightStartingOn: Support.utc("2026-08-12T18:00:00Z"), observer: boulder, timeZone: zone)
        XCTAssertEqual(summary.astronomicalDarknessIntervals.count, 1)
        let dark = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        let best = try XCTUnwrap(MeteorCameraAdvice.bestTimeTonight(shower: perseids, summary: summary))
        XCTAssertEqual(best, dark.end)
        let altitude = radiantAltitude(perseids, boulder, best)
        XCTAssertTrue(altitude > 60, "\(altitude)")
        // The radiant is still climbing, so no minute of the dark is higher, and the last minute is within a minute's climb.
        var highest = -90.0
        var minute = dark.start
        while minute <= dark.end {
            highest = max(highest, radiantAltitude(perseids, boulder, minute))
            minute = minute.addingTimeInterval(60)
        }
        XCTAssertTrue(altitude >= highest && altitude - highest < 0.2, "\(altitude) against \(highest)")
    }

    func testBestTimeIsTheCulminationWhenItFallsInTheDark() throws {
        // Geminids, Boulder, night of December 13 to 14, 2026: the radiant is highest at about 02:00 MST, mid-night.
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let summary = NightPlanner.summary(nightStartingOn: Support.utc("2026-12-13T19:00:00Z"), observer: boulder, timeZone: zone)
        XCTAssertEqual(summary.astronomicalDarknessIntervals.count, 1)
        let dark = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        let geminids = try XCTUnwrap(MeteorShower.withCode("GEM"))
        let best = try XCTUnwrap(MeteorCameraAdvice.bestTimeTonight(shower: geminids, summary: summary))
        XCTAssertTrue(best > dark.start && best < dark.end)
        // On the grid of ten minutes from the start of the dark.
        XCTAssertEqual(best.timeIntervalSince(dark.start).truncatingRemainder(dividingBy: 600), 0, accuracy: 1e-6)
        let altitude = radiantAltitude(geminids, boulder, best)
        var highest = -90.0
        var highestTime = dark.start
        var minute = dark.start
        while minute <= dark.end {
            let value = radiantAltitude(geminids, boulder, minute)
            if value > highest {
                highest = value
                highestTime = minute
            }
            minute = minute.addingTimeInterval(60)
        }
        XCTAssertTrue(abs(best.timeIntervalSince(highestTime)) <= 300 + 1e-6,
                      "\(best.timeIntervalSince(highestTime)) s from the true culmination")
        XCTAssertTrue(highest - altitude < 0.05, "\(highest - altitude)")
        XCTAssertTrue(altitude > 80, "\(altitude)")
    }

    func testNoBestTimeWithoutDarkness() throws {
        // 65°N in mid-August: the Sun stays above −18° all night.
        let perseids = try perseids()
        let north = Observer(location: GeographicLocation(latitude: 65, longitude: 25, elevation: 0))
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Helsinki"))
        let summary = NightPlanner.summary(nightStartingOn: Support.utc("2026-08-12T09:00:00Z"), observer: north, timeZone: zone)
        XCTAssertTrue(summary.astronomicalDarknessIntervals.isEmpty)
        XCTAssertNil(MeteorCameraAdvice.bestTimeTonight(shower: perseids, summary: summary))
    }

    func testTheBestTimeFeedsTheAdvice() throws {
        // The brief's chain: the best time of the night, then the advice for it, then the expected count at that time.
        let perseids = try perseids()
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let summary = NightPlanner.summary(nightStartingOn: Support.utc("2026-08-12T18:00:00Z"), observer: boulder, timeZone: zone)
        let best = try XCTUnwrap(MeteorCameraAdvice.bestTimeTonight(shower: perseids, summary: summary))
        let advice = try XCTUnwrap(MeteorCameraAdvice.bestAim(shower: perseids, observer: boulder, at: best))
        XCTAssertTrue(advice.altitude > MeteorCameraAdvice.minimumAltitude)
        Support.assertNear(40, advice.separationFromRadiant, tolerance: 1e-9, "separation")
        let observed = MeteorCameraAdvice.observedHourlyRate(shower: perseids, radiantAltitude: radiantAltitude(perseids, boulder, best))
        let perHour = MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: perseids, setup: fullFrame24)
        XCTAssertTrue(perHour > 0.4 && perHour < 0.5, "\(perHour)")
    }
}
