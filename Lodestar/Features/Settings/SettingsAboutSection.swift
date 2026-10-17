import SwiftUI

/// Settings ▸ About: version, accuracy notes, the privacy statement, data credits and licences, and the sensor
/// diagnostics.
struct SettingsAboutSection: View {
    @Environment(\.palette) private var palette

    var body: some View {
        SettingsSection(title: "About") {
            InfoRow(label: "Version", value: SettingsAppInfo.versionDescription)
            NavigationLink {
                AccuracyNotesView()
            } label: {
                Label("Accuracy Notes", systemImage: "scope")
            }
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(title: "Privacy", systemImage: "hand.raised")
                Text("Everything Lodestar does happens on your iPhone. There are no accounts, no analytics and no "
                     + "tracking, and Lodestar never collects your location, sites or settings. The only network use "
                     + "is Apple Maps, which loads map tiles when you open the site map, and Apple's geocoding "
                     + "service, which receives a site's coordinates to look up its time zone while you add or edit it.")
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink {
                DataCreditsView()
            } label: {
                Label("Data Credits & Licenses", systemImage: "books.vertical")
            }
            NavigationLink {
                SensorDiagnosticsView()
            } label: {
                Label("Sensor Diagnostics", systemImage: "waveform.path.ecg")
            }
        }
    }
}

/// Facts about the running app taken from its bundle.
enum SettingsAppInfo {
    /// "1.0 (12)": the marketing version and the build number.
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? AppFormat.missing
        let build = info?["CFBundleVersion"] as? String ?? AppFormat.missing
        return "\(version) (\(build))"
    }
}
