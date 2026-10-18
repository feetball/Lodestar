import SwiftUI
import LodestarKit

/// The visible passes of the next three days, grouped by day, with a filter for the ISS alone or all bright satellites, a
/// warning when the orbit data is too old for exact times, and a way into each pass.
struct SatellitePassesView: View {
    let board: SatellitePassBoard
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var filter = SatellitePassFilter.iss

    var body: some View {
        Group {
            if app.online.isEnabled(.satellites) {
                list
            } else {
                EmptyStateView(title: SatelliteText.offTitle, systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                               message: SatelliteText.offMessage)
            }
        }
        .screenBackground(palette)
        .navigationTitle(SatelliteText.passesTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var timeZone: TimeZone { app.observerContext?.timeZone ?? .autoupdatingCurrent }

    private var list: some View {
        // The list moves on once a minute, not with the clock's second.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Show", selection: $filter) {
                        ForEach(SatellitePassFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    rows(now: timeline.date)
                    TonightNote(text: SatelliteText.visibleOnly, style: .footnote)
                    TonightNote(text: SatelliteText.attribution, style: .footnote)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func rows(now: Date) -> some View {
        let library = app.online.satellites
        if library.hasPassData && library.isPassDataStale(at: now) {
            TonightNote(text: SatelliteText.stale, style: .warning)
        }
        if !library.hasPassData {
            TonightNote(text: SatelliteText.loading)
        } else if let items = board.items {
            let passes = SatellitePasses.upcoming(SatellitePasses.filtered(items, filter: filter), now: now)
            if passes.isEmpty {
                TonightNote(text: SatelliteText.noPasses)
            } else {
                ForEach(dayGroups(passes, now: now), id: \.day) { group in
                    Text(group.day.uppercased())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.passes) { item in
                        NavigationLink {
                            SatellitePassDetailView(item: item)
                        } label: {
                            SatellitePassRow(item: item, timeZone: timeZone, now: now, showsChevron: true)
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.surface))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            TonightNote(text: SatelliteText.finding)
        }
    }

    private struct DayGroup {
        let day: String
        let passes: [SatellitePassItem]
    }

    /// The passes under "Today", "Tomorrow" or "Sat, Oct 20", in time order.
    private func dayGroups(_ passes: [SatellitePassItem], now: Date) -> [DayGroup] {
        var groups: [DayGroup] = []
        for item in passes {
            let day = Self.dayLabel(item, now: now, timeZone: timeZone)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, passes: last.passes + [item])
            } else {
                groups.append(DayGroup(day: day, passes: [item]))
            }
        }
        return groups
    }

    /// The weekday and date a pass is listed under: "Today", "Tomorrow" or "Sat, Oct 20".
    static func dayLabel(_ item: SatellitePassItem, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(item.start, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(item.start, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return AppFormat.day(item.start, in: timeZone)
    }
}
