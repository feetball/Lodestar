import SwiftUI
import LodestarKit

/// Settings ▸ Mount: how the phone is clamped to the camera, where the heading comes from, how much the arrows are
/// smoothed, and the state of the star alignment.
struct SettingsMountSection: View {
    /// Time constants below this many seconds switch smoothing off.
    private static let smoothingOffBelow = 0.01

    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        SettingsSection(title: "Mount", footer: "Changing the mount or the heading source clears the star alignment.") {
            NavigationLink {
                MountPresetPickerView()
            } label: {
                MountPresetRowLabel(profile: app.mountProfile, showsSelection: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Heading source")
                    .accessibilityHidden(true)
                ThemedSegmentedPicker("Heading source", selection: $store.settings.headingSource,
                                      options: HeadingSource.allCases, label: \.title)
                SettingsCaption(Self.explanation(of: store.settings.headingSource))
            }
            SettingsSliderRow(title: "Smoothing", valueText: Self.smoothingText(store.settings.smoothingTimeConstant),
                              value: $store.settings.smoothingTimeConstant, range: 0...0.5, step: 0.01)
            SettingsCaption("Less smoothing follows the camera faster; more smoothing steadies the arrows against "
                            + "shaky readings. 0.12 s suits most mounts.")
            SettingsAlignmentStatus()
        }
    }

    private static func explanation(of source: HeadingSource) -> String {
        switch source {
        case .compass:
            return "Reads the iPhone's compass and turns it into true north with the World Magnetic Model. It works at "
                + "once, but metal and electronics near the phone can pull it off by several degrees."
        case .gyroLock:
            return "Copies the compass heading to the gyroscope once the phone holds still, then ignores the compass, "
                + "so tripod heads and camera bodies can no longer disturb it. Hold the phone steady for a moment "
                + "after opening the Aim screen. The heading drifts slowly; align on a star again if it does."
        }
    }

    private static func smoothingText(_ seconds: Double) -> String {
        guard seconds >= smoothingOffBelow else { return "Off" }
        return "\(seconds.formatted(.number.precision(.fractionLength(2)))) s"
    }
}

/// The star alignment at a glance, with a button to throw it away.
private struct SettingsAlignmentStatus: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let alignment = app.alignment
        if alignment.isAligned {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    StatusChip(systemImage: "checkmark.seal", text: "Aligned", tone: .positive)
                    Spacer(minLength: 0)
                }
                InfoRow(label: "Reference points", value: "\(alignment.points.count)")
                InfoRow(label: "Fit residual (RMS)",
                        value: AngleFormatter.formatDegrees(alignment.rmsResidual, decimals: 2))
                if let uncertainty = alignment.pointingUncertainty {
                    InfoRow(label: "Expected pointing error",
                            value: "\u{00B1}" + AngleFormatter.formatDegrees(uncertainty, decimals: 1))
                }
                InfoRow(label: "Compass correction",
                        value: AngleFormatter.formatSignedDegrees(alignment.headingOffset, decimals: 1))
                InfoRow(label: "Bracket tilt correction",
                        value: AngleFormatter.formatDegrees(alignment.deviceCorrection.length, decimals: 1))
            }
            Button("Reset Alignment") {
                app.resetAlignment()
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    StatusChip(systemImage: "scope", text: "Not aligned", tone: .neutral)
                    Spacer(minLength: 0)
                }
                SettingsCaption("On the Aim screen, tap Align and center a bright star, a planet or the Moon in the "
                                + "camera. One point corrects the heading; several points at different heights in "
                                + "the sky also correct the tilt of the bracket.")
            }
        }
    }
}
