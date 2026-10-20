import SwiftUI

/// The app's tab bar, drawn from the palette in day and night mode alike.
///
/// The system tab bar of iOS 26 is a glass that the night palette does not reach: its unselected items stay white. So
/// every tab hides the system bar (`.toolbar(.hidden, for: .tabBar)`) and the `TabView` shows this one in a bottom safe
/// area inset instead. The tabs stay in one `TabView`, so each keeps its state, and the content of every tab ends above
/// the bar.
struct AppTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                AppTabBarButton(tab: tab, isSelected: tab == selection) {
                    selection = tab
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            // The bar's colour runs on under the home indicator; the buttons stay above it.
            palette.surface
                .overlay(alignment: .top) { palette.stroke.frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeOut(duration: 0.15), value: selection)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
    }
}

/// One tab of the bar: its symbol over its title, with a rounded highlight behind them while it is selected.
private struct AppTabBarButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .symbolVariant(iconVariant)
                    .font(.title3)
                Text(tab.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surfaceRaised)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(traits)
    }

    /// The selected tab's symbol is filled, so that the selection does not rest on brightness alone at night.
    private var iconVariant: SymbolVariants { isSelected ? .fill : .none }

    private var traits: AccessibilityTraits { isSelected ? [.isButton, .isSelected] : [.isButton] }
}
