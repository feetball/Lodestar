import SwiftUI
import Charts
import LodestarKit

/// A line chart of an object's altitude through the night, with the horizon, the twilight bands and the present
/// moment marked. Drawn in palette colours only.
struct ObjectDetailAltitudeChart: View {
    /// The altitudes the chart shows; the part below the horizon is cut off at the lower bound.
    private static let altitudeRange: ClosedRange<Double> = -10...90

    @Environment(\.palette) private var palette

    let night: ObjectDetailNight
    /// The present moment, drawn as a vertical line when it falls inside the chart.
    let now: Date?
    let timeZone: TimeZone

    var body: some View {
        Chart {
            ForEach(night.twilightBands) { band in
                RectangleMark(xStart: .value("From", band.interval.start), xEnd: .value("To", band.interval.end))
                    .foregroundStyle(palette.secondaryText.opacity(Self.opacity(ofBrightness: band.brightness)))
            }
            RuleMark(y: .value("Horizon", 0.0))
                .foregroundStyle(palette.horizonLine)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(night.samples) { sample in
                AreaMark(x: .value("Time", sample.date),
                         yStart: .value("Horizon", 0.0),
                         yEnd: .value("Altitude", max(sample.altitude, 0)))
                    .foregroundStyle(palette.accent.opacity(0.18))
                LineMark(x: .value("Time", sample.date),
                         y: .value("Altitude", max(sample.altitude, Self.altitudeRange.lowerBound)))
                    .foregroundStyle(palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let now, night.chartRange.contains(now) {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(palette.primaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .overlay, alignment: .topLeading, spacing: 0,
                                overflowResolution: AnnotationOverflowResolution(x: .fit(to: .plot), y: .disabled)) {
                        Text("Now")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 3)
                    }
            }
        }
        .chartXScale(domain: night.chartRange.start...night.chartRange.end)
        .chartYScale(domain: Self.altitudeRange)
        .chartXAxis {
            AxisMarks(values: night.hourTicks) { value in
                AxisGridLine().foregroundStyle(palette.stroke)
                AxisTick().foregroundStyle(palette.stroke)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(Date.FormatStyle(timeZone: timeZone).hour()))
                    }
                }
                .foregroundStyle(palette.secondaryText)
            }
        }
        .chartYAxis {
            AxisMarks(values: [0.0, 30.0, 60.0, 90.0]) { value in
                AxisGridLine().foregroundStyle(palette.stroke)
                AxisValueLabel {
                    if let degrees = value.as(Double.self) {
                        Text(AngleFormatter.formatDegrees(degrees, decimals: 0))
                    }
                }
                .foregroundStyle(palette.secondaryText)
            }
        }
        .chartPlotStyle { plot in
            plot.background(palette.background)
        }
        .frame(height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Altitude through the night")
        .accessibilityValue(summary)
    }

    /// The highest point of the curve, spoken in place of the drawing.
    private var summary: String {
        guard let highest = night.samples.max(by: { $0.altitude < $1.altitude }), highest.altitude > 0 else {
            return "Below the horizon all night"
        }
        let altitude = AngleFormatter.formatDegrees(highest.altitude, decimals: 0)
        return "Highest \(altitude) at \(AppFormat.time(highest.date, in: timeZone))"
    }

    /// Lighter sky shows as a stronger overlay: astronomical twilight is faint, daylight strongest.
    private static func opacity(ofBrightness brightness: Int) -> Double {
        switch brightness {
        case ...1: return 0.07
        case 2: return 0.14
        case 3: return 0.24
        default: return 0.36
        }
    }
}
