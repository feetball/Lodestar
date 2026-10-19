import Foundation
import LodestarKit

/// What the star-trail plan is asked, with the camera and lens it starts from.
struct ToolsTrailInputs {
    /// What the "time for a chosen trail" is given in.
    enum ArcUnit: String, CaseIterable, Identifiable {
        case degrees, pixels

        var id: String { rawValue }

        var title: String { self == .degrees ? "Degrees" : "Pixels" }
    }

    /// The longest time the planner takes, in minutes.
    static let maximumMinutes = StarTrailPlanner.maximumDurationSeconds / 60

    var sensor: SensorFormat
    var focalLength: Double
    var aperture: Double
    var pixelPitch: Double?
    var declination = 0.0
    /// The time the trails should span, in minutes.
    var durationMinutes = 60.0
    var arcUnit = ArcUnit.degrees
    var arcDegrees = 10.0
    var arcPixels = 1000.0
    var rule = ExposureRule.npf
    /// The length of each frame of the stack in seconds; `nil` takes what the rule allows.
    var frameSeconds: Double?
    /// The time between two frames in seconds.
    var gapSeconds = StarTrailPlanner.defaultGapSeconds

    init(camera: LensSetup) {
        sensor = camera.sensor
        focalLength = camera.focalLengthMillimeters
        aperture = camera.aperture
        pixelPitch = camera.pixelPitchMicrometers
    }

    var setup: LensSetup {
        LensSetup(sensor: sensor, focalLengthMillimeters: focalLength, aperture: aperture,
                  pixelPitchMicrometers: pixelPitch)
    }

    var durationSeconds: Double { durationMinutes * 60 }
}

/// What the time-lapse plan is asked.
struct ToolsLapseInputs {
    /// What the length of the time-lapse is given by.
    enum Basis: String, CaseIterable, Identifiable {
        case clipLength, shootingTime, frames

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clipLength: return "Clip"
            case .shootingTime: return "Shooting"
            case .frames: return "Pictures"
            }
        }
    }

    /// Seconds from the start of one exposure to the start of the next.
    var interval = 15.0
    var exposure = 10.0
    var frameRate = 24.0
    var basis = Basis.clipLength
    var clipSeconds = 10.0
    var shootingMinutes = 60.0
    var frameCount = 240.0
    /// Megabytes per picture; `nil` leaves the storage unknown.
    var pictureMegabytes: Double?
    /// Seconds the camera needs to save a picture between the end of an exposure and the next start.
    var writeSeconds = TimeLapsePlanner.defaultMinimumGapSeconds

    var target: TimeLapseTarget {
        switch basis {
        case .clipLength: return .clipLength(seconds: clipSeconds)
        case .shootingTime: return .shootingTime(seconds: shootingMinutes * 60)
        case .frames: return .frameCount(frames: Int(frameCount.rounded()))
        }
    }
}

/// Where the celestial pole and the current target stand, for the star-trail plan.
struct ToolsTrailSky: Equatable {
    /// The target, where its declination is now and how the pole sits in a frame centred on it.
    struct Target: Equatable {
        var name: String
        var declination: Double
        /// Degrees from the target to the pole; `nil` while the target is below the horizon.
        var separationFromPole: Double?
        var poleInLandscape = false
        var poleInPortrait = false
        /// Whether the pole is behind the camera when it points at the target.
        var isPoleBehind = false
    }

    var hemisphere: PolarAlignment.Hemisphere
    var poleAltitude: Double
    var poleAzimuth: Double
    var target: Target?

    /// The declination of the pole, ±90°.
    var poleDeclination: Double { hemisphere == .north ? 90 : -90 }

    var isPoleAboveHorizon: Bool { poleAltitude > 0 }

    /// `nil` without an observing location.
    @MainActor
    init?(app: AppModel, frameSize: FrameSize) {
        guard let observer = app.observerContext?.observer else { return nil }
        let frame = SkyFrame(date: app.clock.now, observer: observer)
        let pole = StarTrailPlanner.pole(frame: frame)
        hemisphere = pole.hemisphere
        poleAltitude = pole.direction.altitude
        poleAzimuth = pole.direction.azimuth
        guard let object = app.target else { return }
        let declination = frame.apparentEquatorial(of: object).declination
        let pointing = frame.horizontal(of: object)
        guard pointing.altitude >= 0 else {
            target = Target(name: object.name, declination: declination)
            return
        }
        // No position means the pole is behind the camera.
        let landscape = try? StarTrailPlanner.polePosition(pole: pole.direction, pointing: pointing, frameSize: frameSize)
        let portrait = try? StarTrailPlanner.polePosition(pole: pole.direction, pointing: pointing,
                                                          frameSize: frameSize.rotated)
        target = Target(name: object.name, declination: declination,
                        separationFromPole: pointing.angularSeparation(to: pole.direction),
                        poleInLandscape: landscape?.isInFrame ?? false, poleInPortrait: portrait?.isInFrame ?? false,
                        isPoleBehind: landscape == nil)
    }
}

/// What a time-lapse error leaves the person to do: use another interval.
struct ToolsLapseFailure {
    var message: String
    var suggestedInterval: Double?
}

/// The words and numbers of the star-trail and time-lapse results.
enum ToolsPlannerText {
    /// A gap between two stacked frames shows as a break in the trail above about this many pixels.
    static let visibleGapPixels = 2.0

    /// How the sky turns, for the footer of the star trail result.
    static let rateNote = "Stars turn about the celestial pole at \(StarTrailPlanner.rotationRateDegreesPerHour)\u{00B0} "
        + "an hour, the same for every star. A star at declination \u{03B4} draws an arc of that angle \u{00D7} cos "
        + "\u{03B4} along its circle, so trails shorten towards the pole."

    /// An angle with the given number of decimals, e.g. "15.0°".
    static func degrees(_ value: Double, decimals: Int = 1) -> String {
        AngleFormatter.formatDegrees(value, decimals: decimals)
    }

    /// Pixels: whole numbers, one decimal below ten ("0.8 px", "1,240 px").
    static func pixels(_ value: Double) -> String {
        guard value.isFinite else { return AppFormat.missing }
        let digits = value < 10 ? 1 : 0
        return "\(value.formatted(.number.precision(.fractionLength(digits)))) px"
    }

    /// Seconds with up to `maximumDigits` decimals: "1 s", "2.5 s".
    static func seconds(_ value: Double, maximumDigits: Int = 1) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...maximumDigits)))) s"
    }

    /// A storage size: megabytes below a gigabyte, otherwise gigabytes ("600 MB", "9 GB").
    static func storage(megabytes: Double) -> String {
        if megabytes < 1000 {
            return "\(megabytes.formatted(.number.precision(.fractionLength(0)))) MB"
        }
        return "\((megabytes / 1000).formatted(.number.precision(.fractionLength(0...1)))) GB"
    }

    /// A count with the thousands separator of the person's region: "100,000".
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// How much the number of exposures asks of the camera's battery.
    static func battery(_ demand: BatteryDemand) -> String {
        switch demand {
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        case .veryHeavy: return "Very heavy"
        }
    }

    /// What a gap between two stacked frames does to the trail.
    static func gapVerdict(pixels value: Double) -> String {
        if value > visibleGapPixels {
            return "The stars move \(pixels(value)) between frames, so the stacked trails show breaks. Shorten the "
                + "gap if you can; stacking software can also bridge small gaps."
        }
        return "The stars move only \(pixels(value)) between frames, so the stacked trails look unbroken."
    }

    /// What went wrong with a star-trail plan, in words.
    static func message(for error: Error) -> String {
        guard let error = error as? StarTrailError else { return "The plan could not be worked out." }
        switch error {
        case .invalidDuration:
            return "The time must be longer than zero and at most 24 hours."
        case .invalidDeclination:
            return "The declination must be between \u{2212}90\u{00B0} and +90\u{00B0}."
        case .invalidArc:
            return "The trail length must be more than zero (an arc of up to 360\u{00B0})."
        case .noMotionAtThePole:
            return "A star exactly at a celestial pole does not move, so it never draws a trail. Choose a "
                + "declination away from \u{00B1}90\u{00B0}."
        case .durationTooLong(let seconds):
            return "That trail takes \(AngleFormatter.formatDuration(seconds: seconds)) at this declination, more "
                + "than 24 hours. Choose a shorter trail or a declination farther from the pole."
        case .invalidExposure:
            return "The frame length must be between 0.1 seconds and one hour."
        case .invalidGap:
            return "The gap between frames must be between 0 and 60 seconds."
        case .tooManyFrames(let frames, let limit):
            return "This stack needs \(count(frames)) frames, more than the \(count(limit)) Lodestar plans. Use a "
                + "longer frame length, a shorter total time or a longer gap."
        case .invalidFrame:
            return "The picture size is not usable."
        }
    }

    /// An explanation of a time-lapse error. For a gap that is too short it names the interval that works, which
    /// the screen offers as a one-tap fix.
    static func failure(for error: Error) -> ToolsLapseFailure {
        guard let error = error as? TimeLapseError else {
            return ToolsLapseFailure(message: "The plan could not be worked out.", suggestedInterval: nil)
        }
        switch error {
        case .gapTooShort(let gap, let minimumGap, let minimumInterval):
            let minimum = seconds(minimumInterval, maximumDigits: 2)
            let message: String
            if gap < 0 {
                message = "The exposure is longer than the interval, so the next picture would start before this "
                    + "one ends. Use an interval of at least \(minimum), or shorten the exposure."
            } else {
                message = "Only \(seconds(gap, maximumDigits: 2)) is left between the end of one exposure and the "
                    + "start of the next (interval minus exposure). The camera needs "
                    + "\(seconds(minimumGap, maximumDigits: 2)) to save each picture, or it skips frames. Use an "
                    + "interval of at least \(minimum), or shorten the exposure."
            }
            return ToolsLapseFailure(message: message, suggestedInterval: minimumInterval)
        case .invalidInterval:
            return ToolsLapseFailure(message: "The interval must be longer than zero and at most one hour.",
                                     suggestedInterval: nil)
        case .invalidExposure:
            return ToolsLapseFailure(message: "The exposure must be longer than zero and at most one hour.",
                                     suggestedInterval: nil)
        case .invalidFrameRate:
            return ToolsLapseFailure(
                message: "The playback frame rate must be more than zero and at most 240 frames per second.",
                suggestedInterval: nil)
        case .invalidTarget:
            return ToolsLapseFailure(message: "That gives less than one picture. Make the clip or the shooting time "
                                     + "longer.", suggestedInterval: nil)
        case .invalidMinimumGap:
            return ToolsLapseFailure(message: "The time the camera needs to save a picture must be between 0 and 60 "
                                     + "seconds.", suggestedInterval: nil)
        case .invalidFrameSize:
            return ToolsLapseFailure(message: "The size of a picture must be more than zero and at most 10,000 MB.",
                                     suggestedInterval: nil)
        case .tooManyFrames(let frames, let limit):
            return ToolsLapseFailure(
                message: "This time-lapse needs \(count(frames)) pictures, more than the \(count(limit)) Lodestar "
                    + "plans. Make the clip or the shooting time shorter, or the interval longer.",
                suggestedInterval: nil)
        }
    }
}
