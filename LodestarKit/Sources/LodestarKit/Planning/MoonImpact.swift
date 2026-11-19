import Foundation

/// The filter in front of the sensor, as far as moonlight is concerned.
public enum ImagingFilter: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    /// No filter, or a broadband one (UV/IR cut, luminance, colour).
    case none
    /// A light-pollution filter of the CLS or UHC type.
    case lightPollution
    /// A dual-band Hα + OIII filter, usually on a colour camera.
    case dualNarrowband
    /// A single narrowband filter (Hα, SII or OIII), usually on a monochrome camera.
    case narrowband

    /// A stable identifier, equal to the raw value.
    public var id: String { rawValue }

    /// A short name for pickers, for example "Dual narrowband".
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .lightPollution: return "Light pollution"
        case .dualNarrowband: return "Dual narrowband"
        case .narrowband: return "Narrowband"
        }
    }

    /// A one-line description of the filter and what it does about moonlight.
    public var summary: String {
        switch self {
        case .none:
            return "No filter or a broadband one. Moonlight is judged by phase and distance alone."
        case .lightPollution:
            return "A CLS or UHC-type filter. It helps a little with emission nebulae when the Moon is not close."
        case .dualNarrowband:
            return "An Hα + OIII dual-band filter. It keeps emission nebulae usable under most moonlight."
        case .narrowband:
            return "A mono Hα, SII or OIII filter. Emission nebulae stay usable even under a bright Moon."
        }
    }
}

/// How much the Moon disturbs a shot of one target, with the filter on the lens taken into account.
///
/// The broadband rule is the one the apps always used: the Moon's lit fraction times how close it is to the target.
/// A filter relaxes it only for targets that shine in emission lines (see `isEmissionLineTarget(_:)`).
///
/// Why a filter helps. Moonlight is sunlight scattered by the lunar surface and then by the atmosphere, so the glow it
/// adds to the sky is a continuum across the visible spectrum (Krisciunas and Schaefer 1991, "A model of the brightness
/// of moonlight", PASP 103, 1033). An emission nebula puts most of its light into a few lines: Hα at 656.3 nm, [OIII]
/// at 495.9 and 500.7 nm and [SII] at 671.6 and 673.1 nm (Osterbrock and Ferland 2006, "Astrophysics of Gaseous
/// Nebulae and Active Galactic Nuclei", 2nd ed.). A narrowband filter, typically 3 to 12 nm wide at each line, passes
/// the lines whole and only that sliver of the continuum, where a broadband filter passes about 300 nm of it. The
/// nebula's contrast against the moonlit sky therefore improves by about the ratio of the bandwidths, tens of times.
/// A dual-band filter does the same with wider or two bands, and a light-pollution filter passes a much wider band, so
/// it removes less moonlight. Galaxies, clusters, stars and reflection nebulae shine in a continuum (reflection
/// nebulae in scattered starlight, which has the same spectrum as the moonlight), so no filter separates them from
/// the glow. The number of steps each filter relaxes the level by is a rule of thumb that follows this reasoning; it
/// is not fitted to measurements.
///
/// Every function is pure and takes constant time.
public enum MoonImpact {
    /// How strongly the Moon disturbs a shot, from none to the worst.
    public enum Level: String, CaseIterable, Codable, Hashable, Sendable {
        /// The Moon is below the horizon.
        case moonDown
        /// The Moon is up but hardly matters.
        case minor
        /// Moonlight brightens the sky noticeably.
        case moderate
        /// A bright Moon close by washes out faint detail.
        case severe

        /// The level `steps` steps lower: severe to moderate to minor. `moonDown` and `minor` do not go lower.
        public func lowered(steps: Int) -> Level {
            guard self != .moonDown, steps > 0 else { return self }
            switch max(rank - steps, Level.minor.rank) {
            case Level.severe.rank: return .severe
            case Level.moderate.rank: return .moderate
            default: return .minor
            }
        }

        private var rank: Int {
            switch self {
            case .moonDown: return 0
            case .minor: return 1
            case .moderate: return 2
            case .severe: return 3
            }
        }
    }

    /// The Moon's lit fraction times its proximity at which the level becomes severe.
    private static let severeEffect = 0.5
    /// The Moon's lit fraction times its proximity at which the level becomes moderate.
    private static let moderateEffect = 0.2
    /// The separation, in degrees, at which the proximity of the Moon falls to zero before its floor applies.
    private static let proximityRange = 120.0
    /// The proximity of a far-away Moon: moonlight scatters across the whole sky.
    private static let proximityFloor = 0.25
    /// The least separation, in degrees, at which a light-pollution filter relaxes the level.
    private static let lightPollutionMinimumSeparation = 40.0
    /// The least separation, in degrees, at which a dual-band filter relaxes the level by two steps.
    private static let dualNarrowbandFullSeparation = 60.0
    /// The most separation, in degrees, at which a narrowband filter relaxes the level by one step only.
    private static let narrowbandCloseSeparation = 30.0
    /// The least lit fraction at which a close Moon holds a narrowband filter to one step.
    private static let narrowbandBrightFraction = 0.5

    /// How strongly the Moon disturbs a shot of a target of kind `objectKind` through `filter`.
    ///
    /// The Moon counts only when its altitude is above 0°; a value that is not finite counts as below. Without a
    /// filter the level follows the Moon's lit fraction times a proximity that falls from 1 at the target to 0.25 at
    /// 90° and beyond: 0.5 and over is severe, 0.2 and over moderate, else minor. The filter then lowers that level
    /// by `relaxationSteps(separation:illuminatedFraction:filter:objectKind:)` steps, never below minor. A
    /// `separation` or `illuminatedFraction` that is not finite cannot be judged and gives minor; the fraction is
    /// limited to 0…1 and the separation to 0…180°.
    ///
    /// - Parameters:
    ///   - moonAltitude: The Moon's altitude in degrees, geometric.
    ///   - separation: The angle between the Moon and the target in degrees.
    ///   - illuminatedFraction: The lit fraction of the Moon's disc, 0…1.
    ///   - filter: The filter in use.
    ///   - objectKind: The target's category.
    public static func assess(moonAltitude: Double, separation: Double, illuminatedFraction: Double,
                              filter: ImagingFilter, objectKind: ObjectCategory) -> Level {
        guard moonAltitude.isFinite, moonAltitude > 0 else { return .moonDown }
        guard separation.isFinite, illuminatedFraction.isFinite else { return .minor }
        let angle = min(max(separation, 0), 180)
        let lit = min(max(illuminatedFraction, 0), 1)
        // Moonlight scatters across the whole sky but is strongest near the Moon.
        let proximity = min(max(1 - angle / proximityRange, proximityFloor), 1)
        let effect = lit * proximity
        let broadband: Level
        if effect >= severeEffect {
            broadband = .severe
        } else if effect >= moderateEffect {
            broadband = .moderate
        } else {
            broadband = .minor
        }
        return broadband.lowered(steps: relaxationSteps(separation: angle, illuminatedFraction: lit, filter: filter,
                                                        objectKind: objectKind))
    }

    /// How many steps `filter` lowers the level for a target of kind `objectKind` with the Moon `separation` degrees
    /// away and `illuminatedFraction` lit; 0, 1 or 2.
    ///
    /// - `ImagingFilter.none` and every target that is not an emission-line target: 0.
    /// - `ImagingFilter.lightPollution`: 1 from a separation of 40°, else 0.
    /// - `ImagingFilter.dualNarrowband`: 1, and 2 from a separation of 60°.
    /// - `ImagingFilter.narrowband`: 2, but 1 when the Moon is within 30° (30° included) and at least half lit.
    ///
    /// A value that is not finite gives 0.
    public static func relaxationSteps(separation: Double, illuminatedFraction: Double, filter: ImagingFilter,
                                       objectKind: ObjectCategory) -> Int {
        guard isEmissionLineTarget(objectKind) else { return 0 }
        guard separation.isFinite, illuminatedFraction.isFinite else { return 0 }
        switch filter {
        case .none:
            return 0
        case .lightPollution:
            return separation >= lightPollutionMinimumSeparation ? 1 : 0
        case .dualNarrowband:
            return separation >= dualNarrowbandFullSeparation ? 2 : 1
        case .narrowband:
            return separation <= narrowbandCloseSeparation && illuminatedFraction >= narrowbandBrightFraction ? 1 : 2
        }
    }

    /// Whether a target of this category shines mainly in emission lines, so that a filter can separate it from
    /// moonlight: emission nebulae (OpenNGC `HII`, `EmN`), planetary nebulae (`PN`), supernova remnants (`SNR`) and
    /// clusters with nebulosity (`Cl+N`, which are embedded in emission nebulae). Wolf-Rayet shells and similar are
    /// typed `HII` or `EmN` in the catalog. The generic nebula (`Neb`) is left out here because that type mixes
    /// emission and reflection nebulae (see `isEmissionLineTarget(_:)` for an object, which tells them apart); so are
    /// dark and reflection nebulae, galaxies, clusters, stars, the Milky Way and every solar-system body.
    public static func isEmissionLineTarget(_ objectKind: ObjectCategory) -> Bool {
        switch objectKind {
        case .emissionNebula, .planetaryNebula, .supernovaRemnant, .clusterWithNebula:
            return true
        default:
            return false
        }
    }

    /// Whether `object` shines mainly in emission lines: its category is one of `isEmissionLineTarget(_:)`'s, or it is
    /// a generic nebula (OpenNGC `Neb`) that carries a Sharpless number (`Sh2-25` for M8). Sharpless's catalogue lists
    /// H II regions only (Sharpless 1959, "A Catalogue of H II Regions", ApJS 4, 257), so a generic nebula in it is an
    /// emission nebula, where the other generic nebulae (the Iris Nebula, the Merope Nebula) are reflection nebulae.
    /// The catalogue numbers of the object decide; no object is named.
    public static func isEmissionLineTarget(_ object: CelestialObject) -> Bool {
        isEmissionLineTarget(assessmentKind(of: object))
    }

    /// The kind to hand to `assess(moonAltitude:separation:illuminatedFraction:filter:objectKind:)` for `object`: its
    /// category, except that a generic nebula with a Sharpless number counts as an emission nebula (see
    /// `isEmissionLineTarget(_:)` for an object).
    public static func assessmentKind(of object: CelestialObject) -> ObjectCategory {
        if object.category == .nebula, object.catalogues.contains(.sharpless) {
            return .emissionNebula
        }
        return object.category
    }

    /// How much a target at `level` counts when targets are ranked: 1 for a dark sky, falling to 0.4 for a severe
    /// Moon. A ranking multiplies a target's score by it, so a target that the Moon spoils drops behind one that it
    /// leaves alone. The values are a ranking heuristic: minor 0.9, moderate 0.7, severe 0.4.
    public static func moonFreeWeight(level: Level) -> Double {
        switch level {
        case .moonDown: return 1
        case .minor: return 0.9
        case .moderate: return 0.7
        case .severe: return 0.4
        }
    }
}
