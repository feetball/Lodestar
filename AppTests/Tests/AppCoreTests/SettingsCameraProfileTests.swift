import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `CameraProfile` (Model/CameraProfile.swift) and how `AppSettings` keeps its camera profiles.
final class SettingsCameraProfileTests: XCTestCase {
    private func decode(_ json: String) throws -> CameraProfile {
        try JSONDecoder().decode(CameraProfile.self, from: Data(json.utf8))
    }

    private let anID = "5B2D5C4E-1111-4222-8333-444455556666"

    // MARK: The profile

    func testAProfileTakesTheDefaultsOfAFullFrameLens() {
        let profile = CameraProfile(name: "Body")
        XCTAssertEqual(profile.sensorID, SensorFormat.fullFrame.id)
        XCTAssertEqual(profile.focalLength, LensSetup.defaultFocalLengthMillimeters)
        XCTAssertEqual(profile.aperture, LensSetup.defaultAperture)
        XCTAssertNil(profile.pixelPitch)
        XCTAssertEqual(profile.projection, .rectilinear)
        XCTAssertNil(profile.imageCircleDiameter)
        XCTAssertFalse(profile.isCustomSensor)
        XCTAssertEqual(profile.sensor.id, SensorFormat.fullFrame.id)
    }

    func testEveryValueIsLimitedToItsRange() {
        let profile = CameraProfile(name: "x", sensorID: "unknown", customSensorWidth: 500, customSensorHeight: -3,
                                    focalLength: 1, aperture: 99, pixelPitch: 50, imageCircleDiameter: 9_999)
        XCTAssertEqual(profile.sensorID, CameraProfile.customSensorID, "a sensor that is not a preset is custom")
        XCTAssertTrue(profile.isCustomSensor)
        XCTAssertEqual(profile.customSensorWidth, CameraProfile.customSensorRange.upperBound)
        XCTAssertEqual(profile.customSensorHeight, CameraProfile.customSensorRange.lowerBound)
        XCTAssertEqual(profile.focalLength, LensSetup.focalLengthRange.lowerBound)
        XCTAssertEqual(profile.aperture, LensSetup.apertureRange.upperBound)
        XCTAssertNil(profile.pixelPitch, "a pixel pitch out of range is dropped")
        XCTAssertNil(profile.imageCircleDiameter, "an image circle out of range is dropped")
    }

    func testNumbersThatAreNotFiniteTakeTheDefaults() {
        let profile = CameraProfile(name: "x", customSensorWidth: .nan, customSensorHeight: .infinity, focalLength: .nan,
                                    aperture: .nan, pixelPitch: .nan, imageCircleDiameter: .nan)
        XCTAssertEqual(profile.customSensorWidth, 36)
        XCTAssertEqual(profile.customSensorHeight, 24)
        XCTAssertEqual(profile.focalLength, LensSetup.defaultFocalLengthMillimeters)
        XCTAssertEqual(profile.aperture, LensSetup.defaultAperture)
        XCTAssertNil(profile.pixelPitch)
        XCTAssertNil(profile.imageCircleDiameter)
    }

    func testAValidPixelPitchAndImageCircleAreKept() {
        let profile = CameraProfile(name: "x", pixelPitch: 3.76, imageCircleDiameter: 24)
        XCTAssertEqual(profile.pixelPitch, 3.76)
        XCTAssertEqual(profile.imageCircleDiameter, 24)
        XCTAssertEqual(profile.lensSetup.pixelPitchMicrometers, 3.76)
        XCTAssertEqual(profile.lensSetup.imageCircleDiameterMillimeters, 24)
    }

    func testANameIsTrimmedCutAndNeverEmpty() {
        XCTAssertEqual(CameraProfile.limitedName("  Body  "), "Body")
        XCTAssertEqual(CameraProfile.limitedName("   "), "Camera")
        XCTAssertEqual(CameraProfile.limitedName(String(repeating: "a", count: 60)).count, CameraProfile.maximumNameLength)
        let spaced = String(repeating: "a", count: CameraProfile.maximumNameLength - 1) + "   b"
        XCTAssertEqual(CameraProfile.limitedName(spaced), String(repeating: "a", count: CameraProfile.maximumNameLength - 1),
                       "no space is left at the cut")
        XCTAssertEqual(CameraProfile(name: "").name, "Camera")
    }

    func testACustomSensorHasTheSizeOfTheProfile() {
        let profile = CameraProfile(name: "x", sensorID: CameraProfile.customSensorID, customSensorWidth: 20, customSensorHeight: 10)
        XCTAssertTrue(profile.isCustomSensor)
        XCTAssertEqual(profile.sensor.widthMillimeters, 20)
        XCTAssertEqual(profile.sensor.heightMillimeters, 10)
    }

    func testTheLensSetupIsTheProfileAsTheEngineWorksWithIt() {
        let profile = CameraProfile(name: "x", sensorID: SensorFormat.apsC.id, focalLength: 50, aperture: 1.8,
                                    projection: .fisheyeEquisolid)
        let setup = profile.lensSetup
        XCTAssertEqual(setup.sensor.id, SensorFormat.apsC.id)
        XCTAssertEqual(setup.focalLengthMillimeters, 50)
        XCTAssertEqual(setup.aperture, 1.8)
        XCTAssertEqual(setup.projection, .fisheyeEquisolid)
    }

    func testAPresetMakesAProfileNamedAfterIt() {
        let preset = CameraPreset.seestarS50
        let profile = CameraProfile(preset: preset)
        XCTAssertEqual(profile.name, CameraProfile.limitedName(preset.name))
        XCTAssertEqual(profile.focalLength, preset.focalLengthMillimeters)
        XCTAssertEqual(profile.aperture, preset.aperture)
        XCTAssertEqual(profile.pixelPitch, preset.pixelPitchMicrometers)
        XCTAssertEqual(profile.projection, preset.projection)
        let id = UUID()
        XCTAssertEqual(CameraProfile(preset: preset, id: id).id, id)
    }

    func testSanitizingLimitsTheValuesAgain() {
        var profile = CameraProfile(name: "x")
        profile.focalLength = 99_999
        profile.name = "  "
        profile.pixelPitch = 500
        let clean = profile.sanitized()
        XCTAssertEqual(clean.focalLength, LensSetup.focalLengthRange.upperBound)
        XCTAssertEqual(clean.name, "Camera")
        XCTAssertNil(clean.pixelPitch)
        XCTAssertEqual(clean.id, profile.id)
        XCTAssertEqual(clean.sanitized(), clean)
    }

    // MARK: Codable

    func testAProfileSurvivesARoundTrip() throws {
        let profile = CameraProfile(name: "Fisheye", sensorID: SensorFormat.apsC.id, focalLength: 8, aperture: 3.5,
                                    pixelPitch: 4.2, projection: .fisheyeEquidistant, imageCircleDiameter: 22)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    func testAnUnknownPixelPitchAndAMissingImageCircleAreLeftOutOfTheJSON() throws {
        let data = try JSONEncoder().encode(CameraProfile(name: "x"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["pixelPitch"])
        XCTAssertNil(object["imageCircleDiameter"])
        XCTAssertNotNil(object["focalLength"])
    }

    func testAMissingValueTakesItsDefaultAndAnIdentifierIsRequired() throws {
        let profile = try decode(#"{"id":"\#(anID)"}"#)
        XCTAssertEqual(profile.name, "Camera")
        XCTAssertEqual(profile.sensorID, SensorFormat.fullFrame.id)
        XCTAssertEqual(profile.focalLength, LensSetup.defaultFocalLengthMillimeters)
        XCTAssertEqual(profile.projection, .rectilinear)
        XCTAssertThrowsError(try decode(#"{"name":"No id"}"#))
        XCTAssertThrowsError(try decode(#"{"id":"not a uuid"}"#))
    }

    func testOneBadNumberDoesNotLoseTheProfile() throws {
        let profile = try decode(#"{"id":"\#(anID)","name":"Body","focalLength":"long","aperture":2}"#)
        XCTAssertEqual(profile.name, "Body")
        XCTAssertEqual(profile.focalLength, LensSetup.defaultFocalLengthMillimeters)
        XCTAssertEqual(profile.aperture, 2)
    }

    func testTheMigratedProfileHasTheSameIdentifierEverywhere() {
        XCTAssertEqual(CameraProfile.migratedID.uuidString, "00000000-0000-4000-8000-000000000001")
    }

    // MARK: In the settings

    func testSettingsWithoutProfilesDescribeTheirSingleCamera() {
        var settings = AppSettings()
        settings.focalLength = 135
        XCTAssertTrue(settings.cameraProfiles.isEmpty)
        let active = settings.activeCameraProfile
        XCTAssertEqual(active.id, CameraProfile.migratedID)
        XCTAssertEqual(active.name, CameraProfile.defaultName)
        XCTAssertEqual(active.focalLength, 135)
    }

    func testSanitizingMakesTheFirstProfileOfTheSingleCamera() {
        var settings = AppSettings()
        settings.focalLength = 135
        settings.sanitizeCamera()
        XCTAssertEqual(settings.cameraProfiles.count, 1)
        XCTAssertEqual(settings.cameraProfiles[0].focalLength, 135)
        XCTAssertEqual(settings.activeCameraProfileID, CameraProfile.migratedID)
    }

    func testTheSingleCameraKeysFollowTheActiveProfile() {
        var settings = AppSettings()
        let first = CameraProfile(name: "First", focalLength: 24)
        let second = CameraProfile(name: "Second", sensorID: SensorFormat.apsC.id, focalLength: 85, aperture: 1.8, pixelPitch: 4)
        settings.cameraProfiles = [first, second]
        settings.activeCameraProfileID = second.id
        settings.sanitizeCamera()
        XCTAssertEqual(settings.activeCameraProfile, second)
        XCTAssertEqual(settings.focalLength, 85)
        XCTAssertEqual(settings.aperture, 1.8)
        XCTAssertEqual(settings.sensorID, SensorFormat.apsC.id)
        XCTAssertEqual(settings.pixelPitch, 4)
    }

    func testAnUnknownActiveProfileFallsBackToTheFirst() {
        var settings = AppSettings()
        let first = CameraProfile(name: "First")
        settings.cameraProfiles = [first, CameraProfile(name: "Second")]
        settings.activeCameraProfileID = UUID()
        XCTAssertEqual(settings.activeCameraProfile, first)
        settings.sanitizeCamera()
        XCTAssertEqual(settings.activeCameraProfileID, first.id)
    }

    func testDuplicateIdentifiersAreDroppedAndTheNumberOfProfilesIsLimited() {
        var settings = AppSettings()
        let one = CameraProfile(name: "One")
        settings.cameraProfiles = [one, CameraProfile(id: one.id, name: "Same id")]
            + (0..<(AppSettings.maximumCameraProfiles + 5)).map { CameraProfile(name: "Extra \($0)") }
        settings.sanitizeCamera()
        XCTAssertEqual(settings.cameraProfiles.count, AppSettings.maximumCameraProfiles)
        XCTAssertEqual(settings.cameraProfiles.filter { $0.id == one.id }.count, 1)
        XCTAssertEqual(settings.cameraProfiles[0].name, "One")
    }

    func testAChangeToTheSingleCameraKeysGoesToTheActiveProfile() {
        var before = AppSettings()
        before.cameraProfiles = [CameraProfile(name: "Body", focalLength: 24)]
        before.sanitizeCamera()
        var after = before
        after.focalLength = 200
        after.reconcileCamera(after: before)
        XCTAssertEqual(after.cameraProfiles[0].focalLength, 200)
        XCTAssertEqual(after.focalLength, 200)
    }

    func testAChangeToTheProfilesWinsOverOneToTheKeys() {
        var before = AppSettings()
        before.cameraProfiles = [CameraProfile(name: "Body", focalLength: 24)]
        before.sanitizeCamera()
        var after = before
        after.focalLength = 200
        after.cameraProfiles[0].focalLength = 50
        after.reconcileCamera(after: before)
        XCTAssertEqual(after.cameraProfiles[0].focalLength, 50)
        XCTAssertEqual(after.focalLength, 50, "the keys follow the profile")
    }

    func testNothingChangesWhenTheCameraDoesNot() {
        var before = AppSettings()
        before.sanitizeCamera()
        var after = before
        after.reconcileCamera(after: before)
        XCTAssertEqual(after, before)
    }
}

/// The camera profile changes of `SettingsStore`.
@MainActor
final class SettingsCameraProfileStoreTests: XCTestCase {
    private func makeStore() throws -> SettingsStore {
        let suite = "AppCoreTests.CameraProfiles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return SettingsStore(defaults: defaults)
    }

    func testTheStoreAddsAndActivatesProfiles() throws {
        let store = try makeStore()
        XCTAssertEqual(store.settings.cameraProfiles.count, 1, "the first start turns the single camera into a profile")
        let added = CameraProfile(name: "Second", focalLength: 85)
        XCTAssertTrue(store.addCameraProfile(added))
        XCTAssertEqual(store.settings.cameraProfiles.count, 2)
        XCTAssertEqual(store.settings.activeCameraProfileID, added.id)
        XCTAssertEqual(store.settings.focalLength, 85)
        store.activateCameraProfile(CameraProfile.migratedID)
        XCTAssertEqual(store.settings.activeCameraProfileID, CameraProfile.migratedID)
        store.activateCameraProfile(UUID())
        XCTAssertEqual(store.settings.activeCameraProfileID, CameraProfile.migratedID, "an unknown profile is ignored")
    }

    func testTheStoreUpdatesAndRemovesProfilesButKeepsTheLastOne() throws {
        let store = try makeStore()
        let added = CameraProfile(name: "Second")
        XCTAssertTrue(store.addCameraProfile(added))
        var renamed = added
        renamed.name = "Renamed"
        renamed.focalLength = 135
        store.updateCameraProfile(renamed)
        XCTAssertEqual(store.settings.cameraProfiles.first { $0.id == added.id }?.name, "Renamed")
        store.updateCameraProfile(CameraProfile(name: "Not stored"))
        XCTAssertEqual(store.settings.cameraProfiles.count, 2)
        XCTAssertTrue(store.removeCameraProfile(added.id))
        XCTAssertEqual(store.settings.cameraProfiles.count, 1)
        XCTAssertFalse(store.removeCameraProfile(store.settings.cameraProfiles[0].id), "the only profile stays")
        XCTAssertEqual(store.settings.cameraProfiles.count, 1)
    }

    func testTheStoreRefusesProfilesBeyondTheMaximum() throws {
        let store = try makeStore()
        while store.settings.cameraProfiles.count < AppSettings.maximumCameraProfiles {
            XCTAssertTrue(store.addCameraProfile(CameraProfile(name: "p")))
        }
        XCTAssertFalse(store.addCameraProfile(CameraProfile(name: "one too many")))
        XCTAssertEqual(store.settings.cameraProfiles.count, AppSettings.maximumCameraProfiles)
    }

    func testAChangeToTheSingleCameraKeysThroughTheStoreGoesToTheActiveProfile() throws {
        let store = try makeStore()
        store.settings.focalLength = 300
        XCTAssertEqual(store.settings.activeCameraProfile.focalLength, 300)
        XCTAssertEqual(store.settings.cameraProfiles[0].focalLength, 300)
    }
}
