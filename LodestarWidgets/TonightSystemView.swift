import SwiftUI
import WidgetKit

/// The Home Screen layouts: small (the dark window, the Moon, the core) and medium (the same, with the core and the
/// next event in a second column).
struct TonightSystemView: View {
    let entry: TonightEntry
    let isMedium: Bool

    var body: some View {
        switch entry.content {
        case .needsLocation:
            needsLocation
        case .night(let night):
            content(TonightLines(night: night, now: entry.date))
        }
    }

    // MARK: Night

    private func content(_ lines: TonightLines) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header
                darkness(lines)
                Spacer(minLength: 0)
                moon(lines)
                if !isMedium {
                    core(lines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isMedium {
                VStack(alignment: .leading, spacing: 8) {
                    coreBlock(lines)
                    eventBlock(lines)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spoken(includingCore: true, includingEvent: isMedium))
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "moon.stars")
            Text("Tonight")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(TonightStyle.accent)
        .widgetAccentable()
    }

    @ViewBuilder
    private func darkness(_ lines: TonightLines) -> some View {
        if let window = lines.darkWindow {
            VStack(alignment: .leading, spacing: 1) {
                Text(lines.darkTitle)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
                Text(window)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(TonightStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        } else {
            Text(lines.darkTitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(TonightStyle.primaryText)
                .lineLimit(2)
        }
    }

    private func moon(_ lines: TonightLines) -> some View {
        HStack(spacing: 5) {
            TonightMoonGlyph(symbolName: lines.moonSymbol, isSouthernHemisphere: lines.isSouthernHemisphere)
                .font(.callout)
                .foregroundStyle(TonightStyle.accent)
                .widgetAccentable()
            Text("\(lines.moonPercent) \u{00B7} \(lines.moonHorizon)")
                .font(.caption)
                .foregroundStyle(TonightStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func core(_ lines: TonightLines) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(TonightStyle.accent)
                .widgetAccentable()
            Text(lines.coreWindow.map { "Core \($0)" } ?? "Core \(lines.coreNote.lowercased())")
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func coreBlock(_ lines: TonightLines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Milky Way core")
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
            Text(lines.coreWindow ?? lines.coreNote)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(TonightStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if lines.coreWindow != nil {
                Text(lines.coreNote)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private func eventBlock(_ lines: TonightLines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Next event")
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
            if let title = lines.eventTitle, let symbol = lines.eventSymbol, let when = lines.eventWhen {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(TonightStyle.accent)
                        .widgetAccentable()
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(TonightStyle.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Text(when)
                    .font(.caption)
                    .foregroundStyle(TonightStyle.secondaryText)
            } else {
                Text("None listed for the coming weeks")
                    .font(.caption)
                    .foregroundStyle(TonightStyle.secondaryText)
                    .lineLimit(2)
            }
        }
    }

    // MARK: Without a place

    private var needsLocation: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 0)
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(TonightStyle.accent)
                .widgetAccentable()
            Text(TonightNeedsLocationText.full)
                .font(.callout.weight(.semibold))
                .foregroundStyle(TonightStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TonightNeedsLocationText.spoken)
    }
}
