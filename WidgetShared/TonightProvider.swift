import Foundation
import WidgetKit

extension TonightEntry: TimelineEntry {}

/// Feeds the widgets and the complications: where the device is, and a day of entries worked out for it.
///
/// Everything runs on the device with LodestarKit: no network, no App Group. The location comes from Core Location
/// in the widget itself (the system shares the app's authorization), so a widget or complication always shows the
/// device's own place, never the observer chosen in the iPhone app (the watch app may show that one). With no
/// place, the entry says what the user has to do: open Lodestar to allow location, or allow it in Settings.
struct TonightProvider: TimelineProvider {
    /// How long a timeline is used before a new one is asked for (it holds entries for a day).
    static let reloadInterval: TimeInterval = 6 * 3_600
    /// How long the "allow location" state waits before trying again. Long, because it can only end once the user
    /// has acted, and the app asks for a reload whenever it comes forward.
    static let needsLocationReloadInterval: TimeInterval = 3_600

    func placeholder(in context: Context) -> TonightEntry {
        TonightBuilder.entry(for: .preview(), at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TonightEntry) -> Void) {
        if context.isPreview {
            completion(TonightBuilder.entry(for: .preview(), at: Date()))
            return
        }
        Task { @MainActor in
            // A snapshot has to come back quickly, so it does not wait for a fresh fix: the place remembered from
            // the last timeline will do.
            let locator = TonightLocator()
            let now = Date()
            guard locator.isAuthorized, let place = TonightPlaceStore.load(.device) else {
                completion(.needsLocation(at: now, issue: locator.locationIssue))
                return
            }
            let entry = await Task.detached(priority: .userInitiated) {
                TonightBuilder.entry(for: place, at: now)
            }.value
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TonightEntry>) -> Void) {
        Task { @MainActor in
            let locator = TonightLocator()
            let place = await locator.currentPlace()
            let now = Date()
            guard let place else {
                completion(Timeline(entries: [.needsLocation(at: now, issue: locator.locationIssue)],
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
