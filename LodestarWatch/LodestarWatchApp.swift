import SwiftUI

/// Lodestar on the Apple Watch: tonight at a glance, worked out on the watch itself.
@main
struct LodestarWatchApp: App {
    @State private var model = WatchTonightModel()

    var body: some Scene {
        WindowGroup {
            WatchTonightView()
                .environment(model)
        }
    }
}
