import AVFAudio
import Foundation

/// Plays the feedback sounds: ticks at a choice of pitches and the "target acquired" chime.
///
/// The sounds are rendered once into PCM buffers and queued on an `AVAudioPlayerNode`, so nothing runs on the
/// real-time audio thread. The `.ambient` session mixes with other audio and obeys the Silent switch and screen
/// lock. The engine starts on first use and starts again on demand after interruptions and route changes.
@MainActor
final class FeedbackAudioPlayer {
    private static let volume: Float = 0.6
    /// Pause between failed attempts to start the engine (a phone call, for example, refuses the session).
    private static let retryDelay: Duration = .seconds(1)

    private let format: AVAudioFormat
    private let tickBuffers: [AVAudioPCMBuffer]
    private let chimeBuffer: AVAudioPCMBuffer
    private let observations = NotificationObservations()

    private var engine = AVAudioEngine()
    private var node = AVAudioPlayerNode()
    /// Whether the engine runs with the session active, as far as this player knows; cleared when the system stops it.
    private var isSessionActive = false
    /// Whether this player activated the audio session and has not released it yet. Unlike `isSessionActive` it
    /// survives the system stopping the engine (a route change leaves the session active), so `stop()` can release it.
    private var holdsSession = false
    private var retryNotBefore: ContinuousClock.Instant?

    /// Renders the sounds; `nil` if the audio format or a buffer cannot be created.
    init?() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: FeedbackSynthesizer.sampleRate, channels: 1) else {
            return nil
        }
        let ticks = (0..<FeedbackTone.pitchCount).compactMap { index in
            Self.makeBuffer(FeedbackSynthesizer.tick(frequency: FeedbackTone.frequency(ofPitch: index)), format: format)
        }
        guard ticks.count == FeedbackTone.pitchCount,
              let chime = Self.makeBuffer(FeedbackSynthesizer.chime(), format: format) else {
            return nil
        }
        self.format = format
        tickBuffers = ticks
        chimeBuffer = chime
        buildGraph()
        observeAudioSystem()
    }

    /// Queues one tick at `pitchIndex` (see `FeedbackTone`), starting the engine if needed.
    func playTick(pitchIndex: Int) {
        guard ensureRunning() else { return }
        let index = min(max(pitchIndex, 0), tickBuffers.count - 1)
        node.scheduleBuffer(tickBuffers[index], at: nil, options: [], completionHandler: nil)
    }

    /// Plays the chime over whatever is queued, starting the engine if needed. Returns `false` if audio is unavailable.
    @discardableResult
    func playChime() -> Bool {
        guard ensureRunning() else { return false }
        node.scheduleBuffer(chimeBuffer, at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    /// Stops the engine and releases the audio session. Idempotent.
    func stop() {
        guard isSessionActive || holdsSession else { return }
        node.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSessionActive = false
        holdsSession = false
    }

    // MARK: Private

    private static func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }

    private func buildGraph() {
        engine = AVAudioEngine()
        node = AVAudioPlayerNode()
        node.volume = Self.volume
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// Activates the session and starts the engine unless it is already running. `false` if the system refuses.
    private func ensureRunning() -> Bool {
        if isSessionActive && engine.isRunning { return true }
        if let retryNotBefore, ContinuousClock.now < retryNotBefore { return false }
        retryNotBefore = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient)
            try session.setActive(true)
            holdsSession = true
            try engine.start()
            node.play()
            isSessionActive = true
            return true
        } catch {
            retryNotBefore = ContinuousClock.now + Self.retryDelay
            return false
        }
    }

    private func observeAudioSystem() {
        observations.observe(AVAudioSession.interruptionNotification) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            Task { @MainActor [weak self] in self?.systemStoppedEngine() }
        }
        observations.observe(.AVAudioEngineConfigurationChange) { [weak self] _ in
            Task { @MainActor [weak self] in self?.systemStoppedEngine() }
        }
        observations.observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            Task { @MainActor [weak self] in self?.mediaServicesWereReset() }
        }
    }

    /// The system stopped the engine (interruption or route change); the next sound restarts it. Sounds still queued
    /// are dropped, so they are not played late when it does. The session may still be active: `stop()` releases it.
    private func systemStoppedEngine() {
        isSessionActive = false
        node.stop()
    }

    /// All audio objects became invalid; build them again and start on demand. The session starts over inactive.
    private func mediaServicesWereReset() {
        isSessionActive = false
        holdsSession = false
        buildGraph()
    }
}
