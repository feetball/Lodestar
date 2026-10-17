import Foundation

/// The app's notion of time.
///
/// `now` is the live wall-clock time (ticks once per second while running) and is what the Aim
/// screen always uses. `displayDate` adds an optional "time travel" offset for planning views
/// such as the sky chart.
@MainActor
@Observable
final class SkyClock {
    /// Live time, refreshed every second while the clock runs.
    private(set) var now = Date()
    /// Time-travel offset applied to `displayDate`, in seconds.
    private(set) var offset: TimeInterval = 0

    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// The instant planning views display.
    var displayDate: Date { now.addingTimeInterval(offset) }

    /// `true` while no time-travel offset is applied.
    var isLive: Bool { offset == 0 }

    func start() {
        guard tickTask == nil else { return }
        now = Date()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.now = Date()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Shows the sky at `date` in planning views (limited to ±1 year from now).
    func travel(to date: Date) {
        let limit: TimeInterval = 366 * 86_400
        offset = min(max(date.timeIntervalSince(Date()), -limit), limit)
        now = Date()
    }

    /// Shifts the time-travel offset by `seconds`.
    func travel(by seconds: TimeInterval) {
        travel(to: displayDate.addingTimeInterval(seconds))
    }

    func returnToNow() {
        offset = 0
        now = Date()
    }
}
