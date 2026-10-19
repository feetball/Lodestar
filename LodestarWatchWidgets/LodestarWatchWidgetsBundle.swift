import SwiftUI
import WidgetKit

/// The complications Lodestar offers on the Apple Watch.
@main
struct LodestarWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchTonightWidget()
    }
}
