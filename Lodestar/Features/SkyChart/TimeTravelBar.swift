import SwiftUI
import LodestarKit

/// The sky chart's clock: the displayed date and time in the observer's time zone, a slider for
/// ±12 hours around now, one-hour steps, a "Now" button and a way to pick any date.
struct TimeTravelBar: View {
    /// The range of the slider, in hours from now.
    static let sliderRange: ClosedRange<Double> = -12...12

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let timeZone: TimeZone
    let onChooseDate: () -> Void

    var body: some View {
        let clock = app.clock
        VStack(spacing: 6) {
            // At large text sizes the buttons move below the readout.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    readout(clock)
                    Spacer(minLength: 4)
                    dateButtons(clock)
                }
                VStack(alignment: .leading, spacing: 6) {
                    readout(clock)
                    dateButtons(clock)
                }
            }
            HStack(spacing: 8) {
                Button("\u{2212}1h") { clock.travel(by: -3600) }
                    .buttonStyle(.lodestarSecondary)
                    .accessibilityLabel("One hour earlier")
                SkyChartTimeSlider(hours: sliderBinding(for: clock), range: Self.sliderRange)
                Button("+1h") { clock.travel(by: 3600) }
                    .buttonStyle(.lodestarSecondary)
                    .accessibilityLabel("One hour later")
            }
        }
        .card(palette, padding: 10)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// "Now" and the button that opens the date sheet.
    private func dateButtons(_ clock: SkyClock) -> some View {
        HStack(spacing: 8) {
            Button("Now") { clock.returnToNow() }
                .buttonStyle(.lodestarSecondary)
                .disabled(clock.isLive)
            Button(action: onChooseDate) {
                Image(systemName: "calendar")
            }
            .buttonStyle(.lodestarSecondary)
            .accessibilityLabel("Choose date and time")
        }
    }

    private func readout(_ clock: SkyClock) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppFormat.dateTime(clock.displayDate, in: timeZone))
                .font(.headline.monospacedDigit())
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if clock.isLive {
                StatusChip(systemImage: "dot.radiowaves.left.and.right", text: "Live", tone: .positive)
            } else {
                let relative = AppFormat.relative(clock.displayDate, from: clock.now)
                Text("\(relative) \u{00B7} \(zoneName(at: clock.displayDate))")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The abbreviation of the observer's time zone at `date`, such as "PDT" or "GMT+2".
    private func zoneName(at date: Date) -> String {
        timeZone.abbreviation(for: date) ?? timeZone.identifier
    }

    /// The slider position: hours between now and the displayed time. Dragging to the middle returns to live.
    private func sliderBinding(for clock: SkyClock) -> Binding<Double> {
        Binding(
            get: { clock.offset / 3600 },
            set: { hours in
                if abs(hours) < 1.0 / 60 {
                    clock.returnToNow()
                } else {
                    clock.travel(to: clock.now.addingTimeInterval((hours * 60).rounded() * 60))
                }
            })
    }
}

/// A slider for the time offset, drawn from palette colours: the track fills outwards from the
/// middle ("now") to the thumb, so the colour reads as "how far from now".
struct SkyChartTimeSlider: View {
    private static let thumbSize: CGFloat = 26
    /// How far VoiceOver's increment and decrement actions move the time, in hours.
    private static let accessibilityStep = 0.25

    @Environment(\.palette) private var palette
    @Binding var hours: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let middle = width / 2
            let x = thumbX(in: width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.stroke)
                    .frame(height: 4)
                Capsule()
                    .fill(palette.accent.opacity(0.7))
                    .frame(width: abs(x - middle), height: 4)
                    .offset(x: min(x, middle))
                Rectangle()
                    .fill(palette.tertiaryText)
                    .frame(width: 1.5, height: 14)
                    .offset(x: middle - 0.75)
                Circle()
                    .fill(palette.accent)
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .offset(x: x - Self.thumbSize / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                hours = hoursAt(x: value.location.x, width: width)
            })
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time offset from now")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: hours = min(hours + Self.accessibilityStep, range.upperBound)
            case .decrement: hours = max(hours - Self.accessibilityStep, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func thumbX(in width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let fraction = (min(max(hours, range.lowerBound), range.upperBound) - range.lowerBound) / span
        return Self.thumbSize / 2 + CGFloat(fraction) * (width - Self.thumbSize)
    }

    private func hoursAt(x: CGFloat, width: CGFloat) -> Double {
        let travel = max(width - Self.thumbSize, 1)
        let fraction = Double(min(max((x - Self.thumbSize / 2) / travel, 0), 1))
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }

    private var accessibilityValue: String {
        if abs(hours) < 1.0 / 60 { return "Now" }
        let minutes = Int((abs(hours) * 60).rounded())
        let text = AngleFormatter.formatDuration(seconds: Double(minutes) * 60)
        return hours < 0 ? "\(text) earlier" : "\(text) later"
    }
}
