import Foundation
import LodestarKit

/// An object as the mount needs it: a J2000 place, with the proper motion of a star, and where it stands now.
struct MountResolvedTarget: Sendable {
    let object: CelestialObject
    let j2000: EquatorialCoordinate
    let properMotion: ProperMotion?
    /// Geometric (not refracted) altitude now and the lowest it reaches during the next `MountTargets.lookaheadSeconds`,
    /// which is what the engine's altitude limit looks at.
    let altitude: Double
    let lowestAltitude: Double
    let azimuth: Double
}

/// What the mount control needs to know about a target before it is sent.
enum MountTargets {
    /// The engine also checks that the target is still above the limit this long from now (the slew takes time).
    static let lookaheadSeconds = MountSettings.standard.horizonLookaheadSeconds

    /// The J2000 place of `object` at `date`; for a moving object, its place at that moment.
    static func resolve(_ object: CelestialObject, observer: Observer, date: Date) -> MountResolvedTarget {
        let frame = SkyFrame(date: date, observer: observer)
        let j2000: EquatorialCoordinate
        let properMotion: ProperMotion?
        if case .fixed(let coordinate, let motion) = object.position {
            j2000 = coordinate
            properMotion = motion
        } else {
            // Planets, the Moon, comets, asteroids and the celestial poles have no catalog place: take the place they
            // have in the sky now.
            j2000 = frame.j2000(fromHorizontal: frame.horizontal(of: object, refraction: false), refracted: false)
            properMotion = nil
        }
        let now = frame.horizontal(j2000: j2000, properMotion: properMotion, refraction: false)
        let later = SkyFrame(date: date.addingTimeInterval(lookaheadSeconds), observer: observer)
            .horizontal(j2000: j2000, properMotion: properMotion, refraction: false)
        return MountResolvedTarget(object: object, j2000: j2000, properMotion: properMotion, altitude: now.altitude,
                                   lowestAltitude: min(now.altitude, later.altitude), azimuth: now.azimuth)
    }

    /// Whether Lodestar refuses to point a mount at `object`.
    static func isSun(_ object: CelestialObject) -> Bool {
        object.category == .sun || object.id == "sun"
    }

    static let sunRefusal = "Lodestar never slews a mount to the Sun. Looking at the Sun through a telescope or "
        + "camera without a certified solar filter destroys eyesight and equipment."
}

/// How far and which way a slew takes the mount, for the confirmation.
struct MountSlewPlan {
    let target: MountResolvedTarget
    /// Where the mount points now, as altitude and azimuth; `nil` before its first reading.
    let start: HorizontalCoordinate?
    /// Degrees along the sky from where the mount points now to the target.
    let separation: Double?
    /// The turn in azimuth, degrees: positive is clockwise as seen from above.
    let azimuthTurn: Double?
    /// The change of altitude, degrees: positive is up.
    let altitudeChange: Double?

    init(target: MountResolvedTarget, mountPosition: EquatorialCoordinate?, observer: Observer, date: Date) {
        self.target = target
        guard let mountPosition else {
            start = nil
            separation = nil
            azimuthTurn = nil
            altitudeChange = nil
            return
        }
        let frame = SkyFrame(date: date, observer: observer)
        let from = frame.horizontal(j2000: mountPosition, refraction: false)
        let to = frame.horizontal(j2000: target.j2000, properMotion: target.properMotion, refraction: false)
        start = from
        separation = mountPosition.angularSeparation(to: target.j2000)
        azimuthTurn = AstroMath.normalizeSignedDegrees(to.azimuth - from.azimuth)
        altitudeChange = to.altitude - from.altitude
    }

    /// "About 87° across the sky."
    var distanceText: String {
        guard let separation else { return "From wherever it points now." }
        return "About \(AppFormat.separation(separation)) across the sky."
    }

    /// "It turns 90° clockwise seen from above and rises 15°."
    var directionText: String? {
        guard let azimuthTurn, let altitudeChange else { return nil }
        var parts: [String] = []
        if abs(azimuthTurn) >= 1 {
            parts.append("turns \(AppFormat.separation(abs(azimuthTurn))) "
                + (azimuthTurn > 0 ? "clockwise seen from above" : "counter-clockwise seen from above"))
        }
        if abs(altitudeChange) >= 1 {
            parts.append((altitudeChange > 0 ? "rises " : "drops ") + AppFormat.separation(abs(altitudeChange)))
        }
        guard !parts.isEmpty else { return "It moves only a little." }
        return "It " + parts.joined(separator: " and ") + "."
    }
}
