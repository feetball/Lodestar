import Foundation

extension NightPlanner {
    /// A `SkyFrame` for every sample instant across a set of dark intervals, shared by all the targets
    /// evaluated against those intervals.
    ///
    /// Building a frame costs far more than projecting one target with it, so a list of targets is
    /// evaluated by building the frames once and sampling each target at every frame.
    struct DarknessSampler {
        /// The longest allowed gap between samples, in seconds.
        static let maximumStep: TimeInterval = 600
        /// The largest number of gaps in one dark interval; longer intervals are sampled more coarsely.
        static let maximumGapCount = 10_000

        /// One dark interval with its sample frames, evenly spaced from the start to the end.
        struct Stretch {
            let interval: DateInterval
            let step: TimeInterval
            let frames: [SkyFrame]
        }

        let stretches: [Stretch]

        /// Prepares the frames for `intervals`, which are sorted and merged first.
        init(observer: Observer, intervals: [DateInterval]) {
            stretches = IntervalSet.normalized(intervals).map { interval in
                let wanted = (interval.duration / Self.maximumStep).rounded(.up)
                let gapCount = Int(min(wanted, Double(Self.maximumGapCount)))
                let step = interval.duration / Double(gapCount)
                let frames = (0...gapCount).map { index in
                    let date = index == gapCount
                        ? interval.end : interval.start.addingTimeInterval(Double(index) * step)
                    return SkyFrame(date: date, observer: observer)
                }
                return Stretch(interval: interval, step: step, frames: frames)
            }
        }

        /// Samples a target by the sine of its geometric altitude at each frame. Values that are not
        /// finite count as far below the horizon.
        func profile(ofSine sine: (SkyFrame) -> Double) -> DarknessProfile {
            DarknessProfile(stretches: stretches.map { stretch in
                let sines = stretch.frames.map { frame -> Double in
                    let value = sine(frame)
                    return value.isFinite ? AstroMath.clamp(value, -1, 1) : -1
                }
                return DarknessProfile.Stretch(interval: stretch.interval,
                                               altitude: AltitudeProfile(step: stretch.step, sines: sines))
            })
        }

        /// Samples the Sun, the Moon or a planet by the sine of its geometric topocentric altitude.
        func profile(of body: SolarSystemBody) -> DarknessProfile {
            profile { AstroMath.sinDeg($0.horizontal(of: body, refraction: false).altitude) }
        }
    }

    /// The altitude of one target across a set of dark intervals.
    struct DarknessProfile {
        /// The profile of one dark interval.
        struct Stretch {
            let interval: DateInterval
            let altitude: AltitudeProfile
        }

        let stretches: [Stretch]

        /// The dark intervals the profile covers.
        var darkness: [DateInterval] { stretches.map(\.interval) }

        /// The highest point of the target inside `queries`, which may be the dark intervals themselves
        /// or parts of them; `nil` when `queries` overlaps none of them.
        func maximum(within queries: [DateInterval]) -> (date: Date, sine: Double)? {
            var best: (date: Date, sine: Double)?
            for stretch in stretches {
                for query in queries {
                    let start = max(query.start, stretch.interval.start)
                    let end = min(query.end, stretch.interval.end)
                    guard end >= start else { continue }
                    let peak = stretch.altitude.maximum(from: start.timeIntervalSince(stretch.interval.start),
                                                        to: end.timeIntervalSince(stretch.interval.start))
                    if let current = best, current.sine >= peak.sine { continue }
                    best = (stretch.interval.start.addingTimeInterval(peak.offset), peak.sine)
                }
            }
            return best
        }

        /// The parts of the dark intervals where the sine of the altitude is at least `threshold`.
        func intervals(atOrAbove threshold: Double) -> [DateInterval] {
            IntervalSet.normalized(stretches.flatMap { stretch in
                stretch.altitude.offsets(atOrAbove: threshold).map { span in
                    DateInterval(start: stretch.interval.start.addingTimeInterval(span.start),
                                 end: stretch.interval.start.addingTimeInterval(span.end))
                }
            })
        }
    }
}
