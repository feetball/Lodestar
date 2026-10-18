import SwiftUI
import WidgetKit

/// The address widgets and complications open: the Tonight tab. `WidgetShared/TonightLink.swift` (compiled into the
/// widget extensions) carries the same strings, and `Config/Info.plist` registers the scheme.
enum WidgetsLink {
    static let scheme = "lodestar"
    static let tonightHost = "tonight"

    static func isTonight(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == tonightHost
    }
}

/// Connects the app to its widgets and its Apple Watch app: a widget tap opens the Tonight tab, the widgets are asked
/// to reload when the app comes forward or the observer changes (so they pick up a location the user has just allowed),
/// and the watch is told where the observer is.
private struct WidgetsIntegration: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if WidgetsLink.isTonight(url) {
                    app.selectedTab = .tonight
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            .onChange(of: app.observerContext, initial: true) { _, context in
                WatchObserverLink.shared.send(context)
                WidgetCenter.shared.reloadAllTimelines()
            }
    }
}

extension View {
    /// Handles widget links and keeps the widgets and the watch app up to date.
    func lodestarWidgets() -> some View {
        modifier(WidgetsIntegration())
    }
}
