import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Features/Mount/MountPreferences.swift: the address typed for each kind of mount, the settings that outlive a connection and
/// how they are stored in `UserDefaults` (a private suite per test; never the standard defaults).
final class MountNetPreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppCoreTests.MountNet.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func decodeSettings(_ json: String) throws -> MountUserSettings {
        try JSONDecoder().decode(MountUserSettings.self, from: Data(json.utf8))
    }

    private func decodeMemory(_ json: String) throws -> MountConnectionMemory {
        try JSONDecoder().decode(MountConnectionMemory.self, from: Data(json.utf8))
    }

    private func decodeForm(_ json: String) throws -> MountConnectionForm {
        try JSONDecoder().decode(MountConnectionForm.self, from: Data(json.utf8))
    }

    // MARK: The address of one kind of mount

    func testAFormStartsWithTheDefaultsOfItsOption() {
        let lx200 = MountConnectionForm(option: .lx200)
        XCTAssertEqual(lx200.host, "192.168.0.1")
        XCTAssertEqual(lx200.port, 9999)
        XCTAssertEqual(lx200.link, .tcp)
        XCTAssertEqual(lx200.deviceNumber, 0)
        XCTAssertNil(lx200.deviceName)

        let nexstar = MountConnectionForm(option: .nexstar)
        XCTAssertEqual(nexstar.host, "192.168.4.1")
        XCTAssertEqual(nexstar.port, 11880)
        XCTAssertEqual(nexstar.link, .udp)

        let alpaca = MountConnectionForm(option: .alpaca)
        XCTAssertEqual(alpaca.host, "")
        XCTAssertEqual(alpaca.port, 11111)
        XCTAssertEqual(alpaca.link, .http)
    }

    func testAFormRoundTripsThroughJSON() throws {
        var form = MountConnectionForm(option: .alpaca)
        form.host = "192.168.1.20"
        form.port = 32323
        form.deviceNumber = 2
        form.deviceName = "Dobsonian"
        let data = try JSONEncoder().encode(form)
        XCTAssertEqual(try JSONDecoder().decode(MountConnectionForm.self, from: data), form)
    }

    func testAFormWithoutADeviceStillDecodes() throws {
        let form = try decodeForm("{\"host\":\"10.0.0.1\",\"port\":2000,\"link\":\"tcp\"}")
        XCTAssertEqual(form.host, "10.0.0.1")
        XCTAssertEqual(form.port, 2000)
        XCTAssertEqual(form.link, .tcp)
        XCTAssertEqual(form.deviceNumber, 0)
        XCTAssertNil(form.deviceName)
    }

    func testAFormIgnoresADeviceOfTheWrongType() throws {
        let form = try decodeForm("{\"host\":\"h\",\"port\":1,\"link\":\"http\",\"deviceNumber\":\"two\",\"deviceName\":7}")
        XCTAssertEqual(form.deviceNumber, 0)
        XCTAssertNil(form.deviceName)
    }

    func testAFormNeedsItsHostPortAndLink() {
        XCTAssertThrowsError(try decodeForm("{\"port\":1,\"link\":\"tcp\"}"))
        XCTAssertThrowsError(try decodeForm("{\"host\":\"h\",\"link\":\"tcp\"}"))
        XCTAssertThrowsError(try decodeForm("{\"host\":\"h\",\"port\":1}"))
        XCTAssertThrowsError(try decodeForm("{\"host\":\"h\",\"port\":1,\"link\":\"carrier-pigeon\"}"))
        XCTAssertThrowsError(try decodeForm("{\"host\":\"h\",\"port\":\"80\",\"link\":\"tcp\"}"))
    }

    func testTheAddressTextShowsHostAndPort() {
        var form = MountConnectionForm(option: .lx200)
        XCTAssertEqual(form.addressText, "192.168.0.1:9999")
        form.host = "10.0.0.2:2000"
        XCTAssertEqual(form.addressText, "10.0.0.2:2000", "a port in the text wins over the port field")
        form.host = "http://mount.local:8080/"
        form.port = 1
        XCTAssertEqual(form.addressText, "mount.local:8080")
        form.host = "  mount.local  "
        form.port = 4030
        XCTAssertEqual(form.addressText, "mount.local:4030")
    }

    // MARK: What was connected last

    func testTheMemoryStartsWithLX200AndNoAddresses() {
        let memory = MountConnectionMemory()
        XCTAssertEqual(memory.selectedOptionID, "lx200")
        XCTAssertTrue(memory.forms.isEmpty)
    }

    func testTheMemoryGivesTheDefaultFormForAKindItHasNotSeen() {
        let memory = MountConnectionMemory()
        XCTAssertEqual(memory.form(for: .alpaca), MountConnectionForm(option: .alpaca))
        XCTAssertEqual(memory.form(for: .skyWatcher), MountConnectionForm(option: .skyWatcher))
    }

    func testTheMemoryGivesBackTheFormThatWasStored() {
        var memory = MountConnectionMemory()
        var form = MountConnectionForm(option: .nexstar)
        form.host = "1.2.3.4"
        form.port = 2000
        form.link = .tcp
        memory.forms[MountConnectionOption.nexstar.id] = form
        XCTAssertEqual(memory.form(for: .nexstar), form)
        XCTAssertEqual(memory.form(for: .lx200), MountConnectionForm(option: .lx200))
    }

    func testTheMemoryRoundTripsThroughJSON() throws {
        var memory = MountConnectionMemory()
        memory.selectedOptionID = "alpaca"
        var form = MountConnectionForm(option: .alpaca)
        form.host = "192.168.1.20"
        form.deviceNumber = 1
        form.deviceName = "Mount"
        memory.forms["alpaca"] = form
        memory.forms["lx200"] = MountConnectionForm(option: .lx200)
        let data = try JSONEncoder().encode(memory)
        XCTAssertEqual(try JSONDecoder().decode(MountConnectionMemory.self, from: data), memory)
    }

    func testAnEmptyMemoryDocumentGivesTheDefaults() throws {
        let memory = try decodeMemory("{}")
        XCTAssertEqual(memory, MountConnectionMemory())
    }

    func testAMemoryWithAnOptionIdOfTheWrongTypeFallsBackToLX200() throws {
        let memory = try decodeMemory("{\"selectedOptionID\":42,\"forms\":{}}")
        XCTAssertEqual(memory.selectedOptionID, "lx200")
    }

    func testAnUnknownOptionIdIsKeptAsIs() throws {
        let memory = try decodeMemory("{\"selectedOptionID\":\"future-mount\"}")
        XCTAssertEqual(memory.selectedOptionID, "future-mount")
    }

    func testOneDamagedFormDropsAllTheFormsButNotTheSelection() throws {
        let json = """
            {"selectedOptionID":"alpaca","forms":{"alpaca":{"host":"h","port":1,"link":"http"},"lx200":{"host":"only a host"}}}
            """
        let memory = try decodeMemory(json)
        XCTAssertEqual(memory.selectedOptionID, "alpaca")
        XCTAssertTrue(memory.forms.isEmpty)
    }

    func testFormsOfTheWrongShapeAreIgnored() throws {
        XCTAssertTrue(try decodeMemory("{\"forms\":[1,2,3]}").forms.isEmpty)
        XCTAssertTrue(try decodeMemory("{\"forms\":\"none\"}").forms.isEmpty)
    }

    // MARK: Settings

    func testTheSettingsStartWithSafeDefaults() {
        let settings = MountUserSettings()
        XCTAssertEqual(settings.altitudeLimit, 5.0)
        XCTAssertEqual(settings.nudgeRate, .center)
        XCTAssertTrue(settings.sendsSiteAndTime)
        XCTAssertEqual(settings.maximumSyncOffset, 180.0)
        XCTAssertEqual(settings.slewTimeout, 300.0)
        XCTAssertEqual(settings.epochChoice, .automatic)
        XCTAssertFalse(settings.reversesEastWest)
        XCTAssertEqual(settings.arrangement, .automatic)
        XCTAssertFalse(settings.reversesAxis1)
        XCTAssertFalse(settings.reversesAxis2)
        XCTAssertEqual(MountUserSettings.altitudeLimitRange, -10.0...60.0)
    }

    func testTheEngineSettingsCarryTheLimitsAndTimings() {
        var settings = MountUserSettings()
        settings.altitudeLimit = 12.5
        settings.slewTimeout = 120
        settings.maximumSyncOffset = 8
        let engine = settings.engineSettings
        XCTAssertEqual(engine.altitudeLimit, 12.5)
        XCTAssertEqual(engine.maximumSlewSeconds, 120)
        XCTAssertEqual(engine.maximumSyncOffsetDegrees, 8)
        // What the settings do not hold keeps the engine's own value.
        XCTAssertEqual(engine.horizonLookaheadSeconds, MountSettings.standard.horizonLookaheadSeconds)
        XCTAssertEqual(engine.sunExclusionDegrees, MountSettings.standard.sunExclusionDegrees)
    }

    func testTheEngineSettingsOfTheDefaultsAreTheDefaultsOfTheScreen() {
        let engine = MountUserSettings().engineSettings
        XCTAssertEqual(engine.altitudeLimit, 5.0)
        XCTAssertEqual(engine.maximumSlewSeconds, 300.0)
        XCTAssertEqual(engine.maximumSyncOffsetDegrees, 180.0)
    }

    func testSettingsRoundTripThroughJSON() throws {
        var settings = MountUserSettings()
        settings.altitudeLimit = -3.5
        settings.nudgeRate = .find
        settings.sendsSiteAndTime = false
        settings.maximumSyncOffset = 20
        settings.slewTimeout = 90
        settings.epochChoice = .j2000
        settings.reversesEastWest = true
        settings.arrangement = .equatorial
        settings.reversesAxis1 = true
        settings.reversesAxis2 = true
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(MountUserSettings.self, from: data), settings)
    }

    func testAnEmptySettingsDocumentGivesTheDefaults() throws {
        XCTAssertEqual(try decodeSettings("{}"), MountUserSettings())
    }

    func testAMissingSettingNeverLosesTheOthers() throws {
        let settings = try decodeSettings("{\"altitudeLimit\":15,\"reversesEastWest\":true}")
        XCTAssertEqual(settings.altitudeLimit, 15)
        XCTAssertTrue(settings.reversesEastWest)
        XCTAssertEqual(settings.slewTimeout, 300)
        XCTAssertEqual(settings.nudgeRate, .center)
        XCTAssertTrue(settings.sendsSiteAndTime)
    }

    func testTheAltitudeLimitIsHeldToItsRange() throws {
        XCTAssertEqual(try decodeSettings("{\"altitudeLimit\":-10}").altitudeLimit, -10)
        XCTAssertEqual(try decodeSettings("{\"altitudeLimit\":60}").altitudeLimit, 60)
        XCTAssertEqual(try decodeSettings("{\"altitudeLimit\":-10.5}").altitudeLimit, -10)
        XCTAssertEqual(try decodeSettings("{\"altitudeLimit\":60.5}").altitudeLimit, 60)
        XCTAssertEqual(try decodeSettings("{\"altitudeLimit\":-500}").altitudeLimit, -10)
        XCTAssertEqual(try decodeSettings("{\"altitudeLimit\":90}").altitudeLimit, 60)
        XCTAssertEqual(try decodeSettings("{\"altitudeLimit\":0}").altitudeLimit, 0)
    }

    func testTheSyncOffsetIsHeldBetweenATenthAndAHalfTurn() throws {
        XCTAssertEqual(try decodeSettings("{\"maximumSyncOffset\":0.1}").maximumSyncOffset, 0.1)
        XCTAssertEqual(try decodeSettings("{\"maximumSyncOffset\":180}").maximumSyncOffset, 180)
        XCTAssertEqual(try decodeSettings("{\"maximumSyncOffset\":0.05}").maximumSyncOffset, 0.1)
        XCTAssertEqual(try decodeSettings("{\"maximumSyncOffset\":0}").maximumSyncOffset, 0.1)
        XCTAssertEqual(try decodeSettings("{\"maximumSyncOffset\":-4}").maximumSyncOffset, 0.1)
        XCTAssertEqual(try decodeSettings("{\"maximumSyncOffset\":181}").maximumSyncOffset, 180)
        XCTAssertEqual(try decodeSettings("{\"maximumSyncOffset\":45.5}").maximumSyncOffset, 45.5)
    }

    func testTheSlewTimeoutIsHeldBetweenTenSecondsAndAnHour() throws {
        XCTAssertEqual(try decodeSettings("{\"slewTimeout\":10}").slewTimeout, 10)
        XCTAssertEqual(try decodeSettings("{\"slewTimeout\":3600}").slewTimeout, 3600)
        XCTAssertEqual(try decodeSettings("{\"slewTimeout\":9.9}").slewTimeout, 10)
        XCTAssertEqual(try decodeSettings("{\"slewTimeout\":0}").slewTimeout, 10)
        XCTAssertEqual(try decodeSettings("{\"slewTimeout\":3601}").slewTimeout, 3600)
        XCTAssertEqual(try decodeSettings("{\"slewTimeout\":86400}").slewTimeout, 3600)
        XCTAssertEqual(try decodeSettings("{\"slewTimeout\":600}").slewTimeout, 600)
    }

    func testNumbersThatAreNotFiniteFallBackToTheDefaults() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let json = "{\"altitudeLimit\":\"nan\",\"maximumSyncOffset\":\"inf\",\"slewTimeout\":\"-inf\"}"
        let settings = try decoder.decode(MountUserSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.altitudeLimit, 5.0)
        XCTAssertEqual(settings.maximumSyncOffset, 180.0)
        XCTAssertEqual(settings.slewTimeout, 300.0)
        let other = try decoder.decode(MountUserSettings.self, from: Data("{\"altitudeLimit\":\"-inf\",\"maximumSyncOffset\":\"nan\"}".utf8))
        XCTAssertEqual(other.altitudeLimit, 5.0)
        XCTAssertEqual(other.maximumSyncOffset, 180.0)
    }

    func testValuesOfTheWrongTypeFallBackToTheDefaults() throws {
        let json = """
            {"altitudeLimit":"high","nudgeRate":3,"sendsSiteAndTime":"yes","maximumSyncOffset":[],"slewTimeout":{},\
            "epochChoice":false,"reversesEastWest":"true","arrangement":null,"reversesAxis1":"no","reversesAxis2":[true]}
            """
        XCTAssertEqual(try decodeSettings(json), MountUserSettings())
    }

    func testNamesThatAreNotKnownFallBackToTheDefaults() throws {
        let json = "{\"nudgeRate\":\"warp\",\"epochChoice\":\"jnow\",\"arrangement\":\"polar\"}"
        let settings = try decodeSettings(json)
        XCTAssertEqual(settings.nudgeRate, .center)
        XCTAssertEqual(settings.epochChoice, .automatic)
        XCTAssertEqual(settings.arrangement, .automatic)
    }

    func testEveryNudgeRateAndChoiceCanBeRead() throws {
        for rate in MountNudgeRate.allCases {
            XCTAssertEqual(try decodeSettings("{\"nudgeRate\":\"\(rate.rawValue)\"}").nudgeRate, rate)
        }
        for choice in MountEpochChoice.allCases {
            XCTAssertEqual(try decodeSettings("{\"epochChoice\":\"\(choice.rawValue)\"}").epochChoice, choice)
        }
        for choice in MountArrangementChoice.allCases {
            XCTAssertEqual(try decodeSettings("{\"arrangement\":\"\(choice.rawValue)\"}").arrangement, choice)
        }
    }

    func testTheBooleansOfADocumentAreRead() throws {
        let settings = try decodeSettings("{\"sendsSiteAndTime\":false,\"reversesEastWest\":true,\"reversesAxis1\":true,\"reversesAxis2\":true}")
        XCTAssertFalse(settings.sendsSiteAndTime)
        XCTAssertTrue(settings.reversesEastWest)
        XCTAssertTrue(settings.reversesAxis1)
        XCTAssertTrue(settings.reversesAxis2)
    }

    // MARK: UserDefaults

    func testNothingIsConnectedBeforeTheFirstConnection() {
        XCTAssertFalse(MountPreferences.loadConnectedBefore(from: defaults))
    }

    func testTheFirstConnectionIsRemembered() {
        MountPreferences.saveConnectedBefore(to: defaults)
        XCTAssertTrue(MountPreferences.loadConnectedBefore(from: defaults))
        MountPreferences.saveConnectedBefore(to: defaults)
        XCTAssertTrue(MountPreferences.loadConnectedBefore(from: defaults))
        XCTAssertTrue(defaults.bool(forKey: "lodestar.mount.connectedBefore"))
    }

    func testEmptyDefaultsGiveTheDefaultSettingsAndMemory() {
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults), MountUserSettings())
        XCTAssertEqual(MountPreferences.loadMemory(from: defaults), MountConnectionMemory())
    }

    func testSettingsAreSavedAndLoaded() {
        var settings = MountUserSettings()
        settings.altitudeLimit = 20
        settings.nudgeRate = .slew
        settings.slewTimeout = 45
        settings.arrangement = .altAzimuth
        MountPreferences.save(settings, to: defaults)
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults), settings)
    }

    func testSavingAgainReplacesTheEarlierSettings() {
        var settings = MountUserSettings()
        settings.altitudeLimit = 20
        MountPreferences.save(settings, to: defaults)
        settings.altitudeLimit = 30
        MountPreferences.save(settings, to: defaults)
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults).altitudeLimit, 30)
    }

    func testValuesSavedOutOfRangeComeBackHeldToTheRange() {
        var settings = MountUserSettings()
        settings.altitudeLimit = 99
        settings.slewTimeout = 1
        settings.maximumSyncOffset = 0
        MountPreferences.save(settings, to: defaults)
        let loaded = MountPreferences.loadSettings(from: defaults)
        XCTAssertEqual(loaded.altitudeLimit, 60)
        XCTAssertEqual(loaded.slewTimeout, 10)
        XCTAssertEqual(loaded.maximumSyncOffset, 0.1)
    }

    func testTheMemoryIsSavedAndLoaded() {
        var memory = MountConnectionMemory()
        memory.selectedOptionID = "skywatcher"
        var form = MountConnectionForm(option: .skyWatcher)
        form.host = "10.1.2.3"
        memory.forms["skywatcher"] = form
        MountPreferences.save(memory, to: defaults)
        XCTAssertEqual(MountPreferences.loadMemory(from: defaults), memory)
    }

    func testSettingsAndMemoryAreKeptApart() {
        var settings = MountUserSettings()
        settings.altitudeLimit = 33
        MountPreferences.save(settings, to: defaults)
        XCTAssertEqual(MountPreferences.loadMemory(from: defaults), MountConnectionMemory())
        var memory = MountConnectionMemory()
        memory.selectedOptionID = "nexstar"
        MountPreferences.save(memory, to: defaults)
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults).altitudeLimit, 33)
        XCTAssertEqual(MountPreferences.loadMemory(from: defaults).selectedOptionID, "nexstar")
    }

    func testTheStoredKeysDoNotChange() {
        MountPreferences.save(MountUserSettings(), to: defaults)
        MountPreferences.save(MountConnectionMemory(), to: defaults)
        MountPreferences.saveConnectedBefore(to: defaults)
        XCTAssertNotNil(defaults.data(forKey: "lodestar.mount.settings"))
        XCTAssertNotNil(defaults.data(forKey: "lodestar.mount.connection"))
        XCTAssertTrue(defaults.bool(forKey: "lodestar.mount.connectedBefore"))
    }

    func testSettingsAreStoredAsJSONThatAnEarlierVersionWrote() {
        // A document from a version that knew fewer settings, as it would be on disk.
        defaults.set(Data("{\"altitudeLimit\":10,\"nudgeRate\":\"guide\"}".utf8), forKey: "lodestar.mount.settings")
        let loaded = MountPreferences.loadSettings(from: defaults)
        XCTAssertEqual(loaded.altitudeLimit, 10)
        XCTAssertEqual(loaded.nudgeRate, .guide)
        XCTAssertEqual(loaded.slewTimeout, 300)
        XCTAssertFalse(loaded.reversesAxis1)
    }

    func testDamagedStoredSettingsGiveTheDefaults() {
        defaults.set(Data("this is not JSON".utf8), forKey: "lodestar.mount.settings")
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults), MountUserSettings())
        defaults.set(Data(), forKey: "lodestar.mount.settings")
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults), MountUserSettings())
        defaults.set(Data("[1,2,3]".utf8), forKey: "lodestar.mount.settings")
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults), MountUserSettings())
        defaults.set(Data("\"text\"".utf8), forKey: "lodestar.mount.settings")
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults), MountUserSettings())
    }

    func testDamagedStoredMemoryGivesTheDefaults() {
        defaults.set(Data("{\"selectedOptionID\":".utf8), forKey: "lodestar.mount.connection")
        XCTAssertEqual(MountPreferences.loadMemory(from: defaults), MountConnectionMemory())
        defaults.set(Data("null".utf8), forKey: "lodestar.mount.connection")
        XCTAssertEqual(MountPreferences.loadMemory(from: defaults), MountConnectionMemory())
    }

    func testSomethingOtherThanDataUnderTheKeyIsIgnored() {
        defaults.set(12, forKey: "lodestar.mount.settings")
        XCTAssertEqual(MountPreferences.loadSettings(from: defaults), MountUserSettings())
        defaults.set(true, forKey: "lodestar.mount.connection")
        XCTAssertEqual(MountPreferences.loadMemory(from: defaults), MountConnectionMemory())
    }
}
