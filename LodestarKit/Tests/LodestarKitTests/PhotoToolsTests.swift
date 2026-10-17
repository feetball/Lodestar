import Foundation
import XCTest
@testable import LodestarKit

// MARK: - Sensor formats

final class SensorFormatTests: XCTestCase {

    func testPresetsAreListedInPickerOrder() {
        XCTAssertEqual(
            SensorFormat.presets.map(\.id),
            ["fullFrame", "apsC", "apsCCanon", "microFourThirds", "oneInch", "mediumFormat44x33"]
        )
        XCTAssertEqual(SensorFormat.presets.first, .fullFrame)
        XCTAssertEqual(Set(SensorFormat.presets.map(\.id)).count, SensorFormat.presets.count)
        XCTAssertEqual(Set(SensorFormat.presets.map(\.name)).count, SensorFormat.presets.count)
    }

    func testPresetDimensions() {
        let expected: [(SensorFormat, Double, Double)] = [
            (.fullFrame, 36, 24),
            (.apsC, 23.5, 15.6),
            (.apsCCanon, 22.3, 14.9),
            (.microFourThirds, 17.3, 13),
            (.oneInch, 13.2, 8.8),
            (.mediumFormat44x33, 43.8, 32.9),
        ]
        for (sensor, width, height) in expected {
            XCTAssertEqual(sensor.widthMillimeters, width, sensor.id)
            XCTAssertEqual(sensor.heightMillimeters, height, sensor.id)
            XCTAssertTrue(SensorFormat.dimensionRange.contains(width) && SensorFormat.dimensionRange.contains(height))
        }
    }

    func testCropFactors() {
        XCTAssertEqual(SensorFormat.fullFrame.cropFactor, 1.0)
        XCTAssertEqual(SensorFormat.apsC.cropFactor, 1.5339, accuracy: 0.0001)
        XCTAssertEqual(SensorFormat.apsCCanon.cropFactor, 1.6132, accuracy: 0.0001)
        XCTAssertEqual(SensorFormat.microFourThirds.cropFactor, 1.9994, accuracy: 0.0001)
        XCTAssertEqual(SensorFormat.oneInch.cropFactor, 2.7273, accuracy: 0.0001)
        XCTAssertEqual(SensorFormat.mediumFormat44x33.cropFactor, 0.7898, accuracy: 0.0001)
    }

    func testDiagonal() {
        XCTAssertEqual(SensorFormat.fullFrame.diagonalMillimeters, 43.2666, accuracy: 0.0001)
        XCTAssertEqual(SensorFormat.mediumFormat44x33.diagonalMillimeters, 54.7800, accuracy: 0.0001)
    }

    // MARK: Custom sizes

    func testCustomSensor() {
        let sensor = SensorFormat.custom(width: 24, height: 16)
        XCTAssertEqual(sensor.widthMillimeters, 24)
        XCTAssertEqual(sensor.heightMillimeters, 16)
        XCTAssertEqual(sensor.cropFactor, 1.5, accuracy: 1e-12)
        XCTAssertEqual(sensor.id, "custom-24.0x16.0")
        XCTAssertEqual(sensor.name, "Custom 24 \u{00D7} 16 mm")
        XCTAssertFalse(SensorFormat.presets.contains(sensor))

        XCTAssertEqual(SensorFormat.custom(width: 23.456, height: 15.6).name, "Custom 23.46 \u{00D7} 15.6 mm")
    }

    func testCustomSensorsWithSameSizeAreEqual() {
        let first = SensorFormat.custom(width: 20, height: 13.5)
        let second = SensorFormat.custom(width: 20, height: 13.5)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        XCTAssertNotEqual(first, SensorFormat.custom(width: 20, height: 13.6))
        XCTAssertNotEqual(first.id, SensorFormat.custom(width: 13.5, height: 20).id)
    }

    func testCustomSensorLimitsEachDimensionToTheSupportedRange() {
        XCTAssertEqual(SensorFormat.custom(width: 0, height: 24).widthMillimeters, 1)
        XCTAssertEqual(SensorFormat.custom(width: -36, height: 24).widthMillimeters, 1)
        XCTAssertEqual(SensorFormat.custom(width: 36, height: 0.5).heightMillimeters, 1)
        XCTAssertEqual(SensorFormat.custom(width: 1e9, height: 24).widthMillimeters, 200)
        XCTAssertEqual(SensorFormat.custom(width: 36, height: 200.001).heightMillimeters, 200)
        // The other dimension is left alone.
        XCTAssertEqual(SensorFormat.custom(width: 0, height: 24).heightMillimeters, 24)
        XCTAssertEqual(SensorFormat.custom(width: 1e9, height: 24).heightMillimeters, 24)
    }

    func testCustomSensorReplacesNonFiniteDimensionsWithFullFrame() {
        for value in [Double.nan, .infinity, -.infinity] {
            let width = SensorFormat.custom(width: value, height: 16)
            XCTAssertEqual(width.widthMillimeters, 36)
            XCTAssertEqual(width.heightMillimeters, 16)
            let height = SensorFormat.custom(width: 24, height: value)
            XCTAssertEqual(height.widthMillimeters, 24)
            XCTAssertEqual(height.heightMillimeters, 24)
        }
    }

    func testCustomSensorIsAlwaysUsable() {
        for width in [0.0, -1, .nan, .infinity, 1e300, 36] {
            for height in [0.0, -1, .nan, -.infinity, 1e300, 24] {
                let sensor = SensorFormat.custom(width: width, height: height)
                XCTAssertTrue(SensorFormat.dimensionRange.contains(sensor.widthMillimeters))
                XCTAssertTrue(SensorFormat.dimensionRange.contains(sensor.heightMillimeters))
                XCTAssertTrue(sensor.cropFactor.isFinite && sensor.cropFactor > 0)
            }
        }
    }

    func testValidatedCustomSensorRejectsInvalidInput() {
        XCTAssertEqual(SensorFormat.validated(width: 24, height: 16), SensorFormat.custom(width: 24, height: 16))
        XCTAssertNotNil(SensorFormat.validated(width: 1, height: 1))
        XCTAssertNotNil(SensorFormat.validated(width: 200, height: 200))
        let invalid: [Double] = [0, -1, -36, .nan, .infinity, -.infinity, 0.999, 200.001, 1e9, 1e308]
        for value in invalid {
            XCTAssertNil(SensorFormat.validated(width: value, height: 24), "width \(value)")
            XCTAssertNil(SensorFormat.validated(width: 36, height: value), "height \(value)")
        }
    }

    // MARK: Pixel pitch

    func testPixelPitchFromMegapixels() throws {
        // pitch = sqrt(width x height / pixel count)
        XCTAssertEqual(try XCTUnwrap(SensorFormat.fullFrame.pixelPitchMicrometers(megapixels: 24)), 6.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(SensorFormat.fullFrame.pixelPitchMicrometers(megapixels: 45)), 4.3818, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SensorFormat.fullFrame.pixelPitchMicrometers(megapixels: 61)), 3.7635, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SensorFormat.apsCCanon.pixelPitchMicrometers(megapixels: 32.5)), 3.1975, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SensorFormat.microFourThirds.pixelPitchMicrometers(megapixels: 20)), 3.3534, accuracy: 0.0001)
    }

    func testPixelPitchScalesWithTheSquareRootOfResolution() throws {
        let low = try XCTUnwrap(SensorFormat.fullFrame.pixelPitchMicrometers(megapixels: 12))
        let high = try XCTUnwrap(SensorFormat.fullFrame.pixelPitchMicrometers(megapixels: 48))
        XCTAssertEqual(low / high, 2.0, accuracy: 1e-12)
    }

    func testPixelPitchRejectsInvalidResolution() {
        for megapixels in [0.0, -24, .nan, .infinity, -.infinity, 1e9, 1e-4, 1e300, -1e-300] {
            XCTAssertNil(SensorFormat.fullFrame.pixelPitchMicrometers(megapixels: megapixels), "\(megapixels) MP")
        }
        // A pitch outside the supported range is rejected even for a positive resolution.
        XCTAssertNil(SensorFormat.oneInch.pixelPitchMicrometers(megapixels: 5000))
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        let custom = SensorFormat.custom(width: 20.5, height: 13.7)
        for sensor in SensorFormat.presets + [custom] {
            let data = try JSONEncoder().encode(sensor)
            XCTAssertEqual(try JSONDecoder().decode(SensorFormat.self, from: data), sensor)
        }
    }

    func testEncodedKeys() throws {
        let data = try JSONEncoder().encode(SensorFormat.fullFrame)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "name", "widthMillimeters", "heightMillimeters"])
    }

    func testDecodingRejectsCorruptedData() {
        let longName = String(repeating: "x", count: 129)
        let documents = [
            #"{"id":"a","name":"b","widthMillimeters":0,"heightMillimeters":24}"#,
            #"{"id":"a","name":"b","widthMillimeters":36,"heightMillimeters":0}"#,
            #"{"id":"a","name":"b","widthMillimeters":-36,"heightMillimeters":24}"#,
            #"{"id":"a","name":"b","widthMillimeters":36,"heightMillimeters":-24}"#,
            #"{"id":"a","name":"b","widthMillimeters":1e9,"heightMillimeters":24}"#,
            #"{"id":"a","name":"b","widthMillimeters":36,"heightMillimeters":1e308}"#,
            #"{"id":"","name":"b","widthMillimeters":36,"heightMillimeters":24}"#,
            #"{"id":"a","name":"","widthMillimeters":36,"heightMillimeters":24}"#,
            #"{"id":"\#(longName)","name":"b","widthMillimeters":36,"heightMillimeters":24}"#,
            #"{"id":"a","name":"\#(longName)","widthMillimeters":36,"heightMillimeters":24}"#,
            #"{"id":"a","name":"b","widthMillimeters":36}"#,
            #"{"id":"a","name":"b","widthMillimeters":"36","heightMillimeters":24}"#,
            #"{"id":1,"name":"b","widthMillimeters":36,"heightMillimeters":24}"#,
            #"[]"#,
            #"null"#,
        ]
        for document in documents {
            XCTAssertThrowsError(try JSONDecoder().decode(SensorFormat.self, from: Data(document.utf8)), document)
        }
    }

    func testDecodingAcceptsAValidDocument() throws {
        let document = #"{"id":"fullFrame","name":"Full Frame","widthMillimeters":36,"heightMillimeters":24}"#
        XCTAssertEqual(try JSONDecoder().decode(SensorFormat.self, from: Data(document.utf8)), .fullFrame)
    }
}

// MARK: - Range limiting

final class RangeLimiterTests: XCTestCase {

    func testValuesInsideTheRangeAreKept() {
        XCTAssertEqual(RangeLimiter.limit(5, to: 1...10, fallback: 3), 5)
        XCTAssertEqual(RangeLimiter.limit(1, to: 1...10, fallback: 3), 1)
        XCTAssertEqual(RangeLimiter.limit(10, to: 1...10, fallback: 3), 10)
    }

    func testValuesOutsideTheRangeAreLimited() {
        XCTAssertEqual(RangeLimiter.limit(0.5, to: 1...10, fallback: 3), 1)
        XCTAssertEqual(RangeLimiter.limit(-1e300, to: 1...10, fallback: 3), 1)
        XCTAssertEqual(RangeLimiter.limit(10.5, to: 1...10, fallback: 3), 10)
        XCTAssertEqual(RangeLimiter.limit(1e300, to: 1...10, fallback: 3), 10)
    }

    func testValuesThatAreNotFiniteUseTheFallback() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(RangeLimiter.limit(value, to: 1...10, fallback: 3), 3)
        }
    }
}

// MARK: - Lens setups

final class LensSetupTests: XCTestCase {

    private func setup(
        sensor: SensorFormat = .fullFrame,
        focalLength: Double = 24,
        aperture: Double = 2.8,
        pitch: Double? = nil
    ) -> LensSetup {
        LensSetup(sensor: sensor, focalLengthMillimeters: focalLength, aperture: aperture, pixelPitchMicrometers: pitch)
    }

    private func validated(
        sensor: SensorFormat = .fullFrame,
        focalLength: Double = 24,
        aperture: Double = 2.8,
        pitch: Double? = nil
    ) -> LensSetup? {
        LensSetup.validated(
            sensor: sensor, focalLengthMillimeters: focalLength, aperture: aperture, pixelPitchMicrometers: pitch
        )
    }

    func testValidValuesAreKept() {
        let lens = setup(pitch: 5.9)
        XCTAssertEqual(lens.sensor, .fullFrame)
        XCTAssertEqual(lens.focalLengthMillimeters, 24)
        XCTAssertEqual(lens.aperture, 2.8)
        XCTAssertEqual(lens.pixelPitchMicrometers, 5.9)
        XCTAssertNil(setup().pixelPitchMicrometers)
        XCTAssertNil(LensSetup(sensor: .apsC, focalLengthMillimeters: 85, aperture: 1.8).pixelPitchMicrometers)
    }

    func testDefaultsMatchTheStartingSettings() {
        XCTAssertEqual(LensSetup.defaultFocalLengthMillimeters, 24)
        XCTAssertEqual(LensSetup.defaultAperture, 2.8)
        XCTAssertTrue(LensSetup.focalLengthRange.contains(LensSetup.defaultFocalLengthMillimeters))
        XCTAssertTrue(LensSetup.apertureRange.contains(LensSetup.defaultAperture))
    }

    // MARK: Limiting

    func testFocalLengthIsLimitedToTheSupportedRange() {
        XCTAssertEqual(setup(focalLength: 4).focalLengthMillimeters, 4)
        XCTAssertEqual(setup(focalLength: 2000).focalLengthMillimeters, 2000)
        XCTAssertEqual(setup(focalLength: 3.999).focalLengthMillimeters, 4)
        XCTAssertEqual(setup(focalLength: 0).focalLengthMillimeters, 4)
        XCTAssertEqual(setup(focalLength: -24).focalLengthMillimeters, 4)
        XCTAssertEqual(setup(focalLength: 2000.001).focalLengthMillimeters, 2000)
        XCTAssertEqual(setup(focalLength: 1e308).focalLengthMillimeters, 2000)
    }

    func testApertureIsLimitedToTheSupportedRange() {
        XCTAssertEqual(setup(aperture: 0.95).aperture, 0.95)
        XCTAssertEqual(setup(aperture: 32).aperture, 32)
        XCTAssertEqual(setup(aperture: 0.94).aperture, 0.95)
        XCTAssertEqual(setup(aperture: 0).aperture, 0.95)
        XCTAssertEqual(setup(aperture: -2.8).aperture, 0.95)
        XCTAssertEqual(setup(aperture: 64).aperture, 32)
    }

    func testNonFiniteValuesBecomeTheDefaults() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(setup(focalLength: value).focalLengthMillimeters, 24, "focal length \(value)")
            XCTAssertEqual(setup(aperture: value).aperture, 2.8, "aperture \(value)")
            XCTAssertNil(setup(pitch: value).pixelPitchMicrometers, "pixel pitch \(value)")
        }
    }

    func testPixelPitchOutsideTheSupportedRangeIsTreatedAsUnknown() {
        XCTAssertEqual(setup(pitch: 0.3).pixelPitchMicrometers, 0.3)
        XCTAssertEqual(setup(pitch: 100).pixelPitchMicrometers, 100)
        for value in [0.29, 100.1, 0, -5, 1e9] {
            XCTAssertNil(setup(pitch: value).pixelPitchMicrometers, "pixel pitch \(value)")
        }
    }

    func testEveryInputProducesAUsableSetup() {
        let values: [Double] = [.nan, .infinity, -.infinity, 0, -1, 1e-300, 1e300, 4, 24, 2000]
        for focalLength in values {
            for aperture in values {
                for pitch in [nil, 0, 1e300, 4] as [Double?] {
                    let lens = setup(focalLength: focalLength, aperture: aperture, pitch: pitch)
                    XCTAssertTrue(LensSetup.focalLengthRange.contains(lens.focalLengthMillimeters))
                    XCTAssertTrue(LensSetup.apertureRange.contains(lens.aperture))
                    XCTAssertTrue(lens.pixelPitchMicrometers.map { SensorFormat.pixelPitchRange.contains($0) } ?? true)
                    XCTAssertTrue(lens.fieldOfView.horizontal.isFinite)
                }
            }
        }
    }

    // MARK: Validation

    func testValidatedAcceptsEverythingInRange() {
        XCTAssertEqual(validated(pitch: 5.9), setup(pitch: 5.9))
        XCTAssertEqual(validated(), setup())
        XCTAssertNotNil(validated(focalLength: 4))
        XCTAssertNotNil(validated(focalLength: 2000))
        XCTAssertNotNil(validated(aperture: 0.95))
        XCTAssertNotNil(validated(aperture: 32))
        XCTAssertNotNil(validated(pitch: 0.3))
        XCTAssertNotNil(validated(pitch: 100))
    }

    func testValidatedRejectsAnythingOutOfRange() {
        XCTAssertNil(validated(focalLength: 3.999))
        XCTAssertNil(validated(focalLength: 2000.001))
        XCTAssertNil(validated(aperture: 0.94))
        XCTAssertNil(validated(aperture: 32.01))
        XCTAssertNil(validated(pitch: 0.29))
        XCTAssertNil(validated(pitch: 100.1))
        for value in [0.0, -24, .nan, .infinity, -.infinity, 1e308] {
            XCTAssertNil(validated(focalLength: value), "focal length \(value)")
            XCTAssertNil(validated(aperture: value), "aperture \(value)")
            XCTAssertNil(validated(pitch: value), "pixel pitch \(value)")
        }
    }

    // MARK: Derived values

    func testEquivalentFocalLength() {
        XCTAssertEqual(setup(focalLength: 50).equivalentFocalLengthMillimeters, 50, accuracy: 1e-12)
        let crop = SensorFormat.custom(width: 24, height: 16)
        XCTAssertEqual(setup(sensor: crop, focalLength: 24).equivalentFocalLengthMillimeters, 36, accuracy: 1e-9)
        XCTAssertEqual(
            setup(sensor: .apsCCanon, focalLength: 24).equivalentFocalLengthMillimeters,
            38.7177,
            accuracy: 0.0001
        )
    }

    func testImageScale() throws {
        // 206.265 x pitch(um) / focal length(mm) arcseconds per pixel.
        XCTAssertEqual(try XCTUnwrap(setup(focalLength: 50, pitch: 5).imageScaleArcsecondsPerPixel), 20.6265, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(setup(focalLength: 24, pitch: 5.97).imageScaleArcsecondsPerPixel), 51.3084, accuracy: 0.0001)
        XCTAssertNil(setup(focalLength: 50).imageScaleArcsecondsPerPixel)
    }

    func testFieldOfViewMatchesTheStaticFunctions() {
        let lens = setup(sensor: .apsC, focalLength: 35)
        XCTAssertEqual(lens.fieldOfView.horizontal, FieldOfView.horizontal(sensor: .apsC, focalLength: 35))
        XCTAssertEqual(lens.fieldOfView.vertical, FieldOfView.vertical(sensor: .apsC, focalLength: 35))
        XCTAssertEqual(lens.fieldOfView.diagonal, FieldOfView.diagonal(sensor: .apsC, focalLength: 35))
        XCTAssertEqual(lens.fieldOfView, FieldOfView.of(sensor: .apsC, focalLength: 35))
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        for lens in [setup(), setup(sensor: .microFourThirds, focalLength: 300, aperture: 4, pitch: 3.7)] {
            let data = try JSONEncoder().encode(lens)
            XCTAssertEqual(try JSONDecoder().decode(LensSetup.self, from: data), lens)
        }
    }

    func testEncodingOmitsAnUnknownPixelPitch() throws {
        let data = try JSONEncoder().encode(setup())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["sensor", "focalLengthMillimeters", "aperture"])
    }

    func testDecodingRejectsOutOfRangeValues() throws {
        let sensor = String(decoding: try JSONEncoder().encode(SensorFormat.fullFrame), as: UTF8.self)
        let documents = [
            #"{"sensor":\#(sensor),"focalLengthMillimeters":3,"aperture":2.8}"#,
            #"{"sensor":\#(sensor),"focalLengthMillimeters":5000,"aperture":2.8}"#,
            #"{"sensor":\#(sensor),"focalLengthMillimeters":24,"aperture":0}"#,
            #"{"sensor":\#(sensor),"focalLengthMillimeters":24,"aperture":64}"#,
            #"{"sensor":\#(sensor),"focalLengthMillimeters":24,"aperture":2.8,"pixelPitchMicrometers":1000}"#,
            #"{"sensor":\#(sensor),"focalLengthMillimeters":24,"aperture":2.8,"pixelPitchMicrometers":-4}"#,
            #"{"sensor":{"id":"a","name":"b","widthMillimeters":0,"heightMillimeters":24},"focalLengthMillimeters":24,"aperture":2.8}"#,
            #"{"focalLengthMillimeters":24,"aperture":2.8}"#,
            #"{"sensor":\#(sensor),"aperture":2.8}"#,
            #"{"sensor":\#(sensor),"focalLengthMillimeters":"24","aperture":2.8}"#,
        ]
        for document in documents {
            XCTAssertThrowsError(try JSONDecoder().decode(LensSetup.self, from: Data(document.utf8)), document)
        }
        let valid = #"{"sensor":\#(sensor),"focalLengthMillimeters":24,"aperture":2.8,"pixelPitchMicrometers":5.9}"#
        XCTAssertNoThrow(try JSONDecoder().decode(LensSetup.self, from: Data(valid.utf8)))
    }
}

// MARK: - Field of view and framing

final class FieldOfViewTests: XCTestCase {

    private func frame(_ sensor: SensorFormat, _ focalLength: Double) -> FrameSize {
        FieldOfView.of(sensor: sensor, focalLength: focalLength)
    }

    func testFiftyMillimetreOnFullFrame() {
        let frame = frame(.fullFrame, 50)
        XCTAssertEqual(frame.horizontal, 39.6, accuracy: 0.05)
        XCTAssertEqual(frame.vertical, 27.0, accuracy: 0.05)
        XCTAssertEqual(frame.diagonal, 46.8, accuracy: 0.05)
        XCTAssertEqual(frame.horizontal, 39.597753, accuracy: 1e-6)
        XCTAssertEqual(frame.vertical, 26.991467, accuracy: 1e-6)
        XCTAssertEqual(frame.diagonal, 46.793003, accuracy: 1e-6)
    }

    func testOtherFullFrameLenses() {
        let wide = frame(.fullFrame, 14)
        XCTAssertEqual(wide.horizontal, 104.250033, accuracy: 1e-6)
        XCTAssertEqual(wide.vertical, 81.202589, accuracy: 1e-6)
        XCTAssertEqual(wide.diagonal, 114.182131, accuracy: 1e-6)

        let normal = frame(.fullFrame, 24)
        // tan(36.87 degrees) is exactly 3/4, so 24 mm on 36 mm is 2 x atan(0.75).
        XCTAssertEqual(normal.horizontal, 73.739795, accuracy: 1e-6)
        XCTAssertEqual(normal.vertical, 53.130102, accuracy: 1e-6)

        let tele = frame(.fullFrame, 100)
        XCTAssertEqual(tele.horizontal, 20.407947, accuracy: 1e-6)
        XCTAssertEqual(tele.vertical, 13.685547, accuracy: 1e-6)
    }

    func testStaticFunctionsAgreeWithFrameSize() {
        let frame = frame(.apsC, 85)
        XCTAssertEqual(FieldOfView.horizontal(sensor: .apsC, focalLength: 85), frame.horizontal)
        XCTAssertEqual(FieldOfView.vertical(sensor: .apsC, focalLength: 85), frame.vertical)
        XCTAssertEqual(FieldOfView.diagonal(sensor: .apsC, focalLength: 85), frame.diagonal)
    }

    func testLongerLensesSeeLess() {
        var previous = Double.infinity
        for focalLength in [8.0, 14, 24, 50, 135, 400, 2000] {
            let horizontal = frame(.fullFrame, focalLength).horizontal
            XCTAssertLessThan(horizontal, previous)
            previous = horizontal
        }
    }

    func testSmallerSensorsSeeLess() {
        var previous = Double.infinity
        for sensor in [SensorFormat.mediumFormat44x33, .fullFrame, .apsC, .apsCCanon, .microFourThirds, .oneInch] {
            let horizontal = frame(sensor, 50).horizontal
            XCTAssertLessThan(horizontal, previous, sensor.id)
            previous = horizontal
        }
    }

    func testCropFactorEquivalence() {
        // A sensor with crop factor 1.5 at 24 mm frames like full frame at 36 mm.
        let crop = SensorFormat.custom(width: 24, height: 16)
        let cropped = frame(crop, 24)
        let equivalent = frame(.fullFrame, 36)
        XCTAssertEqual(cropped.horizontal, equivalent.horizontal, accuracy: 1e-9)
        XCTAssertEqual(cropped.vertical, equivalent.vertical, accuracy: 1e-9)
        XCTAssertEqual(cropped.diagonal, equivalent.diagonal, accuracy: 1e-9)
    }

    func testFocalLengthsBelowTheLensRangeAreStillCalculated() {
        // A phone camera has a real focal length of a few millimetres; the maths holds for it.
        let expected = 2 * atan(13.2 / 4) * 180 / .pi
        XCTAssertEqual(FieldOfView.horizontal(sensor: .oneInch, focalLength: 2), expected, accuracy: 1e-9)
    }

    func testInvalidFocalLengthsUseTheDefaultLens() {
        let reference = frame(.fullFrame, LensSetup.defaultFocalLengthMillimeters)
        for focalLength in [0.0, -50, .nan, .infinity, -.infinity, -0.0] {
            XCTAssertEqual(FieldOfView.horizontal(sensor: .fullFrame, focalLength: focalLength), reference.horizontal, "\(focalLength)")
            XCTAssertEqual(FieldOfView.vertical(sensor: .fullFrame, focalLength: focalLength), reference.vertical, "\(focalLength)")
            XCTAssertEqual(FieldOfView.diagonal(sensor: .fullFrame, focalLength: focalLength), reference.diagonal, "\(focalLength)")
            XCTAssertEqual(FieldOfView.of(sensor: .fullFrame, focalLength: focalLength), reference, "\(focalLength)")
        }
    }

    func testResultsAreAlwaysValidAngles() {
        for focalLength in [1e-300, 1e-9, 1e-3, 1, 1e3, 1e9, 1e300] {
            let size = frame(.fullFrame, focalLength)
            for angle in [size.horizontal, size.vertical, size.diagonal] {
                XCTAssertTrue(angle.isFinite && angle >= 0 && angle <= 180, "\(angle) at \(focalLength) mm")
            }
        }
        XCTAssertEqual(frame(.fullFrame, 1e-9).horizontal, 180, accuracy: 1e-6)
        XCTAssertEqual(frame(.fullFrame, 1e9).horizontal, 2.0626e-6, accuracy: 1e-9)
    }

    func testFrameSizeGeometry() {
        let size = FrameSize(horizontal: 20, vertical: 13, diagonal: 24)
        XCTAssertEqual(size.longSide, 20)
        XCTAssertEqual(size.shortSide, 13)
        XCTAssertEqual(size.rotated, FrameSize(horizontal: 13, vertical: 20, diagonal: 24))
        XCTAssertEqual(size.rotated.rotated, size)
        XCTAssertEqual(size.rotated.longSide, 20)
        XCTAssertEqual(size.rotated.shortSide, 13)
    }

    // MARK: Framing

    func testAndromedaInA135mmFrame() throws {
        // M31 spans about 190 x 60 arcminutes.
        let framing = try XCTUnwrap(frame(.fullFrame, 135).framing(objectMajorArcmin: 190, minorArcmin: 60))
        XCTAssertEqual(framing.majorAxisFraction, 0.208480, accuracy: 1e-6)
        XCTAssertEqual(framing.minorAxisFraction, 0.098433, accuracy: 1e-6)
        XCTAssertEqual(framing.fillFraction, framing.majorAxisFraction)
        XCTAssertTrue(framing.fitsInFrame)
    }

    func testObjectThatDoesNotFit() throws {
        let tight = try XCTUnwrap(frame(.fullFrame, 800).framing(objectMajorArcmin: 190, minorArcmin: 60))
        XCTAssertEqual(tight.majorAxisFraction, 1.228402, accuracy: 1e-6)
        XCTAssertEqual(tight.minorAxisFraction, 0.581820, accuracy: 1e-6)
        XCTAssertEqual(tight.fillFraction, tight.majorAxisFraction)
        XCTAssertFalse(tight.fitsInFrame)

        let snug = try XCTUnwrap(frame(.fullFrame, 600).framing(objectMajorArcmin: 190, minorArcmin: 60))
        XCTAssertEqual(snug.majorAxisFraction, 0.921422, accuracy: 1e-6)
        XCTAssertTrue(snug.fitsInFrame)
    }

    func testFramingUsesTheTighterDimension() throws {
        // A nearly round object is limited by the short side of the frame.
        let framing = try XCTUnwrap(frame(.fullFrame, 135).framing(objectMajorArcmin: 500, minorArcmin: 480))
        XCTAssertGreaterThan(framing.minorAxisFraction, framing.majorAxisFraction)
        XCTAssertEqual(framing.fillFraction, framing.minorAxisFraction)
        XCTAssertEqual(framing.minorAxisFraction, 480 / (10.159216 * 60), accuracy: 1e-6)
    }

    func testFramingIsIndependentOfOrientationAndArgumentOrder() throws {
        let landscape = frame(.fullFrame, 200)
        let first = try XCTUnwrap(landscape.framing(objectMajorArcmin: 120, minorArcmin: 40))
        XCTAssertEqual(landscape.rotated.framing(objectMajorArcmin: 120, minorArcmin: 40), first)
        XCTAssertEqual(landscape.framing(objectMajorArcmin: 40, minorArcmin: 120), first)
    }

    func testFramingBoundary() throws {
        let size = FrameSize(horizontal: 2, vertical: 1, diagonal: 2.3)
        let exact = try XCTUnwrap(size.framing(objectMajorArcmin: 120, minorArcmin: 30))
        XCTAssertEqual(exact.majorAxisFraction, 1.0, accuracy: 1e-12)
        XCTAssertTrue(exact.fitsInFrame)
        let over = try XCTUnwrap(size.framing(objectMajorArcmin: 120.01, minorArcmin: 30))
        XCTAssertFalse(over.fitsInFrame)
    }

    func testFramingOfLineLikeObjects() throws {
        let framing = try XCTUnwrap(frame(.fullFrame, 135).framing(objectMajorArcmin: 60, minorArcmin: 0))
        XCTAssertEqual(framing.minorAxisFraction, 0)
        XCTAssertGreaterThan(framing.majorAxisFraction, 0)
    }

    func testFramingRejectsInvalidInput() {
        let size = frame(.fullFrame, 135)
        XCTAssertNil(size.framing(objectMajorArcmin: 0, minorArcmin: 0))
        XCTAssertNil(size.framing(objectMajorArcmin: -1, minorArcmin: 1))
        XCTAssertNil(size.framing(objectMajorArcmin: 10, minorArcmin: -1))
        XCTAssertNil(size.framing(objectMajorArcmin: .nan, minorArcmin: 1))
        XCTAssertNil(size.framing(objectMajorArcmin: 10, minorArcmin: .nan))
        XCTAssertNil(size.framing(objectMajorArcmin: .infinity, minorArcmin: 1))
        XCTAssertNil(FrameSize(horizontal: 0, vertical: 10, diagonal: 10).framing(objectMajorArcmin: 10, minorArcmin: 5))
        XCTAssertNil(FrameSize(horizontal: -4, vertical: 10, diagonal: 10).framing(objectMajorArcmin: 10, minorArcmin: 5))
        XCTAssertNil(FrameSize(horizontal: .nan, vertical: 10, diagonal: 10).framing(objectMajorArcmin: 10, minorArcmin: 5))
    }
}

// MARK: - Exposure rules

final class ExposureCalculatorTests: XCTestCase {

    private func lens(
        sensor: SensorFormat = .fullFrame,
        focalLength: Double = 24,
        aperture: Double = 2.8,
        pitch: Double? = nil
    ) -> LensSetup {
        LensSetup(sensor: sensor, focalLengthMillimeters: focalLength, aperture: aperture, pixelPitchMicrometers: pitch)
    }

    private let crop15 = SensorFormat.custom(width: 24, height: 16)

    // MARK: 500, 400 and 300

    func testRuleOf500OnFullFrame() {
        let estimate = ExposureCalculator.maxExposure(rule: .rule500, setup: lens())
        XCTAssertEqual(estimate.seconds, 500.0 / 24, accuracy: 1e-9)
        XCTAssertEqual(estimate.rule, .rule500)
        XCTAssertFalse(estimate.usedDefaultPixelPitch)
        XCTAssertEqual(estimate.declinationFactor, 1)
        XCTAssertTrue(estimate.notes.isEmpty)
    }

    func testRuleOf500OnA1Point5CropSensor() {
        // 500 / (24 mm x 1.5) = 13.9 s
        let estimate = ExposureCalculator.maxExposure(rule: .rule500, setup: lens(sensor: crop15))
        XCTAssertEqual(estimate.seconds, 13.9, accuracy: 0.05)
        XCTAssertEqual(estimate.seconds, 500.0 / 36, accuracy: 1e-9)
    }

    func testRuleOf500OnRealCropSensors() {
        let canon = ExposureCalculator.maxExposure(rule: .rule500, setup: lens(sensor: .apsCCanon))
        XCTAssertEqual(canon.seconds, 12.9140, accuracy: 0.0001)
        let apsC = ExposureCalculator.maxExposure(rule: .rule500, setup: lens(sensor: .apsC))
        XCTAssertEqual(apsC.seconds, 500 / (24 * SensorFormat.apsC.cropFactor), accuracy: 1e-9)
        // The larger the crop factor, the shorter the exposure.
        XCTAssertGreaterThan(canon.seconds, ExposureCalculator.maxExposure(rule: .rule500, setup: lens(sensor: .oneInch)).seconds)
    }

    func testRulesOf400And300() {
        let setup = lens()
        XCTAssertEqual(ExposureCalculator.maxExposure(rule: .rule400, setup: setup).seconds, 400.0 / 24, accuracy: 1e-9)
        XCTAssertEqual(ExposureCalculator.maxExposure(rule: .rule300, setup: setup).seconds, 12.5, accuracy: 1e-9)
        let order = ExposureRule.allCases.filter { $0 != .npf }.map { ExposureCalculator.maxExposure(rule: $0, setup: setup).seconds }
        XCTAssertEqual(order, order.sorted(by: >), "500 is the most lenient rule and 300 the strictest")
    }

    func testRulesOf500FamilyIgnorePixelPitchAndAperture() {
        let reference = ExposureCalculator.maxExposure(rule: .rule500, setup: lens()).seconds
        let other = ExposureCalculator.maxExposure(rule: .rule500, setup: lens(aperture: 8, pitch: 2)).seconds
        XCTAssertEqual(reference, other)
    }

    // MARK: NPF

    func testNPFAgainstPublishedExample() {
        // Light Stalking's worked example: Nikon D750 (35.9 mm / 6016 px = 5.97 um), 24 mm at f/2.8,
        // (35 x 2.8 + 30 x 5.97) / 24 = 11.54 s.
        let estimate = ExposureCalculator.maxExposure(rule: .npf, setup: lens(pitch: 5.97))
        XCTAssertEqual(estimate.seconds, 11.54, accuracy: 0.01)
        XCTAssertEqual(estimate.seconds, (35 * 2.8 + 30 * 5.97) / 24, accuracy: 1e-12)
        XCTAssertEqual(estimate.seconds, 11.545833, accuracy: 1e-6)
        XCTAssertFalse(estimate.usedDefaultPixelPitch)
        XCTAssertTrue(estimate.notes.isEmpty)
    }

    func testNPFWithAnotherLens() {
        let setup = lens(sensor: .fullFrame, focalLength: 85, aperture: 1.8, pitch: 3.76)
        XCTAssertEqual(ExposureCalculator.maxExposure(rule: .npf, setup: setup).seconds, 2.068235, accuracy: 1e-6)
    }

    func testNPFUsesTheRealFocalLengthNotTheEquivalent() {
        // The same lens, aperture and pixel pitch give the same NPF exposure on any sensor size.
        let fullFrame = ExposureCalculator.maxExposure(rule: .npf, setup: lens(sensor: .fullFrame, pitch: 4))
        let apsC = ExposureCalculator.maxExposure(rule: .npf, setup: lens(sensor: .apsC, pitch: 4))
        let oneInch = ExposureCalculator.maxExposure(rule: .npf, setup: lens(sensor: .oneInch, pitch: 4))
        XCTAssertEqual(fullFrame.seconds, apsC.seconds)
        XCTAssertEqual(fullFrame.seconds, oneInch.seconds)
    }

    func testNPFGrowsWithPixelPitchAndAperture() {
        let small = ExposureCalculator.maxExposure(rule: .npf, setup: lens(pitch: 3)).seconds
        let large = ExposureCalculator.maxExposure(rule: .npf, setup: lens(pitch: 6)).seconds
        XCTAssertGreaterThan(large, small)
        let fast = ExposureCalculator.maxExposure(rule: .npf, setup: lens(aperture: 1.8, pitch: 4)).seconds
        let slow = ExposureCalculator.maxExposure(rule: .npf, setup: lens(aperture: 5.6, pitch: 4)).seconds
        XCTAssertGreaterThan(slow, fast)
    }

    func testNPFFallsBackToTheDefaultPixelPitch() {
        XCTAssertEqual(ExposureCalculator.defaultPixelPitchMicrometers, 4.0)
        let estimate = ExposureCalculator.maxExposure(rule: .npf, setup: lens(focalLength: 14))
        XCTAssertEqual(estimate.seconds, (35 * 2.8 + 30 * 4.0) / 14, accuracy: 1e-12)
        XCTAssertEqual(estimate.seconds, 15.571429, accuracy: 1e-6)
        XCTAssertTrue(estimate.usedDefaultPixelPitch)
        XCTAssertEqual(estimate.notes.count, 1)
        XCTAssertTrue(estimate.notes[0].contains("4.0"), estimate.notes[0])
        XCTAssertTrue(estimate.notes[0].lowercased().contains("pixel pitch"), estimate.notes[0])
    }

    func testOnlyNPFReportsTheDefaultPixelPitch() {
        for rule in ExposureRule.allCases {
            let estimate = ExposureCalculator.maxExposure(rule: rule, setup: lens())
            XCTAssertEqual(estimate.usedDefaultPixelPitch, rule == .npf, rule.rawValue)
            let known = ExposureCalculator.maxExposure(rule: rule, setup: lens(pitch: 5))
            XCTAssertFalse(known.usedDefaultPixelPitch, rule.rawValue)
        }
    }

    // MARK: Declination

    func testDeclinationLengthensTheExposure() {
        let setup = lens()
        let equator = ExposureCalculator.maxExposure(rule: .rule500, setup: setup)
        let sixty = ExposureCalculator.maxExposure(rule: .rule500, setup: setup, declination: 60)
        XCTAssertEqual(sixty.declinationFactor, 2, accuracy: 1e-12)
        XCTAssertEqual(sixty.seconds, equator.seconds * 2, accuracy: 1e-9)
        XCTAssertEqual(sixty.notes.count, 1)
        XCTAssertTrue(sixty.notes[0].contains("+60.0\u{00B0}"), sixty.notes[0])
        XCTAssertTrue(sixty.notes[0].contains("\u{00D7}2.0 "), sixty.notes[0])

        let thirty = ExposureCalculator.maxExposure(rule: .rule500, setup: setup, declination: 30)
        XCTAssertEqual(thirty.declinationFactor, 1.154701, accuracy: 1e-6)
        let seventy = ExposureCalculator.maxExposure(rule: .rule500, setup: setup, declination: 70)
        XCTAssertEqual(seventy.declinationFactor, 2.923804, accuracy: 1e-6)
        XCTAssertTrue(seventy.notes[0].contains("\u{00D7}2.9"), seventy.notes[0])
    }

    func testDeclinationIsSymmetricAndAppliesToEveryRule() {
        let setup = lens(pitch: 5)
        for rule in ExposureRule.allCases {
            let north = ExposureCalculator.maxExposure(rule: rule, setup: setup, declination: 45)
            let south = ExposureCalculator.maxExposure(rule: rule, setup: setup, declination: -45)
            let equator = ExposureCalculator.maxExposure(rule: rule, setup: setup, declination: 0)
            XCTAssertEqual(north.seconds, south.seconds, accuracy: 1e-9, rule.rawValue)
            XCTAssertEqual(north.seconds, equator.seconds * (1 / cos(Double.pi / 4)), accuracy: 1e-9, rule.rawValue)
            XCTAssertTrue(south.notes[0].contains("\u{2212}45.0\u{00B0}"), south.notes[0])
        }
    }

    func testDeclinationAtTheEquatorChangesNothing() {
        let setup = lens()
        let plain = ExposureCalculator.maxExposure(rule: .rule500, setup: setup)
        for declination in [0.0, -0.0, 1, -1, 2] {
            let estimate = ExposureCalculator.maxExposure(rule: .rule500, setup: setup, declination: declination)
            XCTAssertTrue(estimate.notes.isEmpty, "\(declination) should not need a note: \(estimate.notes)")
            XCTAssertEqual(estimate.seconds, plain.seconds, accuracy: plain.seconds * 0.001)
        }
    }

    func testDeclinationFactorIsCapped() {
        XCTAssertEqual(ExposureCalculator.maximumDeclinationFactor, 5)
        let setup = lens()
        let base = ExposureCalculator.maxExposure(rule: .rule500, setup: setup).seconds
        // 1 / cos(78.46 degrees) = 5; beyond that the cap applies.
        for declination in [80.0, 85, 89.9, 90, -80, -90] {
            let estimate = ExposureCalculator.maxExposure(rule: .rule500, setup: setup, declination: declination)
            XCTAssertEqual(estimate.declinationFactor, 5, declination.description)
            XCTAssertEqual(estimate.seconds, base * 5, accuracy: 1e-9, declination.description)
            XCTAssertEqual(estimate.notes.count, 1)
            XCTAssertTrue(estimate.notes[0].contains("\u{00D7}5.0, the maximum"), estimate.notes[0])
        }
        let justBelow = ExposureCalculator.maxExposure(rule: .rule500, setup: setup, declination: 78)
        XCTAssertLessThan(justBelow.declinationFactor, 5)
        XCTAssertFalse(justBelow.notes[0].contains("maximum"))
    }

    func testInvalidDeclinationIsIgnoredWithANote() {
        let setup = lens()
        let plain = ExposureCalculator.maxExposure(rule: .rule500, setup: setup)
        for declination in [91.0, -90.0001, 180, .nan, .infinity, -.infinity, 1e300] {
            let estimate = ExposureCalculator.maxExposure(rule: .rule500, setup: setup, declination: declination)
            XCTAssertEqual(estimate.seconds, plain.seconds, "\(declination)")
            XCTAssertEqual(estimate.declinationFactor, 1)
            XCTAssertEqual(estimate.notes.count, 1)
            XCTAssertTrue(estimate.notes[0].contains("ignored"), estimate.notes[0])
        }
    }

    func testNPFNotesCombine() {
        let estimate = ExposureCalculator.maxExposure(rule: .npf, setup: lens(), declination: 60)
        XCTAssertEqual(estimate.notes.count, 2)
        XCTAssertTrue(estimate.usedDefaultPixelPitch)
        XCTAssertEqual(estimate.seconds, (35 * 2.8 + 30 * 4.0) / 24 * 2, accuracy: 1e-9)
    }

    func testEveryLensGivesAFinitePositiveExposure() {
        let focalLengths: [Double] = [.nan, 0, 4, 24, 2000, 1e300]
        for rule in ExposureRule.allCases {
            for focalLength in focalLengths {
                let setup = lens(focalLength: focalLength, aperture: .nan)
                let estimate = ExposureCalculator.maxExposure(rule: rule, setup: setup, declination: 45)
                XCTAssertTrue(estimate.seconds.isFinite && estimate.seconds > 0, "\(rule) at \(focalLength) mm")
            }
        }
    }

    // MARK: Rule metadata

    func testExposureRuleMetadata() {
        XCTAssertEqual(ExposureRule.allCases, [.rule500, .rule400, .rule300, .npf])
        XCTAssertEqual(ExposureRule.allCases.map(\.displayName), ["500 rule", "400 rule", "300 rule", "NPF rule"])
        XCTAssertEqual(ExposureRule.allCases.map(\.id), ["rule500", "rule400", "rule300", "npf"])
        for rule in ExposureRule.allCases {
            XCTAssertFalse(rule.summary.isEmpty)
        }
    }

    func testExposureRuleCodableUsesStableRawValues() throws {
        let data = try JSONEncoder().encode(ExposureRule.allCases)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["rule500","rule400","rule300","npf"]"#)
        XCTAssertEqual(try JSONDecoder().decode([ExposureRule].self, from: data), ExposureRule.allCases)
        XCTAssertThrowsError(try JSONDecoder().decode(ExposureRule.self, from: Data(#""rule600""#.utf8)))
    }

    // MARK: Star trails

    func testSiderealRate() {
        XCTAssertEqual(ExposureCalculator.siderealRateArcsecondsPerSecond, 15.041)
        // 360 degrees in one sidereal day of 86164.0905 s.
        XCTAssertEqual(ExposureCalculator.siderealRateArcsecondsPerSecond, 360 * 3600 / 86164.0905, accuracy: 0.0001)
    }

    func testTrailLengthInArcseconds() {
        XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: 10), 150.41, accuracy: 1e-9)
        XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: 10, declination: 0), 150.41, accuracy: 1e-9)
        XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: 10, declination: 60), 75.205, accuracy: 1e-9)
        XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: 10, declination: -60), 75.205, accuracy: 1e-9)
        XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: 10, declination: 90), 0, accuracy: 1e-9)
        XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: 0), 0)
        // One sidereal day of exposure at the equator is a full circle, to the precision of the rate.
        XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: 86164.0905), 360 * 3600, accuracy: 10)
    }

    func testTrailLengthInPixels() {
        let setup = lens(focalLength: 50, aperture: 2.8, pitch: 5)
        // 150.41 arcsec at 20.6265 arcsec per pixel.
        XCTAssertEqual(
            ExposureCalculator.trailLengthPixels(exposureSeconds: 10, declination: nil, setup: setup),
            7.292083,
            accuracy: 1e-6
        )
        XCTAssertEqual(ExposureCalculator.trailLengthPixels(exposureSeconds: 10, setup: setup), 7.292083, accuracy: 1e-6)
        XCTAssertEqual(
            ExposureCalculator.trailLengthPixels(exposureSeconds: 10, declination: 60, setup: setup),
            3.646041,
            accuracy: 1e-6
        )
    }

    func testTrailLengthScalesWithFocalLengthAndPixelPitch() {
        func pixels(focalLength: Double, pitch: Double) -> Double {
            ExposureCalculator.trailLengthPixels(exposureSeconds: 8, setup: lens(focalLength: focalLength, pitch: pitch))
        }
        let base = pixels(focalLength: 50, pitch: 5)
        XCTAssertEqual(pixels(focalLength: 100, pitch: 5), base * 2, accuracy: 1e-9)
        XCTAssertEqual(pixels(focalLength: 50, pitch: 10), base / 2, accuracy: 1e-9)
    }

    func testTrailLengthAssumesTheDefaultPixelPitchWhenUnknown() {
        let unknown = ExposureCalculator.trailLengthPixels(exposureSeconds: 10, setup: lens(focalLength: 50))
        let assumed = ExposureCalculator.trailLengthPixels(
            exposureSeconds: 10,
            setup: lens(focalLength: 50, pitch: ExposureCalculator.defaultPixelPitchMicrometers)
        )
        XCTAssertEqual(unknown, assumed)
        XCTAssertEqual(unknown, 150.41 / (206.264806 * 4.0 / 50), accuracy: 1e-5)
    }

    func testTrailLengthTreatsInvalidInputAsHarmless() {
        let setup = lens(pitch: 5)
        for exposure in [-1.0, .nan, .infinity, -.infinity] {
            XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: exposure), 0, "\(exposure)")
            XCTAssertEqual(ExposureCalculator.trailLengthPixels(exposureSeconds: exposure, setup: setup), 0, "\(exposure)")
        }
        // An unusable declination counts as the equator, where trails are longest.
        let equator = ExposureCalculator.trailLengthArcseconds(exposureSeconds: 10, declination: 0)
        let equatorPixels = ExposureCalculator.trailLengthPixels(exposureSeconds: 10, declination: 0, setup: setup)
        for declination in [90.5, -91, .nan, .infinity, 1e300] {
            XCTAssertEqual(ExposureCalculator.trailLengthArcseconds(exposureSeconds: 10, declination: declination), equator, "\(declination)")
            XCTAssertEqual(
                ExposureCalculator.trailLengthPixels(exposureSeconds: 10, declination: declination, setup: setup),
                equatorPixels,
                "\(declination)"
            )
        }
    }

    func testRuleOf500TrailsSeveralPixelsOnAModernSensor() throws {
        // A sanity check on the physics: at the 500-rule limit of a 24 mm lens on a 45 MP full-frame
        // camera (4.38 um pixels) a star trails over eight pixels; NPF allows about half that.
        let pitch = try XCTUnwrap(SensorFormat.fullFrame.pixelPitchMicrometers(megapixels: 45))
        let setup = lens(focalLength: 24, pitch: pitch)
        let limit = ExposureCalculator.maxExposure(rule: .rule500, setup: setup).seconds
        let trail = ExposureCalculator.trailLengthPixels(exposureSeconds: limit, setup: setup)
        XCTAssertEqual(trail, 8.3209, accuracy: 0.0001)
        let npf = ExposureCalculator.maxExposure(rule: .npf, setup: setup).seconds
        let npfTrail = ExposureCalculator.trailLengthPixels(exposureSeconds: npf, setup: setup)
        XCTAssertEqual(npfTrail, 3.8185, accuracy: 0.0001)
        XCTAssertLessThan(npfTrail, trail)
    }
}
