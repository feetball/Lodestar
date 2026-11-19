import Foundation
import XCTest
@testable import LodestarKit

// MARK: - Alt-azimuth field rotation, polar-alignment drift and apparent size

final class TrackedExposureTests: XCTestCase {

    private func lens(
        sensor: SensorFormat = .fullFrame,
        focalLength: Double = 200,
        aperture: Double = 2.8,
        pitch: Double? = 4.0
    ) -> LensSetup {
        LensSetup(sensor: sensor, focalLengthMillimeters: focalLength, aperture: aperture, pixelPitchMicrometers: pitch)
    }

    // MARK: Field rotation rate

    func testFieldRotationRateOnTheMeridian() {
        // 15.041 * cos(45) * cos(0) / cos(45) = 15.041, due north and due south alike.
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 0, altitude: 45), 15.041, accuracy: 1e-9)
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 180, altitude: 45), 15.041, accuracy: 1e-9)
    }

    func testFieldRotationRateIsZeroDueEastAndWest() {
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 90, altitude: 45), 0, accuracy: 1e-9)
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 270, altitude: 20), 0, accuracy: 1e-9)
    }

    func testFieldRotationRateIsAMagnitudeSoTheAzimuthConventionDoesNotMatter() {
        let rate = TrackedExposure.fieldRotationRate(latitude: 40, azimuth: 30, altitude: 25)
        let degrees = AstroMath.radiansPerDegree
        XCTAssertEqual(rate, 15.041 * cos(40 * degrees) * cos(30 * degrees) / cos(25 * degrees), accuracy: 1e-9)
        for azimuth in [150.0, 210.0, 330.0, -30.0, 390.0] {
            XCTAssertEqual(
                TrackedExposure.fieldRotationRate(latitude: 40, azimuth: azimuth, altitude: 25), rate, accuracy: 1e-9
            )
        }
        // The southern hemisphere rotates at the same rate as its mirror image in the north.
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: -40, azimuth: 30, altitude: 25), rate, accuracy: 1e-9)
    }

    func testFieldRotationRateIsTheRateOfChangeOfTheParallacticAngle() {
        // Independent check of the formula: the field of an alt-azimuth mount turns as the parallactic angle q,
        // tan q = sin H / (tan phi cos delta - sin delta cos H) (Meeus, Astronomical Algorithms, chapter 14), and the
        // hour angle H grows by 15.041 arcseconds per second. Differentiate q numerically and compare.
        let cases: [(Double, Double, Double)] = [
            (45, 20, 30),
            (52, -10, -60),
            (-33.9, -45, 10),
            (10, 70, 100),
            (60, 5, -20),
        ]
        let step = 1e-5
        for (latitude, declination, hourAngle) in cases {
            let before = parallacticAngle(latitude: latitude, declination: declination,
                                          hourAngle: hourAngle - step * 180 / Double.pi)
            let after = parallacticAngle(latitude: latitude, declination: declination,
                                         hourAngle: hourAngle + step * 180 / Double.pi)
            let difference = atan2(sin(after - before), cos(after - before))
            let expected = 15.041 * abs(difference / (2 * step))
            let (azimuth, altitude) = horizontal(latitude: latitude, declination: declination, hourAngle: hourAngle)
            let rate = TrackedExposure.fieldRotationRate(latitude: latitude, azimuth: azimuth, altitude: altitude)
            XCTAssertEqual(rate, expected, accuracy: expected * 1e-6, "lat \(latitude) dec \(declination) H \(hourAngle)")
        }
    }

    func testFieldRotationRateGrowsTowardsTheZenithAndIsGuarded() {
        let degrees = AstroMath.radiansPerDegree
        let at45 = TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 0, altitude: 45)
        let at80 = TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 0, altitude: 80)
        XCTAssertEqual(at80, at45 * cos(45 * degrees) / cos(80 * degrees), accuracy: 1e-9)
        let guarded = TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 0, altitude: 89.9)
        XCTAssertEqual(guarded, 15.041 * cos(45 * degrees) / cos(89.9 * degrees), accuracy: 1e-6)
        for altitude in [89.95, 90.0, 100.0, 1e9] {
            XCTAssertEqual(
                TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 0, altitude: altitude), guarded, accuracy: 1e-6
            )
        }
        XCTAssertTrue(guarded.isFinite && guarded < 10_000)
        // Below the horizon the formula is the mirror image.
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 0, altitude: -80), at80, accuracy: 1e-9)
    }

    func testFieldRotationVanishesAtThePoles() {
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 90, azimuth: 0, altitude: 45), 0, accuracy: 1e-9)
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: -90, azimuth: 0, altitude: 45), 0, accuracy: 1e-9)
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 120, azimuth: 0, altitude: 45), 0, accuracy: 1e-9)
    }

    func testFieldRotationRateOfValuesThatAreNotNumbersIsZero() {
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: .nan, azimuth: 0, altitude: 45), 0)
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 45, azimuth: .infinity, altitude: 45), 0)
        XCTAssertEqual(TrackedExposure.fieldRotationRate(latitude: 45, azimuth: 0, altitude: .nan), 0)
    }

    // MARK: Field rotation limit

    func testFieldRotationLimitOnAFullFrameCamera() throws {
        // The corner of a 36 x 24 mm frame is 21.633 mm from the centre: 5408.3 pixels of 4 micrometres.
        // 1.5 px * 206264.806 / (5408.3 px * 15.041 arcsec/s) = 3.803 s.
        let seconds = try XCTUnwrap(
            TrackedExposure.maxExposureForFieldRotation(setup: lens(), latitude: 45, azimuth: 0, altitude: 45)
        )
        XCTAssertEqual(seconds, 3.8029, accuracy: 1e-3)
        let halfDiagonalPixels = SensorFormat.fullFrame.diagonalMillimeters * 1000 / 2 / 4.0
        XCTAssertEqual(seconds, 1.5 * AstroMath.arcsecondsPerRadian / (halfDiagonalPixels * 15.041), accuracy: 1e-9)
    }

    func testFieldRotationLimitScalesWithToleranceSensorAndPitchButNotFocalLength() throws {
        let base = try XCTUnwrap(
            TrackedExposure.maxExposureForFieldRotation(setup: lens(), latitude: 45, azimuth: 0, altitude: 45)
        )
        let tolerant = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(), tolerancePixels: 3, latitude: 45, azimuth: 0, altitude: 45))
        XCTAssertEqual(tolerant, 2 * base, accuracy: 1e-9)
        let coarsePixels = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(pitch: 8), latitude: 45, azimuth: 0, altitude: 45))
        XCTAssertEqual(coarsePixels, 2 * base, accuracy: 1e-9)
        let wideLens = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(focalLength: 24), latitude: 45, azimuth: 0, altitude: 45))
        XCTAssertEqual(wideLens, base, accuracy: 1e-9)
        let smallSensor = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(sensor: .microFourThirds), latitude: 45, azimuth: 0, altitude: 45))
        XCTAssertEqual(
            smallSensor,
            base * SensorFormat.fullFrame.diagonalMillimeters / SensorFormat.microFourThirds.diagonalMillimeters,
            accuracy: 1e-9
        )
    }

    func testFieldRotationLimitShrinksTowardsTheZenith() throws {
        let low = try XCTUnwrap(
            TrackedExposure.maxExposureForFieldRotation(setup: lens(), latitude: 45, azimuth: 0, altitude: 30)
        )
        let high = try XCTUnwrap(
            TrackedExposure.maxExposureForFieldRotation(setup: lens(), latitude: 45, azimuth: 0, altitude: 75)
        )
        XCTAssertTrue(high < low / 2)
    }

    func testFieldRotationLimitAssumesTheDefaultPixelPitchWhenThereIsNone() throws {
        let unknown = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(pitch: nil), latitude: 45, azimuth: 0, altitude: 45))
        let known = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(pitch: ExposureCalculator.defaultPixelPitchMicrometers), latitude: 45, azimuth: 0, altitude: 45))
        XCTAssertEqual(unknown, known, accuracy: 1e-12)
    }

    func testFieldRotationLimitIsNilWithoutRotation() {
        XCTAssertNil(TrackedExposure.maxExposureForFieldRotation(setup: lens(), latitude: 45, azimuth: 90, altitude: 45))
        XCTAssertNil(TrackedExposure.maxExposureForFieldRotation(setup: lens(), latitude: 90, azimuth: 0, altitude: 45))
        XCTAssertNil(TrackedExposure.maxExposureForFieldRotation(setup: lens(), latitude: .nan, azimuth: 0, altitude: 45))
    }

    func testToleranceIsLimitedToItsRange() throws {
        let base = try XCTUnwrap(
            TrackedExposure.maxExposureForFieldRotation(setup: lens(), latitude: 45, azimuth: 0, altitude: 45)
        )
        let notANumber = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(), tolerancePixels: .nan, latitude: 45, azimuth: 0, altitude: 45))
        XCTAssertEqual(notANumber, base, accuracy: 1e-12)
        let huge = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(), tolerancePixels: 1000, latitude: 45, azimuth: 0, altitude: 45))
        XCTAssertEqual(huge, base * 20.0 / 1.5, accuracy: 1e-9)
        let negative = try XCTUnwrap(TrackedExposure.maxExposureForFieldRotation(
            setup: lens(), tolerancePixels: -2, latitude: 45, azimuth: 0, altitude: 45))
        XCTAssertEqual(negative, base * 0.1 / 1.5, accuracy: 1e-9)
    }

    // MARK: Polar-alignment drift

    func testDriftRateOfOneDegreeOfPolarError() {
        XCTAssertEqual(TrackedExposure.driftRate(polarErrorDegrees: 1), 0.2625, accuracy: 1e-4)
        XCTAssertEqual(
            TrackedExposure.driftRate(polarErrorDegrees: 1), 15.041 * sin(1.0 * AstroMath.radiansPerDegree), accuracy: 1e-12
        )
    }

    func testDriftRateIsTheLargestDisplacementOfTwoRotationsAboutAxesApart() {
        // Independent check of the derivation: rotate the sky about the true pole by the sidereal angle of one second
        // and take it back about an axis one degree away; the largest displacement of any star is the drift rate.
        let degrees = AstroMath.radiansPerDegree
        let error = 1.0 * degrees
        let angle = 15.041 / AstroMath.arcsecondsPerRadian
        let pole = Vector3(0, 0, 1)
        let axis = Vector3(sin(error), 0, cos(error))
        let net = Matrix3.rotation(axis: axis, angleRadians: -angle) * Matrix3.rotation(axis: pole, angleRadians: angle)
        var largest = 0.0
        for latitude in stride(from: -88, through: 90, by: 2) {
            for longitude in stride(from: 0, to: 360, by: 2) {
                let star = Vector3(
                    cos(Double(latitude) * degrees) * cos(Double(longitude) * degrees),
                    cos(Double(latitude) * degrees) * sin(Double(longitude) * degrees),
                    sin(Double(latitude) * degrees)
                )
                largest = max(largest, (net * star - star).length)
            }
        }
        let drift = TrackedExposure.driftRate(polarErrorDegrees: 1)
        XCTAssertTrue(largest * AstroMath.arcsecondsPerRadian <= drift * 1.0001)
        XCTAssertEqual(largest * AstroMath.arcsecondsPerRadian, drift, accuracy: drift * 1e-3)
    }

    func testDriftRateLimitsItsInput() {
        XCTAssertEqual(
            TrackedExposure.driftRate(polarErrorDegrees: .nan), TrackedExposure.driftRate(polarErrorDegrees: 1), accuracy: 1e-12
        )
        XCTAssertEqual(
            TrackedExposure.driftRate(polarErrorDegrees: 0), TrackedExposure.driftRate(polarErrorDegrees: 0.01), accuracy: 1e-12
        )
        XCTAssertEqual(
            TrackedExposure.driftRate(polarErrorDegrees: -2), TrackedExposure.driftRate(polarErrorDegrees: 2), accuracy: 1e-12
        )
        XCTAssertEqual(TrackedExposure.driftRate(polarErrorDegrees: 1000), 15.041, accuracy: 1e-9)
    }

    func testPolarErrorLimitForTwoHundredMillimetres() throws {
        // Image scale 206.265 * 4 / 200 = 4.1253 arcsec/px; 1.5 px = 6.188 arcsec; at 0.2625 arcsec/s that is 23.57 s.
        let seconds = TrackedExposure.maxExposureForPolarError(setup: lens(), polarErrorDegrees: 1)
        XCTAssertEqual(seconds, 23.57, accuracy: 0.01)
        let scale = try XCTUnwrap(lens().imageScaleArcsecondsPerPixel)
        XCTAssertEqual(seconds, 1.5 * scale / (15.041 * sin(1.0 * AstroMath.radiansPerDegree)), accuracy: 1e-9)
    }

    func testPolarErrorLimitScalesWithTheLensTheToleranceAndTheError() {
        let degrees = AstroMath.radiansPerDegree
        let base = TrackedExposure.maxExposureForPolarError(setup: lens(), polarErrorDegrees: 1)
        XCTAssertEqual(
            TrackedExposure.maxExposureForPolarError(setup: lens(focalLength: 400), polarErrorDegrees: 1),
            base / 2, accuracy: 1e-9
        )
        XCTAssertEqual(
            TrackedExposure.maxExposureForPolarError(setup: lens(), tolerancePixels: 3, polarErrorDegrees: 1),
            2 * base, accuracy: 1e-9
        )
        XCTAssertEqual(
            TrackedExposure.maxExposureForPolarError(setup: lens(), polarErrorDegrees: 0.25),
            base * sin(1.0 * degrees) / sin(0.25 * degrees), accuracy: 1e-9
        )
        let unknownPitch = TrackedExposure.maxExposureForPolarError(setup: lens(pitch: nil), polarErrorDegrees: 1)
        XCTAssertEqual(unknownPitch, base, accuracy: 1e-9)
    }

    // MARK: Apparent size in pixels

    func testPixelSizeOfTheMoonAt200Millimetres() throws {
        // 0.52 degrees = 1872 arcsec; the image scale is 4.1253 arcsec/px: the Moon spans 453.8 px.
        let pixels = try XCTUnwrap(TrackedExposure.pixelSize(angularDiameterDegrees: 0.52, setup: lens()))
        XCTAssertEqual(pixels, 453.8, accuracy: 0.05)
        let scale = try XCTUnwrap(lens().imageScaleArcsecondsPerPixel)
        XCTAssertEqual(pixels, 0.52 * 3600 / scale, accuracy: 1e-9)
    }

    func testPixelSizeOfAPlanet() throws {
        // Jupiter near opposition, 46 arcsec across, about 11 px at 200 mm on 4 micrometre pixels.
        let pixels = try XCTUnwrap(TrackedExposure.pixelSize(angularDiameterDegrees: 46.0 / 3600, setup: lens()))
        XCTAssertEqual(pixels, 11.15, accuracy: 0.01)
        let longer = try XCTUnwrap(
            TrackedExposure.pixelSize(angularDiameterDegrees: 46.0 / 3600, setup: lens(focalLength: 400))
        )
        XCTAssertEqual(longer, 2 * pixels, accuracy: 1e-9)
    }

    func testPixelSizeWithoutAPixelPitch() throws {
        let withDefault = try XCTUnwrap(TrackedExposure.pixelSize(angularDiameterDegrees: 0.52, setup: lens(pitch: nil)))
        let known = try XCTUnwrap(TrackedExposure.pixelSize(angularDiameterDegrees: 0.52, setup: lens()))
        XCTAssertEqual(withDefault, known, accuracy: 1e-9)
        XCTAssertNil(TrackedExposure.pixelSize(
            angularDiameterDegrees: 0.52, setup: lens(pitch: nil), assumingDefaultPixelPitch: false))
        XCTAssertNotNil(TrackedExposure.pixelSize(
            angularDiameterDegrees: 0.52, setup: lens(), assumingDefaultPixelPitch: false))
    }

    func testPixelSizeOfAnInvalidDiameterIsNil() {
        for diameter in [0.0, -0.5, Double.nan, Double.infinity] {
            XCTAssertNil(TrackedExposure.pixelSize(angularDiameterDegrees: diameter, setup: lens()), "\(diameter)")
        }
    }

    // MARK: Helpers

    /// The parallactic angle in radians (Meeus, Astronomical Algorithms, equation 14.1); angles in degrees.
    private func parallacticAngle(latitude: Double, declination: Double, hourAngle: Double) -> Double {
        let phi = latitude * AstroMath.radiansPerDegree
        let delta = declination * AstroMath.radiansPerDegree
        let hour = hourAngle * AstroMath.radiansPerDegree
        return atan2(sin(hour) * cos(phi), sin(phi) * cos(delta) - cos(phi) * sin(delta) * cos(hour))
    }

    /// The azimuth from north through east and the altitude, in degrees, of a star at the hour angle (west positive).
    private func horizontal(latitude: Double, declination: Double, hourAngle: Double) -> (Double, Double) {
        let phi = latitude * AstroMath.radiansPerDegree
        let delta = declination * AstroMath.radiansPerDegree
        let hour = hourAngle * AstroMath.radiansPerDegree
        let east = -cos(delta) * sin(hour)
        let north = sin(delta) * cos(phi) - cos(delta) * cos(hour) * sin(phi)
        let up = sin(delta) * sin(phi) + cos(delta) * cos(hour) * cos(phi)
        return (atan2(east, north) / AstroMath.radiansPerDegree, asin(up) / AstroMath.radiansPerDegree)
    }
}

// MARK: - Moon exposure

final class MoonExposureTests: XCTestCase {

    private func suggestion(
        fraction: Double = 1.0,
        altitude: Double = 90.0,
        aperture: Double = 11.0,
        iso: Double = 100.0
    ) -> MoonExposureSuggestion {
        MoonExposure.suggest(illuminatedFraction: fraction, altitude: altitude, aperture: aperture, iso: iso)
    }

    func testLooney11FullMoon() {
        // f/11 at 1/ISO: 1/100 s at ISO 100.
        let full = suggestion()
        XCTAssertEqual(full.seconds, 0.01, accuracy: 1e-9)
        XCTAssertEqual(full.airmass, 1, accuracy: 1e-12)
        XCTAssertEqual(full.note, "Full Moon high in the sky: the Looney 11 rule as it stands, f/11 at 1/ISO.")
        XCTAssertEqual(suggestion(iso: 400).seconds, 1.0 / 400, accuracy: 1e-9)
    }

    func testHalfMoonAtF8() {
        // One stop more light than the full Moon: f/8 at 1/ISO.
        XCTAssertEqual(suggestion(fraction: 0.5, aperture: 8).seconds, 0.01, accuracy: 1e-9)
        XCTAssertEqual(suggestion(fraction: 0.2, aperture: 5.6).seconds, 0.01, accuracy: 1e-9)
    }

    func testExposureValuesAtISO100() {
        XCTAssertEqual(suggestion(fraction: 1.0).exposureValue, 13.6, accuracy: 0.05)
        XCTAssertEqual(suggestion(fraction: 0.5).exposureValue, 12.6, accuracy: 0.05)
        XCTAssertEqual(suggestion(fraction: 0.2).exposureValue, 11.6, accuracy: 0.05)
        XCTAssertEqual(suggestion(fraction: 1.0).exposureValue, log2(11.0 * 11.0 * 100), accuracy: 1e-12)
    }

    func testShutterScalesWithISOAndAperture() {
        let base = suggestion(fraction: 0.5, aperture: 8)
        XCTAssertEqual(suggestion(fraction: 0.5, aperture: 8, iso: 200).seconds, base.seconds / 2, accuracy: 1e-12)
        XCTAssertEqual(suggestion(fraction: 0.5, aperture: 16).seconds, base.seconds * 4, accuracy: 1e-12)
        XCTAssertEqual(suggestion(fraction: 0.5, aperture: 8, iso: 800).seconds, base.seconds / 8, accuracy: 1e-12)
    }

    func testThePhaseAdjustmentIsALineBetweenTheAnchorsAndHeldOutside() {
        let crescent = suggestion(fraction: 0.2).exposureValue
        let half = suggestion(fraction: 0.5).exposureValue
        let full = suggestion(fraction: 1.0).exposureValue
        XCTAssertEqual(suggestion(fraction: 0.35).exposureValue, (crescent + half) / 2, accuracy: 1e-12)
        XCTAssertEqual(suggestion(fraction: 0.75).exposureValue, (half + full) / 2, accuracy: 1e-12)
        XCTAssertEqual(suggestion(fraction: 0.0).exposureValue, crescent, accuracy: 1e-12)
        XCTAssertEqual(suggestion(fraction: 0.05).exposureValue, crescent, accuracy: 1e-12)
        XCTAssertEqual(suggestion(fraction: 1.7).exposureValue, full, accuracy: 1e-12)
        XCTAssertTrue(suggestion(fraction: 0.3).seconds > suggestion(fraction: 0.6).seconds)
    }

    func testALowMoonNeedsMoreLight() {
        // At 30 degrees the airmass is 2: 0.3 stops lost.
        let low = suggestion(altitude: 30)
        XCTAssertEqual(low.airmass, 2, accuracy: 1e-9)
        XCTAssertEqual(low.seconds, 0.01 * pow(2.0, 0.3), accuracy: 1e-9)
        XCTAssertEqual(low.note, "Low Moon (2.0 airmasses): 0.3 stops more light for the extinction.")
        XCTAssertTrue(suggestion(altitude: 15).seconds > low.seconds)
    }

    func testTheAirmassIsCapped() {
        for altitude in [11.0, 5.0, 0.5] {
            XCTAssertEqual(suggestion(altitude: altitude).airmass, 5, accuracy: 1e-12, "\(altitude)")
        }
        let atTheHorizon = suggestion(altitude: 0)
        XCTAssertEqual(atTheHorizon.airmass, 5, accuracy: 1e-12)
        XCTAssertEqual(suggestion(altitude: -20).airmass, 5, accuracy: 1e-12)
        XCTAssertEqual(atTheHorizon.seconds, 0.01 * pow(2.0, 1.2), accuracy: 1e-9)
        XCTAssertEqual(
            atTheHorizon.note, "The Moon is at or below the horizon: the extinction is the largest the rule counts."
        )
        XCTAssertEqual(suggestion(altitude: 90).airmass, 1, accuracy: 1e-12)
        XCTAssertEqual(suggestion(altitude: 400).airmass, 1, accuracy: 1e-12)
    }

    func testNotesNameThePhaseAndTheExtinction() {
        XCTAssertEqual(
            suggestion(fraction: 0.5).note, "A 50% lit Moon needs about 0.9 stops more light than a full Moon."
        )
        XCTAssertEqual(
            suggestion(fraction: 0.2, altitude: 30).note,
            "A 20% lit Moon needs about 1.9 stops more light than a full Moon. "
                + "Low Moon (2.0 airmasses): 0.3 stops more light for the extinction."
        )
    }

    func testValuesThatAreNotNumbersTakeTheirFallbacks() {
        let reference = suggestion()
        XCTAssertEqual(suggestion(fraction: .nan).seconds, reference.seconds, accuracy: 1e-12)
        XCTAssertEqual(suggestion(altitude: .nan).seconds, reference.seconds, accuracy: 1e-12)
        XCTAssertEqual(suggestion(altitude: .nan).airmass, 1, accuracy: 1e-12)
        XCTAssertEqual(suggestion(iso: .nan).seconds, reference.seconds, accuracy: 1e-12)
        XCTAssertEqual(
            suggestion(aperture: .nan).seconds, suggestion(aperture: LensSetup.defaultAperture).seconds, accuracy: 1e-12
        )
    }

    func testApertureAndISOAreLimitedToTheirRanges() {
        XCTAssertEqual(suggestion(aperture: 500).seconds, suggestion(aperture: 32).seconds, accuracy: 1e-12)
        XCTAssertEqual(suggestion(aperture: 0).seconds, suggestion(aperture: 0.95).seconds, accuracy: 1e-12)
        XCTAssertEqual(suggestion(iso: 1e9).seconds, suggestion(iso: 102_400).seconds, accuracy: 1e-12)
        XCTAssertEqual(suggestion(iso: -100).seconds, suggestion(iso: 50).seconds, accuracy: 1e-12)
    }
}
