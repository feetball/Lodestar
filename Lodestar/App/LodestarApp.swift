import SwiftUI

/// Lodestar — aim your camera at the night sky.
@main
struct LodestarApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}
