import Foundation
import LodestarKit

/// The satellites of one CelesTrak group, built once per download and kept in memory (about 1.2 KB each: 11,000 Starlink
/// satellites are 12 MB).
final class SatelliteGroup: Sendable {
    let group: ElementSetGroup
    let satellites: [Satellite]
    /// The element set with the newest epoch, which decides whether the group is fresh.
    let newest: OrbitalElements?
    /// How many records of the download were unusable (a few are normal).
    let skippedCount: Int

    init(group: ElementSetGroup, satellites: [Satellite], newest: OrbitalElements?, skippedCount: Int) {
        self.group = group
        self.satellites = satellites
        self.newest = newest
        self.skippedCount = skippedCount
    }

    /// Whether the newest element set is within the group's freshness limit at `date`.
    func isFresh(at date: Date) -> Bool {
        guard let newest else { return false }
        return group.isFresh(newest, at: date)
    }

    /// Element sets whose epoch is later than this after the present are dropped (a clock or data error).
    private static let futureTolerance: TimeInterval = 86_400

    /// Reads a CelesTrak OMM JSON download. Throws `OnlineDataError` for anything that is not a usable list: not JSON, no
    /// valid element set, or more unusable records than usable ones (the format has probably changed). Heavy for the
    /// Starlink group (0.2 to 0.5 s): call it off the main actor.
    static func parse(group: ElementSetGroup, data: Data, now: Date) throws -> OnlineParsed<SatelliteGroup> {
        let batch: ElementSetBatch
        do {
            batch = try ElementSetParser.parseJson(data).latestPerObject()
        } catch {
            throw OnlineDataError("Not a CelesTrak element list: \(error.localizedDescription)")
        }
        let limit = now.addingTimeInterval(futureTolerance)
        let elements = batch.elements.filter { $0.epoch <= limit }
        guard let newest = elements.max(by: { $0.epoch < $1.epoch }) else {
            throw OnlineDataError("No usable element sets.")
        }
        guard batch.skippedCount <= elements.count else { throw OnlineDataError("Too many unusable records.") }
        let built = SatelliteGroup(group: group, satellites: elements.map { Satellite(elements: $0) }, newest: newest,
                                   skippedCount: batch.skippedCount)
        return OnlineParsed(value: built, dataEpoch: newest.epoch)
    }
}

/// A satellite of the pass lists together with the group whose freshness limit applies to it (the stations' for the ISS
/// and Tiangong, else the group it came from).
struct PassSatellite: Sendable {
    let satellite: Satellite
    let group: ElementSetGroup

    /// Whether this satellite's own element set is within its group's freshness limit at `date`.
    func isFresh(at date: Date) -> Bool { group.isFresh(satellite.elements, at: date) }
}

/// Everything downloaded about satellites, as an immutable snapshot (a new one for every change, so a pass list can tell
/// that its inputs changed).
struct SatelliteLibrary: Sendable {
    /// NORAD number of the International Space Station.
    static let issCatalogNumber = 25544
    /// NORAD number of the Tiangong core module (Tianhe).
    static let tiangongCatalogNumber = 48274
    private static let brightStations: Set<Int> = [issCatalogNumber, tiangongCatalogNumber]

    static let empty = SatelliteLibrary(stations: nil, visual: nil, starlink: nil, generation: 0)

    let stations: SatelliteGroup?
    let visual: SatelliteGroup?
    let starlink: SatelliteGroup?
    /// Counts every change.
    let generation: Int
    /// The ISS, Tiangong and the visual group, each satellite once (the newer element set wins), ISS first.
    let passSatellites: [PassSatellite]

    private init(stations: SatelliteGroup?, visual: SatelliteGroup?, starlink: SatelliteGroup?, generation: Int) {
        self.stations = stations
        self.visual = visual
        self.starlink = starlink
        self.generation = generation
        passSatellites = Self.makePassSatellites(stations: stations, visual: visual)
    }

    /// Whether the ISS and the bright satellites have data.
    var hasPassData: Bool { !passSatellites.isEmpty }

    /// Whether any group needed for the passes is past its freshness limit at `date`.
    func isPassDataStale(at date: Date) -> Bool {
        [stations, visual].contains { group in group.map { !$0.isFresh(at: date) } ?? false }
    }

    /// This library with `group` added or replaced.
    func with(_ group: SatelliteGroup) -> SatelliteLibrary {
        switch group.group {
        case .stations: return SatelliteLibrary(stations: group, visual: visual, starlink: starlink, generation: generation + 1)
        case .visual: return SatelliteLibrary(stations: stations, visual: group, starlink: starlink, generation: generation + 1)
        case .starlink: return SatelliteLibrary(stations: stations, visual: visual, starlink: group, generation: generation + 1)
        }
    }

    /// This library without the groups of `feed`.
    func without(_ feed: OnlineFeed) -> SatelliteLibrary {
        switch feed {
        case .satellites: return SatelliteLibrary(stations: nil, visual: nil, starlink: starlink, generation: generation + 1)
        case .starlink: return SatelliteLibrary(stations: stations, visual: visual, starlink: nil, generation: generation + 1)
        case .comets, .clouds: return self
        }
    }

    private static func makePassSatellites(stations: SatelliteGroup?, visual: SatelliteGroup?) -> [PassSatellite] {
        var order: [Int] = []
        var byNumber: [Int: PassSatellite] = [:]
        func add(_ group: SatelliteGroup?, only: Set<Int>?) {
            guard let group else { return }
            for satellite in group.satellites {
                let number = satellite.catalogNumber
                if let only, !only.contains(number) { continue }
                // The ISS and Tiangong are in both groups: judge their data by the stricter station limit, whichever
                // download happens to be the newer.
                let limitGroup: ElementSetGroup = brightStations.contains(number) ? .stations : group.group
                if let known = byNumber[number] {
                    if satellite.elements.epoch > known.satellite.elements.epoch {
                        byNumber[number] = PassSatellite(satellite: satellite, group: limitGroup)
                    }
                } else {
                    byNumber[number] = PassSatellite(satellite: satellite, group: limitGroup)
                    order.append(number)
                }
            }
        }
        // The station group lists every module of the ISS: only the bright, independent ones are wanted.
        add(stations, only: brightStations)
        add(visual, only: nil)
        let all = order.compactMap { byNumber[$0] }
        return all.filter { $0.satellite.catalogNumber == issCatalogNumber }
            + all.filter { $0.satellite.catalogNumber != issCatalogNumber }
    }
}
