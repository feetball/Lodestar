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

    var sensor: SensorFormat
    var focalLength: Double
    var aperture: Double
    var pixelPitch: Double?
    var declination = 0.0
    /// The shooting time in minutes.
    var durationMinutes = 120.0
    var arcUnit = ArcUnit.degrees
    var arcDegrees = 15.0
    var arcPixels = 1000.0
    var rule = ExposureRule.npf
    /// The single exposure of the stack in seconds; `nil` takes what the rule allows.
    var exposure: Double?
    /// The time between two exposures in seconds.
    var gap = StarTrailPlanner.defaultGapSeconds

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
    /// What the number of frames follows from.
    enum Goal: String, CaseIterable, Identifiable {
        case clipLength, shootingTime, frameCount

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clipLength: return "Clip length"
            case .shootingTime: return "Shooting time"
            case .frameCount: return "Frames"
            }
        }
    }

    /// Seconds from the start of one exposure to the start of the next.
    var interval = 10.0
    var exposure = 8.0
    var frameRate = 24.0
    var goal = Goal.clipLength
    var clipSeconds = 10.0
    var shootingMinutes = 60.0
    var frames = 300.0
    /// Megabytes per picture; `nil` leaves the storage unknown.
    var pictureMegabytes: Double?
    /// Seconds the camera needs between the end of an exposure and the next start.
    var writeSeconds = TimeLapsePlanner.defaultMinimumGapSeconds

    var target: TimeLapseTarget {
        switch goal {
        case .clipLength: return .clipLength(seconds: clipSeconds)
        case .shootingTime: return .shootingTime(seconds: shootingMinutes * 60)
        case .frameCount: return .frameCount(frames: Int(frames.rounded()))
        }
    }
}

/// Where the celestial pole and the current target stand, for the star-trail plan.
struct ToolsTrailSky: Equatable {
    /// The target and where its declination is now, when the app has one.
    struct Target: Equatable {
        var name: String
        var declination: Double
        /// Degrees from the target to the pole.
        var separationFromPole: Double
        /// Whether the pole falls inside the lens frame (landscape) when the camera is centred on the target.
        var poleInFrame: Bool
    }

    var hemisphere: PolarAlignment.Hemisphere
    var poleAltitude: Double
    var poleAzimuth: Double
    var target: Target?

    /// The declination of the pole, ±90°.
    var poleDeclination: Double { hemisphere == .north ? 90 : -90 }

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
        let pointing = frame.horizontal(of: object)
        // No position means the pole is behind the camera.
        let poleInFrame = (try? StarTrailPlanner.polePosition(pole: pole.direction, pointing: pointing,
                                                              frameSize: frameSize))?.isInFrame ?? false
        target = Target(name: object.name, declination: frame.apparentEquatorial(of: object).declination,
                        separationFromPole: pointing.angularSeparation(to: pole.direction), poleInFrame: poleInFrame)
    }
}

/// The words and numbers of the star-trail and time-lapse results.
enum ToolsPlannerText {
    /// "15.04°" for small angles, "120°" for large ones.
    static func degrees(_ value: Double) -> String {
        AngleFormatter.formatDegrees(value, decimals: abs(value) < 10 ? 2 : 1)
    }

    /// "1,234 px", or "2.4 px" below ten.
    static func pixels(_ value: Double) -> String {
        guard value.isFinite else { return AppFormat.missing }
        let digits = value < 10 ? 1 : 0
        return "\(value.formatted(.number.precision(.fractionLength(digits)))) px"
    }

    /// "9.0 GB" or "850 MB".
    static func storage(megabytes: Double) -> String {
        if megabytes >= 1000 {
            return "\((megabytes / 1000).formatted(.number.precision(.fractionLength(1)))) GB"
        }
        return "\(megabytes.formatted(.number.precision(.fractionLength(0)))) MB"
    }

    /// A count with a thousands separator.
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// Seconds with at most one decimal, e.g. "9 s" or "2.5 s".
    static func seconds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) s"
    }

    /// What went wrong with a star-trail plan, in words.
    static func message(for error: Error) -> String {
        guard let error = error as? StarTrailError else { return "The plan could not be worked out." }
        switch error {
        case .invalidDuration:
            return "Enter a time between a minute and 24 hours."
        case .invalidDeclination:
            return "The declination must be between \u{2212}90\u{00B0} and +90\u{00B0}."
        case .invalidArc:
            return "Enter a trail length greater than zero (at most 360\u{00B0})."
        case .noMotionAtThePole:
            return "A star exactly at the celestial pole does not move, so it draws no trail. Choose a declination "
                + "away from \u{00B1}90\u{00B0}."
        case .durationTooLong:
            return "That trail would take more than 24 hours to draw."
        case .invalidExposure:
            return "Enter an exposure between a fraction of a second and an hour."
        case .invalidGap:
            return "Enter a gap between 0 and \(Int(StarTrailPlanner.maximumGapSeconds)) seconds."
        case .tooManyFrames(_, let limit):
            return "That takes more than \(count(limit)) frames. Use a longer exposure or a shorter time."
        case .invalidFrame:
            return "The field of view of this lens is out of range."
        }
    }

    /// What went wrong with a time-lapse plan, in words. A gap that is too short is explained by the caller.
    static func message(forLapse error: Error) -> String {
        guard let error = error as? TimeLapseError else { return "The plan could not be worked out." }
        switch error {
        case .invalidInterval:
            return "Enter an interval between a fraction of a second and an hour."
        case .invalidExposure:
            return "Enter an exposure between a fraction of a second and an hour."
        case .invalidFrameRate:
            return "Enter a playback rate between 1 and \(Int(TimeLapsePlanner.maximumFrameRate)) frames per second."
        case .invalidTarget:
            return "That gives less than one frame. Enter a longer clip or shooting time, or more frames."
        case .invalidMinimumGap:
            return "Enter a write time between 0 and \(Int(TimeLapsePlanner.maximumMinimumGapSeconds)) seconds."
        case .invalidFrameSize:
            return "Enter a picture size between 0 and \(count(Int(TimeLapsePlanner.maximumFrameSizeMegabytes))) MB."
        case .gapTooShort(let gap, let minimum, _):
            return "The gap between exposures is \(seconds(max(gap, 0))), but the camera needs at least "
                + "\(seconds(minimum)) to write each picture and be ready for the next one. Frames would be skipped."
        case .tooManyFrames(_, let limit):
            return "That takes more than \(count(limit)) frames. Use a shorter clip or a longer interval."
        }
    }
}
