import Foundation

extension NightPlanner {
    /// Arithmetic on sets of time intervals.
    ///
    /// Every function accepts any intervals and returns intervals that are sorted, disjoint (touching
    /// intervals are joined), longer than zero seconds and between finite dates.
    enum IntervalSet {
        /// The union of `intervals` as sorted, disjoint intervals of positive length between finite dates.
        static func normalized(_ intervals: [DateInterval]) -> [DateInterval] {
            var result = [DateInterval]()
            for interval in intervals.filter(isUsable).sorted(by: { $0.start < $1.start }) {
                guard let last = result.last, interval.start <= last.end else {
                    result.append(interval)
                    continue
                }
                if interval.end > last.end {
                    result[result.count - 1] = DateInterval(start: last.start, end: interval.end)
                }
            }
            return result
        }

        /// Whether `interval` starts and ends at finite dates and is longer than zero seconds.
        private static func isUsable(_ interval: DateInterval) -> Bool {
            interval.start.timeIntervalSinceReferenceDate.isFinite
                && interval.end.timeIntervalSinceReferenceDate.isFinite && interval.duration > 0
        }

        /// The time covered by both `first` and `second`.
        static func intersection(_ first: [DateInterval], _ second: [DateInterval]) -> [DateInterval] {
            let first = normalized(first), second = normalized(second)
            var result = [DateInterval]()
            var i = 0, j = 0
            while i < first.count, j < second.count {
                let start = max(first[i].start, second[j].start)
                let end = min(first[i].end, second[j].end)
                if end > start { result.append(DateInterval(start: start, end: end)) }
                if first[i].end < second[j].end { i += 1 } else { j += 1 }
            }
            return result
        }

        /// The time covered by `base` but not by `removed`.
        static func subtracting(_ removed: [DateInterval], from base: [DateInterval]) -> [DateInterval] {
            let removed = normalized(removed)
            var result = [DateInterval]()
            for piece in normalized(base) {
                var cursor = piece.start
                for cut in removed where cut.end > cursor && cut.start < piece.end {
                    if cut.start > cursor { result.append(DateInterval(start: cursor, end: cut.start)) }
                    cursor = max(cursor, cut.end)
                }
                if cursor < piece.end { result.append(DateInterval(start: cursor, end: piece.end)) }
            }
            return result
        }

        /// The total length of `intervals` in seconds, counting overlapping time once.
        static func totalDuration(of intervals: [DateInterval]) -> TimeInterval {
            normalized(intervals).reduce(0) { $0 + $1.duration }
        }
    }
}
