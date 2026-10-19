import SwiftUI

// Palette-drawn replacements for the bars of iOS 26 (night chrome experiment `ctl`, see `NightChrome`): the tab bar, the
// back button, the Done/Cancel/Save buttons of sheets, the search field of Objects and the large titles. They apply
// only at night on iOS 26; elsewhere the call sites draw the system bars exactly as before. Known gap: with the system
// back button hidden, the swipe from the screen edge no longer pops the screen until the pop gesture is restored.

// MARK: Tab bar

extension View {
    /// Shows the night tab bar under the tab view (only in the `ctl` experiment, and at night). Pair it with
    /// `nightHidesTabBar()` on every tab.
    func nightTabBar(selection: Binding<AppTab>) -> some View {
        modifier(NightTabBarModifier(selection: selection))
    }

    /// Hides the system tab bar of this tab while the night tab bar is shown.
    func nightHidesTabBar() -> some View {
        modifier(NightHideTabBarModifier())
    }
}

private struct NightTabBarModifier: ViewModifier {
    @Binding var selection: AppTab
    @Environment(\.palette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        // Whether the experiment is on does not change while the app runs, so the stack below does not come and go.
        if NightChrome.isEnabled("ctl") {
            VStack(spacing: 0) {
                content
                if palette.isNight {
                    NightTabBar(selection: $selection, palette: palette)
                }
            }
        } else {
            content
        }
    }
}

private struct NightHideTabBarModifier: ViewModifier {
    @Environment(\.palette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if NightChrome.isActive("ctl", night: palette.isNight) {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
        }
    }
}

/// The five tabs as a flat bar: the selected one in the accent colour, the others dim, on the surface colour.
struct NightTabBar: View {
    @Binding var selection: AppTab
    let palette: Palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .background(palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.stroke)
                .frame(height: 0.5)
        }
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22))
                    .frame(height: 26)
                Text(tab.title)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
            .frame(maxWidth: .infinity, minHeight: 49)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
    }
}

// MARK: Back button

extension View {
    /// Replaces the glass back button of a pushed screen by a plain chevron in the accent colour (night, iOS 26,
    /// experiment `ctl`). Does nothing otherwise.
    @ViewBuilder
    func nightBackButton() -> some View {
        if #available(iOS 26, *) {
            modifier(NightBackButtonModifier())
        } else {
            self
        }
    }
}

@available(iOS 26, *)
private struct NightBackButtonModifier: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @ViewBuilder
    func body(content: Content) -> some View {
        if NightChrome.isActive("ctl", night: palette.isNight) {
            content
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    NightBackToolbar(palette: palette) { dismiss() }
                }
        } else {
            content
        }
    }
}

@available(iOS 26, *)
private struct NightBackToolbar: ToolbarContent {
    let palette: Palette
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.accent)
            }
            .accessibilityLabel("Back")
        }
        // No shared glass capsule behind the button: it is grey.
        .sharedBackgroundVisibility(.hidden)
    }
}

// MARK: Sheet buttons

extension View {
    /// The Cancel and Done/Save buttons of a sheet's navigation bar. By day and before iOS 26 they are the system
    /// buttons; at night on iOS 26 (experiment `ctl`) they are accent-coloured text without the grey glass capsule.
    /// - Parameters:
    ///   - cancel: The title of the Cancel button, or `nil` for none.
    ///   - confirm: The title of the confirming button.
    ///   - isBusy: Shows a spinner in place of the confirming button.
    ///   - canConfirm: Whether the confirming button is enabled.
    func sheetToolbar(cancel: String? = nil, confirm: String, isBusy: Bool = false, canConfirm: Bool = true,
                      onCancel: @escaping () -> Void = {}, onConfirm: @escaping () -> Void) -> some View {
        modifier(SheetToolbarModifier(items: SheetToolbarItems(cancel: cancel, confirm: confirm, isBusy: isBusy,
                                                               canConfirm: canConfirm, onCancel: onCancel,
                                                               onConfirm: onConfirm)))
    }
}

private struct SheetToolbarItems {
    let cancel: String?
    let confirm: String
    let isBusy: Bool
    let canConfirm: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
}

private struct SheetToolbarModifier: ViewModifier {
    let items: SheetToolbarItems
    @Environment(\.palette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if NightChrome.isActive("ctl", night: palette.isNight) {
                content.toolbar { NightSheetToolbar(items: items, palette: palette) }
            } else {
                content.toolbar { SheetToolbar(items: items, palette: palette) }
            }
        } else {
            content.toolbar { SheetToolbar(items: items, palette: palette) }
        }
    }
}

private struct SheetToolbar: ToolbarContent {
    let items: SheetToolbarItems
    let palette: Palette

    var body: some ToolbarContent {
        if let cancel = items.cancel {
            ToolbarItem(placement: .cancellationAction) {
                Button(cancel, action: items.onCancel)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if items.isBusy {
                ProgressView()
                    .tint(palette.accent)
            } else {
                Button(items.confirm, action: items.onConfirm)
                    .disabled(!items.canConfirm)
            }
        }
    }
}

@available(iOS 26, *)
private struct NightSheetToolbar: ToolbarContent {
    let items: SheetToolbarItems
    let palette: Palette

    var body: some ToolbarContent {
        if let cancel = items.cancel {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: items.onCancel) {
                    Text(cancel)
                        .foregroundStyle(palette.accent)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarItem(placement: .confirmationAction) {
            if items.isBusy {
                ProgressView()
                    .tint(palette.accent)
            } else {
                Button(action: items.onConfirm) {
                    Text(items.confirm)
                        .fontWeight(.semibold)
                        .foregroundStyle(items.canConfirm ? palette.accent : palette.tertiaryText)
                }
                .disabled(!items.canConfirm)
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

// MARK: Search and titles

extension View {
    /// A search field in the navigation bar by day and before iOS 26 (`searchable`); at night on iOS 26 (experiment
    /// `ctl`) the palette-drawn `nightBar` under the navigation bar instead, because the system field is grey.
    func nightSearchable<Bar: View>(text: Binding<String>, prompt: String,
                                    @ViewBuilder nightBar: () -> Bar) -> some View {
        modifier(NightSearchableModifier(text: text, prompt: prompt, nightBar: nightBar()))
    }

    /// An inline navigation title at night on iOS 26 (experiment `ctl`); the large title of the system bar is not
    /// drawn there. The automatic style otherwise.
    func nightInlineTitle() -> some View {
        modifier(NightInlineTitleModifier())
    }
}

private struct NightSearchableModifier<Bar: View>: ViewModifier {
    @Binding var text: String
    let prompt: String
    let nightBar: Bar
    @Environment(\.palette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if NightChrome.isActive("ctl", night: palette.isNight) {
            content.safeAreaInset(edge: .top, spacing: 0) { nightBar }
        } else {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        }
    }
}

private struct NightInlineTitleModifier: ViewModifier {
    @Environment(\.palette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if NightChrome.isActive("ctl", night: palette.isNight) {
            content.navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}

/// A search field drawn in the palette, as in the target picker of the Aim screen.
struct NightSearchField: View {
    @Binding var text: String
    let prompt: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.tertiaryText)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(palette.tertiaryText))
                .textFieldStyle(.plain)
                .foregroundStyle(palette.primaryText)
                .tint(palette.accent)
                .submitLabel(.search)
                .accessibilityLabel("Search")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.tertiaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.stroke, lineWidth: 0.5))
    }
}
