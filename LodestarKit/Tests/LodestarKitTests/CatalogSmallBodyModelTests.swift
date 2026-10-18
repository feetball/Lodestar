import XCTest
@testable import LodestarKit

private typealias Fixture = CatalogSmallBodyFixture

/// Comets and asteroids as catalog objects: categories, position case, factory, peak magnitude estimate, prominence.
final class CatalogSmallBodyModelTests: XCTestCase {
    // MARK: Categories

    func testCometAndAsteroidCategories() throws {
        XCTAssertEqual(ObjectCategory.comet.displayName, "Comet")
        XCTAssertEqual(ObjectCategory.asteroid.displayName, "Asteroid")
        XCTAssertEqual(ObjectCategory.comet.systemImageName, "sparkle")
        XCTAssertEqual(ObjectCategory.asteroid.systemImageName, "circle.fill")
        XCTAssertEqual(ObjectCategory.comet.group, .solarSystem)
        XCTAssertEqual(ObjectCategory.asteroid.group, .solarSystem)
        XCTAssertEqual(ObjectGroup.solarSystem.categories, [.sun, .moon, .planet, .comet, .asteroid])
        XCTAssertEqual(ObjectCategory(rawValue: "comet"), .comet)
        XCTAssertEqual(ObjectCategory(rawValue: "asteroid"), .asteroid)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode([ObjectCategory.comet]), as: UTF8.self), "[\"comet\"]")
        XCTAssertEqual(try JSONDecoder().decode([ObjectCategory].self, from: Data("[\"asteroid\"]".utf8)), [.asteroid])
        // The open-NGC type codes never produce them.
        for code in ["G", "OCl", "PN", "*", "Other", "comet"] {
            let category = ObjectCategory(openNGCType: code)
            XCTAssertTrue(category != .comet && category != .asteroid, code)
        }
    }

    // MARK: Factory

    func testCometObject() throws {
        let body = try Fixture.tsuchinshanAtlas
        let object = CelestialObject(smallBody: body)
        XCTAssertEqual(object.id, "comet.C/2023 A3")
        XCTAssertEqual(object.name, "C/2023 A3 (Tsuchinshan-ATLAS)")
        XCTAssertEqual(object.designations, ["C/2023 A3"])
        XCTAssertEqual(object.alternateNames, ["Tsuchinshan-ATLAS"])
        XCTAssertEqual(object.category, .comet)
        XCTAssertEqual(object.group, .solarSystem)
        XCTAssertNil(object.constellation)
        XCTAssertNil(object.constellationName)
        XCTAssertNil(object.magnitude)
        XCTAssertNil(object.angularSize)
        XCTAssertNil(object.colorIndex)
        XCTAssertNil(object.spectralType)
        XCTAssertNil(object.distanceLightYears)
        XCTAssertNil(object.notes)
        XCTAssertTrue(object.catalogNumbers.isEmpty)
        XCTAssertEqual(object.position, .smallBody(body))
        XCTAssertEqual(object.smallBody, body)
        XCTAssertNil(object.j2000)
        XCTAssertTrue(object.isSolarSystem)
        XCTAssertFalse(object.isDeepSky)
        XCTAssertEqual(object.subtitle, "Comet")
        XCTAssertTrue(object.isListed)
        XCTAssertEqual(object.prominence, .showpiece)
        XCTAssertEqual(try XCTUnwrap(object.estimatedPeakMagnitude), 3.6858435, accuracy: 1e-6)
        XCTAssertEqual(object.rankingMagnitude, try XCTUnwrap(object.estimatedPeakMagnitude))
    }

    func testNumberedCometObjectUsesTheNumberedTitle() throws {
        let object = CelestialObject(smallBody: try Fixture.ponsBrooks)
        XCTAssertEqual(object.id, "comet.12P")
        XCTAssertEqual(object.name, "12P/Pons-Brooks")
        XCTAssertEqual(object.designations, ["12P"])
        XCTAssertEqual(object.alternateNames, ["Pons-Brooks"])
        XCTAssertEqual(try XCTUnwrap(object.estimatedPeakMagnitude), 3.9154425, accuracy: 1e-6)
        XCTAssertEqual(CelestialObject(smallBody: try Fixture.halley).id, "comet.1P")
        XCTAssertEqual(CelestialObject(smallBody: try Fixture.haleBopp).prominence, .showpiece)
    }

    func testAsteroidObjects() throws {
        let vesta = CelestialObject(smallBody: try Fixture.vesta)
        XCTAssertEqual(vesta.id, "asteroid.4")
        XCTAssertEqual(vesta.name, "(4) Vesta")
        XCTAssertEqual(vesta.designations, ["(4)"], "a numbered asteroid's designation is its number in parentheses")
        XCTAssertEqual(vesta.alternateNames, ["Vesta"])
        XCTAssertEqual(vesta.category, .asteroid)
        XCTAssertEqual(vesta.subtitle, "Asteroid")
        XCTAssertNil(vesta.magnitude)
        XCTAssertNil(vesta.constellation)
        XCTAssertEqual(try XCTUnwrap(vesta.estimatedPeakMagnitude), 5.2109315, accuracy: 1e-6)
        XCTAssertEqual(vesta.prominence, .showpiece)
        XCTAssertTrue(vesta.isListed)

        let ceres = CelestialObject(smallBody: try Fixture.ceres)
        XCTAssertEqual(ceres.id, "asteroid.1")
        XCTAssertEqual(ceres.name, "(1) Ceres")
        XCTAssertEqual(try XCTUnwrap(ceres.estimatedPeakMagnitude), 6.3134413, accuracy: 1e-6)
        XCTAssertEqual(ceres.prominence, .prominent)

        let eros = CelestialObject(smallBody: try Fixture.eros)
        XCTAssertEqual(try XCTUnwrap(eros.estimatedPeakMagnitude), 9.1564466, accuracy: 1e-6,
                       "the Earth distance is never below 0.5 AU")
        XCTAssertEqual(eros.prominence, .notable)
        XCTAssertTrue(eros.isListed)

        let provisional = CelestialObject(smallBody: try Fixture.yr4)
        XCTAssertEqual(provisional.id, "asteroid.2024 YR4")
        XCTAssertEqual(provisional.name, "2024 YR4")
        XCTAssertEqual(provisional.designations, ["2024 YR4"])
        XCTAssertTrue(provisional.alternateNames.isEmpty)
        XCTAssertEqual(provisional.prominence, .obscure)
        XCTAssertFalse(provisional.isListed, "a faint asteroid is found by search only")

        let unnamed = CelestialObject(smallBody: try Fixture.numberedUnnamed)
        XCTAssertEqual(unnamed.id, "asteroid.202411")
        XCTAssertEqual(unnamed.designations, ["(202411)"])
        XCTAssertEqual(unnamed.name, try Fixture.numberedUnnamed.title)
    }

    func testBodyWithoutMagnitudeParametersIsObscureAndLast() throws {
        let object = CelestialObject(smallBody: try Fixture.withoutMagnitude)
        XCTAssertNil(object.estimatedPeakMagnitude)
        XCTAssertEqual(object.prominence, .obscure)
        XCTAssertFalse(object.isListed)
        XCTAssertEqual(object.rankingMagnitude, Double.infinity)
        let custom = CelestialObject.custom(name: "x", j2000: EquatorialCoordinate(rightAscension: 1, declination: 2))
        XCTAssertNil(custom.estimatedPeakMagnitude)
        XCTAssertNil(custom.smallBody)
    }

    func testObjectsEqualByValueAndHashByIdentifier() throws {
        let first = CelestialObject(smallBody: try Fixture.vesta)
        let second = CelestialObject(smallBody: try Fixture.vesta)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        let fresher = CelestialObject(smallBody: try withEpoch(try Fixture.vesta, 2_461_300.5))
        XCTAssertEqual(first.id, fresher.id, "the identifier survives an element update")
        XCTAssertEqual(first.hashValue, fresher.hashValue)
        XCTAssertNotEqual(first, fresher)
        XCTAssertNotEqual(first, CelestialObject(smallBody: try Fixture.ceres))
    }

    // MARK: Peak magnitude estimate

    func testCometEstimateUsesTheClampedSunDistanceAndARightAngleView() throws {
        let body = try Fixture.haleBopp
        guard case .comet(let photometry) = try XCTUnwrap(body.photometry) else { return XCTFail("a comet") }
        let r = body.orbit.perihelionDistanceAU
        let expected = photometry.totalMagnitude + 5 * log10((1 + r * r).squareRoot()) + photometry.totalSlope * log10(r)
        XCTAssertEqual(try XCTUnwrap(SmallBodyBrightness.peakMagnitudeEstimate(of: body)), expected, accuracy: 1e-12)

        // A sungrazer: 0.05 AU is treated as 0.4226 AU, closer to the Sun than sin 25° nothing can be 25° from it.
        let grazer = try syntheticComet(perihelion: 0.05, totalMagnitude: 10, slope: 10)
        let clamped = 10.0 + 5 * log10((1 + 0.4226 * 0.4226).squareRoot()) + 10.0 * log10(0.4226)
        XCTAssertEqual(try XCTUnwrap(SmallBodyBrightness.peakMagnitudeEstimate(of: grazer)), clamped, accuracy: 1e-12)
        XCTAssertEqual(SmallBodyBrightness.minimumSunDistanceAU, 0.4226)
        XCTAssertEqual(SmallBodyBrightness.minimumAsteroidEarthDistanceAU, 0.5)
    }

    func testAsteroidEstimateIsTheOppositionAtPerihelion() throws {
        let body = try Fixture.vesta
        guard case .asteroid(let photometry) = try XCTUnwrap(body.photometry) else { return XCTFail("an asteroid") }
        let q = body.orbit.perihelionDistanceAU
        XCTAssertEqual(try XCTUnwrap(SmallBodyBrightness.peakMagnitudeEstimate(of: body)),
                       photometry.absoluteMagnitude + 5 * log10(q * (q - 1)), accuracy: 1e-12)
        // The slope parameter does not matter at zero phase.
        let steeper = try XCTUnwrap(SmallBody(
            designation: "4", name: "Vesta", kind: .asteroid, number: 4, orbit: body.orbit,
            photometry: .asteroid(try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: photometry.absoluteMagnitude,
                                                                   slopeParameter: 0.4)))))
        XCTAssertEqual(try XCTUnwrap(SmallBodyBrightness.peakMagnitudeEstimate(of: body)),
                       try XCTUnwrap(SmallBodyBrightness.peakMagnitudeEstimate(of: steeper)), accuracy: 1e-12)
        XCTAssertNil(SmallBodyBrightness.peakMagnitudeEstimate(of: try Fixture.withoutMagnitude))
    }

    func testEstimateOrdersTheFamousBodiesAsExpected() throws {
        let bodies = [try Fixture.haleBopp, try Fixture.tsuchinshanAtlas, try Fixture.vesta, try Fixture.ceres,
                      try Fixture.eros, try Fixture.encke, try Fixture.yr4]
        let estimates = try bodies.map { try XCTUnwrap(SmallBodyBrightness.peakMagnitudeEstimate(of: $0)) }
        XCTAssertEqual(estimates, estimates.sorted())
    }

    // MARK: Prominence

    func testSmallBodyProminenceThresholds() {
        XCTAssertEqual(Prominence.showpieceSmallBodyMagnitude, 6)
        XCTAssertEqual(Prominence.prominentSmallBodyMagnitude, 8)
        XCTAssertEqual(Prominence.notableSmallBodyMagnitude, 10)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: -20), .showpiece)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: 6), .showpiece)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: 6.0000001), .prominent)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: 8), .prominent)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: 8.0000001), .notable)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: 10), .notable)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: 10.0000001), .obscure)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: 30), .obscure)
        XCTAssertEqual(Prominence(smallBodyPeakMagnitude: nil), .obscure)
    }

    func testCometsBrighterThanSixthMagnitudeAreShowpieces() throws {
        XCTAssertEqual(CelestialObject(smallBody: try Fixture.comet("C/2030 A1", "Bright", 5.9)).prominence, .showpiece)
        XCTAssertEqual(CelestialObject(smallBody: try Fixture.comet("C/2030 A2", "Edge", 6.0)).prominence, .showpiece)
        XCTAssertEqual(CelestialObject(smallBody: try Fixture.comet("C/2030 A3", "Binocular", 7.0)).prominence, .prominent)
        XCTAssertEqual(CelestialObject(smallBody: try Fixture.comet("C/2030 A4", "Camera", 9.0)).prominence, .notable)
        let faint = CelestialObject(smallBody: try Fixture.comet("C/2030 A5", "Faint", 12.0))
        XCTAssertEqual(faint.prominence, .obscure)
        XCTAssertFalse(faint.isListed)
        // The listed objects are exactly the notable or better ones.
        for magnitude in [-3.0, 4, 6.5, 8.5, 10, 11, 15] {
            let object = CelestialObject(smallBody: try Fixture.comet("C/2030 B", "B", magnitude))
            XCTAssertEqual(object.isListed, object.prominence <= Prominence.lastListed, "\(magnitude)")
        }
    }

    // MARK: Helpers

    private func syntheticComet(perihelion: Double, totalMagnitude: Double, slope: Double) throws -> SmallBody {
        let orbit = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: perihelion, eccentricity: 0.9, inclination: 20,
                                                    argumentOfPerihelion: 30, longitudeOfAscendingNode: 40,
                                                    perihelionJulianDayTT: 2_461_000, epochJulianDayTT: 2_461_200.5))
        let magnitudes = try XCTUnwrap(CometMagnitudes(totalMagnitude: totalMagnitude, totalSlope: slope))
        return try XCTUnwrap(SmallBody(designation: "C/2031 S1", name: "", kind: .comet, number: nil, orbit: orbit,
                                       photometry: .comet(magnitudes)))
    }

    private func withEpoch(_ body: SmallBody, _ epoch: Double) throws -> SmallBody {
        let orbit = try XCTUnwrap(SmallBodyElements.fromMeanAnomaly(
            semiMajorAxisAU: try XCTUnwrap(body.orbit.semiMajorAxisAU), eccentricity: body.orbit.eccentricity,
            inclination: body.orbit.inclination, argumentOfPerihelion: body.orbit.argumentOfPerihelion,
            longitudeOfAscendingNode: body.orbit.longitudeOfAscendingNode, meanAnomaly: 10, epochJulianDayTT: epoch))
        return try XCTUnwrap(SmallBody(designation: body.designation, name: body.name, kind: body.kind, number: body.number,
                                       orbit: orbit, photometry: body.photometry))
    }
}
