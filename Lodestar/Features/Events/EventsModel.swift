import Foundation
import LodestarKit
import Observation

/// Works out the events of the next twelve months off the main actor and keeps the result for the observer and the
/// day, so the Tonight card and the calendar share one computation.
///
/// The events are worked out again when the local day changes, when the time zone changes or when the observer moves
/// more than `EventsKey.placeToleranceKilometers`.
@MainActor
@Observable
final class EventsModel {
    /// The events, in time order, or `nil` until the first run has finished (and while another place is worked out).
    private(set) var entries: [EventsEntry]?

    /// The key `entries` were worked out for; `nil` while there are none.
    @ObservationIgnored private var loadedKey: EventsKey?
    @ObservationIgnored private var pendingKey: EventsKey?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Starts a run when the stored events do not fit `context` and `now`. Cheap to call often: a run in progress or a
    /// result that still fits makes it return at once.
    func refresh(context: ObserverContext, now: Date) {
        let key = EventsKey(context: context, now: now)
        if let loadedKey, loadedKey.covers(key) {
            // The stored events fit again: a run for another key would replace them with events that do not.
            task?.cancel()
            pendingKey = nil
            return
        }
        if let pendingKey, pendingKey.covers(key) { return }
        // Events of another place would show the wrong visibility; another day is only a little out of date.
        if let loadedKey, !loadedKey.isNear(key) || loadedKey.timeZone.identifier != key.timeZone.identifier {
            entries = nil
            self.loadedKey = nil
        }
        pendingKey = key
        task?.cancel()
        task = Task { [weak self] in
            let computed = await Task.detached(priority: .userInitiated) {
                EventsCalculator.entries(for: key)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.entries = computed
            self.loadedKey = key
            self.pendingKey = nil
        }
    }

    /// The events that have not happened yet at `now`, in time order.
    func upcoming(after now: Date) -> [EventsEntry] {
        (entries ?? []).filter { $0.event.date >= now }
    }
}
