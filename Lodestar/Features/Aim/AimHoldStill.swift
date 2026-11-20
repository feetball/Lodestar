import Foundation
import LodestarKit

/// Where the wait between tapping Sync and syncing stands.
enum AimHoldStillStatus: Equatable, Sendable {
    /// Still waiting; `progress` in [0, 1] is how much of the steady window the camera has been still for.
    case waiting(progress: Double)
    /// The camera was still for the whole window: sync now.
    case steady
    /// `AimHoldStill.timeoutSeconds` passed without a steady window.
    case timedOut
}

/// The wait between tapping Sync and syncing: the alignment is only recorded once the camera has been held still for
/// a whole window (`SteadinessDetector`), and the wait ends after `timeoutSeconds` without one.
///
/// Feed `update(now:sample:)` with the newest boresight sample at a steady pace (every `pollInterval`) and the
/// caller's clock. The clock is any monotonic seconds value; it is not the sensor clock, so a stalled sensor still
/// times out. Make a new one for each tap on Sync.
struct AimHoldStill: Sendable {
    /// Seconds after which the wait gives up.
    static let timeoutSeconds = 6.0
    /// Time between two looks at the sensors: about the sensors' own rate, so a short shake is seen.
    static let pollInterval: Duration = .milliseconds(20)
    /// Shown when the wait timed out.
    static let timeoutNotice = "The phone is still moving. Steady the tripod and try again."

    private let startedAt: Double
    private let timeoutSeconds: Double
    private var detector = SteadinessDetector()

    /// `startedAt` is the caller's clock, in seconds, when Sync was tapped.
    init(startedAt: Double, timeoutSeconds: Double = AimHoldStill.timeoutSeconds) {
        self.startedAt = startedAt
        self.timeoutSeconds = timeoutSeconds
    }

    /// Takes the newest `sample` (`nil` when the sensors delivered nothing) at `now` and says how the wait stands.
    /// A steady window wins over a timeout that falls at the same moment.
    mutating func update(now: Double, sample: SteadinessSample?) -> AimHoldStillStatus {
        if let sample { detector = detector.adding(sample) }
        if detector.isSteady { return .steady }
        if now - startedAt >= timeoutSeconds { return .timedOut }
        return .waiting(progress: detector.progress)
    }
}
