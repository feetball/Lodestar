import Foundation
import LodestarKit
import Observation

/// Where Aim leads guidance for a satellite, at one instant.
struct SatelliteAimFix: Sendable {
    /// The direction to point the camera at: the apparent (refracted) direction.
    let horizontal: HorizontalCoordinate
    /// The marker's name on the sky.
    let label: String
    /// The live look of a followed satellite (range, angular speed, shadow); `nil` for a fixed point.
    let look: SatelliteLook?
    /// For "wait at the peak": seconds until the satellite is there, negative once it has passed.
    let secondsToPeak: Double?

    /// The direction as an East-North-Up unit vector.
    var direction: Vector3 { horizontal.unitVector }
}

/// What Aim aims at instead of an object while a satellite is chosen: a moving target (follow) or a fixed point of the sky
/// to wait at (the peak of a pass). Immutable.
struct SatelliteAimSource: Identifiable, Sendable {
    enum Mode: Sendable {
        /// The satellite itself; `pass` is the pass it was chosen from, for the note about when it rises or is over.
        case follow(Satellite, pass: SatellitePassItem?)
        /// The point where a pass reaches its highest: the instant and the (refracted) direction.
        case peak(Date, HorizontalCoordinate)
    }

    /// Tells sources apart: guidance starts afresh when it changes, and only then.
    let id = UUID()
    let title: String
    let observer: Observer
    let mode: Mode

    /// A live, moving target: the satellite of `item`.
    static func follow(_ item: SatellitePassItem, observer: Observer) -> SatelliteAimSource {
        SatelliteAimSource(title: item.name, observer: observer, mode: .follow(item.satellite, pass: item))
    }

    /// A fixed point of the sky: where the pass of `item` reaches its highest point while the satellite can be seen.
    static func peak(_ item: SatellitePassItem, observer: Observer) -> SatelliteAimSource {
        let point = item.peak
        let look = item.satellite.look(at: point.date, observer: observer)
        return SatelliteAimSource(title: item.name, observer: observer,
                                  mode: .peak(point.date, look?.apparentHorizontal ?? point.horizontal))
    }

    var isPeak: Bool {
        if case .peak = mode { return true }
        return false
    }

    /// The pass a followed satellite was chosen from.
    var pass: SatellitePassItem? {
        if case .follow(_, let pass) = mode { return pass }
        return nil
    }

    /// The instant of the peak, for a source that waits for it.
    var peakDate: Date? {
        if case .peak(let date, _) = mode { return date }
        return nil
    }

    /// Where to point at `date`; `nil` where the orbit cannot be computed. A followed satellite builds one
    /// `SatelliteSkyContext` for the instant and looks the satellite up in it; the guidance target is that look's
    /// `apparentHorizontal`.
    func fix(at date: Date) -> SatelliteAimFix? {
        switch mode {
        case .follow(let satellite, _):
            guard let look = satellite.look(in: SatelliteSkyContext(date: date, observer: observer)) else { return nil }
            return SatelliteAimFix(horizontal: look.apparentHorizontal, label: title, look: look, secondsToPeak: nil)
        case .peak(let peak, let horizontal):
            return SatelliteAimFix(horizontal: horizontal, label: "\(title) peak", look: nil,
                                   secondsToPeak: peak.timeIntervalSince(date))
        }
    }
}

/// The satellite Aim is following or waiting for, kept with the app model so it survives tab switches. Aim reads it; the
/// pass screens set it; choosing another target ends it.
@MainActor
@Observable
final class SatelliteAimSession {
    /// The chosen satellite target, or `nil` for the ordinary target.
    private(set) var source: SatelliteAimSource?

    /// Leads Aim to `source`.
    func start(_ source: SatelliteAimSource) {
        self.source = source
    }

    /// Back to the ordinary target.
    func stop() {
        if source != nil { source = nil }
    }
}
