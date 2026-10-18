#if DEBUG
import SwiftUI

#if REVIEW_WIDGETS
import WidgetKit
import LodestarKit

/// The widgets' views, drawn at the sizes of each family on the screen of the Simulator.
///
/// The widget views live in `WidgetShared` and `LodestarWidgets`, which are compiled into the widget extension and the
/// watch app but not into the app. The review workflow copies those sources into the app's folder and builds with
/// `-DREVIEW_WIDGETS` (see `.github/workflows/review.yml`), so this file draws the very views the extension draws. The
/// Home Screen families get the app's background and the default content margin; the Lock Screen families sit on a
/// grey wallpaper, as they do on the Lock Screen. The widgets have no night palette (they follow the system, and the
/// extension cannot know that the app is in night mode), so the red variant shows them under a red filter.
struct ReviewWidgetsScreen: View {
    let screen: ReviewScreen

    @State private var rows: [Row] = []

    private struct Row: Identifiable {
        let id: Int
        let title: String
        let entry: TonightEntry
    }

    /// A family and the size the system gives it on a 6.3-inch iPhone (the smaller phones' are a little smaller).
    private struct Size {
        let family: WidgetFamily
        let name: String
        let width: CGFloat
        let height: CGFloat
    }

    private static let sizes = [
        Size(family: .systemSmall, name: "systemSmall", width: 158, height: 158),
        Size(family: .systemMedium, name: "systemMedium", width: 338, height: 158),
        Size(family: .accessoryCircular, name: "accessoryCircular", width: 76, height: 76),
        Size(family: .accessoryRectangular, name: "accessoryRectangular", width: 172, height: 76),
        Size(family: .accessoryInline, name: "accessoryInline", width: 257, height: 26),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(row.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        widget(.systemSmall, row.entry)
                        widget(.systemMedium, row.entry)
                        HStack(alignment: .top, spacing: 12) {
                            widget(.accessoryCircular, row.entry)
                            widget(.accessoryRectangular, row.entry)
                        }
                        widget(.accessoryInline, row.entry)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            LinearGradient(colors: [Color(white: 0.32), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea())
        .modifier(ReviewWidgetsLook(screen: screen))
        .task {
            rows = await Self.makeRows(for: screen)
        }
    }

    @ViewBuilder
    private func widget(_ family: WidgetFamily, _ entry: TonightEntry) -> some View {
        let size = Self.sizes.first { $0.family == family }
        if let size {
            let isHomeScreen = family == .systemSmall || family == .systemMedium
            VStack(alignment: .leading, spacing: 3) {
                Text("\(size.name) \(Int(size.width))\u{00D7}\(Int(size.height))")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.75))
                TonightWidgetView(entry: entry)
                    .environment(\.widgetFamily, family)
                    .padding(isHomeScreen ? 16 : 0)
                    .frame(width: size.width, height: size.height)
                    .background {
                        if isHomeScreen { TonightStyle.gradient }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: isHomeScreen ? 22 : 8, style: .continuous))
            }
        }
    }

    // MARK: Rows

    private static func makeRows(for screen: ReviewScreen) async -> [Row] {
        let grandCanyon = TonightPlace(latitude: 36.0544, longitude: -112.1401, elevation: 2130,
                                       timeZoneIdentifier: "America/Phoenix")
        let sydney = TonightPlace(latitude: -33.8688, longitude: 151.2093, elevation: 20,
                                  timeZoneIdentifier: "Australia/Sydney")
        let tromso = TonightPlace(latitude: 69.6492, longitude: 18.9553, elevation: 10,
                                  timeZoneIdentifier: "Europe/Oslo")
        func entry(_ place: TonightPlace?, _ iso: String) -> TonightEntry {
            guard let place, let date = ISO8601DateFormatter().date(from: iso) else {
                return .needsLocation(at: Date())
            }
            return TonightBuilder.entry(for: place, at: date)
        }
        let rows: [(String, TonightEntry)]
        switch screen {
        case .widgetsStates:
            rows = await Task.detached {
                [
                    ("Sydney, southern hemisphere, 21:00", entry(sydney, "2026-10-19T10:00:00Z")),
                    ("Tromso, midsummer: no darkness", entry(tromso, "2026-06-21T22:00:00Z")),
                    ("Grand Canyon, around the full Moon", entry(grandCanyon, "2026-10-26T05:00:00Z")),
                    ("Grand Canyon, around the new Moon", entry(grandCanyon, "2026-11-10T05:00:00Z")),
                    ("No location yet", TonightEntry.needsLocation(at: Date())),
                ]
            }.value
        default:
            rows = await Task.detached {
                [
                    ("Grand Canyon, 22:00, in the dark", entry(grandCanyon, "2026-10-19T05:00:00Z")),
                    ("Grand Canyon, 17:30, before dusk", entry(grandCanyon, "2026-10-19T00:30:00Z")),
                    ("Grand Canyon, 04:30, before dawn", entry(grandCanyon, "2026-10-19T11:30:00Z")),
                ]
            }.value
        }
        return rows.enumerated().map { Row(id: $0.offset, title: $0.element.0, entry: $0.element.1) }
    }
}

/// What distinguishes the variants of the screen: the text size, and the red filter.
private struct ReviewWidgetsLook: ViewModifier {
    let screen: ReviewScreen

    func body(content: Content) -> some View {
        switch screen {
        case .widgetsLargeType:
            content.dynamicTypeSize(.accessibility2)
        case .widgetsRed:
            content.colorMultiply(Color(red: 1, green: 0, blue: 0))
        default:
            content
        }
    }
}

#else

/// The widget views are not compiled into the app: build with `OTHER_SWIFT_FLAGS=-DREVIEW_WIDGETS` after copying
/// `WidgetShared` and `LodestarWidgets` next to this file (see `.github/workflows/review.yml`).
struct ReviewWidgetsScreen: View {
    let screen: ReviewScreen

    var body: some View {
        Text("The widget views are not part of this build.")
            .padding()
    }
}

#endif
#endif
