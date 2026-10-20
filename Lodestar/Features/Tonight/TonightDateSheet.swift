import SwiftUI

/// Chooses the night to plan with a month calendar drawn from palette colours.
///
/// The system date picker is white on black, which would undo night vision, so the days are buttons.
/// A night is named after the evening it starts on and runs from noon to noon.
struct TonightDateSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let timeZone: TimeZone
    /// The night now shown.
    let selected: Date
    /// The night under way (or coming), marked in the calendar.
    let tonight: Date
    /// The nights that can be chosen.
    let range: ClosedRange<Date>
    let onSelect: (TonightNightChoice) -> Void

    /// The first instant of the month on show.
    @State private var monthStart: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    init(timeZone: TimeZone, selected: Date, tonight: Date, range: ClosedRange<Date>,
         onSelect: @escaping (TonightNightChoice) -> Void) {
        self.timeZone = timeZone
        self.selected = selected
        self.tonight = tonight
        self.range = range
        self.onSelect = onSelect
        let calendar = Self.makeCalendar(timeZone: timeZone)
        _monthStart = State(initialValue: calendar.dateInterval(of: .month, for: selected)?.start ?? selected)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    monthHeader
                    weekdayHeader
                    dayGrid
                    Text("A night is named after the evening it starts on and runs from noon to noon.")
                        .font(.footnote)
                        .foregroundStyle(palette.tertiaryText)
                    Button {
                        onSelect(.tonight)
                        dismiss()
                    } label: {
                        Label("Tonight", systemImage: "moon.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.lodestarPrimary)
                }
                .padding(16)
            }
            .screenBackground(palette)
            .symbolRenderingMode(.monochrome)
            .navigationTitle("Choose a Night")
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

    // MARK: Calendar

    private var calendar: Calendar { Self.makeCalendar(timeZone: timeZone) }

    private static func makeCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    private func shiftMonth(by months: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: months, to: monthStart) else { return }
        monthStart = shifted
    }

    private var canShowPreviousMonth: Bool { monthStart > range.lowerBound }

    private var canShowNextMonth: Bool {
        calendar.date(byAdding: .month, value: 1, to: monthStart).map { $0 <= range.upperBound } ?? false
    }

    /// The month's days in grid order, with empty cells before the first of the month. Each day is the
    /// noon that stands for the night starting on it.
    private var cells: [Date?] {
        guard let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7
        let days: [Date?] = (0..<dayCount).map { offset in
            calendar.date(byAdding: .day, value: offset, to: monthStart)
                .map { TonightCalculator.localNoon(of: $0, calendar: calendar) }
        }
        return Array(repeating: nil, count: leadingBlanks) + days
    }

    // MARK: Parts

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.lodestarSecondary)
            .disabled(!canShowPreviousMonth)
            .accessibilityLabel("Previous month")
            Text(monthStart.formatted(Date.FormatStyle(timeZone: timeZone).month(.wide).year()))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.lodestarSecondary)
            .disabled(!canShowNextMonth)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        let ordered = Array(symbols[shift...] + symbols[..<shift])
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityHidden(true)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let day = cell {
                    dayButton(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isTonight = calendar.isDate(day, inSameDayAs: tonight)
        let isAllowed = range.contains(day)
        let textColor = isSelected ? palette.onAccent : (isAllowed ? palette.primaryText : palette.tertiaryText)
        return Button {
            onSelect(.date(day))
            dismiss()
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.body.weight(isSelected ? .bold : .regular).monospacedDigit())
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Circle().fill(isSelected ? palette.accent : Color.clear))
                .overlay(Circle().strokeBorder(isTonight && !isSelected ? palette.accent : Color.clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isAllowed)
        .accessibilityLabel(spokenDate(day) + (isTonight ? ", tonight" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func spokenDate(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(date: .complete, time: .omitted, timeZone: timeZone))
    }
}
