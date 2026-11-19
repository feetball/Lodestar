import XCTest
@testable import LodestarKit

/// The Moon's effect on a target: the rule the apps used, and how each imaging filter relaxes it.
final class PlanningMoonImpactTests: XCTestCase {
    private typealias Level = MoonImpact.Level

    private let allKinds = ObjectCategory.allCases
    private let emissionKinds: [ObjectCategory] = [.emissionNebula, .planetaryNebula, .supernovaRemnant, .clusterWithNebula]
    private var otherKinds: [ObjectCategory] { allKinds.filter { !emissionKinds.contains($0) } }

    /// The rule of thumb as the apps had it before it moved into the engine, kept here as the reference.
    private func legacyLevel(moonAltitude: Double, separation: Double, illuminatedFraction: Double) -> Level {
        guard moonAltitude > 0 else { return .moonDown }
        let proximity = min(max(1 - separation / 120, 0.25), 1)
        switch illuminatedFraction * proximity {
        case 0.5...: return .severe
        case 0.2...: return .moderate
        default: return .minor
        }
    }

    private func assess(_ separation: Double, _ illuminatedFraction: Double, _ filter: ImagingFilter,
                        _ kind: ObjectCategory = .emissionNebula, moonAltitude: Double = 30) -> Level {
        MoonImpact.assess(moonAltitude: moonAltitude, separation: separation,
                          illuminatedFraction: illuminatedFraction, filter: filter, objectKind: kind)
    }

    private let separations = (0...72).map { Double($0) * 2.5 }
    private let fractions = (0...40).map { Double($0) * 0.025 }

    // MARK: Without a filter

    func testNoFilterEqualsTheOldAppRuleOnAGrid() {
        var checked = 0
        for altitude in [-30.0, -0.5, 0.0, 1e-9, 0.0001, 10.0, 60.0, 90.0] {
            for separation in separations {
                for fraction in fractions {
                    let expected = legacyLevel(moonAltitude: altitude, separation: separation,
                                               illuminatedFraction: fraction)
                    for kind in allKinds {
                        XCTAssertEqual(
                            MoonImpact.assess(moonAltitude: altitude, separation: separation,
                                              illuminatedFraction: fraction, filter: .none, objectKind: kind),
                            expected, "altitude \(altitude) separation \(separation) fraction \(fraction) \(kind.rawValue)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 8 * 73 * 41 * allKinds.count)
    }

    func testBroadbandThresholdsSitExactlyOnTheOldCutOffs() {
        // 1 × (1 − 60/120) = 0.5 exactly: severe. Just under it: moderate.
        XCTAssertEqual(assess(60, 1, .none), .severe)
        XCTAssertEqual(assess(60, 0.9999, .none), .moderate)
        // 0.2 × 1 = 0.2 exactly: moderate. Just under it: minor.
        XCTAssertEqual(assess(0, 0.2, .none), .moderate)
        XCTAssertEqual(assess(0, 0.1999, .none), .minor)
        // The proximity stops falling at 0.25 from 90° on: a full Moon is moderate anywhere in the sky.
        XCTAssertEqual(assess(90, 1, .none), .moderate)
        XCTAssertEqual(assess(180, 1, .none), .moderate)
        XCTAssertEqual(assess(180, 0.7999, .none), .minor)
    }

    func testTheMoonOnTheHorizonOrBelowIsDownWhateverTheFilter() {
        for altitude in [0.0, -0.0, -1.0, -90.0, Double.nan, -Double.infinity, Double.infinity] {
            for filter in ImagingFilter.allCases {
                for kind in allKinds {
                    XCTAssertEqual(
                        MoonImpact.assess(moonAltitude: altitude, separation: 10, illuminatedFraction: 1,
                                          filter: filter, objectKind: kind),
                        .moonDown, "altitude \(altitude) \(filter.rawValue) \(kind.rawValue)")
                }
            }
        }
        XCTAssertEqual(assess(10, 1, .none, moonAltitude: 1e-9), .severe)
    }

    func testGeometryThatIsNotFiniteCannotBeJudgedAndIsMinor() {
        for filter in ImagingFilter.allCases {
            for kind in allKinds {
                let label = "\(filter.rawValue) \(kind.rawValue)"
                XCTAssertEqual(MoonImpact.assess(moonAltitude: 30, separation: .nan, illuminatedFraction: 1,
                                                 filter: filter, objectKind: kind), .minor, label)
                XCTAssertEqual(MoonImpact.assess(moonAltitude: 30, separation: 10, illuminatedFraction: .nan,
                                                 filter: filter, objectKind: kind), .minor, label)
                XCTAssertEqual(MoonImpact.assess(moonAltitude: 30, separation: .infinity, illuminatedFraction: 1,
                                                 filter: filter, objectKind: kind), .minor, label)
                XCTAssertEqual(MoonImpact.assess(moonAltitude: 30, separation: 10, illuminatedFraction: -.infinity,
                                                 filter: filter, objectKind: kind), .minor, label)
            }
        }
    }

    func testValuesOutOfRangeAreLimitedToTheirRange() {
        for filter in ImagingFilter.allCases {
            XCTAssertEqual(assess(0, 1, filter), assess(-25, 1, filter))
            XCTAssertEqual(assess(180, 1, filter), assess(400, 1, filter))
            XCTAssertEqual(assess(20, 1, filter), assess(20, 1.7, filter))
            XCTAssertEqual(assess(20, 0, filter), assess(20, -0.4, filter))
        }
    }

    // MARK: Which targets benefit

    func testOnlyEmissionLineTargetsBenefit() {
        for kind in allKinds {
            XCTAssertEqual(MoonImpact.isEmissionLineTarget(kind), emissionKinds.contains(kind), kind.rawValue)
        }
        // The same from the catalog's OpenNGC type codes.
        for code in ["HII", "EmN", "PN", "SNR", "Cl+N"] {
            XCTAssertTrue(MoonImpact.isEmissionLineTarget(ObjectCategory(openNGCType: code)), code)
        }
        for code in ["G", "GPair", "GTrpl", "GGroup", "OCl", "GCl", "RfN", "DrkN", "Neb", "*Ass", "**", "*", "Other",
                     "Nova"] {
            XCTAssertFalse(MoonImpact.isEmissionLineTarget(ObjectCategory(openNGCType: code)), code)
        }
    }

    func testTargetsWithoutEmissionLinesAreNeverRelaxed() {
        for kind in otherKinds {
            for filter in ImagingFilter.allCases {
                let label = "\(filter.rawValue) \(kind.rawValue)"
                XCTAssertEqual(MoonImpact.relaxationSteps(separation: 10, illuminatedFraction: 1, filter: filter,
                                                          objectKind: kind), 0, label)
                XCTAssertEqual(MoonImpact.relaxationSteps(separation: 120, illuminatedFraction: 1, filter: filter,
                                                          objectKind: kind), 0, label)
                for separation in separations {
                    for fraction in fractions {
                        XCTAssertEqual(assess(separation, fraction, filter, kind),
                                       assess(separation, fraction, .none, kind),
                                       "\(label) separation \(separation) fraction \(fraction)")
                    }
                }
            }
        }
    }

    // MARK: Each filter

    func testNoFilterTakesNoStepsOffAnyTarget() {
        for kind in allKinds {
            XCTAssertEqual(MoonImpact.relaxationSteps(separation: 10, illuminatedFraction: 1, filter: .none,
                                                      objectKind: kind), 0)
            XCTAssertEqual(MoonImpact.relaxationSteps(separation: 150, illuminatedFraction: 0.2, filter: .none,
                                                      objectKind: kind), 0)
        }
    }

    func testLightPollutionFilterTakesOneStepOffFromFortyDegrees() {
        let filter = ImagingFilter.lightPollution
        func steps(_ separation: Double) -> Int {
            MoonImpact.relaxationSteps(separation: separation, illuminatedFraction: 1, filter: filter,
                                       objectKind: .emissionNebula)
        }
        XCTAssertEqual(steps(0), 0)
        XCTAssertEqual(steps(39.999), 0)
        XCTAssertEqual(steps(40), 1)
        XCTAssertEqual(steps(180), 1)
        // A full Moon 39.999° away is severe either way; at 40° the filter makes it moderate.
        XCTAssertEqual(assess(39.999, 1, filter), .severe)
        XCTAssertEqual(assess(40, 1, filter), .moderate)
        XCTAssertEqual(assess(40, 1, .none), .severe)
        // Moderate becomes minor.
        XCTAssertEqual(assess(50, 0.5, .none), .moderate)
        XCTAssertEqual(assess(50, 0.5, filter), .minor)
        XCTAssertEqual(assess(30, 0.5, filter), .moderate)
    }

    func testDualNarrowbandTakesOneStepOffAlwaysAndTwoFromSixtyDegrees() {
        let filter = ImagingFilter.dualNarrowband
        func steps(_ separation: Double, _ fraction: Double = 1) -> Int {
            MoonImpact.relaxationSteps(separation: separation, illuminatedFraction: fraction, filter: filter,
                                       objectKind: .planetaryNebula)
        }
        XCTAssertEqual(steps(0), 1)
        XCTAssertEqual(steps(59.999), 1)
        XCTAssertEqual(steps(60), 2)
        XCTAssertEqual(steps(180, 0.1), 2)
        // A full Moon is severe up to and including 60°: one step less before 60°, two steps from it.
        XCTAssertEqual(assess(5, 1, filter), .moderate)
        XCTAssertEqual(assess(59.999, 1, filter), .moderate)
        XCTAssertEqual(assess(60, 1, filter), .minor)
        XCTAssertEqual(assess(59.999, 1, .none), .severe)
        // Moderate and minor cannot drop below minor.
        XCTAssertEqual(assess(70, 0.9, filter), .minor)
        XCTAssertEqual(assess(70, 0.1, filter), .minor)
    }

    func testNarrowbandTakesTwoStepsOffUnlessTheMoonIsCloseAndBright() {
        let filter = ImagingFilter.narrowband
        let kind = ObjectCategory.supernovaRemnant
        func steps(_ separation: Double, _ fraction: Double) -> Int {
            MoonImpact.relaxationSteps(separation: separation, illuminatedFraction: fraction, filter: filter,
                                       objectKind: kind)
        }
        XCTAssertEqual(steps(31, 1), 2)
        XCTAssertEqual(steps(30.001, 1), 2)
        XCTAssertEqual(steps(30, 1), 1)
        XCTAssertEqual(steps(0, 0.5), 1)
        XCTAssertEqual(steps(30, 0.4999), 2)
        XCTAssertEqual(steps(0, 0), 2)
        XCTAssertEqual(steps(180, 1), 2)
        // A full Moon is severe at 30° and 31°: within 30° it goes down to moderate, beyond it to minor.
        XCTAssertEqual(assess(30, 1, .none, kind), .severe)
        XCTAssertEqual(assess(30, 1, filter, kind), .moderate)
        XCTAssertEqual(assess(30.001, 1, filter, kind), .minor)
        XCTAssertEqual(assess(31, 1, filter, kind), .minor)
        // A 60 % lit Moon at 5° is severe, and the filter makes it moderate; half lit at 30° it is moderate, then minor.
        XCTAssertEqual(assess(5, 0.6, .none, kind), .severe)
        XCTAssertEqual(assess(5, 0.6, filter, kind), .moderate)
        XCTAssertEqual(assess(30, 0.5, filter, kind), .minor)
    }

    func testAStrongerFilterNeverTakesFewerSteps() {
        let order: [ImagingFilter] = [.none, .lightPollution, .dualNarrowband, .narrowband]
        for kind in emissionKinds {
            for separation in separations {
                for fraction in fractions {
                    let steps = order.map {
                        MoonImpact.relaxationSteps(separation: separation, illuminatedFraction: fraction, filter: $0,
                                                   objectKind: kind)
                    }
                    XCTAssertEqual(steps.sorted(), steps, "\(kind.rawValue) separation \(separation) fraction \(fraction)")
                    XCTAssertTrue(steps.allSatisfy { (0...2).contains($0) })
                }
            }
        }
    }

    func testFiltersOnlyEverLowerTheLevelAndLeaveTheMoonBeingDown() {
        let rank = Dictionary(uniqueKeysWithValues: Level.allCases.enumerated().map { ($0.element, $0.offset) })
        for kind in emissionKinds {
            for separation in separations {
                for fraction in fractions {
                    let broadband = assess(separation, fraction, .none, kind)
                    for filter in ImagingFilter.allCases {
                        let level = assess(separation, fraction, filter, kind)
                        XCTAssertLessThanOrEqual(rank[level] ?? -1, rank[broadband] ?? -1,
                                                 "\(filter.rawValue) \(separation) \(fraction)")
                        XCTAssertNotEqual(level, .moonDown)
                        // Relaxing never goes below minor.
                        XCTAssertGreaterThanOrEqual(rank[level] ?? -1, rank[.minor] ?? 99)
                    }
                }
            }
        }
    }

    // MARK: Levels and weights

    func testLoweringStopsAtMinorAndNeverTouchesMoonDown() {
        XCTAssertEqual(Level.severe.lowered(steps: 1), .moderate)
        XCTAssertEqual(Level.severe.lowered(steps: 2), .minor)
        XCTAssertEqual(Level.severe.lowered(steps: 9), .minor)
        XCTAssertEqual(Level.moderate.lowered(steps: 1), .minor)
        XCTAssertEqual(Level.minor.lowered(steps: 1), .minor)
        XCTAssertEqual(Level.moonDown.lowered(steps: 2), .moonDown)
        XCTAssertEqual(Level.severe.lowered(steps: 0), .severe)
        XCTAssertEqual(Level.moderate.lowered(steps: -3), .moderate)
    }

    func testTheMoonFreeWeightFallsWithTheLevel() {
        let weights = [Level.moonDown, .minor, .moderate, .severe].map { MoonImpact.moonFreeWeight(level: $0) }
        XCTAssertEqual(weights, [1.0, 0.9, 0.7, 0.4])
        XCTAssertEqual(weights.sorted(by: >), weights)
        XCTAssertTrue(weights.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    func testAFilterRaisesTheWeightOfAnEmissionTargetUnderABrightMoonAndNobodyElses() {
        // A bright Moon 20° away: severe for everything without a filter.
        let broadband = MoonImpact.moonFreeWeight(level: assess(20, 1, .none))
        XCTAssertEqual(broadband, 0.4)
        XCTAssertEqual(MoonImpact.moonFreeWeight(level: assess(20, 1, .narrowband)), 0.7)
        XCTAssertEqual(MoonImpact.moonFreeWeight(level: assess(20, 1, .lightPollution)), 0.4)
        for kind in otherKinds {
            for filter in ImagingFilter.allCases {
                XCTAssertEqual(MoonImpact.moonFreeWeight(level: assess(20, 1, filter, kind)), 0.4,
                               "\(filter.rawValue) \(kind.rawValue)")
            }
        }
        // 80° away the narrowband filter takes the target to minor.
        XCTAssertEqual(MoonImpact.moonFreeWeight(level: assess(80, 1, .narrowband)), 0.9)
        XCTAssertEqual(MoonImpact.moonFreeWeight(level: assess(80, 1, .none)), 0.7)
    }

    // MARK: Names and storage

    func testTheFiltersHaveStableRawValuesAndReadableText() {
        XCTAssertEqual(ImagingFilter.allCases.map(\.rawValue), ["none", "lightPollution", "dualNarrowband", "narrowband"])
        XCTAssertEqual(ImagingFilter.allCases.map(\.id), ImagingFilter.allCases.map(\.rawValue))
        for filter in ImagingFilter.allCases {
            XCTAssertEqual(ImagingFilter(rawValue: filter.rawValue), filter)
            XCTAssertFalse(filter.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(filter.summary.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(filter.summary.contains("\n"))
        }
        XCTAssertEqual(Set(ImagingFilter.allCases.map(\.displayName)).count, ImagingFilter.allCases.count)
        XCTAssertEqual(Set(ImagingFilter.allCases.map(\.summary)).count, ImagingFilter.allCases.count)
        XCTAssertEqual(ImagingFilter.none.displayName, "None")
        XCTAssertEqual(ImagingFilter.dualNarrowband.displayName, "Dual narrowband")
        XCTAssertNil(ImagingFilter(rawValue: "Narrowband"))
        XCTAssertNil(ImagingFilter(rawValue: ""))
    }

    func testFiltersAndLevelsStoreAsTheirRawValues() throws {
        let filters = String(decoding: try JSONEncoder().encode(ImagingFilter.allCases), as: UTF8.self)
        XCTAssertEqual(filters, "[\"none\",\"lightPollution\",\"dualNarrowband\",\"narrowband\"]")
        XCTAssertEqual(try JSONDecoder().decode([ImagingFilter].self, from: Data("[\"dualNarrowband\",\"none\"]".utf8)),
                       [.dualNarrowband, .none])
        let levels = String(decoding: try JSONEncoder().encode(Level.allCases), as: UTF8.self)
        XCTAssertEqual(levels, "[\"moonDown\",\"minor\",\"moderate\",\"severe\"]")
        for level in Level.allCases {
            XCTAssertEqual(Level(rawValue: level.rawValue), level)
        }
        XCTAssertNil(Level(rawValue: "extreme"))
    }
}
