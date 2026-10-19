import Foundation

/// What is known about a cached download besides its bytes.
struct OnlineCacheMeta: Codable, Equatable, Sendable {
    /// When the data was last confirmed current: downloaded, or answered with "not modified".
    var savedAt: Date
    /// The server's `ETag`, for the next conditional request.
    var etag: String?
    /// The server's `Last-Modified` header text, for `If-Modified-Since`.
    var lastModified: String?
    /// When the server says the data expires (MET Norway), if it does.
    var expires: Date?
    /// The newest orbit epoch in the data (satellites), if it has one.
    var dataEpoch: Date?
    /// Tells the copies of one resource apart: the rounded coordinates of a forecast.
    var key: String?
}

/// A cached download: its bytes and `meta`.
struct OnlineCacheEntry: Sendable {
    let bytes: Data
    let meta: OnlineCacheMeta
}

/// The downloads kept on the phone, one file per resource in `directory` (Application Support/Online, excluded from
/// backups). A file holds a small header with the metadata, then the length and the raw bytes, and is replaced
/// atomically: written to a temporary file and renamed over the old one, so a reader sees the old data or the new, never
/// half of either. The length lets a reader notice a file that was cut short.
struct OnlineCache: Sendable {
    let directory: URL

    /// The magic number of the file format, "LOD1".
    private static let magic: [UInt8] = [0x4C, 0x4F, 0x44, 0x31]
    private static let maximumHeader = 4096

    /// Application Support/Online.
    static func standard() -> OnlineCache {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return OnlineCache(directory: base.appendingPathComponent("Online", isDirectory: true))
    }

    /// The entry named `name`, or `nil` when there is none or the file is damaged.
    func read(_ name: String) -> OnlineCacheEntry? {
        guard let url = fileURL(name), let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        guard let (meta, bodyStart) = Self.header(of: data), data.count >= bodyStart + 4 else { return nil }
        let size = data[(bodyStart)..<(bodyStart + 4)].reduce(0) { ($0 << 8) | Int($1) }
        guard data.count == bodyStart + 4 + size else { return nil }
        return OnlineCacheEntry(bytes: data.subdata(in: (bodyStart + 4)..<data.count), meta: meta)
    }

    /// The metadata of `name` without reading its bytes, or `nil`.
    func readMeta(_ name: String) -> OnlineCacheMeta? {
        guard let url = fileURL(name), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8), prefix.count == 8 else { return nil }
        guard let length = Self.headerLength(in: prefix),
              let header = try? handle.read(upToCount: length), header.count == length else { return nil }
        return try? JSONDecoder().decode(OnlineCacheMeta.self, from: header)
    }

    /// Stores `bytes` and `meta` as `name`, replacing what was there. Throws when the disk refuses.
    func write(_ name: String, bytes: Data, meta: OnlineCacheMeta) throws {
        guard var url = fileURL(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        try prepareDirectory()
        let header = try JSONEncoder().encode(meta)
        var file = Data(Self.magic)
        var length = UInt32(header.count).bigEndian
        withUnsafeBytes(of: &length) { file.append(contentsOf: $0) }
        file.append(header)
        guard bytes.count <= Int(UInt32.max) else { throw CocoaError(.fileWriteOutOfSpace) }
        var size = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &size) { file.append(contentsOf: $0) }
        file.append(bytes)
        try file.write(to: url, options: [.atomic])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Replaces the metadata of `name` and keeps its bytes. Returns `false` when there is nothing cached.
    func updateMeta(_ name: String, meta: OnlineCacheMeta) throws -> Bool {
        guard let entry = read(name) else { return false }
        try write(name, bytes: entry.bytes, meta: meta)
        return true
    }

    /// Removes `name`.
    func delete(_ name: String) {
        guard let url = fileURL(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Private

    private func fileURL(_ name: String) -> URL? {
        guard !name.isEmpty, name.count <= 41,
              name.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }) else { return nil }
        return directory.appendingPathComponent("\(name).cache", isDirectory: false)
    }

    /// Creates the directory and keeps it out of backups: the data can be downloaded again.
    private func prepareDirectory() throws {
        var url = directory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// The length of the header when `prefix` (the first 8 bytes) starts a file of this format.
    private static func headerLength(in prefix: Data) -> Int? {
        let bytes = [UInt8](prefix)
        guard bytes.count >= 8, Array(bytes[0..<4]) == magic else { return nil }
        let length = bytes[4..<8].reduce(0) { ($0 << 8) | Int($1) }
        return (2...maximumHeader).contains(length) ? length : nil
    }

    /// The metadata of a whole file and where its bytes start.
    private static func header(of data: Data) -> (OnlineCacheMeta, Int)? {
        guard data.count >= 8, let length = headerLength(in: data.prefix(8)), data.count >= 8 + length else { return nil }
        let start = data.startIndex + 8
        guard let meta = try? JSONDecoder().decode(OnlineCacheMeta.self, from: data[start..<(start + length)]) else {
            return nil
        }
        return (meta, 8 + length)
    }
}

/// Small persistent values of the online data: which feeds are on, and when each resource was last requested. They live
/// in `UserDefaults`, which is thread safe.
final class OnlineStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func enabledKey(_ feed: OnlineFeed) -> String { "lodestar.online.enabled.\(feed.rawValue)" }
    private static func attemptKey(_ resource: OnlineResource) -> String { "lodestar.online.attempt.\(resource.key)" }
    private static func failedKey(_ resource: OnlineResource) -> String { "lodestar.online.attemptFailed.\(resource.key)" }
    private static let explainedKey = "lodestar.online.explained"

    func isEnabled(_ feed: OnlineFeed) -> Bool { defaults.bool(forKey: Self.enabledKey(feed)) }

    func setEnabled(_ feed: OnlineFeed, _ enabled: Bool) { defaults.set(enabled, forKey: Self.enabledKey(feed)) }

    /// Whether the user has read the first-time explanation.
    var hasExplained: Bool {
        get { defaults.bool(forKey: Self.explainedKey) }
        set { defaults.set(newValue, forKey: Self.explainedKey) }
    }

    /// When `resource` was last requested, successful or not. It survives turning the feed off, so toggling cannot bypass
    /// the request interval.
    func lastAttempt(_ resource: OnlineResource) -> Date? {
        guard let seconds = defaults.object(forKey: Self.attemptKey(resource)) as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func setLastAttempt(_ resource: OnlineResource, _ date: Date?) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: Self.attemptKey(resource))
        } else {
            defaults.removeObject(forKey: Self.attemptKey(resource))
        }
    }

    /// Whether that request failed.
    func lastAttemptFailed(_ resource: OnlineResource) -> Bool { defaults.bool(forKey: Self.failedKey(resource)) }

    func setLastAttemptFailed(_ resource: OnlineResource, _ failed: Bool) {
        defaults.set(failed, forKey: Self.failedKey(resource))
    }
}
