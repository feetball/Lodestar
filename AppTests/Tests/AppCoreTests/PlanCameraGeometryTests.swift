import Foundation
import XCTest
@testable import AppCore

/// The optics of the delivered frames: a pinhole model with square pixels, the format's field of view across the long side.
final class PlanCameraGeometryTests: XCTestCase {
    // MARK: A 4:3 frame

    func testAFourByThreePortraitFrameHasTheShortFieldOfViewAcrossItsWidth() throws {
        // tan(45 degrees) * 3/4 = 0.75, and 2 * atan(0.75) = 73.7398 degrees (the 3-4-5 triangle).
        let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 90, width: 3000, height: 4000))
        XCTAssertEqual(geometry.portraitHorizontalFOV, 73.7397952917, accuracy: 1e-6)
        XCTAssertEqual(geometry.portraitVerticalFOV, 90, accuracy: 1e-9)
        XCTAssertEqual(geometry.imageWidth, 3000)
        XCTAssertEqual(geometry.imageHeight, 4000)
    }

    func testAFourByThreeLandscapeFrameHasTheLongFieldOfViewAcrossItsWidth() throws {
        let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 90, width: 4000, height: 3000))
        XCTAssertEqual(geometry.portraitHorizontalFOV, 90, accuracy: 1e-9)
        XCTAssertEqual(geometry.portraitVerticalFOV, 73.7397952917, accuracy: 1e-6)
        XCTAssertEqual(geometry.imageWidth, 4000)
        XCTAssertEqual(geometry.imageHeight, 3000)
    }

    func testAnOrdinaryFieldOfViewOfSixtyFiveDegrees() throws {
        let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 65, width: 3024, height: 4032))
        XCTAssertEqual(geometry.portraitHorizontalFOV, 51.0771934667, accuracy: 1e-6)
        XCTAssertEqual(geometry.portraitVerticalFOV, 65, accuracy: 1e-9)
    }

    // MARK: A 16:9 frame

    func testASixteenByNinePortraitFrame() throws {
        // 2 * atan(tan(45 degrees) * 1080 / 1920) = 2 * atan(0.5625) = 58.7155 degrees.
        let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 90, width: 1080, height: 1920))
        XCTAssertEqual(geometry.portraitHorizontalFOV, 58.7155070856, accuracy: 1e-6)
        XCTAssertEqual(geometry.portraitVerticalFOV, 90, accuracy: 1e-9)
    }

    func testASixteenByNineLandscapeFrame() throws {
        let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 90, width: 1920, height: 1080))
        XCTAssertEqual(geometry.portraitHorizontalFOV, 90, accuracy: 1e-9)
        XCTAssertEqual(geometry.portraitVerticalFOV, 58.7155070856, accuracy: 1e-6)
    }

    func testTheLongSideFieldOfViewIsKeptExactly() throws {
        let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 60, width: 1920, height: 1080))
        XCTAssertEqual(geometry.portraitHorizontalFOV, 60)
        XCTAssertEqual(geometry.portraitVerticalFOV, 35.9833977714, accuracy: 1e-6)
    }

    // MARK: Square and extreme frames

    func testASquareFrameHasTheSameFieldOfViewAcrossBothSides() throws {
        let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 60, width: 1000, height: 1000))
        XCTAssertEqual(geometry.portraitHorizontalFOV, 60, accuracy: 1e-9)
        XCTAssertEqual(geometry.portraitVerticalFOV, 60, accuracy: 1e-9)
    }

    func testAVeryNarrowFrameHasAVerySmallShortSideFieldOfView() throws {
        let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 60, width: 1, height: 10_000))
        // About 2 * atan(tan(30 degrees) / 10000) = 0.00662 degrees.
        XCTAssertGreaterThan(geometry.portraitHorizontalFOV, 0)
        XCTAssertEqual(geometry.portraitHorizontalFOV, 0.0066, accuracy: 0.0001)
        XCTAssertEqual(geometry.portraitVerticalFOV, 60, accuracy: 1e-9)
    }

    func testTheShortSideFieldOfViewNeverExceedsTheLongSideFieldOfView() throws {
        for fieldOfView in [10.0, 45.0, 90.0, 120.0, 170.0] {
            let geometry = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: fieldOfView, width: 3, height: 4))
            XCTAssertLessThan(geometry.portraitHorizontalFOV, geometry.portraitVerticalFOV)
            XCTAssertEqual(geometry.portraitVerticalFOV, fieldOfView, accuracy: 1e-9)
        }
    }

    // MARK: Unusable input

    func testNonPositiveFrameSizesAreRejected() {
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: 60, width: 0, height: 1080))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: 60, width: 1920, height: 0))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: 60, width: -1920, height: 1080))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: 60, width: 1920, height: -1080))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: 60, width: 0, height: 0))
    }

    func testFieldsOfViewOutsideZeroToOneEightyAreRejected() {
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: 0, width: 1920, height: 1080))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: -30, width: 1920, height: 1080))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: 180, width: 1920, height: 1080))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: 200, width: 1920, height: 1080))
    }

    func testFieldsOfViewThatAreNotNumbersAreRejected() {
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: .nan, width: 1920, height: 1080))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: .infinity, width: 1920, height: 1080))
        XCTAssertNil(CameraGeometry.portrait(longSideFieldOfView: -.infinity, width: 1920, height: 1080))
    }

    func testFieldsOfViewJustInsideTheLimitsAreAccepted() {
        XCTAssertNotNil(CameraGeometry.portrait(longSideFieldOfView: 179.9, width: 1920, height: 1080))
        XCTAssertNotNil(CameraGeometry.portrait(longSideFieldOfView: 0.001, width: 1920, height: 1080))
    }

    // MARK: Value semantics

    func testGeometriesWithTheSameValuesAreEqual() throws {
        let a = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 70, width: 3000, height: 4000))
        let b = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 70, width: 3000, height: 4000))
        let c = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 71, width: 3000, height: 4000))
        let d = try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 70, width: 3000, height: 4001))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    func testTheMemberwiseInitialiserKeepsItsValues() {
        let geometry = CameraGeometry(portraitHorizontalFOV: 40, portraitVerticalFOV: 55, imageWidth: 100, imageHeight: 200)
        XCTAssertEqual(geometry.portraitHorizontalFOV, 40)
        XCTAssertEqual(geometry.portraitVerticalFOV, 55)
        XCTAssertEqual(geometry.imageWidth, 100)
        XCTAssertEqual(geometry.imageHeight, 200)
    }
}
