import Foundation
import LodestarKit

/// Where an alignment star is and how well the fitted model explains it.
struct MountAlignmentStar: Hashable, Sendable {
    /// The apparent place of the star as the alignment recorded it.
    let place: EquatorialCoordinate
    /// Degrees between the star and where the fitted model points, or `nil` before there is a fit.
    let residualDegrees: Double?
}

/// The star alignment of a mount that Lodestar aligns itself.
struct MountAlignmentDetail: Hashable, Sendable {
    /// The stars the model is fitted to, oldest first (the order `removeAlignmentPoint` counts in).
    var stars: [MountAlignmentStar]
    /// How far off the model is expected to be away from the stars, degrees.
    var predictedErrorDegrees: Double?
    var maximumResidualDegrees: Double?
}

/// What a driver can tell besides the controller's status. Only the Sky-Watcher driver has any of it: that mount has no
/// pointing model of its own, so Lodestar keeps its alignment, its pier side and its start position.
struct MountDriverDetail: Hashable, Sendable {
    var alignment: MountAlignmentDetail?
    /// How the mount is set up: from the mount model or the person's choice.
    var arrangement: SkyWatcherMountMode?
    /// Which side of the pier the telescope is on (equatorial set-up).
    var pierSide: SkyWatcherPierSide?
    /// The axis angles when the session began: far from (0°, 0°) means the mount was not at its home position.
    var startAxis1Degrees: Double?
    var startAxis2Degrees: Double?
    /// Why tracking stopped by itself: a limit.
    var trackingStopReason: MountError?

    /// The mount was probably not at its home position when it was switched on, or was turned since: an axis stood more than
    /// this many degrees from zero at the start.
    static let homeToleranceDegrees = 10.0

    var startsAwayFromHome: Bool {
        guard let first = startAxis1Degrees, let second = startAxis2Degrees else { return false }
        return abs(first) > Self.homeToleranceDegrees || abs(second) > Self.homeToleranceDegrees
    }

    /// Reads a Sky-Watcher driver on the mount worker thread.
    init(skyWatcher driver: SkyWatcherDriver) {
        let observer = Observer(location: driver.location)
        let mode = driver.mountMode
        var stars: [MountAlignmentStar] = []
        for (index, point) in driver.alignmentPoints.enumerated() {
            guard let mode else { break }
            let sidereal = SkyFrame(date: point.timestamp, observer: observer).localApparentSiderealTime
            let place = SkyWatcherSky.apparentPlace(point.direction, localSiderealTime: sidereal,
                                                    latitude: driver.location.latitude, mode: mode)
            let residuals = driver.alignmentFit?.residualsDegrees
            stars.append(MountAlignmentStar(place: place,
                                            residualDegrees: residuals.flatMap { index < $0.count ? $0[index] : nil }))
        }
        alignment = MountAlignmentDetail(stars: stars, predictedErrorDegrees: driver.alignmentFit?.predictedErrorDegrees,
                                         maximumResidualDegrees: driver.alignmentFit?.maximumResidualDegrees)
        arrangement = mode
        pierSide = mode == .equatorial ? driver.pierSide : nil
        startAxis1Degrees = driver.startupAxisAngles?.axis1Degrees
        startAxis2Degrees = driver.startupAxisAngles?.axis2Degrees
        trackingStopReason = driver.trackingStopReason
    }
}
