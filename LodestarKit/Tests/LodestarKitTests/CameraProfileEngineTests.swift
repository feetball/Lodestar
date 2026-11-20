import Foundation
import XCTest
@testable import LodestarKit

// Camera profiles: lens projections, the fisheye field of view, the frame outline and the presets. Every number that
// is not a formula's own result was computed independently (Python, double precision) from the mappings named in
// LensProjection: r = f·tan θ, r = f·θ, r = 2f·sin(θ/2) and r = 2f·tan(θ/2).

private let zAxis = Vector3(0, 0, 1)

private func fieldOfViewOf(
    _ sensor: SensorFormat,
    _ focalLength: Double,
    _ projection: LensProjection,
    _ imageCircle: Double? = nil
) -> FrameSize {
    FieldOfView.of(sensor: sensor, focalLength: focalLength, projection: projection, imageCircleDiameterMillimeters: imageCircle)
}

// MARK: - Lens projections

final class LensProjectionTests: XCTestCase {

    func testRawValuesAndIdentifiers() {
        XCTAssertEqual(
            LensProjection.allCases.map(\.rawValue),
            ["rectilinear", "fisheyeEquidistant", "fisheyeEquisolid", "fisheyeStereographic"]
        )
        for projection in LensProjection.allCases {
            XCTAssertEqual(projection.id, projection.rawValue)
            XCTAssertEqual(LensProjection(rawValue: projection.rawValue), projection)
        }
        XCTAssertNil(LensProjection(rawValue: "fisheye"))
        XCTAssertNil(LensProjection(rawValue: ""))
    }

    func testDisplayNamesAreDistinctAndOnlyTheOrdinaryLensIsNotAFisheye() {
        XCTAssertEqual(Set(LensProjection.allCases.map(\.displayName)).count, LensProjection.allCases.count)
        XCTAssertEqual(LensProjection.rectilinear.displayName, "Rectilinear")
        XCTAssertFalse(LensProjection.rectilinear.isFisheye)
        for projection in LensProjection.allCases.dropFirst() { XCTAssertTrue(projection.isFisheye, projection.rawValue) }
    }

    func testForwardMappings() throws {
        // r = f·tan θ: 24 mm at 30° is 13.8564 mm.
        XCTAssertEqual(try XCTUnwrap(LensProjection.rectilinear.imageRadiusMillimeters(angleDegrees: 30, focalLength: 24)),
                       13.856406460551018, accuracy: 1e-9)
        // r = f·θ: 10 mm at 30° is 10 · π/6.
        XCTAssertEqual(try XCTUnwrap(LensProjection.fisheyeEquidistant.imageRadiusMillimeters(angleDegrees: 30, focalLength: 10)),
                       5.235987755982988, accuracy: 1e-9)
        // r = 2f·sin(θ/2): 8 mm at 90° is 16 · sin 45°, the radius of a circular fisheye's 180° image.
        XCTAssertEqual(try XCTUnwrap(LensProjection.fisheyeEquisolid.imageRadiusMillimeters(angleDegrees: 90, focalLength: 8)),
                       11.31370849898476, accuracy: 1e-9)
        // r = 2f·tan(θ/2): 10 mm at 90° is 20 mm.
        XCTAssertEqual(try XCTUnwrap(LensProjection.fisheyeStereographic.imageRadiusMillimeters(angleDegrees: 90, focalLength: 10)),
                       20, accuracy: 1e-9)
        for projection in LensProjection.allCases {
            XCTAssertEqual(try XCTUnwrap(projection.imageRadiusMillimeters(angleDegrees: 0, focalLength: 20)), 0, accuracy: 0,
                           projection.rawValue)
        }
    }

    func testTheInverseMappingUndoesTheForwardOne() throws {
        for projection in LensProjection.allCases {
            for angle in [0.0, 1, 10, 45, 80, 89] {
                let radius = try XCTUnwrap(projection.imageRadiusMillimeters(angleDegrees: angle, focalLength: 17))
                XCTAssertEqual(projection.angleDegrees(imageRadiusMillimeters: radius, focalLength: 17), angle, accuracy: 1e-9,
                               "\(projection.rawValue) at \(angle)")
            }
        }
        for projection in LensProjection.allCases.dropFirst() {
            for angle in [100.0, 135, 170] {
                let radius = try XCTUnwrap(projection.imageRadiusMillimeters(angleDegrees: angle, focalLength: 17))
                XCTAssertEqual(projection.angleDegrees(imageRadiusMillimeters: radius, focalLength: 17), angle, accuracy: 1e-9,
                               "\(projection.rawValue) at \(angle)")
            }
        }
    }

    func testAnImageDistanceBeyondTheMappingGivesHalfTurn() {
        // An equisolid lens reaches at most 2f from the centre; an equidistant one π·f.
        XCTAssertEqual(LensProjection.fisheyeEquisolid.angleDegrees(imageRadiusMillimeters: 16, focalLength: 8), 180, accuracy: 1e-9)
        XCTAssertEqual(LensProjection.fisheyeEquisolid.angleDegrees(imageRadiusMillimeters: 18, focalLength: 8), 180)
        XCTAssertEqual(LensProjection.fisheyeEquidistant.angleDegrees(imageRadiusMillimeters: 40, focalLength: 10), 180)
        XCTAssertLessThanOrEqual(LensProjection.fisheyeStereographic.angleDegrees(imageRadiusMillimeters: 1e12, focalLength: 10), 180)
        XCTAssertLessThanOrEqual(LensProjection.rectilinear.angleDegrees(imageRadiusMillimeters: 1e12, focalLength: 10), 180)
    }

    func testTheForwardMappingRefusesWhatALensCannotImage() {
        XCTAssertNil(LensProjection.rectilinear.imageRadiusMillimeters(angleDegrees: 90, focalLength: 24))
        XCTAssertNil(LensProjection.rectilinear.imageRadiusMillimeters(angleDegrees: 120, focalLength: 24))
        XCTAssertNil(LensProjection.fisheyeStereographic.imageRadiusMillimeters(angleDegrees: 180, focalLength: 10))
        XCTAssertNotNil(LensProjection.fisheyeEquisolid.imageRadiusMillimeters(angleDegrees: 180, focalLength: 10))
        for projection in LensProjection.allCases {
            XCTAssertNil(projection.imageRadiusMillimeters(angleDegrees: -1, focalLength: 10), projection.rawValue)
            XCTAssertNil(projection.imageRadiusMillimeters(angleDegrees: 181, focalLength: 10), projection.rawValue)
            XCTAssertNil(projection.imageRadiusMillimeters(angleDegrees: .nan, focalLength: 10), projection.rawValue)
            XCTAssertNil(projection.imageRadiusMillimeters(angleDegrees: 10, focalLength: 0), projection.rawValue)
            XCTAssertNil(projection.imageRadiusMillimeters(angleDegrees: 10, focalLength: .nan), projection.rawValue)
            XCTAssertNil(projection.imageRadiusMillimeters(angleDegrees: 10, focalLength: .infinity), projection.rawValue)
        }
    }

    func testTheCentreOfTheFrameIsOnTheAxis() {
        for projection in LensProjection.allCases {
            XCTAssertEqual(projection.angleDegrees(imageRadiusMillimeters: 0, focalLength: 24), 0, projection.rawValue)
        }
    }
}

// MARK: - Field of view with a projection

final class FisheyeFieldOfViewTests: XCTestCase {

    func testTheRectilinearNumbersAreUnchanged() {
        // The formula the engine used before projections existed, evaluated in the same order.
        func legacy(_ extent: Double, _ focalLength: Double) -> Double { 2 * atan(extent / (2 * focalLength)) * 180 / .pi }
        for sensor in SensorFormat.presets + [SensorFormat.custom(width: 24, height: 16)] {
            for focalLength in [4.0, 8, 14, 24, 35, 50, 85, 200, 600, 2000] {
                let frame = FieldOfView.of(sensor: sensor, focalLength: focalLength)
                XCTAssertEqual(frame.horizontal, legacy(sensor.widthMillimeters, focalLength), "\(sensor.id) \(focalLength)")
                XCTAssertEqual(frame.vertical, legacy(sensor.heightMillimeters, focalLength), "\(sensor.id) \(focalLength)")
                XCTAssertEqual(frame.diagonal, legacy(sensor.diagonalMillimeters, focalLength), "\(sensor.id) \(focalLength)")
                XCTAssertEqual(frame, fieldOfViewOf(sensor, focalLength, .rectilinear))
            }
        }
    }

    func testAnEightMillimetreEquisolidLensOnFullFrameSeesHalfTheSphereOrMore() {
        // r = 18, 12 and 21.6 mm all lie beyond the 2f = 16 mm edge of the mapping or past 90°, so the angles are capped.
        let frame = fieldOfViewOf(.fullFrame, 8, .fisheyeEquisolid)
        XCTAssertEqual(frame.horizontal, 180)
        XCTAssertEqual(frame.vertical, 180)
        XCTAssertEqual(frame.diagonal, 180)
    }

    func testAFifteenMillimetreEquisolidLensOnFullFrame() {
        // 4·asin(18/30) = 147.48°, 4·asin(12/30) = 94.31°; the diagonal 2·θ(21.63 mm) = 184.6° is capped.
        let frame = fieldOfViewOf(.fullFrame, 15, .fisheyeEquisolid)
        XCTAssertEqual(frame.horizontal, 147.479591, accuracy: 1e-6)
        XCTAssertEqual(frame.vertical, 94.312714, accuracy: 1e-6)
        XCTAssertEqual(frame.diagonal, 180)
        XCTAssertEqual(FieldOfView.horizontal(sensor: .fullFrame, focalLength: 15, projection: .fisheyeEquisolid), frame.horizontal)
        XCTAssertEqual(FieldOfView.vertical(sensor: .fullFrame, focalLength: 15, projection: .fisheyeEquisolid), frame.vertical)
        XCTAssertEqual(FieldOfView.diagonal(sensor: .fullFrame, focalLength: 15, projection: .fisheyeEquisolid), frame.diagonal)
    }

    func testATwelveMillimetreEquisolidLensSeesExactlyOneHundredTwentyDegreesVertically() {
        // 12 mm half height at f = 12: sin(θ/2) = 12/24 = 1/2, so θ = 60°.
        let frame = fieldOfViewOf(.fullFrame, 12, .fisheyeEquisolid)
        XCTAssertEqual(frame.vertical, 120, accuracy: 1e-9)
        XCTAssertEqual(frame.horizontal, 180)
    }

    func testEquidistantAndStereographicLenses() {
        let equidistant = fieldOfViewOf(.fullFrame, 20, .fisheyeEquidistant)
        XCTAssertEqual(equidistant.horizontal, 103.132403, accuracy: 1e-6)
        XCTAssertEqual(equidistant.vertical, 68.754935, accuracy: 1e-6)
        XCTAssertEqual(equidistant.diagonal, 123.949723, accuracy: 1e-6)
        let stereographic = fieldOfViewOf(.fullFrame, 10, .fisheyeStereographic)
        XCTAssertEqual(stereographic.horizontal, 167.94885, accuracy: 1e-5)
        XCTAssertEqual(stereographic.vertical, 123.855026, accuracy: 1e-6)
        XCTAssertEqual(stereographic.diagonal, 180)
    }

    func testAnImageCircleLimitsTheFrame() {
        // A 22.627 mm circle is the 180° image of an 8 mm equisolid lens: 180° every way on a sensor that is taller
        // than the circle, and on a shorter one the height only (15.6 mm: 4·asin(7.8 / 16) = 116.7°).
        let circle = 4.0 * 8.0 * sin(Double.pi / 4)
        for sensor in [SensorFormat.fullFrame, .mediumFormat44x33] {
            let frame = fieldOfViewOf(sensor, 8, .fisheyeEquisolid, circle)
            XCTAssertEqual(frame.horizontal, 180, accuracy: 1e-9, sensor.id)
            XCTAssertEqual(frame.vertical, 180, accuracy: 1e-9, sensor.id)
            XCTAssertEqual(frame.diagonal, 180, accuracy: 1e-9, sensor.id)
        }
        let apsC = fieldOfViewOf(.apsC, 8, .fisheyeEquisolid, circle)
        XCTAssertEqual(apsC.horizontal, 180, accuracy: 1e-9)
        XCTAssertEqual(apsC.vertical, 116.7, accuracy: 0.05)
        XCTAssertEqual(apsC.diagonal, 180, accuracy: 1e-9)
        // A 12 mm circle sees 4·asin(6/16) = 88.097° in every direction.
        let small = fieldOfViewOf(.fullFrame, 8, .fisheyeEquisolid, 12)
        XCTAssertEqual(small.horizontal, 88.097251, accuracy: 1e-6)
        XCTAssertEqual(small.vertical, 88.097251, accuracy: 1e-6)
        XCTAssertEqual(small.diagonal, 88.097251, accuracy: 1e-6)
    }

    func testAnImageCircleBetweenTheSidesOnlyLimitsTheLongerOnes() {
        // 30 mm on a 36 × 24 mm sensor: the width and diagonal reach the circle, the height does not.
        let frame = fieldOfViewOf(.fullFrame, 15, .fisheyeEquisolid, 30)
        XCTAssertEqual(frame.horizontal, 120, accuracy: 1e-9)
        XCTAssertEqual(frame.vertical, 94.312714, accuracy: 1e-6)
        XCTAssertEqual(frame.diagonal, 120, accuracy: 1e-9)
    }

    func testAnImageCircleLargerThanTheSensorChangesNothing() {
        for projection in LensProjection.allCases {
            let plain = fieldOfViewOf(.fullFrame, 24, projection)
            XCTAssertEqual(fieldOfViewOf(.fullFrame, 24, projection, 60), plain, projection.rawValue)
            XCTAssertEqual(fieldOfViewOf(.fullFrame, 24, projection, SensorFormat.fullFrame.diagonalMillimeters), plain)
        }
    }

    func testAnUnusableImageCircleIsIgnored() {
        let plain = fieldOfViewOf(.fullFrame, 15, .fisheyeEquisolid)
        for circle in [0.0, -5, .nan, .infinity, -.infinity] {
            XCTAssertEqual(fieldOfViewOf(.fullFrame, 15, .fisheyeEquisolid, circle), plain, "\(circle)")
        }
    }

    func testNoAngleExceedsHalfAGreatCircle() {
        for projection in LensProjection.allCases {
            for focalLength in [1e-9, 0.5, 4, 8, 15, 50, 1e6] {
                let frame = fieldOfViewOf(.mediumFormat44x33, focalLength, projection)
                for angle in [frame.horizontal, frame.vertical, frame.diagonal] {
                    XCTAssertTrue(angle.isFinite && angle >= 0 && angle <= 180, "\(angle) \(projection.rawValue) at \(focalLength) mm")
                }
            }
        }
    }

    func testAShorterFocalLengthSeesMoreThroughEveryProjection() {
        for projection in LensProjection.allCases {
            var previous = 0.0
            for focalLength in [200.0, 100, 50, 28, 20, 14, 10] {
                let horizontal = FieldOfView.horizontal(sensor: .fullFrame, focalLength: focalLength, projection: projection)
                XCTAssertGreaterThan(horizontal, previous, "\(projection.rawValue) at \(focalLength) mm")
                previous = horizontal
            }
        }
    }

    func testALensSetupReportsTheFieldOfViewOfItsProjectionAndImageCircle() {
        let fisheye = LensSetup(
            sensor: .fullFrame, focalLengthMillimeters: 15, aperture: 2.8, pixelPitchMicrometers: nil,
            projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: 30
        )
        XCTAssertEqual(fisheye.fieldOfView, fieldOfViewOf(.fullFrame, 15, .fisheyeEquisolid, 30))
        let ordinary = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 15, aperture: 2.8)
        XCTAssertEqual(ordinary.fieldOfView, FieldOfView.of(sensor: .fullFrame, focalLength: 15))
        XCTAssertGreaterThan(fisheye.fieldOfView.horizontal, ordinary.fieldOfView.horizontal)
    }
}

// MARK: - Lens setups with a projection

final class LensSetupProjectionTests: XCTestCase {

    private let fullFrameJSON = #"{"id":"fullFrame","name":"Full Frame","widthMillimeters":36.0,"heightMillimeters":24.0}"#

    private func keys(_ setup: LensSetup) throws -> Set<String> {
        let data = try JSONEncoder().encode(setup)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    private func decode(_ document: String) throws -> LensSetup {
        try JSONDecoder().decode(LensSetup.self, from: Data(document.utf8))
    }

    func testASetupIsRectilinearWithoutAnImageCircleByDefault() throws {
        let setup = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8)
        XCTAssertEqual(setup.projection, .rectilinear)
        XCTAssertNil(setup.imageCircleDiameterMillimeters)
        XCTAssertEqual(try XCTUnwrap(LensSetup.validated(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8)), setup)
    }

    func testTheProjectionAndTheImageCircleAreKept() throws {
        let setup = LensSetup(
            sensor: .fullFrame, focalLengthMillimeters: 8, aperture: 3.5, pixelPitchMicrometers: 5.9,
            projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: 22.6
        )
        XCTAssertEqual(setup.projection, .fisheyeEquisolid)
        XCTAssertEqual(setup.imageCircleDiameterMillimeters, 22.6)
        XCTAssertEqual(
            LensSetup.validated(
                sensor: .fullFrame, focalLengthMillimeters: 8, aperture: 3.5, pixelPitchMicrometers: 5.9,
                projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: 22.6
            ),
            setup
        )
        XCTAssertNotEqual(setup, LensSetup(sensor: .fullFrame, focalLengthMillimeters: 8, aperture: 3.5, pixelPitchMicrometers: 5.9))
    }

    func testAnImageCircleOutsideTheRangeIsDroppedOrRejected() {
        for circle in [0.0, 0.5, 201, -3, .nan, .infinity] {
            let limited = LensSetup(
                sensor: .fullFrame, focalLengthMillimeters: 8, aperture: 3.5,
                projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: circle
            )
            XCTAssertNil(limited.imageCircleDiameterMillimeters, "\(circle)")
            XCTAssertEqual(limited.projection, .fisheyeEquisolid)
            XCTAssertNil(
                LensSetup.validated(
                    sensor: .fullFrame, focalLengthMillimeters: 8, aperture: 3.5,
                    projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: circle
                ),
                "\(circle)"
            )
        }
        XCTAssertEqual(LensSetup.imageCircleRange, 1...200)
    }

    func testTheJSONOfAnOrdinaryLensIsUnchanged() throws {
        XCTAssertEqual(
            try keys(LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8)),
            ["sensor", "focalLengthMillimeters", "aperture"]
        )
        XCTAssertEqual(
            try keys(LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8, pixelPitchMicrometers: 5.9)),
            ["sensor", "focalLengthMillimeters", "aperture", "pixelPitchMicrometers"]
        )
    }

    func testAFisheyeWritesItsProjectionAndImageCircleAndReadsThemBack() throws {
        let setup = LensSetup(
            sensor: .fullFrame, focalLengthMillimeters: 8, aperture: 3.5, pixelPitchMicrometers: 5.9,
            projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: 22.6
        )
        XCTAssertEqual(
            try keys(setup),
            ["sensor", "focalLengthMillimeters", "aperture", "pixelPitchMicrometers", "projection", "imageCircleDiameterMillimeters"]
        )
        XCTAssertEqual(try JSONDecoder().decode(LensSetup.self, from: JSONEncoder().encode(setup)), setup)
        for projection in LensProjection.allCases {
            let plain = LensSetup(sensor: .apsC, focalLengthMillimeters: 10, aperture: 2.8, projection: projection)
            XCTAssertEqual(try JSONDecoder().decode(LensSetup.self, from: JSONEncoder().encode(plain)), plain, projection.rawValue)
        }
    }

    func testAMissingOrNullProjectionAndImageCircleReadAsTheDefaults() throws {
        let missing = try decode(#"{"sensor":\#(fullFrameJSON),"focalLengthMillimeters":24,"aperture":2.8}"#)
        XCTAssertEqual(missing, LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8))
        let nulls = try decode(
            #"{"sensor":\#(fullFrameJSON),"focalLengthMillimeters":24,"aperture":2.8,"projection":null,"imageCircleDiameterMillimeters":null}"#
        )
        XCTAssertEqual(nulls, missing)
    }

    func testAnUnknownProjectionOrAnImageCircleOutsideTheRangeIsRejected() {
        let head = #"{"sensor":\#(fullFrameJSON),"focalLengthMillimeters":24,"aperture":2.8"#
        for tail in [
            #","projection":"cylindrical"}"#,
            #","projection":""}"#,
            #","projection":3}"#,
            #","imageCircleDiameterMillimeters":0}"#,
            #","imageCircleDiameterMillimeters":500}"#,
            #","imageCircleDiameterMillimeters":"22"}"#,
        ] {
            XCTAssertThrowsError(try decode(head + tail), tail)
        }
    }
}

// MARK: - The frame outline

final class CameraFrameOutlineTests: XCTestCase {

    /// The border the engine drew before projections existed: tangents of the half angles, as the apps used it.
    private func legacyOutline(_ setup: LensSetup, _ samplesPerEdge: Int) -> [Vector3] {
        let frame = setup.fieldOfView
        let halfWidth = AstroMath.tanDeg(frame.horizontal / 2)
        let halfHeight = AstroMath.tanDeg(frame.vertical / 2)
        let cornerRight = [-1.0, 1.0, 1.0, -1.0]
        let cornerUp = [1.0, 1.0, -1.0, -1.0]
        var outline: [Vector3] = []
        for edge in 0..<4 {
            let next = (edge + 1) % 4
            for step in 0..<samplesPerEdge {
                let t = Double(step) / Double(samplesPerEdge)
                let right = (cornerRight[edge] + (cornerRight[next] - cornerRight[edge]) * t) * halfWidth
                let up = (cornerUp[edge] + (cornerUp[next] - cornerUp[edge]) * t) * halfHeight
                outline.append(Vector3(right, up, 1).normalized)
            }
        }
        return outline
    }

    private func assertSameDirections(_ expected: [Vector3], _ actual: [Vector3], accuracy: Double, _ message: String) {
        XCTAssertEqual(expected.count, actual.count, message)
        guard expected.count == actual.count else { return }
        for index in expected.indices {
            XCTAssertEqual(expected[index].x, actual[index].x, accuracy: accuracy, "\(message) x[\(index)]")
            XCTAssertEqual(expected[index].y, actual[index].y, accuracy: accuracy, "\(message) y[\(index)]")
            XCTAssertEqual(expected[index].z, actual[index].z, accuracy: accuracy, "\(message) z[\(index)]")
        }
    }

    private func angle(_ direction: Vector3) -> Double { direction.angle(to: zAxis) }

    func testARectilinearFrameIsTheOutlineOfBefore() {
        for sensor in [SensorFormat.fullFrame, .apsC, .microFourThirds] {
            for focalLength in [14.0, 24, 85, 400] {
                for samples in [1, 4, 8] {
                    let setup = LensSetup(sensor: sensor, focalLengthMillimeters: focalLength, aperture: 2.8)
                    assertSameDirections(
                        legacyOutline(setup, samples), CameraFrameOutline.directions(setup: setup, samplesPerEdge: samples),
                        accuracy: 1e-12, "\(sensor.id) \(focalLength) mm, \(samples) samples"
                    )
                }
            }
        }
    }

    func testTheOutlineHasFourTimesTheSamplesOfUnitVectors() {
        for projection in LensProjection.allCases {
            for samples in [1, 2, 4, 7] {
                let setup = LensSetup(sensor: .apsC, focalLengthMillimeters: 12, aperture: 2.8, projection: projection)
                let outline = CameraFrameOutline.directions(setup: setup, samplesPerEdge: samples)
                XCTAssertEqual(outline.count, 4 * samples, projection.rawValue)
                for direction in outline {
                    XCTAssertTrue(direction.isFinite, projection.rawValue)
                    XCTAssertEqual(direction.length, 1, accuracy: 1e-12, projection.rawValue)
                }
            }
        }
    }

    func testTheOutlineStartsAtTheTopLeftAndRunsClockwise() {
        let setup = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8)
        let outline = CameraFrameOutline.directions(setup: setup, samplesPerEdge: 4)
        // Top-left corner, then along the top edge to the right.
        XCTAssertTrue(outline[0].x < 0 && outline[0].y > 0)
        XCTAssertEqual(outline[0].x, -outline[4].x, accuracy: 1e-12)
        XCTAssertEqual(outline[0].y, outline[4].y, accuracy: 1e-12)
        for step in 0..<3 { XCTAssertLessThan(outline[step].x, outline[step + 1].x) }
        XCTAssertEqual(outline[2].x, 0, accuracy: 1e-12)
        XCTAssertTrue(outline[8].x > 0 && outline[8].y < 0)
        XCTAssertTrue(outline[12].x < 0 && outline[12].y < 0)
    }

    func testTheOutlineIsSymmetricAboutTheAxis() {
        // A half turn about the axis maps the point at index i to the one at i + half the count.
        for projection in LensProjection.allCases {
            for circle in [nil, 14.0, 30.0] as [Double?] {
                for samples in [1, 3, 4, 8] {
                    let setup = LensSetup(
                        sensor: .fullFrame, focalLengthMillimeters: 15, aperture: 2.8,
                        projection: projection, imageCircleDiameterMillimeters: circle
                    )
                    let outline = CameraFrameOutline.directions(setup: setup, samplesPerEdge: samples)
                    let half = outline.count / 2
                    for index in 0..<half {
                        let a = outline[index]
                        let b = outline[index + half]
                        let message = "\(projection.rawValue) circle \(String(describing: circle)), \(samples) samples, point \(index)"
                        XCTAssertEqual(b.x, -a.x, accuracy: 1e-12, message)
                        XCTAssertEqual(b.y, -a.y, accuracy: 1e-12, message)
                        XCTAssertEqual(b.z, a.z, accuracy: 1e-12, message)
                    }
                    XCTAssertEqual(outline.reduce(0) { $0 + $1.x }, 0, accuracy: 1e-9)
                    XCTAssertEqual(outline.reduce(0) { $0 + $1.y }, 0, accuracy: 1e-9)
                }
            }
        }
    }

    func testTheCornersOfAFisheyeFrameLieAtTheAngleOfTheirImageDistance() {
        let setup = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 15, aperture: 2.8, projection: .fisheyeEquisolid)
        let outline = CameraFrameOutline.directions(setup: setup, samplesPerEdge: 4)
        // The corner is 21.633 mm from the centre: 2·asin(21.633 / 30) = 92.29° from the axis, behind the sensor's plane.
        XCTAssertEqual(angle(outline[0]), 92.292443, accuracy: 1e-6)
        XCTAssertLessThan(outline[0].z, 0)
        // The middle of the top edge is 12 mm out: 2·asin(12 / 30) = 47.16°; the middle of the right edge, 18 mm: 73.74°.
        XCTAssertEqual(angle(outline[2]), 47.156357, accuracy: 1e-6)
        XCTAssertEqual(angle(outline[6]), 73.739795, accuracy: 1e-6)
        XCTAssertEqual(outline[2].y, sin(47.156357 * Double.pi / 180), accuracy: 1e-6)
        XCTAssertEqual(outline[2].x, 0, accuracy: 1e-12)
    }

    func testACircularFisheyeFrameIsAnEvenCircle() {
        // The 180° image of an 8 mm equisolid lens: every point is 90° from the axis, evenly spaced.
        let diameter = 4.0 * 8.0 * sin(Double.pi / 4)
        let setup = LensSetup(
            sensor: .fullFrame, focalLengthMillimeters: 8, aperture: 3.5,
            projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: diameter
        )
        let outline = CameraFrameOutline.directions(setup: setup, samplesPerEdge: 4)
        XCTAssertEqual(outline.count, 16)
        for direction in outline { XCTAssertEqual(angle(direction), 90, accuracy: 1e-6) }
        // Starts 45° anticlockwise from the top and turns clockwise by 22.5° a point.
        XCTAssertTrue(outline[0].x < 0 && outline[0].y > 0)
        XCTAssertEqual(outline[0].x, -sin(Double.pi / 4), accuracy: 1e-12)
        XCTAssertEqual(outline[2].x, 0, accuracy: 1e-12)
        XCTAssertEqual(outline[2].y, 1, accuracy: 1e-12)
        for index in outline.indices {
            let next = outline[(index + 1) % outline.count]
            XCTAssertEqual(outline[index].angle(to: next), 22.5, accuracy: 1e-6, "step \(index)")
        }
    }

    func testACircleThatOnlyTrimsTheCornersMovesThemOntoTheCircle() {
        // 30 mm on a 36 × 24 mm sensor: 15 mm radius, 2·asin(15 / 30) = 60° from the axis.
        let setup = LensSetup(
            sensor: .fullFrame, focalLengthMillimeters: 15, aperture: 2.8,
            projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: 30
        )
        let outline = CameraFrameOutline.directions(setup: setup, samplesPerEdge: 4)
        XCTAssertEqual(angle(outline[0]), 60, accuracy: 1e-6)
        XCTAssertEqual(angle(outline[1]), 60, accuracy: 1e-6)
        XCTAssertEqual(angle(outline[2]), 47.156357, accuracy: 1e-6)
        XCTAssertEqual(angle(outline[3]), 60, accuracy: 1e-6)
        // The right edge lies beyond the circle too, so it is trimmed to it as well.
        XCTAssertEqual(angle(outline[5]), 60, accuracy: 1e-6)
        XCTAssertEqual(angle(outline[6]), 60, accuracy: 1e-6)
    }

    func testTooFewOrTooManySamplesAreHandled() {
        let setup = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8)
        XCTAssertTrue(CameraFrameOutline.directions(setup: setup, samplesPerEdge: 0).isEmpty)
        XCTAssertTrue(CameraFrameOutline.directions(setup: setup, samplesPerEdge: -3).isEmpty)
        XCTAssertEqual(CameraFrameOutline.directions(setup: setup, samplesPerEdge: 100_000).count,
                       4 * CameraFrameOutline.maximumSamplesPerEdge)
        XCTAssertEqual(CameraFrameOutline.maximumSamplesPerEdge, 1000)
    }

    func testTheMiddleOfTheTopEdge() {
        let ordinary = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8)
        let top = CameraFrameOutline.topMiddle(setup: ordinary)
        XCTAssertEqual(top.x, 0, accuracy: 1e-12)
        XCTAssertEqual(angle(top), ordinary.fieldOfView.vertical / 2, accuracy: 1e-9)
        assertSameDirections([CameraFrameOutline.directions(setup: ordinary, samplesPerEdge: 4)[2]], [top], accuracy: 1e-12, "rectilinear")

        let fisheye = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 15, aperture: 2.8, projection: .fisheyeEquisolid)
        XCTAssertEqual(angle(CameraFrameOutline.topMiddle(setup: fisheye)), 47.156357, accuracy: 1e-6)
        assertSameDirections([CameraFrameOutline.directions(setup: fisheye, samplesPerEdge: 4)[2]],
                             [CameraFrameOutline.topMiddle(setup: fisheye)], accuracy: 1e-12, "fisheye")

        // The top of a circle smaller than the frame is the top of the circle.
        let circular = LensSetup(
            sensor: .fullFrame, focalLengthMillimeters: 8, aperture: 3.5,
            projection: .fisheyeEquisolid, imageCircleDiameterMillimeters: 12
        )
        XCTAssertEqual(angle(CameraFrameOutline.topMiddle(setup: circular)), 44.048626, accuracy: 1e-6)
        XCTAssertGreaterThan(CameraFrameOutline.topMiddle(setup: circular).y, 0)
    }

    func testEveryPresetAndProjectionGivesFiniteUnitVectors() {
        for preset in CameraPreset.all {
            for projection in LensProjection.allCases {
                let setup = LensSetup(
                    sensor: preset.sensor, focalLengthMillimeters: preset.focalLengthMillimeters,
                    aperture: preset.aperture, projection: projection
                )
                for direction in CameraFrameOutline.directions(setup: setup, samplesPerEdge: 8) + [CameraFrameOutline.topMiddle(setup: setup)] {
                    XCTAssertTrue(direction.isFinite, "\(preset.id) \(projection.rawValue)")
                    XCTAssertEqual(direction.length, 1, accuracy: 1e-12, "\(preset.id) \(projection.rawValue)")
                }
            }
        }
    }

    func testTheOutlineOfARectilinearFrameStaysInFrontOfTheCamera() {
        let setup = LensSetup(sensor: .mediumFormat44x33, focalLengthMillimeters: 4, aperture: 2.8)
        XCTAssertLessThan(setup.fieldOfView.diagonal, 180)
        for direction in CameraFrameOutline.directions(setup: setup, samplesPerEdge: 6) { XCTAssertGreaterThan(direction.z, 0) }
    }
}

// MARK: - Presets

final class CameraPresetTests: XCTestCase {

    /// The vendor's published field of view in degrees: the number, what it measures and how far ours may be off.
    private struct Published {
        let degrees: Double
        let across: String
        let tolerance: Double
    }

    func testPresetsAreListedInPickerOrderWithDistinctIdentifiersAndNames() {
        XCTAssertEqual(
            CameraPreset.all.map(\.id),
            ["fullFrame24", "seestarS50", "seestarS30", "seestarS50Pro", "seestarS30Pro", "dwarf3Tele", "dwarf3Wide",
             "dwarf2Tele", "vesperaII"]
        )
        XCTAssertEqual(CameraPreset.all.first, CameraPreset.fullFrame24)
        XCTAssertEqual(CameraPreset.smartTelescopes, Array(CameraPreset.all.dropFirst()))
        XCTAssertEqual(Set(CameraPreset.all.map(\.name)).count, CameraPreset.all.count)
        XCTAssertTrue(CameraPreset.all.allSatisfy { !$0.name.isEmpty && $0.name.count <= 40 })
    }

    func testTheStarterIsAFullFrame24MillimetreF28Lens() {
        let preset = CameraPreset.fullFrame24
        XCTAssertEqual(preset.name, "Full-frame 24 mm f/2.8")
        XCTAssertEqual(preset.setup, LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8))
        XCTAssertNil(preset.pixelPitchMicrometers)
        XCTAssertEqual(preset.projection, .rectilinear)
    }

    func testASmartTelescopeSensorIsItsPixelCountTimesItsPixelPitch() throws {
        // 1920 × 1080 pixels of 2.9 µm.
        let seestar = CameraPreset.seestarS50
        XCTAssertEqual(seestar.sensor.widthMillimeters, 5.568, accuracy: 1e-9)
        XCTAssertEqual(seestar.sensor.heightMillimeters, 3.132, accuracy: 1e-9)
        XCTAssertEqual(seestar.pixelPitchMicrometers, 2.9)
        XCTAssertEqual(seestar.focalLengthMillimeters, 250)
        XCTAssertEqual(seestar.aperture, 5)
        // 3840 × 2160 pixels of 2 µm.
        XCTAssertEqual(CameraPreset.dwarf3Tele.sensor.widthMillimeters, 7.68, accuracy: 1e-9)
        XCTAssertEqual(CameraPreset.dwarf3Tele.sensor.heightMillimeters, 4.32, accuracy: 1e-9)
        // The image scale follows from the pitch and the focal length: 2.9 µm at 250 mm is 2.39 arcseconds a pixel.
        XCTAssertEqual(try XCTUnwrap(CameraPreset.vesperaII.setup.imageScaleArcsecondsPerPixel), 2.39, accuracy: 0.005)
    }

    func testEveryPresetIsAValidSetupThatKeepsItsValues() {
        for preset in CameraPreset.all {
            let setup = preset.setup
            XCTAssertEqual(setup.sensor, preset.sensor, preset.id)
            XCTAssertEqual(setup.focalLengthMillimeters, preset.focalLengthMillimeters, preset.id)
            XCTAssertEqual(setup.aperture, preset.aperture, preset.id)
            XCTAssertEqual(setup.pixelPitchMicrometers, preset.pixelPitchMicrometers, preset.id)
            XCTAssertEqual(setup.projection, preset.projection, preset.id)
            XCTAssertNil(setup.imageCircleDiameterMillimeters, preset.id)
            XCTAssertNotNil(
                LensSetup.validated(
                    sensor: preset.sensor, focalLengthMillimeters: preset.focalLengthMillimeters,
                    aperture: preset.aperture, pixelPitchMicrometers: preset.pixelPitchMicrometers
                ),
                preset.id
            )
        }
    }

    func testTheFieldOfViewIsWhatTheVendorPublishes() throws {
        // Published values are rounded and nominal, so each has a tolerance that covers that; "long" and "short" are
        // the longer and shorter side of the frame, "diagonal" the corner to corner angle.
        let published: [String: [Published]] = [
            // https://www.seestar.com/products/seestar-s50: 0.73° × 1.29°.
            "seestarS50": [Published(degrees: 1.29, across: "long", tolerance: 0.02),
                           Published(degrees: 0.73, across: "short", tolerance: 0.02)],
            // https://www.seestar.com/products/seestar-s30-all-in-one-smart-telescope: 2.46°.
            "seestarS30": [Published(degrees: 2.46, across: "diagonal", tolerance: 0.03)],
            // https://www.seestar.com/products/seestar-s50-pro-smart-telescope: 2.8°.
            "seestarS50Pro": [Published(degrees: 2.8, across: "diagonal", tolerance: 0.03)],
            // https://www.seestar.com/products/seestar-s30-pro: 4.6°.
            "seestarS30Pro": [Published(degrees: 4.6, across: "diagonal", tolerance: 0.05)],
            // https://dwarflab.com/products/dwarf-3-smart-telescope: D 3.38° and D 50.6°.
            "dwarf3Tele": [Published(degrees: 3.38, across: "diagonal", tolerance: 0.03)],
            "dwarf3Wide": [Published(degrees: 50.6, across: "diagonal", tolerance: 0.5)],
            // https://dwarflab.com/products/dwarf-2-smart-telescope: D 3.72°.
            "dwarf2Tele": [Published(degrees: 3.72, across: "diagonal", tolerance: 0.1)],
            // https://vaonis.com/products/vespera-2: 2.5° × 1.4°.
            "vesperaII": [Published(degrees: 2.5, across: "long", tolerance: 0.1),
                          Published(degrees: 1.4, across: "short", tolerance: 0.1)],
        ]
        XCTAssertEqual(Set(CameraPreset.smartTelescopes.map(\.id)), Set(published.keys))
        for preset in CameraPreset.smartTelescopes {
            let frame = preset.setup.fieldOfView
            for value in try XCTUnwrap(published[preset.id]) {
                let computed: Double
                switch value.across {
                case "long": computed = frame.longSide
                case "short": computed = frame.shortSide
                default: computed = frame.diagonal
                }
                XCTAssertEqual(computed, value.degrees, accuracy: value.tolerance, "\(preset.id) \(value.across)")
            }
        }
    }

    func testFieldOfViewNumbersOfThePresets() throws {
        // Our own numbers, to the precision of the arithmetic.
        let expected: [String: (Double, Double, Double)] = [
            "seestarS50": (1.2760, 0.7178, 1.4640),
            "seestarS30": (2.1266, 1.1963, 2.4398),
            "seestarS50Pro": (2.4536, 1.3803, 2.8150),
            "seestarS30Pro": (3.9862, 2.2428, 4.5729),
            "dwarf3Tele": (2.9329, 1.6500, 3.3648),
            "dwarf3Wide": (45.1280, 26.3113, 50.9788),
            "dwarf2Tele": (3.1894, 1.7944, 3.6591),
            "vesperaII": (2.5518, 1.4355, 2.9276),
        ]
        for preset in CameraPreset.smartTelescopes {
            let frame = preset.setup.fieldOfView
            let (horizontal, vertical, diagonal) = try XCTUnwrap(expected[preset.id])
            XCTAssertEqual(frame.horizontal, horizontal, accuracy: 1e-4, preset.id)
            XCTAssertEqual(frame.vertical, vertical, accuracy: 1e-4, preset.id)
            XCTAssertEqual(frame.diagonal, diagonal, accuracy: 1e-4, preset.id)
        }
        XCTAssertFalse(CameraPreset.smartTelescopes.contains { $0.projection.isFisheye })
    }
}

// MARK: - Photo metadata

final class CameraPhotoMetadataTests: XCTestCase {

    private func metadata(
        _ model: String? = nil,
        _ focalLength: Double? = nil,
        _ equivalent: Double? = nil,
        _ aperture: Double? = nil,
        _ width: Int? = nil,
        _ height: Int? = nil
    ) -> CameraPhotoMetadata {
        CameraPhotoMetadata(
            cameraModel: model, focalLengthMillimeters: focalLength, focalLength35mmEquivalent: equivalent,
            aperture: aperture, pixelWidth: width, pixelHeight: height
        )
    }

    func testAFullFrameCameraGivesTheFullFrameSensorAndItsPixelPitch() throws {
        let suggestion = try XCTUnwrap(metadata("NIKON D850", 24, 24, 2.8, 8256, 5504).suggestion())
        XCTAssertEqual(suggestion.name, "NIKON D850")
        XCTAssertEqual(suggestion.sensor, .fullFrame)
        XCTAssertEqual(try XCTUnwrap(suggestion.cropFactor), 1, accuracy: 1e-12)
        XCTAssertEqual(suggestion.focalLengthMillimeters, 24)
        XCTAssertEqual(suggestion.aperture, 2.8)
        // 36 mm over 8256 pixels.
        XCTAssertEqual(try XCTUnwrap(suggestion.pixelPitchMicrometers), 4.3605, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(suggestion.megapixels), 45.441024, accuracy: 1e-6)
    }

    func testTheNearestPresetIsChosenByCropFactor() {
        // 16 mm that frames like 24 mm: crop 1.5, Nikon-style APS-C (1.534), not Canon's (1.613).
        XCTAssertEqual(metadata(nil, 16, 24, nil, 6000, 4000).suggestion()?.sensor, .apsC)
        // 18 mm that frames like 29 mm: crop 1.611, Canon APS-C.
        XCTAssertEqual(metadata(nil, 18, 29, nil, 6000, 4000).suggestion()?.sensor, .apsCCanon)
        XCTAssertEqual(metadata(nil, 12, 24, nil, 5184, 3888).suggestion()?.sensor, .microFourThirds)
        XCTAssertEqual(metadata(nil, 9, 24, nil, 5472, 3648).suggestion()?.sensor, .oneInch)
        XCTAssertEqual(metadata(nil, 50, 40, nil, 8256, 6192).suggestion()?.sensor, .mediumFormat44x33)
    }

    func testThePixelPitchFollowsFromTheSensorAndThePictureSize() throws {
        XCTAssertEqual(try XCTUnwrap(metadata(nil, 16, 24, nil, 6000, 4000).suggestion()?.pixelPitchMicrometers), 3.9167, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(metadata(nil, 18, 29, nil, 6000, 4000).suggestion()?.pixelPitchMicrometers), 3.7167, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(metadata(nil, 12, 24, nil, 5184, 3888).suggestion()?.pixelPitchMicrometers), 3.3372, accuracy: 1e-4)
    }

    func testAPictureTurnedToPortraitGivesTheSameSuggestion() {
        let landscape = metadata("NIKON D850", 24, 24, 2.8, 8256, 5504).suggestion()
        let portrait = metadata("NIKON D850", 24, 24, 2.8, 5504, 8256).suggestion()
        XCTAssertEqual(landscape, portrait)
    }

    func testACropFactorThatMatchesNoPresetMakesACustomSensorWithThePictureShape() throws {
        // A phone: 6.9 mm that frames like 24 mm, crop 3.478; 12.44 mm diagonal at 4:3.
        let suggestion = try XCTUnwrap(metadata("Pixel", 6.9, 24, 1.7, 4000, 3000).suggestion())
        let sensor = try XCTUnwrap(suggestion.sensor)
        XCTAssertEqual(sensor.widthMillimeters, 9.9513, accuracy: 1e-4)
        XCTAssertEqual(sensor.heightMillimeters, 7.4635, accuracy: 1e-4)
        XCTAssertEqual(sensor.diagonalMillimeters, 12.4392, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(suggestion.pixelPitchMicrometers), 2.4878, accuracy: 1e-4)
        // Without the picture size the shape is 3:2 and no pixel pitch can be estimated.
        let unsized = try XCTUnwrap(metadata(nil, 6.9, 24, nil).suggestion())
        XCTAssertEqual(try XCTUnwrap(unsized.sensor).widthMillimeters, 10.35, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(unsized.sensor).heightMillimeters, 6.9, accuracy: 1e-9)
        XCTAssertNil(unsized.pixelPitchMicrometers)
        XCTAssertNil(unsized.megapixels)
    }

    func testWithoutAnEquivalentFocalLengthThereIsNoSensor() throws {
        let suggestion = try XCTUnwrap(metadata("Camera", 35, nil, 1.8, 6000, 4000).suggestion())
        XCTAssertNil(suggestion.sensor)
        XCTAssertNil(suggestion.cropFactor)
        XCTAssertNil(suggestion.pixelPitchMicrometers)
        XCTAssertEqual(suggestion.focalLengthMillimeters, 35)
        XCTAssertEqual(try XCTUnwrap(suggestion.megapixels), 24, accuracy: 1e-9)
    }

    func testAPhotoWithoutAUsableFocalLengthSuggestsNothing() {
        XCTAssertNil(metadata("Camera", nil, 35, 1.8, 6000, 4000).suggestion())
        for focalLength in [0.0, -24, 2, 5000, .nan, .infinity] {
            XCTAssertNil(metadata("Camera", focalLength, 35, 1.8, 6000, 4000).suggestion(), "\(focalLength)")
        }
    }

    func testValuesOutsideTheirRangesAreIgnoredNotCorrected() {
        for aperture in [0.5, 100, .nan, -2.8] {
            XCTAssertNil(metadata(nil, 24, 24, aperture).suggestion()?.aperture, "\(aperture)")
        }
        // A crop factor of 20 or 0.1 is not believed.
        XCTAssertNil(metadata(nil, 24, 480).suggestion()?.cropFactor)
        XCTAssertNil(metadata(nil, 24, 2.4).suggestion()?.cropFactor)
        XCTAssertNil(metadata(nil, 24, 24, nil, 0, 4000).suggestion()?.pixelPitchMicrometers)
        XCTAssertNil(metadata(nil, 24, 24, nil, 6000, -4000).suggestion()?.pixelPitchMicrometers)
        XCTAssertNil(metadata(nil, 24, 24, nil, 6000, 200_000).suggestion()?.pixelPitchMicrometers)
        // 36 mm over 20 pixels would be 1800 µm a pixel.
        XCTAssertNil(metadata(nil, 24, 24, nil, 20, 10).suggestion()?.pixelPitchMicrometers)
        for equivalent in [0.0, -35, .nan, .infinity] {
            XCTAssertNil(metadata(nil, 24, equivalent).suggestion()?.sensor, "\(equivalent)")
        }
    }

    func testTheModelNameIsCleanedAndCut() {
        XCTAssertEqual(metadata("  NIKON\u{0000} D850 \n", 24, 24).suggestion()?.name, "NIKON D850")
        XCTAssertNil(metadata("", 24, 24).suggestion()?.name)
        XCTAssertNil(metadata("  \t ", 24, 24).suggestion()?.name)
        XCTAssertNil(metadata(nil, 24, 24).suggestion()?.name)
        let long = String(repeating: "A", count: 60)
        XCTAssertEqual(metadata(long, 24, 24).suggestion()?.name, String(repeating: "A", count: CameraPhotoMetadata.maximumNameLength))
        XCTAssertEqual(CameraPhotoMetadata.maximumNameLength, 40)
    }
}
