import Foundation
import LodestarKit

/// Where the meteor-shower camera card stands: working, or what the night allows.
enum EventsMeteorCameraState: Sendable, Equatable {
    /// The advice is being worked out.
    case loading
    /// The Sun does not get 18\u{00B0} below the horizon that night.
    case noDarkness
    /// The radiant stays too far below the horizon the whole dark.
    case radiantBelowHorizon
    /// The advice.
    case ready(EventsMeteorCameraPlan)
}

/// The camera advice for one night of a shower.
struct EventsMeteorCameraPlan: Sendable, Equatable {
    /// The moment it is for: the instant of the night's darkness with the radiant highest.
    let time: Date
    /// Where to point the camera at `time`.
    let advice: MeteorAimAdvice
    /// The radiant's geometric altitude at `time`, in degrees.
    let radiantAltitude: Double
}

/// The numbers and words of the "Camera" card of a meteor shower. Pure, so the astronomy runs off the main actor.
enum EventsMeteorCamera {
    /// The one tip under the advice.
    static let tip = "Use your widest lens, the NPF exposure, continuous shooting; keep the radiant in or near the frame edge."

    /// The note under the numbers: the count is an estimate for a particular kind of camera.
    static let estimateNote = "A planning estimate for a fast, wide lens, which records meteors to about magnitude 2. "
        + "Fireballs and a longer exposure add more."

    /// The advice for the night of `event`: the night that holds its best time (or the peak), the moment of that
    /// night's darkness with the radiant highest, the best direction then. Works out a night of twilight and a few
    /// dozen sky frames: run it off the main actor.
    static func state(event: AstronomicalEvent, shower: MeteorShower, context: ObserverContext) -> EventsMeteorCameraState {
        let reference = event.visibility?.bestTime ?? event.date
        let zone = context.timeZone
        let summary = NightPlanner.summary(nightStartingOn: nightStart(containing: reference, in: zone),
                                           observer: context.observer, timeZone: zone)
        guard let time = MeteorCameraAdvice.bestTimeTonight(shower: shower, summary: summary) else {
            return .noDarkness
        }
        guard let advice = MeteorCameraAdvice.bestAim(shower: shower, observer: context.observer, at: time) else {
            return .radiantBelowHorizon
        }
        let radiant = SkyFrame(date: time, observer: context.observer)
            .horizontal(j2000: shower.radiant(at: time), properMotion: nil, refraction: false)
        return .ready(EventsMeteorCameraPlan(time: time, advice: advice, radiantAltitude: radiant.altitude))
    }

    /// An instant on the local date the night holding `instant` starts on: that night runs from local noon to local
    /// noon, so before noon it is the previous date's. The result is local noon of that date.
    static func nightStart(containing instant: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: instant) else { return instant }
        if instant >= noon { return noon }
        return calendar.date(byAdding: .day, value: -1, to: noon) ?? noon.addingTimeInterval(-86_400)
    }

    /// The meteors an hour expected in the frame of `lens` at the plan's time.
    static func expectedPerHour(_ plan: EventsMeteorCameraPlan, shower: MeteorShower, lens: LensSetup) -> Double {
        let observed = MeteorCameraAdvice.observedHourlyRate(shower: shower, radiantAltitude: plan.radiantAltitude)
        return MeteorCameraAdvice.expectedInFrame(observedHourlyRate: observed, shower: shower, setup: lens)
    }

    /// The custom target "Perseids camera field" at the advised place, to aim the camera at.
    static func target(shower: MeteorShower, advice: MeteorAimAdvice) -> CelestialObject {
        CelestialObject.custom(name: "\(shower.name) camera field", j2000: advice.aimPoint)
    }

    /// "Point the camera at azimuth 210\u{00B0} (SSW), altitude 55\u{00B0}, 40\u{00B0} from the radiant."
    static func aimText(_ advice: MeteorAimAdvice) -> String {
        let point = AngleFormatter.compassPoint(azimuth: advice.azimuth).abbreviation
        return "Point the camera at azimuth \(degrees(advice.azimuth)) (\(point)), altitude \(degrees(advice.altitude)), "
            + "\(degrees(advice.separationFromRadiant)) from the radiant."
    }

    /// What to expect in the frame, `lensText` naming the camera: "Expect about one meteor every 1.6 hours in your
    /// frame at 24 mm f/2.8 \u{00B7} Full Frame." The count is `perHour` meteors an hour; with the radiant at or below the
    /// horizon (`radiantAltitude`) none are expected.
    static func countText(perHour: Double, radiantAltitude: Double, lensText: String) -> String {
        guard radiantAltitude > 0, perHour > 0 else {
            return "The radiant is below the horizon then, so expect no meteors in your frame."
        }
        let place = "in your frame at \(lensText)."
        let minutes = 60 / perHour
        if perHour >= 6 {
            return "Expect about \(Int(perHour.rounded())) meteors an hour \(place)"
        }
        if perHour >= 2 {
            return "Expect a few meteors an hour \(place)"
        }
        if minutes <= 90 {
            return "Expect about one meteor every \(max(5, Int((minutes / 5).rounded()) * 5)) minutes \(place)"
        }
        if minutes > 600 {
            return "Expect fewer than one meteor in 10 hours \(place)"
        }
        let hours = (minutes / 6).rounded() / 10
        return "Expect about one meteor every \(oneDecimal(hours)) hours \(place)"
    }

    /// "24 mm f/2.8 \u{00B7} Full Frame".
    static func lensText(_ lens: LensSetup) -> String {
        "\(oneDecimal(lens.focalLengthMillimeters)) mm f/\(oneDecimal(lens.aperture)) \u{00B7} \(lens.sensor.name)"
    }

    private static func degrees(_ value: Double) -> String {
        AngleFormatter.formatDegrees(value, decimals: 0)
    }

    /// A number with at most one decimal, such as "24" or "2.8".
    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
