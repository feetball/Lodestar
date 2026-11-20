import AppIntents
import Foundation
import LodestarKit

/// A sky object as Siri and Shortcuts know it: a name to say and a line to tell it from others.
struct CelestialObjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sky Object"
    static let defaultQuery = CelestialObjectQuery()

    /// The catalog identifier, such as `dso.M31`.
    let id: String
    let name: String
    /// A designation and the kind of object, "NGC 224 · Galaxy".
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        if detail.isEmpty { return DisplayRepresentation(title: "\(name)") }
        return DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(_ object: CelestialObject) {
        id = object.id
        name = object.name
        let designation = object.designations.first { $0 != object.name }
        detail = [designation, object.category.displayName].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

/// Finds objects of the loaded catalog by name or designation ("m31", "andromeda", "ngc 7000").
struct CelestialObjectQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CelestialObjectEntity] {
        await LodestarIntentHost.objects(withIDs: identifiers)
    }

    func entities(matching string: String) async throws -> [CelestialObjectEntity] {
        await LodestarIntentHost.objects(matching: string)
    }

    func suggestedEntities() async throws -> [CelestialObjectEntity] {
        await LodestarIntentHost.suggestions()
    }
}

/// "Aim Lodestar at Andromeda": opens the app on Aim with the object as the target.
struct AimAtObjectIntent: AppIntent {
    static let title: LocalizedStringResource = "Aim at Object"
    static let description = IntentDescription("Opens Lodestar on the Aim screen with the chosen object as the target.")
    static let openAppWhenRun = true

    @Parameter(title: "Object", requestValueDialog: "Which object?")
    var target: CelestialObjectEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Aim at \(\.$target)")
    }

    init() {}

    init(target: CelestialObjectEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        LodestarCommandCenter.shared.submit(.aim(objectID: target.id))
        return .result()
    }
}

/// "When is it dark in Lodestar": says tonight's darkness, the Moon and the Milky Way core, without opening the app.
struct DarkTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "When Is It Dark"
    static let description = IntentDescription(
        "Tells you when the sky is dark tonight, when the Moon rises and sets and when the Milky Way core is up.")
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        guard let place = LodestarIntentHost.tonightPlace() else {
            return .result(dialog: "\(DarkTonightWords.noPlace)")
        }
        let sentence = await Task.detached(priority: .userInitiated) {
            DarkTonightWords.sentence(for: place, at: now)
        }.value
        return .result(dialog: "\(sentence)")
    }
}

/// The phrases Siri and the Shortcuts app offer for Lodestar.
struct LodestarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AimAtObjectIntent(),
            phrases: [
                "Aim \(.applicationName) at \(\.$target)",
                "Aim at \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Aim at Object",
            systemImageName: "scope")
        AppShortcut(
            intent: DarkTonightIntent(),
            phrases: [
                "When is it dark in \(.applicationName)",
                "When is it dark tonight in \(.applicationName)",
            ],
            shortTitle: "When Is It Dark",
            systemImageName: "moon.stars")
        AppShortcut(
            intent: ToggleNightModeIntent(change: .on),
            phrases: ["Turn on \(.applicationName) night mode"],
            shortTitle: "Night Mode On",
            systemImageName: "moon.fill")
        AppShortcut(
            intent: RedTorchIntent(),
            phrases: ["\(.applicationName) red torch"],
            shortTitle: "Red Torch",
            systemImageName: "flashlight.on.fill")
    }
}
