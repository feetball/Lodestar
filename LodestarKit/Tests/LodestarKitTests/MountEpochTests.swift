import XCTest
@testable import LodestarKit

/// J2000 to mount-frame conversions: published values (Meeus) and round trips.
final class MountEpochTests: XCTestCase {
    private let observer = Observer(location: GeographicLocation(latitude: 0.0, longitude: 0.0))

    private func frame(_ jd: JulianDate) -> SkyFrame { SkyFrame(julianDate: jd, observer: observer) }

    private func frame(_ unixSeconds: Double) -> SkyFrame { SkyFrame(date: Date(timeIntervalSince1970: unixSeconds), observer: observer) }

    private func hms(_ hours: Int, _ minutes: Int, _ seconds: Double) -> Double {
        (Double(hours) + Double(minutes) / 60.0 + seconds / 3600.0) * 15.0
    }

    private func dms(_ degrees: Int, _ minutes: Int, _ seconds: Double) -> Double {
        Double(degrees) + Double(minutes) / 60.0 + seconds / 3600.0
    }

    private var thetaPersei: EquatorialCoordinate {
        EquatorialCoordinate(rightAscension: hms(2, 44, 11.986), declination: dms(49, 13, 42.48))
    }

    private func thetaPerseiMotion() -> ProperMotion {
        ProperMotion(raMilliarcsecondsPerYear: 0.03425 * 15 * 1000 * AstroMath.cosDeg(thetaPersei.declination),
                     decMilliarcsecondsPerYear: -89.5)
    }

    func testMeanOfDateMatchesMeeusExample21b() {
        // Meeus, Astronomical Algorithms 21.b: θ Persei, J2000.0 → 2028 November 13.19 TD, with proper motion:
        // α = 2h 46m 11.331s = 41.547214°, δ = +49° 20′ 54.54″ = 49.348483°.
        let sky = frame(JulianDate(tt: 2_462_088.69))
        let place = MountEpoch.meanOfDate.fromJ2000(thetaPersei, frame: sky, properMotion: thetaPerseiMotion())
        XCTAssertEqual(place.rightAscension, 41.547214, accuracy: 0.00001)
        XCTAssertEqual(place.declination, 49.348483, accuracy: 0.00001)
    }

    func testApparentOfDateMatchesMeeusExample23a() {
        // Meeus 23.a: the apparent place for the same instant: α = 2h 46m 14.390s, δ = +49° 21′ 07.45″.
        let sky = frame(JulianDate(tt: 2_462_088.69))
        let place = MountEpoch.apparentOfDate.fromJ2000(thetaPersei, frame: sky, properMotion: thetaPerseiMotion())
        XCTAssertEqual(place.rightAscension, hms(2, 46, 14.390), accuracy: 0.05 / 3600)
        XCTAssertEqual(place.declination, dms(49, 21, 7.45), accuracy: 0.05 / 3600)
    }

    func testJ2000FrameOnlyAppliesProperMotion() {
        let sky = frame(JulianDate(tt: 2_462_088.69))
        XCTAssertEqual(MountEpoch.j2000.fromJ2000(thetaPersei, frame: sky), thetaPersei)
        let moved = MountEpoch.j2000.fromJ2000(thetaPersei, frame: sky, properMotion: thetaPerseiMotion())
        XCTAssertEqual(moved, thetaPerseiMotion().apply(to: thetaPersei, years: sky.yearsSinceJ2000))
        let separation = moved.angularSeparation(to: thetaPersei)
        XCTAssertTrue(separation >= 0.0025 && separation <= 0.0030, "moved \(separation)")
        // Barnard's Star moves 10.3 arcseconds per year in declination.
        let barnard = EquatorialCoordinate(rightAscensionHours: 17.9631, declination: 4.6934)
        let sky2026 = frame(1_792_296_000.0)
        let shifted = MountEpoch.j2000.fromJ2000(barnard, frame: sky2026,
                                                 properMotion: ProperMotion(raMilliarcsecondsPerYear: -798.58, decMilliarcsecondsPerYear: 10_328.12))
        XCTAssertEqual(shifted.declination - barnard.declination, 10.32812 * sky2026.yearsSinceJ2000 / 3600, accuracy: 0.0002)
    }

    func testMeanOfDateIsPurePrecession() {
        // 26.8 years of general precession move a place on the equator at α = 0 by about 46.1″ × 26.8 = 0.34°.
        let sky = frame(1_792_296_000.0)
        let origin = EquatorialCoordinate(rightAscension: 0.0, declination: 0.0)
        let place = MountEpoch.meanOfDate.fromJ2000(origin, frame: sky)
        XCTAssertEqual(place.rightAscension, 0.343, accuracy: 0.005)
        XCTAssertEqual(place.declination, 0.149, accuracy: 0.005)
        // Apparent and mean places differ by nutation and aberration only: below 0.01° (36″).
        let apparent = MountEpoch.apparentOfDate.fromJ2000(origin, frame: sky)
        let difference = place.angularSeparation(to: apparent)
        XCTAssertTrue(difference > 0.0005 && difference < 0.01, "difference \(difference)")
    }

    func testPlacesSurviveTheRoundTrip() {
        let dates = [946_728_000.0, 1_000_000_000.0, 1_792_296_000.0, 2_550_000_000.0, 4_000_000_000.0]
        var places: [EquatorialCoordinate] = []
        for ra in [0.0, 0.0001, 45.0, 123.456, 180.0, 270.5, 359.9999] {
            for dec in [-89.9, -60.0, -10.0, 0.0, 33.3, 75.0, 89.9] {
                places.append(EquatorialCoordinate(rightAscension: ra, declination: dec))
            }
        }
        places.append(EquatorialCoordinate(rightAscension: 10.0, declination: 90.0))
        places.append(EquatorialCoordinate(rightAscension: 250.0, declination: -90.0))
        for epoch in MountEpoch.allCases {
            for date in dates {
                let sky = frame(date)
                for place in places {
                    let mount = epoch.fromJ2000(place, frame: sky)
                    let back = epoch.toJ2000(mount, frame: sky)
                    // First-order aberration inversion is good to a few milliarcseconds; the rest is exact.
                    XCTAssertEqual(place.angularSeparation(to: back), 0.0, accuracy: 2e-6, "\(epoch) \(date) \(place)")
                }
            }
        }
    }

    func testRightAscensionStaysInRangeAcrossTheWrap() {
        let sky = frame(1_792_296_000.0)
        let nearZero = EquatorialCoordinate(rightAscension: 359.9999, declination: 10.0)
        for epoch in MountEpoch.allCases {
            let mount = epoch.fromJ2000(nearZero, frame: sky)
            XCTAssertTrue(mount.rightAscension >= 0.0 && mount.rightAscension < 360.0, "\(epoch) \(mount.rightAscension)")
            let separation = mount.angularSeparation(to: nearZero)
            XCTAssertLessThan(separation, 0.5, "\(epoch) \(separation)")
        }
    }

    func testRawValues() {
        XCTAssertEqual(MountEpoch(rawValue: "meanOfDate"), .meanOfDate)
        XCTAssertEqual(MountEpoch(rawValue: "apparentOfDate"), .apparentOfDate)
        XCTAssertEqual(MountEpoch(rawValue: "j2000"), .j2000)
        XCTAssertNil(MountEpoch(rawValue: "B1950"))
        for protocolKind in MountProtocol.allCases { XCTAssertEqual(MountProtocol(rawValue: protocolKind.rawValue), protocolKind) }
        for feature in MountFeature.allCases { XCTAssertEqual(MountFeature(rawValue: feature.rawValue), feature) }
        for phase in MountPhase.allCases { XCTAssertEqual(MountPhase(rawValue: phase.rawValue), phase) }
        for direction in MountNudgeDirection.allCases { XCTAssertEqual(MountNudgeDirection(rawValue: direction.rawValue), direction) }
        for rate in MountNudgeRate.allCases { XCTAssertEqual(MountNudgeRate(rawValue: rate.rawValue), rate) }
        for flavor in NexStarFlavor.allCases { XCTAssertEqual(NexStarFlavor(rawValue: flavor.rawValue), flavor) }
        for precision in LX200Precision.allCases { XCTAssertEqual(LX200Precision(rawValue: precision.rawValue), precision) }
        for dialect in LX200Dialect.allCases { XCTAssertEqual(LX200Dialect(rawValue: dialect.rawValue), dialect) }
        XCTAssertNil(MountProtocol(rawValue: "x"))
    }

    func testNudgeRates() {
        XCTAssertEqual(MountNudgeRate.siderealDegreesPerSecond, 15.041068 / 3600, accuracy: 1e-8)
        XCTAssertEqual(MountNudgeRate.guide.degreesPerSecond, MountNudgeRate.siderealDegreesPerSecond, accuracy: 0.0)
        XCTAssertEqual(MountNudgeRate.center.degreesPerSecond, 8 * MountNudgeRate.siderealDegreesPerSecond, accuracy: 1e-12)
        let rates = MountNudgeRate.allCases
        for index in 1 ..< rates.count { XCTAssertLessThan(rates[index - 1].degreesPerSecond, rates[index].degreesPerSecond) }
        XCTAssertLessThan(abs(MountNudgeRate.slew.degreesPerSecond * 3600 * 4), 65_535, "fits the NexStar rate field")
    }
}
