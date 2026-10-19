import SwiftUI
import LodestarKit

/// The night at a glance: how dark the sky is, when the Moon is up, when it is dark without the Moon and when
/// the Milky Way's core can be photographed, with a marker for the present moment.
struct TonightTimelineCard: View {
    @Environment(\.palette) private var palette

    let report: TonightReport

    var body: some View {
        let summary = report.summary
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Darkness", systemImage: "chart.bar.xaxis")
            Text("Sunset \(AppFormat.time(summary.twilight.sunset, in: report.timeZone))"
                 + " \u{2192} sunrise \(AppFormat.time(summary.twilight.sunrise, in: report.timeZone))")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                TonightTimelineCanvas(model: report.timeline, timeZone: report.timeZone, now: timeline.date)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Darkness timeline")
            .accessibilityValue(spokenSummary)
            TonightSkyLegend()
            if report.appliesSkyline {
                TonightSkylineNote(detail: "the Moon and Milky Way core bars follow the skyline.")
            }
            if !summary.hasAstronomicalDarkness {
                TonightNote(text: "The Sun stays less than 18\u{00B0} below the horizon, so the sky never gets fully"
                            + " dark on this night.", style: .warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    /// The drawing in words, for VoiceOver.
    private var spokenSummary: String {
        let summary = report.summary
        let zone = report.timeZone
        var sentences: [String] = []
        if summary.hasAstronomicalDarkness {
            sentences.append("Astronomical darkness from "
                             + TonightFormat.spokenWindows(summary.astronomicalDarknessIntervals, in: zone))
        } else {
            sentences.append("No astronomical darkness")
        }
        if summary.moon.upIntervals.isEmpty {
            sentences.append("The Moon stays down")
        } else {
            sentences.append("Moon up from " + TonightFormat.spokenWindows(summary.moon.upIntervals, in: zone))
        }
        if !summary.darknessIntervals.isEmpty {
            sentences.append("Dark without the Moon from "
                             + TonightFormat.spokenWindows(summary.darknessIntervals, in: zone))
        }
        if report.timeline.coreVisible.isEmpty {
            sentences.append("The Milky Way core is not visible")
        } else {
            sentences.append("Milky Way core visible from "
                             + TonightFormat.spokenWindows(report.timeline.coreVisible, in: zone))
        }
        return sentences.joined(separator: ". ")
    }
}

/// Swatches for the levels of the sky bar, brightest first.
private struct TonightSkyLegend: View {
    @Environment(\.palette) private var palette

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(TonightSkyLevel.allCases.reversed(), id: \.self) { level in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(palette.accent.opacity(level.fillOpacity))
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(palette.stroke, lineWidth: 0.5))
                        .frame(width: 16, height: 10)
                    Text(level.title)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The drawing itself: four bars on a shared time axis. Drawn in palette colours only.
private struct TonightTimelineCanvas: View {
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 10

    let model: TonightTimelineModel
    let timeZone: TimeZone
    /// The present moment, drawn as a marker while it falls inside the night.
    let now: Date

    /// The bars from top to bottom.
    private enum Row: CaseIterable {
        case sky, moon, dark, core

        var title: String {
            switch self {
            case .sky: return "Sky"
            case .moon: return "Moon up"
            case .dark: return "Dark sky"
            case .core: return "Milky Way"
            }
        }

        /// The bar's height in label heights: the sky bar is twice as tall as the others.
        var heightFactor: CGFloat { self == .sky ? 2 : 1 }
    }

    /// Maps instants to horizontal positions.
    private struct Axis {
        let range: DateInterval
        let minX: CGFloat
        let width: CGFloat

        func x(_ date: Date) -> CGFloat {
            let fraction = date.timeIntervalSince(range.start) / range.duration
            return minX + width * CGFloat(AstroMath.clamp(fraction, 0, 1))
        }
    }

    private var rowGap: CGFloat { labelSize * 0.5 }
    /// Room above the bars for the "Now" label and its pointer.
    private var markerHeight: CGFloat { labelSize * 1.3 + 8 }
    /// Room below the bars for the hour labels.
    private var axisHeight: CGFloat { labelSize * 1.3 + 6 }
    private var barsHeight: CGFloat {
        Row.allCases.reduce(0) { $0 + labelSize * $1.heightFactor } + rowGap * CGFloat(Row.allCases.count - 1)
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: markerHeight + barsHeight + axisHeight)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let range = model.range
        guard range.duration > 0, size.width > 0 else { return }
        let gutter = labelSize * 5.8
        let axis = Axis(range: range, minX: gutter, width: max(size.width - gutter, 1))

        // The tracks of the four bars.
        var tracks: [(row: Row, rect: CGRect)] = []
        var top = markerHeight
        for row in Row.allCases {
            let height = labelSize * row.heightFactor
            tracks.append((row, CGRect(x: axis.minX, y: top, width: axis.width, height: height)))
            top += height + rowGap
        }
        let barsBottom = top - rowGap
        for (row, rect) in tracks {
            context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 3), with: .color(palette.surfaceRaised))
            let title = Text(row.title)
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(palette.secondaryText)
            context.draw(title, at: CGPoint(x: 0, y: rect.midY), anchor: .leading)
        }

        drawHourLines(in: &context, axis: axis, bottom: barsBottom, size: size)
        for (row, rect) in tracks {
            drawBar(row, in: rect, axis: axis, context: &context)
        }
        drawNowMarker(in: &context, axis: axis, bottom: barsBottom, size: size)
    }

    /// Hairlines and labels at whole hours, as many as fit without the labels touching.
    private func drawHourLines(in context: inout GraphicsContext, axis: Axis, bottom: CGFloat, size: CGSize) {
        let format = Date.FormatStyle(timeZone: timeZone).hour()
        let labels = model.hourTicks.map { tick in
            (tick, context.resolve(Text(tick.date.formatted(format))
                .font(.system(size: labelSize).monospacedDigit())
                .foregroundStyle(palette.secondaryText)))
        }
        let labelWidth = labels.map { $0.1.measure(in: size).width }.max() ?? 0
        let pointsPerHour = axis.width / CGFloat(model.range.duration / 3600)
        let spacing = TonightTimelineModel.labelSpacing(pointsPerHour: pointsPerHour, labelWidth: labelWidth,
                                                        gap: labelSize * 0.8)
        var lines = Path()
        for (tick, label) in labels where tick.hour % spacing == 0 {
            let x = axis.x(tick.date)
            lines.move(to: CGPoint(x: x, y: markerHeight))
            lines.addLine(to: CGPoint(x: x, y: bottom))
            guard x + labelWidth / 2 <= size.width else { continue }
            context.draw(label, at: CGPoint(x: x, y: bottom + 4), anchor: .top)
        }
        context.stroke(lines, with: .color(palette.gridLine), lineWidth: 1)
    }

    private func drawBar(_ row: Row, in rect: CGRect, axis: Axis, context: inout GraphicsContext) {
        var bar = context
        bar.clip(to: Path(roundedRect: rect, cornerRadius: rect.height / 3))
        switch row {
        case .sky:
            for band in model.bands {
                fill(bar: &bar, intervals: [band.interval], rect: rect, axis: axis,
                     color: palette.accent.opacity(band.level.fillOpacity))
            }
        case .moon:
            fill(bar: &bar, intervals: model.moonUp, rect: rect, axis: axis, color: palette.secondaryText)
        case .dark:
            fill(bar: &bar, intervals: model.dark, rect: rect, axis: axis, color: palette.positive)
        case .core:
            fill(bar: &bar, intervals: model.coreVisible, rect: rect, axis: axis,
                 color: palette.deepSkyMarker.opacity(0.4))
            fill(bar: &bar, intervals: model.coreMoonFree, rect: rect, axis: axis, color: palette.deepSkyMarker)
        }
    }

    private func fill(bar: inout GraphicsContext, intervals: [DateInterval], rect: CGRect, axis: Axis, color: Color) {
        for interval in intervals {
            let start = axis.x(interval.start)
            let end = axis.x(interval.end)
            bar.fill(Path(CGRect(x: start, y: rect.minY, width: max(end - start, 1), height: rect.height)),
                     with: .color(color))
        }
    }

    /// A line through the bars at the present moment, with a pointer and the word "Now".
    private func drawNowMarker(in context: inout GraphicsContext, axis: Axis, bottom: CGFloat, size: CGSize) {
        guard model.range.contains(now) else { return }
        let x = axis.x(now)
        var line = Path()
        line.move(to: CGPoint(x: x, y: markerHeight - 3))
        line.addLine(to: CGPoint(x: x, y: bottom + 2))
        context.stroke(line, with: .color(palette.primaryText), lineWidth: 1.5)

        var pointer = Path()
        pointer.move(to: CGPoint(x: x - 4, y: markerHeight - 8))
        pointer.addLine(to: CGPoint(x: x + 4, y: markerHeight - 8))
        pointer.addLine(to: CGPoint(x: x, y: markerHeight - 2))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(palette.primaryText))

        let labelX = AstroMath.clamp(x, axis.minX + labelSize * 1.2, size.width - labelSize * 1.2)
        let label = Text("Now")
            .font(.system(size: labelSize, weight: .semibold))
            .foregroundStyle(palette.primaryText)
        context.draw(label, at: CGPoint(x: labelX, y: markerHeight - 9), anchor: .bottom)
    }
}
