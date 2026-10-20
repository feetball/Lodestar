import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `AppSettings`: defaults, the forward-compatible decoding, the clamping and the site list.
final class SettingsAppSettingsTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    private func roundTrip(_ settings: AppSettings) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    }

    private func makeSite(_ name: String = "Dark Site", id: UUID = UUID()) throws -> SavedSite {
        try XCTUnwrap(SavedSite(id: id, name: name, latitude: 40.5, longitude: -105.5, elevation: 2100))
    }

    /// The value a numeric setting has after `sanitize()` when it was set to `value`.
    private func clamped(_ keyPath: WritableKeyPath<AppSettings, Double>, _ value: Double) -> Double {
        var settings = AppSettings()
        settings[keyPath: keyPath] = value
        settings.sanitize()
        return settings[keyPath: keyPath]
    }

    // MARK: Defaults

    func testTheLimitsAreTheDocumentedOnes() {
        XCTAssertEqual(AppSettings.maximumSavedSites, 100)
        XCTAssertEqual(AppSettings.maximumRecents, 20)
        XCTAssertEqual(AppSettings.maximumFavorites, 200)
    }

    func testDefaultLocationAndMountSettings() {
        let settings = AppSettings()
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertEqual(settings.locationSource, .device)
        XCTAssertTrue(settings.savedSites.isEmpty)
        XCTAssertEqual(settings.mountPresetID, "backCamera.portrait")
        XCTAssertEqual(settings.mountPresetID, MountProfile.backCameraPortrait.id)
        XCTAssertEqual(settings.headingSource, .compass)
        XCTAssertEqual(settings.smoothingTimeConstant, 0.12)
    }

    func testDefaultCameraAndLensSettings() {
        let settings = AppSettings()
        XCTAssertEqual(settings.sensorID, "fullFrame")
        XCTAssertEqual(settings.sensorID, SensorFormat.fullFrame.id)
        XCTAssertEqual(settings.customSensorWidth, 36)
        XCTAssertEqual(settings.customSensorHeight, 24)
        XCTAssertEqual(settings.focalLength, 24)
        XCTAssertEqual(settings.aperture, 2.8)
        XCTAssertNil(settings.pixelPitch)
    }

    func testDefaultNightFeedbackAndSkyDisplaySettings() {
        let settings = AppSettings()
        XCTAssertEqual(settings.nightMode, .automatic)
        XCTAssertEqual(settings.nightIntensity, 0.7)
        XCTAssertTrue(settings.dimScreenAtNight)
        XCTAssertEqual(settings.nightBrightness, 0.2)
        XCTAssertFalse(settings.redFilterOverlay)
        XCTAssertTrue(settings.cameraPreviewEnabled)
        XCTAssertFalse(settings.cameraPreviewAtNight)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertFalse(settings.audioCuesEnabled)
        XCTAssertTrue(settings.keepScreenAwake)
        XCTAssertTrue(settings.showConstellationLines)
        XCTAssertTrue(settings.showConstellationNames)
        XCTAssertTrue(settings.showDeepSkyObjects)
        XCTAssertTrue(settings.showMilkyWay)
        XCTAssertEqual(settings.deepSkyProminence, 2)
        XCTAssertEqual(settings.starMagnitudeLimit, 5)
        XCTAssertEqual(settings.coordinateStyle, .sexagesimal)
    }

    func testDefaultAtmosphereAndObjectLists() {
        let settings = AppSettings()
        XCTAssertEqual(settings.temperatureCelsius, 10)
        XCTAssertEqual(settings.pressureMillibars, 1010)
        XCTAssertTrue(settings.favoriteObjectIDs.isEmpty)
        XCTAssertTrue(settings.recentObjectIDs.isEmpty)
    }

    func testDefaultsAreAFixedPointOfSanitizing() {
        var settings = AppSettings()
        settings.sanitize()
        XCTAssertEqual(settings, AppSettings())
    }

    func testAtmosphereCarriesThePressureAndTemperature() {
        var settings = AppSettings()
        XCTAssertEqual(settings.atmosphere, Atmosphere(pressureMillibars: 1010, temperatureCelsius: 10))
        settings.pressureMillibars = 950
        settings.temperatureCelsius = -5
        XCTAssertEqual(settings.atmosphere.pressureMillibars, 950)
        XCTAssertEqual(settings.atmosphere.temperatureCelsius, -5)
    }

    // MARK: Sanitizing

    func testSmoothingTimeConstantIsClampedToZeroToOne() {
        XCTAssertEqual(clamped(\.smoothingTimeConstant, -0.5), 0)
        XCTAssertEqual(clamped(\.smoothingTimeConstant, 0), 0)
        XCTAssertEqual(clamped(\.smoothingTimeConstant, 0.5), 0.5)
        XCTAssertEqual(clamped(\.smoothingTimeConstant, 1), 1)
        XCTAssertEqual(clamped(\.smoothingTimeConstant, 1.5), 1)
    }

    func testCustomSensorSizeIsClampedToOneToHundredMillimetres() {
        XCTAssertEqual(clamped(\.customSensorWidth, 0.5), 1)
        XCTAssertEqual(clamped(\.customSensorWidth, 1), 1)
        XCTAssertEqual(clamped(\.customSensorWidth, 36), 36)
        XCTAssertEqual(clamped(\.customSensorWidth, 100), 100)
        XCTAssertEqual(clamped(\.customSensorWidth, 150), 100)
        XCTAssertEqual(clamped(\.customSensorHeight, 0), 1)
        XCTAssertEqual(clamped(\.customSensorHeight, 24), 24)
        XCTAssertEqual(clamped(\.customSensorHeight, 101), 100)
    }

    func testFocalLengthIsClampedToFourToTwoThousand() {
        XCTAssertEqual(clamped(\.focalLength, 3.9), 4)
        XCTAssertEqual(clamped(\.focalLength, 4), 4)
        XCTAssertEqual(clamped(\.focalLength, 135), 135)
        XCTAssertEqual(clamped(\.focalLength, 2000), 2000)
        XCTAssertEqual(clamped(\.focalLength, 2000.1), 2000)
    }

    func testApertureIsClampedToF095ToF32() {
        XCTAssertEqual(clamped(\.aperture, 0.5), 0.95)
        XCTAssertEqual(clamped(\.aperture, 0.95), 0.95)
        XCTAssertEqual(clamped(\.aperture, 4), 4)
        XCTAssertEqual(clamped(\.aperture, 32), 32)
        XCTAssertEqual(clamped(\.aperture, 33), 32)
    }

    func testNightIntensityAndBrightnessAreClamped() {
        XCTAssertEqual(clamped(\.nightIntensity, 0.1), 0.25)
        XCTAssertEqual(clamped(\.nightIntensity, 0.25), 0.25)
        XCTAssertEqual(clamped(\.nightIntensity, 0.5), 0.5)
        XCTAssertEqual(clamped(\.nightIntensity, 1.2), 1)
        XCTAssertEqual(clamped(\.nightBrightness, 0), 0.01)
        XCTAssertEqual(clamped(\.nightBrightness, 0.5), 0.5)
        XCTAssertEqual(clamped(\.nightBrightness, 2), 1)
    }

    func testStarMagnitudeLimitIsClampedToOneToSixAndAHalf() {
        XCTAssertEqual(clamped(\.starMagnitudeLimit, 0), 1)
        XCTAssertEqual(clamped(\.starMagnitudeLimit, 1), 1)
        XCTAssertEqual(clamped(\.starMagnitudeLimit, 6.5), 6.5)
        XCTAssertEqual(clamped(\.starMagnitudeLimit, 7), 6.5)
    }

    func testTemperatureAndPressureAreClampedToPlausibleWeather() {
        XCTAssertEqual(clamped(\.temperatureCelsius, -61), -60)
        XCTAssertEqual(clamped(\.temperatureCelsius, 0), 0)
        XCTAssertEqual(clamped(\.temperatureCelsius, 60), 60)
        XCTAssertEqual(clamped(\.temperatureCelsius, 61), 60)
        XCTAssertEqual(clamped(\.pressureMillibars, 299), 300)
        XCTAssertEqual(clamped(\.pressureMillibars, 300), 300)
        XCTAssertEqual(clamped(\.pressureMillibars, 1100), 1100)
        XCTAssertEqual(clamped(\.pressureMillibars, 1101), 1100)
    }

    func testNonFiniteNumbersFallBackToTheirDefaultsRatherThanTheNearestBound() {
        XCTAssertEqual(clamped(\.smoothingTimeConstant, .nan), 0.12)
        XCTAssertEqual(clamped(\.smoothingTimeConstant, .infinity), 0.12)
        XCTAssertEqual(clamped(\.smoothingTimeConstant, -.infinity), 0.12)
        XCTAssertEqual(clamped(\.customSensorWidth, .nan), 36)
        XCTAssertEqual(clamped(\.customSensorHeight, .nan), 24)
        XCTAssertEqual(clamped(\.focalLength, .infinity), 24)
        XCTAssertEqual(clamped(\.aperture, .nan), 2.8)
        XCTAssertEqual(clamped(\.nightIntensity, .nan), 0.7)
        XCTAssertEqual(clamped(\.nightBrightness, .nan), 0.2)
        XCTAssertEqual(clamped(\.starMagnitudeLimit, .nan), 5)
        XCTAssertEqual(clamped(\.temperatureCelsius, .nan), 10)
        XCTAssertEqual(clamped(\.pressureMillibars, .nan), 1010)
    }

    func testPixelPitchIsKeptOnlyInsideHalfToTwentyMicrometres() {
        func pitch(_ value: Double?) -> Double? {
            var settings = AppSettings()
            settings.pixelPitch = value
            settings.sanitize()
            return settings.pixelPitch
        }
        XCTAssertNil(pitch(nil))
        XCTAssertNil(pitch(0.4))
        XCTAssertEqual(pitch(0.5), 0.5)
        XCTAssertEqual(pitch(3.76), 3.76)
        XCTAssertEqual(pitch(20), 20)
        XCTAssertNil(pitch(20.5))
        XCTAssertNil(pitch(Double.nan))
        XCTAssertNil(pitch(Double.infinity))
        XCTAssertNil(pitch(-4))
    }

    func testDeepSkyProminenceIsClampedToOneToFour() {
        func prominence(_ value: Int) -> Int {
            var settings = AppSettings()
            settings.deepSkyProminence = value
            settings.sanitize()
            return settings.deepSkyProminence
        }
        XCTAssertEqual(prominence(-7), 1)
        XCTAssertEqual(prominence(0), 1)
        XCTAssertEqual(prominence(1), 1)
        XCTAssertEqual(prominence(3), 3)
        XCTAssertEqual(prominence(4), 4)
        XCTAssertEqual(prominence(5), 4)
        XCTAssertEqual(prominence(Int.max), 4)
    }

    func testSanitizingResetsALocationSourceThatNamesNoSavedSite() throws {
        let known = try makeSite()
        var settings = AppSettings()
        settings.savedSites = [known]

        settings.locationSource = .site(UUID())
        settings.sanitize()
        XCTAssertEqual(settings.locationSource, .device)

        settings.locationSource = .site(known.id)
        settings.sanitize()
        XCTAssertEqual(settings.locationSource, .site(known.id))

        settings.locationSource = .device
        settings.sanitize()
        XCTAssertEqual(settings.locationSource, .device)
    }

    // MARK: Decoding

    func testAnEmptyObjectDecodesToTheDefaults() throws {
        XCTAssertEqual(try decode("{}"), AppSettings())
    }

    func testUnknownKeysAreIgnored() throws {
        let settings = try decode(#"{"someFutureSetting":{"a":1},"hapticsEnabled":false}"#)
        var expected = AppSettings()
        expected.hapticsEnabled = false
        XCTAssertEqual(settings, expected)
    }

    func testPresentKeysAreReadAndMissingOnesKeepTheirDefaults() throws {
        let settings = try decode(#"{"focalLength":135,"nightMode":"on","coordinateStyle":"decimal","headingSource":"gyroLock"}"#)
        XCTAssertEqual(settings.focalLength, 135)
        XCTAssertEqual(settings.nightMode, .on)
        XCTAssertEqual(settings.coordinateStyle, .decimal)
        XCTAssertEqual(settings.headingSource, .gyroLock)
        XCTAssertEqual(settings.aperture, 2.8)
        XCTAssertTrue(settings.hapticsEnabled)
    }

    func testAKeyOfTheWrongTypeFallsBackToItsDefaultWithoutLosingTheOthers() throws {
        let settings = try decode(#"{"focalLength":"long","hapticsEnabled":"yes","keepScreenAwake":false,"aperture":4}"#)
        XCTAssertEqual(settings.focalLength, 24)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertFalse(settings.keepScreenAwake)
        XCTAssertEqual(settings.aperture, 4)
    }

    func testANullKeyFallsBackToItsDefault() throws {
        let settings = try decode(#"{"focalLength":null,"pixelPitch":null,"aperture":5.6}"#)
        XCTAssertEqual(settings.focalLength, 24)
        XCTAssertNil(settings.pixelPitch)
        XCTAssertEqual(settings.aperture, 5.6)
    }

    func testAnUnknownEnumValueFallsBackToTheDefault() throws {
        let settings = try decode(#"{"nightMode":"bogus","headingSource":"sextant","coordinateStyle":"octal","hasCompletedOnboarding":true}"#)
        XCTAssertEqual(settings.nightMode, .automatic)
        XCTAssertEqual(settings.headingSource, .compass)
        XCTAssertEqual(settings.coordinateStyle, .sexagesimal)
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }

    func testAMalformedLocationSourceFallsBackToTheDevice() throws {
        XCTAssertEqual(try decode(#"{"locationSource":"somewhere"}"#).locationSource, .device)
    }

    func testAFractionalIntegerSettingFallsBackToItsDefault() throws {
        XCTAssertEqual(try decode(#"{"deepSkyProminence":2.5}"#).deepSkyProminence, 2)
        XCTAssertEqual(try decode(#"{"deepSkyProminence":3}"#).deepSkyProminence, 3)
    }

    func testAnUnknownMountPresetIdentifierIsKeptAsIs() throws {
        XCTAssertEqual(try decode(#"{"mountPresetID":"flatOnTop.topEdgeBack"}"#).mountPresetID, "flatOnTop.topEdgeBack")
        XCTAssertEqual(try decode(#"{"mountPresetID":"custom.something"}"#).mountPresetID, "custom.something")
    }

    func testOutOfRangeStoredNumbersAreClampedOnDecoding() throws {
        let settings = try decode("""
        {"focalLength":99999,"aperture":0.1,"smoothingTimeConstant":5,"customSensorWidth":0,"customSensorHeight":500,
         "nightIntensity":0,"nightBrightness":0,"starMagnitudeLimit":10,"deepSkyProminence":0,
         "temperatureCelsius":-100,"pressureMillibars":2000,"pixelPitch":50}
        """)
        XCTAssertEqual(settings.focalLength, 2000)
        XCTAssertEqual(settings.aperture, 0.95)
        XCTAssertEqual(settings.smoothingTimeConstant, 1)
        XCTAssertEqual(settings.customSensorWidth, 1)
        XCTAssertEqual(settings.customSensorHeight, 100)
        XCTAssertEqual(settings.nightIntensity, 0.25)
        XCTAssertEqual(settings.nightBrightness, 0.01)
        XCTAssertEqual(settings.starMagnitudeLimit, 6.5)
        XCTAssertEqual(settings.deepSkyProminence, 1)
        XCTAssertEqual(settings.temperatureCelsius, -60)
        XCTAssertEqual(settings.pressureMillibars, 1100)
        XCTAssertNil(settings.pixelPitch)
    }

    func testObjectListsOfTheWrongTypeFallBackToEmpty() throws {
        let settings = try decode(#"{"favoriteObjectIDs":[1,2],"recentObjectIDs":"M31"}"#)
        XCTAssertTrue(settings.favoriteObjectIDs.isEmpty)
        XCTAssertTrue(settings.recentObjectIDs.isEmpty)
    }

    func testStoredFavoritesAndRecentsAreCutToTheirLimitsKeepingTheFirstOnes() throws {
        var settings = AppSettings()
        settings.favoriteObjectIDs = (0..<250).map { "fav\($0)" }
        settings.recentObjectIDs = (0..<30).map { "recent\($0)" }
        let decoded = try roundTrip(settings)
        XCTAssertEqual(decoded.favoriteObjectIDs.count, 200)
        XCTAssertEqual(decoded.favoriteObjectIDs.first, "fav0")
        XCTAssertEqual(decoded.favoriteObjectIDs.last, "fav199")
        XCTAssertEqual(decoded.recentObjectIDs.count, 20)
        XCTAssertEqual(decoded.recentObjectIDs.first, "recent0")
        XCTAssertEqual(decoded.recentObjectIDs.last, "recent19")
    }

    func testObjectListsAtTheirLimitsAreKeptWhole() throws {
        var settings = AppSettings()
        settings.favoriteObjectIDs = (0..<200).map { "fav\($0)" }
        settings.recentObjectIDs = (0..<20).map { "recent\($0)" }
        let decoded = try roundTrip(settings)
        XCTAssertEqual(decoded.favoriteObjectIDs, settings.favoriteObjectIDs)
        XCTAssertEqual(decoded.recentObjectIDs, settings.recentObjectIDs)
    }

    // MARK: Saved sites in storage

    func testAnInvalidOrDamagedSiteIsDroppedAndTheGoodOnesSurvive() throws {
        let goodID = UUID()
        let good = #"{"id":"\#(goodID.uuidString)","name":"Dark Site","latitude":40.5,"longitude":-105.5,"elevation":2100}"#
        let badLatitude = #"{"id":"\#(UUID().uuidString)","name":"Nowhere","latitude":123.0,"longitude":0}"#
        let missingName = #"{"id":"\#(UUID().uuidString)","latitude":1,"longitude":2}"#
        let notAnObject = "42"
        let settings = try decode(#"{"savedSites":[\#(badLatitude),\#(good),\#(notAnObject),\#(missingName)]}"#)
        XCTAssertEqual(settings.savedSites.count, 1)
        let site = try XCTUnwrap(settings.savedSites.first)
        XCTAssertEqual(site.id, goodID)
        XCTAssertEqual(site.name, "Dark Site")
        XCTAssertEqual(site.latitude, 40.5)
        XCTAssertEqual(site.longitude, -105.5)
        XCTAssertEqual(site.elevation, 2100)
    }

    func testSavedSitesThatAreNotAnArrayAreIgnored() throws {
        XCTAssertTrue(try decode(#"{"savedSites":5}"#).savedSites.isEmpty)
        XCTAssertTrue(try decode(#"{"savedSites":null}"#).savedSites.isEmpty)
    }

    func testMoreThanTheMaximumNumberOfSitesKeepsTheFirstHundred() throws {
        var settings = AppSettings()
        settings.savedSites = try (0..<105).map { try makeSite("Site \($0)") }
        let decoded = try roundTrip(settings)
        XCTAssertEqual(decoded.savedSites.count, 100)
        XCTAssertEqual(decoded.savedSites.map(\.name), (0..<100).map { "Site \($0)" })
    }

    func testALocationSourceThatNamesAMissingSiteIsResetToTheDeviceOnDecoding() throws {
        var settings = AppSettings()
        settings.locationSource = .site(UUID())
        XCTAssertEqual(try roundTrip(settings).locationSource, .device)
    }

    func testALocationSourceThatNamesASavedSiteSurvivesDecoding() throws {
        let site = try makeSite()
        var settings = AppSettings()
        settings.savedSites = [site]
        settings.locationSource = .site(site.id)
        XCTAssertEqual(try roundTrip(settings).locationSource, .site(site.id))
    }

    func testALocationSourceWhoseSiteWasDamagedInStorageIsResetToTheDevice() throws {
        let id = UUID()
        let bad = #"{"id":"\#(id.uuidString)","name":"Broken","latitude":999,"longitude":0}"#
        let source = try JSONEncoder().encode(LocationSource.site(id))
        let sourceJSON = String(decoding: source, as: UTF8.self)
        let settings = try decode(#"{"locationSource":\#(sourceJSON),"savedSites":[\#(bad)]}"#)
        XCTAssertTrue(settings.savedSites.isEmpty)
        XCTAssertEqual(settings.locationSource, .device)
    }

    // MARK: Round trip

    func testEveryNonDefaultSettingSurvivesAnEncodeDecodeRoundTrip() throws {
        let site = try makeSite()
        var settings = AppSettings()
        settings.hasCompletedOnboarding = true
        settings.savedSites = [site]
        settings.locationSource = .site(site.id)
        settings.mountPresetID = "backCamera.landscapeLeft"
        settings.headingSource = .gyroLock
        settings.smoothingTimeConstant = 0.5
        settings.sensorID = "apsC"
        settings.customSensorWidth = 20.5
        settings.customSensorHeight = 15.25
        settings.focalLength = 135
        settings.aperture = 4
        settings.pixelPitch = 4.5
        settings.nightMode = .on
        settings.nightIntensity = 0.5
        settings.dimScreenAtNight = false
        settings.nightBrightness = 0.5
        settings.redFilterOverlay = true
        settings.cameraPreviewEnabled = false
        settings.cameraPreviewAtNight = true
        settings.hapticsEnabled = false
        settings.audioCuesEnabled = true
        settings.keepScreenAwake = false
        settings.showConstellationLines = false
        settings.showConstellationNames = false
        settings.showDeepSkyObjects = false
        settings.showMilkyWay = false
        settings.deepSkyProminence = 3
        settings.starMagnitudeLimit = 6
        settings.coordinateStyle = .decimal
        settings.temperatureCelsius = -5
        settings.pressureMillibars = 950
        settings.favoriteObjectIDs = ["dso.M31", "planet.mars"]
        settings.recentObjectIDs = ["star.hip32349"]
        XCTAssertEqual(try roundTrip(settings), settings)
    }

    func testTheDefaultSettingsSurviveARoundTrip() throws {
        XCTAssertEqual(try roundTrip(AppSettings()), AppSettings())
    }

    func testASiteWithASkylineSurvivesTheRoundTripOfTheSettings() throws {
        let skyline = HorizonProfile.constant(12.5)
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: skyline))
        var settings = AppSettings()
        settings.savedSites = [site]
        let decoded = try roundTrip(settings)
        XCTAssertEqual(decoded.savedSites.first?.horizon, skyline)
    }
}

/// The small preference enums of `AppSettings.swift`.
final class SettingsPreferenceEnumTests: XCTestCase {
    func testNightModeSettingTitlesIdsAndOrder() {
        XCTAssertEqual(NightModeSetting.allCases, [.off, .on, .automatic])
        XCTAssertEqual(NightModeSetting.off.title, "Off")
        XCTAssertEqual(NightModeSetting.on.title, "On")
        XCTAssertEqual(NightModeSetting.automatic.title, "After Sunset")
        XCTAssertEqual(NightModeSetting.allCases.map(\.id), ["off", "on", "automatic"])
    }

    func testHeadingSourceTitlesIdsAndOrder() {
        XCTAssertEqual(HeadingSource.allCases, [.compass, .gyroLock])
        XCTAssertEqual(HeadingSource.compass.title, "Compass")
        XCTAssertEqual(HeadingSource.gyroLock.title, "Gyro Lock")
        XCTAssertEqual(HeadingSource.allCases.map(\.id), ["compass", "gyroLock"])
    }

    func testCoordinateStyleTitlesIdsAndOrder() {
        XCTAssertEqual(CoordinateStyle.allCases, [.sexagesimal, .decimal])
        XCTAssertEqual(CoordinateStyle.sexagesimal.title, "h m s / \u{00B0} \u{2032} \u{2033}")
        XCTAssertEqual(CoordinateStyle.decimal.title, "Decimal")
        XCTAssertEqual(CoordinateStyle.allCases.map(\.id), ["sexagesimal", "decimal"])
    }

    func testEnumsRoundTripThroughTheirRawValues() throws {
        for mode in NightModeSetting.allCases {
            let data = try JSONEncoder().encode([mode])
            XCTAssertEqual(try JSONDecoder().decode([NightModeSetting].self, from: data), [mode])
        }
        XCTAssertEqual(NightModeSetting(rawValue: "automatic"), .automatic)
        XCTAssertNil(NightModeSetting(rawValue: "Automatic"))
        XCTAssertEqual(HeadingSource(rawValue: "gyroLock"), .gyroLock)
        XCTAssertEqual(CoordinateStyle(rawValue: "decimal"), .decimal)
    }

    func testLocationSourceEqualityHashingAndCoding() throws {
        let a = UUID(), b = UUID()
        XCTAssertEqual(LocationSource.device, LocationSource.device)
        XCTAssertEqual(LocationSource.site(a), LocationSource.site(a))
        XCTAssertNotEqual(LocationSource.site(a), LocationSource.site(b))
        XCTAssertNotEqual(LocationSource.site(a), LocationSource.device)
        XCTAssertEqual(Set([LocationSource.site(a), .site(a), .device]).count, 2)

        for source in [LocationSource.device, .site(a)] {
            let data = try JSONEncoder().encode(source)
            XCTAssertEqual(try JSONDecoder().decode(LocationSource.self, from: data), source)
        }
    }
}
