import SwiftUI

extension View {
    /// Registers the destinations of the events screens in the enclosing `NavigationStack`: an event opens its detail
    /// screen and `EventsCalendarRoute` opens the calendar. The stack also needs the `EventsModel` in its environment.
    func eventsDestinations() -> some View {
        navigationDestination(for: EventsEntry.self) { entry in
            EventsDetailView(entry: entry)
        }
        .navigationDestination(for: EventsCalendarRoute.self) { _ in
            EventsCalendarView()
        }
    }
}
