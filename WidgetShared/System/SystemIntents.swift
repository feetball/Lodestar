#if os(iOS)
import AppIntents

// The intents that both the app and the widget extension compile: Control Center controls run them from the
// extension, Siri and Shortcuts from the app. Each opens the app and hands a command to `LodestarCommandCenter`; the
// app does the work, because there is no App Group through which the extension could change the app's state.

extension NightModeChange: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Night mode"

    static let caseDisplayRepresentations: [NightModeChange: DisplayRepresentation] = [
        .toggle: "Switch",
        .on: "On",
        .off: "Off",
    ]
}

/// Switches Lodestar's red night mode. Opens the app: the setting lives in the app's own storage, which a Control Center
/// control (it runs in the widget extension) cannot reach without an App Group.
struct ToggleNightModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Night Mode"
    static let description = IntentDescription("Switches Lodestar's red night mode on or off.")
    static let openAppWhenRun = true

    @Parameter(title: "Change", default: .toggle)
    var change: NightModeChange

    init() {}

    init(change: NightModeChange) {
        self.change = change
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        LodestarCommandCenter.shared.submit(.nightMode(change))
        return .result()
    }
}

/// Opens Lodestar on the red torch.
struct RedTorchIntent: AppIntent {
    static let title: LocalizedStringResource = "Red Torch"
    static let description = IntentDescription("Opens Lodestar's red torch: a full-screen red light that keeps your night vision.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        LodestarCommandCenter.shared.submit(.showTorch)
        return .result()
    }
}

/// Opens Lodestar on the Aim screen.
struct OpenAimIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Aim"
    static let description = IntentDescription("Opens Lodestar on the Aim screen.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        LodestarCommandCenter.shared.submit(.showAim)
        return .result()
    }
}
#endif
