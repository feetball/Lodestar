import SwiftUI
import LodestarKit

/// Settings ▸ Great Red Spot: the spot's System II longitude, which times its transits in the events calendar and on
/// Jupiter's screen. Empty means the kit's dated default; a number counts from the day it was entered.
struct SettingsJupiterSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let today = Date()
        let override = app.settings.greatRedSpot
        let current = override?.spot ?? .reference
        let longitude = Binding<Double?>(
            get: { app.settings.greatRedSpot?.longitude },
            set: { value in
                app.settingsStore.settings.greatRedSpot = value.map { GreatRedSpotSetting(longitude: $0, asOf: Date()) }
            })
        SettingsSection(
            title: "Great Red Spot",
            footer: "The spot drifts by a few degrees a month, which moves its transit by a few minutes. The default is "
                + "Sky & Telescope\u{2019}s for 2026: \(AngleFormatter.formatDegrees(GreatRedSpot.referenceLongitude, decimals: 0)) "
                + "on June 1, 2026, drifting 1.75\u{00B0} a month, "
                + "\(AngleFormatter.formatDegrees(GreatRedSpot.reference.systemIILongitude(at: today), decimals: 0)) today. "
                + "To use the longitude from a recent image or table, enter it here: it counts from today.") {
            SettingsNumberField(title: "System II longitude", unit: "\u{00B0}", optionalValue: longitude,
                                range: 0...360, fractionDigits: 0, placeholder: "Default")
            SettingsCaption("Now \(AngleFormatter.formatDegrees(current.systemIILongitude(at: today), decimals: 0))"
                            + (override.map { " (yours, entered \(AppFormat.day($0.asOf, in: .autoupdatingCurrent)))" }
                                ?? " (default)"))
            if override != nil {
                Button("Reset to Default") {
                    app.settingsStore.settings.greatRedSpot = nil
                }
            }
        }
    }
}
