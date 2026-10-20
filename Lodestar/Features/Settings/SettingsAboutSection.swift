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
                     + "tracking, and Lodestar never collects your location, sites or settings. The network is used by "
                     + "Apple Maps, which loads map tiles when you open the site map, by Apple's geocoding service, "
                     + "which receives a site's coordinates, rounded to about 1 km, to look up its time zone when you "
                     + "add or edit it (and again later if it was saved without a network), and by "
                     + "the optional downloads in Online Data, which are off until you switch them on: CelesTrak, the "
                     + "Minor Planet Center and MET Norway see your IP address, and MET Norway also your location "
                     + "rounded to about 10 km. GoTo mount control talks to the mount on your local network only.")
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
