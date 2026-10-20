import SwiftUI
import LodestarKit

/// Sets the sky chart's date and time with large buttons drawn from palette colours.
///
/// The system date picker is white on black, which would undo night vision; steps in days, hours
/// and minutes reach any moment within the clock's range and stay red in night mode.
struct SkyChartDateSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let timeZone: TimeZone

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    readout
                    section("Date", steps: SkyChartTimeStep.dateSteps)
                    section("Time", steps: SkyChartTimeStep.timeSteps)
                    presets
                }
                .padding(16)
            }
            .screenBackground(palette)
            .navigationTitle("Sky Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheetDragIndicator(palette, daytime: .automatic)
        .presentationBackground(palette.background)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private var readout: some View {
        let clock = app.clock
        return VStack(alignment: .leading, spacing: 4) {
            Text(AppFormat.day(clock.displayDate, in: timeZone))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            Text(AppFormat.time(clock.displayDate, in: timeZone))
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primaryText)
            Text(clock.isLive ? "Live" : AppFormat.relative(clock.displayDate, from: clock.now))
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, steps: [SkyChartTimeStep]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: title)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(steps) { step in
                    gridButton(step.title, kind: .secondary) { apply(step) }
                        .accessibilityLabel(step.accessibilityLabel)
                }
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "Jump to")
            LazyVGrid(columns: columns, spacing: 10) {
                gridButton("Now", kind: .primary) { app.clock.returnToNow() }
                    .disabled(app.clock.isLive)
                gridButton("Tonight 22:00", kind: .secondary) {
                    jump(to: calendar.date(bySettingHour: 22, minute: 0, second: 0, of: app.clock.now))
                }
                gridButton("Midnight", kind: .secondary) {
                    jump(to: calendar.nextDate(after: app.clock.now, matching: DateComponents(hour: 0, minute: 0),
                                               matchingPolicy: .nextTime))
                }
            }
        }
    }

    /// A button that fills its grid cell.
    private func gridButton(_ title: String, kind: LodestarButtonStyle.Kind,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LodestarButtonStyle(kind: kind))
    }

    private func apply(_ step: SkyChartTimeStep) {
        jump(to: calendar.date(byAdding: step.component, value: step.value, to: app.clock.displayDate))
    }

    private func jump(to date: Date?) {
        guard let date else { return }
        app.clock.travel(to: date)
    }
}

/// A button of the date sheet: move the displayed time by a number of calendar units.
private struct SkyChartTimeStep: Identifiable {
    let title: String
    let accessibilityLabel: String
    let component: Calendar.Component
    let value: Int

    var id: String { title }

    static let dateSteps = [
        SkyChartTimeStep(title: "\u{2212}1 month", accessibilityLabel: "One month earlier",
                         component: .month, value: -1),
        SkyChartTimeStep(title: "\u{2212}1 week", accessibilityLabel: "One week earlier", component: .day, value: -7),
        SkyChartTimeStep(title: "\u{2212}1 day", accessibilityLabel: "One day earlier", component: .day, value: -1),
        SkyChartTimeStep(title: "+1 day", accessibilityLabel: "One day later", component: .day, value: 1),
        SkyChartTimeStep(title: "+1 week", accessibilityLabel: "One week later", component: .day, value: 7),
        SkyChartTimeStep(title: "+1 month", accessibilityLabel: "One month later", component: .month, value: 1),
    ]

    static let timeSteps = [
        SkyChartTimeStep(title: "\u{2212}1 hour", accessibilityLabel: "One hour earlier", component: .hour, value: -1),
        SkyChartTimeStep(title: "\u{2212}10 min", accessibilityLabel: "Ten minutes earlier",
                         component: .minute, value: -10),
        SkyChartTimeStep(title: "+10 min", accessibilityLabel: "Ten minutes later", component: .minute, value: 10),
        SkyChartTimeStep(title: "+1 hour", accessibilityLabel: "One hour later", component: .hour, value: 1),
    ]
}
