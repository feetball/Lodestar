import Foundation

/// The outcome of `OnlineRefresher.refresh`.
enum OnlineRefreshOutcome: Sendable {
    /// New data was downloaded, parsed and cached.
    case updated(OnlineLoaded, OnlineCacheMeta)
    /// The server said the cached data is current.
    case notModified(OnlineCacheMeta)
    /// Nothing changed; whatever was cached stays.
    case failed(OnlineFailure, message: String)
}

/// One refresh of one resource: request (conditionally), validate with the parser, then replace the cache. A failed
/// request, an empty answer or an answer the parser rejects never touches the cached data. Every request is recorded in
/// the store before it is made, so the request rules hold even across crashes and across turning the feed off and on.
/// The functions are asynchronous and not tied to an actor, so the file work and the parsing stay off the main actor.
struct OnlineRefresher: Sendable {
    let cache: OnlineCache
    let downloader: OnlineDownloader
    let store: OnlineStore

    init(cache: OnlineCache = .standard(), downloader: OnlineDownloader = OnlineDownloader(), store: OnlineStore = OnlineStore()) {
        self.cache = cache
        self.downloader = downloader
        self.store = store
    }

    /// What the schedule needs to know about `resource`.
    func state(_ resource: OnlineResource) async -> OnlineResourceState {
        OnlineResourceState(lastAttempt: store.lastAttempt(resource), lastAttemptFailed: store.lastAttemptFailed(resource),
                            meta: cache.readMeta(resource.key))
    }

    /// Requests `url` for `resource`. `key` names the copy wanted (the forecast's rounded coordinates); the validators of
    /// the cached copy are sent only when it is the same copy.
    func refresh(_ resource: OnlineResource, url: URL, key: String?, now: Date = Date()) async -> OnlineRefreshOutcome {
        let cached = cache.readMeta(resource.key).flatMap { $0.key == key ? $0 : nil }
        let previousAttempt = store.lastAttempt(resource)
        let previousFailed = store.lastAttemptFailed(resource)
        store.setLastAttempt(resource, now)
        store.setLastAttemptFailed(resource, true)
        let request = OnlineRequest(url: url, maximumBytes: resource.maximumBytes, etag: cached?.etag,
                                    lastModified: cached?.lastModified, allowsExpensiveNetwork: !resource.requiresUnmetered)
        switch await downloader.fetch(request) {
        case .failed(let failure, let status):
            if failure.sentNothing {
                // Nothing reached the provider, so the request interval is not used up.
                store.setLastAttempt(resource, previousAttempt)
                store.setLastAttemptFailed(resource, previousFailed)
            }
            return .failed(failure, message: failure.message(statusCode: status))
        case .notModified(let expires):
            return notModified(resource, cached: cached, expires: expires)
        case .downloaded(let bytes, let etag, let lastModified, let expires):
            return downloaded(resource, key: key, bytes: bytes, etag: etag, lastModified: lastModified, expires: expires)
        }
    }

    /// The cached data parsed, or `nil` when there is none or it no longer parses (it is then removed).
    func loadCached(_ resource: OnlineResource) async -> (OnlineLoaded, OnlineCacheMeta)? {
        guard let entry = cache.read(resource.key) else { return nil }
        do {
            return (try OnlineParsing.parse(resource, data: entry.bytes, now: Date()).value, entry.meta)
        } catch {
            cache.delete(resource.key)
            return nil
        }
    }

    /// Takes `bytes` as if `resource` had just been downloaded: validates them, saves them, and returns the data, without a
    /// request. For tests and screenshots.
    func install(_ resource: OnlineResource, bytes: Data, key: String?, now: Date = Date()) async -> OnlineLoaded? {
        guard let parsed = try? OnlineParsing.parse(resource, data: bytes, now: now) else { return nil }
        let meta = OnlineCacheMeta(savedAt: now, dataEpoch: parsed.dataEpoch, key: key)
        guard (try? cache.write(resource.key, bytes: bytes, meta: meta)) != nil else { return nil }
        return parsed.value
    }

    // MARK: Private

    private func notModified(_ resource: OnlineResource, cached: OnlineCacheMeta?, expires: Date?) -> OnlineRefreshOutcome {
        guard var meta = cached else { return .failed(.empty, message: OnlineFailure.empty.message()) }
        meta.savedAt = Date()
        meta.expires = expires ?? meta.expires
        do {
            guard try cache.updateMeta(resource.key, meta: meta) else {
                return .failed(.empty, message: OnlineFailure.empty.message())
            }
            store.setLastAttemptFailed(resource, false)
            return .notModified(meta)
        } catch {
            return .failed(.storage, message: OnlineFailure.storage.message())
        }
    }

    private func downloaded(_ resource: OnlineResource, key: String?, bytes: Data, etag: String?, lastModified: String?,
                            expires: Date?) -> OnlineRefreshOutcome {
        let parsed: OnlineParsed<OnlineLoaded>
        do {
            parsed = try OnlineParsing.parse(resource, data: bytes, now: Date())
        } catch {
            return .failed(.unreadable, message: OnlineFailure.unreadable.message())
        }
        let meta = OnlineCacheMeta(savedAt: Date(), etag: etag, lastModified: lastModified, expires: expires,
                                   dataEpoch: parsed.dataEpoch, key: key)
        do {
            try cache.write(resource.key, bytes: bytes, meta: meta)
            store.setLastAttemptFailed(resource, false)
            return .updated(parsed.value, meta)
        } catch {
            return .failed(.storage, message: OnlineFailure.storage.message())
        }
    }
}
