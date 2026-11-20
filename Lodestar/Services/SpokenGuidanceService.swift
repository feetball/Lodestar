import AVFAudio
import Foundation
import LodestarKit

/// Speaks the aiming guidance with the system's speech synthesiser: the words come from `GuidanceSpeech`, which decides
/// what is worth saying and when; this class says them.
///
/// The phone is often clamped above eye level while the photographer's hands are on the tripod head, so the screen is
/// not readable when it matters. The audio session is `.ambient`, like the one of the audio ticks
/// (`FeedbackAudioPlayer`): it mixes with other audio and obeys the Silent switch and screen lock.
///
/// A phrase still being spoken is not cut off by the next one: while the head is moving, that would never let one finish.
/// The newer guidance is spoken once the phrase has ended; only "On target" interrupts. A phrase that was dropped does not
/// count as spoken, so the next call offers it again.
@MainActor
final class SpokenGuidanceService {
    /// Utterance rates: `AVSpeechUtteranceDefaultSpeechRate` is 0.5.
    private static let normalRate: Float = 0.5
    private static let slowRate: Float = 0.38
    /// Pause between failed attempts to activate the audio session (a phone call, for example, refuses it).
    private static let retryDelay: Duration = .seconds(1)

    private let synthesizer = AVSpeechSynthesizer()
    /// The phrases are English: use the device's voice if it speaks English, else an American one.
    private let voice: AVSpeechSynthesisVoice?
    private var isEnabled = false
    private var rate = SpokenGuidanceRate.normal
    /// What was last spoken in this session; `nil` at its start.
    private var previous: SpokenState?
    /// Whether this service activated the audio session and has not released it yet.
    private var holdsSession = false
    private var retryNotBefore: ContinuousClock.Instant?

    init() {
        let isEnglish = Locale.current.language.languageCode == .english
        voice = AVSpeechSynthesisVoice(language: isEnglish ? AVSpeechSynthesisVoice.currentLanguageCode() : "en-US")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Turns speaking on or off and sets its rate. Cheap; called whenever settings are applied.
    func configure(isEnabled: Bool, rate: SpokenGuidanceRate) {
        self.rate = rate
        guard isEnabled != self.isEnabled else { return }
        self.isEnabled = isEnabled
        if !isEnabled { stop() }
    }

    /// Offers the newest guidance. Call every frame while aiming; it speaks only when `GuidanceSpeech` has something to say.
    func update(_ guidance: Guidance, now: Date = Date()) {
        guard isEnabled,
              let phrase = GuidanceSpeech.phrase(current: guidance, previous: previous, now: now) else { return }
        if synthesizer.isSpeaking {
            guard phrase.state.kind == .onTarget else { return }
            synthesizer.stopSpeaking(at: .immediate)
        }
        guard activateSession() else { return }
        let utterance = AVSpeechUtterance(string: phrase.text)
        utterance.rate = rate == .slow ? Self.slowRate : Self.normalRate
        utterance.voice = voice
        synthesizer.speak(utterance)
        previous = phrase.state
    }

    /// Forgets what was said and falls silent: the target changed or the guidance ended. The next phrase starts a new
    /// session, so it says "degrees" again.
    func reset() {
        previous = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// Falls silent and releases the audio session; call when the Aim screen goes away. Idempotent.
    func stop() {
        reset()
        guard holdsSession else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        holdsSession = false
    }

    /// Activates the `.ambient` session unless it is active already. `false` if the system refuses.
    private func activateSession() -> Bool {
        if let retryNotBefore, ContinuousClock.now < retryNotBefore { return false }
        retryNotBefore = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient)
            try session.setActive(true)
            holdsSession = true
            return true
        } catch {
            retryNotBefore = ContinuousClock.now + Self.retryDelay
            return false
        }
    }
}
