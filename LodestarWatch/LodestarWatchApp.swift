import SwiftUI

/// Lodestar on the Apple Watch: tonight at a glance, worked out on the watch itself, and an Aim page that mirrors the
/// iPhone's Aim screen while the phone aims.
@main
struct LodestarWatchApp: App {
    @State private var aim: WatchAimModel
    @State private var model: WatchTonightModel
    @State private var page = Page.tonight
    /// Whether the phone is aiming, as of the last second.
    @State private var isAiming = false

    /// The pages, side by side.
    enum Page: Hashable {
        case tonight, aim
    }

    init() {
        let aim = WatchAimModel()
        _aim = State(initialValue: aim)
        _model = State(initialValue: WatchTonightModel(aim: aim))
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let review = WatchReviewMode.current, review.content == .complications {
                WatchComplicationsReview(mode: review)
                    .dynamicTypeSize(review.usesLargeType ? .accessibility1 : .large)
            } else {
                pages
                    .dynamicTypeSize(WatchReviewMode.current?.usesLargeType == true ? .accessibility1 : .large)
            }
            #else
            pages
            #endif
        }
    }

    private var pages: some View {
        TabView(selection: $page) {
            WatchTonightView()
                .environment(model)
                .tag(Page.tonight)
            WatchAimView()
                .environment(aim)
                .tag(Page.aim)
        }
        .tabViewStyle(.page)
        // The Aim page comes forward when the phone starts to aim. When it stops, the page says it is waiting.
        .onChange(of: isAiming) { _, aiming in
            if aiming { page = .aim }
        }
        .task {
            // Notices the messages starting and stopping.
            while !Task.isCancelled {
                isAiming = aim.current(at: Date()) != nil
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
