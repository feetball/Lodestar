import SwiftUI
import LodestarKit

/// One month of the calendar.
private struct EventsMonth: Identifiable {
    let id: String
    let title: String
    let entries: [EventsEntry]
}

/// The astronomical events of the next twelve months, grouped by month, with a filter by kind and a switch that
/// keeps only what can be seen from the observer's place.
struct EventsCalendarView: View {
    @Environment(AppModel.self) private var app
    @Environment(EventsModel.self) private var model
    @Environment(\.palette) private var palette

    @AppStorage("lodestar.events.visibleOnly") private var showsOnlyVisible = false
    @State private var categories: Set<EventsCategory> = []
    @State private var now = Date()

    var body: some View {
        Group {
            if let context = app.observerContext {
                content(context: context)
                    .task(id: context) {
                        await keepFresh(context: context)
                    }
            } else {
                NeedsLocationView()
            }
        }
        .screenBackground(palette)
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Content

    private func content(context: ObserverContext) -> some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                filterCard
                if let entries = model.entries {
                    let months = months(of: filtered(entries), in: context)
                    if months.isEmpty {
                        emptyCard
                    } else {
                        ForEach(months) { month in
                            Section {
                                monthCard(month, context: context)
                            } header: {
                                monthHeader(month.title)
                            }
                        }
                    }
                    footer(context: context)
                } else {
                    pendingCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .symbolRenderingMode(.monochrome)
    }

    private func monthCard(_ month: EventsMonth, context: ObserverContext) -> some View {
        let isSouthern = context.location.latitude < 0
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(month.entries) { entry in
                if entry.id != month.entries.first?.id {
                    TonightRowSeparator()
                }
                EventsRowLink(entry: entry, timeZone: context.timeZone, isSouthernHemisphere: isSouthern)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func monthHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(palette.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(palette.background)
            .accessibilityAddTraits(.isHeader)
    }

    private var pendingCard: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(palette.accent)
            Text("Working out the events\u{2026}")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .card(palette)
        .accessibilityElement(children: .combine)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(palette.tertiaryText)
                .accessibilityHidden(true)
            Text("No events match the filters.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            Button("Reset Filters") {
                categories = []
                showsOnlyVisible = false
            }
            .buttonStyle(.lodestarSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .card(palette)
    }

    private func footer(context: ObserverContext) -> some View {
        let zone = EventsFormat.zoneName(context.timeZone, at: now)
        return VStack(alignment: .leading, spacing: 4) {
            TonightNote(text: "\(context.name) \u{00B7} times in \(zone). Conjunctions are listed when the pair comes "
                        + "within 3\u{00B0}. \u{201C}Visible from here\u{201D} means there is a window with the target "
                        + "at least 10\u{00B0} high and the sky dark enough.", style: .footnote)
            TonightNote(text: "Meteor shower data: International Meteor Organization.", style: .footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Filter

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    EventsFilterChip(title: "All", systemImage: "list.bullet", isSelected: categories.isEmpty) {
                        categories = []
                    }
                    ForEach(EventsCategory.allCases) { category in
                        EventsFilterChip(title: category.title, systemImage: category.systemImage,
                                         isSelected: categories.contains(category)) {
                            toggle(category)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            TonightRowSeparator()
            Toggle(isOn: $showsOnlyVisible) {
                Label("Visible from here only", systemImage: "eye")
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
            }
            .tint(palette.accent)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func toggle(_ category: EventsCategory) {
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
    }

    // MARK: Data

    /// The entries that have not happened yet, in the chosen categories (all when none is chosen), and, with the
    /// switch on, only those that are not known to be out of sight.
    private func filtered(_ entries: [EventsEntry]) -> [EventsEntry] {
        entries.filter { entry in
            guard entry.event.date >= now else { return false }
            if showsOnlyVisible, entry.isVisibleFromHere == false { return false }
            return categories.isEmpty || categories.contains { $0.includes(entry.event) }
        }
    }

    private func months(of entries: [EventsEntry], in context: ObserverContext) -> [EventsMonth] {
        let calendar = context.calendar
        var months: [EventsMonth] = []
        var current: (id: String, title: String, entries: [EventsEntry])?
        for entry in entries {
            let parts = calendar.dateComponents([.year, .month], from: entry.event.date)
            let id = "\(parts.year ?? 0)-\(parts.month ?? 0)"
            if let open = current, open.id == id {
                current?.entries.append(entry)
            } else {
                if let open = current {
                    months.append(EventsMonth(id: open.id, title: open.title, entries: open.entries))
                }
                current = (id, EventsFormat.month(entry.event.date, in: context.timeZone), [entry])
            }
        }
        if let open = current {
            months.append(EventsMonth(id: open.id, title: open.title, entries: open.entries))
        }
        return months
    }

    /// Starts the computation if needed and keeps `now` current to the minute.
    private func keepFresh(context: ObserverContext) async {
        while !Task.isCancelled {
            now = app.clock.now
            model.refresh(context: context, now: now)
            try? await Task.sleep(for: .seconds(60))
        }
    }
}

/// A toggle chip of the calendar's kind filter.
private struct EventsFilterChip: View {
    @Environment(\.palette) private var palette

    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? palette.onAccent : palette.secondaryText)
                .background(Capsule().fill(isSelected ? palette.accent : palette.surfaceRaised))
                .overlay(Capsule().strokeBorder(palette.stroke, lineWidth: isSelected ? 0 : 0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Selected" : "Filters the list")
    }
}
