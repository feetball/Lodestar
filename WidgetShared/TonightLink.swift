import Foundation

/// The address a widget or complication opens: the app's Tonight tab. The app registers the `lodestar` scheme and
/// handles it in `Lodestar/Features/Widgets/WidgetsIntegration.swift`, which carries a copy of these strings.
enum TonightLink {
    static let url = URL(string: "lodestar://tonight")
}
