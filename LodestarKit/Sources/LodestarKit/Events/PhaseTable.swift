import Foundation

/// The new and full Moons of one search interval, computed once per run and shared by the finders that start from a
/// syzygy (special full Moons, lunar and solar eclipses).
///
/// The table covers `from` and `to` with a margin of two days on both sides so that an eclipse whose greatest phase
/// falls inside the interval is never missed.
struct PhaseTable {
    /// The instants of the new Moons in the table, in time order.
    let newMoons: [Date]
    /// The instants of the full Moons in the table, in time order.
    let fullMoons: [Date]

    init(from: Date, to: Date) {
        let start = from.addingTimeInterval(-2 * JulianDate.secondsPerDay)
        let days = to.timeIntervalSince(start) / JulianDate.secondsPerDay + 2
        let count = min(Int((days / 7).rounded(.up)) + 2, MoonPhaseCalculator.maximumPhaseCount)
        var news = [Date]()
        var fulls = [Date]()
        for phase in MoonPhaseCalculator.nextPhases(after: start, count: count) {
            switch phase.kind {
            case .newMoon: news.append(phase.date)
            case .fullMoon: fulls.append(phase.date)
            case .firstQuarter, .lastQuarter: break
            }
        }
        newMoons = news
        fullMoons = fulls
    }
}
