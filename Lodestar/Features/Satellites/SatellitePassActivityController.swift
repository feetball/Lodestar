import ActivityKit
import Foundation

/// Runs the Live Activity of the pass Aim follows or waits for: it starts with the follow, is brought up to date at the
/// rise and the peak while the app can run, and ends with the pass or when the follow stops. The Lock Screen banner and
/// the Dynamic Island count down to the rise and then to the peak (`LodestarWidgets/SatellitePassLiveActivity.swift`).
///
/// The system draws the countdown itself, so it keeps running while the app is suspended. What a suspended app cannot
/// do is move the activity on at the rise or the peak, so each update sets a stale date at the next change: the views
/// pick the stage from the clock, never an earlier one than it says.
@MainActor
final class SatellitePassActivityController {
    /// How long a finished pass stays on the Lock Screen.
    static let lingerAfterPass: TimeInterval = 120

    private var activity: Activity<SatellitePassActivityAttributes>?
    private var timeline: SatellitePassTimeline?
    private var updateTask: Task<Void, Never>?

    init() {
        // A follow does not survive the app being closed, so an activity left from a run that ended is stale.
        Task {
            for leftover in Activity<SatellitePassActivityAttributes>.activities {
                await leftover.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Starts the activity for the pass of `source`. Does nothing when activities are off in Settings, the source has no
    /// pass, or the pass is over.
    func begin(for source: SatelliteAimSource, isNight: Bool, now: Date = Date()) {
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let item = source.passItem,
              let timeline = Self.timeline(of: item), timeline.stage(at: now) != .over else { return }
        let attributes = SatellitePassActivityAttributes(
            name: item.name, timeline: timeline, waitsAtPeak: source.isPeak, isNight: isNight)
        let content = Self.content(for: timeline, at: now)
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            // The system refuses when too many activities run or the user switched them off meanwhile.
            return
        }
        self.timeline = timeline
        scheduleUpdates(for: timeline)
    }

    /// Ends the activity at once (the follow stopped).
    func end() {
        updateTask?.cancel()
        updateTask = nil
        timeline = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Moves the activity to the stage the clock says (the app was suspended and missed a change).
    func refresh(now: Date = Date()) {
        guard let activity, let timeline else { return }
        advance(activity, timeline: timeline, now: now)
    }

    // MARK: Private

    /// The rise, the peak and the set of a pass. The peak is the highest point of the visible part.
    private static func timeline(of item: SatellitePassItem) -> SatellitePassTimeline? {
        let pass = item.pass
        return SatellitePassTimeline(
            rise: pass.rise.date, peak: item.peak.date, set: pass.set.date,
            riseAzimuth: pass.rise.azimuth, peakAzimuth: item.peak.azimuth, setAzimuth: pass.set.azimuth,
            peakAltitude: item.peak.altitude)
    }

    private static func content(for timeline: SatellitePassTimeline, at now: Date)
        -> ActivityContent<SatellitePassActivityAttributes.ContentState> {
        ActivityContent(state: .init(stage: timeline.stage(at: now)), staleDate: timeline.nextChange(after: now))
    }

    private func scheduleUpdates(for timeline: SatellitePassTimeline) {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                guard let next = timeline.nextChange(after: now) else { break }
                // A moment past the change, so that the stage has changed when it is asked for.
                try? await Task.sleep(for: .seconds(max(next.timeIntervalSince(now), 0) + 0.5))
                guard !Task.isCancelled, let self, let activity = self.activity else { return }
                self.advance(activity, timeline: timeline, now: Date())
            }
        }
    }

    private func advance(_ activity: Activity<SatellitePassActivityAttributes>, timeline: SatellitePassTimeline,
                         now: Date) {
        if timeline.stage(at: now) == .over {
            updateTask?.cancel()
            updateTask = nil
            self.activity = nil
            self.timeline = nil
            let state = SatellitePassActivityAttributes.ContentState(stage: .over)
            let ending = ActivityContent(state: state, staleDate: nil)
            Task {
                await activity.end(ending, dismissalPolicy: .after(now.addingTimeInterval(Self.lingerAfterPass)))
            }
            return
        }
        let content = Self.content(for: timeline, at: now)
        Task { await activity.update(content) }
    }
}
