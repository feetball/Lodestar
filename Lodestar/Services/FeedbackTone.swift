import Foundation

/// How the distance to the target sounds: the closer, the faster and higher the ticks.
///
/// Angular separations span two orders of magnitude between "far" and "on target", so the tick interval and the
/// pitch both change geometrically with the separation; every halving of the distance then sounds like the same
/// step.
struct FeedbackTone: Equatable, Sendable {
    /// Separation in degrees at and beyond which the tone is slowest and lowest.
    static let farSeparation = 60.0
    /// Separation in degrees at and below which the tone is fastest and highest.
    static let nearSeparation = 0.5
    /// Seconds between ticks when far from the target.
    static let slowestInterval = 1.2
    /// Seconds between ticks when on target.
    static let fastestInterval = 0.08
    static let lowestFrequency = 440.0
    static let highestFrequency = 1320.0
    /// The number of distinct pitches between the lowest and highest frequency (about 40 cents apart).
    static let pitchCount = 48

    /// Seconds until the next tick.
    let interval: Double
    /// Which pre-rendered pitch to play: 0 is the lowest (far), `pitchCount - 1` the highest (on target).
    let pitchIndex: Int

    /// The tone for an angular separation in degrees; invalid input sounds like "far".
    init(separation: Double) {
        let clamped = separation.isFinite
            ? min(max(separation, Self.nearSeparation), Self.farSeparation)
            : Self.farSeparation
        // 0 on target … 1 far away.
        let distance = log(clamped / Self.nearSeparation) / log(Self.farSeparation / Self.nearSeparation)
        interval = Self.fastestInterval * pow(Self.slowestInterval / Self.fastestInterval, distance)
        pitchIndex = Int(((1 - distance) * Double(Self.pitchCount - 1)).rounded())
    }

    /// The frequency in hertz of a pre-rendered pitch; out-of-range indices are clamped.
    static func frequency(ofPitch index: Int) -> Double {
        let fraction = Double(min(max(index, 0), pitchCount - 1)) / Double(pitchCount - 1)
        return lowestFrequency * pow(highestFrequency / lowestFrequency, fraction)
    }
}

/// Decides when the next tick is due. It sees only times in seconds from any monotonic clock, so it can be tested
/// with plain numbers.
///
/// The rhythm follows the latest separation report: whenever the schedule is asked, the tick interval for the
/// separation reported now is measured from the previous tick, so approaching the target speeds the rhythm up at
/// once instead of after the old, longer interval has run out.
struct FeedbackTickSchedule: Sendable {
    /// A separation report with the time (seconds) it was made.
    struct Report: Equatable, Sendable {
        var degrees: Double
        var time: Double
    }

    enum Action: Equatable, Sendable {
        /// Play a tick of this pitch now, then ask again after `wait` seconds.
        case tick(pitchIndex: Int, wait: Double)
        /// Nothing to play yet; ask again after `wait` seconds.
        case wait(Double)
        /// Nothing is left to play.
        case finished
    }

    /// Reports older than this many seconds mean the screen stopped aiming.
    static let reportTimeout = 0.75
    /// Longest time between two decisions in seconds, so that a change of rhythm is noticed quickly.
    static let maximumWait = 0.1

    private var lastTick: Double?

    /// What to do at time `now`, given the newest report and the time (seconds) the chime ends, if one is playing.
    mutating func next(now: Double, report: Report?, chimeEndsAt: Double?) -> Action {
        if let report, now - report.time <= Self.reportTimeout {
            let tone = FeedbackTone(separation: report.degrees)
            let due = lastTick.map { $0 + tone.interval } ?? now
            guard now >= due else { return .wait(min(due - now, Self.maximumWait)) }
            lastTick = now
            return .tick(pitchIndex: tone.pitchIndex, wait: min(tone.interval, Self.maximumWait))
        }
        if let chimeEndsAt, now < chimeEndsAt {
            return .wait(chimeEndsAt - now)
        }
        return .finished
    }

    /// Forgets the last tick; the next report starts a new run of ticks with an immediate one.
    mutating func reset() {
        lastTick = nil
    }
}

/// Renders the feedback sounds as mono samples.
enum FeedbackSynthesizer {
    static let sampleRate = 44_100.0

    private static let tickDuration = 0.025
    private static let tickAmplitude: Float = 0.8
    private static let chimeAmplitude: Float = 0.7
    private static let chimeNoteOffset = 0.11
    private static let firstNoteDuration = 0.2
    private static let secondNoteDuration = 0.35

    /// A short soft blip: a sine burst under a raised-cosine envelope, so it starts and ends without a click.
    static func tick(frequency: Double) -> [Float] {
        let count = Int(tickDuration * sampleRate)
        return (0..<count).map { index in
            let envelope = 0.5 * (1 - cos(2 * .pi * Double(index) / Double(count - 1)))
            let time = Double(index) / sampleRate
            return tickAmplitude * Float(envelope * sin(2 * .pi * frequency * time))
        }
    }

    /// The "target acquired" sound: two rising notes with a decaying tail.
    static func chime() -> [Float] {
        let first = note(frequency: 880, duration: firstNoteDuration, decay: 0.06)
        let second = note(frequency: 1320, duration: secondNoteDuration, decay: 0.09)
        let offset = Int(chimeNoteOffset * sampleRate)
        var samples = [Float](repeating: 0, count: max(first.count, offset + second.count))
        for (index, value) in first.enumerated() { samples[index] += value }
        for (index, value) in second.enumerated() { samples[offset + index] += value }
        let peak = samples.reduce(0) { max($0, abs($1)) }
        let gain = peak > 0 ? chimeAmplitude / peak : 0
        return samples.map { $0 * gain }
    }

    /// How long `chime()` sounds, in seconds.
    static var chimeDuration: Double { max(firstNoteDuration, chimeNoteOffset + secondNoteDuration) }

    /// A sine note with a 4 ms attack, exponential decay (time constant `decay`) and a 20 ms release.
    private static func note(frequency: Double, duration: Double, decay: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        let attack = Int(0.004 * sampleRate)
        let release = Int(0.02 * sampleRate)
        return (0..<count).map { index in
            let time = Double(index) / sampleRate
            var envelope = exp(-time / decay)
            if index < attack { envelope *= Double(index) / Double(attack) }
            if index >= count - release { envelope *= Double(count - index) / Double(release) }
            return Float(envelope * sin(2 * .pi * frequency * time))
        }
    }
}
