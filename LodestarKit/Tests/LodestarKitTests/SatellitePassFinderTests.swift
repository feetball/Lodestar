import XCTest
@testable import LodestarKit

/// Properties of `SatellitePassFinder`; the times against Skyfield are in `SatelliteReferenceTests`.
final class SatellitePassFinderTests: XCTestCase {
    private typealias Support = SatelliteTestSupport
    private let boulder = SatelliteTestSupport.boulder
    private let start = SatelliteTestSupport.iso("2026-10-18T04:00:00Z")
    private var threeDays: DateInterval { DateInterval(start: start, duration: 3 * 86_400.0) }

    private func satellites() throws -> [String: Satellite] { try Support.referenceSatellites() }
    private func iss() throws -> Satellite { try XCTUnwrap(satellites()["iss"]) }

    private func issPasses() throws -> [SatellitePass] {
        SatellitePassFinder(observer: boulder, interval: threeDays).passes(of: try iss())
    }

    func testPassesAreOrderedAndInternallyConsistent() throws {
        let satellite = try iss()
        let passes = try issPasses()
        XCTAssertEqual(passes.count, 18)
        var previousSet = start
        for pass in passes {
            XCTAssertGreaterThanOrEqual(pass.rise.date, previousSet)
            XCTAssertTrue(pass.rise.date < pass.culmination.date && pass.culmination.date < pass.set.date)
            previousSet = pass.set.date
            // Rise and set are where the altitude equals the threshold.
            XCTAssertEqual(pass.rise.altitude, 10.0, accuracy: 0.01)
            XCTAssertEqual(pass.set.altitude, 10.0, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(pass.culmination.altitude, 10.0)
            XCTAssertEqual(pass.set.date.timeIntervalSince(pass.rise.date), pass.duration, accuracy: 1e-9)
            XCTAssertEqual(pass.interval, DateInterval(start: pass.rise.date, end: pass.set.date))
            XCTAssertTrue((60.0...700.0).contains(pass.duration), "duration \(pass.duration)")
            XCTAssertTrue(!pass.isRiseCut && !pass.isSetCut)
            // No point of the pass is higher than the culmination.
            var offset = 0.0
            while offset <= pass.duration {
                let altitude = try XCTUnwrap(satellite.look(at: pass.rise.date.addingTimeInterval(offset), observer: boulder)).altitude
                XCTAssertLessThanOrEqual(altitude, pass.culmination.altitude + 1e-6)
                XCTAssertGreaterThanOrEqual(altitude, 10.0 - 0.01)
                offset += 10.0
            }
            // Visible parts lie inside the pass, in order, and the satellite is lit and the sky dark there.
            var cursor = pass.rise.date
            for part in pass.visibleIntervals {
                XCTAssertTrue(part.start >= cursor && part.end <= pass.set.date && part.duration > 0.0)
                cursor = part.end
                let inside = try XCTUnwrap(satellite.look(at: part.start.addingTimeInterval(part.duration / 2), observer: boulder))
                XCTAssertTrue(inside.isVisible())
            }
            XCTAssertEqual(pass.isVisible, !pass.visibleIntervals.isEmpty)
            XCTAssertEqual(pass.visibleSpan?.start, pass.visibleIntervals.first?.start)
            XCTAssertEqual(pass.visibleSpan?.end, pass.visibleIntervals.last?.end)
        }
        XCTAssertEqual(passes.filter(\.isVisible).count, 4)
        XCTAssertTrue(passes.allSatisfy { $0.brightest == nil || $0.isVisible })
    }

    func testTheBrightestPointOfAVisiblePassIsTheBrightestSample() throws {
        let satellite = try iss()
        let visible = try XCTUnwrap(try issPasses().first { $0.isVisible })
        let brightest = try XCTUnwrap(visible.brightest)
        XCTAssertTrue(visible.visibleIntervals.contains { brightest.date >= $0.start && brightest.date <= $0.end })
        let magnitude = try XCTUnwrap(brightest.magnitude)
        for part in visible.visibleIntervals {
            var offset = 0.0
            while offset <= part.duration {
                let look = try XCTUnwrap(satellite.look(at: part.start.addingTimeInterval(offset), observer: boulder))
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(look.magnitude), magnitude - 1e-6, "magnitude \(String(describing: look.magnitude)) is brighter than \(magnitude)")
                offset += 1.0
            }
        }
        XCTAssertTrue((-5.5...(-0.5)).contains(magnitude), "magnitude \(magnitude)")
        // A satellite with an unknown intrinsic magnitude has no brightest point.
        let starlink = SatellitePassFinder(observer: boulder, interval: threeDays).passes(of: try XCTUnwrap(satellites()["starlink"])).filter(\.isVisible)
        XCTAssertTrue(!starlink.isEmpty && starlink.allSatisfy { $0.brightest == nil })
    }

    func testAHigherThresholdGivesShorterPassesInsideTheLowerOnes() throws {
        let satellite = try iss()
        let low = SatellitePassFinder(observer: boulder, interval: threeDays, minimumAltitude: 10.0).passes(of: satellite)
        let high = SatellitePassFinder(observer: boulder, interval: threeDays, minimumAltitude: 40.0).passes(of: satellite)
        XCTAssertTrue(high.count >= 1 && high.count < low.count)
        for pass in high {
            let containing = low.filter { $0.rise.date <= pass.culmination.date && pass.culmination.date <= $0.set.date }
            XCTAssertEqual(containing.count, 1)
            let outer = try XCTUnwrap(containing.first)
            XCTAssertTrue(pass.rise.date > outer.rise.date && pass.set.date < outer.set.date)
            XCTAssertEqual(pass.culmination.altitude, outer.culmination.altitude, accuracy: 1e-3)
            XCTAssertEqual(pass.rise.altitude, 40.0, accuracy: 0.01)
        }
        // A threshold of 80 degrees leaves only a near-zenith pass or none.
        XCTAssertTrue(SatellitePassFinder(observer: boulder, interval: threeDays, minimumAltitude: 80.0).passes(of: satellite).isEmpty)
        // A negative threshold lengthens the pass.
        let horizon = SatellitePassFinder(observer: boulder, interval: threeDays, minimumAltitude: 0.0).passes(of: satellite)
        XCTAssertGreaterThanOrEqual(horizon.count, low.count)
        XCTAssertEqual(horizon[0].rise.altitude, 0.0, accuracy: 0.01)
    }

    func testASubWindowGivesTheSamePassesCutAtItsEdges() throws {
        let satellite = try iss()
        let full = try issPasses()
        let target = full[3]
        // A window that starts in the middle of a pass and ends in the middle of the next one.
        let next = full[4]
        let begin = target.rise.date.addingTimeInterval(target.duration / 2)
        let finish = next.rise.date.addingTimeInterval(next.duration / 3)
        let sub = SatellitePassFinder(observer: boulder, interval: DateInterval(start: begin, end: finish)).passes(of: satellite)
        XCTAssertEqual(sub.count, 2)
        XCTAssertTrue(sub[0].isRiseCut && !sub[0].isSetCut)
        XCTAssertTrue(!sub[1].isRiseCut && sub[1].isSetCut)
        XCTAssertEqual(sub[0].rise.date, begin)
        XCTAssertEqual(sub[1].set.date.timeIntervalSince1970, finish.timeIntervalSince1970, accuracy: 1e-6)
        XCTAssertEqual(sub[0].set.date.timeIntervalSince1970, target.set.date.timeIntervalSince1970, accuracy: 0.02)
        XCTAssertEqual(sub[1].rise.date.timeIntervalSince1970, next.rise.date.timeIntervalSince1970, accuracy: 0.02)
        // The rising part of the second pass has the full pass's first half.
        XCTAssertEqual(sub[1].rise.azimuth, next.rise.azimuth, accuracy: 0.01)
        XCTAssertLessThanOrEqual(sub[1].culmination.altitude, next.culmination.altitude + 1e-6)
        // A window that holds the whole culmination of the pass reports it.
        let around = SatellitePassFinder(
            observer: boulder, interval: DateInterval(start: target.rise.date.addingTimeInterval(-60.0), duration: target.duration + 120.0)
        ).passes(of: satellite)
        XCTAssertEqual(around.count, 1)
        XCTAssertEqual(around[0].culmination.altitude, target.culmination.altitude, accuracy: 1e-3)
        XCTAssertEqual(around[0].culmination.date.timeIntervalSince1970, target.culmination.date.timeIntervalSince1970, accuracy: 0.1)
    }

    func testAGeostationarySatelliteOverTheObserverIsOnePassCutAtBothEnds() throws {
        let epoch = Support.iso("2026-10-18T00:00:00Z")
        let geo = Satellite(elements: try Support.geostationary(longitude: 30.0, epoch: epoch))
        let equator = Support.observer(0.0, 30.0)
        let passes = SatellitePassFinder(observer: equator, interval: DateInterval(start: epoch.addingTimeInterval(3600.0), duration: 2 * 86_400.0)).passes(of: geo)
        XCTAssertEqual(passes.count, 1)
        XCTAssertTrue(passes[0].isRiseCut && passes[0].isSetCut)
        XCTAssertEqual(passes[0].rise.date, epoch.addingTimeInterval(3600.0))
        XCTAssertEqual(passes[0].set.date.timeIntervalSince1970, epoch.addingTimeInterval(3600.0 + 2 * 86_400.0).timeIntervalSince1970, accuracy: 1e-6)
        XCTAssertGreaterThan(passes[0].culmination.altitude, 85.0, "altitude \(passes[0].culmination.altitude)")
        // From the other side of the Earth it never rises.
        XCTAssertTrue(SatellitePassFinder(observer: Support.observer(0.0, -150.0), interval: DateInterval(start: epoch, duration: 86_400.0)).passes(of: geo).isEmpty)
    }

    func testASatelliteThatNeverReachesTheObserver() throws {
        // The ISS (51.6 degrees inclination) never gets 10 degrees above the horizon of the North Pole.
        XCTAssertTrue(SatellitePassFinder(observer: Support.observer(89.9, 0.0), interval: threeDays).passes(of: try iss()).isEmpty)
        // The polar-orbiting ENVISAT does, many times a day.
        let polar = SatellitePassFinder(observer: Support.observer(89.9, 0.0), interval: DateInterval(start: start, duration: 86_400.0))
            .passes(of: try XCTUnwrap(satellites()["polar"]))
        XCTAssertGreaterThanOrEqual(polar.count, 10)
    }

    func testADecayedSatelliteHasNoPasses() throws {
        let decayed = try OrbitalElements(
            catalogNumber: 28872, epoch: Support.iso("2005-11-29T00:00:00Z"), meanMotion: 16.46015938, eccentricity: 0.0303955,
            inclination: 96.4736, rightAscensionOfAscendingNode: 157.9986, argumentOfPericenter: 244.0492,
            meanAnomaly: 110.6523, bstar: 0.24476e-3, meanMotionDot: 0.25992681
        )
        let window = DateInterval(start: Support.iso("2005-12-01T00:00:00Z"), duration: 3 * 86_400.0)
        XCTAssertTrue(SatellitePassFinder(observer: boulder, interval: window).passes(of: Satellite(elements: decayed)).isEmpty)
        // Far from the epoch SGP4 refuses altogether.
        XCTAssertTrue(SatellitePassFinder(observer: boulder, interval: DateInterval(start: Support.iso("2050-01-01T00:00:00Z"), duration: 86_400.0)).passes(of: try iss()).isEmpty)
    }

    func testInvalidSettingsFallBackToDefaults() throws {
        let satellite = try iss()
        let finder = SatellitePassFinder(observer: boulder, interval: threeDays, minimumAltitude: .nan, darknessSunAltitude: -6.0)
        XCTAssertEqual(finder.passes(of: satellite).count, try issPasses().count)
        XCTAssertEqual(SatellitePassFinder.defaultMinimumAltitude, 10.0, accuracy: 0.0)
        XCTAssertEqual(SatellitePassFinder.defaultDarknessSunAltitude, -6.0, accuracy: 0.0)
        // A zero-length window has no passes, a huge window is cut at 30 days.
        XCTAssertTrue(SatellitePassFinder(observer: boulder, interval: DateInterval(start: start, duration: 0.0)).passes(of: satellite).isEmpty)
        let month = SatellitePassFinder(observer: boulder, interval: DateInterval(start: start, duration: 400 * 86_400.0)).passes(of: satellite)
        let last = try XCTUnwrap(month.last)
        XCTAssertLessThan(last.rise.date, start.addingTimeInterval(SatellitePassFinder.maximumWindowDays * 86_400.0 + 1))
        XCTAssertGreaterThan(month.count, 100)
        XCTAssertTrue(last.isSetCut || last.set.date < start.addingTimeInterval(30 * 86_400.0))
    }

    func testTheDarknessThresholdDecidesWhatIsVisible() throws {
        let satellite = try iss()
        func visibleTime(_ darkness: Double) -> Double {
            SatellitePassFinder(observer: boulder, interval: threeDays, darknessSunAltitude: darkness).passes(of: satellite)
                .reduce(0.0) { $0 + $1.visibleIntervals.reduce(0.0) { $0 + $1.duration } }
        }
        let civil = visibleTime(-6.0)
        let astronomical = visibleTime(-18.0)
        let anytime = visibleTime(90.0)
        XCTAssertTrue(astronomical <= civil && civil < anytime)
        // With no darkness requirement the visible time is the sunlit time of the passes.
        for pass in SatellitePassFinder(observer: boulder, interval: threeDays, darknessSunAltitude: 90.0).passes(of: satellite) {
            for part in pass.visibleIntervals {
                XCTAssertTrue(try XCTUnwrap(satellite.look(at: part.start.addingTimeInterval(part.duration / 2), observer: boulder)).isSunlit)
            }
        }
    }

    func testOneFinderServesManyThreads() throws {
        let all = Array(try satellites().values)
        let finder = SatellitePassFinder(observer: boulder, interval: threeDays)
        let expected = all.map { finder.passes(of: $0) }
        let rounds = 8
        let results = UnsafeMutableBufferPointer<[[SatellitePass]]>.allocate(capacity: rounds)
        results.initialize(repeating: [])
        defer { results.deallocate() }
        nonisolated(unsafe) let output = results
        DispatchQueue.concurrentPerform(iterations: rounds) { round in
            output[round] = all.map { finder.passes(of: $0) }
        }
        for round in 0..<rounds { XCTAssertEqual(results[round], expected) }
        XCTAssertTrue(expected.allSatisfy { $0.allSatisfy { abs($0.duration) >= 0.0 } })
    }

    func testPassesOfDeepSpaceOrbitsLastHours() throws {
        let sydney = Support.observer(-33.8688, 151.2093, 20.0)
        let window = DateInterval(start: start.addingTimeInterval(4 * 3600.0), duration: 3 * 86_400.0)
        let molniya = SatellitePassFinder(observer: sydney, interval: window).passes(of: try XCTUnwrap(satellites()["molniya"]))
        XCTAssertEqual(molniya.count, 4)
        // Three long passes of an hour and a half and a graze of six minutes that peaks at 10.3 degrees.
        XCTAssertEqual(molniya.map { ($0.duration / 36.0).rounded() / 100.0 }, [1.54, 1.61, 0.10, 1.67])
        XCTAssertEqual(molniya[2].culmination.altitude, 10.3, accuracy: 0.05)
        XCTAssertNil(molniya.first { $0.culmination.altitude < 10.0 })
        // The two passes of the geosynchronous TDRS 7 last sixteen hours each.
        let geo = SatellitePassFinder(observer: sydney, interval: window).passes(of: try XCTUnwrap(satellites()["geo"]))
        XCTAssertEqual(geo.map { $0.isRiseCut || $0.isSetCut }, [true, false, false, true])
        XCTAssertEqual(geo.filter { !$0.isRiseCut && !$0.isSetCut }.map { ($0.duration / 36.0).rounded() / 100.0 }, [16.13, 16.14])
    }
}
