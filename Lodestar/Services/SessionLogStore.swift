import Foundation
import LodestarKit

/// The session log: what was shot (or tried) on which night. It lives in one JSON file in Application Support, on this
/// device only, and holds at most `maximumEntries` entries.
///
/// Changes are written after a short pause, off the main actor; `saveNow()` writes at once (the app calls it when it goes
/// to the background).
@MainActor
@Observable
final class SessionLogStore {
    /// The most entries kept.
    static let maximumEntries = SessionLogCodec.maximumEntries

    /// Every entry, newest first.
    private(set) var entries: [SessionLogEntry] {
        didSet { imagedTargetIDs = Set(entries.lazy.filter(\.isImaged).map(\.targetID)) }
    }

    /// The identifiers of the objects that have an entry marked as imaged.
    private(set) var imagedTargetIDs: Set<String> = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    /// Reads the file, if there is one; a file that cannot be read gives an empty log.
    init(fileURL: URL? = SessionLogFile.defaultURL()) {
        self.fileURL = fileURL
        let loaded = fileURL.map { SessionLogFile.read(from: $0, limit: Self.maximumEntries) } ?? []
        entries = loaded
        imagedTargetIDs = Set(loaded.lazy.filter(\.isImaged).map(\.targetID))
    }

    /// Whether another entry fits.
    var hasRoom: Bool { entries.count < Self.maximumEntries }

    /// The entries of one object, newest first.
    func entries(forTarget targetID: String) -> [SessionLogEntry] {
        entries.filter { $0.targetID == targetID }
    }

    /// Adds an entry.
    ///
    /// - Returns: `false` when the log is full.
    @discardableResult
    func add(_ entry: SessionLogEntry) -> Bool {
        guard hasRoom else { return false }
        entries.append(entry)
        entries.sort { $0.date > $1.date }
        scheduleSave()
        return true
    }

    /// Replaces the entry that has the same identifier.
    func update(_ entry: SessionLogEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        entries.sort { $0.date > $1.date }
        scheduleSave()
    }

    /// Removes the entries with these identifiers.
    func delete(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    /// Writes the log now.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else { return }
        let snapshot = entries
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            SessionLogFile.write(snapshot, to: fileURL)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.saveNow()
        }
    }
}

/// The file format of the session log: `{"version": 1, "entries": [...]}`. Every value is optional on reading and is
/// cleaned by `SessionLogEntry`, and an entry that cannot be read does not spoil the others.
enum SessionLogFile {
    private static let largestFileBytes = 64_000_000

    private struct Stored: Codable {
        var id: String?
        var time: Double?
        var targetID: String?
        var targetName: String?
        var rightAscension: Double?
        var declination: Double?
        var siteName: String?
        var siteLatitude: Double?
        var siteLongitude: Double?
        var siteUTCOffsetMinutes: Int?
        var camera: String?
        var focalLength: Double?
        var lensAperture: Double?
        var sensorPixelsX: Int?
        var sensorPixelsY: Int?
        var exposureSeconds: Double?
        var iso: Int?
        var frameCount: Int?
        var filter: String?
        var notes: String?
        var isImaged: Bool?

        init(_ entry: SessionLogEntry) {
            id = entry.id
            time = entry.date.timeIntervalSince1970
            targetID = entry.targetID
            targetName = entry.targetName
            rightAscension = entry.rightAscension
            declination = entry.declination
            siteName = entry.siteName
            siteLatitude = entry.siteLatitude
            siteLongitude = entry.siteLongitude
            siteUTCOffsetMinutes = entry.siteUTCOffsetMinutes
            camera = entry.camera
            focalLength = entry.focalLength
            lensAperture = entry.lensAperture
            sensorPixelsX = entry.sensorPixelsX
            sensorPixelsY = entry.sensorPixelsY
            exposureSeconds = entry.exposureSeconds
            iso = entry.iso
            frameCount = entry.frameCount
            filter = entry.filter
            notes = entry.notes
            isImaged = entry.isImaged
        }

        /// The entry, or nil when it has no usable date or target.
        func entry() -> SessionLogEntry? {
            guard let time, time.isFinite, abs(time) < 4e11, let targetID, !targetID.isEmpty else { return nil }
            return SessionLogEntry(
                id: id ?? "", date: Date(timeIntervalSince1970: time), targetID: targetID, targetName: targetName ?? "",
                rightAscension: rightAscension, declination: declination, siteName: siteName ?? "",
                siteLatitude: siteLatitude, siteLongitude: siteLongitude, siteUTCOffsetMinutes: siteUTCOffsetMinutes,
                camera: camera ?? "", focalLength: focalLength, lensAperture: lensAperture,
                sensorPixelsX: sensorPixelsX, sensorPixelsY: sensorPixelsY, exposureSeconds: exposureSeconds ?? 0,
                iso: iso ?? 0, frameCount: frameCount ?? 0, filter: filter ?? "", notes: notes ?? "",
                isImaged: isImaged ?? false)
        }
    }

    private struct Lossy: Decodable {
        let value: Stored?

        init(from decoder: Decoder) throws {
            value = try? Stored(from: decoder)
        }
    }

    private struct Document: Codable {
        var version: Int
        var entries: [Stored]
    }

    private struct LossyDocument: Decodable {
        var entries: [Lossy]
    }

    /// `Application Support/SessionLog.json`.
    static func defaultURL() -> URL? {
        guard let directory = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                           appropriateFor: nil, create: true) else { return nil }
        return directory.appendingPathComponent("SessionLog.json")
    }

    /// The entries of the file, newest first, at most `limit`, without repeated identifiers.
    static func read(from url: URL, limit: Int) -> [SessionLogEntry] {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0, size <= largestFileBytes, let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(LossyDocument.self, from: data) else { return [] }
        var seen = Set<String>()
        var result: [SessionLogEntry] = []
        for stored in document.entries {
            guard let entry = stored.value?.entry(), seen.insert(entry.id).inserted else { continue }
            result.append(entry)
            if result.count >= limit { break }
        }
        return result.sorted { $0.date > $1.date }
    }

    /// Writes the entries atomically; a failure leaves the old file in place.
    static func write(_ entries: [SessionLogEntry], to url: URL) {
        let document = Document(version: 1, entries: entries.map(Stored.init))
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
