import SwiftUI
import LodestarKit

/// Settings ▸ Feedback: haptics, audio cues and keeping the screen awake while aiming.
struct SettingsFeedbackSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsSection(title: "Feedback") {
            SettingsToggleRow(
                title: "Haptics",
                caption: "A tap when the camera reaches the target and when it leaves it.",
                isOn: $store.settings.hapticsEnabled)
            SettingsToggleRow(
                title: "Audio cues",
                caption: "Ticks that speed up and rise in pitch as the camera nears the target, and a chime on target. "
                    + "The Silent switch mutes them.",
                isOn: $store.settings.audioCuesEnabled)
            SettingsToggleRow(
                title: "Keep screen awake",
                caption: "Stops the iPhone from locking while the Aim screen is open.",
                isOn: $store.settings.keepScreenAwake)
        }
    }
}

/// Settings ▸ Sky Display: what the Aim screen and the sky chart draw.
struct SettingsSkyDisplaySection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsSection(title: "Sky Display") {
            Toggle("Constellation lines", isOn: $store.settings.showConstellationLines)
            Toggle("Constellation names", isOn: $store.settings.showConstellationNames)
            Toggle("Deep-sky objects", isOn: $store.settings.showDeepSkyObjects)
            Toggle("Milky Way", isOn: $store.settings.showMilkyWay)
            VStack(alignment: .leading, spacing: 4) {
                SettingsSliderRow(title: "Faintest stars",
                                  valueText: AppFormat.magnitude(store.settings.starMagnitudeLimit),
                                  value: $store.settings.starMagnitudeLimit, range: 1...6.5, step: 0.5)
                SettingsCaption("Stars fainter than this are left out. Under a dark sky the eye reaches about "
                                + "magnitude 6.")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Coordinates")
                    .accessibilityHidden(true)
                Picker("Coordinates", selection: $store.settings.coordinateStyle) {
                    ForEach(CoordinateStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

/// Settings ▸ Atmosphere: the weather values that decide how much the air lifts objects near the horizon.
struct SettingsAtmosphereSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsSection(
            title: "Atmosphere",
            footer: "The air bends light, so objects near the horizon look higher than they are. Lodestar corrects for "
                + "it with these values; the defaults (10\u{00A0}\u{00B0}C, 1010\u{00A0}hPa) suit most places.") {
            SettingsNumberField(title: "Temperature", unit: "\u{00B0}C", value: $store.settings.temperatureCelsius,
                                range: -60...60, fractionDigits: 0)
            SettingsNumberField(title: "Pressure", unit: "hPa", value: $store.settings.pressureMillibars,
                                range: 300...1100, fractionDigits: 0)
        }
    }
}

/// Settings ▸ Tools: links to the exposure calculator and the polar alignment helper.
struct SettingsToolsSection: View {
    var body: some View {
        SettingsSection(title: "Tools") {
            NavigationLink {
                ExposureCalculatorView()
            } label: {
                Label("Exposure Calculator", systemImage: "timer")
            }
            NavigationLink {
                PolarAlignmentView()
            } label: {
                Label("Polar Alignment", systemImage: "sparkle")
            }
        }
    }
}
