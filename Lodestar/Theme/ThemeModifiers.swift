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

    /// `themedRoot` for the nested mount sheets, which have none, but only in the night chrome experiment `ovl` (so that
    /// the overlay also covers them); every other run, and every Release build, leaves them as they are.
    @ViewBuilder
    func themedRootForOverlayExperiment(_ palette: Palette, redFilter: Bool) -> some View {
        if NightChrome.isEnabled("ovl") {
            themedRoot(palette, redFilter: redFilter)
        } else {
            self
        }
    }
}

private struct ThemedRootModifier: ViewModifier {
    let palette: Palette
    let redFilter: Bool

    /// Whether the multiply overlay is drawn: the user's red filter setting, or on iOS 26 the night chrome experiment
    /// `ovl`, which tries the same overlay to turn the system chrome of iOS 26 red (it ignores the palette there).
    private var showsOverlay: Bool {
        guard palette.isNight else { return false }
        return redFilter || NightChrome.isActive("ovl", night: true)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
            .preferredColorScheme(.dark)
            .modifier(OverlayGroup(isOn: NightChrome.isActive("ovl", night: palette.isNight) && NightChrome.has("g")))
            .modifier(NightControlsModifier(isOn: NightChrome.isActive("ctl", night: palette.isNight)))
            .overlay {
                if showsOverlay {
                    // Multiply by pure red: white → red, blue/green → black. Hit testing is off so
                    // the overlay never intercepts touches.
                    Color(red: 1, green: 0, blue: 0)
                        .blendMode(.multiply)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .onAppear {
                            if !redFilter { NightChrome.log("ovl: overlay shown in a themed root") }
                        }
                }
            }
    }
}

/// Flattens the content into one layer before the overlay is drawn over it (`ovl+g`), to see whether that makes the
/// overlay blend with the UIKit-drawn parts of the content. Does nothing when off.
private struct OverlayGroup: ViewModifier {
    let isOn: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOn {
            content.compositingGroup()
        } else {
            content
        }
    }
}

/// UIKit appearance for the controls SwiftUI does not fully theme (navigation bar, switch/slider
/// thumbs, segmented controls, search field text). Applied to the appearance proxies (for new views)
/// and to the navigation bars already on screen, so switching night mode never has to rebuild the
/// view tree. The tab bar is not here: the app draws its own (`AppTabBar`).
@MainActor
enum BarAppearance {
    static func apply(_ palette: Palette) {
        // Night chrome experiment `t`: the bar of iOS 26 is glass; an opaque appearance background there hides the large
        // title behind the bar background (an empty band at the top of Objects and Settings).
        let transparent = NightChrome.isActive("t", night: palette.isNight)
        if transparent { NightChrome.log("t: transparent navigation bar appearance") }
        let navigation = navigationBarAppearance(palette, transparent: transparent)
        let accent = UIColor(palette.accent)

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

        // The track of iOS 26 is a light glass on which dim red text disappears: give it the surface colour and, at
        // night, give the unselected titles the accent's full strength.
        UISegmentedControl.appearance().backgroundColor = UIColor(palette.surface)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(palette.surfaceRaised)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(palette.primaryText)], for: .selected)
        let unselectedSegment = palette.isNight ? palette.accent : palette.secondaryText
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(unselectedSegment)], for: .normal)

        // Restyle the bars that already exist; the proxies above only affect views created later.
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                restyle(window, navigation: navigation, accent: accent)
            }
        }
    }

    private static func navigationBarAppearance(_ palette: Palette, transparent: Bool) -> UINavigationBarAppearance {
        let title = UIColor(palette.primaryText)
        let navigation = UINavigationBarAppearance()
        if transparent {
            navigation.configureWithTransparentBackground()
        } else {
            navigation.configureWithOpaqueBackground()
            navigation.backgroundColor = UIColor(palette.background)
            navigation.shadowColor = .clear
        }
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

    private static func restyle(_ view: UIView, navigation: UINavigationBarAppearance, accent: UIColor) {
        if let bar = view as? UINavigationBar {
            bar.standardAppearance = navigation
            bar.scrollEdgeAppearance = navigation
            bar.compactAppearance = navigation
            bar.tintColor = accent
        }
        for subview in view.subviews {
            restyle(subview, navigation: navigation, accent: accent)
        }
    }
}
