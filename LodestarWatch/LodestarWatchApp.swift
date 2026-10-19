import SwiftUI

/// Lodestar on the Apple Watch: tonight at a glance, worked out on the watch itself.
@main
struct LodestarWatchApp: App {
    @State private var model = WatchTonightModel()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let review = WatchReviewMode.current, review.content == .complications {
                WatchComplicationsReview(mode: review)
                    .dynamicTypeSize(review.usesLargeType ? .accessibility1 : .large)
            } else {
                WatchTonightView()
                    .environment(model)
                    .dynamicTypeSize(WatchReviewMode.current?.usesLargeType == true ? .accessibility1 : .large)
            }
            #else
            WatchTonightView()
                .environment(model)
            #endif
        }
    }
}
