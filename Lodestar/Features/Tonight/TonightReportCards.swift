import SwiftUI

/// The cards that describe one night, from the darkness timeline to the best targets.
struct TonightReportCards: View {
    let report: TonightReport

    var body: some View {
        Group {
            TonightTimelineCard(report: report)
            TonightSunCard(summary: report.summary, timeZone: report.timeZone)
            TonightMoonCard(summary: report.summary, timeZone: report.timeZone, appliesSkyline: report.appliesSkyline)
            TonightMilkyWayCard(summary: report.summary, timeZone: report.timeZone,
                                appliesSkyline: report.appliesSkyline)
            TonightPlanetsCard(summary: report.summary, timeZone: report.timeZone,
                               appliesSkyline: report.appliesSkyline)
            TonightTargetsCard(outcome: report.targets, timeZone: report.timeZone,
                               appliesSkyline: report.appliesSkyline)
        }
    }
}

/// A sentence of explanation inside a card: ordinary text, a quieter footnote or a warning.
struct TonightNote: View {
    enum Style {
        case body, footnote, warning
    }

    @Environment(\.palette) private var palette

    let text: String
    var style = Style.body

    var body: some View {
        Text(text)
            .font(style == .body ? .subheadline : .footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch style {
        case .body: return palette.secondaryText
        case .footnote: return palette.tertiaryText
        case .warning: return palette.warning
        }
    }
}

/// A hairline between the rows of a card, drawn in the palette's stroke colour.
struct TonightRowSeparator: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.stroke)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

/// Stands in for the cards while the first night is being worked out.
struct TonightPendingCard: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(palette.tertiaryText)
                .accessibilityHidden(true)
            Text("Working out the night\u{2026}")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .card(palette)
        .accessibilityElement(children: .combine)
    }
}
