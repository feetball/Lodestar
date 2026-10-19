import SwiftUI
import LodestarKit

/// The Tonight tab: plan a night of astrophotography. It shows when it is dark, where the Moon is, when the
/// Milky Way's core can be photographed, which planets and deep-sky objects are worth the trouble, and where
/// the pole star stands for aligning a tracker.
///
/// The night defaults to the one under way (or the coming one by day); the selector and calendar reach a year
/// either way. Planets and targets open `ObjectDetailView`; the Upcoming card opens the events calendar and the
/// detail screens of astronomical events.
struct TonightView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    /// The astronomical events of the next twelve months, shared by the Upcoming card and the calendar.
    @State private var events = EventsModel()

    var body: some View {
        NavigationStack {
            content
                .screenBackground(palette)
                .navigationTitle("Tonight")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: CelestialObject.self) { object in
                    ObjectDetailView(object: object)
                }
                .navigationDestination(for: SmallBodyListRoute.self) { _ in
                    SmallBodyListView()
                }
                .eventsDestinations()
        }
        .environment(events)
        .task {
            await app.catalog.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let context = app.observerContext {
            TonightScreen(context: context)
        } else {
            NeedsLocationView()
        }
    }
}
