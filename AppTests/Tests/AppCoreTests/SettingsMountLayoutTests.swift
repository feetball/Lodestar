import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `MountLayout`: how a mount's geometry is classified for its picture, and the sentence that describes it.
final class SettingsMountLayoutTests: XCTestCase {
    /// The turn of a back-camera layout, or nil for any other layout.
    private func rotation(of profile: MountProfile) -> Double? {
        if case let .backCamera(rotation) = MountLayout(profile) { return rotation }
        return nil
    }

    private func degrees(_ value: Double) -> Double { value * Double.pi / 180 }

    // MARK: The built-in presets

    func testThePortraitPresetIsUprightOnTheBackOfTheCamera() throws {
        let turn = try XCTUnwrap(rotation(of: .backCameraPortrait))
        XCTAssertEqual(turn, 0, accuracy: 1e-9)
    }

    func testTheUpsideDownPresetIsTurnedHalfWayRound() throws {
        let turn = try XCTUnwrap(rotation(of: .backCameraPortraitUpsideDown))
        XCTAssertEqual(abs(turn), 180, accuracy: 1e-9)
    }

    func testTheLandscapeLeftPresetIsOnItsSideWithTheTopEdgeToTheLeft() throws {
        let turn = try XCTUnwrap(rotation(of: .backCameraLandscapeLeft))
        XCTAssertEqual(turn, -90, accuracy: 1e-9)
    }

    func testTheLandscapeRightPresetIsOnItsSideWithTheTopEdgeToTheRight() throws {
        let turn = try XCTUnwrap(rotation(of: .backCameraLandscapeRight))
        XCTAssertEqual(turn, 90, accuracy: 1e-9)
    }

    func testTheFlatOnTopPresetsKnowWhichWayTheTopEdgePoints() {
        XCTAssertEqual(MountLayout(.flatOnTopTopEdgeForward), .flatOnTop(topEdgeForward: true))
        XCTAssertEqual(MountLayout(.flatOnTopTopEdgeBack), .flatOnTop(topEdgeForward: false))
    }

    func testNoBuiltInPresetFallsBackToTheCustomPicture() {
        XCTAssertEqual(MountProfile.presets.count, 6)
        for preset in MountProfile.presets {
            XCTAssertNotEqual(MountLayout(preset), .custom, "\(preset.id) has no picture of its own")
        }
    }

    func testEveryBuiltInPresetHasItsOwnDescription() {
        let summaries = MountProfile.presets.map { MountLayout($0).summary }
        XCTAssertEqual(Set(summaries).count, summaries.count)
    }

    // MARK: Custom geometry

    func testAnAxisSlightlyOffTheBackOfThePhoneIsStillABackCameraMount() throws {
        // cos 5° is above the 0.99 threshold.
        let tilt = degrees(5)
        let profile = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, sin(tilt), -cos(tilt)), cameraUp: Vector3(0, 1, 0)))
        let turn = try XCTUnwrap(rotation(of: profile))
        XCTAssertEqual(turn, 0, accuracy: 1e-6)
    }

    func testAnAxisTiltedFurtherThanTheThresholdIsCustom() throws {
        // cos 9° is below 0.99.
        let tilt = degrees(9)
        let profile = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, sin(tilt), -cos(tilt)), cameraUp: Vector3(0, 1, 0)))
        XCTAssertEqual(MountLayout(profile), .custom)
    }

    func testAnAxisAcrossThePhoneIsCustom() throws {
        let profile = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(1, 0, 0), cameraUp: Vector3(0, 0, 1)))
        XCTAssertEqual(MountLayout(profile), .custom)
    }

    func testAnAxisAlongThePhoneWithUpOutOfTheScreenIsFlatOnTop() throws {
        let forward = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, 1, 0), cameraUp: Vector3(0, 0, 1)))
        XCTAssertEqual(MountLayout(forward), .flatOnTop(topEdgeForward: true))
        let back = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, -1, 0), cameraUp: Vector3(0, 0, 1)))
        XCTAssertEqual(MountLayout(back), .flatOnTop(topEdgeForward: false))
    }

    func testAnAxisAlongThePhoneWithUpIntoTheScreenIsCustom() throws {
        let profile = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, 1, 0), cameraUp: Vector3(0, 0, -1)))
        XCTAssertEqual(MountLayout(profile), .custom)
    }

    func testABackCameraMountTurnedByFortyFiveDegreesKeepsItsTurn() throws {
        let profile = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, 0, -1), cameraUp: Vector3(1, 1, 0)))
        let turn = try XCTUnwrap(rotation(of: profile))
        XCTAssertEqual(turn, -45, accuracy: 1e-6)
        XCTAssertEqual(MountLayout(profile).summary, "On the back of the camera, its rear camera looking along the lens.")
    }

    // MARK: Summaries

    func testTheSummaryOfAnUprightBackCameraMount() {
        let expected = "Upright on the back of the camera, screen towards you, its rear camera looking along the lens."
        XCTAssertEqual(MountLayout.backCamera(rotation: 0).summary, expected)
        XCTAssertEqual(MountLayout.backCamera(rotation: 0.4).summary, expected)
        XCTAssertEqual(MountLayout.backCamera(rotation: -0.4).summary, expected)
    }

    func testTheSummaryOfAnUpsideDownBackCameraMount() {
        let expected = "Upside down on the back of the camera, its rear camera looking along the lens."
        XCTAssertEqual(MountLayout.backCamera(rotation: 180).summary, expected)
        XCTAssertEqual(MountLayout.backCamera(rotation: -180).summary, expected)
        XCTAssertEqual(MountLayout.backCamera(rotation: 179.6).summary, expected)
        XCTAssertEqual(MountLayout.backCamera(rotation: -179.6).summary, expected)
    }

    func testTheSummaryOfASidewaysBackCameraMount() {
        let left = "On its side with the top edge to your left, its rear camera looking along the lens."
        let right = "On its side with the top edge to your right, its rear camera looking along the lens."
        XCTAssertEqual(MountLayout.backCamera(rotation: -90).summary, left)
        XCTAssertEqual(MountLayout.backCamera(rotation: -89.6).summary, left)
        XCTAssertEqual(MountLayout.backCamera(rotation: 90).summary, right)
        XCTAssertEqual(MountLayout.backCamera(rotation: 89.6).summary, right)
    }

    func testTheSummaryOfABackCameraMountAtAnotherTurn() {
        let expected = "On the back of the camera, its rear camera looking along the lens."
        XCTAssertEqual(MountLayout.backCamera(rotation: 45).summary, expected)
        XCTAssertEqual(MountLayout.backCamera(rotation: -135).summary, expected)
        XCTAssertEqual(MountLayout.backCamera(rotation: 0.6).summary, expected)
        XCTAssertEqual(MountLayout.backCamera(rotation: 120).summary, expected)
    }

    func testTheSummariesOfAPhoneFlatOnTop() {
        XCTAssertEqual(MountLayout.flatOnTop(topEdgeForward: true).summary,
                       "Flat on top of the camera, screen up, its top edge pointing along the lens.")
        XCTAssertEqual(MountLayout.flatOnTop(topEdgeForward: false).summary,
                       "Flat on top of the camera, screen up, its top edge pointing towards you.")
    }

    func testTheSummaryOfACustomMount() {
        XCTAssertEqual(MountLayout.custom.summary, "A custom mount.")
    }

    func testTheSummariesOfTheBuiltInPresetsMatchTheirNames() {
        XCTAssertEqual(MountLayout(.backCameraPortrait).summary,
                       "Upright on the back of the camera, screen towards you, its rear camera looking along the lens.")
        XCTAssertEqual(MountLayout(.backCameraPortraitUpsideDown).summary,
                       "Upside down on the back of the camera, its rear camera looking along the lens.")
        XCTAssertEqual(MountLayout(.backCameraLandscapeLeft).summary,
                       "On its side with the top edge to your left, its rear camera looking along the lens.")
        XCTAssertEqual(MountLayout(.backCameraLandscapeRight).summary,
                       "On its side with the top edge to your right, its rear camera looking along the lens.")
        XCTAssertEqual(MountLayout(.flatOnTopTopEdgeForward).summary,
                       "Flat on top of the camera, screen up, its top edge pointing along the lens.")
        XCTAssertEqual(MountLayout(.flatOnTopTopEdgeBack).summary,
                       "Flat on top of the camera, screen up, its top edge pointing towards you.")
    }

    // MARK: Equality

    func testLayoutsCompareByCaseAndValue() {
        XCTAssertEqual(MountLayout.backCamera(rotation: 90), .backCamera(rotation: 90))
        XCTAssertNotEqual(MountLayout.backCamera(rotation: 90), .backCamera(rotation: -90))
        XCTAssertNotEqual(MountLayout.flatOnTop(topEdgeForward: true), .flatOnTop(topEdgeForward: false))
        XCTAssertNotEqual(MountLayout.custom, .backCamera(rotation: 0))
    }
}
