import Foundation
import Observation
import WidgetKit

/// The state of the watch app's Tonight screen: the place (the iPhone's observer if it sent one, otherwise the
/// watch's own location) and a day of entries worked out for it.
@MainActor
@Observable
final class WatchTonightModel {
    /// The entries from the last refresh, in time order; empty until the first one, or without a place.
    private(set) var entries: [TonightEntry] = []
    /// `true` until the first refresh has finished.
    private(set) var isLoading = true
    /// `true` when there is no place to work for.
    private(set) var needsLocation = false

    @ObservationIgnored private let locator = TonightLocator()
    @ObservationIgnored private var link: WatchPhoneLink?
    @ObservationIgnored private var phonePlace = TonightPlaceStore.load(.phone)
    @ObservationIgnored private var isRefreshing = false

    /// Starts listening to the iPhone and asks for location access if the user has not been asked.
    func start() {
        guard link == nil else { return }
        let link = WatchPhoneLink { [weak self] place in
            Task { @MainActor [weak self] in await self?.receive(place) }
        }
        self.link = link
        link.activate()
        #if DEBUG
        // The visual review fixes the place, so it must not ask for the location.
        if WatchReviewMode.current != nil { return }
        #endif
        locator.requestAuthorization()
    }

    /// Works out the entries again for the current place and asks the complications to do the same. A place the iPhone
    /// sends meanwhile makes it start over, so that it never shows what was worked out for the place before.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var phone: TonightPlace?
        var computed: [TonightEntry]?
        repeat {
            phone = phonePlace
            computed = await entriesForCurrentPlace()
        } while phonePlace != phone
        guard let computed else {
            entries = []
            needsLocation = true
            isLoading = false
            return
        }
        entries = computed
        needsLocation = false
        isLoading = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The entries for the current place, or `nil` without a place.
    private func entriesForCurrentPlace() async -> [TonightEntry]? {
        let (place, now) = await placeAndDate()
        guard let place else { return nil }
        return await Task.detached(priority: .userInitiated) {
            TonightBuilder.entries(for: place, from: now)
        }.value
    }

    /// The place to work for and the moment to start from. (The visual review of the Simulator fixes both.)
    private func placeAndDate() async -> (TonightPlace?, Date) {
        #if DEBUG
        if let review = WatchReviewMode.current { return (review.place, review.date) }
        #endif
        if let phonePlace { return (phonePlace, Date()) }
        return (await locator.currentPlace(), Date())
    }

    private func receive(_ place: TonightPlace) async {
        guard place != phonePlace else { return }
        phonePlace = place
        TonightPlaceStore.save(place, as: .phone)
        // A refresh already under way sees the new place and starts over.
        await refresh()
    }
}
