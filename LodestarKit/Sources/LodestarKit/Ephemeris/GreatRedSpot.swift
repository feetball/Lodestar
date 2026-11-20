import Foundation

/// One crossing of Jupiter's central meridian by the Great Red Spot.
public struct GreatRedSpotTransit: Sendable, Hashable {
    /// The instant the spot is on the central meridian (System II longitude of the meridian equal to the spot's).
    public let date: Date
    /// The spot's System II longitude then, degrees, [0, 360).
    public let longitude: Double
    /// The stretch around `date` in which the spot is within 50 minutes (about 30° of longitude) of the meridian, so
    /// that it is clearly on the visible disc.
    public let wellPlaced: DateInterval

    public init(date: Date, longitude: Double, wellPlaced: DateInterval) {
        self.date = date
        self.longitude = longitude
        self.wellPlaced = wellPlaced
    }
}

/// The Great Red Spot, placed by its System II longitude.
///
/// The spot is not fixed: its longitude drifts by a few degrees a month and wanders. So the position is a longitude at
/// an `epoch` with a `driftPer30Days`, and `reference` is the one the kit ships; the apps let the user replace it.
///
/// The reference is Sky & Telescope's: its online tool "Transit Times of Jupiter's Great Red Spot"
/// (skyandtelescope.org/observing/interactive-sky-watching-tools/transit-times-of-jupiters-great-red-spot/) takes the
/// spot to be at System II longitude 91° on 2026 June 1 with a drift of 1.75° per month, "based on trends noted by
/// JUPOS". Other 2025 and 2026 sources agree within a few degrees: the BAA Jupiter Section's report no. 2 of 2025/26
/// has L2 = 77° on 2025 September 1 (S. Mizumoto, ALPO-Japan); the IMCCE JGRS service
/// (ssp.imcce.fr/webservices/vo-tools/jgrs, from JUPOS measurements) gives 103.5° at 2026 November 19 21:27 UT, where
/// this extrapolation has 101.0°: 2.5° (4 minutes of transit time) ahead of it.
public struct GreatRedSpot: Sendable, Hashable {
    /// The longitude of the reference spot in System II at `referenceEpoch`, degrees.
    public static let referenceLongitude = 91.0

    /// The day of `referenceLongitude`: 2026 June 1, 0h UT.
    public static let referenceEpoch = Date(timeIntervalSince1970: 1_780_272_000)

    /// The reference drift, degrees per 30 days (1.75° a month).
    public static let referenceDriftPer30Days = 1.75

    /// The spot Sky & Telescope's tool assumes for 2026; see the type's comment.
    ///
    /// This is one straight line from `referenceEpoch` (2026 June 1), used for every date, and it has no validity
    /// horizon: the real spot wanders, so the error grows with the distance from that day, and `transits(from:to:)`
    /// gives exact-looking times years later all the same. Refresh `referenceLongitude`, `referenceEpoch` and
    /// `referenceDriftPer30Days` from a current JUPOS-based source once a year.
    public static let reference = GreatRedSpot(
        normalized: referenceLongitude, epoch: referenceEpoch, driftPer30Days: referenceDriftPer30Days)

    /// How long before and after a transit the spot counts as well placed, in minutes.
    public static let wellPlacedMinutes = 50.0

    /// The longest interval, in days, that `transits(from:to:)` searches.
    public static let maximumSpanDays = 366.0

    /// The largest drift `init(longitude:epoch:driftPer30Days:)` accepts, degrees per 30 days either way.
    public static let maximumDriftPer30Days = 30.0

    /// The System II longitude at `epoch`, degrees, [0, 360).
    public let longitude: Double
    /// The instant the longitude is for.
    public let epoch: Date
    /// The spot's drift in System II longitude, degrees per 30 days (positive towards larger longitudes).
    public let driftPer30Days: Double

    /// The spot at `longitude` (any finite value; it is taken modulo 360) on `epoch`, drifting by `driftPer30Days`
    /// (finite, at most `maximumDriftPer30Days` either way); `nil` otherwise.
    public init?(longitude: Double, epoch: Date, driftPer30Days: Double = GreatRedSpot.referenceDriftPer30Days) {
        guard longitude.isFinite, driftPer30Days.isFinite, abs(driftPer30Days) <= Self.maximumDriftPer30Days,
              epoch.timeIntervalSinceReferenceDate.isFinite,
              epoch >= Date.distantPast, epoch <= Date.distantFuture else { return nil }
        self.init(normalized: AstroMath.normalizeDegrees(longitude), epoch: epoch, driftPer30Days: driftPer30Days)
    }

    private init(normalized longitude: Double, epoch: Date, driftPer30Days: Double) {
        self.longitude = longitude
        self.epoch = epoch
        self.driftPer30Days = driftPer30Days
    }

    /// The spot's System II longitude at `date`, degrees, [0, 360): the longitude at the epoch moved by the drift
    /// (a straight line; the real drift wanders by a degree or two around it).
    public func systemIILongitude(at date: Date) -> Double {
        AstroMath.normalizeDegrees(longitudeAt(ut: JulianDate(date: date).ut))
    }

    private func longitudeAt(ut: Double) -> Double {
        longitude + driftPer30Days / 30 * (ut - JulianDate(date: epoch).ut)
    }

    /// The crossings of the central meridian from `from` to `to` (both inclusive), in time order: about 2.4 a day.
    /// Intervals longer than `maximumSpanDays` are cut short; a reversed interval or one outside the years 1 to 4001
    /// gives nothing. Each transit is found by Newton steps on `JupiterPhysical.state(at:)`, accurate to the second for
    /// the given longitude. Cost: about 0.1 ms for a day.
    public func transits(from: Date, to: Date) -> [GreatRedSpotTransit] {
        let first = from.timeIntervalSinceReferenceDate
        let last = to.timeIntervalSinceReferenceDate
        guard first.isFinite, last.isFinite, first >= Date.distantPast.timeIntervalSinceReferenceDate,
              last <= Date.distantFuture.timeIntervalSinceReferenceDate, last >= first else { return [] }
        let fromUT = JulianDate(date: from).ut
        let toUT = min(JulianDate(date: to).ut, fromUT + Self.maximumSpanDays)
        let rate = JupiterPhysical.systemIIRate - driftPer30Days / 30
        let period = 360 / rate
        func offset(_ ut: Double) -> Double {
            AstroMath.normalizeSignedDegrees(JupiterPhysical.state(at: JulianDate(ut: ut)).systemIILongitude
                                             - longitudeAt(ut: ut))
        }
        func refine(_ guess: Double) -> Double {
            var ut = guess
            for _ in 0..<6 {
                let step = offset(ut) / rate
                ut -= step
                if abs(step) < 1e-8 { break }
            }
            return ut
        }
        var found = [GreatRedSpotTransit]()
        var ut = refine(fromUT)
        while ut < fromUT { ut = refine(ut + period) }
        let limit = Int((Self.maximumSpanDays / period).rounded(.up)) + 1
        while ut <= toUT, found.count < limit {
            let date = JulianDate(ut: ut).date
            found.append(GreatRedSpotTransit(
                date: date, longitude: AstroMath.normalizeDegrees(longitudeAt(ut: ut)),
                wellPlaced: DateInterval(start: date.addingTimeInterval(-Self.wellPlacedMinutes * 60),
                                         end: date.addingTimeInterval(Self.wellPlacedMinutes * 60))))
            ut = refine(ut + period)
        }
        return found
    }
}
