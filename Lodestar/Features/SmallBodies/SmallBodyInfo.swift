import Foundation
import LodestarKit

/// Something worth warning about when a comet or an asteroid is listed or aimed at.
enum SmallBodyWarning: Sendable, Hashable {
    /// Closer than 25° to the Sun: twilight and glare hide it.
    case twilightGlow
    /// The orbital elements are old, so the position is only good to a fraction of a degree or worse.
    case positionApproximate
    /// The orbit file has no magnitude parameters for it.
    case noBrightnessData
}

/// What the app shows about a comet or an asteroid at one instant: distances, elongation, phase, the magnitude
/// estimate, and the warnings. Computed from `SmallBodyState`; pure, so it can be made on any thread.
struct SmallBodyInfo: Sendable, Equatable {
    /// Below this angle from the Sun a body is "in the twilight glow".
    static let twilightElongation = 25.0
    /// Comet elements older than this many days make the position approximate.
    static let cometElementsAgeDays = 60.0
    /// Asteroid elements (the bundled ones) older than this many days make the position approximate.
    static let asteroidElementsAgeDays = 365.0

    let body: SmallBody
    /// Distance from the Earth in AU.
    let earthDistanceAU: Double
    /// Distance from the Sun in AU.
    let sunDistanceAU: Double
    /// Angle from the Sun in degrees.
    let elongation: Double
    /// Sun–body–Earth angle in degrees.
    let phaseAngle: Double
    /// The total magnitude of a comet or V of an asteroid, an estimate (comet totals are good to a magnitude or two).
    let magnitude: Double?
    /// Bright enough (magnitude 10) and far enough from the Sun (25°) for a camera.
    let isPhotographable: Bool
    /// Days between the date of the orbital elements and the instant of this info (always positive).
    let elementsAgeDays: Double

    var isInTwilightGlow: Bool { elongation < Self.twilightElongation }

    var hasApproximatePosition: Bool { elementsAgeDays > Self.maximumElementsAgeDays(of: body.kind) }

    var hasNoBrightnessData: Bool { magnitude == nil }

    /// The warnings that apply, most important first.
    var warnings: [SmallBodyWarning] {
        var result: [SmallBodyWarning] = []
        if isInTwilightGlow { result.append(.twilightGlow) }
        if hasApproximatePosition { result.append(.positionApproximate) }
        if hasNoBrightnessData { result.append(.noBrightnessData) }
        return result
    }

    static func maximumElementsAgeDays(of kind: SmallBodyKind) -> Double {
        kind == .comet ? cometElementsAgeDays : asteroidElementsAgeDays
    }

    /// The info of `body` at `frame`'s instant; `nil` when its orbit cannot be evaluated then.
    static func compute(_ body: SmallBody, frame: SkyFrame) -> SmallBodyInfo? {
        frame.state(of: body).map(of)
    }

    /// The info of `body` at `date`; the observer does not matter, the numbers are geocentric.
    static func compute(_ body: SmallBody, at date: Date) -> SmallBodyInfo? {
        SmallBodyEphemeris.state(of: body, at: JulianDate(date: date)).map(of)
    }

    /// The info for a state already computed.
    static func of(_ state: SmallBodyState) -> SmallBodyInfo {
        SmallBodyInfo(body: state.body, earthDistanceAU: state.distanceAU, sunDistanceAU: state.heliocentricDistanceAU,
                      elongation: state.elongation, phaseAngle: state.phaseAngle, magnitude: state.apparentMagnitude,
                      isPhotographable: state.isPhotographable(),
                      elementsAgeDays: abs(state.julianDate.tt - state.body.orbit.epochJulianDayTT))
    }
}

/// Where a comet's ion tail points, seen from the observer, and how to turn the camera so that the tail lies along a
/// side of the frame.
struct SmallBodyTail: Sendable, Equatable {
    /// Phase angles closer than this to 0° or 180° foreshorten the tail by more than a factor of four.
    static let foreshortenedPhase = 15.0

    /// Degrees in (−180, 180]: 0 = the tail points straight up, positive = towards the observer's right.
    let angleFromVertical: Double
    /// Sun–body–Earth angle: a tail seen almost end-on is short and ill-defined.
    let phaseAngle: Double

    /// The smallest camera roll in degrees, in [−45, 45], that puts the tail along a side of the frame (up, down, left
    /// or right all count): positive turns the camera clockwise as seen from behind it.
    var cameraTilt: Double {
        angleFromVertical - 90 * SmallBodyText.roundedHalfUp(angleFromVertical / 90)
    }

    /// `true` when the comet is seen so nearly end-on that its tail is foreshortened to a stub.
    var isForeshortened: Bool {
        phaseAngle < Self.foreshortenedPhase || phaseAngle > 180 - Self.foreshortenedPhase
    }

    static func compute(_ state: SmallBodyState, frame: SkyFrame) -> SmallBodyTail? {
        guard state.body.kind == .comet,
              let angle = SmallBodyEphemeris.tailAngleFromVertical(of: state, in: frame) else { return nil }
        return SmallBodyTail(angleFromVertical: angle, phaseAngle: state.phaseAngle)
    }
}

/// Everything the detail screen shows about a comet or an asteroid: the `info`, and for a comet the `tail`.
struct SmallBodyDetail: Sendable, Equatable {
    let info: SmallBodyInfo
    let tail: SmallBodyTail?

    /// The detail of `body` at `frame`'s instant; `nil` when its orbit cannot be evaluated then.
    static func compute(_ body: SmallBody, frame: SkyFrame) -> SmallBodyDetail? {
        guard let state = frame.state(of: body) else { return nil }
        return SmallBodyDetail(info: SmallBodyInfo.of(state), tail: SmallBodyTail.compute(state, frame: frame))
    }
}
