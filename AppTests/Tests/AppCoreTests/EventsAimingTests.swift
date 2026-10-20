import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Dates, events and observers for the tests of `EventsAiming.swift` and `EventsCalculator.swift`.
private enum EventsAimingFixtures {
    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: .nan)
    }

    /// On the equator at the Greenwich meridian.
    static let equator = Observer(location: GeographicLocation(latitude: 0, longitude: 0, elevation: 0))

    /// 2026-08-28 is the day of a full Moon (at 04:18 UTC), so the Moon stands near the meridian at the local midnight,
    /// 00:18 UTC, about 78 degrees high on the equator, and near the opposite point 12 hours later, about 82 degrees below
    /// the horizon.
    static let moonUp = date("2026-08-28T00:18:00Z")
    static let moonDown = date("2026-08-28T12:18:00Z")

    static let moment = date("2026-08-12T17:46:00Z")

    static func event(_ details: EventDetails, at moment: Date = EventsAimingFixtures.moment,
                      visibility: EventVisibility? = nil) -> AstronomicalEvent {
        AstronomicalEvent(date: moment, details: details, visibility: visibility)
    }

    static func visibility(bestTime: Date?) -> EventVisibility {
        EventVisibility(altitude: 30, azimuth: 90, sunAltitude: -20, isDark: true, bestWindow: nil, bestTime: bestTime,
                        darknessLimit: -18, contacts: [])
    }

    static func peak(of shower: MeteorShower, fraction: Double) -> MeteorShowerPeak {
        MeteorShowerPeak(shower: shower, activityStart: date("2026-07-17T00:00:00Z"), activityEnd: date("2026-08-25T00:00:00Z"),
                         moonIlluminatedFraction: fraction, radiant: shower.radiant)
    }

    static let testShower = MeteorShower(
        code: "TST", iauNumber: 999, name: "Testids", activityStartMonth: 7, activityStartDay: 17, activityEndMonth: 8,
        activityEndDay: 24, peakSolarLongitude: 140, zhr: 100, radiant: EquatorialCoordinate(rightAscension: 48, declination: 58),
        radiantDriftRightAscension: 1.42, radiantDriftDeclination: 0.2, velocity: 59, populationIndex: 2.2)

    static func meteor(fraction: Double, at moment: Date, visibility: EventVisibility? = nil) -> AstronomicalEvent {
        event(.meteorShower(peak(of: testShower, fraction: fraction)), at: moment, visibility: visibility)
    }

    static func conjunction(_ first: ConjunctionTarget, _ second: ConjunctionTarget) -> AstronomicalEvent {
        event(.conjunction(Conjunction(first: first, second: second, separation: 2, solarElongation: 90,
                                       occultationPossible: false, topocentric: nil)))
    }
}

// MARK: - From a subject to an object

final class EventsAimingTests: XCTestCase {
    private typealias F = EventsAimingFixtures

    private static let loaded = Result { try Catalog.loadBundled() }

    private func bundledCatalog() throws -> Catalog {
        try Self.loaded.get()
    }

    /// The place of Spica moved `degrees` to the north in declination (the right ascension is kept).
    private func spica(movedBy degrees: Double) -> EquatorialCoordinate {
        let place = ReferenceStar.spica.position
        return EquatorialCoordinate(rightAscension: place.rightAscension, declination: place.declination + degrees)
    }

    // MARK: Identifiers

    func testTheCatalogIdentifiersOfTheSolarSystemBodies() {
        XCTAssertEqual(EventsAiming.identifier(of: .sun), "sun")
        XCTAssertEqual(EventsAiming.identifier(of: .moon), "moon")
        XCTAssertEqual(EventsAiming.identifier(of: .mercury), "planet.mercury")
        XCTAssertEqual(EventsAiming.identifier(of: .venus), "planet.venus")
        XCTAssertEqual(EventsAiming.identifier(of: .mars), "planet.mars")
        XCTAssertEqual(EventsAiming.identifier(of: .jupiter), "planet.jupiter")
        XCTAssertEqual(EventsAiming.identifier(of: .saturn), "planet.saturn")
        XCTAssertEqual(EventsAiming.identifier(of: .uranus), "planet.uranus")
        XCTAssertEqual(EventsAiming.identifier(of: .neptune), "planet.neptune")
    }

    // MARK: Solar-system bodies

    func testEveryBodyIsFoundInTheBundledCatalog() throws {
        let catalog = try bundledCatalog()
        for body in SolarSystemBody.allCases {
            let object = EventsAiming.object(for: .body(body), in: catalog)
            XCTAssertEqual(object?.id, EventsAiming.identifier(of: body), body.displayName)
            XCTAssertEqual(object?.name, body.displayName, body.displayName)
        }
    }

    func testABodyHasNoObjectWhileTheCatalogIsNotLoaded() {
        for body in SolarSystemBody.allCases {
            XCTAssertNil(EventsAiming.object(for: .body(body), in: nil), body.displayName)
        }
    }

    // MARK: Reference stars

    func testEveryBrightReferenceStarIsFoundInTheCatalog() throws {
        let catalog = try bundledCatalog()
        for star in [ReferenceStar.regulus, .spica, .antares, .aldebaran] {
            let subject = EventsCalculator.AimSubject.fixed(name: star.displayName, star.position)
            let object = try XCTUnwrap(EventsAiming.object(for: subject, in: catalog), star.displayName)
            XCTAssertFalse(object.id.hasPrefix("custom."), star.displayName)
            XCTAssertEqual(object.name, star.displayName)
            let place = try XCTUnwrap(object.j2000, star.displayName)
            XCTAssertLessThanOrEqual(EventsAiming.separation(place, star.position), EventsAiming.matchRadius, star.displayName)
        }
    }

    func testThePleiadesAreFoundAsTheCatalogClusterByTheirCatalogName() throws {
        let catalog = try bundledCatalog()
        let subject = EventsCalculator.AimSubject.fixed(name: "Pleiades", ReferenceStar.pleiades.position)
        let object = try XCTUnwrap(EventsAiming.object(for: subject, in: catalog))
        XCTAssertTrue(object.isDeepSky, object.id)
        let place = try XCTUnwrap(object.j2000)
        XCTAssertLessThanOrEqual(EventsAiming.separation(place, ReferenceStar.pleiades.position), EventsAiming.matchRadius)
    }

    func testTheEventsNameForThePleiadesStillAimsAtThePleiades() throws {
        // Whether the catalog knows the cluster by this name or a custom target is made, the object is at the place.
        let catalog = try bundledCatalog()
        let star = ReferenceStar.pleiades
        let subject = EventsCalculator.AimSubject.fixed(name: star.displayName, star.position)
        let object = try XCTUnwrap(EventsAiming.object(for: subject, in: catalog))
        let place = try XCTUnwrap(object.j2000)
        XCTAssertLessThanOrEqual(EventsAiming.separation(place, star.position), EventsAiming.matchRadius)
    }

    func testAPlaceJustInsideTheMatchRadiusStillStandsForTheStar() throws {
        let catalog = try bundledCatalog()
        let subject = EventsCalculator.AimSubject.fixed(name: "Spica", spica(movedBy: 0.9))
        let object = try XCTUnwrap(EventsAiming.object(for: subject, in: catalog))
        XCTAssertFalse(object.id.hasPrefix("custom."), object.id)
        XCTAssertEqual(object.name, "Spica")
    }

    func testAPlaceJustOutsideTheMatchRadiusBecomesACustomTarget() throws {
        let catalog = try bundledCatalog()
        let place = spica(movedBy: 1.1)
        let object = try XCTUnwrap(EventsAiming.object(for: .fixed(name: "Spica", place), in: catalog))
        XCTAssertTrue(object.id.hasPrefix("custom."), object.id)
        XCTAssertEqual(object.category, .custom)
        XCTAssertEqual(object.name, "Spica")
        let kept = try XCTUnwrap(object.j2000)
        XCTAssertEqual(kept.rightAscension, place.rightAscension, accuracy: 1e-9)
        XCTAssertEqual(kept.declination, place.declination, accuracy: 1e-9)
    }

    func testANameFromThePlaceFarAwayBecomesACustomTarget() throws {
        let catalog = try bundledCatalog()
        let object = try XCTUnwrap(EventsAiming.object(for: .fixed(name: "Spica", EquatorialCoordinate(rightAscension: 0, declination: 60)),
                                                       in: catalog))
        XCTAssertTrue(object.id.hasPrefix("custom."), object.id)
        XCTAssertEqual(object.name, "Spica")
    }

    func testAnUnknownNameBecomesACustomTargetAtThePlace() throws {
        let catalog = try bundledCatalog()
        let place = EquatorialCoordinate(rightAscension: 10, declination: -80)
        let object = try XCTUnwrap(EventsAiming.object(for: .fixed(name: "Zzyzx Nonexistent Star", place), in: catalog))
        XCTAssertTrue(object.id.hasPrefix("custom."), object.id)
        XCTAssertEqual(object.name, "Zzyzx Nonexistent Star")
        XCTAssertEqual(object.j2000?.rightAscension ?? .nan, 10, accuracy: 1e-9)
        XCTAssertEqual(object.j2000?.declination ?? .nan, -80, accuracy: 1e-9)
    }

    func testAFixedPlaceWithoutACatalogBecomesACustomTarget() throws {
        let place = ReferenceStar.spica.position
        let object = try XCTUnwrap(EventsAiming.object(for: .fixed(name: "Spica", place), in: nil))
        XCTAssertTrue(object.id.hasPrefix("custom."), object.id)
        XCTAssertEqual(object.category, .custom)
        XCTAssertEqual(object.name, "Spica")
        XCTAssertEqual(object.j2000, place)
    }

    // MARK: Radiants

    func testARadiantIsAlwaysACustomTarget() throws {
        let place = EquatorialCoordinate(rightAscension: 48, declination: 58)
        let catalog = try bundledCatalog()
        let withCatalog = try XCTUnwrap(EventsAiming.object(for: .radiant(name: "Perseids radiant", place), in: catalog))
        let withoutCatalog = try XCTUnwrap(EventsAiming.object(for: .radiant(name: "Perseids radiant", place), in: nil))
        for object in [withCatalog, withoutCatalog] {
            XCTAssertTrue(object.id.hasPrefix("custom."), object.id)
            XCTAssertEqual(object.category, .custom)
            XCTAssertEqual(object.name, "Perseids radiant")
            XCTAssertEqual(object.j2000, place)
        }
    }

    func testEachCustomTargetGetsItsOwnIdentifier() throws {
        let place = EquatorialCoordinate(rightAscension: 48, declination: 58)
        let first = try XCTUnwrap(EventsAiming.object(for: .radiant(name: "Perseids radiant", place), in: nil))
        let second = try XCTUnwrap(EventsAiming.object(for: .radiant(name: "Perseids radiant", place), in: nil))
        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: Separation

    func testTheSeparationOfAPlaceFromItselfIsZero() {
        let place = EquatorialCoordinate(rightAscension: 123.456, declination: 45.678)
        let separation = EventsAiming.separation(place, place)
        XCTAssertTrue(separation.isFinite)
        XCTAssertEqual(separation, 0, accuracy: 1e-5)
    }

    func testTheSeparationOfPlacesAQuarterOfTheSkyApartIs90Degrees() {
        let origin = EquatorialCoordinate(rightAscension: 0, declination: 0)
        XCTAssertEqual(EventsAiming.separation(origin, EquatorialCoordinate(rightAscension: 90, declination: 0)), 90, accuracy: 1e-9)
        XCTAssertEqual(EventsAiming.separation(origin, EquatorialCoordinate(rightAscension: 0, declination: 90)), 90, accuracy: 1e-9)
    }

    func testTheSeparationOfOppositePlacesIs180Degrees() {
        let origin = EquatorialCoordinate(rightAscension: 0, declination: 0)
        XCTAssertEqual(EventsAiming.separation(origin, EquatorialCoordinate(rightAscension: 180, declination: 0)), 180, accuracy: 1e-6)
        XCTAssertEqual(EventsAiming.separation(EquatorialCoordinate(rightAscension: 0, declination: 90),
                                               EquatorialCoordinate(rightAscension: 0, declination: -90)), 180, accuracy: 1e-6)
    }

    func testTheSeparationAcrossTheRightAscensionWrapIsShort() {
        XCTAssertEqual(EventsAiming.separation(EquatorialCoordinate(rightAscension: 359, declination: 0),
                                               EquatorialCoordinate(rightAscension: 1, declination: 0)), 2, accuracy: 1e-9)
    }

    func testTheSeparationAlongADeclinationCircleIsTheDifferenceInDeclination() {
        XCTAssertEqual(EventsAiming.separation(EquatorialCoordinate(rightAscension: 10, declination: 10),
                                               EquatorialCoordinate(rightAscension: 10, declination: 11)), 1, accuracy: 1e-9)
    }

    func testTheSeparationIsSymmetric() {
        let a = EquatorialCoordinate(rightAscension: 12, declination: -40)
        let b = EquatorialCoordinate(rightAscension: 200, declination: 33)
        XCTAssertEqual(EventsAiming.separation(a, b), EventsAiming.separation(b, a), accuracy: 1e-9)
    }
}

// MARK: - The calculator's framing and aiming

final class EventsCalculatorAimTests: XCTestCase {
    private typealias F = EventsAimingFixtures

    // MARK: Options

    func testTheCalendarOptionsUseThreeDegreesAndTheSiteZone() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let options = EventsCalculator.options(timeZone: zone)
        XCTAssertEqual(options.planetConjunctionThreshold, 3)
        XCTAssertEqual(options.moonConjunctionThreshold, 3)
        XCTAssertEqual(options.timeZone?.identifier, "Europe/Madrid")
    }

    func testTheCalendarOptionsAskForTheDefaultKinds() {
        let options = EventsCalculator.options(timeZone: TimeZone.gmt)
        XCTAssertEqual(options.kinds, EventKind.defaultKinds)
        XCTAssertFalse(options.kinds.contains(.earthApsis))
        XCTAssertFalse(options.visibleOnly)
    }

    // MARK: Focal length

    func testTheSuggestedFocalLengthFollowsTheSeparation() {
        // The frame is three separations wide, and the lens is the longest standard one whose 36 mm long side covers it.
        let expected: [(Double, Double)] = [
            (0.1, 800), (0.5, 800), (1, 600), (1.5, 400), (2, 300), (3, 200), (4, 135), (5, 135), (7, 85), (10, 50),
            (15, 35), (20, 24), (25, 20),
        ]
        for (separation, focalLength) in expected {
            XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: separation), focalLength, "\(separation) degrees")
        }
    }

    func testAFrameWiderThanTheWidestLensGivesTheWidestLens() {
        // At 30 degrees the exact lens is 18 mm, and only the 14 mm lens is no longer than that.
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: 30), 14)
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: 40), 14)
        // The frame is capped at 120 degrees, so a larger separation gives the same lens.
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: 100), 14)
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: 180), 14)
    }

    func testAVeryCloseOrZeroSeparationGivesTheLongestLens() {
        // The frame is never narrower than half a degree.
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: 0.0001), 800)
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: 0.16), 800)
    }

    func testAnUnusableSeparationGivesTheWidestLens() {
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: 0), 14)
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: -2), 14)
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: .nan), 14)
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: .infinity), 14)
        XCTAssertEqual(EventsCalculator.suggestedFocalLength(separation: -.infinity), 14)
    }

    func testTheFocalLengthIsAlwaysAStandardOneAndShrinksAsThePairSpreads() {
        var previous = Double.infinity
        for separation in [0.05, 0.1, 0.25, 0.5, 1, 1.5, 2, 3, 4, 5, 7, 10, 15, 20, 25, 30, 40, 60, 100] {
            let focalLength = EventsCalculator.suggestedFocalLength(separation: separation)
            XCTAssertTrue(EventsCalculator.standardFocalLengths.contains(focalLength), "\(separation): \(focalLength)")
            XCTAssertLessThanOrEqual(focalLength, previous, "\(separation)")
            previous = focalLength
        }
    }

    // MARK: Moonlight at the peak

    private func interference(fraction: Double, at moment: Date) throws -> EventsMoonInterference {
        try XCTUnwrap(EventsCalculator.moonInterference(of: F.meteor(fraction: fraction, at: moment), observer: F.equator))
    }

    func testAThinMoonHighAtThePeakIsALittleInterference() throws {
        let moon = try interference(fraction: 0.1, at: F.moonUp)
        XCTAssertEqual(moon.illuminatedFraction, 0.1, accuracy: 1e-12)
        XCTAssertGreaterThan(moon.moonAltitude, 45)
        XCTAssertEqual(moon.level, .little)
    }

    func testAHalfMoonHighAtThePeakIsAModerateInterference() throws {
        let moon = try interference(fraction: 0.4, at: F.moonUp)
        XCTAssertEqual(moon.illuminatedFraction, 0.4, accuracy: 1e-12)
        XCTAssertEqual(moon.level, .moderate)
    }

    func testABrightMoonHighAtThePeakIsAStrongInterference() throws {
        let moon = try interference(fraction: 0.9, at: F.moonUp)
        XCTAssertEqual(moon.level, .strong)
    }

    func testAMoonBelowTheHorizonAtThePeakDoesNotInterfereWhateverItsPhase() throws {
        let moon = try interference(fraction: 0.9, at: F.moonDown)
        XCTAssertEqual(moon.illuminatedFraction, 0.9, accuracy: 1e-12)
        XCTAssertLessThan(moon.moonAltitude, -45)
        XCTAssertEqual(moon.level, .moonDown)
    }

    func testTheMoonIsJudgedAtTheBestTimeWhenThereIsOne() throws {
        // The peak falls with the Moon down, but the best time of the night has it up.
        let event = F.meteor(fraction: 0.9, at: F.moonDown, visibility: F.visibility(bestTime: F.moonUp))
        let moon = try XCTUnwrap(EventsCalculator.moonInterference(of: event, observer: F.equator))
        XCTAssertGreaterThan(moon.moonAltitude, 45)
        XCTAssertEqual(moon.level, .strong)
    }

    func testTheMoonIsJudgedAtTheBestTimeEvenWhenItIsDownThen() throws {
        let event = F.meteor(fraction: 0.9, at: F.moonUp, visibility: F.visibility(bestTime: F.moonDown))
        let moon = try XCTUnwrap(EventsCalculator.moonInterference(of: event, observer: F.equator))
        XCTAssertLessThan(moon.moonAltitude, -45)
        XCTAssertEqual(moon.level, .moonDown)
    }

    func testTheMoonIsJudgedAtThePeakWhenThereIsNoBestTime() throws {
        let event = F.meteor(fraction: 0.9, at: F.moonUp, visibility: F.visibility(bestTime: nil))
        let moon = try XCTUnwrap(EventsCalculator.moonInterference(of: event, observer: F.equator))
        XCTAssertGreaterThan(moon.moonAltitude, 45)
    }

    func testOnlyMeteorShowersHaveMoonInterference() {
        XCTAssertNil(EventsCalculator.moonInterference(of: F.conjunction(.body(.moon), .body(.venus)), observer: F.equator))
        XCTAssertNil(EventsCalculator.moonInterference(of: F.event(.season(Season(kind: .juneSolstice))), observer: F.equator))
        XCTAssertNil(EventsCalculator.moonInterference(
            of: F.event(.fullMoonSpecial(FullMoonSpecial(categories: [.supermoon], distanceKilometers: 357_000,
                                                         angularDiameterArcseconds: 2_010))), observer: F.equator))
    }

    func testAnEntryCarriesTheMoonOfAShowerOnly() throws {
        let shower = F.meteor(fraction: 0.4, at: F.moonUp)
        XCTAssertNotNil(EventsCalculator.entry(for: shower, observer: F.equator).moonInterference)
        XCTAssertEqual(EventsCalculator.entry(for: shower, observer: F.equator).event, shower)
        let conjunction = F.conjunction(.body(.moon), .body(.venus))
        XCTAssertNil(EventsCalculator.entry(for: conjunction, observer: F.equator).moonInterference)
        XCTAssertEqual(EventsCalculator.entry(for: conjunction, observer: F.equator).event, conjunction)
    }

    // MARK: Aim subjects: meteor showers

    func testTheRadiantOfAnActiveShowerIsTheRadiantNow() throws {
        let shower = try XCTUnwrap(MeteorShower.withCode("PER"))
        let peakDate = shower.peak(near: F.date("2026-08-01T00:00:00Z"))
        let period = shower.activityPeriod(aroundPeak: peakDate)
        let peak = MeteorShowerPeak(shower: shower, activityStart: period.start, activityEnd: period.end,
                                    moonIlluminatedFraction: 0.2, radiant: shower.radiant)
        let event = F.event(.meteorShower(peak), at: peakDate)
        let now = F.date("2026-08-05T00:00:00Z")
        XCTAssertTrue(shower.isActive(at: now))
        XCTAssertEqual(EventsCalculator.aimSubjects(of: event, now: now),
                       [.radiant(name: "Perseids radiant", shower.radiant(at: now))])
    }

    func testTheRadiantOfAShowerThatIsNotActiveIsTheRadiantAtThePeak() throws {
        let shower = try XCTUnwrap(MeteorShower.withCode("PER"))
        let peakDate = shower.peak(near: F.date("2026-08-01T00:00:00Z"))
        let period = shower.activityPeriod(aroundPeak: peakDate)
        let peak = MeteorShowerPeak(shower: shower, activityStart: period.start, activityEnd: period.end,
                                    moonIlluminatedFraction: 0.2, radiant: shower.radiant)
        let event = F.event(.meteorShower(peak), at: peakDate)
        let now = F.date("2026-03-01T00:00:00Z")
        XCTAssertFalse(shower.isActive(at: now))
        XCTAssertEqual(EventsCalculator.aimSubjects(of: event, now: now),
                       [.radiant(name: "Perseids radiant", shower.radiant(at: peakDate))])
    }

    func testTheRadiantDriftsBetweenNowAndThePeak() throws {
        let shower = try XCTUnwrap(MeteorShower.withCode("PER"))
        let peakDate = shower.peak(near: F.date("2026-08-01T00:00:00Z"))
        let period = shower.activityPeriod(aroundPeak: peakDate)
        let peak = MeteorShowerPeak(shower: shower, activityStart: period.start, activityEnd: period.end,
                                    moonIlluminatedFraction: 0.2, radiant: shower.radiant)
        let event = F.event(.meteorShower(peak), at: peakDate)
        let early = EventsCalculator.aimSubjects(of: event, now: F.date("2026-08-05T00:00:00Z"))
        let late = EventsCalculator.aimSubjects(of: event, now: F.date("2026-03-01T00:00:00Z"))
        XCTAssertEqual(early.count, 1)
        XCTAssertEqual(late.count, 1)
        XCTAssertNotEqual(early, late)
    }

    // MARK: Aim subjects: other events

    func testAMoonConjunctionAimsAtTheMoonThenTheOtherBody() {
        XCTAssertEqual(EventsCalculator.aimSubjects(of: F.conjunction(.body(.moon), .body(.venus)), now: F.moment),
                       [.body(.moon), .body(.venus)])
    }

    func testAPlanetConjunctionAimsAtBothPlanets() {
        XCTAssertEqual(EventsCalculator.aimSubjects(of: F.conjunction(.body(.venus), .body(.jupiter)), now: F.moment),
                       [.body(.venus), .body(.jupiter)])
    }

    func testAConjunctionWithAReferenceStarAimsAtTheStarByItsName() {
        for star in ReferenceStar.allCases {
            XCTAssertEqual(EventsCalculator.aimSubjects(of: F.conjunction(.body(.moon), .star(star)), now: F.moment),
                           [.body(.moon), .fixed(name: star.displayName, star.position)], star.displayName)
        }
    }

    func testOppositionsAndElongationsAimAtThePlanet() {
        let opposition = F.event(.opposition(Opposition(planet: .saturn, distanceAU: 8.9, apparentMagnitude: 0.5,
                                                        angularDiameterArcseconds: 19)))
        XCTAssertEqual(EventsCalculator.aimSubjects(of: opposition, now: F.moment), [.body(.saturn)])
        let elongation = F.event(.greatestElongation(GreatestElongation(planet: .mercury, direction: .west, angle: 25,
                                                                         apparentMagnitude: 0)))
        XCTAssertEqual(EventsCalculator.aimSubjects(of: elongation, now: F.moment), [.body(.mercury)])
    }

    func testEclipsesAndSpecialFullMoonsAimAtTheMoonOrTheSun() {
        let fullMoon = F.event(.fullMoonSpecial(FullMoonSpecial(categories: [.supermoon], distanceKilometers: 357_000,
                                                                angularDiameterArcseconds: 2_010)))
        XCTAssertEqual(EventsCalculator.aimSubjects(of: fullMoon, now: F.moment), [.body(.moon)])
        let lunar = F.event(.lunarEclipse(LunarEclipse(
            kind: .penumbral, gamma: 1.0, penumbralMagnitude: 0.5, umbralMagnitude: -0.5, p1: F.moment, u1: nil, u2: nil,
            greatest: F.moment.addingTimeInterval(3_600), u3: nil, u4: nil, p4: F.moment.addingTimeInterval(7_200))))
        XCTAssertEqual(EventsCalculator.aimSubjects(of: lunar, now: F.moment), [.body(.moon)])
        let solar = F.event(.solarEclipse(SolarEclipse(kind: .total, greatest: F.moment, gamma: 0.9, greatestMagnitude: 1.04,
                                                       isCentral: true, local: nil)))
        XCTAssertEqual(EventsCalculator.aimSubjects(of: solar, now: F.moment), [.body(.sun)])
    }

    func testSeasonsAndApsidesHaveNothingToAimAt() {
        XCTAssertTrue(EventsCalculator.aimSubjects(of: F.event(.season(Season(kind: .marchEquinox))), now: F.moment).isEmpty)
        XCTAssertTrue(EventsCalculator.aimSubjects(of: F.event(.earthApsis(EarthApsis(kind: .perihelion, distanceAU: 0.983))),
                                                   now: F.moment).isEmpty)
    }

    // MARK: Titles

    func testTheTitleOfASubjectIsItsName() {
        let place = EquatorialCoordinate(rightAscension: 10, declination: 20)
        XCTAssertEqual(EventsCalculator.AimSubject.body(.moon).title, "Moon")
        XCTAssertEqual(EventsCalculator.AimSubject.body(.neptune).title, "Neptune")
        XCTAssertEqual(EventsCalculator.AimSubject.fixed(name: "Spica", place).title, "Spica")
        XCTAssertEqual(EventsCalculator.AimSubject.radiant(name: "Perseids radiant", place).title, "Perseids radiant")
    }

    func testSubjectsAreEqualOnlyWhenNameAndPlaceAreEqual() {
        let place = EquatorialCoordinate(rightAscension: 10, declination: 20)
        let other = EquatorialCoordinate(rightAscension: 10, declination: 21)
        XCTAssertEqual(EventsCalculator.AimSubject.fixed(name: "Spica", place), .fixed(name: "Spica", place))
        XCTAssertNotEqual(EventsCalculator.AimSubject.fixed(name: "Spica", place), .fixed(name: "Spica", other))
        XCTAssertNotEqual(EventsCalculator.AimSubject.fixed(name: "Spica", place), .radiant(name: "Spica", place))
    }
}
