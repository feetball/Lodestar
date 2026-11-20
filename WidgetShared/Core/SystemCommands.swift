import Foundation

/// How a request changes night mode.
enum NightModeChange: String, Sendable, CaseIterable {
    case toggle
    case on
    case off

    /// Whether night mode is to be on afterwards. `isOn` says whether the setting is "On" now; "After Sunset" counts
    /// as not on, so a toggle then switches night mode on for good and the next toggle switches it off. The Android
    /// quick settings tile follows the same rule.
    func resultingIsOn(currentlyOn isOn: Bool) -> Bool {
        switch self {
        case .toggle: return !isOn
        case .on: return true
        case .off: return false
        }
    }
}

/// What an intent, a Control Center control or a shortcut asks the app to do once it is running.
enum LodestarCommand: Sendable, Equatable {
    /// Show the Aim tab.
    case showAim
    /// Show the red torch.
    case showTorch
    /// Change night mode.
    case nightMode(NightModeChange)
    /// Make the object with this catalog identifier the target and show the Aim tab.
    case aim(objectID: String)
}

/// Hands commands from intents to the app. An intent that opens the app can run before the app model exists (a cold
/// start), so commands wait here until the app attaches its handler, and are delivered in the order they came.
@MainActor
final class LodestarCommandCenter {
    static let shared = LodestarCommandCenter()

    /// The most commands kept while nothing handles them; the oldest are dropped first.
    static let maximumPending = 8

    private var pending: [LodestarCommand] = []
    private var handler: ((LodestarCommand) -> Void)?

    init() {}

    /// Delivers `command` to the handler, or keeps it until there is one.
    func submit(_ command: LodestarCommand) {
        if let handler {
            handler(command)
            return
        }
        pending.append(command)
        if pending.count > Self.maximumPending { pending.removeFirst(pending.count - Self.maximumPending) }
    }

    /// Sets the handler (replacing an earlier one) and delivers what has been waiting.
    func attach(_ handler: @escaping (LodestarCommand) -> Void) {
        self.handler = handler
        let waiting = pending
        pending = []
        for command in waiting { handler(command) }
    }
}

/// What a tap does to the red torch: red to a question about white light, the question to red again (a tap elsewhere
/// is no yes), white back to red at once. Only the confirmation turns it white.
enum TorchLight: Sendable, Equatable {
    case red
    case confirmingWhite
    case white

    var afterTap: TorchLight {
        switch self {
        case .red: return .confirmingWhite
        case .confirmingWhite, .white: return .red
        }
    }

    var afterConfirm: TorchLight {
        self == .confirmingWhite ? .white : self
    }

    var afterCancel: TorchLight {
        self == .confirmingWhite ? .red : self
    }
}
