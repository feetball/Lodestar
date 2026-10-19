import SwiftUI
import UIKit

extension View {
    /// Fills the background with the palette's screen colour, edge to edge.
    func screenBackground(_ palette: Palette) -> some View {
        background(palette.background.ignoresSafeArea())
    }

    /// Standard card container used by the Tonight, detail and settings screens.
    func card(_ palette: Palette, padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.stroke, lineWidth: 0.5))
    }

    /// Lists and forms with themed background instead of the system grouped colours.
    func themedList(_ palette: Palette) -> some View {
        scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .foregroundStyle(palette.primaryText)
            .tint(palette.accent)
    }

    /// Applies the palette, tint and colour scheme to a presentation root (window or sheet) and,
    /// in night mode, a red multiply filter that turns any remaining system colours red.
    func themedRoot(_ palette: Palette, redFilter: Bool) -> some View {
        modifier(ThemedRootModifier(palette: palette, redFilter: redFilter))
    }
}

private struct ThemedRootModifier: ViewModifier {
    let palette: Palette
    let redFilter: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
            .preferredColorScheme(.dark)
            .overlay {
                if palette.isNight && redFilter {
                    // Multiply by pure red: white → red, blue/green → black. Hit testing is off so
                    // the overlay never intercepts touches.
                    Color(red: 1, green: 0, blue: 0)
                        .blendMode(.multiply)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// UIKit appearance for the controls SwiftUI does not fully theme (tab bar, navigation bar,
/// switch/slider thumbs, search field text). Applied to the appearance proxies (for new views) and
/// to the bars already on screen, so switching night mode never has to rebuild the view tree.
@MainActor
enum BarAppearance {
    static func apply(_ palette: Palette) {
        let tab = tabBarAppearance(palette)
        let navigation = navigationBarAppearance(palette)
        let accent = UIColor(palette.accent)

        let unselected = UIColor(palette.tertiaryText)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        // The floating glass tab bar of iOS 26 ignores the item colours of the appearance and draws unselected
        // items in the label colour (white), but follows the bar's tint colours.
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = unselected
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = accent
        UIBarButtonItem.appearance().tintColor = accent

        // System switches and sliders draw white thumbs; at night every pixel must be red.
        let nightAccent: UIColor? = palette.isNight ? accent : nil
        UISwitch.appearance().onTintColor = palette.isNight ? UIColor(palette.surfaceRaised) : nil
        UISwitch.appearance().thumbTintColor = nightAccent
        UISlider.appearance().thumbTintColor = nightAccent
        UISlider.appearance().minimumTrackTintColor = accent
        UISlider.appearance().maximumTrackTintColor = palette.isNight ? UIColor(palette.stroke) : nil
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).textColor = UIColor(palette.primaryText)

        // The track of iOS 26 is a light glass on which dim red text disappears: give it the surface colour, and at
        // night the unselected titles full text strength.
        UISegmentedControl.appearance().backgroundColor = UIColor(palette.surface)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(palette.surfaceRaised)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(palette.primaryText)], for: .selected)
        let unselectedSegment = palette.isNight ? palette.primaryText.opacity(0.8) : palette.secondaryText
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(unselectedSegment)], for: .normal)

        // Restyle the bars that already exist; the proxies above only affect views created later.
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                restyle(window, tab: tab, navigation: navigation, accent: accent, unselected: unselected)
            }
        }
    }

    private static func tabBarAppearance(_ palette: Palette) -> UITabBarAppearance {
        let selected = UIColor(palette.accent)
        let normal = UIColor(palette.tertiaryText)
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(palette.surface)
        tab.shadowColor = UIColor(palette.stroke)
        for itemAppearance in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            itemAppearance.normal.iconColor = normal
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: normal]
            itemAppearance.selected.iconColor = selected
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        return tab
    }

    private static func navigationBarAppearance(_ palette: Palette) -> UINavigationBarAppearance {
        let title = UIColor(palette.primaryText)
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(palette.background)
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: title]
        navigation.largeTitleTextAttributes = [.foregroundColor: title]
        // The glass back button of iOS 26 draws its chevron in the label colour (white) whatever the tint; an
        // image in the palette's own colour is drawn as it is.
        let accent = UIColor(palette.accent)
        if let chevron = UIImage(systemName: "chevron.backward",
                                 withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))?
            .withTintColor(accent, renderingMode: .alwaysOriginal) {
            navigation.setBackIndicatorImage(chevron, transitionMaskImage: chevron)
        }
        return navigation
    }

    private static func restyle(_ view: UIView, tab: UITabBarAppearance, navigation: UINavigationBarAppearance,
                                accent: UIColor, unselected: UIColor) {
        if let bar = view as? UITabBar {
            bar.standardAppearance = tab
            bar.scrollEdgeAppearance = tab
            bar.tintColor = accent
            bar.unselectedItemTintColor = unselected
        } else if let bar = view as? UINavigationBar {
            bar.standardAppearance = navigation
            bar.scrollEdgeAppearance = navigation
            bar.compactAppearance = navigation
            bar.tintColor = accent
        }
        for subview in view.subviews {
            restyle(subview, tab: tab, navigation: navigation, accent: accent, unselected: unselected)
        }
    }
}
