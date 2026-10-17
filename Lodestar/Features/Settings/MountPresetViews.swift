import SwiftUI
import LodestarKit

/// One mount preset as a row: its picture, name and description, and a check mark when it is the chosen one.
struct MountPresetRowLabel: View {
    @Environment(\.palette) private var palette
    let profile: MountProfile
    var isSelected = false
    /// Whether to reserve room for the check mark (off for a summary row that only shows the current mount).
    var showsSelection = true

    var body: some View {
        HStack(spacing: 14) {
            MountIllustration(layout: MountLayout(profile))
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.primaryText)
                Text(MountLayout(profile).summary)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if showsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The list of mount presets; choosing one stores it in the settings. Changing the mount clears the star alignment.
struct MountPresetPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            SettingsSection(
                title: "Phone Mount",
                footer: "Choose how the phone is clamped to the camera. Lodestar uses it to work out which way the "
                    + "camera points and which way the arrows turn. Changing it clears your star alignment.") {
                ForEach(MountProfile.presets) { profile in
                    Button {
                        app.settingsStore.settings.mountPresetID = profile.id
                    } label: {
                        MountPresetRowLabel(profile: profile, isSelected: profile.id == app.mountProfile.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .themedList(palette)
        .navigationTitle("Phone Mount")
        .navigationBarTitleDisplayMode(.inline)
    }
}
