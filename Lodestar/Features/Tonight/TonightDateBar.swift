import SwiftUI

/// The night selector: previous and next night buttons around the date, which opens the calendar.
struct TonightDateBar: View {
    @Environment(\.palette) private var palette

    /// The date the night starts on, such as "Fri, Oct 17".
    let title: String
    /// How far the night is from tonight, such as "Tomorrow night".
    let subtitle: String
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void
    let pickDate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            stepButton(systemImage: "chevron.left", label: "Previous night", isEnabled: canGoBack, action: goBack)
            Button(action: pickDate) {
                VStack(spacing: 2) {
                    Text("Night of \(title)")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Label(subtitle, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Night of \(title), \(subtitle)")
            .accessibilityHint("Opens a calendar to choose another night")
            stepButton(systemImage: "chevron.right", label: "Next night", isEnabled: canGoForward, action: goForward)
        }
    }

    private func stepButton(systemImage: String, label: String, isEnabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.lodestarSecondary)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
