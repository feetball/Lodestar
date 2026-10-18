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
        locator.requestAuthorization()
    }

    /// Works out the entries again for the current place and asks the complications to do the same.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let place: TonightPlace?
        if let phonePlace {
            place = phonePlace
        } else {
            place = await locator.currentPlace()
        }
        let now = Date()
        guard let place else {
            entries = []
            needsLocation = true
            isLoading = false
            return
        }
        entries = await Task.detached(priority: .userInitiated) {
            TonightBuilder.entries(for: place, from: now)
        }.value
        needsLocation = false
        isLoading = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func receive(_ place: TonightPlace) async {
        guard place != phonePlace else { return }
        phonePlace = place
        TonightPlaceStore.save(place, as: .phone)
        await refresh()
    }
}
