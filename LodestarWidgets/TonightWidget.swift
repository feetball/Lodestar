import SwiftUI
import WidgetKit

/// Tonight at a glance: the dark window, the Moon, the Milky Way core and the next event, worked out on the device
/// for where it is (its own location, not the observer chosen in the app). Tapping it opens the app's Tonight tab.
struct TonightWidget: Widget {
    static let kind = "net.kuecker.Lodestar.widgets.tonight"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TonightProvider()) { entry in
            TonightWidgetView(entry: entry)
        }
        .configurationDisplayName("Tonight")
        .description("When it gets dark, the Moon, the Milky Way core and the next event, for where this iPhone is.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Chooses the layout for the widget's family and gives it the app's background.
struct TonightWidgetView: View {
    let entry: TonightEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            // The Home Screen layouts have a fixed size: beyond this the text only truncates ("Fir…", "Da… · n…").
            .dynamicTypeSize(Self.dynamicTypeRange(for: family))
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

    /// The medium widget's tiles are about 133 pt wide, so its text stops growing earlier than the small one's: at xLarge
    /// the bold value is still larger than its label and fits without shrinking far. The small one is about 126 pt high
    /// inside its margins: at xxLarge the Moon phase on two lines, its "lit" line, the label and the dark window on two
    /// lines still fit (the window shrinks a little); at xxxLarge they need about 140 pt, so the window would be cut to
    /// one line again ("7:13 PM – 5:13…"). The inline widget is one line of 257 pt: "Dark until 5:13 · 54%" is about
    /// 160 pt at the default size, so it stops growing at xxLarge instead of being cut to "Dark until 5:…".
    private static func dynamicTypeRange(for family: WidgetFamily) -> ClosedRange<DynamicTypeSize> {
        switch family {
        case .systemSmall: return .xSmall ... .xxLarge
        case .systemMedium: return .xSmall ... .xLarge
        case .accessoryInline: return .xSmall ... .xxLarge
        default: return .xSmall ... .accessibility5
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
