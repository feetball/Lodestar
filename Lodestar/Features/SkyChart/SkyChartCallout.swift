import SwiftUI
import LodestarKit

/// The card for the selected object: name, type, where it is now, and the actions "Aim" and "Details".
struct SkyChartCallout: View {
    @Environment(\.palette) private var palette
    let selection: SkyChartSelection
    /// Whether the chart shows the present; if not, the position is that of the chart's time.
    let isLive: Bool
    let onAim: () -> Void
    let onDetails: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ObjectIcon(category: selection.object.category)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.object.name)
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(palette.tertiaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            // At large text sizes the position and the buttons stack.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    position
                    Spacer(minLength: 4)
                    actions
                }
                VStack(alignment: .leading, spacing: 8) {
                    position
                    actions
                }
            }
        }
        .card(palette, padding: 12)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onDismiss)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Aim", action: onAim)
                .buttonStyle(.lodestarPrimary)
            Button("Details", action: onDetails)
                .buttonStyle(.lodestarSecondary)
        }
    }

    /// The object's type, constellation and current magnitude.
    private var subtitle: String {
        let object = selection.object
        var parts = [object.category.displayName]
        if let constellation = object.constellationName { parts.append(constellation) }
        if let magnitude = selection.magnitude { parts.append(AppFormat.magnitude(magnitude)) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var position: some View {
        let horizontal = selection.horizontal
        return VStack(alignment: .leading, spacing: 1) {
            Text("Alt \(AppFormat.altitude(horizontal.altitude))")
            Text("Az \(AppFormat.azimuth(horizontal.azimuth))")
            if horizontal.altitude < 0 {
                Text("Below the horizon")
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
            }
            if selection.object.category == .sun {
                Text("Needs a solar filter")
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
            }
            if !isLive {
                Text("At the chart's time")
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryText)
            }
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(palette.primaryText)
        .accessibilityElement(children: .combine)
    }
}
