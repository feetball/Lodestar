import SwiftUI
import LodestarKit
import Observation

/// What the Starlink streak warning knows.
enum SatelliteStreakState {
    /// Nothing to show: the feed is off, the pointing is not known, or there is no satellite data yet.
    case hidden
    /// The Starlink data is older than its freshness limit, so no prediction is made.
    case tooOld
    /// The newest assessment of the framing.
    case ready(SatelliteStreakResult)
}

/// An assessment of the framing together with the exposure it is for.
struct SatelliteStreakResult: Sendable {
    let assessment: StreakAssessment
    let exposureSeconds: Int
    let computedAt: Date

    var risk: Double { assessment.probabilityOfStreak(exposureSeconds: Double(exposureSeconds)) }
}

/// The Starlink streak warning's background work: about once a second it takes the camera's framing from Aim, works out
/// which satellites cross it during the exposure (`StreakRisk.assess`, off the main actor) and publishes the result. It does
/// nothing while the Starlink data is older than its limit. When the camera has hardly moved, a result under three seconds
/// old is reused. The exposure is the longest one that keeps stars sharp with the lens (the NPF rule, with the target's
/// declination when there is one): the app has no exposure setting of its own.
@MainActor
@Observable
final class SatelliteStreakMonitor {
    private(set) var state = SatelliteStreakState.hidden
    /// Whether the sheet with the crossings is open. It closes with the result it shows.
    var isSheetPresented = false

    /// The shortest exposure considered, in seconds.
    nonisolated static let minimumExposure = 1
    /// The longest, in seconds: long exposures are the tracker's business, not the plain tripod's.
    nonisolated static let maximumExposure = 120

    private static let interval: TimeInterval = 1
    private static let reuseAge: TimeInterval = 3
    private static let reuseDegrees = 0.5

    @ObservationIgnored private var lastRun = Date.distantPast
    @ObservationIgnored private var lastBoresight: Vector3?
    @ObservationIgnored private var lastLens: LensSetup?
    @ObservationIgnored private var lastTargetID: String?
    @ObservationIgnored private var isComputing = false
    /// Counts the clears, so that an answer computed before one is dropped.
    @ObservationIgnored private var epoch = 0

    /// Forgets the result (the warning is off or the pointing is unknown).
    func clear() {
        epoch += 1
        lastBoresight = nil
        lastRun = .distantPast
        isSheetPresented = false
        if case .hidden = state { return }
        state = .hidden
    }

    /// Called with every sensor tick of the Aim screen; works at most once a second.
    func tick(model: AimViewModel) {
        let app = model.app
        guard app.online.isEnabled(.starlink), let group = app.online.satellites.starlink,
              let observer = app.observerContext?.observer else {
            clear()
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= Self.interval, !isComputing else { return }
        guard let frame = model.engine.frame() else {
            clear()
            return
        }
        lastRun = now
        guard group.isFresh(at: now) else {
            isSheetPresented = false
            if case .tooOld = state {} else { state = .tooOld }
            return
        }
        let configuration = model.configuration
        let lens = app.lensSetup
        let target = model.guidanceTarget
        let boresight = frame.pointing.boresightVector
        let moved = lastBoresight.map { $0.angle(to: boresight) > Self.reuseDegrees } ?? true
        if case .ready(let previous) = state, !moved, now.timeIntervalSince(previous.computedAt) < Self.reuseAge,
           lens == lastLens, target?.id == lastTargetID {
            return
        }
        // The engine's frame (not the app's own `CameraFrame`, the camera picture).
        guard let cameraFrame = LodestarKit.CameraFrame(solution: frame.pointing, widthDegrees: configuration.lensFrame.horizontal,
                                                        heightDegrees: configuration.lensFrame.vertical) else {
            clear()
            return
        }
        isComputing = true
        let request = epoch
        let satellites = group.satellites
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                let seconds = Self.exposure(lens: lens, target: target, observer: observer, now: now)
                let assessment = StreakRisk.assess(satellites, observer: observer, frame: cameraFrame,
                                                   exposure: DateInterval(start: now, duration: Double(seconds)))
                return SatelliteStreakResult(assessment: assessment, exposureSeconds: seconds, computedAt: now)
            }.value
            guard let self else { return }
            self.isComputing = false
            guard request == self.epoch else { return }
            self.lastBoresight = boresight
            self.lastLens = lens
            self.lastTargetID = target?.id
            self.state = .ready(result)
        }
    }

    /// The longest exposure in whole seconds that keeps stars sharp for `lens` (the NPF rule, with the declination of
    /// `target` at `now` when there is one), within the range the warning considers.
    nonisolated static func exposure(lens: LensSetup, target: CelestialObject?, observer: Observer, now: Date) -> Int {
        let declination = target.map { SkyFrame(date: now, observer: observer).apparentEquatorial(of: $0).declination }
        let seconds = ExposureCalculator.maxExposure(rule: .npf, setup: lens, declination: declination).seconds
        guard seconds.isFinite else { return minimumExposure }
        return min(max(Int(seconds.rounded()), minimumExposure), maximumExposure)
    }
}

/// The Starlink streak warning in Aim: a chip among the status chips, for example "Starlink: 3 crossings in 30 s · 12%
/// streak risk", that opens the list of crossings. Shown only while the Starlink feed is on and the pointing is known.
struct SatelliteStreakChip: View {
    let model: AimViewModel
    @Environment(\.palette) private var palette

    private static let symbol = "point.topleft.down.to.point.bottomright.curvepath"

    var body: some View {
        @Bindable var streak = model.streak
        switch streak.state {
        case .hidden:
            EmptyView()
        case .tooOld:
            StatusChip(systemImage: Self.symbol, text: SatelliteText.streakStaleChip)
                .aimChipBacking(palette)
        case .ready(let result):
            let text = SatelliteText.streakChip(crossings: result.assessment.crossings.count,
                                                exposureSeconds: result.exposureSeconds, risk: result.risk)
            Button {
                streak.isSheetPresented = true
            } label: {
                // Padded to the minimum touch target.
                StatusChip(systemImage: Self.symbol, text: text,
                           tone: result.assessment.crossings.isEmpty ? .neutral : .warning)
                    .aimChipBacking(palette)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text)
            .accessibilityHint("Shows the Starlink crossings")
            .sheet(isPresented: $streak.isSheetPresented) {
                SatelliteStreakSheet(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .themedRoot(model.app.palette, redFilter: model.app.settings.redFilterOverlay)
            }
        }
    }
}

/// The crossings of the framing: entry and exit times and brightness, with the numbers behind the chip.
private struct SatelliteStreakSheet: View {
    let model: AimViewModel
    @Environment(\.palette) private var palette

    /// The most crossings listed.
    private static let maximumRows = 25

    private var timeZone: TimeZone { model.app.observerContext?.timeZone ?? .autoupdatingCurrent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(SatelliteText.streakSheetTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if case .ready(let result) = model.streak.state {
                    crossings(result)
                } else {
                    TonightNote(text: SatelliteText.streakStaleChip)
                }
                TonightNote(text: SatelliteText.streakNote, style: .footnote)
                TonightNote(text: SatelliteText.attribution, style: .footnote)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground(palette)
    }

    @ViewBuilder
    private func crossings(_ result: SatelliteStreakResult) -> some View {
        let assessment = result.assessment
        TonightNote(text: SatelliteText.streakSummary(
            exposureSeconds: result.exposureSeconds, sunlitAbove20: assessment.sunlitAboveSummaryAltitudeCount,
            crossingsPerMinute: assessment.crossingsPerMinute, risk: result.risk))
        if assessment.crossings.isEmpty {
            Text(SatelliteText.noCrossings)
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
        }
        let shown = Array(assessment.crossings.prefix(Self.maximumRows).enumerated())
        ForEach(shown, id: \.offset) { index, crossing in
            if index > 0 { TonightRowSeparator() }
            VStack(alignment: .leading, spacing: 2) {
                Text(crossing.satellite.name)
                    .font(.body)
                    .foregroundStyle(palette.primaryText)
                Text(SatelliteText.crossing(crossing, in: timeZone))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
        if assessment.crossings.count > shown.count {
            TonightNote(text: "and \(assessment.crossings.count - shown.count) more", style: .footnote)
        }
    }
}
