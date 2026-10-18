#if DEBUG
import SwiftUI

/// Launch arguments for the visual review of the watch app in the Simulator, which has no location and a clock of its
/// own. Compiled into Debug builds only. Example:
///
///     -LodestarReview view=app date=2026-10-19T05:00:00Z place=36.0544,-112.1401,2130,America/Phoenix scrollTo=core
///
/// `view` is `app` (the Tonight screen) or `complications` (the complication views at their sizes); `scrollTo` is the id of
/// a section to scroll to (`dark`, `moon`, `core`, `event`, or `row0`, `row1`, ... of the complications); `type=large`
/// uses a large text size. Unknown keys are ignored.
struct WatchReviewMode {
    enum Content: String {
        case app, complications
    }

    var content: Content
    var date: Date
    var place: TonightPlace
    var scrollTo: String?
    var usesLargeType: Bool

    static let current: WatchReviewMode? = WatchReviewMode(arguments: ProcessInfo.processInfo.arguments)

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-LodestarReview") else { return nil }
        var values: [String: String] = [:]
        for argument in arguments[(index + 1)...] {
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        content = values["view"].flatMap(Content.init(rawValue:)) ?? .app
        date = values["date"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let numbers = (values["place"] ?? "").split(separator: ",").map(String.init)
        let fallback = TonightPlace(latitude: 36.0544, longitude: -112.1401, elevation: 2130,
                                    timeZoneIdentifier: "America/Phoenix")
        if numbers.count == 4, let latitude = Double(numbers[0]), let longitude = Double(numbers[1]),
           let elevation = Double(numbers[2]),
           let parsed = TonightPlace(latitude: latitude, longitude: longitude, elevation: elevation,
                                     timeZoneIdentifier: numbers[3]) {
            place = parsed
        } else if let fallback {
            place = fallback
        } else {
            return nil
        }
        scrollTo = values["scrollTo"]
        usesLargeType = values["type"] == "large"
    }
}

#if REVIEW_WIDGETS
import WidgetKit

/// The complication views drawn at the sizes of an Apple Watch, over the face colour, in several states. Needs the review
/// build of `.github/workflows/review.yml`, which gives the views an environment value for the family that this can set
/// (WidgetKit's own `widgetFamily` can only be read).
struct WatchComplicationsReview: View {
    let mode: WatchReviewMode

    private struct Row: Sendable {
        let title: String
        let entry: TonightEntry
    }

    @State private var rows: [Row] = []

    private struct Size {
        let family: WidgetFamily
        let name: String
        let width: CGFloat
        let height: CGFloat
    }

    private static let sizes = [
        Size(family: .accessoryCircular, name: "circular", width: 48, height: 48),
        Size(family: .accessoryRectangular, name: "rectangular", width: 160, height: 68),
        Size(family: .accessoryInline, name: "inline", width: 160, height: 20),
        Size(family: .accessoryCorner, name: "corner (disc only; the curved label needs the face)", width: 52, height: 52),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.caption2.weight(.semibold))
                            ForEach(Self.sizes, id: \.name) { size in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(size.name)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                    TonightAccessoryView(entry: row.entry)
                                        .environment(\.reviewWidgetFamily, size.family)
                                        .frame(width: size.width, height: size.height)
                                        .background(size.family == .accessoryRectangular ? Color.white.opacity(0.1) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                        .id("row\(index)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: rows.count) {
                try? await Task.sleep(for: .milliseconds(600))
                if let target = mode.scrollTo { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .task {
            let place = mode.place
            let start = mode.date
            rows = await Task.detached {
                [
                    Row(title: "Dark, 22:00", entry: TonightBuilder.entry(for: place, at: start)),
                    Row(title: "Before dusk",
                        entry: TonightBuilder.entry(for: place, at: start.addingTimeInterval(-4.5 * 3_600))),
                    Row(title: "No location", entry: TonightEntry.needsLocation(at: start)),
                ]
            }.value
        }
    }
}
#else
/// The complication views are drawn only in the review build.
struct WatchComplicationsReview: View {
    let mode: WatchReviewMode

    var body: some View {
        Text("The complications are not part of this build.")
    }
}
#endif
#endif
