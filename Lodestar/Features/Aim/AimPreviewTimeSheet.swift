import SwiftUI
import LodestarKit

/// Sets the previewed date and time with large buttons drawn from palette colours.
///
/// The system date picker is white on black, which would undo night vision; steps in days, hours and minutes reach any
/// moment within 48 hours of now and stay red in night mode. Every change applies at once; the readout shows the result.
struct AimPreviewTimeSheet: View {
    let model: AimViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    readout
                    section("Day", steps: Self.dayShifts)
                    section("Time", steps: Self.timeShifts)
                    presets
                }
                .padding(16)
            }
        }
        .background(palette.background)
        .foregroundStyle(palette.primaryText)
        .presentationBackground(palette.background)
    }

    private var header: some View {
        HStack {
            Text("Preview Time")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.lodestarSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.previewTimeZone
        return calendar
    }

    private var readout: some View {
        let date = model.date
        let zone = model.previewTimeZone
        return VStack(alignment: .leading, spacing: 4) {
            Text(AppFormat.day(date, in: zone))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            Text(AppFormat.time(date, in: zone))
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primaryText)
            Text(model.isPreviewing ? AppFormat.relative(date, from: model.app.clock.now) : "Live")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, steps: [Shift]) -> some View {
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
                gridButton("Now", kind: .primary) { model.endPreview() }
                    .disabled(!model.isPreviewing)
                gridButton("Tonight 22:00", kind: .secondary) {
                    jump(to: calendar.date(bySettingHour: 22, minute: 0, second: 0, of: model.app.clock.now))
                }
                gridButton("Midnight", kind: .secondary) {
                    jump(to: calendar.nextDate(after: model.app.clock.now, matching: DateComponents(hour: 0, minute: 0),
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

    private func apply(_ shift: Shift) {
        jump(to: calendar.date(byAdding: shift.component, value: shift.value, to: model.date))
    }

    private func jump(to date: Date?) {
        guard let date else { return }
        model.previewAt(date)
    }

    /// A button of the sheet: move the previewed time by a number of calendar units.
    private struct Shift: Identifiable {
        let title: String
        let accessibilityLabel: String
        let component: Calendar.Component
        let value: Int

        var id: String { title }
    }

    private static let dayShifts = [
        Shift(title: "\u{2212}1 day", accessibilityLabel: "One day earlier", component: .day, value: -1),
        Shift(title: "+1 day", accessibilityLabel: "One day later", component: .day, value: 1),
    ]

    private static let timeShifts = [
        Shift(title: "\u{2212}1 hour", accessibilityLabel: "One hour earlier", component: .hour, value: -1),
        Shift(title: "\u{2212}10 min", accessibilityLabel: "Ten minutes earlier", component: .minute, value: -10),
        Shift(title: "+10 min", accessibilityLabel: "Ten minutes later", component: .minute, value: 10),
        Shift(title: "+1 hour", accessibilityLabel: "One hour later", component: .hour, value: 1),
    ]
}
