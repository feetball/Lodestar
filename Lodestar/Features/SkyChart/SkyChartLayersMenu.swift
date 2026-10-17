import SwiftUI
import LodestarKit

/// The menu that shows and hides the chart's layers.
///
/// It is drawn by the app, not by the system, so it stays red in night mode. The first four layers
/// are the "Sky Display" preferences of the Settings screen, shared with the Aim screen; the rest
/// belong to the chart alone.
struct SkyChartLayersMenu: View {
    /// The range of the "faintest star" setting the menu offers, in magnitudes.
    private static let starLimitRange: ClosedRange<Double> = 3...6.5
    private static let starLimitStep = 0.5

    @Environment(\.palette) private var palette
    @Bindable var store: SettingsStore
    @Binding var showsStarNames: Bool
    @Binding var showsAltitudeGrid: Bool
    @Binding var showsCameraView: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkyChartLayerRow(title: "Constellation lines", isOn: $store.settings.showConstellationLines)
            SkyChartLayerRow(title: "Constellation names", isOn: $store.settings.showConstellationNames)
            SkyChartLayerRow(title: "Milky Way", isOn: $store.settings.showMilkyWay)
            SkyChartLayerRow(title: "Deep-sky objects", isOn: $store.settings.showDeepSkyObjects)
            SkyChartLayerRow(title: "Star names", isOn: $showsStarNames)
            SkyChartLayerRow(title: "Altitude grid", isOn: $showsAltitudeGrid)
            SkyChartLayerRow(title: "Camera view", isOn: $showsCameraView)
            starLimitRow
        }
        .frame(width: 270)
        .card(palette, padding: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
    }

    private var starLimitRow: some View {
        let limit = store.settings.starMagnitudeLimit
        return HStack(spacing: 10) {
            Text("Faintest star")
                .foregroundStyle(palette.primaryText)
            Spacer(minLength: 0)
            stepButton("minus.circle", label: "Show fewer stars", isDisabled: limit <= Self.starLimitRange.lowerBound) {
                setLimit(limit - Self.starLimitStep)
            }
            Text(AppFormat.magnitude(limit))
                .monospacedDigit()
                .foregroundStyle(palette.secondaryText)
                .frame(minWidth: 64)
            stepButton("plus.circle", label: "Show more stars", isDisabled: limit >= Self.starLimitRange.upperBound) {
                setLimit(limit + Self.starLimitStep)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ systemImage: String, label: String, isDisabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(isDisabled ? palette.tertiaryText : palette.accent)
                .frame(minWidth: 36, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }

    private func setLimit(_ value: Double) {
        let range = Self.starLimitRange
        store.settings.starMagnitudeLimit = min(max(value, range.lowerBound), range.upperBound)
    }
}

/// One layer of the menu: a title and a check mark.
private struct SkyChartLayerRow: View {
    @Environment(\.palette) private var palette
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn = !isOn
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? palette.accent : palette.tertiaryText)
                Text(title)
                    .foregroundStyle(palette.primaryText)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
