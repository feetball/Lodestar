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
                ScrollView {
                    content(at: context.date)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func content(at date: Date) -> some View {
        if let entry = TonightBuilder.current(in: model.entries, at: date), case .night(let night) = entry.content {
            let lines = TonightLines(night: night, now: date)
            VStack(alignment: .leading, spacing: 12) {
                section(lines.dark, symbol: "moon.stars", valueStyle: TonightStyle.accent)
                moon(lines)
                section(lines.core, symbol: "sparkles", valueStyle: TonightStyle.primaryText)
                section(lines.event, symbol: lines.eventSymbol ?? "calendar", valueStyle: TonightStyle.primaryText)
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

    private func labelLine(_ item: TonightItem, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 4) {
            icon()
            Text(item.label)
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
                .lineLimit(1)
            if let badge = item.badge {
                Text("\u{00B7} \(badge)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TonightStyle.accent)
                    .lineLimit(1)
            }
            if let trailing = item.trailing {
                Spacer(minLength: 2)
                Text(trailing)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TonightStyle.primaryText)
            }
        }
    }

    private var needsLocation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(TonightStyle.accent)
                .accessibilityHidden(true)
            Text(TonightNeedsLocationText.full)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TonightStyle.primaryText)
            Text("Or allow location for Lodestar on this watch.")
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
