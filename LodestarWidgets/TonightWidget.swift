import SwiftUI
import WidgetKit

/// Tonight at a glance: the dark window, the Moon, the Milky Way core and the next event, worked out on the device
/// for where it is. Tapping it opens the app's Tonight tab.
struct TonightWidget: Widget {
    static let kind = "net.kuecker.Lodestar.widgets.tonight"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TonightProvider()) { entry in
            TonightWidgetView(entry: entry)
        }
        .configurationDisplayName("Tonight")
        .description("When it gets dark, the Moon, the Milky Way core and the next event, for where you are.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Chooses the layout for the widget's family and gives it the app's background.
struct TonightWidgetView: View {
    let entry: TonightEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(TonightLink.url)
            .containerBackground(for: .widget) {
                switch family {
                case .systemSmall, .systemMedium:
                    TonightStyle.gradient
                default:
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            TonightSystemView(entry: entry, isMedium: false)
        case .systemMedium:
            TonightSystemView(entry: entry, isMedium: true)
        default:
            TonightAccessoryView(entry: entry)
        }
    }
}
