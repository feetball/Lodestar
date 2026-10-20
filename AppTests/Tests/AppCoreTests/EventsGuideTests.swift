import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Events for the tests of `EventsGuide.swift`.
private enum EventsGuideFixtures {
    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: .nan)
    }

    /// The ASCII digits of `text`: they survive another decimal mark or digit grouping.
    static func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    static let moment = date("2026-08-12T17:46:00Z")

    static func entry(_ details: EventDetails, interference: EventsMoonInterference? = nil) -> EventsEntry {
        EventsEntry(event: AstronomicalEvent(date: moment, details: details, visibility: nil), moonInterference: interference)
    }

    static func guide(_ details: EventDetails, southern: Bool = false,
                      interference: EventsMoonInterference? = nil) -> EventsGuide {
        EventsGuide.make(for: entry(details, interference: interference), isSouthernHemisphere: southern)
    }

    static func moon(_ level: EventsMoonInterference.Level) -> EventsMoonInterference {
        EventsMoonInterference(illuminatedFraction: 0.5, moonAltitude: 20, level: level)
    }

    // MARK: Details

    static func meteor() -> EventDetails {
        let shower = MeteorShower(
            code: "TST", iauNumber: 999, name: "Perseids", activityStartMonth: 7, activityStartDay: 17, activityEndMonth: 8,
            activityEndDay: 24, peakSolarLongitude: 140, zhr: 100,
            radiant: EquatorialCoordinate(rightAscension: 48, declination: 58), radiantDriftRightAscension: 1.42,
            radiantDriftDeclination: 0.2, velocity: 59, populationIndex: 2.2)
        return .meteorShower(MeteorShowerPeak(
            shower: shower, activityStart: date("2026-07-17T00:00:00Z"), activityEnd: date("2026-08-25T00:00:00Z"),
            moonIlluminatedFraction: 0.64, radiant: shower.radiant))
    }

    static func conjunction(_ first: ConjunctionTarget = .body(.moon), _ second: ConjunctionTarget = .body(.venus),
                            separation: Double = 2.0, elongation: Double = 90, occultationPossible: Bool = false,
                            topocentric: TopocentricApproach? = nil) -> EventDetails {
        .conjunction(Conjunction(first: first, second: second, separation: separation, solarElongation: elongation,
                                 occultationPossible: occultationPossible, topocentric: topocentric))
    }

    static func opposition(_ planet: SolarSystemBody) -> EventDetails {
        .opposition(Opposition(planet: planet, distanceAU: 4.0, apparentMagnitude: -2.5, angularDiameterArcseconds: 45.67))
    }

    static func elongation(_ planet: SolarSystemBody, _ direction: ElongationDirection, angle: Double) -> EventDetails {
        .greatestElongation(GreatestElongation(planet: planet, direction: direction, angle: angle, apparentMagnitude: nil))
    }

    static func apsis(_ kind: EarthApsisKind) -> EventDetails {
        .earthApsis(EarthApsis(kind: kind, distanceAU: 0.9833))
    }

    static func season(_ kind: SeasonKind) -> EventDetails {
        .season(Season(kind: kind))
    }

    static func fullMoon(_ categories: [FullMoonCategory]) -> EventDetails {
        .fullMoonSpecial(FullMoonSpecial(categories: categories, distanceKilometers: 356_900.4, angularDiameterArcseconds: 2_010))
    }

    /// A lunar eclipse of the given kind with 59 minutes of totality (if total).
    static func lunar(_ kind: LunarEclipseKind) -> EventDetails {
        let base = date("2026-03-03T08:44:00Z")
        func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
        let hasUmbra = kind != .penumbral
        let isTotal = kind == .total
        let umbral = kind == .penumbral ? -0.2149 : (isTotal ? 1.1722 : 0.5123)
        return .lunarEclipse(LunarEclipse(
            kind: kind, gamma: -0.38, penumbralMagnitude: kind == .penumbral ? 0.9234 : 2.1838, umbralMagnitude: umbral,
            p1: at(0), u1: hasUmbra ? at(3_960) : nil, u2: isTotal ? at(8_400) : nil, greatest: at(10_200),
            u3: isTotal ? at(11_940) : nil, u4: hasUmbra ? at(16_680) : nil, p4: at(20_400)))
    }

    static func local(_ kind: LocalSolarEclipseKind, obscuration: Double = 0.62, duration: Double = 106) -> LocalSolarCircumstances {
        LocalSolarCircumstances(kind: kind, c1: nil, c2: nil, maximum: date("2026-08-12T18:29:13Z"), c3: nil, c4: nil,
                                magnitude: 1.0386, obscuration: obscuration, sunAltitude: 12.4, sunAzimuth: 268,
                                centralDuration: duration, visibleInterval: nil)
    }

    static func solar(_ kind: SolarEclipseKind, local: LocalSolarCircumstances? = nil) -> EventDetails {
        .solarEclipse(SolarEclipse(kind: kind, greatest: moment, gamma: 0.8977, greatestMagnitude: 1.0386, isCentral: true,
                                   local: local))
    }
}

final class EventsGuideTests: XCTestCase {
    private typealias F = EventsGuideFixtures

    // MARK: Every kind

    func testEveryKindOfEventHasAnAboutAndAWhy() {
        let all: [EventDetails] = [
            F.meteor(), F.conjunction(), F.opposition(.mars), F.elongation(.venus, .east, angle: 46), F.apsis(.aphelion),
            F.season(.marchEquinox), F.fullMoon([.supermoon]), F.lunar(.total), F.solar(.total),
        ]
        for details in all {
            let guide = F.guide(details)
            XCTAssertFalse(guide.about.isEmpty, "\(details)")
            XCTAssertFalse(guide.why.isEmpty, "\(details)")
        }
    }

    func testTheGuideIsTheSameForBothHemispheresExceptForTheSeasons() {
        let unaffected: [EventDetails] = [
            F.meteor(), F.conjunction(), F.opposition(.jupiter), F.elongation(.mercury, .west, angle: 25), F.apsis(.perihelion),
            F.fullMoon([.blueMoon]), F.lunar(.partial), F.solar(.annular),
        ]
        for details in unaffected {
            XCTAssertEqual(F.guide(details, southern: false), F.guide(details, southern: true), "\(details)")
        }
        XCTAssertNotEqual(F.guide(F.season(.juneSolstice), southern: false), F.guide(F.season(.juneSolstice), southern: true))
    }

    // MARK: Meteor showers

    func testAMeteorShowerGuideNamesTheShowerAndItsRate() {
        let guide = F.guide(F.meteor())
        XCTAssertTrue(guide.about.hasPrefix("Perseids is a meteor shower."), guide.about)
        XCTAssertTrue(guide.about.hasSuffix("it can show up to about 100 meteors an hour at its peak."), guide.about)
        XCTAssertTrue(guide.about.contains("the radiant"), guide.about)
    }

    func testAMeteorShowerGuideHasFourTipsWithoutMoonlight() {
        XCTAssertEqual(F.guide(F.meteor()).tips.count, 4)
        XCTAssertEqual(F.guide(F.meteor(), interference: F.moon(.moonDown)).tips.count, 4)
        XCTAssertEqual(F.guide(F.meteor(), interference: F.moon(.little)).tips.count, 4)
    }

    func testAMeteorShowerGuideWarnsAboutModerateAndStrongMoonlight() {
        for level in [EventsMoonInterference.Level.moderate, .strong] {
            let tips = F.guide(F.meteor(), interference: F.moon(level)).tips
            XCTAssertEqual(tips.count, 5, "\(level)")
            XCTAssertEqual(tips.last, "Moonlight hides faint meteors. Frame away from the Moon, or shoot after it sets.")
        }
    }

    func testTheFirstMeteorTipsAreTheSameWithOrWithoutMoonlight() {
        let dark = F.guide(F.meteor()).tips
        let bright = F.guide(F.meteor(), interference: F.moon(.strong)).tips
        XCTAssertEqual(Array(bright.prefix(4)), dark)
        XCTAssertTrue(dark[0].hasPrefix("Use a wide lens (14 to 24 mm)"), dark[0])
        XCTAssertTrue(dark[1].hasPrefix("Aim about 40\u{00B0} away from the radiant"), dark[1])
    }

    // MARK: Conjunctions

    func testAMoonConjunctionGuideNamesThePairAndTheSeparation() {
        let guide = F.guide(F.conjunction(.body(.moon), .body(.venus), separation: 2.0))
        XCTAssertTrue(guide.about.hasPrefix("The Moon passes 2.0\u{00B0} from Venus, as seen from the centre of the Earth."), guide.about)
    }

    func testAPlanetConjunctionGuideNamesBothPlanets() {
        let guide = F.guide(F.conjunction(.body(.venus), .body(.jupiter), separation: 1.2))
        XCTAssertTrue(guide.about.hasPrefix("Venus and Jupiter come within 1.2\u{00B0} of each other in the sky."), guide.about)
        XCTAssertFalse(guide.about.contains("The Moon"), guide.about)
    }

    func testAConjunctionGuideSuggestsALensForTheSeparation() {
        // A pair 2 degrees apart needs a frame 6 degrees wide: at most 343 mm, so 300 mm.
        let tips = F.guide(F.conjunction(.body(.venus), .body(.jupiter), separation: 2.0)).tips
        XCTAssertEqual(tips, ["Frame both. They are 2.0\u{00B0} apart, so about 300 mm (35 mm equivalent) holds the pair "
                              + "with room around it."])
    }

    func testAWideConjunctionNeedsAWiderLens() {
        let tips = F.guide(F.conjunction(.body(.venus), .body(.jupiter), separation: 10)).tips
        XCTAssertTrue(tips[0].hasPrefix("Frame both. They are 10\u{00B0} apart, so about 50 mm "), tips[0])
    }

    func testAConjunctionLowInTheTwilightWarnsAboutTheHorizon() {
        let tips = F.guide(F.conjunction(.body(.venus), .body(.jupiter), elongation: 30)).tips
        XCTAssertEqual(tips.count, 2)
        XCTAssertEqual(tips[1], "The pair stands only 30\u{00B0} from the Sun, so it is low in twilight. Scout a clear horizon first.")
    }

    func testTheTwilightWarningStopsAt45Degrees() {
        XCTAssertEqual(F.guide(F.conjunction(.body(.venus), .body(.jupiter), elongation: 44.9)).tips.count, 2)
        XCTAssertEqual(F.guide(F.conjunction(.body(.venus), .body(.jupiter), elongation: 45)).tips.count, 1)
        XCTAssertEqual(F.guide(F.conjunction(.body(.venus), .body(.jupiter), elongation: 120)).tips.count, 1)
    }

    func testAMoonConjunctionGuideAdvisesBracketing() {
        let tips = F.guide(F.conjunction(.body(.moon), .body(.venus))).tips
        XCTAssertEqual(tips.count, 2)
        XCTAssertTrue(tips[1].hasPrefix("The Moon is far brighter than a planet or a star. Bracket your exposures"), tips[1])
    }

    func testAnOccultationFromHereIsAnnounced() {
        let approach = TopocentricApproach(time: F.moment, separation: 0.0, isOccultation: true)
        let guide = F.guide(F.conjunction(.body(.moon), .star(.spica), separation: 0.5, occultationPossible: true,
                                          topocentric: approach))
        XCTAssertEqual(guide.tips.last, "From here the Moon passes in front of Spica: an occultation. Start recording "
                       + "several minutes before.")
    }

    func testAnOccultationElsewhereIsMentionedWhenItIsNotSeenFromHere() {
        let miss = TopocentricApproach(time: F.moment, separation: 0.4, isOccultation: false)
        let guide = F.guide(F.conjunction(.body(.moon), .star(.spica), separation: 0.5, occultationPossible: true,
                                          topocentric: miss))
        XCTAssertEqual(guide.tips.last, "The Moon covers Spica from parts of the Earth, but not as seen from here.")
    }

    func testNoOccultationTipWhenItIsNotPossible() {
        let tips = F.guide(F.conjunction(.body(.moon), .star(.spica), separation: 0.5)).tips
        XCTAssertEqual(tips.count, 2)
        XCTAssertFalse(tips.contains { $0.contains("occultation") || $0.contains("covers") })
    }

    func testTheConjunctionGuideTipsComeInOrder() {
        let approach = TopocentricApproach(time: F.moment, separation: 0.0, isOccultation: true)
        let tips = F.guide(F.conjunction(.body(.moon), .star(.regulus), separation: 0.5, elongation: 30,
                                         occultationPossible: true, topocentric: approach)).tips
        XCTAssertEqual(tips.count, 4)
        XCTAssertTrue(tips[0].hasPrefix("Frame both."), tips[0])
        XCTAssertTrue(tips[1].hasPrefix("The pair stands only"), tips[1])
        XCTAssertTrue(tips[2].hasPrefix("The Moon is far brighter"), tips[2])
        XCTAssertTrue(tips[3].hasPrefix("From here the Moon passes in front of Regulus"), tips[3])
    }

    // MARK: Oppositions

    func testAnOppositionGuideNamesThePlanetAndItsSize() {
        let guide = F.guide(F.opposition(.mars))
        XCTAssertTrue(guide.about.hasPrefix("Mars is opposite the Sun in the sky."), guide.about)
        XCTAssertTrue(guide.about.hasSuffix("\u{2033} across)."), guide.about)
        // 45.7 arcseconds.
        XCTAssertEqual(F.digits(guide.about), "457")
    }

    func testTheNearPlanetsAreAdvisedALongLensAndStacking() {
        for planet in [SolarSystemBody.mars, .jupiter, .saturn] {
            let guide = F.guide(F.opposition(planet))
            XCTAssertEqual(guide.tips.count, 3, planet.displayName)
            XCTAssertEqual(guide.tips[0], "Use the longest focal length you have, 400 mm or more, or a telescope.")
            XCTAssertEqual(guide.tips[2], "Wait until \(planet.displayName) is high, around midnight, when the air is steadiest.")
            XCTAssertTrue(guide.why.hasPrefix("The best weeks of the year to photograph \(planet.displayName)"), guide.why)
        }
    }

    func testTheDistantPlanetsAreAdvisedAStarChartAndAShortExposure() {
        for planet in [SolarSystemBody.uranus, .neptune] {
            let guide = F.guide(F.opposition(planet))
            XCTAssertEqual(guide.tips.count, 3, planet.displayName)
            XCTAssertTrue(guide.tips[0].hasPrefix("\(planet.displayName) looks like a faint star."), guide.tips[0])
            XCTAssertEqual(guide.tips[2], "Wait until \(planet.displayName) is high, around midnight, and the Moon is away.")
            XCTAssertTrue(guide.why.hasPrefix("The best time of the year to catch a distant planet"), guide.why)
        }
    }

    // MARK: Elongations

    func testAnEveningElongationGuide() {
        let guide = F.guide(F.elongation(.venus, .east, angle: 46.0))
        XCTAssertEqual(guide.about, "Venus is as far from the Sun as it gets in this apparition: 46\u{00B0} east of it, "
                       + "in the evening sky.")
        XCTAssertEqual(guide.tips.first, "Look low in the west after sunset.")
        XCTAssertEqual(guide.tips.count, 3)
        XCTAssertTrue(guide.why.hasPrefix("The easiest time to see and photograph Venus"), guide.why)
    }

    func testAMorningElongationGuide() {
        let guide = F.guide(F.elongation(.mercury, .west, angle: 25.3))
        XCTAssertEqual(guide.about, "Mercury is as far from the Sun as it gets in this apparition: 25\u{00B0} west of it, "
                       + "in the morning sky.")
        XCTAssertEqual(guide.tips.first, "Look low in the east before sunrise.")
    }

    // MARK: Apsides

    func testAPerihelionGuide() {
        let guide = F.guide(F.apsis(.perihelion))
        XCTAssertTrue(guide.about.hasPrefix("The Earth is closest to the Sun, "), guide.about)
        XCTAssertTrue(guide.about.contains(" AU away. The distance changes the Sun's size in the sky by only about 3 percent."),
                      guide.about)
        // 0.983 AU, then the "3 percent" of the text.
        XCTAssertEqual(F.digits(guide.about), "09833")
        XCTAssertTrue(guide.tips.isEmpty)
    }

    func testAnAphelionGuide() {
        let guide = F.guide(F.apsis(.aphelion))
        XCTAssertTrue(guide.about.hasPrefix("The Earth is farthest from the Sun, "), guide.about)
        XCTAssertTrue(guide.tips.isEmpty)
    }

    // MARK: Seasons

    func testTheEquinoxesAreVernalOrAutumnalForTheHemisphere() {
        XCTAssertTrue(F.guide(F.season(.marchEquinox), southern: false).about.contains("the vernal equinox for your hemisphere"))
        XCTAssertTrue(F.guide(F.season(.marchEquinox), southern: true).about.contains("the autumnal equinox for your hemisphere"))
        XCTAssertTrue(F.guide(F.season(.septemberEquinox), southern: false).about.contains("the autumnal equinox for your hemisphere"))
        XCTAssertTrue(F.guide(F.season(.septemberEquinox), southern: true).about.contains("the vernal equinox for your hemisphere"))
    }

    func testAnEquinoxGuideHasThreeTips() {
        let guide = F.guide(F.season(.marchEquinox))
        XCTAssertTrue(guide.about.hasPrefix("The Sun crosses the celestial equator: "), guide.about)
        XCTAssertEqual(guide.tips.count, 3)
        XCTAssertTrue(guide.tips[0].hasPrefix("Scout the spot a day or two before."), guide.tips[0])
    }

    func testTheJuneSolsticeInTheNorth() {
        let guide = F.guide(F.season(.juneSolstice), southern: false)
        XCTAssertEqual(guide.about, "The Sun reaches its northernmost point. For your hemisphere this is the summer "
                       + "solstice: the longest day and the shortest night.")
        XCTAssertEqual(guide.tips[1], "The night is short, so plan star photography early or late.")
    }

    func testTheJuneSolsticeInTheSouth() {
        let guide = F.guide(F.season(.juneSolstice), southern: true)
        XCTAssertEqual(guide.about, "The Sun reaches its northernmost point. For your hemisphere this is the winter "
                       + "solstice: the shortest day and the longest night.")
        XCTAssertEqual(guide.tips[1], "The long night leaves plenty of dark time for star photography.")
    }

    func testTheDecemberSolsticeInTheNorth() {
        let guide = F.guide(F.season(.decemberSolstice), southern: false)
        XCTAssertEqual(guide.about, "The Sun reaches its southernmost point. For your hemisphere this is the winter "
                       + "solstice: the shortest day and the longest night.")
        XCTAssertEqual(guide.tips[1], "The long night leaves plenty of dark time for star photography.")
    }

    func testTheDecemberSolsticeInTheSouth() {
        let guide = F.guide(F.season(.decemberSolstice), southern: true)
        XCTAssertEqual(guide.about, "The Sun reaches its southernmost point. For your hemisphere this is the summer "
                       + "solstice: the longest day and the shortest night.")
        XCTAssertEqual(guide.tips[1], "The night is short, so plan star photography early or late.")
    }

    func testASolsticeGuideHasThreeTips() {
        XCTAssertEqual(F.guide(F.season(.juneSolstice)).tips.count, 3)
        XCTAssertTrue(F.guide(F.season(.juneSolstice)).tips[0].hasPrefix("Check where the Sun rises and sets"))
    }

    // MARK: Special full Moons

    func testASupermoonGuide() {
        let guide = F.guide(F.fullMoon([.supermoon]))
        XCTAssertTrue(guide.about.hasPrefix("A full Moon that is a supermoon: full while close to the Earth ("), guide.about)
        XCTAssertTrue(guide.about.hasSuffix(" km), so a little larger and brighter than an average full Moon."), guide.about)
        XCTAssertEqual(F.digits(guide.about), "356900")
    }

    func testAMicromoonGuide() {
        let guide = F.guide(F.fullMoon([.micromoon]))
        XCTAssertTrue(guide.about.hasPrefix("A full Moon that is a micromoon: full while far from the Earth ("), guide.about)
        XCTAssertTrue(guide.about.hasSuffix(" km), so a little smaller than an average full Moon."), guide.about)
    }

    func testABlueMoonGuide() {
        XCTAssertEqual(F.guide(F.fullMoon([.blueMoon])).about,
                       "A full Moon that is a blue moon: the second full Moon of its calendar month. It is not actually blue.")
    }

    func testAMoonWithSeveralReasonsListsThemAll() {
        let about = F.guide(F.fullMoon([.supermoon, .blueMoon])).about
        XCTAssertTrue(about.hasPrefix("A full Moon that is a supermoon: "), about)
        XCTAssertTrue(about.hasSuffix("an average full Moon, and a blue moon: the second full Moon of its calendar month. "
                                      + "It is not actually blue."), about)
    }

    func testAFullMoonWithoutAnyCategoryIsJustSpecial() {
        XCTAssertEqual(F.guide(F.fullMoon([])).about, "A special full Moon.")
    }

    func testOnlyASupermoonGetsTheSizeTip() {
        XCTAssertEqual(F.guide(F.fullMoon([.supermoon])).tips.count, 4)
        XCTAssertEqual(F.guide(F.fullMoon([.supermoon])).tips[3],
                       "The size difference is small. Put a landmark of known size in the frame to show it.")
        XCTAssertEqual(F.guide(F.fullMoon([.micromoon])).tips.count, 3)
        XCTAssertEqual(F.guide(F.fullMoon([.blueMoon])).tips.count, 3)
        XCTAssertEqual(F.guide(F.fullMoon([.blueMoon, .supermoon])).tips.count, 4)
        XCTAssertEqual(F.guide(F.fullMoon([])).tips.count, 3)
    }

    // MARK: Lunar eclipses

    func testATotalLunarEclipseGuideGivesTheLengthOfTotality() {
        let guide = F.guide(F.lunar(.total))
        XCTAssertEqual(guide.about, "The whole Moon enters the dark core of the Earth's shadow and glows a dim copper red "
                       + "for 59m 00s.")
    }

    func testAPartialLunarEclipseGuideGivesTheUmbralMagnitude() {
        let guide = F.guide(F.lunar(.partial))
        XCTAssertTrue(guide.about.hasPrefix("Part of the Moon enters the dark core of the Earth's shadow and looks bitten "
                                            + "away (umbral magnitude "), guide.about)
        XCTAssertTrue(guide.about.hasSuffix(")."), guide.about)
        XCTAssertEqual(F.digits(guide.about), "0512")
    }

    func testAPenumbralLunarEclipseGuideSaysItIsHardToSee() {
        XCTAssertEqual(F.guide(F.lunar(.penumbral)).about,
                       "The Moon passes through the faint outer shadow of the Earth and dims only slightly. "
                       + "The change is hard to see.")
    }

    func testAnEclipseThatReachesTheUmbraGetsAnExposureTip() {
        for kind in [LunarEclipseKind.partial, .total] {
            let tips = F.guide(F.lunar(kind)).tips
            XCTAssertEqual(tips.count, 4, "\(kind)")
            XCTAssertEqual(tips[1], "The exposure changes a lot: about 1/500 s at ISO 200 before the shadow, seconds at "
                           + "ISO 1600 or more in the shadow. Check the histogram.")
        }
    }

    func testAPenumbralEclipseHasNoExposureTip() {
        let tips = F.guide(F.lunar(.penumbral)).tips
        XCTAssertEqual(tips.count, 3)
        XCTAssertTrue(tips[0].hasPrefix("Use a long lens (200 to 600 mm)"), tips[0])
        XCTAssertEqual(tips[1], "Shoot a frame every minute or two and combine them into a sequence.")
        XCTAssertEqual(tips[2], "No filter is needed: a lunar eclipse is safe to watch and to photograph.")
    }

    // MARK: Solar eclipses

    func testSolarEclipseKindsAreDescribed() {
        XCTAssertEqual(F.guide(F.solar(.total)).about, "The Moon covers the Sun completely along a narrow path across the Earth.")
        XCTAssertEqual(F.guide(F.solar(.annular)).about,
                       "The Moon crosses in front of the Sun but is too far away to cover it, leaving a ring of sunlight.")
        XCTAssertEqual(F.guide(F.solar(.hybrid)).about,
                       "The eclipse is annular in some places and total in others along its path.")
        XCTAssertEqual(F.guide(F.solar(.partial)).about,
                       "The Moon covers only part of the Sun, as seen from anywhere on the Earth.")
    }

    func testTheWhyOfASolarEclipseFollowsItsKind() {
        let total = "One of the most dramatic sights in the sky. In totality the Sun's corona shows around the black Moon."
        XCTAssertEqual(F.guide(F.solar(.total)).why, total)
        XCTAssertEqual(F.guide(F.solar(.hybrid)).why, total)
        XCTAssertEqual(F.guide(F.solar(.annular)).why,
                       "The Moon sits inside the Sun's disc and leaves a bright ring, the \u{201C}ring of fire\u{201D}.")
        XCTAssertEqual(F.guide(F.solar(.partial)).why,
                       "The Sun turns into a crescent. Light through leaves and gaps also throws small crescents on the ground.")
    }

    func testASolarEclipseGuideWithoutLocalCircumstancesSaysNothingAboutHere() {
        XCTAssertFalse(F.guide(F.solar(.total)).about.contains("From here"))
        XCTAssertFalse(F.guide(F.solar(.total)).about.contains("from here"))
    }

    func testASolarEclipseThatCannotBeSeenFromHere() {
        let guide = F.guide(F.solar(.total, local: F.local(LocalSolarEclipseKind.none)))
        XCTAssertEqual(guide.about, "The Moon covers the Sun completely along a narrow path across the Earth. "
                       + "It cannot be seen from here.")
    }

    func testASolarEclipseThatIsPartialFromHere() {
        let guide = F.guide(F.solar(.total, local: F.local(.partial, obscuration: 0.62)))
        XCTAssertEqual(guide.about, "The Moon covers the Sun completely along a narrow path across the Earth. "
                       + "From here it is partial: 62% of the Sun is covered at most.")
    }

    func testASolarEclipseThatIsAnnularFromHere() {
        let guide = F.guide(F.solar(.annular, local: F.local(.annular, duration: 312)))
        XCTAssertTrue(guide.about.hasSuffix(" From here it is annular, for 5m 12s."), guide.about)
    }

    func testASolarEclipseThatIsTotalFromHere() {
        let guide = F.guide(F.solar(.total, local: F.local(.total, duration: 106)))
        XCTAssertTrue(guide.about.hasSuffix(" From here it is total, for 1m 46s."), guide.about)
    }

    func testEverySolarEclipseGuideHasTheSafetyTipsFirst() {
        for kind in SolarEclipseKind.allCases {
            let tips = F.guide(F.solar(kind)).tips
            XCTAssertEqual(tips.count, 4, kind.rawValue)
            XCTAssertTrue(tips[0].hasPrefix("Fit a certified solar filter over the front of the lens"), tips[0])
            XCTAssertTrue(tips[2].hasPrefix("Never look at the Sun through the viewfinder"), tips[2])
        }
    }
}
