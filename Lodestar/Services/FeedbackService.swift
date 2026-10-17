import Foundation
import UIKit

/// Haptic and audio cues for aiming.
///
/// Haptics fire on the transitions the Aim screen reports. Audio ticks are scheduled here: the screen reports the
/// separation every frame and a task plays ticks at the rate that separation calls for, so the rhythm does not
/// stutter with the frame rate. The tick task and the audio engine stop by themselves when the reports stop.
@MainActor
final class FeedbackService {
    /// Within this separation (degrees) the haptic generators are kept ready for the target-acquired cue.
    private static let hapticReadySeparation = 5.0
    private static let hapticReadyInterval = 2.0
    /// The audio engine is kept running this long (seconds) after the chime's nominal end, so its tail is not cut.
    private static let chimeTailAllowance = 0.2

    private let acquiredGenerator = UINotificationFeedbackGenerator()
    private let lostGenerator = UIImpactFeedbackGenerator(style: .light)
    private var audioPlayer: FeedbackAudioPlayer?
    private var isAudioPlayerUnavailable = false

    private var hapticsEnabled = false
    private var audioEnabled = false
    private var lastHapticReady: Double?

    private let clockOrigin = ContinuousClock.now
    private var schedule = FeedbackTickSchedule()
    private var latestReport: FeedbackTickSchedule.Report?
    private var chimeEndsAt: Double?
    private var tickTask: Task<Void, Never>?
    /// Identifies the running tick task, so a task that was replaced cannot clear its successor's state.
    private var tickGeneration = 0

    /// Seconds since this service was created, on a monotonic clock.
    private var now: Double {
        (ContinuousClock.now - clockOrigin) / .seconds(1)
    }

    /// Turns the cue types on or off. Cheap; called whenever settings are applied.
    func configure(haptics: Bool, audio: Bool) {
        if haptics && !hapticsEnabled { prepareHaptics() }
        hapticsEnabled = haptics
        if !audio && audioEnabled { stopGuidanceAudio() }
        audioEnabled = audio
    }

    /// The camera is on target: success haptic, plus the chime when audio is on.
    func targetAcquired() {
        if hapticsEnabled {
            acquiredGenerator.notificationOccurred(.success)
            acquiredGenerator.prepare()
        }
        if audioEnabled, let output = audioOutput(), output.playChime() {
            chimeEndsAt = now + FeedbackSynthesizer.chimeDuration + Self.chimeTailAllowance
            startTickTaskIfNeeded()
        }
    }

    /// The camera left the target: a light tap.
    func targetLost() {
        if hapticsEnabled {
            lostGenerator.impactOccurred()
        }
    }

    /// Reports the current angular separation in degrees. Call every frame while aiming; with audio on, ticks
    /// play faster and higher the closer the camera gets.
    func guidanceTick(separation: Double) {
        guard separation.isFinite else { return }
        let time = now
        if hapticsEnabled, separation < Self.hapticReadySeparation {
            keepHapticsReady(at: time)
        }
        guard audioEnabled else { return }
        latestReport = FeedbackTickSchedule.Report(degrees: max(separation, 0), time: time)
        startTickTaskIfNeeded()
    }

    /// Stops the ticks and releases the audio engine and session.
    func stopGuidanceAudio() {
        tickGeneration += 1
        tickTask?.cancel()
        tickTask = nil
        latestReport = nil
        chimeEndsAt = nil
        schedule.reset()
        audioPlayer?.stop()
    }

    // MARK: Haptics

    private func prepareHaptics() {
        acquiredGenerator.prepare()
        lostGenerator.prepare()
    }

    private func keepHapticsReady(at time: Double) {
        if let last = lastHapticReady, time - last < Self.hapticReadyInterval { return }
        lastHapticReady = time
        prepareHaptics()
    }

    // MARK: Audio

    private func audioOutput() -> FeedbackAudioPlayer? {
        if let audioPlayer { return audioPlayer }
        guard !isAudioPlayerUnavailable else { return nil }
        audioPlayer = FeedbackAudioPlayer()
        isAudioPlayerUnavailable = audioPlayer == nil
        return audioPlayer
    }

    private func startTickTaskIfNeeded() {
        guard tickTask == nil else { return }
        tickGeneration += 1
        let generation = tickGeneration
        tickTask = Task { await runTicks(generation: generation) }
    }

    /// Plays ticks as the schedule asks until the reports stop, then releases the audio engine.
    private func runTicks(generation: Int) async {
        while !Task.isCancelled, generation == tickGeneration {
            switch schedule.next(now: now, report: latestReport, chimeEndsAt: chimeEndsAt) {
            case .tick(let pitchIndex, let wait):
                audioOutput()?.playTick(pitchIndex: pitchIndex)
                try? await Task.sleep(for: .seconds(wait))
            case .wait(let wait):
                try? await Task.sleep(for: .seconds(wait))
            case .finished:
                // Ended on its own, not through stopGuidanceAudio(): release the audio engine.
                stopGuidanceAudio()
                return
            }
        }
    }
}
