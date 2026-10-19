import XCTest
@testable import LodestarKit

/// The bright asteroids that ship with the library (`asteroids.txt`, an extract of the Minor Planet Center's `MPCORB.DAT`
/// of 2026-10-18), against JPL Horizons and the Small-Body Database.
final class CatalogBundledAsteroidsTests: XCTestCase {
    private func loaded() throws -> BundledAsteroids { try BundledAsteroids.load() }

    private func byDesignation() throws -> [String: SmallBody] {
        Dictionary(try loaded().bodies.map { ($0.designation, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: The data

    func testTheBundledFileDecodesWithoutRejections() throws {
        let loaded = try loaded()
        XCTAssertEqual(loaded.bodies.count, 216, "the asteroids of the pinned MPCORB file that pass the cut")
        XCTAssertEqual(loaded.rejectedLineCount, 0)
        XCTAssertEqual(Set(loaded.bodies.map(\.id)).count, loaded.bodies.count)
        XCTAssertTrue(loaded.bodies.allSatisfy { $0.kind == .asteroid })
        XCTAssertTrue(loaded.bodies.allSatisfy { $0.number != nil && $0.designation == String($0.number ?? 0) })
        let numbers = loaded.bodies.compactMap(\.number)
        XCTAssertEqual(numbers, numbers.sorted(), "in the order of the MPC file")
        XCTAssertTrue(loaded.bodies.allSatisfy { !$0.name.isEmpty || ($0.number ?? 0) > 10_000 }, "the bright ones have names")
    }

    func testTheSelectionRuleHolds() throws {
        let loaded = try loaded()
        let byDesignation = try byDesignation()
        for body in loaded.bodies {
            guard case .asteroid(let photometry) = try XCTUnwrap(body.photometry, body.id) else { return XCTFail(body.id) }
            XCTAssertLessThanOrEqual(photometry.absoluteMagnitude, BundledAsteroids.maximumAbsoluteMagnitude, body.id)
            XCTAssertLessThanOrEqual(try XCTUnwrap(SmallBodyBrightness.peakMagnitudeEstimate(of: body)),
                                     BundledAsteroids.peakMagnitudeLimit + 1e-6, body.id)
        }
        for number in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 433, 1036] {
            XCTAssertNotNil(byDesignation["\(number)"], "(\(number)) is bright")
        }
        // Objects that are bright in absolute magnitude but never in the sky are not in it.
        for number in [134_340, 136_199, 136_472, 90_377, 50_000, 28_978] {
            XCTAssertNil(byDesignation["\(number)"], "(\(number)) is far away")
        }
        XCTAssertEqual(byDesignation["4"]?.name, "Vesta")
        XCTAssertEqual(byDesignation["1"]?.name, "Ceres")
        XCTAssertEqual(byDesignation["433"]?.name, "Eros")
        guard case .asteroid(let vesta)? = byDesignation["4"]?.photometry else { return XCTFail("Vesta has photometry") }
        XCTAssertEqual(vesta.absoluteMagnitude, 3.25)
        XCTAssertEqual(vesta.slopeParameter, 0.15)
        XCTAssertEqual(AsteroidMagnitudes.defaultSlopeParameter, 0.15)
    }

    func testTheFileIsSmallAndKeepsTheMinorPlanetCenterHeader() throws {
        let data = try BundledAsteroids.bundledData()
        XCTAssertTrue((30_000...60_000).contains(data.count), "\(data.count) bytes")
        let text = String(decoding: data, as: UTF8.self)
        // The licence of the MPC: the header stays with the data, the Minor Planet Center is credited.
        XCTAssertTrue(text.contains("MINOR PLANET CENTER ORBIT DATABASE (MPCORB)"))
        XCTAssertTrue(text.contains("Software programs may include this datafile amongst their datasets"))
        XCTAssertTrue(text.contains("proper attribution"))
        XCTAssertTrue(text.contains("https://www.minorplanetcenter.org/iau/MPCORB/MPCORB.DAT"))
        XCTAssertTrue(text.contains("Source: https://www.minorplanetcenter.net/iau/MPCORB/MPCORB.DAT.gz"))
        XCTAssertTrue(text.unicodeScalars.allSatisfy { $0.value < 128 }, "plain ASCII")
        XCTAssertEqual(BundledAsteroids.resourceFileName, "asteroids.txt")
    }

    // MARK: Freshness

    func testTheEpochOfTheElementsIsReported() throws {
        // MPC epoch K2669 = 2026 June 9 (Julian Day 2461200.5 in TT).
        let loaded = try loaded()
        let epoch = JulianDate(tt: 2_461_200.5).date
        XCTAssertEqual(loaded.oldestEpoch, epoch)
        XCTAssertEqual(loaded.newestEpoch, epoch)
        XCTAssertTrue(loaded.bodies.allSatisfy { $0.orbit.epochJulianDayTT == 2_461_200.5 })
        XCTAssertEqual(loaded.ageDays(at: loaded.oldestEpoch), 0)
        XCTAssertEqual(loaded.ageDays(at: JulianDate(ut: JulianDate.julianDay(year: 2026, month: 10, day: 18)).date), 131, accuracy: 0.01)
        XCTAssertEqual(loaded.ageDays(at: loaded.oldestEpoch.addingTimeInterval(365 * 86_400)), 365, accuracy: 1e-6)
        XCTAssertLessThan(loaded.ageDays(at: JulianDate(ut: JulianDate.julianDay(year: 2026, month: 1, day: 1)).date), 0)
    }

    // MARK: Against JPL

    func testElementsAgreeWithJPLHorizonsOsculatingElements() throws {
        // Horizons' own osculating elements for the same epoch (Rec #4 and Rec #1, solutions of 2021-Apr-13).
        let byDesignation = try byDesignation()
        for horizons in [CometsHorizonsData.vesta, CometsHorizonsData.ceres] {
            let number = String(horizons.title.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" })
            let body = try XCTUnwrap(byDesignation[number], horizons.title)
            let orbit = body.orbit
            XCTAssertEqual(orbit.epochJulianDayTT, horizons.epochTDB, horizons.title)
            XCTAssertEqual(orbit.perihelionDistanceAU, horizons.perihelionDistance, accuracy: 2e-6, horizons.title)
            XCTAssertEqual(orbit.eccentricity, horizons.eccentricity, accuracy: 2e-6, horizons.title)
            XCTAssertEqual(orbit.inclination, horizons.inclination, accuracy: 2e-4, horizons.title)
            XCTAssertEqual(orbit.longitudeOfAscendingNode, horizons.ascendingNode, accuracy: 2e-4, horizons.title)
            XCTAssertEqual(orbit.argumentOfPerihelion, horizons.argumentOfPerihelion, accuracy: 2e-4, horizons.title)
            XCTAssertEqual(orbit.perihelionJulianDayTT, horizons.perihelionTimeTDB, accuracy: 0.005, horizons.title)
            guard case .asteroid(let magnitudes)? = body.photometry else { return XCTFail(horizons.title) }
            XCTAssertEqual(magnitudes.absoluteMagnitude, horizons.absoluteMagnitude, horizons.title)
        }
    }

    func testPositionsAgreeWithJPLHorizons() throws {
        // Measured (arcseconds): 0.1 at the epoch, 0.3 after 30 days, 5.3 after 120 and 131, 37 after 365, 790 after 731.
        let allowed: [(offset: Double, arcseconds: Double)] = [(0, 1), (30, 2), (120, 10), (131, 12), (365, 80), (731, 1_700)]
        let offsets = CatalogAsteroidReferenceData.offsetsDays
        XCTAssertEqual(allowed.map(\.offset), offsets)
        let byDesignation = try byDesignation()
        var checked = 0
        for reference in CatalogAsteroidReferenceData.references {
            let body = try XCTUnwrap(byDesignation[reference.designation], reference.title)
            XCTAssertEqual(body.title, reference.title)
            for (index, offset) in offsets.enumerated() {
                let date = JulianDate(ut: CatalogAsteroidReferenceData.epochJulianDay + offset)
                let state = try XCTUnwrap(SmallBodyEphemeris.state(of: body, at: date))
                let expected = EquatorialCoordinate(rightAscension: reference.positions[index].rightAscension,
                                                    declination: reference.positions[index].declination)
                let error = state.astrometricJ2000.angle(to: expected.unitVector) * 3600
                let limit = allowed[index].arcseconds
                XCTAssertLessThanOrEqual(error, limit, "\(reference.title) at \(offset) days: \(error) arcsec, allowed \(limit)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 7 * 6)
    }

    func testMagnitudeOfVestaAgreesWithHorizons() throws {
        // Horizons' APmag for Vesta 120 days after the epoch is 6.423 (H = 3.25, G = 0.32); the MPC's G = 0.15 gives 0.2 less.
        let vesta = try XCTUnwrap(try byDesignation()["4"])
        let row = CometsHorizonsData.vesta.rows[2]
        let state = try XCTUnwrap(SmallBodyEphemeris.state(of: vesta, at: JulianDate(ut: CometsHorizonsData.vesta.epochTDB + row.offsetDays)))
        XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), row.magnitude, accuracy: 0.3)
    }

    // MARK: In the catalog

    func testTheBundledAsteroidsWorkInACatalog() throws {
        let bundled = try CatalogFixture.catalog()
        let loaded = try loaded()
        let catalog = bundled.withSmallBodies(loaded.bodies)
        XCTAssertEqual(catalog.smallBodies.count, 216)
        XCTAssertEqual(catalog.objects.count, bundled.objects.count + 216)
        XCTAssertTrue(catalog.smallBodies.allSatisfy { $0.category == .asteroid })
        let queries: [(String, String)] = [
            ("Vesta", "asteroid.4"), ("4 Vesta", "asteroid.4"), ("Ceres", "asteroid.1"), ("Pallas", "asteroid.2"),
            ("Juno", "asteroid.3"), ("Eros", "asteroid.433"), ("Ganymed", "asteroid.1036"), ("Hygiea", "asteroid.10"),
        ]
        for (query, id) in queries {
            XCTAssertEqual(catalog.search(query, limit: 1).map(\.id), [id], query)
        }
        XCTAssertEqual(catalog.smallBodies.first?.id, "asteroid.4", "Vesta has the brightest best case")
        // Listed asteroids are the notable or better ones: peak magnitude 10 or brighter.
        let listed = catalog.smallBodies.filter(\.isListed)
        XCTAssertTrue((80...140).contains(listed.count), "\(listed.count)")
        XCTAssertTrue(try listed.allSatisfy { try XCTUnwrap($0.estimatedPeakMagnitude) <= Prominence.notableSmallBodyMagnitude })
        XCTAssertEqual(catalog.objects(in: .solarSystem).count, 9 + listed.count)
        XCTAssertEqual(Set(catalog.smallBodies.map(\.prominence)), [.showpiece, .prominent, .notable, .obscure])
        // Downloaded elements replace the bundled ones: the last body with an identifier wins.
        let fresher = try XCTUnwrap(loaded.bodies.first { $0.id == "asteroid.4" })
        let replaced = bundled.withSmallBodies(loaded.bodies + [fresher])
        XCTAssertEqual(replaced.smallBodies.count, 216)
    }

    // MARK: Damaged files

    func testDamagedFilesAreRejectedWithATypedError() throws {
        let data = try BundledAsteroids.bundledData()
        let bad: [Data] = [Data(), Data("\n\n".utf8), Data("no header and no orbits\n".utf8), Data(String(repeating: "-", count: 160).utf8)]
        for file in bad {
            XCTAssertThrowsError(try BundledAsteroids.parse(file)) { error in
                guard case CatalogError.brightAsteroidsUnavailable = error else { return XCTFail("\(error)") }
            }
        }
        XCTAssertThrowsError(try BundledAsteroids.parse(Data(count: BundledAsteroids.maximumFileBytes + 1)))
        do {
            _ = try BundledAsteroids.parse(Data())
            XCTFail("an empty file")
        } catch let error as CatalogError {
            XCTAssertTrue(error.description.contains("bright-asteroid"), error.description)
            XCTAssertEqual(error.errorDescription, error.description)
            XCTAssertEqual(error, CatalogError.brightAsteroidsUnavailable(reason: "no valid line (0 rejected)"))
        }
        XCTAssertEqual(CatalogError.brightAsteroidsUnavailable(reason: "x"), CatalogError.brightAsteroidsUnavailable(reason: "x"))

        // A damaged line costs that line only.
        let text = String(decoding: data, as: UTF8.self)
        let damaged = try BundledAsteroids.parse(Data((text + "garbage line that is not an orbit\n" + "00001 not a number\n").utf8))
        XCTAssertEqual(damaged.bodies.count, 216)
        XCTAssertEqual(damaged.rejectedLineCount, 2)
        // Windows line endings, no final line break and a duplicated record are accepted.
        let trimmed = String(text.reversed().drop { $0 == "\n" }.reversed())
        let windows = try BundledAsteroids.parse(Data(trimmed.replacingOccurrences(of: "\n", with: "\r\n").utf8))
        XCTAssertEqual(windows.bodies.count, 216)
        XCTAssertEqual(windows.rejectedLineCount, 0)
        let lastLine = try XCTUnwrap(trimmed.split(separator: "\n", omittingEmptySubsequences: false).last)
        let duplicated = try BundledAsteroids.parse(Data((text + lastLine + "\n").utf8))
        XCTAssertEqual(duplicated.bodies.count, 216)
        XCTAssertEqual(duplicated.rejectedLineCount, 1)
    }
}
