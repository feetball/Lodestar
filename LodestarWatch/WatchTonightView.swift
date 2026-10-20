import SwiftUI

/// The watch app's only screen: the same four things as the widgets (the dark windows, the Moon, the Milky Way core
/// and the next event), one under the other.
struct WatchTonightView: View {
    /// How often the entries are worked out again while the screen is open.
    private static let refreshInterval: Duration = .seconds(30 * 60)

    @Environment(WatchTonightModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollViewReader { proxy in
                    ScrollView {
                        content(at: Self.moment(context.date))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    #if DEBUG
                    .task(id: model.entries.count) {
                        // The visual review scrolls to a section (`scrollTo=core`).
                        try? await Task.sleep(for: .milliseconds(600))
                        if let id = WatchReviewMode.current?.scrollTo { proxy.scrollTo(id, anchor: .top) }
                    }
                    #endif
                }
            }
            .navigationTitle(TonightLines.title)
            .containerBackground(TonightStyle.gradient, for: .navigation)
        }
        .task {
            model.start()
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }

    /// The moment shown: now (the visual review fixes it).
    private static func moment(_ now: Date) -> Date {
        #if DEBUG
        return WatchReviewMode.current?.date ?? now
        #else
        return now
        #endif
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        if let entry = TonightBuilder.current(in: model.entries, at: date), case .night(let night) = entry.content {
            let lines = TonightLines(night: night, now: date)
            VStack(alignment: .leading, spacing: 12) {
                if let source = model.placeSource {
                    placeLine(source)
                }
                section(lines.dark, symbol: "moon.stars", valueStyle: TonightStyle.accent).id("dark")
                moon(lines).id("moon")
                section(lines.core, symbol: "sparkles", valueStyle: TonightStyle.primaryText).id("core")
                section(lines.event, symbol: lines.eventSymbol ?? "calendar", valueStyle: TonightStyle.primaryText).id("event")
            }
        } else if model.isLoading {
            ProgressView()
                .tint(TonightStyle.accent)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Working out tonight")
        } else {
            needsLocation
        }
    }

    // MARK: Sections

    /// Which place the screen is for. The complications always use the watch's own location, so when the iPhone sent
    /// a place the two can differ, and this says why.
    private func placeLine(_ source: TonightPlaceStore.Source) -> some View {
        Text(source == .phone ? "Your iPhone\u{2019}s place" : TonightLines.placeName)
            .font(.caption2)
            .foregroundStyle(TonightStyle.tertiaryText)
    }

    /// One item: its label line, its main line, the line under it and, where there is one, the last line.
    private func section(_ item: TonightItem, symbol: String, valueStyle: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            labelLine(item) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
                    .accessibilityHidden(true)
            }
            Text(item.value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(valueStyle)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let detail = item.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
            }
            if let extra = item.extra {
                Text(extra)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.tertiaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.spoken)
    }

    private func moon(_ lines: TonightLines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            labelLine(lines.moon) {
                TonightMoonDisc(fraction: lines.moonFraction, isWaxing: lines.moonIsWaxing,
                                isSouthernHemisphere: lines.isSouthernHemisphere, size: 14)
                    .foregroundStyle(TonightStyle.primaryText)
            }
            Text(lines.moon.value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(TonightStyle.primaryText)
            if let detail = lines.moon.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.moon.spoken)
    }

    /// The label line of an item. When the label, the badge and the figure do not fit side by side (a small watch, a large
    /// text size), the badge goes on a line of its own and the label may take two lines.
    private func labelLine(_ item: TonightItem, @ViewBuilder icon: () -> some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                icon()
                labelText(item, lines: 1)
                badgeText(item, separated: true)
                trailingText(item)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    icon()
                    labelText(item, lines: 2)
                    trailingText(item)
                }
                badgeText(item, separated: false)
            }
        }
    }

    private func labelText(_ item: TonightItem, lines: Int) -> some View {
        Text(item.label)
            .font(.caption2)
            .foregroundStyle(TonightStyle.secondaryText)
            .lineLimit(lines)
    }

    @ViewBuilder
    private func badgeText(_ item: TonightItem, separated: Bool) -> some View {
        if let badge = item.badge {
            // On a line of its own the badge has nothing to be separated from.
            Text(separated ? "\u{00B7} \(badge)" : badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(TonightStyle.accent)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func trailingText(_ item: TonightItem) -> some View {
        if let trailing = item.trailing {
            Spacer(minLength: 2)
            Text(trailing)
                .font(.caption2.weight(.bold))
                .foregroundStyle(TonightStyle.primaryText)
        }
    }

    private var needsLocation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(TonightStyle.accent)
                .accessibilityHidden(true)
            Text(TonightNeedsLocationText.full(model.locationIssue))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TonightStyle.primaryText)
            // The iPhone app can supply the place whichever way the watch's own location stands.
            Text(model.locationIssue == .notAsked
                 ? "Or allow location for Lodestar on this watch."
                 : "Or open Lodestar on your iPhone.")
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
