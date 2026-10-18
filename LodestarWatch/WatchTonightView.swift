import SwiftUI

/// The watch app's only screen: tonight's dark window, the Moon, the Milky Way core and the next event.
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
            .navigationTitle("Tonight")
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
                darkness(lines)
                moon(lines)
                core(lines)
                event(lines)
            }
            .accessibilityElement(children: .contain)
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

    private func darkness(_ lines: TonightLines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(lines.darkTitle)
                .font(.footnote)
                .foregroundStyle(TonightStyle.accent)
            Text(lines.darkWindow ?? "")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(TonightStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spokenDark)
    }

    private func moon(_ lines: TonightLines) -> some View {
        HStack(spacing: 8) {
            TonightMoonGlyph(symbolName: lines.moonSymbol, isSouthernHemisphere: lines.isSouthernHemisphere)
                .font(.title2)
                .foregroundStyle(TonightStyle.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(lines.moonName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TonightStyle.primaryText)
                Text("\(lines.moonPercent) \u{00B7} \(lines.moonHorizon)")
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spokenMoon)
    }

    private func core(_ lines: TonightLines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Milky Way core")
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
            Text(lines.coreWindow ?? lines.coreNote)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TonightStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if lines.coreWindow != nil {
                Text(lines.coreNote)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.tertiaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spokenCore)
    }

    @ViewBuilder
    private func event(_ lines: TonightLines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Next event")
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
            if let title = lines.eventTitle, let symbol = lines.eventSymbol, let when = lines.eventWhen {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: symbol)
                        .font(.footnote)
                        .foregroundStyle(TonightStyle.accent)
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TonightStyle.primaryText)
                }
                Text(when)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
            } else {
                Text("None listed for the coming weeks")
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spokenEvent ?? "No events listed for the coming weeks.")
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
