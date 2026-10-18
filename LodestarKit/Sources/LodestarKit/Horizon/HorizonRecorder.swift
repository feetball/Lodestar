import Foundation

/// Records a `HorizonProfile` while the user sweeps the camera along the skyline.
///
/// The app feeds one sample for every attitude update: the azimuth and altitude of the camera's optical axis
/// (the boresight, in true-north azimuth), the sensor clock and, if the platform has one, a sensor quality.
/// The camera is held so that the skyline runs through the middle of the picture; the boresight altitude is
/// then the skyline altitude.
///
/// - **Bins.** Samples are collected per whole degree: bin `n` holds azimuths from `n − 0.5°` to `n + 0.5°`
///   and becomes the skyline altitude at azimuth `n°`. A bin is the **median** of the (at most
///   `Configuration.maximumSamplesPerBin`) most recent samples it holds, which removes hand jitter and
///   single wild readings. Bin 0 follows bin 359, so a sweep may cross north.
/// - **Backtracking.** Order and direction do not matter. A bin that is entered again more than
///   `Configuration.newPassInterval` seconds after its last sample starts over, so sweeping back over a
///   stretch replaces what was recorded there (the careful second pass wins); a wobble back and forth within
///   a few seconds just adds samples to the median.
/// - **Rejected samples.** A sample is not used when a number is not finite (`Rejection.invalid`), its
///   quality is below `Configuration.minimumQuality` (`Rejection.lowQuality`), its altitude is outside
///   −10°…+60° (`Rejection.outOfRange`) or the camera sweeps faster than `Configuration.maximumSweepRate`
///   degrees per second since the previous sample (`Rejection.tooFast`; the sensors lag behind a fast
///   sweep, and a single wild reading in azimuth rejects itself and the sample after it). The speed is that of
///   the azimuth change, scaled by the cosine of the altitude; altitude jitter, which is what the median is
///   for, does not count. The first reason that applies, in this order, is reported.
/// - **Gaps.** Bins without a sample are filled from the nearest recorded bins by linear interpolation when
///   the run of missing bins is at most `Configuration.maximumInterpolatedGap` long (sweeping slightly too
///   fast). Longer runs are gaps: they are reported, in `gaps` while recording and in `Recording.gaps` at the
///   end, and get the value the `UnrecordedFill` chooses.
/// - **Partial sweeps.** Recording only part of the circle is fine. What the rest becomes is explicit: with
///   `UnrecordedFill.keepBase` (the default) it keeps the altitude of the `base` profile passed to `finish`, or
///   0° (flat) when there is none; with `UnrecordedFill.interpolate` it is a straight line between the
///   recorded ends. Passing the stored profile as `base` is how a new partial sweep is merged into it.
///
/// A value type: `add`, `clear` and `reset` mutate it. Memory is fixed: 72 KB with the default 25 samples per
/// bin (at most 288 KB). Call `reset()` (or make a new recorder) for a new sweep: the sensor clock is expected to
/// keep increasing within one recording. Not thread safe.
public struct HorizonRecorder: Sendable {
    /// The thresholds of a `HorizonRecorder`.
    ///
    /// Construction replaces a value that is not finite, or not in its range, by its default and clamps the
    /// counts; see `standard`.
    public struct Configuration: Sendable, Hashable {
        /// Samples with a quality below this are rejected; [0, 1], default 0.25. A sample without a quality
        /// is accepted.
        public let minimumQuality: Double
        /// Samples that follow the previous sample (one that passed the validity, quality and range checks)
        /// faster than this many degrees per second are rejected; positive, default 60.
        public let maximumSweepRate: Double
        /// How many recent samples a bin keeps for its median; 1…100, default 25.
        public let maximumSamplesPerBin: Int
        /// Seconds after which re-entering a bin starts it over; positive, default 3.
        public let newPassInterval: Double
        /// The longest run of empty bins (degrees) that is filled by interpolation and is not reported as a
        /// gap; 0…30, default 6.
        public let maximumInterpolatedGap: Int

        /// The default thresholds.
        public static let standard = Configuration()

        /// Creates a configuration; a value out of range falls back to its default (counts are clamped).
        public init(minimumQuality: Double = 0.25, maximumSweepRate: Double = 60, maximumSamplesPerBin: Int = 25,
                    newPassInterval: Double = 3, maximumInterpolatedGap: Int = 6) {
            self.minimumQuality = minimumQuality.isFinite ? AstroMath.clamp(minimumQuality, 0, 1) : 0.25
            self.maximumSweepRate = maximumSweepRate.isFinite && maximumSweepRate > 0 ? maximumSweepRate : 60
            self.maximumSamplesPerBin = AstroMath.clamp(maximumSamplesPerBin, 1, 100)
            self.newPassInterval = newPassInterval.isFinite && newPassInterval > 0 ? newPassInterval : 3
            self.maximumInterpolatedGap = AstroMath.clamp(maximumInterpolatedGap, 0, 30)
        }
    }

    /// Why `add` did not use a sample.
    public enum Rejection: String, Sendable, Hashable, CaseIterable {
        /// The azimuth, altitude or timestamp is not finite.
        case invalid
        /// The sensor quality is below `Configuration.minimumQuality`.
        case lowQuality
        /// The altitude is outside −10°…+60°, so it cannot be the skyline.
        case outOfRange
        /// The camera swept faster than `Configuration.maximumSweepRate`.
        case tooFast
    }

    /// What happens to the bins that no sample reached and that interpolation does not fill.
    public enum UnrecordedFill: String, Sendable, Hashable, CaseIterable {
        /// They keep the `base` profile's altitude, or 0° without a base.
        case keepBase
        /// They follow a straight line between the nearest recorded bins on either side (wrapping through north).
        case interpolate
    }

    /// A finished recording.
    public struct Recording: Sendable, Hashable {
        /// The skyline: recorded bins, interpolated small gaps, and the unrecorded rest as chosen.
        public let profile: HorizonProfile
        /// The fraction of the 360 bins that received at least one sample, [0, 1].
        public let coverage: Double
        /// The unrecorded stretches longer than `Configuration.maximumInterpolatedGap`, in azimuth order (the
        /// range that starts first after north comes first).
        public let gaps: [AzimuthRange]
        /// How many bins were filled by interpolation: small gaps and, with `UnrecordedFill.interpolate`,
        /// large ones.
        public let interpolatedBinCount: Int

        /// `true` when no gap is left: every azimuth was recorded or lies in a small gap.
        public var isComplete: Bool { gaps.isEmpty }

        /// Creates a recording.
        public init(profile: HorizonProfile, coverage: Double, gaps: [AzimuthRange], interpolatedBinCount: Int) {
            self.profile = profile
            self.coverage = coverage
            self.gaps = gaps
            self.interpolatedBinCount = interpolatedBinCount
        }
    }

    /// The thresholds this recorder applies.
    public let configuration: Configuration

    private let capacity: Int
    private var samples: [Double]
    private var counts: [Int]
    private var heads: [Int]
    private var lastTimes: [Double]
    private var recordedCount = 0
    private var acceptedTotal = 0
    private var rejectedTotals: [Int]
    private var hasPrevious = false
    private var previousAzimuth = 0.0
    private var previousAltitude = 0.0
    private var previousTime = 0.0
    private var latestRate = Double.nan

    /// Creates an empty recorder.
    public init(configuration: Configuration = .standard) {
        self.configuration = configuration
        capacity = configuration.maximumSamplesPerBin
        samples = [Double](repeating: 0, count: HorizonProfile.binCount * configuration.maximumSamplesPerBin)
        counts = [Int](repeating: 0, count: HorizonProfile.binCount)
        heads = [Int](repeating: 0, count: HorizonProfile.binCount)
        lastTimes = [Double](repeating: 0, count: HorizonProfile.binCount)
        rejectedTotals = [Int](repeating: 0, count: Rejection.allCases.count)
    }

    // MARK: Feeding

    /// Feeds one sample and returns why it was not used, or `nil` when it was.
    ///
    /// - Parameters:
    ///   - azimuth: Azimuth of the camera axis in degrees from true north through east.
    ///   - altitude: Altitude of the camera axis in degrees; the skyline is at the middle of the picture.
    ///   - timestamp: The sensor clock in seconds (it only needs to increase while the user sweeps).
    ///   - quality: The quality of the heading, 0 (unusable) to 1 (best), if known; `nil` or not finite means
    ///     unknown, which is accepted. Platforms map their accuracy levels onto this range.
    @discardableResult
    public mutating func add(azimuth: Double, altitude: Double, timestamp: Double, quality: Double? = nil) -> Rejection? {
        guard azimuth.isFinite, altitude.isFinite, timestamp.isFinite else { return reject(.invalid) }
        if let quality, quality.isFinite, quality < configuration.minimumQuality { return reject(.lowQuality) }
        guard altitude >= HorizonProfile.lowestAltitude, altitude <= HorizonProfile.highestAltitude else {
            return reject(.outOfRange)
        }
        let wrapped = AstroMath.normalizeDegrees(azimuth)
        var tooFast = false
        if hasPrevious {
            let elapsed = timestamp - previousTime
            if elapsed > 0 {
                let turn = AstroMath.normalizeSignedDegrees(wrapped - previousAzimuth)
                    * AstroMath.cosDeg((altitude + previousAltitude) / 2)
                latestRate = abs(turn) / elapsed
                tooFast = latestRate > configuration.maximumSweepRate
            }
        }
        hasPrevious = true
        previousAzimuth = wrapped
        previousAltitude = altitude
        previousTime = timestamp
        if tooFast { return reject(.tooFast) }

        let bin = Int((wrapped + 0.5).rounded(.down)) % HorizonProfile.binCount
        if counts[bin] > 0, timestamp - lastTimes[bin] > configuration.newPassInterval {
            counts[bin] = 0
            heads[bin] = 0
            recordedCount -= 1
        }
        if counts[bin] == 0 { recordedCount += 1 }
        let slot = heads[bin]
        samples[bin * capacity + slot] = altitude
        heads[bin] = slot + 1 == capacity ? 0 : slot + 1
        if counts[bin] < capacity { counts[bin] += 1 }
        lastTimes[bin] = timestamp

        acceptedTotal += 1
        return nil
    }

    private mutating func reject(_ reason: Rejection) -> Rejection {
        rejectedTotals[Self.index(of: reason)] += 1
        return reason
    }

    private static func index(of reason: Rejection) -> Int {
        Rejection.allCases.firstIndex(of: reason) ?? 0
    }

    // MARK: Progress

    /// How many samples were used.
    public var acceptedCount: Int { acceptedTotal }

    /// How many samples were rejected for `reason`.
    public func rejectedCount(for reason: Rejection) -> Int { rejectedTotals[Self.index(of: reason)] }

    /// The sweep speed in degrees per second (the change of azimuth times the cosine of the altitude) between
    /// the last two samples that passed the validity, quality and range checks, so a `Rejection.tooFast`
    /// sample shows its speed; `nil` before the second one. Show it to ask the user to slow down before
    /// samples are rejected.
    public var sweepRate: Double? { latestRate.isNaN ? nil : latestRate }

    /// The azimuth of the last sample that passed the validity, quality and range checks, in degrees; `nil`
    /// before the first.
    public var lastAzimuth: Double? { hasPrevious ? previousAzimuth : nil }

    /// The altitude of the last sample that passed the validity, quality and range checks, in degrees; `nil`
    /// before the first.
    public var lastAltitude: Double? { hasPrevious ? previousAltitude : nil }

    /// How many of the 360 bins hold at least one sample.
    public var recordedBinCount: Int { recordedCount }

    /// The fraction of the circle that has been recorded, [0, 1]: the progress of the sweep.
    public var coverage: Double { Double(recordedCount) / Double(HorizonProfile.binCount) }

    /// Whether the bin of `azimuth` (any angle, in degrees) holds a sample.
    public func isRecorded(_ azimuth: Double) -> Bool {
        guard azimuth.isFinite else { return false }
        return counts[binIndex(of: azimuth)] > 0
    }

    /// For each whole degree 0…359, whether its bin holds a sample; draw the recorded arc from it.
    public var recordedMask: [Bool] { counts.map { $0 > 0 } }

    /// The unrecorded stretches that are longer than `Configuration.maximumInterpolatedGap`, in azimuth order:
    /// the parts the user still has to sweep. Each range starts at the lower edge of its first bin (e.g.
    /// 79.5° for a gap that starts at bin 80). With nothing recorded it is the whole circle.
    public var gaps: [AzimuthRange] { describe(unrecordedRuns()) }

    // MARK: Result

    /// The skyline recorded so far (see `finish`); cheap enough to redraw while the user sweeps.
    ///
    /// - Parameters:
    ///   - fill: What the unrecorded bins that are not interpolated become.
    ///   - base: The profile the unrecorded bins keep with `UnrecordedFill.keepBase`; flat when `nil`.
    public func profile(fill: UnrecordedFill = .keepBase, base: HorizonProfile? = nil) -> HorizonProfile {
        finish(fill: fill, base: base).profile
    }

    /// Ends the recording: the skyline, how much of the circle was recorded and the gaps that are left.
    /// The recorder is not changed; the sweep can continue and be finished again.
    ///
    /// - Parameters:
    ///   - fill: What the unrecorded bins that are not interpolated become.
    ///   - base: The profile the unrecorded bins keep with `UnrecordedFill.keepBase`; flat when `nil`.
    public func finish(fill: UnrecordedFill = .keepBase, base: HorizonProfile? = nil) -> Recording {
        let binCount = HorizonProfile.binCount
        var values = (0..<binCount).map { base?.altitudes[$0] ?? 0 }
        if recordedCount == 0 {
            return Recording(profile: HorizonProfile.fromClamped(values), coverage: 0, gaps: [.full],
                             interpolatedBinCount: 0)
        }

        var medians = [Double](repeating: 0, count: binCount)
        var scratch = [Double](repeating: 0, count: capacity)
        for bin in 0..<binCount where counts[bin] > 0 {
            medians[bin] = median(of: bin, scratch: &scratch)
            values[bin] = medians[bin]
        }
        var interpolated = 0
        let runs = unrecordedRuns()
        for run in runs {
            let interpolate = run.length <= configuration.maximumInterpolatedGap || fill == .interpolate
            guard interpolate else { continue }
            let before = (run.start + binCount - 1) % binCount
            let after = (run.start + run.length) % binCount
            for offset in 0..<run.length {
                let fraction = Double(offset + 1) / Double(run.length + 1)
                values[(run.start + offset) % binCount] = medians[before] + (medians[after] - medians[before]) * fraction
            }
            interpolated += run.length
        }
        return Recording(profile: HorizonProfile.fromClamped(values), coverage: coverage, gaps: describe(runs),
                         interpolatedBinCount: interpolated)
    }

    // MARK: Editing the recording

    /// Forgets everything recorded in `range`, so that stretch can be swept again. Samples that arrive
    /// later are collected from scratch there.
    public mutating func clear(_ range: AzimuthRange) {
        for bin in 0..<HorizonProfile.binCount where counts[bin] > 0 && range.contains(Double(bin)) {
            counts[bin] = 0
            heads[bin] = 0
            recordedCount -= 1
        }
    }

    /// Forgets all samples and counts; the recorder is as new.
    public mutating func reset() {
        counts = [Int](repeating: 0, count: HorizonProfile.binCount)
        heads = [Int](repeating: 0, count: HorizonProfile.binCount)
        recordedCount = 0
        acceptedTotal = 0
        rejectedTotals = [Int](repeating: 0, count: Rejection.allCases.count)
        hasPrevious = false
        previousAzimuth = 0
        previousAltitude = 0
        previousTime = 0
        latestRate = .nan
    }

    // MARK: Helpers

    /// A run of unrecorded bins: the first bin and how many follow it (wrapping through bin 359 → 0).
    private struct Run {
        let start: Int
        let length: Int
    }

    private func binIndex(of azimuth: Double) -> Int {
        Int((AstroMath.normalizeDegrees(azimuth) + 0.5).rounded(.down)) % HorizonProfile.binCount
    }

    /// The median of the samples of a recorded bin.
    private func median(of bin: Int, scratch: inout [Double]) -> Double {
        let count = counts[bin]
        let base = bin * capacity
        for index in 0..<count {
            let value = samples[base + index]
            var position = index
            while position > 0, scratch[position - 1] > value {
                scratch[position] = scratch[position - 1]
                position -= 1
            }
            scratch[position] = value
        }
        let middle = count / 2
        return count % 2 == 1 ? scratch[middle] : (scratch[middle - 1] + scratch[middle]) / 2
    }

    /// All runs of unrecorded bins, in bin order starting after the first recorded bin; empty when all are recorded.
    private func unrecordedRuns() -> [Run] {
        let binCount = HorizonProfile.binCount
        guard recordedCount > 0, let first = counts.firstIndex(where: { $0 > 0 }) else {
            return [Run(start: 0, length: binCount)]
        }
        var runs = [Run]()
        var start = -1
        for offset in 1...binCount {
            let bin = (first + offset) % binCount
            if counts[bin] == 0 {
                if start < 0 { start = bin }
            } else if start >= 0 {
                runs.append(Run(start: start, length: (bin - start + binCount) % binCount))
                start = -1
            }
        }
        return runs
    }

    /// The ranges of the runs longer than the interpolation limit, in azimuth order.
    private func describe(_ runs: [Run]) -> [AzimuthRange] {
        if recordedCount == 0 { return [.full] }
        return runs.filter { $0.length > configuration.maximumInterpolatedGap }
            .map { AzimuthRange(start: Double($0.start) - 0.5, length: Double($0.length)) }
            .sorted { $0.start < $1.start }
    }
}
