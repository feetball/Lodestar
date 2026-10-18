import SwiftUI
import LodestarKit

/// The next few astronomical events, for the Tonight screen: each opens its detail screen, and "Calendar" opens the
/// whole next twelve months. It starts the events computation for the observer, which the calendar then shares.
struct EventsUpcomingCard: View {
    /// The most events the card lists.
    static let rowLimit = 4

    @Environment(AppModel.self) private var app
    @Environment(EventsModel.self) private var model
    @Environment(\.palette) private var palette

    let context: ObserverContext

    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                CardTitle(title: "Upcoming", systemImage: "calendar")
                NavigationLink(value: EventsCalendarRoute()) {
                    HStack(spacing: 4) {
                        Text("Calendar")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Calendar")
                .accessibilityHint("Opens the events of the next twelve months")
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
        .task(id: context) {
            await keepFresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.entries == nil {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(palette.accent)
                Text("Working out the events\u{2026}")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        } else {
            let upcoming = Array(model.upcoming(after: now).prefix(Self.rowLimit))
            if upcoming.isEmpty {
                TonightNote(text: "No events are listed for the coming months.")
            } else {
                let isSouthern = context.location.latitude < 0
                ForEach(upcoming) { entry in
                    if entry.id != upcoming.first?.id {
                        TonightRowSeparator()
                    }
                    EventsRowLink(entry: entry, timeZone: context.timeZone, isSouthernHemisphere: isSouthern)
                }
            }
        }
    }

    /// Starts the computation, then checks once a minute that the list still starts at the present and fits the day.
    private func keepFresh() async {
        while !Task.isCancelled {
            now = app.clock.now
            model.refresh(context: context, now: now)
            try? await Task.sleep(for: .seconds(60))
        }
    }
}
