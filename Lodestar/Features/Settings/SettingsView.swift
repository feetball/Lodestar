import SwiftUI

/// The Settings tab: observing location, phone mount, camera and lens, night mode and the other preferences, the
/// photography tools, and About.
struct SettingsView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            Form {
                SettingsLocationSection()
                SettingsMountSection()
                SettingsCameraSection()
                SettingsNightSection()
                SettingsFeedbackSection()
                SettingsSkyDisplaySection()
                SettingsAtmosphereSection()
                SettingsToolsSection()
                SettingsAboutSection()
            }
            .themedList(palette)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
        }
    }
}
