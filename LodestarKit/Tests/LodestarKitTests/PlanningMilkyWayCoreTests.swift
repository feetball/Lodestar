import XCTest
@testable import LodestarKit

/// When the core of the Milky Way can be photographed: June against December, a New Moon against a
/// Full Moon, and the planner's answers against the root finder and fresh sky frames.
final class PlanningMilkyWayCoreTests: XCTestCase {
    private typealias Support = PlanningTestSupport
    private typealias Sets = NightPlanner.IntervalSet

    private let boulder = Support.boulder
    /// 33.9° S on the longitude of Sydney, a latitude where the core passes almost through the zenith.
    private let southern = Support.Site(name: "33.9° S", latitude: -33.9, longitude: 151.2,
                                        timeZoneIdentifier: "Australia/Sydney")

    private func coreAltitude(_ date: Date, _ observer: Observer) -> Double {
        SkyFrame(date: date, observer: observer)
            .horizontal(j2000: MilkyWayCoreVisibility.galacticCentre, refraction: false).altitude
    }

    // MARK: The target

    func testTheCoreIsSagittariusAStar() {
        let core = MilkyWayCoreVisibility.galacticCentre
        XCTAssertEqual(core.rightAscensionHours, 17 + 45.0 / 60 + 40.04 / 3_600, accuracy: 1e-9)
        XCTAssertEqual(core.declination, -(29 + 28.1 / 3_600), accuracy: 1e-9)
        XCTAssertEqual(MilkyWayCoreVisibility.minimumAltitude, 10)
    }

    // MARK: June against December

    func testJuneNightShowsTheCoreAllNightAtFortyNorth() throws {
        // New Moon at 20:54 MDT on 14 June 2026: no moonlight.
        let summary = try Support.summary(boulder, 2026, 6, 14)
        let core = summary.milkyWayCore
        let night = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        XCTAssertEqual(summary.astronomicalDarknessIntervals.count, 1)
        Support.assertIntervals(core.visibleIntervals, [night], accuracy: 1, "the core stays above 10° all night")
        Support.assertIntervals(core.moonFreeVisibleIntervals, [night], accuracy: 1)

        let transit = try XCTUnwrap(core.riseTransitSet.transit)
        XCTAssertTrue(night.contains(transit), "the core crosses the meridian in the dark")
        XCTAssertEqual(core.riseTransitSet.circumstance, .normal)
        XCTAssertLessThan(try XCTUnwrap(core.riseTransitSet.rise), night.start)
        XCTAssertGreaterThan(try XCTUnwrap(core.riseTransitSet.set), night.end)
        XCTAssertEqual(try XCTUnwrap(core.bestTime).timeIntervalSince(transit), 0, accuracy: 3)
        // Culmination altitude 90° − (40° − (−29.0°)) = 21.0° due south.
        XCTAssertEqual(try XCTUnwrap(core.maxAltitude), 21.0, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(core.maxAltitude), try XCTUnwrap(core.riseTransitSet.transitAltitude), accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(core.bestAzimuth), 180, accuracy: 0.1)
    }

    func testDecemberNightHidesTheCoreAtFortyNorth() throws {
        // In December the Sun is in Sagittarius: the core is up only by day.
        let summary = try Support.summary(boulder, 2026, 12, 14)
        let core = summary.milkyWayCore
        XCTAssertTrue(summary.hasAstronomicalDarkness)
        XCTAssertTrue(core.visibleIntervals.isEmpty)
        XCTAssertTrue(core.moonFreeVisibleIntervals.isEmpty)
        XCTAssertNil(core.bestTime)
        XCTAssertNil(core.maxAltitude)
        XCTAssertNil(core.bestAzimuth)
        XCTAssertEqual(core.riseTransitSet.circumstance, .normal)
        XCTAssertLessThan(try XCTUnwrap(core.riseTransitSet.set), try XCTUnwrap(summary.twilight.astronomicalDusk))
        XCTAssertGreaterThan(try XCTUnwrap(core.riseTransitSet.rise), try XCTUnwrap(summary.twilight.astronomicalDawn))
    }

    func testJuneNightShowsTheCoreNearTheZenithAtThirtyFourSouth() throws {
        let summary = try Support.summary(southern, 2026, 6, 14)       // New Moon on 15 June
        let core = summary.milkyWayCore
        let night = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        XCTAssertGreaterThan(summary.astronomicalDarkHours, 11)
        Support.assertIntervals(core.visibleIntervals, [night], accuracy: 1)
        Support.assertIntervals(core.moonFreeVisibleIntervals, [night], accuracy: 1)

        let transit = try XCTUnwrap(core.riseTransitSet.transit)
        XCTAssertTrue(night.contains(transit))
        XCTAssertEqual(try XCTUnwrap(core.bestTime).timeIntervalSince(transit), 0, accuracy: 3)
        // 90° − |−33.9° − (−29.0°)| = 85.1°, so far north of the zenith that the azimuth is almost exact.
        XCTAssertEqual(try XCTUnwrap(core.maxAltitude), 85.1, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(core.maxAltitude), try XCTUnwrap(core.riseTransitSet.transitAltitude), accuracy: 1e-3)
        let azimuth = try XCTUnwrap(core.bestAzimuth)
        XCTAssertLessThan(min(azimuth, 360 - azimuth), 0.2, "due north of the zenith")
    }

    func testDecemberNightHidesTheCoreAtThirtyFourSouth() throws {
        let summary = try Support.summary(southern, 2026, 12, 14)
        let core = summary.milkyWayCore
        XCTAssertTrue(summary.hasAstronomicalDarkness)
        XCTAssertTrue(core.visibleIntervals.isEmpty)
        XCTAssertTrue(core.moonFreeVisibleIntervals.isEmpty)
        XCTAssertNil(core.bestTime)
        XCTAssertNil(core.maxAltitude)
        XCTAssertLessThan(try XCTUnwrap(core.riseTransitSet.set), try XCTUnwrap(summary.twilight.astronomicalDusk))
        XCTAssertGreaterThan(try XCTUnwrap(core.riseTransitSet.rise), try XCTUnwrap(summary.twilight.astronomicalDawn))
    }

    func testTheCoreNeverReachesTenDegreesFarNorth() throws {
        // Culminates at 90° − (60° + 29°) = 1° at 60° N.
        let helsinki = Support.Site(name: "60° N", latitude: 60, longitude: 25, timeZoneIdentifier: "Europe/Helsinki")
        let summary = try Support.summary(helsinki, 2026, 10, 1)
        XCTAssertTrue(summary.hasAstronomicalDarkness)
        XCTAssertTrue(summary.milkyWayCore.visibleIntervals.isEmpty)
        XCTAssertNil(summary.milkyWayCore.bestTime)
    }

    func testWhiteNightsLeaveNoDarknessForTheCore() throws {
        // London on the solstice: the Sun stays above −15.1°, so astronomical darkness never comes.
        let summary = try Support.summary(Support.london, 2026, 6, 21)
        let core = summary.milkyWayCore
        XCTAssertFalse(summary.hasAstronomicalDarkness)
        XCTAssertTrue(core.visibleIntervals.isEmpty)
        XCTAssertTrue(core.moonFreeVisibleIntervals.isEmpty)
        XCTAssertNil(core.bestTime)
        XCTAssertNil(core.maxAltitude)
        XCTAssertNil(core.bestAzimuth)
        XCTAssertNotNil(core.riseTransitSet.transit)
    }

    // MARK: Moonlight

    func testBestTimeWaitsForMoonsetWhenTheMoonLightsTheMeridianPassage() throws {
        // 21 June 2026, a day after first quarter: the Moon sets at 00:58 MDT, after the core's passage
        // at 00:47 and 2.5 hours before dawn. The moon-free hours begin with the core already descending.
        let summary = try Support.summary(boulder, 2026, 6, 21)
        let core = summary.milkyWayCore
        let night = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        let moonSet = try XCTUnwrap(summary.moon.riseTransitSet.set)
        let transit = try XCTUnwrap(core.riseTransitSet.transit)
        XCTAssertLessThan(transit, moonSet)
        Support.assertIntervals(core.visibleIntervals, [night], accuracy: 1)
        Support.assertIntervals(core.moonFreeVisibleIntervals, [DateInterval(start: moonSet, end: night.end)], accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(core.bestTime).timeIntervalSince(moonSet), 0, accuracy: 3,
                       "the highest the core gets once the sky is moon-free")
        XCTAssertLessThan(try XCTUnwrap(core.maxAltitude), try XCTUnwrap(core.riseTransitSet.transitAltitude))
        XCTAssertEqual(try XCTUnwrap(core.maxAltitude), 20.93, accuracy: 0.05)
    }

    func testFullMoonNightHasNoMoonFreeCoreButStillReportsTheBestTime() throws {
        // Full Moon at 17:57 MDT on 29 June 2026.
        let summary = try Support.summary(boulder, 2026, 6, 29)
        let core = summary.milkyWayCore
        let night = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        XCTAssertEqual(summary.moon.phase.name, .fullMoon)
        XCTAssertTrue(summary.darknessIntervals.isEmpty)
        XCTAssertTrue(core.moonFreeVisibleIntervals.isEmpty)
        // The core is above 10° from dusk until a little before dawn.
        let window = try XCTUnwrap(core.visibleIntervals.first)
        XCTAssertEqual(core.visibleIntervals.count, 1)
        XCTAssertEqual(window.start.timeIntervalSince(night.start), 0, accuracy: 1)
        XCTAssertLessThan(window.end, night.end)
        XCTAssertEqual(coreAltitude(window.end, summary.observer), 10, accuracy: 0.01)
        let transit = try XCTUnwrap(core.riseTransitSet.transit)
        XCTAssertEqual(try XCTUnwrap(core.bestTime).timeIntervalSince(transit), 0, accuracy: 3,
                       "without a moon-free window the best time comes from the whole dark time")
        XCTAssertEqual(try XCTUnwrap(core.maxAltitude), 21.0, accuracy: 0.05)
    }

    // MARK: Partial windows

    func testRisingCoreIsVisibleOnlyFromTenDegreesUntilDawn() throws {
        // 16 April 2026 (New Moon): the core rises in the small hours and clears 10° shortly before dawn.
        let summary = try Support.summary(boulder, 2026, 4, 16)
        let core = summary.milkyWayCore
        let dawn = try XCTUnwrap(summary.twilight.astronomicalDawn)
        let window = try XCTUnwrap(core.visibleIntervals.first)
        XCTAssertEqual(core.visibleIntervals.count, 1)
        XCTAssertEqual(window.end.timeIntervalSince(dawn), 0, accuracy: 1)
        XCTAssertGreaterThan(window.start, try XCTUnwrap(summary.twilight.astronomicalDusk))
        XCTAssertLessThan(window.duration, 3 * 3_600)
        XCTAssertEqual(coreAltitude(window.start, summary.observer), 10, accuracy: 0.01)
        XCTAssertLessThan(coreAltitude(window.start.addingTimeInterval(-60), summary.observer), 10)
        XCTAssertGreaterThan(coreAltitude(window.start.addingTimeInterval(60), summary.observer), 10)
        let best = try XCTUnwrap(core.bestTime)
        XCTAssertEqual(best.timeIntervalSince(dawn), 0, accuracy: 3, "still climbing when the sky brightens")
        XCTAssertEqual(coreAltitude(best, summary.observer), try XCTUnwrap(core.maxAltitude), accuracy: 1e-4)
    }

    func testSettingCoreIsVisibleFromDuskUntilItSinksBelowTenDegrees() throws {
        // 10 September 2026 (New Moon): the core is high in the south-west after dusk and sets before midnight.
        let summary = try Support.summary(boulder, 2026, 9, 10)
        let core = summary.milkyWayCore
        let dusk = try XCTUnwrap(summary.twilight.astronomicalDusk)
        let window = try XCTUnwrap(core.visibleIntervals.first)
        XCTAssertEqual(core.visibleIntervals.count, 1)
        XCTAssertEqual(window.start.timeIntervalSince(dusk), 0, accuracy: 1)
        XCTAssertLessThan(window.end, try XCTUnwrap(summary.twilight.astronomicalDawn))
        XCTAssertEqual(coreAltitude(window.end, summary.observer), 10, accuracy: 0.01)
        XCTAssertGreaterThan(coreAltitude(window.end.addingTimeInterval(-60), summary.observer), 10)
        XCTAssertLessThan(coreAltitude(window.end.addingTimeInterval(60), summary.observer), 10)
        XCTAssertEqual(try XCTUnwrap(core.bestTime).timeIntervalSince(dusk), 0, accuracy: 3,
                       "already past the meridian at dusk, so the best moment is the first")
    }

    // MARK: Agreement with independent calculations

    /// The visible stretches equal the root finder's stretches above 10°, cut to the dark time.
    func testVisibleIntervalsMatchTheRootFinderEverywhere() throws {
        let sites = [boulder, southern, Support.quito, Support.paranal, Support.london]
        for site in sites {
            for (month, day) in [(1, 15), (3, 20), (5, 10), (7, 25), (9, 10), (11, 5)] {
                let summary = try Support.summary(site, 2026, month, day)
                let label = "\(site.name) 2026-\(month)-\(day)"
                let observer = site.observer
                let expected = Sets.intersection(
                    Support.intervals(above: MilkyWayCoreVisibility.minimumAltitude, within: summary.night,
                                      altitude: { self.coreAltitude($0, observer) }),
                    summary.astronomicalDarknessIntervals)
                Support.assertIntervals(summary.milkyWayCore.visibleIntervals, expected, accuracy: 1, label)
            }
        }
    }

    /// Structural properties of the core's answer, checked at a grid of places and dates against fresh
    /// frames: the dark time is split exactly into "core high enough" and "core too low", the moon-free
    /// stretches are the part without moonlight, and the best moment is the highest one in the preferred
    /// stretches.
    func testAnswersAreConsistentWithDirectAltitudes() throws {
        let sites = [boulder, southern, Support.quito, Support.paranal, Support.london, Support.tromso]
        var nightsWithTheCore = 0, nightsWithoutIt = 0
        for site in sites {
            for (month, day) in [(2, 10), (4, 16), (6, 14), (8, 20), (10, 25), (12, 14)] {
                let summary = try Support.summary(site, 2026, month, day)
                let label = "\(site.name) 2026-\(month)-\(day)"
                let observer = site.observer
                let core = summary.milkyWayCore
                if core.visibleIntervals.isEmpty { nightsWithoutIt += 1 } else { nightsWithTheCore += 1 }

                XCTAssertEqual(Sets.intersection(core.visibleIntervals, summary.astronomicalDarknessIntervals),
                               core.visibleIntervals, label)
                XCTAssertEqual(core.moonFreeVisibleIntervals,
                               Sets.intersection(core.visibleIntervals, summary.darknessIntervals), label)
                let darkEdges = summary.astronomicalDarknessIntervals.flatMap { [$0.start, $0.end] }
                for interval in core.visibleIntervals {
                    XCTAssertGreaterThanOrEqual(coreAltitude(interval.start.addingTimeInterval(interval.duration / 2),
                                                             observer), 10, label)
                    // Each end is where the dark time begins or ends, or else where the core crosses 10°.
                    for edge in [interval.start, interval.end] where darkEdges.allSatisfy({ abs($0.timeIntervalSince(edge)) > 1 }) {
                        XCTAssertEqual(coreAltitude(edge, observer), 10, accuracy: 0.01, "\(label): an edge at 10°")
                    }
                }
                for gap in Sets.subtracting(core.visibleIntervals, from: summary.astronomicalDarknessIntervals) {
                    XCTAssertLessThan(coreAltitude(gap.start.addingTimeInterval(gap.duration / 2), observer), 10, label)
                }

                let preferred = core.moonFreeVisibleIntervals.isEmpty ? core.visibleIntervals : core.moonFreeVisibleIntervals
                guard let best = core.bestTime, let maxAltitude = core.maxAltitude else {
                    XCTAssertTrue(core.visibleIntervals.isEmpty, label)
                    XCTAssertNil(core.bestTime, label)
                    XCTAssertNil(core.maxAltitude, label)
                    XCTAssertNil(core.bestAzimuth, label)
                    continue
                }
                XCTAssertTrue(preferred.contains { $0.start <= best && best <= $0.end }, "\(label): best time in the window")
                XCTAssertEqual(coreAltitude(best, observer), maxAltitude, accuracy: 1e-4, label)
                let frame = SkyFrame(date: best, observer: observer)
                XCTAssertEqual(frame.horizontal(j2000: MilkyWayCoreVisibility.galacticCentre, refraction: false).azimuth,
                               try XCTUnwrap(core.bestAzimuth), accuracy: 1e-6, label)
                for interval in preferred {
                    var date = interval.start
                    while date <= interval.end {
                        XCTAssertLessThanOrEqual(coreAltitude(date, observer), maxAltitude + 1e-3, label)
                        date = date.addingTimeInterval(300)
                    }
                }
            }
        }
        XCTAssertGreaterThan(nightsWithTheCore, 12, "the grid must include many nights with a visible core")
        XCTAssertGreaterThan(nightsWithoutIt, 8, "and many without")
    }

    func testRiseTransitSetIsTheRootFindersForTheNight() throws {
        for site in [boulder, southern, Support.london] {
            let summary = try Support.summary(site, 2026, 8, 12)
            XCTAssertEqual(summary.milkyWayCore.riseTransitSet,
                           RiseSetCalculator.riseTransitSet(forJ2000: MilkyWayCoreVisibility.galacticCentre,
                                                            observer: site.observer, within: summary.night),
                           site.name)
        }
    }
}
