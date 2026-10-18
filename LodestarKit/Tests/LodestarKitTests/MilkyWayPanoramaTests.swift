import XCTest
@testable import LodestarKit

final class MilkyWayPanoramaTests: XCTestCase {
    private let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    private let paranal = Observer(location: GeographicLocation(latitude: -24.627, longitude: -70.404, elevation: 2635))
    private let denver = TimeZone(identifier: "America/Denver")!

    /// 2026-07-16 05:00 UTC, 23:00 in Colorado: the core stands in the south, 21° high.
    private let july = Date(timeIntervalSince1970: 1_784_178_000)

    /// Local noon on 2026-08-12 in Colorado: the night of the new moon.
    private let august = Date(timeIntervalSince1970: 1_786_557_600)

    /// Local noon on 2026-12-15 in Colorado: the core is up only by day.
    private let december = Date(timeIntervalSince1970: 1_797_361_200)

    // MARK: The arch

    func testArchIsTheUpperHalfOfTheGalacticPlane() {
        let frame = SkyFrame(date: july, observer: boulder)
        let arch = MilkyWayPanorama.arch(frame: frame, refraction: false)
        XCTAssertTrue((175...186).contains(arch.path.count), "\(arch.path.count)")
        for point in arch.path {
            XCTAssertGreaterThanOrEqual(point.horizontal.altitude, 0.0)
            // Every point is on the galactic plane.
            let place = frame.j2000(fromHorizontal: point.horizontal, refracted: false)
            XCTAssertEqual(CoordinateTransforms.equatorialJ2000ToGalactic(place).latitude, 0.0, accuracy: 1e-6)
        }
        // In order of increasing galactic longitude, one degree apart.
        for index in 0..<(arch.path.count - 1) {
            let step = AstroMath.normalizeDegrees(arch.path[index + 1].galacticLongitude - arch.path[index].galacticLongitude)
            XCTAssertEqual(step, 1.0, accuracy: 1e-9)
        }
        // The two ends are on the horizon.
        XCTAssertLessThan(arch.path.first!.horizontal.altitude, 1.0)
        XCTAssertLessThan(arch.path.last!.horizontal.altitude, 1.0)
        // The ends of a half circle are opposite each other: 180° apart in azimuth.
        let span = AstroMath.normalizeDegrees(arch.path.last!.horizontal.azimuth - arch.path.first!.horizontal.azimuth)
        XCTAssertEqual(span, 180.0, accuracy: 2.0)
    }

    func testHighestPointAndInclination() throws {
        let frame = SkyFrame(date: july, observer: boulder)
        let arch = MilkyWayPanorama.arch(frame: frame, refraction: false)
        let highest = try XCTUnwrap(arch.highestPoint)
        // The north galactic pole (IAU, J2000: 192.85948°, +27.12825°) gives the tilt of the plane independently: inclination = 90° − |altitude of the pole|.
        let pole = frame.horizontal(j2000: EquatorialCoordinate(rightAscension: 192.85948, declination: 27.12825), properMotion: nil, refraction: false)
        XCTAssertEqual(arch.inclination, 90.0 - abs(pole.altitude), accuracy: 0.01)
        // A full arch reaches its inclination, and nothing on the path is higher.
        XCTAssertEqual(highest.horizontal.altitude, arch.inclination, accuracy: 1e-6)
        for point in arch.path { XCTAssertLessThanOrEqual(point.horizontal.altitude, highest.horizontal.altitude + 1e-6) }
        // The highest point lies on the plane, at the galactic longitude whose altitude is greatest.
        let best = try XCTUnwrap(arch.path.max { $0.horizontal.altitude < $1.horizontal.altitude })
        XCTAssertEqual(abs(AstroMath.normalizeSignedDegrees(best.galacticLongitude - highest.galacticLongitude)), 0.0, accuracy: 1.0)
        XCTAssertGreaterThanOrEqual(highest.horizontal.altitude, best.horizontal.altitude)
    }

    func testRefractionLiftsTheArchSlightly() throws {
        let frame = SkyFrame(date: july, observer: boulder)
        let plain = MilkyWayPanorama.arch(frame: frame, refraction: false)
        let refracted = MilkyWayPanorama.arch(frame: frame, refraction: true)
        XCTAssertGreaterThanOrEqual(refracted.path.count, plain.path.count)
        XCTAssertEqual(refracted.inclination, plain.inclination, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(refracted.highestPoint).horizontal.altitude, try XCTUnwrap(plain.highestPoint).horizontal.altitude, accuracy: 0.02)
        XCTAssertGreaterThan(refracted.core.altitude, plain.core.altitude)
    }

    func testCoreTiltAgainstAFiniteDifference() throws {
        // The tilt is the angle between the plane's direction at the core and the horizontal direction. Measured here by
        // placing two points of the plane half a degree either side of the core, in azimuth and altitude.
        for seconds in [1_784_178_000.0, 1_784_178_000.0 - 4 * 3600, 1_784_178_000.0 + 2 * 3600, 1_778_922_000.0] {
            let frame = SkyFrame(date: Date(timeIntervalSince1970: seconds), observer: boulder)
            let arch = MilkyWayPanorama.arch(frame: frame, refraction: false)
            let before = frame.horizontal(j2000: CoordinateTransforms.galacticToEquatorialJ2000(GalacticCoordinate(longitude: -0.25, latitude: 0)),
                                          properMotion: nil, refraction: false)
            let after = frame.horizontal(j2000: CoordinateTransforms.galacticToEquatorialJ2000(GalacticCoordinate(longitude: 0.25, latitude: 0)),
                                         properMotion: nil, refraction: false)
            let altitude = AstroMath.asinDeg((AstroMath.sinDeg(before.altitude) + AstroMath.sinDeg(after.altitude)) / 2)
            let alongHorizon = abs(AstroMath.normalizeSignedDegrees(after.azimuth - before.azimuth)) * AstroMath.cosDeg(altitude)
            let upward = abs(after.altitude - before.altitude)
            let expected = AstroMath.atan2Deg(upward, alongHorizon)
            let tilt = try XCTUnwrap(arch.coreTilt)
            XCTAssertEqual(tilt, expected, accuracy: 0.05, "at \(seconds)")
            XCTAssertTrue((0.0...90.0).contains(tilt))
        }
    }

    func testArchAboveAHighMinimumAltitudeIsEmpty() {
        let frame = SkyFrame(date: july, observer: boulder)
        let arch = MilkyWayPanorama.arch(frame: frame, minimumAltitude: 89, refraction: false)
        XCTAssertTrue(arch.path.isEmpty)
        XCTAssertNil(arch.highestPoint)
        XCTAssertNil(arch.panoramaRegion())
        XCTAssertEqual(arch.minimumAltitude, 89.0)
        // A raised floor shortens the path.
        let raised = MilkyWayPanorama.arch(frame: frame, minimumAltitude: 30, refraction: false)
        XCTAssertLessThan(raised.path.count, MilkyWayPanorama.arch(frame: frame, refraction: false).path.count)
        XCTAssertTrue(raised.path.allSatisfy { $0.horizontal.altitude >= 30.0 })
        // Arguments that are not numbers fall back to the defaults.
        XCTAssertEqual(MilkyWayPanorama.arch(frame: frame, minimumAltitude: .nan).minimumAltitude, 0.0)
        XCTAssertEqual(MilkyWayPanorama.arch(frame: frame, longitudeStep: .nan).path.count, MilkyWayPanorama.arch(frame: frame).path.count)
        XCTAssertGreaterThan(MilkyWayPanorama.arch(frame: frame, longitudeStep: 0.001).path.count, 600)
    }

    func testArchInTheSouthernHemisphere() throws {
        // From Paranal in July the core passes near the zenith.
        let frame = SkyFrame(date: july, observer: paranal)
        let arch = MilkyWayPanorama.arch(frame: frame, refraction: false)
        XCTAssertTrue((175...186).contains(arch.path.count))
        XCTAssertGreaterThan(arch.core.altitude, 60)
        let times = MilkyWayPanorama.bestTimes(
            observer: paranal, intervals: [DateInterval(start: july.addingTimeInterval(-6 * 3600), end: july.addingTimeInterval(6 * 3600))])
        XCTAssertGreaterThan(try XCTUnwrap(times.coreHighest).coreAltitude, 80)
    }

    // MARK: The panorama box

    func testPanoramaBoxCoversTheArch() throws {
        for seconds in [1_784_178_000.0, 1_784_178_000.0 - 5 * 3600, 1_773_661_200.0] {
            let frame = SkyFrame(date: Date(timeIntervalSince1970: seconds), observer: boulder)
            let arch = MilkyWayPanorama.arch(frame: frame, refraction: false)
            let box = try XCTUnwrap(arch.panoramaRegion(minimumAltitude: 5, margin: 5))
            guard case let .horizontal(azimuthStart, azimuthSpan, minimumAltitude, maximumAltitude) = box else { return XCTFail("not horizontal") }
            XCTAssertTrue(azimuthSpan > 100 && azimuthSpan <= 360)
            XCTAssertTrue(azimuthStart >= 0 && azimuthStart < 360)
            XCTAssertTrue(minimumAltitude >= -90 && minimumAltitude < maximumAltitude && maximumAltitude <= 90)
            // Every point of the arch above 5° lies inside the box, with the margin to spare.
            for point in arch.path.filter({ $0.horizontal.altitude >= 5.0 }) {
                let offset = AstroMath.normalizeDegrees(point.horizontal.azimuth - azimuthStart)
                XCTAssertTrue(offset >= 4.99 && offset <= azimuthSpan - 4.99, "azimuth offset \(offset) of \(azimuthSpan)")
                XCTAssertTrue(point.horizontal.altitude >= minimumAltitude + 4.99 || minimumAltitude <= -85.0)
                XCTAssertTrue(point.horizontal.altitude <= maximumAltitude - 4.99 || maximumAltitude >= 89.99)
            }
            // The box is a good region for the planner, and the panels it plans cover the arch.
            let plan = try MosaicPlanner.plan(region: box, frame: MosaicTestSupport.frame(focalLength: 24), orientation: .portrait)
            let quads = plan.panels.map { MosaicTestSupport.Quad($0) }
            for point in arch.path.filter({ $0.horizontal.altitude >= 5.0 }) {
                let vector = point.horizontal.unitVector
                XCTAssertTrue(quads.contains { $0.contains(vector) }, "arch point \(point.horizontal) not covered")
            }
            XCTAssertTrue((3...24).contains(plan.panelCount), "\(plan.panelCount)")
        }
    }

    func testPanoramaBoxSettings() throws {
        let frame = SkyFrame(date: july, observer: boulder)
        let arch = MilkyWayPanorama.arch(frame: frame, refraction: false)
        guard case let .horizontal(_, tightSpan, tightMinimum, tightMaximum)? = arch.panoramaRegion(minimumAltitude: 20, margin: 0),
              case let .horizontal(_, looseSpan, _, _)? = arch.panoramaRegion(minimumAltitude: 5, margin: 10),
              case let .horizontal(_, bareSpan, bareMinimum, _)? = arch.panoramaRegion(minimumAltitude: 5, margin: 0)
        else { return XCTFail("no region") }
        XCTAssertLessThan(tightSpan, looseSpan)
        XCTAssertGreaterThanOrEqual(tightMinimum, 19.99)
        XCTAssertEqual(tightMaximum, try XCTUnwrap(arch.highestPoint).horizontal.altitude, accuracy: 0.01)
        XCTAssertEqual(bareSpan, looseSpan - 20.0, accuracy: 1e-9)
        // Margins and floors that are not numbers fall back to 5°; a huge margin is limited to 45°.
        XCTAssertEqual(arch.panoramaRegion(minimumAltitude: 5, margin: 5), arch.panoramaRegion(minimumAltitude: .nan, margin: .nan))
        guard case let .horizontal(_, wideSpan, wideMinimum, wideMaximum)? = arch.panoramaRegion(minimumAltitude: 5, margin: 1000)
        else { return XCTFail("no region") }
        XCTAssertEqual(wideSpan, bareSpan + 90.0, accuracy: 1e-9)
        XCTAssertEqual(wideMinimum, bareMinimum - 45.0, accuracy: 1e-9)
        XCTAssertEqual(wideMaximum, 90.0)
        // The result is always an altitude range at least a degree high.
        let flat = MilkyWayArch(
            path: [MilkyWayPoint(galacticLongitude: 10, horizontal: HorizontalCoordinate(azimuth: 100, altitude: 30))],
            highestPoint: nil, inclination: 0, core: HorizontalCoordinate(azimuth: 0, altitude: 0), coreTilt: nil, minimumAltitude: 0)
        guard case let .horizontal(boxStart, boxSpan, boxMinimum, boxMaximum)? = flat.panoramaRegion(minimumAltitude: 0, margin: 0)
        else { return XCTFail("no region") }
        XCTAssertEqual(boxMaximum - boxMinimum, 1.0, accuracy: 1e-9)
        XCTAssertEqual(boxSpan, 1.0, accuracy: 1e-9)
        XCTAssertEqual(boxStart, 100.0, accuracy: 1e-9)
    }

    func testPanoramaOfAnArchPassingNearTheZenithFollowsThePath() throws {
        // In September at Boulder the plane passes close to the zenith: the box is as wide as the arch is, not narrower.
        let frame = SkyFrame(date: Date(timeIntervalSince1970: 1_789_495_200 + 9 * 3600), observer: boulder)
        let arch = MilkyWayPanorama.arch(frame: frame, refraction: false)
        XCTAssertGreaterThan(arch.inclination, 70)
        guard case let .horizontal(_, span, _, maximum)? = arch.panoramaRegion() else { return XCTFail("no region") }
        XCTAssertGreaterThan(span, 150)
        XCTAssertGreaterThan(maximum, 75)
    }

    // MARK: Best times

    func testCoreHighestAgreesWithTheNightSummary() throws {
        let summary = NightPlanner.summary(nightStartingOn: august, observer: boulder, timeZone: denver)
        let expected = try XCTUnwrap(summary.milkyWayCore.bestTime)
        let times = MilkyWayPanorama.bestTimes(summary: summary, darkness: .moonFree)
        let highest = try XCTUnwrap(times.coreHighest)
        XCTAssertEqual(abs(highest.date.timeIntervalSince(expected)), 0.0, accuracy: 180.0)
        XCTAssertEqual(highest.coreAltitude, try XCTUnwrap(summary.milkyWayCore.maxAltitude), accuracy: 0.2)
        XCTAssertEqual(highest.coreAzimuth, try XCTUnwrap(summary.milkyWayCore.bestAzimuth), accuracy: 0.6)
        // The Moon is down all night: astronomical darkness gives the same answer.
        XCTAssertEqual(highest.date, MilkyWayPanorama.bestTimes(summary: summary).coreHighest?.date)
    }

    func testMostHorizontalAndMostVerticalAreTheExtremesOfTheNight() throws {
        for start in [july, august] {
            let summary = NightPlanner.summary(nightStartingOn: start, observer: boulder, timeZone: denver)
            let intervals = summary.astronomicalDarknessIntervals
            let times = MilkyWayPanorama.bestTimes(summary: summary)
            let flat = try XCTUnwrap(times.mostHorizontal)
            let steep = try XCTUnwrap(times.mostVertical)
            // Brute force every five minutes.
            var smallest = 90.0
            var largest = 0.0
            for interval in intervals {
                var offset = 0.0
                while offset <= interval.duration {
                    let frame = SkyFrame(date: interval.start.addingTimeInterval(offset), observer: boulder)
                    let arch = MilkyWayPanorama.arch(frame: frame, refraction: false)
                    if let tilt = arch.coreTilt, arch.core.altitude >= 10.0 {
                        smallest = min(smallest, tilt)
                        largest = max(largest, tilt)
                    }
                    offset += 300.0
                }
            }
            let flatTilt = try XCTUnwrap(flat.coreTilt)
            let steepTilt = try XCTUnwrap(steep.coreTilt)
            XCTAssertLessThanOrEqual(flatTilt, smallest + 1e-6, "flat \(flatTilt) against \(smallest)")
            XCTAssertEqual(flatTilt, smallest, accuracy: 1.0)
            XCTAssertGreaterThanOrEqual(steepTilt, largest - 1e-6, "steep \(steepTilt) against \(largest)")
            XCTAssertEqual(steepTilt, largest, accuracy: 1.0)
            XCTAssertTrue(flat.coreAltitude >= 10.0 - 1e-6 && steep.coreAltitude >= 10.0 - 1e-6)
            XCTAssertLessThanOrEqual(flatTilt, steepTilt)
            // The moments are inside the dark intervals.
            for moment in [flat, steep, try XCTUnwrap(times.coreHighest)] {
                XCTAssertTrue(intervals.contains { $0.contains(moment.date) }, "\(moment.date)")
            }
            // Inclination at the moment agrees with a fresh arch.
            let fresh = MilkyWayPanorama.arch(frame: SkyFrame(date: flat.date, observer: boulder), refraction: false)
            XCTAssertEqual(flat.inclination, fresh.inclination, accuracy: 1e-6)
            XCTAssertEqual(flatTilt, try XCTUnwrap(fresh.coreTilt), accuracy: 1e-6)
        }
    }

    func testNoCoreInDecemberAtNight() {
        let summary = NightPlanner.summary(nightStartingOn: december, observer: boulder, timeZone: denver)
        let times = MilkyWayPanorama.bestTimes(summary: summary)
        XCTAssertNil(times.coreHighest)
        XCTAssertNil(times.mostHorizontal)
        XCTAssertNil(times.mostVertical)
        // Raising the limit hides July's core as well: it only gets 21° high.
        let julySummary = NightPlanner.summary(nightStartingOn: july, observer: boulder, timeZone: denver)
        XCTAssertNil(MilkyWayPanorama.bestTimes(summary: julySummary, minimumCoreAltitude: 30).coreHighest)
        XCTAssertNotNil(MilkyWayPanorama.bestTimes(summary: julySummary, minimumCoreAltitude: 15).coreHighest)
        // Nothing to search.
        XCTAssertNil(MilkyWayPanorama.bestTimes(observer: boulder, intervals: []).coreHighest)
    }

    func testBestTimesHandleASingleInstant() throws {
        let instant = DateInterval(start: july, duration: 0)
        let times = MilkyWayPanorama.bestTimes(observer: boulder, intervals: [instant])
        for moment in [times.coreHighest, times.mostHorizontal, times.mostVertical] {
            XCTAssertEqual(abs(try XCTUnwrap(moment).date.timeIntervalSince(july)), 0.0, accuracy: 1e-6)
        }
        XCTAssertEqual(try XCTUnwrap(times.mostHorizontal).coreTilt, try XCTUnwrap(times.mostVertical).coreTilt)
    }

    func testMilkyWayHelpersAreFast() {
        let frame = SkyFrame(date: july, observer: boulder)
        _ = MilkyWayPanorama.arch(frame: frame)
        var start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<50 { _ = MilkyWayPanorama.arch(frame: frame) }
        let archMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 50.0 / 1e6
        XCTAssertLessThan(archMilliseconds, 20.0, "\(archMilliseconds) ms per arch")
        let summary = NightPlanner.summary(nightStartingOn: july, observer: boulder, timeZone: denver)
        _ = MilkyWayPanorama.bestTimes(summary: summary)
        start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<10 { _ = MilkyWayPanorama.bestTimes(summary: summary) }
        let timesMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 10.0 / 1e6
        XCTAssertLessThan(timesMilliseconds, 300.0, "\(timesMilliseconds) ms per search")
    }
}
