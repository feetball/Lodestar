import SwiftUI
import WidgetKit

/// Tonight on the watch face: the Moon's phase (circular and corner), the dark window with the Moon and the next
/// event (rectangular, also in the Smart Stack) or just the dark window (inline). Worked out on the watch for where
/// it is; the system shares the Lodestar watch app's location permission.
struct WatchTonightWidget: Widget {
    static let kind = "net.kuecker.Lodestar.watch.tonight"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TonightProvider()) { entry in
            TonightAccessoryView(entry: entry)
                .widgetURL(TonightLink.url)
                .containerBackground(for: .widget) {
                    TonightStyle.gradient
                }
        }
        .configurationDisplayName("Tonight")
        .description("When it gets dark, the Moon and the next event, for where you are.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
