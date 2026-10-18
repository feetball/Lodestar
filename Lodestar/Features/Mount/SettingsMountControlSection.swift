import SwiftUI

/// Settings ▸ GoTo Mount: the way into the mount connection screen, with the state of the connection on the row.
struct SettingsMountControlSection: View {
    @Environment(\.palette) private var palette
    private var service: MountService { MountService.shared }

    private static let footer = """
        Send a computerised GoTo mount to the Aim target, sync it on a centred star and nudge it. \
        Connects over Wi-Fi. After the first connection, Aim shows a Mount button.
        """

    var body: some View {
        SettingsSection(
            title: "GoTo Mount",
            footer: Self.footer) {
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
