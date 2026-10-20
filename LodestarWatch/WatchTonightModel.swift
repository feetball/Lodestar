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
    /// What the user has to do about it while `needsLocation` is `true`.
    private(set) var locationIssue: TonightLocationIssue = .notAsked
    /// Where the place of the last refresh came from, so the screen can say which place it is for; `nil` without one.
    /// (The complications always use the watch's own location, so they can differ from a place sent by the iPhone.)
    private(set) var placeSource: TonightPlaceStore.Source?

    @ObservationIgnored private let locator = TonightLocator()
    @ObservationIgnored private var link: WatchPhoneLink?
    @ObservationIgnored private var phonePlace = TonightPlaceStore.load(.phone)
    @ObservationIgnored private var isRefreshing = false
    /// Set when the iPhone's place arrives during a refresh, which then works it out again with the new place.
    @ObservationIgnored private var isPlaceStale = false

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

    /// Works out the entries again for the current place and asks the complications to work theirs out again too
    /// (for the watch's own location, which they always use).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            isPlaceStale = false
            await refreshOnce()
        } while isPlaceStale
    }

    private func refreshOnce() async {
        let (place, source, now) = await placeAndDate()
        guard let place else {
            entries = []
            placeSource = nil
            locationIssue = locator.locationIssue
            needsLocation = true
            isLoading = false
            return
        }
        entries = await Task.detached(priority: .userInitiated) {
            TonightBuilder.entries(for: place, from: now)
        }.value
        placeSource = source
        needsLocation = false
        isLoading = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The place to work for, where it came from, and the moment to start from. (The visual review of the Simulator
    /// fixes the place and the moment.)
    private func placeAndDate() async -> (TonightPlace?, TonightPlaceStore.Source, Date) {
        #if DEBUG
        if let review = WatchReviewMode.current { return (review.place, .device, review.date) }
        #endif
        if let phonePlace { return (phonePlace, .phone, Date()) }
        return (await locator.currentPlace(), .device, Date())
    }

    private func receive(_ place: TonightPlace) async {
        guard place != phonePlace else { return }
        phonePlace = place
        TonightPlaceStore.save(place, as: .phone)
        if isRefreshing {
            // A refresh that is already under way may have chosen the place before this one arrived.
            isPlaceStale = true
        } else {
            await refresh()
        }
    }
}
