import LodestarKit
import XCTest
@testable import AppCore

/// The reference objects offered for star alignment, the notices of the alignment sheet and the words for its errors.
final class AimAlignmentSupportTests: XCTestCase {
    private enum Fixture {
        static let catalog = Result { try Catalog.loadBundled() }
    }

    private let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    /// 2026-07-16 05:00 UTC, 23:00 in Colorado: Arcturus stands 43 degrees up in the southwest.
    private let night = Date(timeIntervalSince1970: 1_784_178_000)
    /// 2026-07-16 17:15 UTC, 10:15 in Colorado: the Sun is 60 degrees up.
    private let morning = Date(timeIntervalSince1970: 1_784_222_100)
    /// 2026-07-16 06:41 UTC: Arcturus stands 5 degrees up in the west, seen from Boulder.
    private let arcturusLow = Date(timeIntervalSince1970: 1_784_190_060)
    /// 2026-07-16 18:38 UTC at 19°N on the meridian of Greenwich: Arcturus crosses the zenith.
    private let arcturusZenith = Date(timeIntervalSince1970: 1_784_227_080)

    // MARK: Helpers

    private func loadedCatalog() throws -> Catalog {
        try Fixture.catalog.get()
    }

    private func candidates(observer: Observer? = nil, at date: Date? = nil) throws -> [AimAlignmentCandidate] {
        AimAlignmentCandidates.make(catalog: try loadedCatalog(), observer: observer ?? boulder, date: date ?? night)
    }

    private func arcturus() throws -> CelestialObject {
        let catalog = try loadedCatalog()
        let star = try XCTUnwrap(catalog.renderStars.first { $0.name == "Arcturus" })
        return try XCTUnwrap(catalog.object(id: star.id))
    }

    private func zenithObserver() -> Observer {
        Observer(location: GeographicLocation(latitude: 19.0, longitude: 0, elevation: 0))
    }

    // MARK: Limits

    func testTheLimitsOfWhatIsOffered() {
        XCTAssertEqual(AimAlignmentCandidates.minimumAltitude, 15.0)
        XCTAssertEqual(AimAlignmentCandidates.maximumAltitude, AlignmentModel.maximumAltitude - 2)
        XCTAssertEqual(AimAlignmentCandidates.maximumAltitude, 78.0)
        XCTAssertEqual(AimAlignmentCandidates.starMagnitudeLimit, 2.0)
        XCTAssertEqual(AimAlignmentCandidates.planetMagnitudeLimit, 3.0)
    }

    // MARK: Who is offered

    func testEveryCandidateIsBetweenTheAltitudeLimits() throws {
        for date in [night, morning] {
            let list = try candidates(at: date)
            XCTAssertFalse(list.isEmpty)
            for candidate in list {
                XCTAssertGreaterThanOrEqual(candidate.horizontal.altitude, 15.0, candidate.id)
                XCTAssertLessThanOrEqual(candidate.horizontal.altitude, 78.0, candidate.id)
            }
        }
    }

    func testStarsAreOfferedDownToMagnitudeTwo() throws {
        let list = try candidates()
        let stars = list.filter { $0.id.hasPrefix("star.") }
        XCTAssertFalse(stars.isEmpty)
        for star in stars {
            let magnitude = try XCTUnwrap(star.magnitude, star.id)
            XCTAssertLessThanOrEqual(magnitude, 2.0, star.id)
        }
    }

    func testABrightStarInTheSkyIsOfferedWithItsPositionAndMagnitude() throws {
        let star = try arcturus()
        let list = try candidates()
        let found = try XCTUnwrap(list.first { $0.id == star.id }, "Arcturus is 43 degrees up")
        XCTAssertEqual(found.object, star)
        XCTAssertEqual(try XCTUnwrap(found.magnitude), -0.05, accuracy: 1e-9)
        let expected = SkyFrame(date: night, observer: boulder).horizontal(of: star, refraction: true)
        XCTAssertEqual(found.horizontal.altitude, expected.altitude, accuracy: 1e-9)
        XCTAssertEqual(AstroMath.normalizeSignedDegrees(found.horizontal.azimuth - expected.azimuth), 0.0, accuracy: 1e-9)
        XCTAssertEqual(found.horizontal.altitude, 42.8, accuracy: 0.5)
    }

    func testAStarTooCloseToTheZenithIsNotOffered() throws {
        let star = try arcturus()
        let observer = zenithObserver()
        let altitude = SkyFrame(date: arcturusZenith, observer: observer).horizontal(of: star, refraction: true).altitude
        XCTAssertGreaterThan(altitude, 80.0, "the test needs Arcturus at the zenith")
        XCTAssertFalse(try candidates(observer: observer, at: arcturusZenith).contains { $0.id == star.id })
    }

    func testAStarTooLowIsNotOffered() throws {
        let star = try arcturus()
        let altitude = SkyFrame(date: arcturusLow, observer: boulder).horizontal(of: star, refraction: true).altitude
        XCTAssertLessThan(altitude, 10.0, "the test needs Arcturus near the horizon")
        XCTAssertGreaterThan(altitude, 0.0)
        XCTAssertFalse(try candidates(at: arcturusLow).contains { $0.id == star.id })
    }

    func testTheSunIsNeverOffered() throws {
        // The Sun stands 60 degrees up, inside the altitude limits: it is left out all the same.
        let sunAltitude = SkyFrame(date: morning, observer: boulder).horizontal(of: .sun, refraction: true).altitude
        XCTAssertTrue((15.0...78.0).contains(sunAltitude), "the test needs the Sun between the limits")
        let list = try candidates(at: morning)
        XCTAssertFalse(list.contains { $0.id == "sun" })
    }

    func testTheMoonIsOfferedWhenItIsBetweenTheLimitsWhateverItsBrightness() throws {
        let frame = SkyFrame(date: morning, observer: boulder)
        let altitude = frame.horizontal(of: .moon, refraction: true).altitude
        let list = try candidates(at: morning)
        XCTAssertEqual(list.contains { $0.id == "moon" }, (15.0...78.0).contains(altitude), "moon at \(altitude) degrees")
        if let moon = list.first(where: { $0.id == "moon" }) {
            XCTAssertEqual(moon.horizontal.altitude, altitude, accuracy: 1e-9)
            XCTAssertEqual(moon.magnitude, frame.state(of: .moon).apparentMagnitude)
        }
    }

    func testThePlanetsThatNeverGetAsBrightAsMagnitudeThreeAreNeverOffered() throws {
        for date in [night, morning, arcturusLow] {
            let ids = Set(try candidates(at: date).map(\.id))
            XCTAssertFalse(ids.contains("planet.uranus"))
            XCTAssertFalse(ids.contains("planet.neptune"))
        }
    }

    func testPlanetsThatAreOfferedAreBrightEnough() throws {
        for date in [night, morning, arcturusLow, arcturusZenith] {
            for candidate in try candidates(at: date) where candidate.id.hasPrefix("planet.") {
                let magnitude = try XCTUnwrap(candidate.magnitude, candidate.id)
                XCTAssertLessThanOrEqual(magnitude, 3.0, candidate.id)
            }
        }
    }

    func testACandidateAndItsRowAreIdentifiedByTheirObject() throws {
        let star = try arcturus()
        let candidate = AimAlignmentCandidate(object: star, horizontal: HorizontalCoordinate(azimuth: 200, altitude: 40),
                                              magnitude: -0.05)
        XCTAssertEqual(candidate.id, star.id)
        let withSeparation = AimAlignmentRow(candidate: candidate, separation: 12.5)
        XCTAssertEqual(withSeparation.id, star.id)
        XCTAssertEqual(withSeparation.separation, 12.5)
        XCTAssertNil(AimAlignmentRow(candidate: candidate, separation: nil).separation)
    }

    // MARK: Notices

    func testASuccessNoticeCarriesItsText() {
        let notice = AimAlignmentNotice.success("Aligned on Vega.")
        XCTAssertEqual(notice.text, "Aligned on Vega.")
        XCTAssertTrue(notice.isSuccess)
    }

    func testAFailureNoticeCarriesItsText() {
        let notice = AimAlignmentNotice.failure("Not aligned.")
        XCTAssertEqual(notice.text, "Not aligned.")
        XCTAssertFalse(notice.isSuccess)
    }

    // MARK: Error messages

    func testUnusableSensorReadingsAskForASteadyPhone() {
        XCTAssertEqual(AlignmentError.nonFiniteInput.aimMessage(forObject: "Vega"),
                       "The sensors gave an unusable reading. Hold the phone still for a moment and sync again.")
    }

    func testACameraPointingStraightUpIsToldToChooseALowerObject() {
        XCTAssertEqual(AlignmentError.boresightTooHigh(altitude: 85.4).aimMessage(forObject: "Vega"),
                       "The camera points almost straight up (85\u{00B0}). Alignment needs an object below 80\u{00B0}: choose a lower one.")
        // A camera pointing at the nadir has a negative altitude: the number is written with a minus sign.
        let down = AlignmentError.boresightTooHigh(altitude: -85.6).aimMessage(forObject: "Vega")
        XCTAssertTrue(down.contains("(\u{2212}86\u{00B0})"), down)
    }

    func testATargetTooHighIsNamed() {
        XCTAssertEqual(AlignmentError.targetTooHigh(altitude: 86.6).aimMessage(forObject: "Vega"),
                       "Vega is too high in the sky (87\u{00B0}) for a reliable alignment. Choose an object below 80\u{00B0}.")
    }

    func testAnImplausibleCorrectionNamesTheObject() {
        XCTAssertEqual(AlignmentError.implausibleCorrection(degrees: 23.2).aimMessage(forObject: "Capella"),
                       "This would need a correction of 23\u{00B0}, more than a bracket can cause. Check that Capella is really in the middle of the frame and that the right mount is chosen in Settings.")
    }
}
