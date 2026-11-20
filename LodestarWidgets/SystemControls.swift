import AppIntents
import SwiftUI
import WidgetKit

// Control Center and Lock Screen controls (iOS 18 and later). Each is a button that runs one of the intents of
// `WidgetShared/System/SystemIntents.swift` and opens Lodestar: the app's state (night mode, the torch, the Aim tab) lives
// in the app's own storage, which the extension cannot reach because there is no App Group.

@available(iOS 18.0, *)
struct NightModeControl: ControlWidget {
    static let kind = "net.kuecker.Lodestar.controls.nightMode"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleNightModeIntent()) {
                Label("Night mode", systemImage: "moon.stars")
            }
        }
        .displayName("Night Mode")
        .description("Switches Lodestar's red night mode on or off. Opens Lodestar.")
    }
}

@available(iOS 18.0, *)
struct RedTorchControl: ControlWidget {
    static let kind = "net.kuecker.Lodestar.controls.redTorch"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RedTorchIntent()) {
                Label("Red torch", systemImage: "flashlight.on.fill")
            }
        }
        .displayName("Red Torch")
        .description("Opens Lodestar's red torch, a full-screen red light that keeps your night vision.")
    }
}

@available(iOS 18.0, *)
struct AimControl: ControlWidget {
    static let kind = "net.kuecker.Lodestar.controls.aim"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenAimIntent()) {
                Label("Aim", systemImage: "scope")
            }
        }
        .displayName("Aim")
        .description("Opens Lodestar on the Aim screen.")
    }
}
