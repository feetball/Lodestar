import SwiftUI
import WidgetKit

/// The lock-screen widgets of the iPhone and the complications of the Apple Watch: circular (the Moon's phase),
/// rectangular (the dark window and the Moon, then the Milky Way core on the iPhone and the next event on the watch),
/// inline and, on the watch, corner. The system draws them in vibrant or tinted colours, so they use the default
/// styles and mark the one accent with `widgetAccentable()`.
struct TonightAccessoryView: View {
    let entry: TonightEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.content {
        case .needsLocation(let issue):
            needsLocation(issue)
        case .night(let night):
            let lines = TonightLines(night: night, now: entry.date)
            switch family {
            case .accessoryCircular:
                circular(lines)
            case .accessoryRectangular:
                rectangular(lines)
            #if os(watchOS)
            case .accessoryCorner:
                corner(lines)
            #endif
            default:
                inline(lines)
            }
        }
    }

    private func disc(_ lines: TonightLines, size: CGFloat) -> some View {
        TonightMoonDisc(fraction: lines.moonFraction, isWaxing: lines.moonIsWaxing,
                        isSouthernHemisphere: lines.isSouthernHemisphere, size: size)
    }

    // MARK: Night

    private func circular(_ lines: TonightLines) -> some View {
        Gauge(value: lines.moonFraction) {
            Text("Moon")
        } currentValueLabel: {
            disc(lines, size: 24)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.moon.spoken)
    }

    private func rectangular(_ lines: TonightLines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(lines.darkInline)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                disc(lines, size: 12)
                Text(lines.moonCompact)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            thirdLine(lines)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spoken(includingCore: !Self.showsEvent, includingEvent: Self.showsEvent))
    }

    /// The core on the iPhone's lock screen, the next event on the watch.
    @ViewBuilder
    private func thirdLine(_ lines: TonightLines) -> some View {
        if Self.showsEvent {
            HStack(spacing: 4) {
                Image(systemName: lines.eventSymbol ?? "calendar")
                Text(lines.eventCompact ?? lines.event.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text(lines.coreCompact)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func inline(_ lines: TonightLines) -> some View {
        #if os(watchOS)
        let text = lines.darkInline
        #else
        let text = "\(lines.darkInline) \u{00B7} \(lines.moon.trailing ?? "")"
        #endif
        return Label {
            Text(text)
        } icon: {
            disc(lines, size: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spoken(includingCore: false, includingEvent: false))
    }

    #if os(watchOS)
    private func corner(_ lines: TonightLines) -> some View {
        disc(lines, size: 28)
            .widgetAccentable()
            .widgetLabel {
                Text(lines.darkCompactWindow.map { "Dark \($0)" } ?? lines.darkInline)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lines.spoken(includingCore: false, includingEvent: false))
    }
    #endif

    // MARK: Without a place

    @ViewBuilder
    private func needsLocation(_ issue: TonightLocationIssue) -> some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "location.slash")
                    .font(.title3)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TonightNeedsLocationText.spoken(issue))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(TonightLines.title, systemImage: "moon.stars")
                    .font(.headline)
                    .widgetAccentable()
                Text(TonightNeedsLocationText.full(issue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TonightNeedsLocationText.spoken(issue))
        #if os(watchOS)
        case .accessoryCorner:
            Image(systemName: "location.slash")
                .font(.title2)
                .widgetAccentable()
                .widgetLabel { Text(TonightNeedsLocationText.corner(issue)) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TonightNeedsLocationText.spoken(issue))
        #endif
        default:
            Label(TonightNeedsLocationText.short(issue), systemImage: "location.slash")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TonightNeedsLocationText.spoken(issue))
        }
    }

    /// The rectangular widget's third line: the next event on the watch, the Milky Way core on the iPhone.
    private static var showsEvent: Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }
}
