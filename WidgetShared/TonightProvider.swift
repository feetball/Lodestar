import Foundation
import WidgetKit

extension TonightEntry: TimelineEntry {}

/// Feeds the widgets and the complications: where the device is, and a day of entries worked out for it.
///
/// Everything runs on the device with LodestarKit: no network, no App Group. The location comes from Core Location
/// in the widget itself (the system shares the app's authorization); with none, the entry asks the user to open
/// Lodestar.
struct TonightProvider: TimelineProvider {
    /// How long a timeline is used before a new one is asked for (it holds entries for a day).
    static let reloadInterval: TimeInterval = 6 * 3_600
    /// How long the "open Lodestar" state waits before trying again.
    static let needsLocationReloadInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> TonightEntry {
        TonightBuilder.entry(for: .preview(), at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TonightEntry) -> Void) {
        if context.isPreview {
            completion(TonightBuilder.entry(for: .preview(), at: Date()))
            return
        }
        Task { @MainActor in
            let locator = TonightLocator()
            let place = await locator.currentPlace()
            let now = Date()
            completion(place.map { TonightBuilder.entry(for: $0, at: now) } ?? .needsLocation(at: now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TonightEntry>) -> Void) {
        Task { @MainActor in
            let locator = TonightLocator()
            let place = await locator.currentPlace()
            let now = Date()
            guard let place else {
                completion(Timeline(entries: [.needsLocation(at: now)],
                                    policy: .after(now.addingTimeInterval(Self.needsLocationReloadInterval))))
                return
            }
            let entries = await Task.detached(priority: .userInitiated) {
                TonightBuilder.entries(for: place, from: now)
            }.value
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.reloadInterval))))
        }
    }
}
