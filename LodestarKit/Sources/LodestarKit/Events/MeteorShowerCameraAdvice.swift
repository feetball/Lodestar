import Foundation

/// Where to point a camera at a meteor shower.
public struct MeteorAimAdvice: Sendable, Hashable {
    /// Azimuth of the view in degrees from north through east, [0, 360).
    public let azimuth: Double
    /// Geometric altitude of the view in degrees, above `MeteorCameraAdvice.minimumAltitude`.
    public let altitude: Double
    /// Great-circle distance from the radiant in degrees (the ring radius, 40°).
    public let separationFromRadiant: Double
    /// The place of the view as a J2000 position at the instant the advice is for, so the app can make a custom
    /// target of it; it stays fixed among the stars while the horizontal place moves with the sky.
    public let aimPoint: EquatorialCoordinate
    /// A sentence about the Moon in that direction; `nil` when the Moon was not considered.
    public let moonNote: String?
    /// One sentence on why this direction.
    public let reason: String

    public init(azimuth: Double, altitude: Double, separationFromRadiant: Double, aimPoint: EquatorialCoordinate,
                moonNote: String?, reason: String) {
        self.azimuth = azimuth
        self.altitude = altitude
        self.separationFromRadiant = separationFromRadiant
        self.aimPoint = aimPoint
        self.moonNote = moonNote
        self.reason = reason
    }
}

/// The Moon as the direction chooser sees it: where it stands in the horizon frame and how much of it is lit.
struct MeteorCameraMoon: Sendable, Hashable {
    let direction: HorizontalCoordinate
    let illuminatedFraction: Double
}

/// The direction the chooser picked on the ring around the radiant.
struct MeteorCameraChoice: Sendable, Hashable {
    /// The picked view, in the horizon frame.
    let direction: HorizontalCoordinate
    /// Where it lies on the ring, in degrees from the vertical circle through the radiant towards the zenith,
    /// turning right-handed about the radiant.
    let positionAngle: Double
    /// Distance from the radiant in degrees.
    let separationFromRadiant: Double
    /// Distance from the Moon in degrees; `nil` when there is no Moon above the horizon.
    let moonSeparation: Double?
    /// `true` when the Moon penalty made the chooser take another direction than the altitude preference alone
    /// would have.
    let isSteeredByMoon: Bool
}

/// Advice for photographing a meteor shower with a fixed camera: which part of the sky to frame, how many meteors to
/// expect in the frame, and when the radiant is highest in the dark.
///
/// **Direction.** Meteors seem to fly away from the radiant; they are shortest near it, where they come almost
/// straight at the observer, and longest well away from it, so a camera is best pointed 30° to 60° from the radiant
/// rather than at it. `bestAim` samples the ring 40° from the radiant every 10° of position angle and scores each
/// direction above `minimumAltitude` by its height (best at `preferredAltitude`, falling linearly to nothing at 25°
/// and 85°: clear of the horizon haze, but not so high that the camera is awkward to frame) minus a Moon penalty. The
/// Moon penalty is the Moon's illuminated fraction times how far the direction lies inside `moonInfluenceRadius` of the
/// Moon (`1 − separation / 40°`, so 0 at 40° and a full Moon in the frame costs a whole point of score); it applies
/// only when the Moon is above the horizon. Directions whose scores differ by less than 1e-9 count as equal and the one
/// with the smaller position angle wins, which keeps the choice the same in both languages when the sky is symmetric.
///
/// **Count.** The rate an eye sees under a perfect sky is `observedHourlyRate`: the zenithal hourly rate scaled by
/// sin(radiant altitude), the IMO definition `ZHR = HR · r^(6.5 − lm) / sin h` read backwards (IMO, Rendtel and Arlt
/// (eds.), *Handbook for Meteor Observers*; the correction for a partly obstructed sky is 1 here). `expectedInFrame`
/// takes the part of that rate which falls in the camera frame, the frame's solid angle over the 2π sr of sky above
/// the horizon, and divides by the population index raised to `6.5 − cameraLimitingMagnitude`, because every
/// magnitude the sensor cannot reach hides `r` times as many meteors. It is a planning estimate: it takes a fast, wide
/// lens to record meteors to about +2 for a bright Perseid-class shower, assumes the whole frame lies above the
/// horizon and ignores exposure, sky glow and trailing loss.
///
/// Every call is cheap: `bestAim` is one sky frame, the Moon and 36 directions (about 0.1 ms), `bestTimeTonight` one
/// sky frame per ten minutes of darkness (about 45 µs each, 2 ms for a seven-hour dark). Nothing here uses the network or
/// shares state, so any thread may call it.
public enum MeteorCameraAdvice {
    /// The distance of the sampled directions from the radiant, in degrees.
    public static let ringRadius = 40.0
    /// The step between the sampled directions along the ring, in degrees of position angle.
    public static let ringStep = 10.0
    /// Directions at or below this altitude, in degrees, are not offered.
    public static let minimumAltitude = 25.0
    /// The altitude, in degrees, the preference for height peaks at.
    public static let preferredAltitude = 55.0
    /// The altitude, in degrees, above which a direction scores nothing for height.
    public static let maximumAltitude = 85.0
    /// `bestAim` returns `nil` when the radiant is lower than this altitude, in degrees.
    public static let lowestRadiantAltitude = -10.0
    /// The Moon penalty applies to directions closer than this to the Moon, in degrees.
    public static let moonInfluenceRadius = 40.0
    /// The limiting magnitude of the naked eye under a perfect sky, the one the ZHR is defined for.
    public static let eyeLimitingMagnitude = 6.5
    /// The limiting magnitude assumed for the camera: a fast wide lens records meteors to about +2 for a bright shower.
    public static let cameraLimitingMagnitude = 2.0
    /// The time between the instants `bestTimeTonight` looks at, in seconds (10 minutes).
    public static let timeStep = 600.0
    /// `bestTimeTonight` looks at no more than this many steps of one dark interval.
    public static let maximumTimeSteps = 1_000

    private static let moonNoteThreshold = 0.25
    private static let scoreTolerance = 1e-9
    private static let hemisphereSolidAngle = 2 * Double.pi

    /// The best direction to point a camera at `shower` at `date`, or `nil` when the radiant is below
    /// `lowestRadiantAltitude` or no direction on the ring is above `minimumAltitude`.
    ///
    /// - Parameter moonConsidered: Subtract the Moon penalty and write a `MeteorAimAdvice.moonNote`; `false` ignores
    ///   the Moon.
    public static func bestAim(shower: MeteorShower, observer: Observer, at date: Date,
                               moonConsidered: Bool = true) -> MeteorAimAdvice? {
        let frame = SkyFrame(date: date, observer: observer)
        let radiant = frame.horizontal(j2000: shower.radiant(at: date), properMotion: nil, refraction: false)
        let moon: MeteorCameraMoon? = moonConsidered
            ? MeteorCameraMoon(direction: frame.horizontal(of: .moon, refraction: false),
                               illuminatedFraction: frame.state(of: .moon).illuminatedFraction ?? 0)
            : nil
        guard let choice = choose(radiant: radiant, moon: moon) else { return nil }
        let reason = "Meteors trail longest about \(Int(ringRadius))\u{00B0} from the radiant. "
            + (choice.isSteeredByMoon
                ? "This view is high in the sky and turned away from the Moon."
                : "This view is high enough to clear the horizon haze.")
        return MeteorAimAdvice(
            azimuth: choice.direction.azimuth,
            altitude: choice.direction.altitude,
            separationFromRadiant: choice.separationFromRadiant,
            aimPoint: frame.j2000(fromHorizontal: choice.direction, refracted: false),
            moonNote: moon.map { moonNote($0, choice: choice) },
            reason: reason)
    }

    /// The direction on the ring around `radiant` (a geometric horizontal place) with the best score, or `nil` when
    /// the radiant is lower than `lowestRadiantAltitude` (or not a number) or no direction is above `minimumAltitude`.
    /// `moon` is `nil` when the Moon is not considered; a Moon at or below the horizon is ignored.
    static func choose(radiant: HorizontalCoordinate, moon: MeteorCameraMoon?) -> MeteorCameraChoice? {
        guard radiant.altitude >= lowestRadiantAltitude else { return nil }
        let center = radiant.unitVector
        let zenith = Vector3(0, 0, 1)
        var towardZenith = zenith - center * zenith.dot(center)
        if towardZenith.length < 1e-9 {
            // The radiant is at the zenith or the nadir: every direction up is the same, so use north.
            let north = Vector3(0, 1, 0)
            towardZenith = north - center * north.dot(center)
        }
        let up = towardZenith.normalized
        let right = center.cross(up)
        let visibleMoon = moon.flatMap { $0.direction.altitude > 0 && $0.illuminatedFraction.isFinite ? $0 : nil }
        let moonVector = visibleMoon?.direction.unitVector
        let lit = visibleMoon.map { AstroMath.clamp($0.illuminatedFraction, 0, 1) } ?? 0
        let cosRadius = AstroMath.cosDeg(ringRadius)
        let sinRadius = AstroMath.sinDeg(ringRadius)

        var best: Candidate?
        var bestByAltitude: Candidate?
        for step in 0..<Int(360.0 / ringStep) {
            let angle = Double(step) * ringStep
            let offset = up * AstroMath.cosDeg(angle) + right * AstroMath.sinDeg(angle)
            let vector = center * cosRadius + offset * sinRadius
            let direction = HorizontalCoordinate(vector: vector)
            guard direction.altitude > minimumAltitude else { continue }
            let preference = altitudePreference(direction.altitude)
            let moonSeparation = moonVector.map { vector.angle(to: $0) }
            let penalty = moonSeparation.map {
                lit * AstroMath.clamp((moonInfluenceRadius - $0) / moonInfluenceRadius, 0, 1)
            } ?? 0
            let candidate = Candidate(direction: direction, positionAngle: angle, preference: preference,
                                      score: preference - penalty, moonSeparation: moonSeparation)
            if let current = best {
                if candidate.score > current.score + scoreTolerance { best = candidate }
            } else {
                best = candidate
            }
            if let current = bestByAltitude {
                if candidate.preference > current.preference + scoreTolerance { bestByAltitude = candidate }
            } else {
                bestByAltitude = candidate
            }
        }
        guard let picked = best else { return nil }
        return MeteorCameraChoice(
            direction: picked.direction,
            positionAngle: picked.positionAngle,
            separationFromRadiant: picked.direction.unitVector.angle(to: center),
            moonSeparation: picked.moonSeparation,
            isSteeredByMoon: bestByAltitude?.positionAngle != picked.positionAngle)
    }

    /// The preference for a direction's height, [0, 1]: 1 at `preferredAltitude`, 0 at 25° and 85° and beyond.
    static func altitudePreference(_ altitude: Double) -> Double {
        let spread = altitude < preferredAltitude ? preferredAltitude - minimumAltitude : maximumAltitude - preferredAltitude
        return AstroMath.clamp(1 - abs(altitude - preferredAltitude) / spread, 0, 1)
    }

    static func moonNote(_ moon: MeteorCameraMoon, choice: MeteorCameraChoice) -> String {
        guard moon.direction.altitude > 0, let separation = choice.moonSeparation else {
            return "The Moon is below the horizon."
        }
        let lit = moon.illuminatedFraction.isFinite ? AstroMath.clamp(moon.illuminatedFraction, 0, 1) : 0
        let altitudeText = Int(moon.direction.altitude.rounded())
        let separationText = Int(separation.rounded())
        let percent = Int((lit * 100).rounded())
        let note = "The Moon is \(altitudeText)\u{00B0} up, \(separationText)\u{00B0} from this view, \(percent)% lit."
        if separation < moonInfluenceRadius, lit >= moonNoteThreshold {
            return "\(note) It is close enough to wash out the fainter meteors."
        }
        return note
    }

    /// The hourly rate an observer under a perfect sky (limiting magnitude `limitingMagnitude`, 6.5 by default) sees:
    /// `ZHR · sin(altitude) · r^(lm − 6.5)`. 0 when the radiant is not above the horizon or a value is not a usable
    /// number.
    ///
    /// - Parameter radiantAltitude: The radiant's geometric altitude in degrees.
    public static func observedHourlyRate(shower: MeteorShower, radiantAltitude: Double,
                                          limitingMagnitude: Double = MeteorCameraAdvice.eyeLimitingMagnitude) -> Double {
        let index = shower.populationIndex
        guard radiantAltitude > 0, radiantAltitude.isFinite, limitingMagnitude.isFinite else { return 0 }
        guard index.isFinite, index > 0, shower.zhr >= 0 else { return 0 }
        let height = AstroMath.sinDeg(AstroMath.clamp(radiantAltitude, 0, 90))
        return Double(shower.zhr) * height * pow(index, limitingMagnitude - eyeLimitingMagnitude)
    }

    /// The solid angle of the camera frame of `setup` in steradians: the rectangular pyramid of the frame's width and
    /// height angles, `4 · asin(sin(w/2) · sin(h/2))`.
    public static func frameSolidAngle(of setup: LensSetup) -> Double {
        frameSolidAngle(frame: setup.fieldOfView)
    }

    static func frameSolidAngle(frame: FrameSize) -> Double {
        let width = frame.horizontal
        let height = frame.vertical
        guard width.isFinite, height.isFinite, width > 0, height > 0, width < 180, height < 180 else { return 0 }
        return 4 * asin(AstroMath.sinDeg(width / 2) * AstroMath.sinDeg(height / 2))
    }

    /// The meteors an hour expected in the frame of `setup`: `observedHourlyRate` (what the eye sees, e.g. from
    /// `observedHourlyRate(shower:radiantAltitude:limitingMagnitude:)`) times the frame's share of the sky above the
    /// horizon, `solid angle / 2π`, times the camera's handicap `r^−(6.5 − cameraLimitingMagnitude)`.
    ///
    /// For the Perseids (ZHR 100, r 2.2) with the radiant 60° up and a 24 mm full-frame lens (frame 73.7° × 53.1°,
    /// 1.0866 sr) that is `100 · sin 60° · 0.1729 · 2.2^−4.5 = 0.431` meteors an hour. 0 when the rate is not a usable
    /// number or the radiant's population index is not positive.
    public static func expectedInFrame(observedHourlyRate: Double, shower: MeteorShower, setup: LensSetup) -> Double {
        let index = shower.populationIndex
        guard observedHourlyRate.isFinite, observedHourlyRate > 0 else { return 0 }
        guard index.isFinite, index > 0 else { return 0 }
        let share = AstroMath.clamp(frameSolidAngle(of: setup) / hemisphereSolidAngle, 0, 1)
        return observedHourlyRate * share * pow(index, cameraLimitingMagnitude - eyeLimitingMagnitude)
    }

    /// The mean number of minutes between two meteors in the frame, 60 divided by `expectedInFrame`; `nil` when none
    /// is expected.
    public static func meanMinutesPerMeteor(observedHourlyRate: Double, shower: MeteorShower,
                                            setup: LensSetup) -> Double? {
        let expected = expectedInFrame(observedHourlyRate: observedHourlyRate, shower: shower, setup: setup)
        return expected > 0 ? 60 / expected : nil
    }

    /// The instant of astronomical darkness in `summary` with the radiant of `shower` highest, looking at the dark
    /// intervals every `timeStep` and at their ends; the earliest when several are equally high. `nil` when the night
    /// has no astronomical darkness. The Moon is not considered: the Moon penalty is part of `bestAim`.
    ///
    /// Cost: one sky frame per ten minutes of darkness, about 45 µs each.
    public static func bestTimeTonight(shower: MeteorShower, summary: NightSummary) -> Date? {
        var best: Date?
        var bestAltitude = -Double.infinity
        for interval in summary.astronomicalDarknessIntervals {
            let duration = interval.duration
            guard duration.isFinite else { continue }
            let steps = Int(min((duration / timeStep).rounded(.up), Double(maximumTimeSteps)))
            for step in 0...steps {
                let offset = Double(step) * timeStep < duration ? Double(step) * timeStep : duration
                let time = interval.start.addingTimeInterval(offset)
                let altitude = SkyFrame(date: time, observer: summary.observer)
                    .horizontal(j2000: shower.radiant(at: time), properMotion: nil, refraction: false).altitude
                if altitude > bestAltitude {
                    bestAltitude = altitude
                    best = time
                }
            }
        }
        return best
    }

    private struct Candidate {
        let direction: HorizontalCoordinate
        let positionAngle: Double
        let preference: Double
        let score: Double
        let moonSeparation: Double?
    }
}
