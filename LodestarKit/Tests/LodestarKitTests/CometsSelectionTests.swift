import XCTest
@testable import LodestarKit

/// Selection of the bright comets and asteroids from a list of orbit records.
final class CometsSelectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_324_800) // 2026-10-18T12:00:00Z
    private let monthEnd = Date(timeIntervalSince1970: 1_792_324_800 + 31 * 86_400) // 2026-11-18T12:00:00Z

    private func fixtureComets() throws -> [SmallBody] {
        try [
            CometsTestData.cometHaleBopp, CometsTestData.cometTsuchinshanAtlas, CometsTestData.cometPonsBrooks,
            CometsTestData.cometHalley, CometsTestData.cometEncke, CometsTestData.cometBielaA, CometsTestData.cometPerrineMrkos,
            CometsTestData.cometSchwassmannWachmann3Bt, CometsTestData.cometIkeyaMurakamiB, CometsTestData.cometOumuamua,
            CometsTestData.cometBorisov, CometsTestData.cometAtlas3i, CometsTestData.cometSidingSpring,
            CometsTestData.cometAsteroidLike, CometsTestData.cometUnnamedPeriodic, CometsTestData.cometHartleyIras,
            CometsTestData.cometGehrels, CometsTestData.cometSchwassmannWachmann, CometsTestData.cometBernardinelliBernstein,
            CometsTestData.cometWierzchos, CometsTestData.cometLeonard,
        ].map { try CometElementsParser.parseLine($0) }
    }

    private func fixtureAsteroids() throws -> [SmallBody] {
        try [
            CometsTestData.asteroidCeres, CometsTestData.asteroidVesta, CometsTestData.asteroidEros,
            CometsTestData.asteroidApophis, CometsTestData.asteroidBennu, CometsTestData.asteroidYr42024,
            CometsTestData.asteroidUnknownH, CometsTestData.asteroidNumberedUnnamed,
        ].map { try MinorPlanetElementsParser.parseLine($0) }
    }

    /// The magnitude of every sample of `body` (infinite where it cannot be computed or the elongation is too small).
    private func sampledMagnitudes(_ body: SmallBody, _ start: Date, _ days: Double, _ count: Int, _ minimumElongation: Double) -> [Double] {
        (0..<count).map { index in
            let julianDate = JulianDate(date: start).addingDays(count > 1 ? days * Double(index) / Double(count - 1) : 0.0)
            let state = SmallBodyEphemeris.state(of: body, at: index == 0 ? JulianDate(date: start) : julianDate)
            guard let state, let magnitude = state.apparentMagnitude, state.elongation >= minimumElongation else {
                return Double.infinity
            }
            return magnitude
        }
    }

    // MARK: Real records

    func testBrightCometsNowOnTheFixtureSet() throws {
        let comets = try fixtureComets()
        let bright = SmallBodySelection.brightNow(in: comets, at: now, magnitudeLimit: 14.0)
        // On 2026 October 18 only 161P/Hartley-IRAS (9.7), P/2026 R2 (Leonard, 13.3) and 78P/Gehrels (13.9) are brighter than 14.
        XCTAssertEqual(bright.map(\.body.id), ["comet.161P", "comet.P/2026 R2", "comet.78P"])
        XCTAssertEqual(bright[0].peakMagnitude, 9.72, accuracy: 0.01)
        XCTAssertEqual(bright[1].peakMagnitude, 13.27, accuracy: 0.01)
        XCTAssertEqual(bright[0].peakDate.timeIntervalSince1970.rounded(.down), now.timeIntervalSince1970)
        XCTAssertTrue(bright.allSatisfy { $0.peak.elongation >= 25.0 })
        XCTAssertEqual(bright.map(\.peakMagnitude), bright.map(\.peakMagnitude).sorted())
        XCTAssertEqual(bright[0].peak.elongation, 110.3, accuracy: 0.1)
    }

    func testBrightNowAgreesWithABruteForceScanOfAllRecords() throws {
        let bodies = try fixtureComets() + fixtureAsteroids()
        for limit in [9.0, 12.0, 15.0, 30.0] {
            let selected = SmallBodySelection.brightNow(in: bodies, at: now, magnitudeLimit: limit, minimumElongation: 20.0)
            var expected = [(id: String, magnitude: Double)]()
            for body in bodies {
                guard let state = SmallBodyEphemeris.state(of: body, at: JulianDate(date: now)), let magnitude = state.apparentMagnitude else { continue }
                if magnitude <= limit && state.elongation >= 20.0 { expected.append((body.id, magnitude)) }
            }
            expected.sort { $0.magnitude != $1.magnitude ? $0.magnitude < $1.magnitude : $0.id < $1.id }
            XCTAssertEqual(selected.map(\.body.id), expected.map(\.id), "limit \(limit)")
            XCTAssertEqual(selected.map(\.peakMagnitude), expected.map(\.magnitude), "limit \(limit)")
        }
    }

    func testBrightestDuringAMonthOnTheFixtureSet() throws {
        let bodies = try fixtureComets() + fixtureAsteroids()
        let month = SmallBodySelection.brightest(in: bodies, during: DateInterval(start: now, end: monthEnd), magnitudeLimit: 10.0)
        // Vesta (6.4 at opposition on October 18) leads; Ceres, Pallas-like asteroids and 161P follow.
        XCTAssertEqual(month.first?.body.id, "asteroid.4")
        XCTAssertTrue(try XCTUnwrap(month.first).peakMagnitude < 6.6)
        XCTAssertTrue(month.contains { $0.body.id == "comet.161P" })
        XCTAssertEqual(month.map(\.peakMagnitude), month.map(\.peakMagnitude).sorted())
        for entry in month {
            XCTAssertTrue(entry.peakMagnitude <= 10.0)
            XCTAssertTrue(entry.peakDate >= now && entry.peakDate <= monthEnd, entry.body.id)
            XCTAssertTrue(entry.peak.elongation >= 25.0)
        }
        // The peak is at least as bright as the state at the first and last instant.
        for entry in month {
            for edge in [now, monthEnd] {
                let state = try XCTUnwrap(SmallBodyEphemeris.state(of: entry.body, at: JulianDate(date: edge)))
                if state.elongation >= 25.0 {
                    let edgeMagnitude = try XCTUnwrap(state.apparentMagnitude)
                    XCTAssertTrue(entry.peakMagnitude <= edgeMagnitude + 1e-9, entry.body.id)
                }
            }
        }
    }

    func testPeakBetweenSamplesIsRefined() throws {
        // C/2023 A3 brightened towards the Sun in early October 2024; with daily samples the peak falls between two of them.
        let item = CometsHorizonsData.c2023a3
        let orbit = try XCTUnwrap(SmallBodyElements(
            perihelionDistanceAU: item.perihelionDistance, eccentricity: item.eccentricity, inclination: item.inclination,
            argumentOfPerihelion: item.argumentOfPerihelion, longitudeOfAscendingNode: item.ascendingNode,
            perihelionJulianDayTT: item.perihelionTimeTDB, epochJulianDayTT: item.epochTDB))
        let atlas = try XCTUnwrap(SmallBody(
            designation: "C/2023 A3", kind: .comet, orbit: orbit,
            photometry: .comet(try XCTUnwrap(CometMagnitudes(totalMagnitude: item.absoluteMagnitude, totalSlope: item.slope)))))
        let start = Date(timeIntervalSince1970: 1_728_023_400) // 2024-10-04T06:30:00Z
        let interval = DateInterval(start: start, duration: 26.0 * 86_400.0)
        let result = SmallBodySelection.brightest(in: [atlas], during: interval, magnitudeLimit: 8.0, minimumElongation: 10.0)
        XCTAssertEqual(result.count, 1)
        let peak = try XCTUnwrap(result.first)
        // Dense scan, every 10 minutes.
        var bestMagnitude = Double.infinity
        var bestTime = start
        var seconds = 0.0
        while seconds <= 26.0 * 86_400.0 {
            let instant = start.addingTimeInterval(seconds)
            let state = try XCTUnwrap(SmallBodyEphemeris.state(of: atlas, at: JulianDate(date: instant)))
            let magnitude = try XCTUnwrap(state.apparentMagnitude)
            if state.elongation >= 10.0 && magnitude < bestMagnitude {
                bestMagnitude = magnitude
                bestTime = instant
            }
            seconds += 600.0
        }
        XCTAssertEqual(peak.peakMagnitude, bestMagnitude, accuracy: 0.002)
        XCTAssertTrue(abs(peak.peakDate.timeIntervalSince(bestTime)) < 6 * 3600.0, "peak \(peak.peakDate), dense \(bestTime)")
        // It is brighter than every daily sample.
        let daily = sampledMagnitudes(atlas, start, 26.0, 27, 10.0)
        XCTAssertTrue(peak.peakMagnitude <= (daily.min() ?? 0.0) + 1e-12)
    }

    // MARK: Synthetic records

    func testPrefilterBoundIsNeverBrighterThanTheTrueMinimum() throws {
        let bodies = SyntheticOrbits(seed: 20_261_018).bodies(300)
        var excluded = 0
        for offset in [0.0, 400.0, -700.0] {
            let start = JulianDate(ut: 2_461_330.5 + offset)
            let end = start.addingDays(40.0)
            for body in bodies {
                let bound = SmallBodySelection.brightestPossible(for: body, startTT: start.tt, endTT: end.tt)
                var minimum = Double.infinity
                for step in 0...80 {
                    guard let state = SmallBodyEphemeris.state(of: body, at: start.addingDays(Double(step) * 0.5)) else { continue }
                    minimum = min(minimum, state.apparentMagnitude ?? Double.infinity)
                }
                XCTAssertTrue(bound <= minimum, "\(body.id) from \(offset): bound \(bound), true minimum \(minimum)")
                if bound > 10.0 { excluded += 1 }
            }
        }
        // The bound is useful: most of the records are excluded without computing a position.
        XCTAssertTrue(excluded > 300, "only \(excluded) of 900 excluded")
    }

    /// The lower bound of the magnitude for distances from the Sun between `nearest` and `farthest` (AU), computed independently.
    private func bound(_ absolute: Double, _ slope: Double?, _ nearest: Double, _ farthest: Double) -> Double {
        let earthDistance = max(0.001, max(nearest - 1.0169, 0.9831 - farthest))
        if let slope {
            return absolute + 5 * log10(earthDistance) + slope * log10(nearest) - 0.35
        }
        return absolute + 5 * log10(nearest * earthDistance) - 0.35
    }

    func testPrefilterBoundForSpecialOrbits() throws {
        let orbit = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: 0.5, eccentricity: 1.0, inclination: 20.0, argumentOfPerihelion: 30.0,
                                                  longitudeOfAscendingNode: 40.0, perihelionJulianDayTT: 2_461_340.0))
        let photometry = SmallBodyPhotometry.comet(try XCTUnwrap(CometMagnitudes(totalMagnitude: 8.0, totalSlope: 10.0)))
        let parabolic = try XCTUnwrap(SmallBody(designation: "P", kind: .comet, orbit: orbit, photometry: photometry))
        // Perihelion (r = 0.5) lies inside the window; the ends are farther from the Sun.
        let inside = SmallBodySelection.brightestPossible(for: parabolic, startTT: 2_461_330.0, endTT: 2_461_350.0)
        let farthest = max(try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_461_330.0)),
                           try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_461_350.0)))
        XCTAssertEqual(inside, bound(8.0, 10.0, 0.5, farthest), accuracy: 1e-9)
        // After perihelion r only grows: the distance at the start is the smallest.
        let after = SmallBodySelection.brightestPossible(for: parabolic, startTT: 2_461_345.0, endTT: 2_461_350.0)
        let rStart = try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_461_345.0))
        let rEnd = try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_461_350.0))
        XCTAssertEqual(after, bound(8.0, 10.0, rStart, rEnd), accuracy: 1e-9)
        // Far from the Sun the Earth is at least r - 1.0169 away.
        let far = SmallBodySelection.brightestPossible(for: parabolic, startTT: 2_461_340.0 + 4_000.0, endTT: 2_461_340.0 + 4_010.0)
        let rFar = try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_461_340.0 + 4_000.0))
        XCTAssertTrue(rFar > 10.0 && far > 20.0, "far \(far) at \(rFar)")
        // No photometry: nothing to select.
        let bare = try XCTUnwrap(SmallBody(designation: "B", kind: .comet, orbit: orbit))
        XCTAssertEqual(SmallBodySelection.brightestPossible(for: bare, startTT: 2_461_330.0, endTT: 2_461_350.0), Double.infinity)
        // Beyond the span of an unbound orbit no bound can be given.
        XCTAssertEqual(SmallBodySelection.brightestPossible(for: parabolic, startTT: 2_461_340.0 + 60_000.0, endTT: 2_461_340.0 + 60_010.0), -Double.infinity)
        XCTAssertEqual(SmallBodySelection.brightestPossible(for: parabolic, startTT: 2_461_340.0, endTT: 2_461_340.0 + 60_000.0), -Double.infinity)
        // An elliptic orbit that completes several revolutions in the window passes perihelion and aphelion.
        let short = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: 1.0, eccentricity: 0.1, inclination: 5.0, argumentOfPerihelion: 0.0,
                                                  longitudeOfAscendingNode: 0.0, perihelionJulianDayTT: 2_461_000.0)) // period 1.2 years
        let asteroid = try XCTUnwrap(SmallBody(designation: "A", kind: .asteroid, orbit: short,
                                               photometry: .asteroid(try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 10.0, slopeParameter: 0.15)))))
        let aphelion = try XCTUnwrap(short.aphelionDistanceAU)
        XCTAssertEqual(aphelion, 1.222, accuracy: 1e-3)
        XCTAssertEqual(SmallBodySelection.brightestPossible(for: asteroid, startTT: 2_461_100.0, endTT: 2_462_100.0), bound(10.0, nil, 1.0, aphelion), accuracy: 1e-9)
        // A window that contains neither extremum is bounded by its end points.
        let r0 = try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: short, at: 2_461_050.0))
        let r1 = try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: short, at: 2_461_060.0))
        XCTAssertEqual(SmallBodySelection.brightestPossible(for: asteroid, startTT: 2_461_050.0, endTT: 2_461_060.0), bound(10.0, nil, min(r0, r1), max(r0, r1)), accuracy: 1e-9)
        // Perihelion only (aphelion is half a period later, outside the window).
        let periodDays = try XCTUnwrap(short.periodDays)
        let aroundPerihelion = SmallBodySelection.brightestPossible(for: asteroid, startTT: 2_461_000.0 + periodDays - 5, endTT: 2_461_000.0 + periodDays + 5)
        let rBefore = try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: short, at: 2_461_000.0 + periodDays - 5))
        XCTAssertEqual(aroundPerihelion, bound(10.0, nil, 1.0, rBefore), accuracy: 1e-9)
        // Negative slope: the farthest distance gives the brightest value.
        let inverted = SmallBodyPhotometry.comet(try XCTUnwrap(CometMagnitudes(totalMagnitude: 8.0, totalSlope: -2.0)))
        let odd = try XCTUnwrap(SmallBody(designation: "N", kind: .comet, orbit: orbit, photometry: inverted))
        let oddBound = SmallBodySelection.brightestPossible(for: odd, startTT: 2_461_345.0, endTT: 2_461_350.0)
        let earthDistance = max(0.001, max(rStart - 1.0169, 0.9831 - rEnd))
        XCTAssertEqual(oddBound, 8.0 + 5 * log10(earthDistance) - 2.0 * log10(rEnd) - 0.35, accuracy: 1e-9)
    }

    func testSelectionEqualsABruteForceScan() throws {
        let bodies = SyntheticOrbits(seed: 777).bodies(400)
        let interval = DateInterval(start: now, end: monthEnd)
        let days = interval.duration / 86_400.0
        let count = 32
        for limit in [8.0, 10.0, 12.0] {
            let selected = SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: limit, maximumCount: 1000)
            let byId = Dictionary(uniqueKeysWithValues: selected.map { ($0.body.id, $0) })
            var sampledQualifiers = 0
            for body in bodies {
                let sampled = sampledMagnitudes(body, now, days, count, 25.0).min() ?? Double.infinity
                let entry = byId[body.id]
                if sampled <= limit {
                    sampledQualifiers += 1
                    let found = try XCTUnwrap(entry, "\(body.id) sampled at \(sampled)")
                    XCTAssertTrue(found.peakMagnitude <= sampled + 1e-9, "\(body.id): \(found.peakMagnitude) vs \(sampled)")
                }
                if let entry {
                    XCTAssertTrue(entry.peakMagnitude <= limit, body.id)
                    XCTAssertTrue(entry.peak.elongation >= 25.0, body.id)
                    // The refined peak is not brighter than a dense scan finds (hourly samples, 0.005 mag margin).
                    var dense = Double.infinity
                    for hour in 0...Int(days * 24) {
                        guard let state = SmallBodyEphemeris.state(of: body, at: JulianDate(date: now).addingDays(Double(hour) / 24.0)) else { continue }
                        if state.elongation >= 25.0 { dense = min(dense, state.apparentMagnitude ?? Double.infinity) }
                    }
                    XCTAssertTrue(entry.peakMagnitude >= dense - 0.01, "\(body.id): \(entry.peakMagnitude) vs dense \(dense)")
                }
            }
            XCTAssertTrue(selected.count >= sampledQualifiers)
        }
    }

    func testResultsAreSortedCappedAndFiltered() {
        let bodies = SyntheticOrbits(seed: 4242).bodies(300)
        let interval = DateInterval(start: now, end: monthEnd)
        let all = SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: 12.0, maximumCount: 1000)
        XCTAssertTrue(all.count > 10, "only \(all.count) bright bodies")
        XCTAssertEqual(all.map(\.peakMagnitude), all.map(\.peakMagnitude).sorted())
        XCTAssertEqual(all.count, Set(all.map(\.body.id)).count)
        let capped = SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: 12.0, maximumCount: 5)
        XCTAssertEqual(capped.map(\.body.id), all.prefix(5).map(\.body.id))
        XCTAssertEqual(SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: 12.0, maximumCount: 0), [])
        XCTAssertEqual(SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: 12.0, maximumCount: -3), [])
        let comets = SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: 12.0, kind: .comet, maximumCount: 1000)
        let asteroids = SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: 12.0, kind: .asteroid, maximumCount: 1000)
        XCTAssertTrue(comets.allSatisfy { $0.body.kind == .comet })
        XCTAssertTrue(asteroids.allSatisfy { $0.body.kind == .asteroid })
        XCTAssertEqual(Set(all.map(\.body.id)), Set((comets + asteroids).map(\.body.id)))
        // A stricter elongation limit never adds bodies.
        let wide = SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: 12.0, minimumElongation: 90.0, maximumCount: 1000)
        XCTAssertTrue(Set(wide.map(\.body.id)).subtracting(Set(all.map(\.body.id))).isEmpty)
        XCTAssertTrue(wide.allSatisfy { $0.peak.elongation >= 90.0 })
        XCTAssertEqual(SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: 12.0, minimumElongation: 180.0, maximumCount: 1000), [])
        XCTAssertEqual(SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: -30.0, maximumCount: 1000), [])
    }

    func testDegenerateArguments() throws {
        let bodies = try fixtureComets()
        let interval = DateInterval(start: now, end: monthEnd)
        XCTAssertEqual(SmallBodySelection.brightest(in: [], during: interval), [])
        XCTAssertEqual(SmallBodySelection.brightest(in: bodies, during: interval, magnitudeLimit: Double.nan), [])
        XCTAssertEqual(SmallBodySelection.brightest(in: bodies, during: interval, minimumElongation: Double.nan), [])
        XCTAssertEqual(SmallBodySelection.brightNow(in: bodies, at: now, magnitudeLimit: Double.nan), [])
        // A zero-length interval is the same as "now".
        let current = SmallBodySelection.brightNow(in: bodies, at: now, magnitudeLimit: 14.0)
        let zero = SmallBodySelection.brightest(in: bodies, during: DateInterval(start: now, duration: 0.0), magnitudeLimit: 14.0)
        XCTAssertEqual(current.map(\.body.id), zero.map(\.body.id))
        XCTAssertEqual(current.map(\.peakMagnitude), zero.map(\.peakMagnitude))
        // An elongation limit above 180 is clamped to 180: nothing qualifies.
        XCTAssertEqual(SmallBodySelection.brightNow(in: bodies, at: now, magnitudeLimit: 30.0, minimumElongation: 500.0), [])
        // A negative elongation limit is clamped to 0.
        XCTAssertFalse(SmallBodySelection.brightNow(in: bodies, at: now, magnitudeLimit: 30.0, minimumElongation: -50.0).isEmpty)
        // Records without photometry are skipped.
        let orbit = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: 0.3, eccentricity: 1.0, inclination: 20.0, argumentOfPerihelion: 30.0,
                                                  longitudeOfAscendingNode: 40.0, perihelionJulianDayTT: 2_461_330.0))
        let bare = try XCTUnwrap(SmallBody(designation: "B", kind: .comet, orbit: orbit))
        XCTAssertEqual(SmallBodySelection.brightNow(in: [bare], at: now, magnitudeLimit: 99.0), [])
        // A long interval is sampled coarsely but still works.
        let year = SmallBodySelection.brightest(in: bodies, during: DateInterval(start: now, duration: 365.0 * 86_400.0), magnitudeLimit: 10.0)
        XCTAssertFalse(year.isEmpty)
        XCTAssertEqual(SmallBodySelection.maximumSampleCount, 64)
    }

    func testPeakStateIsConsistentWithTheBody() throws {
        let bodies = try fixtureAsteroids()
        let result = SmallBodySelection.brightest(in: bodies, during: DateInterval(start: now, end: monthEnd), magnitudeLimit: 11.0)
        XCTAssertFalse(result.isEmpty)
        for entry in result {
            XCTAssertEqual(entry.body, entry.peak.body)
            let again = try XCTUnwrap(SmallBodyEphemeris.state(of: entry.body, at: entry.peak.julianDate))
            XCTAssertEqual(entry.peak, again)
            XCTAssertEqual(entry.peak.apparentMagnitude, entry.peakMagnitude)
            XCTAssertEqual(entry.peak.julianDate.date, entry.peakDate)
        }
        XCTAssertNil(result.first { $0.body.id == "asteroid.1991 TT" }) // no H, no photometry
    }

    // MARK: Cost

    func testThousandsOfRecordsAreFast() {
        let bodies = SyntheticOrbits(seed: 99).bodies(5_000)
        let started = Date()
        let month = SmallBodySelection.brightest(in: bodies, during: DateInterval(start: now, end: monthEnd), magnitudeLimit: 10.0)
        let monthSeconds = Date().timeIntervalSince(started)
        let startedNow = Date()
        let current = SmallBodySelection.brightNow(in: bodies, at: now, magnitudeLimit: 10.0)
        let nowSeconds = Date().timeIntervalSince(startedNow)
        XCTAssertTrue(!month.isEmpty && !current.isEmpty)
        XCTAssertTrue(monthSeconds < 3.0, "5000 records over a month took \(monthSeconds) s")
        XCTAssertTrue(nowSeconds < 1.5, "5000 records now took \(nowSeconds) s")
    }

    func testCompareIdentifiersUsesScalarOrder() throws {
        // Equal magnitudes are ordered by identifier; identifiers are compared scalar by scalar.
        let orbit = try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: 2.0, eccentricity: 0.1, inclination: 5.0, argumentOfPerihelion: 10.0,
                                                  longitudeOfAscendingNode: 20.0, perihelionJulianDayTT: 2_461_330.0))
        let photometry = SmallBodyPhotometry.comet(try XCTUnwrap(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 10.0)))
        let bodies = try ["C/B", "C/A", "C/AA", "C/\u{00E9}"].map { try XCTUnwrap(SmallBody(designation: $0, kind: .comet, orbit: orbit, photometry: photometry)) }
        let result = SmallBodySelection.brightNow(in: bodies, at: now, magnitudeLimit: 30.0, minimumElongation: 0.0)
        XCTAssertEqual(result.map(\.body.id), ["comet.C/A", "comet.C/AA", "comet.C/B", "comet.C/\u{00E9}"])
    }
}
