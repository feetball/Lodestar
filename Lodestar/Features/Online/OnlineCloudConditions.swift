import SwiftUI

/// The words of the weather part of the "Clouds tonight" card. The Android app uses the same texts.
enum CloudConditionsText {
    static let hourly = "Hourly"
    static let showHourly = "Show the hourly forecast"
    static let hideHourly = "Hide the hourly forecast"
    static let dewGapNote = "Dew gap: how far the air temperature is above the dew point. Dew forms on a cold lens when it is small."
}

/// The night's weather under the cloud strip: chips for dew, wind, fog and temperature (in the warning tone where they
/// matter), a line for the most important warning and the hourly table. Everything comes from `slots`, the forecast cut
/// to the night.
struct CloudConditions: View {
    let slots: [CloudSlot]
    let timeZone: TimeZone
    @Environment(\.locale) private var locale

    var body: some View {
        let system = ForecastUnits.system(for: locale)
        let timeText: (Date) -> String = { AppFormat.time($0, in: timeZone) }
        let conditions = ForecastNight.conditions(slots)
        let chips = ForecastWords.chips(conditions, system: system, timeText: timeText)
        VStack(alignment: .leading, spacing: 10) {
            if !chips.isEmpty {
                CloudChipFlow(spacing: 8, lineSpacing: 8) {
                    ForEach(chips, id: \.kind) { chip in
                        StatusChip(systemImage: Self.symbol(chip.kind), text: chip.text,
                                   tone: chip.isWarning ? .warning : .neutral)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(chip.spoken)
                    }
                }
            }
            if let hint = ForecastWords.hint(conditions, timeText: timeText) {
                TonightNote(text: hint, style: .warning)
            }
            CloudHourlyTable(hours: conditions.hourly, system: system, timeText: timeText)
        }
    }

    private static func symbol(_ kind: ForecastChipKind) -> String {
        switch kind {
        case .dew: return "drop"
        case .wind: return "wind"
        case .fog: return "cloud.fog"
        case .temperature: return "thermometer.medium"
        }
    }
}

/// "Hourly": a row that opens the table of time, cloud, temperature, dew gap and wind, one row per forecast slot.
private struct CloudHourlyTable: View {
    let hours: [NightHour]
    let system: ForecastUnitSystem
    let timeText: (Date) -> String
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        if !hours.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Text(CloudConditionsText.hourly)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CloudConditionsText.hourly)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? CloudConditionsText.hideHourly : CloudConditionsText.showHourly)
                if isExpanded {
                    table
                    TonightNote(text: CloudConditionsText.dewGapNote, style: .footnote)
                }
            }
        }
    }

    private var table: some View {
        let rows = Array(hours.enumerated())
        return Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(ForecastWords.hourlyHeaders(system).enumerated()), id: \.offset) { column, title in
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.tertiaryText)
                        .multilineTextAlignment(.trailing)
                        .gridColumnAlignment(column == 0 ? .leading : .trailing)
                }
            }
            ForEach(rows, id: \.offset) { _, hour in
                GridRow {
                    ForEach(Array(ForecastWords.hourlyCells(hour, system: system, timeText: timeText).enumerated()),
                            id: \.offset) { _, cell in
                        Text(cell)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.primaryText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One VoiceOver element per forecast time, in words, instead of one per cell.
        .accessibilityRepresentation {
            VStack(alignment: .leading) {
                ForEach(rows, id: \.offset) { _, hour in
                    Text(ForecastWords.hourlySpoken(hour, system: system, timeText: timeText))
                }
            }
        }
    }
}

/// Lays its children out in rows from the leading edge that wrap when the width runs out. A child wider than the row is
/// offered the row's width, so its text wraps instead of running over the card's edge.
private struct CloudChipFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        let sizes = childSizes(of: subviews, limit: limit)
        let rows = rows(of: sizes, maxWidth: limit)
        let height = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }.reduce(0, +)
            + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map { width(of: $0, sizes: sizes) }.max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = childSizes(of: subviews, limit: bounds.width)
        var y = bounds.minY
        for row in rows(of: sizes, maxWidth: bounds.width) {
            var x = bounds.minX
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }

    /// The size of each child: its ideal one, or, if that is wider than `limit`, the one it takes in `limit`.
    private func childSizes(of subviews: Subviews, limit: CGFloat) -> [CGSize] {
        subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified)
            guard limit.isFinite, ideal.width > limit else { return ideal }
            return subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
        }
    }

    /// Indices of the children in each row.
    private func rows(of sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let widthWithChild = current.isEmpty ? size.width : currentWidth + spacing + size.width
            if !current.isEmpty && widthWithChild > maxWidth {
                rows.append(current)
                current = [index]
                currentWidth = size.width
            } else {
                current.append(index)
                currentWidth = widthWithChild
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func width(of row: [Int], sizes: [CGSize]) -> CGFloat {
        row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0))
    }
}
