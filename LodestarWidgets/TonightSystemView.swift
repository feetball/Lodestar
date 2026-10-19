import SwiftUI
import WidgetKit

/// The Home Screen layouts, as on Android: small shows the Moon and the dark window, medium shows the four items
/// (dark, Moon, Milky Way core, next event) as tiles of a label line, a main line and a detail line.
struct TonightSystemView: View {
    let entry: TonightEntry
    let isMedium: Bool

    /// The four things a widget shows.
    private enum Slot {
        case dark, moon, core, event

        var symbolName: String {
            switch self {
            case .dark: return "moon.stars"
            case .moon: return "moonphase.full.moon"
            case .core: return "sparkles"
            case .event: return "calendar"
            }
        }
    }

    var body: some View {
        switch entry.content {
        case .needsLocation:
            needsLocation
        case .night(let night):
            let lines = TonightLines(night: night, now: entry.date)
            Group {
                if isMedium {
                    grid(lines)
                } else {
                    small(lines)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lines.spoken(includingCore: isMedium, includingEvent: isMedium))
        }
    }

    private func item(_ slot: Slot, in lines: TonightLines) -> TonightItem {
        switch slot {
        case .dark: return lines.dark
        case .moon: return lines.moon
        case .core: return lines.core
        case .event: return lines.event
        }
    }

    private func disc(_ lines: TonightLines, size: CGFloat) -> some View {
        TonightMoonDisc(fraction: lines.moonFraction, isWaxing: lines.moonIsWaxing,
                        isSouthernHemisphere: lines.isSouthernHemisphere, size: size)
            .foregroundStyle(TonightStyle.primaryText)
    }

    // MARK: Small

    /// The Moon, drawn, with its phase and lit part; the dark window under it.
    private func small(_ lines: TonightLines) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                disc(lines, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lines.moon.value)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(TonightStyle.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text("\(lines.moon.trailing ?? "") lit")
                        .font(.caption)
                        .foregroundStyle(TonightStyle.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            labelLine(.dark, lines: lines, short: true)
            Text(lines.dark.value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(TonightStyle.accent)
                .widgetAccentable()
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let detail = lines.dark.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium

    private func grid(_ lines: TonightLines) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                tile(.dark, lines: lines)
                tile(.moon, lines: lines)
            }
            HStack(spacing: 6) {
                tile(.core, lines: lines)
                tile(.event, lines: lines)
            }
        }
    }

    private func tile(_ slot: Slot, lines: TonightLines) -> some View {
        let item = item(slot, in: lines)
        return VStack(alignment: .leading, spacing: 1) {
            labelLine(slot, lines: lines, short: true)
            Text(item.value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(slot == .dark ? TonightStyle.accent : TonightStyle.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail = item.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(TonightStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    /// An item's label line: its picture (the Moon's phase for the Moon), the label, a mark for what is happening
    /// now, and its figure at the end.
    private func labelLine(_ slot: Slot, lines: TonightLines, short: Bool) -> some View {
        let item = item(slot, in: lines)
        return HStack(spacing: 4) {
            if slot == .moon {
                disc(lines, size: 12)
            } else {
                Image(systemName: slot == .event ? (lines.eventSymbol ?? slot.symbolName) : slot.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(TonightStyle.secondaryText)
                    .accessibilityHidden(true)
            }
            Text(short ? item.shortLabel : item.label)
                .font(.caption2)
                .foregroundStyle(TonightStyle.secondaryText)
                .lineLimit(1)
            if let badge = item.badge {
                Text("\u{00B7} \(badge)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TonightStyle.accent)
                    .widgetAccentable()
                    .lineLimit(1)
            }
            if let trailing = item.trailing {
                Spacer(minLength: 2)
                Text(trailing)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TonightStyle.primaryText)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Without a place

    private var needsLocation: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(TonightStyle.accent)
                .widgetAccentable()
            Text(TonightNeedsLocationText.full)
                .font(.footnote.weight(.bold))
                .foregroundStyle(TonightStyle.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TonightNeedsLocationText.spoken)
    }
}
