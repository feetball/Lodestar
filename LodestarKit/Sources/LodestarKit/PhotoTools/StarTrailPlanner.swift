import Foundation

/// Why a star trail could not be planned.
public enum StarTrailError: Error, Hashable, Sendable {
    /// The duration is not a finite number of seconds in (0, `StarTrailPlanner.maximumDurationSeconds`].
    case invalidDuration(seconds: Double)
    /// The declination is not a finite number in [−90, 90] degrees.
    case invalidDeclination(degrees: Double)
    /// The arc is not a finite length in (0, 360] degrees, or the pixel length is not a finite positive number.
    case invalidArc(value: Double)
    /// A star at a celestial pole does not move, so no duration produces a trail.
    case noMotionAtThePole
    /// The trail needs more than `StarTrailPlanner.maximumDurationSeconds` seconds.
    case durationTooLong(seconds: Double)
    /// The single exposure is not a finite number of seconds in (0, 3600].
    case invalidExposure(seconds: Double)
    /// The gap between exposures is not a finite number of seconds in [0, `StarTrailPlanner.maximumGapSeconds`].
    case invalidGap(seconds: Double)
    /// The plan would need `count` frames, more than the `limit` the planner handles.
    case tooManyFrames(count: Int, limit: Int)
    /// The camera frame is not a pair of angles in (0, 180) degrees.
    case invalidFrame(horizontal: Double, vertical: Double)
}

/// The trail a star draws while the shutter is open (or over a stack of exposures).
public struct StarTrail: Hashable, Sendable {
    /// The time in seconds.
    public let duration: Double
    /// The star's declination in degrees.
    public let declination: Double
    /// The angle the star turns about the celestial pole: the sidereal rate times the time, the same for every
    /// star. This is the angle of the arc on the concentric circles around the pole.
    public let rotationDegrees: Double
    /// The length of the trail on the sky in degrees, `rotation × cos(declination)`.
    public let arcLengthDegrees: Double
    /// The length in image pixels, using the image scale at the centre of the frame (a pixel pitch of 4 µm when
    /// the setup has none, see `usedDefaultPixelPitch`). Trails near the edges of a wide rectilinear frame are
    /// longer in pixels than this.
    public let arcLengthPixels: Double
    /// The angular distance of the star from the celestial pole, `90° − |declination|`: the radius of its circle
    /// on the sky.
    public let radiusFromPoleDegrees: Double
    /// `true` when the setup has no pixel pitch and `arcLengthPixels` assumes 4 µm.
    public let usedDefaultPixelPitch: Bool
}

/// A plan for a star trail made by stacking many short exposures.
public struct StarTrailStackPlan: Hashable, Sendable {
    /// The time the trail should span in seconds, as requested.
    public let totalDuration: Double
    /// The longest single exposure the rule allows, with its notes.
    public let estimate: ExposureEstimate
    /// The exposure planned for each frame: the estimate rounded down to a value that is easy to dial in (whole
    /// seconds from 2 s, tenths of a second below), or the caller's own exposure.
    public let exposureSeconds: Double
    /// The time between the end of one exposure and the start of the next.
    public let gapSeconds: Double
    /// The number of frames: enough to span `totalDuration`.
    public let frameCount: Int
    /// The time the frames span, `frameCount × (exposure + gap)`, in seconds.
    public let actualDuration: Double
    /// The time the shutter is open in total, `frameCount × exposure`.
    public let lightSeconds: Double
    /// The length of the trail in a single frame, in pixels.
    public let exposureTrailPixels: Double
    /// The distance a star moves in the gap between two frames, in pixels: the break in the stacked trail. Below
    /// about 2 pixels it is hardly visible.
    public let gapPixels: Double
    /// The trail of the whole stack over `actualDuration` (at most 24 hours): its rotation and length.
    public let trail: StarTrail
}

/// Where a celestial pole is: the centre of the star-trail circles.
public struct StarTrailPole: Hashable, Sendable {
    /// The pole's hemisphere.
    public let hemisphere: PolarAlignment.Hemisphere
    /// The azimuth and altitude of the pole, 0° azimuth (north) for the north pole and 180° for the south pole.
    /// Its altitude is about the observer's latitude (negative if the pole is below the horizon).
    public let direction: HorizontalCoordinate

    /// `true` when the pole is above the horizon, so full circles around it can be photographed.
    public var isAboveHorizon: Bool { direction.altitude > 0 }
}

/// Where the pole falls in the camera frame.
public struct StarTrailPolePosition: Hashable, Sendable {
    /// Horizontal position in units of half the frame width: −1 at the left edge, +1 at the right edge.
    public let x: Double
    /// Vertical position in units of half the frame height: −1 at the bottom edge, +1 at the top edge.
    public let y: Double
    /// The angle between the optical axis and the pole in degrees.
    public let separation: Double
    /// `true` when the pole is inside the frame, `|x| ≤ 1` and `|y| ≤ 1`.
    public let isInFrame: Bool
}

/// Plans star trails: how long they get, how many frames a stack takes, and where the circles around the pole
/// fall in the frame.
///
/// Stars move at the sidereal rate of 15.041° per hour about the celestial pole, so a star at declination δ draws
/// an arc of `15.041° × hours × cos δ` along its circle. All functions are pure and take microseconds.
public enum StarTrailPlanner {
    /// The rate at which the sky turns about the celestial poles, in degrees per hour.
    public static let rotationRateDegreesPerHour = ExposureCalculator.siderealRateArcsecondsPerSecond

    /// The longest duration the planner accepts: 24 hours.
    public static let maximumDurationSeconds = 86_400.0

    /// The longest single exposure the planner accepts for a stack: an hour.
    public static let maximumExposureSeconds = 3_600.0

    /// The gap between stacked exposures when the caller gives none: one second, a typical write time.
    public static let defaultGapSeconds = 1.0

    /// The longest gap the planner accepts.
    public static let maximumGapSeconds = 60.0

    /// The most frames a stack plan may have.
    public static let maximumFrameCount = 100_000

    private static let degreesPerSecond = rotationRateDegreesPerHour / 3600.0

    /// The trail of a star at `declination` during `duration`.
    ///
    /// - Parameters:
    ///   - duration: The time in seconds, in (0, `maximumDurationSeconds`].
    ///   - declination: The star's declination in degrees, [−90, 90].
    ///   - setup: The camera and lens, for the length in pixels.
    /// - Throws: `StarTrailError.invalidDuration` for a duration out of range, `StarTrailError.invalidDeclination`
    ///   for a declination out of range.
    public static func trail(duration: Double, declination: Double, setup: LensSetup) throws -> StarTrail {
        guard duration > 0, duration <= maximumDurationSeconds else { throw StarTrailError.invalidDuration(seconds: duration) }
        guard declination >= -90, declination <= 90 else { throw StarTrailError.invalidDeclination(degrees: declination) }
        let rotation = degreesPerSecond * duration
        return StarTrail(
            duration: duration, declination: declination, rotationDegrees: rotation,
            arcLengthDegrees: rotation * AstroMath.cosDeg(declination),
            arcLengthPixels: ExposureCalculator.trailLengthPixels(exposureSeconds: duration, declination: declination, setup: setup),
            radiusFromPoleDegrees: 90 - abs(declination),
            usedDefaultPixelPitch: setup.pixelPitchMicrometers == nil)
    }

    /// The time a star at `declination` needs to draw an arc of `arc` degrees on the sky.
    ///
    /// - Parameters:
    ///   - arc: The length of the trail in degrees, in (0, 360].
    ///   - declination: The star's declination in degrees, [−90, 90].
    /// - Returns: The duration in seconds.
    /// - Throws: `StarTrailError.invalidArc` for an arc out of range, `StarTrailError.invalidDeclination` for a
    ///   declination out of range, `StarTrailError.noMotionAtThePole` at a declination of ±90°,
    ///   `StarTrailError.durationTooLong` if the arc takes more than 24 hours.
    public static func duration(forArcDegrees arc: Double, declination: Double) throws -> Double {
        guard arc > 0, arc <= 360 else { throw StarTrailError.invalidArc(value: arc) }
        return try seconds(arc: arc, declination: declination)
    }

    /// The time a star at `declination` needs to draw a trail `pixels` long in the image.
    ///
    /// - Parameters:
    ///   - pixels: The length of the trail in pixels, finite and positive.
    ///   - declination: The star's declination in degrees, [−90, 90].
    ///   - setup: The camera and lens; a missing pixel pitch counts as 4 µm.
    /// - Returns: The duration in seconds.
    /// - Throws: `StarTrailError.invalidArc` for a length that is not a positive number,
    ///   `StarTrailError.invalidDeclination` for a declination out of range, `StarTrailError.noMotionAtThePole`
    ///   at a declination of ±90°, `StarTrailError.durationTooLong` if the trail takes more than 24 hours.
    public static func duration(forArcPixels pixels: Double, declination: Double, setup: LensSetup) throws -> Double {
        guard pixels > 0, pixels.isFinite else { throw StarTrailError.invalidArc(value: pixels) }
        let pitch = setup.pixelPitchMicrometers ?? ExposureCalculator.defaultPixelPitchMicrometers
        let arcDegrees = pixels * setup.imageScale(forPixelPitch: pitch) / AstroMath.arcsecondsPerDegree
        return try seconds(arc: arcDegrees, declination: declination)
    }

    private static func seconds(arc: Double, declination: Double) throws -> Double {
        guard declination >= -90, declination <= 90 else { throw StarTrailError.invalidDeclination(degrees: declination) }
        let factor = AstroMath.cosDeg(declination)
        guard factor > 1e-9 else { throw StarTrailError.noMotionAtThePole }
        let result = arc / (degreesPerSecond * factor)
        guard result <= maximumDurationSeconds else { throw StarTrailError.durationTooLong(seconds: result) }
        return result
    }

    /// Plans a stack of short exposures that together draw a trail of `totalDuration`.
    ///
    /// Each frame is exposed as long as `rule` allows without trailing (see `ExposureCalculator.maxExposure`),
    /// rounded down, unless `exposureSeconds` says otherwise; frames follow each other after `gapSeconds`.
    ///
    /// - Parameters:
    ///   - totalDuration: The time the trail should span in seconds, in (0, `maximumDurationSeconds`].
    ///   - declination: The declination of the target in degrees, or nil to assume the celestial equator.
    ///   - setup: The camera and lens.
    ///   - rule: The exposure rule that sets the single exposure.
    ///   - exposureSeconds: The exposure to use instead of the rule's, in (0, `maximumExposureSeconds`].
    ///   - gapSeconds: The time between exposures in seconds, [0, `maximumGapSeconds`].
    /// - Throws: `StarTrailError` for a value out of range, or if more than `maximumFrameCount` frames are needed.
    public static func stackingPlan(totalDuration: Double, declination: Double?, setup: LensSetup,
                                    rule: ExposureRule = .npf, exposureSeconds: Double? = nil,
                                    gapSeconds: Double = StarTrailPlanner.defaultGapSeconds) throws -> StarTrailStackPlan {
        guard totalDuration > 0, totalDuration <= maximumDurationSeconds else {
            throw StarTrailError.invalidDuration(seconds: totalDuration)
        }
        if let declination, !(declination >= -90 && declination <= 90) {
            throw StarTrailError.invalidDeclination(degrees: declination)
        }
        if let exposureSeconds, !(exposureSeconds > 0 && exposureSeconds <= maximumExposureSeconds) {
            throw StarTrailError.invalidExposure(seconds: exposureSeconds)
        }
        guard gapSeconds >= 0, gapSeconds <= maximumGapSeconds else { throw StarTrailError.invalidGap(seconds: gapSeconds) }

        let estimate = ExposureCalculator.maxExposure(rule: rule, setup: setup, declination: declination)
        let exposure = exposureSeconds ?? practicalExposure(estimate.seconds)
        let period = exposure + gapSeconds
        let frames = max(1, ceil(totalDuration / period - 1e-9))
        if frames > Double(maximumFrameCount) {
            throw StarTrailError.tooManyFrames(count: frames >= 1e9 ? 1_000_000_000 : Int(frames), limit: maximumFrameCount)
        }
        let actual = frames * period
        let trailDeclination = declination ?? 0
        return StarTrailStackPlan(
            totalDuration: totalDuration, estimate: estimate, exposureSeconds: exposure, gapSeconds: gapSeconds,
            frameCount: Int(frames), actualDuration: actual, lightSeconds: frames * exposure,
            exposureTrailPixels: ExposureCalculator.trailLengthPixels(exposureSeconds: exposure, declination: trailDeclination, setup: setup),
            gapPixels: ExposureCalculator.trailLengthPixels(exposureSeconds: gapSeconds, declination: trailDeclination, setup: setup),
            trail: try trail(duration: min(actual, maximumDurationSeconds), declination: trailDeclination, setup: setup))
    }

    /// An exposure rounded down to a value that is easy to set: whole seconds from 2 s up, tenths of a second
    /// from 0.1 s, and unchanged below that.
    static func practicalExposure(_ seconds: Double) -> Double {
        if seconds >= 2 { return floor(seconds) }
        if seconds >= 0.1 { return floor(seconds * 10) / 10 }
        return seconds
    }

    /// Where the celestial pole stands: the centre of the star-trail circles.
    ///
    /// - Parameters:
    ///   - frame: The instant and observer.
    ///   - hemisphere: The pole to find; nil takes the observer's hemisphere (north on or above the equator).
    ///   - refraction: Whether to raise the altitude by atmospheric refraction.
    public static func pole(frame: SkyFrame, hemisphere: PolarAlignment.Hemisphere? = nil,
                            refraction: Bool = true) -> StarTrailPole {
        let chosen = hemisphere ?? PolarAlignment.Hemisphere(latitude: frame.observer.location.latitude)
        return StarTrailPole(hemisphere: chosen,
                             direction: frame.horizontalOfCelestialPole(north: chosen == .north, refraction: refraction))
    }

    /// Where a pole falls in the camera frame, for drawing the circles around it.
    ///
    /// The picture is a rectilinear view. With `roll` 0 its top points towards the zenith.
    ///
    /// - Parameters:
    ///   - pole: The direction of the pole, see `pole(frame:hemisphere:refraction:)`.
    ///   - pointing: The direction the optical axis points.
    ///   - frameSize: The angular size of the frame as held: `horizontal` runs along the picture's x axis.
    ///   - roll: The turn of the camera about its axis in degrees, positive clockwise as seen through the camera,
    ///     as in the mosaic guidance.
    /// - Returns: The position, or nil if the pole is behind the camera (90° or more from the axis).
    /// - Throws: `StarTrailError.invalidFrame` if the frame is not a pair of angles in (0, 180) degrees.
    public static func polePosition(pole: HorizontalCoordinate, pointing: HorizontalCoordinate, frameSize: FrameSize,
                                    roll: Double = 0) throws -> StarTrailPolePosition? {
        guard frameSize.horizontal > 0, frameSize.horizontal < 180, frameSize.vertical > 0, frameSize.vertical < 180 else {
            throw StarTrailError.invalidFrame(horizontal: frameSize.horizontal, vertical: frameSize.vertical)
        }
        let axis = pointing.unitVector
        let toPole = pole.unitVector
        let depth = toPole.dot(axis)
        guard depth > 1e-9 else { return nil }
        let zenith = Vector3(0, 0, 1)
        let level = zenith - axis * axis.z
        let levelUp = level.length > 1e-9 ? level.normalized : Vector3(0, 1, 0)
        let levelRight = axis.cross(levelUp)
        let turn = roll.isFinite ? roll : 0
        let up = (levelUp * AstroMath.cosDeg(turn) + levelRight * AstroMath.sinDeg(turn)).normalized
        let right = axis.cross(up)
        let x = toPole.dot(right) / depth / AstroMath.tanDeg(frameSize.horizontal / 2)
        let y = toPole.dot(up) / depth / AstroMath.tanDeg(frameSize.vertical / 2)
        return StarTrailPolePosition(x: x, y: y, separation: axis.angle(to: toPole), isInFrame: abs(x) <= 1 && abs(y) <= 1)
    }
}
