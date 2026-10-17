import Foundation

/// One of the 88 IAU constellations, with its stick figure.
public struct Constellation: Identifiable, Hashable, Sendable {
    /// The IAU abbreviation, which is also the identifier ("CMa").
    public var id: String { abbreviation }
    /// The IAU three-letter abbreviation ("CMa").
    public let abbreviation: String
    /// The English name ("Canis Major").
    public let name: String
    /// The genitive form used in star names ("Canis Majoris").
    public let genitive: String
    /// Where to put the constellation's label, as a J2000 position.
    public let labelPosition: EquatorialCoordinate
    /// The stick figure as polylines of J2000 positions.
    ///
    /// Consecutive vertices are joined by great-circle arcs; a polyline may cross right ascension
    /// 0°/360°, so interpolate on the sphere rather than in right ascension.
    public let lines: [[EquatorialCoordinate]]

    init(abbreviation: String, name: String, genitive: String, labelPosition: EquatorialCoordinate,
         lines: [[EquatorialCoordinate]]) {
        self.abbreviation = abbreviation
        self.name = name
        self.genitive = genitive
        self.labelPosition = labelPosition
        self.lines = lines
    }
}

/// The brightness outlines of the Milky Way as polygons on the celestial sphere.
public struct MilkyWayOutline: Hashable, Sendable {
    /// The outlines of one brightness level.
    public struct Level: Hashable, Sendable {
        /// The brightness level, from 1 (the faint outer glow) to 5 (the bright core).
        public let level: Int
        /// Filled rings of J2000 positions. A ring is implicitly closed (its first vertex is not repeated).
        public let polygons: [[EquatorialCoordinate]]
        /// Rings of J2000 positions that are cut out of the filled area (dark lanes).
        ///
        /// Fill `polygons` and `holes` together with the even-odd rule, or fill the polygons and
        /// then punch out the holes.
        public let holes: [[EquatorialCoordinate]]

        init(level: Int, polygons: [[EquatorialCoordinate]], holes: [[EquatorialCoordinate]]) {
            self.level = level
            self.polygons = polygons
            self.holes = holes
        }
    }

    /// The levels in ascending order.
    ///
    /// Edges are great-circle arcs between consecutive vertices, so subdivide long edges before
    /// drawing a wide field of view. The level-1 band circles the whole sky; it is cut along right
    /// ascension 180° by a zero-width slit that must not be stroked.
    public let levels: [Level]

    init(levels: [Level]) {
        self.levels = levels
    }
}
