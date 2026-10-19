import SwiftUI

/// The Settings tab: observing location, phone mount, camera and lens, night mode and the other preferences, the
/// photography tools, and About.
struct SettingsView: View {
    @Environment(\.palette) private var palette
    /// What the Location section asks to present. Its sheets hang on the form, which is always on screen.
    @State private var locationPresentation = SettingsLocationPresentation()

    var body: some View {
        NavigationStack {
            Form {
                SettingsHelpSection()
                SettingsLocationSection(presentation: $locationPresentation)
                SettingsMountSection()
                SettingsMountControlSection()
                SettingsCameraSection()
                SettingsNightSection()
                SettingsFeedbackSection()
                SettingsSkyDisplaySection()
                SettingsAtmosphereSection()
                SettingsOnlineDataSection()
                SettingsToolsSection()
                SettingsAboutSection()
            }
            .settingsLocationSheets($locationPresentation)
            .themedList(palette)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .nightInlineTitle()
        }
    }
}
