import SwiftUI
import LodestarKit
import Observation

/// The visible passes of the next three days, found once off the main actor and shared by the Tonight card and the
/// Passes screen. They are found again when the satellite data or the observing place changes, and every half hour as the
/// window moves on.
@MainActor
@Observable
final class SatellitePassBoard {
    /// The window is moved on after this long.
    static let refreshAfter: TimeInterval = 30 * 60
    private static let checkEvery: Duration = .seconds(5 * 60)

    /// The passes, by the time they become visible; `nil` until they have been worked out.
    private(set) var items: [SatellitePassItem]?

    @ObservationIgnored private var generation = -1
    @ObservationIgnored private var observer: Observer?
    @ObservationIgnored private var computedAt = Date.distantPast
    /// Counts the requests, so that an answer that arrives after a newer request was made is dropped.
    @ObservationIgnored private var requestID = 0

    /// Works the passes out for `library` and `observer` unless they are already current at `now`.
    func ensure(library: SatelliteLibrary, observer: Observer, now: Date) async {
        let isCurrent = generation == library.generation && self.observer == observer
            && now.timeIntervalSince(computedAt) < Self.refreshAfter
        guard !isCurrent else { return }
        requestID += 1
        let request = requestID
        let found = await Task.detached(priority: .userInitiated) {
            SatellitePasses.compute(library: library, observer: observer, start: now)
        }.value
        guard request == requestID else { return }
        generation = library.generation
        self.observer = observer
        computedAt = now
        items = found
    }

    /// Forgets the passes (the satellite data went away).
    func clear() {
        requestID += 1
        generation = -1
        observer = nil
        items = nil
    }

    /// Keeps the passes up to date for as long as the calling task runs: works them out for the app's satellite data and
    /// observing place and again every few minutes. Call it from `.task(id:)` with the inputs in the id.
    func keepCurrent(app: AppModel, observer: Observer?) async {
        let library = app.online.satellites
        guard app.online.isEnabled(.satellites), let observer, library.hasPassData else {
            clear()
            return
        }
        while !Task.isCancelled {
            await ensure(library: library, observer: observer, now: app.clock.now)
            try? await Task.sleep(for: Self.checkEvery)
        }
    }
}

/// What restarts the board's background work: other satellite data, another place, the feed switched on or off.
struct SatelliteBoardKey: Equatable {
    var generation: Int
    var observer: Observer?
    var isOn: Bool
}
