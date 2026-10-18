import Foundation
import LodestarKit

/// The address typed for one kind of mount.
struct MountConnectionForm: Codable, Equatable, Sendable {
    var host: String
    var port: Int
    var link: MountLinkKind
    /// Which telescope of an Alpaca server to drive.
    var deviceNumber = 0
    var deviceName: String?

    /// The defaults of `option`.
    init(option: MountConnectionOption) {
        host = option.defaultHost
        port = option.defaultPort
        link = option.defaultLink
    }

    private enum CodingKeys: String, CodingKey {
        case host, port, link, deviceNumber, deviceName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        link = try container.decode(MountLinkKind.self, forKey: .link)
        deviceNumber = (try? container.decode(Int.self, forKey: .deviceNumber)) ?? 0
        deviceName = try? container.decode(String.self, forKey: .deviceName)
    }

    /// What a connection to this address is called on screen: the host and port, or the device's name.
    var addressText: String {
        let address = MountAddress(text: host, defaultPort: port)
        return "\(address.host):\(address.port)"
    }
}

/// The last connection, remembered between launches: which kind of mount, and the address typed for each kind.
struct MountConnectionMemory: Codable, Equatable, Sendable {
    var selectedOptionID = MountConnectionOption.lx200.id
    var forms: [String: MountConnectionForm] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case selectedOptionID, forms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedOptionID = (try? container.decode(String.self, forKey: .selectedOptionID)) ?? Self.defaultOptionID
        forms = (try? container.decode([String: MountConnectionForm].self, forKey: .forms)) ?? [:]
    }

    private static let defaultOptionID = MountConnectionOption.lx200.id

    func form(for option: MountConnectionOption) -> MountConnectionForm {
        forms[option.id] ?? MountConnectionForm(option: option)
    }
}

/// The picks that outlive a connection: limits, speeds and the options of the connection screen.
struct MountUserSettings: Codable, Equatable, Sendable {
    static let altitudeLimitRange: ClosedRange<Double> = -10...60

    /// Targets below this geometric altitude are never sent to the mount, degrees.
    var altitudeLimit = 5.0
    var nudgeRate = MountNudgeRate.center
    /// Send the phone's location and clock to the mount when connecting.
    var sendsSiteAndTime = true
    /// A sync that would move the mount by more than this is refused, degrees; 180 allows everything.
    var maximumSyncOffset = 180.0
    /// A slew that takes longer than this is stopped, seconds.
    var slewTimeout = 300.0
    var epochChoice = MountEpochChoice.automatic
    var reversesEastWest = false

    /// The limits and timings the engine's controller runs with.
    var engineSettings: MountSettings {
        MountSettings(altitudeLimit: altitudeLimit, maximumSlewSeconds: slewTimeout,
                      maximumSyncOffsetDegrees: maximumSyncOffset)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case altitudeLimit, nudgeRate, sendsSiteAndTime, maximumSyncOffset, slewTimeout, epochChoice, reversesEastWest
    }

    /// Missing or invalid values fall back to the defaults, so a new setting never loses the others.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MountUserSettings()
        let limit = (try? container.decode(Double.self, forKey: .altitudeLimit)) ?? defaults.altitudeLimit
        altitudeLimit = limit.isFinite
            ? min(max(limit, Self.altitudeLimitRange.lowerBound), Self.altitudeLimitRange.upperBound)
            : defaults.altitudeLimit
        nudgeRate = (try? container.decode(MountNudgeRate.self, forKey: .nudgeRate)) ?? defaults.nudgeRate
        sendsSiteAndTime = (try? container.decode(Bool.self, forKey: .sendsSiteAndTime)) ?? defaults.sendsSiteAndTime
        let offset = (try? container.decode(Double.self, forKey: .maximumSyncOffset)) ?? defaults.maximumSyncOffset
        maximumSyncOffset = offset.isFinite ? min(max(offset, 0.1), 180) : defaults.maximumSyncOffset
        let timeout = (try? container.decode(Double.self, forKey: .slewTimeout)) ?? defaults.slewTimeout
        slewTimeout = timeout.isFinite ? min(max(timeout, 10), 3_600) : defaults.slewTimeout
        epochChoice = (try? container.decode(MountEpochChoice.self, forKey: .epochChoice)) ?? defaults.epochChoice
        reversesEastWest = (try? container.decode(Bool.self, forKey: .reversesEastWest)) ?? defaults.reversesEastWest
    }
}

/// Reads and writes the mount preferences in `UserDefaults`.
enum MountPreferences {
    private static let settingsKey = "lodestar.mount.settings"
    private static let connectionKey = "lodestar.mount.connection"
    private static let connectedBeforeKey = "lodestar.mount.connectedBefore"

    /// Whether a connection to a mount (the simulated one included) has ever succeeded.
    static func loadConnectedBefore(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: connectedBeforeKey)
    }

    static func saveConnectedBefore(to defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: connectedBeforeKey)
    }

    static func loadSettings(from defaults: UserDefaults = .standard) -> MountUserSettings {
        load(MountUserSettings.self, key: settingsKey, from: defaults) ?? MountUserSettings()
    }

    static func save(_ settings: MountUserSettings, to defaults: UserDefaults = .standard) {
        store(settings, key: settingsKey, to: defaults)
    }

    static func loadMemory(from defaults: UserDefaults = .standard) -> MountConnectionMemory {
        load(MountConnectionMemory.self, key: connectionKey, from: defaults) ?? MountConnectionMemory()
    }

    static func save(_ memory: MountConnectionMemory, to defaults: UserDefaults = .standard) {
        store(memory, key: connectionKey, to: defaults)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func store<Value: Encodable>(_ value: Value, key: String, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
