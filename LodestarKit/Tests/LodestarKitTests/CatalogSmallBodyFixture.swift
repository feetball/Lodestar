import XCTest
@testable import LodestarKit

/// The comets and asteroids of the small-body catalog tests: real MPC lines of 2026-10-18 (`CometsTestData`) and a helper
/// for synthetic comets. The bundled catalog is the one of `CatalogFixture`.
enum CatalogSmallBodyFixture {
    static var tsuchinshanAtlas: SmallBody { get throws { try CometElementsParser.parseLine(CometsTestData.cometTsuchinshanAtlas) } }
    static var ponsBrooks: SmallBody { get throws { try CometElementsParser.parseLine(CometsTestData.cometPonsBrooks) } }
    static var halley: SmallBody { get throws { try CometElementsParser.parseLine(CometsTestData.cometHalley) } }
    static var haleBopp: SmallBody { get throws { try CometElementsParser.parseLine(CometsTestData.cometHaleBopp) } }
    static var encke: SmallBody { get throws { try CometElementsParser.parseLine(CometsTestData.cometEncke) } }
    static var oumuamua: SmallBody { get throws { try CometElementsParser.parseLine(CometsTestData.cometOumuamua) } }
    static var ceres: SmallBody { get throws { try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidCeres) } }
    static var vesta: SmallBody { get throws { try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidVesta) } }
    static var eros: SmallBody { get throws { try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidEros) } }
    static var yr4: SmallBody { get throws { try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidYr42024) } }
    static var numberedUnnamed: SmallBody {
        get throws { try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidNumberedUnnamed) }
    }
    static var withoutMagnitude: SmallBody {
        get throws { try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidUnknownH) }
    }

    static var comets: [SmallBody] {
        get throws { [try tsuchinshanAtlas, try ponsBrooks, try halley, try haleBopp, try encke] }
    }

    static var asteroids: [SmallBody] {
        get throws { [try ceres, try vesta, try eros, try yr4] }
    }

    /// The bundled catalog with all of the bodies above that have a magnitude, added.
    static func catalog() throws -> Catalog {
        try CatalogFixture.catalog().withSmallBodies(try comets + asteroids)
    }

    /// A comet with the given `name` whose peak magnitude estimate is `peakMagnitude` (perihelion at 1 AU, where the
    /// estimate is `M1 + 5·log10(√2)`, so M1 is the estimate minus 0.7526).
    static func comet(_ designation: String, _ name: String, _ peakMagnitude: Double) throws -> SmallBody {
        let orbit = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: 1, eccentricity: 0.5, inclination: 20,
                                                    argumentOfPerihelion: 30, longitudeOfAscendingNode: 40,
                                                    perihelionJulianDayTT: 2_461_000, epochJulianDayTT: 2_461_200.5))
        let magnitudes = try XCTUnwrap(CometMagnitudes(totalMagnitude: peakMagnitude - 0.752574989159953, totalSlope: 10))
        return try XCTUnwrap(SmallBody(designation: designation, name: name, kind: .comet, number: nil, orbit: orbit,
                                       photometry: .comet(magnitudes)))
    }
}
