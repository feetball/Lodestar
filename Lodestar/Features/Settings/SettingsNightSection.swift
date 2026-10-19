import SwiftUI

/// Settings ▸ Night Mode: when the red night palette is used, how bright it is, screen dimming, the camera at
/// night, the experimental red overlay, and the guide to iOS Color Filters.
struct SettingsNightSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsSection(
            title: "Night Mode",
            footer: "Night mode draws Lodestar in pure red on black so your eyes stay adapted to the dark.") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Night mode")
                    .accessibilityHidden(true)
                ThemedSegmentedPicker("Night mode", selection: $store.settings.nightMode,
                                      options: NightModeSetting.allCases, label: \.title)
                SettingsCaption(statusText(for: store.settings.nightMode))
            }
            SettingsSliderRow(title: "Red brightness", valueText: AppFormat.percent(store.settings.nightIntensity),
                              value: $store.settings.nightIntensity, range: 0.25...1, step: 0.05)
            SettingsToggleRow(
                title: "Dim the screen",
                caption: "Lowers the screen brightness while night mode is on and gives it back afterwards.",
                isOn: $store.settings.dimScreenAtNight)
            if store.settings.dimScreenAtNight {
                SettingsSliderRow(title: "Screen brightness",
                                  valueText: AppFormat.percent(store.settings.nightBrightness),
                                  value: $store.settings.nightBrightness, range: 0.01...1, step: 0.01)
            }
            SettingsToggleRow(
                title: "Camera preview at night",
                caption: "Shows the camera picture in red tones behind the sky. It is brighter than the sky overlay "
                    + "alone, so it costs some night vision.",
                isOn: $store.settings.cameraPreviewAtNight)
            SettingsToggleRow(
                title: "Red screen overlay (experimental)",
                caption: "Multiplies everything on screen with pure red, so system-drawn colors such as maps and "
                    + "keyboards turn red as well. It may not reach every system view and only works in night mode. "
                    + "Color Filters (below) are more reliable.",
                isOn: $store.settings.redFilterOverlay)
        }
        SettingsSection(title: "Pure Red for the Whole iPhone") {
            ColorFiltersGuideCard(showsTitle: false)
        }
    }

    private func statusText(for mode: NightModeSetting) -> String {
        switch mode {
        case .off:
            return "Normal colors at all times."
        case .on:
            return "Red at all times."
        case .automatic:
            let rule = "Switches on when the Sun is more than 6\u{00B0} below the horizon."
            guard app.observerContext != nil else { return rule }
            return app.isNightModeActive ? "On now. " + rule : "Off now. " + rule
        }
    }
}
