import Foundation
import LodestarKit
import Observation

/// What Settings ▸ Online Data shows about one feed.
struct OnlineFeedStatus: Equatable, Sendable {
    var isEnabled = false
    /// When the feed's data was last confirmed current (the oldest of its files); `nil` for never.
    var lastUpdate: Date?
    var isUpdating = false
    /// A sentence about the last attempt when it failed or is waiting; the saved data stays in use.
    var error: String?
    /// The earliest time "Update now" is allowed again, when that is in the future.
    var nextRequest: Date?
}

/// The optional downloads (satellite elements, Starlink elements, comets, the cloud forecast) and what comes of them.
///
/// Everything is off until the user switches a feed on. A feed is refreshed when the app becomes active, when it is
/// switched on and when a screen asks for a forecast; there are no background tasks. Downloads, parsing and satellite
/// construction run off the main actor, one at a time; results appear in the observable properties of this class
/// (`statuses`, `satellites`, `forecast`) and in the catalog (comets). A failed or unreadable download keeps the saved
/// data. Turning a feed off deletes its saved data and the copy in memory.
@MainActor
@Observable
final class OnlineDataService {
    /// Added to a server's `Expires` so that the app's users do not all ask in the same minute (MET Norway asks for it).
    private static let maximumJitter: TimeInterval = 300

    /// The state of every feed.
    private(set) var statuses: [OnlineFeed: OnlineFeedStatus]
    /// The satellites in memory (empty while the feeds are off).
    private(set) var satellites = SatelliteLibrary.empty
    /// The cloud forecast in memory, for the place it was requested for.
    private(set) var forecast: CloudForecast?
    /// Whether the user has read the first-time explanation.
    private(set) var hasExplained: Bool

    /// Where the observer is, for the forecast; set by the app model.
    @ObservationIgnored var locationProvider: @MainActor () -> GeographicLocation? = { nil }

    @ObservationIgnored private let catalog: CatalogService
    @ObservationIgnored private let store: OnlineStore
    @ObservationIgnored private let refresher: OnlineRefresher
    @ObservationIgnored private let expiresJitter = TimeInterval.random(in: 0..<OnlineDataService.maximumJitter)
    @ObservationIgnored private var loaded = Set<OnlineFeed>()
    @ObservationIgnored private var workTail: Task<Void, Never>?

    init(catalog: CatalogService, store: OnlineStore = OnlineStore(), refresher: OnlineRefresher = OnlineRefresher()) {
        self.catalog = catalog
        self.store = store
        self.refresher = refresher
        hasExplained = store.hasExplained
        var initial: [OnlineFeed: OnlineFeedStatus] = [:]
        for feed in OnlineFeed.allCases {
            initial[feed] = OnlineFeedStatus(isEnabled: store.isEnabled(feed))
        }
        statuses = initial
    }

    // MARK: Queries

    /// Whether `feed` is switched on.
    func isEnabled(_ feed: OnlineFeed) -> Bool { status(feed).isEnabled }

    func status(_ feed: OnlineFeed) -> OnlineFeedStatus { statuses[feed] ?? OnlineFeedStatus() }

    // MARK: Changes

    /// Remembers that the first-time explanation was shown.
    func markExplained() {
        hasExplained = true
        store.hasExplained = true
    }

    /// Switches `feed` on (and downloads it at once) or off (and deletes what it downloaded).
    func setEnabled(_ feed: OnlineFeed, _ enabled: Bool) {
        guard isEnabled(feed) != enabled else { return }
        statuses[feed] = OnlineFeedStatus(isEnabled: enabled)
        store.setEnabled(feed, enabled)
        if enabled {
            enqueue { service in
                await service.loadSaved(feed)
                await service.refresh(feed, manual: false)
            }
        } else {
            clearMemory(feed)
            let cache = refresher.cache
            enqueue { service in
                for resource in feed.resources { cache.delete(resource.key) }
                service.loaded.remove(feed)
            }
        }
    }

    /// Downloads `feed` now, if its request rules allow it.
    func updateNow(_ feed: OnlineFeed) {
        guard isEnabled(feed) else { return }
        enqueue { service in
            await service.loadSaved(feed)
            await service.refresh(feed, manual: true)
        }
    }

    /// Loads the saved data of the feeds that are on and refreshes the stale ones. Call when the app becomes active.
    func onForeground() {
        for feed in OnlineFeed.allCases where isEnabled(feed) {
            enqueue { service in
                guard service.isEnabled(feed) else { return }
                await service.loadSaved(feed)
                await service.refresh(feed, manual: false)
            }
        }
    }

    /// Asks for the forecast of the current place if the one in memory is for another place or has expired.
    func refreshForecast() {
        guard isEnabled(.clouds) else { return }
        enqueue { service in
            await service.loadSaved(.clouds)
            await service.refresh(.clouds, manual: false)
        }
    }

    // MARK: Work queue

    /// Runs `job` after the jobs queued before it: one download at a time.
    private func enqueue(_ job: @escaping @MainActor (OnlineDataService) async -> Void) {
        let previous = workTail
        workTail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await job(self)
        }
    }

    // MARK: Loading

    private func loadSaved(_ feed: OnlineFeed) async {
        guard loaded.insert(feed).inserted else { return }
        for resource in feed.resources {
            if let (data, _) = await refresher.loadCached(resource), isEnabled(feed) { publish(data) }
        }
        await publishStatus(feed)
    }

    // MARK: Refreshing

    private func refresh(_ feed: OnlineFeed, manual: Bool) async {
        for resource in feed.resources {
            guard isEnabled(feed) else { return }
            await refreshResource(feed, resource: resource, manual: manual)
        }
        await publishStatus(feed)
    }

    private func refreshResource(_ feed: OnlineFeed, resource: OnlineResource, manual: Bool) async {
        let now = Date()
        let place = resource == .forecast ? locationProvider() : nil
        if resource == .forecast && place == nil {
            update(feed) { $0.error = "Choose an observing location to get a cloud forecast." }
            return
        }
        let key = place.map { OnlineCoordinates.key(latitude: $0.latitude, longitude: $0.longitude) }
        let state = await refresher.state(resource)
        guard OnlineSchedule.mayRequest(resource, state: state, now: now, key: key, expiresJitter: expiresJitter) else { return }
        guard manual || OnlineSchedule.isDue(resource, state: state, now: now, key: key) else { return }
        guard let url = resource.url(latitude: place?.latitude, longitude: place?.longitude) else { return }
        update(feed) { $0.isUpdating = true }
        let outcome = await refresher.refresh(resource, url: url, key: key)
        update(feed) { $0.isUpdating = false }
        switch outcome {
        case .updated(let data, _):
            if isEnabled(feed) {
                publish(data)
                update(feed) { $0.error = nil }
            } else {
                // Switched off while the download was running: nothing of it stays.
                refresher.cache.delete(resource.key)
            }
        case .notModified:
            update(feed) { $0.error = nil }
        case .failed(_, let message):
            let kept = state.meta != nil ? " The saved data is kept." : ""
            update(feed) { $0.error = "The last update failed. \(message)\(kept)" }
        }
        await publishStatus(feed)
    }

    /// Puts parsed data where the screens read it.
    private func publish(_ data: OnlineLoaded) {
        switch data {
        case .satellites(let group):
            satellites = satellites.with(group)
        case .comets(let bodies):
            catalog.setDownloadedSmallBodies(bodies)
        case .forecast(let value):
            forecast = value
        }
    }

    private func publishStatus(_ feed: OnlineFeed) async {
        var updates: [Date] = []
        var next = Date.distantPast
        for resource in feed.resources {
            let state = await refresher.state(resource)
            if let saved = state.meta?.savedAt { updates.append(saved) }
            next = max(next, OnlineSchedule.earliestRequest(resource, state: state, key: forecastKey(resource),
                                                            expiresJitter: expiresJitter))
        }
        let oldest = updates.min()
        update(feed) {
            $0.lastUpdate = oldest
            $0.nextRequest = next > Date() ? next : nil
        }
    }

    private func forecastKey(_ resource: OnlineResource) -> String? {
        guard resource == .forecast, let place = locationProvider() else { return nil }
        return OnlineCoordinates.key(latitude: place.latitude, longitude: place.longitude)
    }

    // MARK: State

    private func update(_ feed: OnlineFeed, _ change: (inout OnlineFeedStatus) -> Void) {
        var status = self.status(feed)
        change(&status)
        statuses[feed] = status
    }

    private func clearMemory(_ feed: OnlineFeed) {
        switch feed {
        case .satellites, .starlink: satellites = satellites.without(feed)
        case .comets: catalog.setDownloadedSmallBodies([])
        case .clouds: forecast = nil
        }
    }
}
