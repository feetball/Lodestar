import SwiftUI

/// Lodestar — aim your camera at the night sky.
@main
struct LodestarApp: App {
    @State private var appModel: AppModel

    init() {
        let model = AppModel()
        _appModel = State(initialValue: model)
        // Siri, Shortcuts and Control Center reach the app through the model (see `LodestarIntentHost`).
        LodestarIntentHost.attach(model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}
