import SwiftUI

/// Settings ▸ GoTo Mount: the way into the mount connection screen, with the state of the connection on the row.
struct SettingsMountControlSection: View {
    @Environment(\.palette) private var palette
    private var service: MountService { MountService.shared }

    var body: some View {
        SettingsSection(
            title: "GoTo Mount",
            footer: "Drive a computerised telescope mount over Wi-Fi from the Aim screen: GoTo, sync, nudge and stop.") {
            NavigationLink {
                MountConnectionView()
            } label: {
                HStack(spacing: 8) {
                    Label("Mount Control", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer(minLength: 8)
                    Text(service.summaryText)
                        .font(.subheadline)
                        .foregroundStyle(service.isConnected ? palette.positive : palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .accessibilityValue(service.summaryText)
        }
    }
}
