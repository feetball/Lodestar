import Foundation

/// How the camera is held while shooting a mosaic.
///
/// The planner works with the frame as the photographer sees it: for `landscape` the sensor's width runs
/// along the rows of the mosaic, for `portrait` (the camera turned a quarter turn) its height does.
public enum MosaicOrientation: String, CaseIterable, Codable, Hashable, Sendable {
    /// The long side of the sensor runs along the rows.
    case landscape
    /// The short side of the sensor runs along the rows; the camera is turned a quarter turn.
    case portrait

    /// `size`, a camera frame in landscape, as it appears in this orientation: swapped for `portrait`.
    public func oriented(_ size: FrameSize) -> FrameSize {
        self == .portrait ? size.rotated : size
    }
}

/// The coordinate system a mosaic is planned in.
///
/// Equatorial plans follow the stars (panel centres are J2000 places), horizontal plans follow the
/// observer's horizon (panel centres are fixed azimuth and altitude).
public enum MosaicFrameKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Panels are placed in J2000 right ascension and declination.
    case equatorial
    /// Panels are placed in azimuth and altitude.
    case horizontal
}

/// The part of the sky a mosaic has to cover.
///
/// Values are not checked when they are created; `MosaicPlanner.plan` throws a `MosaicError` for an
/// unusable region.
public enum MosaicRegion: Hashable, Sendable {
    /// A rectangle on the sky, planned in J2000 right ascension and declination.
    ///
    /// The rows of the mosaic follow the rectangle's width axis. At position angle 0 they follow circles of
    /// constant declination, and the region is the band between two declinations and two hour circles: its
    /// `height` is measured along a meridian and its `width` along the declination circle through the
    /// `center` (an arc of that circle, so near a pole the right-ascension span is wider than `width`).
    /// A position angle turns the whole rectangle about its centre.
    ///
    /// - `center`: The centre of the rectangle, a J2000 place.
    /// - `width`: The extent along the rows in degrees, in (0, 360].
    /// - `height`: The extent across the rows in degrees, in (0, 180].
    /// - `positionAngle`: The direction of the height axis in degrees, measured from north through east: 0 keeps
    ///   the height axis north-south and the width axis along the declination circle, 90 turns the rectangle so
    ///   that its height runs east-west and its width north-south.
    case equatorial(center: EquatorialCoordinate, width: Double, height: Double, positionAngle: Double = 0)

    /// An azimuth and altitude box, for a panorama shot from a fixed tripod.
    ///
    /// The mosaic follows circles of constant altitude, with the camera held level.
    ///
    /// - `azimuthStart`: The azimuth of the left edge of the box in degrees, from north through east. The box
    ///   extends from there towards increasing azimuth.
    /// - `azimuthSpan`: The azimuth extent in degrees, in (0, 360]; 360 is a full-circle panorama.
    /// - `minimumAltitude`: The altitude of the lower edge in degrees, in [−90, 90).
    /// - `maximumAltitude`: The altitude of the upper edge in degrees, in (−90, 90], above `minimumAltitude`.
    case horizontal(azimuthStart: Double, azimuthSpan: Double, minimumAltitude: Double, maximumAltitude: Double)

    /// The margin, as a fraction of the object's size, that `fitting` adds by default.
    public static let defaultMargin = 0.2

    /// The largest margin `fitting` accepts.
    public static let maximumMargin = 2.0

    /// The region that fits an object of `size` centred on `center`, with a margin all round.
    ///
    /// The width is the object's major axis and the height its minor axis (a round object gets a square
    /// region), each enlarged by `margin`; the region is turned so that its width runs along the object's
    /// major axis (`AngularSize.positionAngle`, north-south when the catalog gives none).
    ///
    /// - Parameters:
    ///   - center: The object's J2000 place.
    ///   - size: The object's angular size.
    ///   - margin: The margin as a fraction of each axis, in [0, `maximumMargin`]: 0.2 makes the region 20 % larger
    ///     than the object.
    /// - Throws: `MosaicError.invalidMargin` if the margin is not in range, `MosaicError.invalidWidth` if the
    ///   enlarged major axis is more than a full circle.
    public static func fitting(center: EquatorialCoordinate, size: AngularSize,
                               margin: Double = MosaicRegion.defaultMargin) throws -> MosaicRegion {
        guard margin >= 0, margin <= maximumMargin else { throw MosaicError.invalidMargin(value: margin) }
        let scale = 1 + margin
        let width = size.majorArcminutes / 60 * scale
        let height = (size.minorArcminutes ?? size.majorArcminutes) / 60 * scale
        guard width > 0, width <= 360 else { throw MosaicError.invalidWidth(value: width) }
        guard height > 0, height <= 180 else { throw MosaicError.invalidHeight(value: height) }
        return .equatorial(center: center, width: width, height: height,
                           positionAngle: AstroMath.normalizeDegrees((size.positionAngle ?? 0) - 90))
    }

    /// The region that fits a catalog object, see `fitting(center:size:margin:)`.
    ///
    /// - Parameters:
    ///   - object: A fixed object with a catalog size.
    ///   - margin: The margin as a fraction of each axis.
    /// - Throws: `MosaicError.objectNotFixed` if the object moves (solar-system bodies) or is a celestial pole,
    ///   `MosaicError.objectHasNoSize` if the catalog has no size for the object.
    public static func fitting(object: CelestialObject, margin: Double = MosaicRegion.defaultMargin) throws -> MosaicRegion {
        guard let center = object.j2000 else { throw MosaicError.objectNotFixed(objectID: object.id) }
        guard let size = object.angularSize else { throw MosaicError.objectHasNoSize(objectID: object.id) }
        return try fitting(center: center, size: size, margin: margin)
    }

    /// A horizontal box given by its centre and extent, with the altitudes limited to [−90, 90].
    ///
    /// - Parameters:
    ///   - centerAzimuth: The azimuth of the middle of the box in degrees.
    ///   - centerAltitude: The altitude of the middle of the box in degrees.
    ///   - azimuthSpan: The azimuth extent in degrees.
    ///   - altitudeSpan: The altitude extent in degrees.
    public static func centered(centerAzimuth: Double, centerAltitude: Double, azimuthSpan: Double,
                                altitudeSpan: Double) -> MosaicRegion {
        .horizontal(azimuthStart: AstroMath.normalizeDegrees(centerAzimuth - azimuthSpan / 2),
                    azimuthSpan: azimuthSpan,
                    minimumAltitude: AstroMath.clamp(centerAltitude - altitudeSpan / 2, -90, 90),
                    maximumAltitude: AstroMath.clamp(centerAltitude + altitudeSpan / 2, -90, 90))
    }
}

/// Why a mosaic could not be planned.
public enum MosaicError: Error, Hashable, Sendable {
    /// A value of the region, the frame or the observer is not a finite number.
    case nonFiniteInput
    /// The region's width is not in (0, 360] degrees.
    case invalidWidth(value: Double)
    /// The region's height is not in (0, 180] degrees.
    case invalidHeight(value: Double)
    /// The horizontal region's azimuth span is not in (0, 360] degrees.
    case invalidAzimuthSpan(value: Double)
    /// The horizontal region's altitudes are not ordered within [−90, 90] degrees.
    case invalidAltitudeRange(minimum: Double, maximum: Double)
    /// The overlap is not in `MosaicPlanner.overlapRange`.
    case invalidOverlap(value: Double)
    /// The margin of a fitted region is not in [0, `MosaicRegion.maximumMargin`].
    case invalidMargin(value: Double)
    /// The camera frame is not a pair of angles in (0, 180) degrees.
    case invalidFrame(horizontal: Double, vertical: Double)
    /// The observer's latitude is not in [−90, 90] degrees.
    case invalidLatitude(value: Double)
    /// The mosaic would need `count` panels, more than the `limit` the planner will handle.
    case tooManyPanels(count: Int, limit: Int)
    /// The object is a solar-system body or a pole, so it has no fixed place to plan a mosaic on.
    case objectNotFixed(objectID: String)
    /// The catalog has no angular size for the object.
    case objectHasNoSize(objectID: String)
}

/// A direction on the sky, in the coordinate system of the plan that produced it.
public enum MosaicPoint: Hashable, Sendable {
    /// A J2000 place of an equatorial plan.
    case equatorial(EquatorialCoordinate)
    /// An azimuth and altitude of a horizontal plan.
    case horizontal(HorizontalCoordinate)

    /// The J2000 place, or nil for a horizontal point.
    public var equatorialCoordinate: EquatorialCoordinate? {
        if case let .equatorial(coordinate) = self { return coordinate }
        return nil
    }

    /// The azimuth and altitude, or nil for an equatorial point.
    public var horizontalCoordinate: HorizontalCoordinate? {
        if case let .horizontal(coordinate) = self { return coordinate }
        return nil
    }

    /// The unit vector of the direction: J2000 equatorial for an equatorial point, ENU for a horizontal point.
    public var unitVector: Vector3 {
        switch self {
        case let .equatorial(coordinate): coordinate.unitVector
        case let .horizontal(coordinate): coordinate.unitVector
        }
    }
}

/// One frame of a mosaic.
///
/// Panels are numbered in row-major order: `index` runs along the top row from the left, then along the next
/// row, and so on. Rows count downwards from the pole side of the mosaic (north for equatorial plans, the
/// zenith for horizontal plans) and columns count from the left edge of the image, which is east for an
/// equatorial plan and the start of the azimuth range for a horizontal plan. The picture of the grid is
/// therefore what the stitched image looks like.
public struct MosaicPanel: Hashable, Sendable {
    /// The panel's position in row-major order, from 0.
    public let index: Int
    /// The row, from 0 at the top.
    public let row: Int
    /// The column within its row, from 0 at the left. Rows may have different numbers of columns.
    public let column: Int
    /// The direction of the optical axis.
    public let center: MosaicPoint
    /// The four corners of the frame for drawing: top left, top right, bottom right, bottom left. The edges
    /// between them are great-circle arcs, which is how a rectilinear lens sees straight lines.
    public let corners: [MosaicPoint]
    /// The place of the panel in the shooting order, from 0.
    public let shootingPosition: Int

    /// A short name for lists: "R2C3" is the third panel of the second row.
    public var id: String { "R\(row + 1)C\(column + 1)" }

    /// The outline of the frame with each edge divided into `segmentsPerEdge` great-circle steps, for charts
    /// that do not draw great circles as straight lines.
    ///
    /// - Parameter segmentsPerEdge: Steps per edge, limited to 1...64.
    /// - Returns: The points of the outline in the order of `corners`, starting at the top left corner and not
    ///   repeating it at the end: `4 × segmentsPerEdge` points.
    public func outline(segmentsPerEdge: Int = 8) -> [MosaicPoint] {
        let steps = AstroMath.clamp(segmentsPerEdge, 1, 64)
        var result = [MosaicPoint]()
        result.reserveCapacity(steps * 4)
        for edge in 0..<4 {
            let from = corners[edge]
            let to = corners[(edge + 1) % 4]
            let a = from.unitVector
            let b = to.unitVector
            let angle = a.angleRadians(to: b)
            for step in 0..<steps {
                let fraction = Double(step) / Double(steps)
                let vector: Vector3
                if angle > 1e-12 {
                    let sinAngle = sin(angle)
                    vector = a * (sin((1 - fraction) * angle) / sinAngle) + b * (sin(fraction * angle) / sinAngle)
                } else {
                    vector = a
                }
                switch from {
                case .equatorial: result.append(.equatorial(EquatorialCoordinate(vector: vector)))
                case .horizontal: result.append(.horizontal(HorizontalCoordinate(vector: vector)))
                }
            }
        }
        return result
    }
}

/// How much of the region a plan covers.
public struct MosaicCoverage: Hashable, Sendable {
    /// The extent of the mosaic along its rows, in degrees of arc measured along the parallel of the row
    /// nearest the middle of the plan.
    public let widthDegrees: Double
    /// The extent across the rows along the central meridian, in degrees.
    public let heightDegrees: Double
    /// The extent along the rows in degrees of longitude about the plan's pole: the azimuth span of a
    /// horizontal plan, the right-ascension span of an equatorial plan with position angle 0.
    public let longitudeSpanDegrees: Double
    /// The area of the requested region.
    public let regionAreaSquareDegrees: Double
    /// The sum of the areas of all frames; larger than the region by the overlap and by what the frames add at
    /// the edges.
    public let panelAreaSquareDegrees: Double
    /// The fraction of the region that lies inside at least one frame, [0, 1], measured on a 41 by 61 lattice of
    /// points that includes the region's edges and corners.
    public let coveredFraction: Double
}

/// A caution about a plan. The plan is still usable.
public enum MosaicWarning: Hashable, Sendable {
    /// The plan has more than `MosaicPlanner.recommendedPanelLimit` panels: shooting it takes long and the sky
    /// moves meanwhile.
    case tooManyPanels(count: Int)
    /// The planner could not place the frames so that the whole region is covered with the requested overlap:
    /// only `coveredFraction` of the sampled region is inside a frame.
    case overlapNotMet(coveredFraction: Double)
}

/// The panels needed to cover a region, and the order to shoot them in.
///
/// Created by `MosaicPlanner.plan` only.
public struct MosaicPlan: Hashable, Sendable {
    /// The region that was planned.
    public let region: MosaicRegion
    /// Whether the panels are placed in equatorial or horizontal coordinates.
    public let kind: MosaicFrameKind
    /// How the camera is held.
    public let orientation: MosaicOrientation
    /// The size of one frame on the sky as held: `horizontal` runs along the rows.
    public let frame: FrameSize
    /// The requested overlap, a fraction of the frame size.
    public let overlap: Double
    /// The smallest overlap the layout gives between neighbouring panels, or nil for a single panel. Along a
    /// row it is measured at the latitude where the frame is narrowest on the sphere, between rows on the
    /// central meridian. It is the requested overlap, or more when the planner had to add overlap to close
    /// gaps that the curved frame edges leave.
    public let achievedOverlap: Double?
    /// The number of rows.
    public let rows: Int
    /// The number of panels in each row, from the top. Rows nearer a pole of the grid need fewer panels for the
    /// same extent because they are shorter on the sphere.
    public let columnsPerRow: [Int]
    /// All panels in row-major order.
    public let panels: [MosaicPanel]
    /// The panel indices in the order to shoot them.
    public let shootingOrder: [Int]
    /// The point the rows circle: the north celestial pole for an equatorial plan with position angle 0 (turned
    /// with the position angle otherwise), the zenith for a horizontal plan. The top edge of each frame points
    /// towards it.
    public let pole: MosaicPoint
    /// What the plan covers.
    public let coverage: MosaicCoverage
    /// Cautions, empty for a plan that fits the region comfortably.
    public let warnings: [MosaicWarning]

    /// The number of panels.
    public var panelCount: Int { panels.count }

    /// The largest number of panels in a row.
    public var columns: Int { columnsPerRow.max() ?? 0 }

    /// `true` when every row has the same number of panels, so the plan is a plain rows × columns grid.
    public var isRectangular: Bool { columnsPerRow.allSatisfy { $0 == columnsPerRow[0] } }

    /// The grid as text for a title, for example "3 × 1" (columns × rows).
    public var gridDescription: String {
        isRectangular ? "\(columns) \u{00D7} \(rows)" : "\(panelCount) panels in \(rows) rows"
    }

    /// The panels in shooting order.
    public var orderedPanels: [MosaicPanel] { shootingOrder.map { panels[$0] } }

    /// The boundary of the requested region as closed polylines, for drawing it on a chart behind the panels.
    ///
    /// The top and bottom edges of the region are circles of latitude of the plan's grid, so they are sampled; the
    /// sides are great-circle arcs. The loop runs clockwise as seen in the picture of the stitched image: along the top edge
    /// from the left, down the right side, back along the bottom edge and up the left side.
    ///
    /// - Parameter pointsPerEdge: Points per side, limited to 2...256.
    /// - Returns: One loop of `4 × pointsPerEdge` points, or, for a region that wraps all the way round the pole,
    ///   two circles of `4 × pointsPerEdge` points, the upper and then the lower edge. A loop does not repeat its
    ///   first point at the end.
    public func regionOutline(pointsPerEdge: Int = 16) -> [[MosaicPoint]] {
        let extent: MosaicExtent
        switch region {
        case let .equatorial(center, width, height, positionAngle):
            extent = MosaicGeometry.extent(center: center, width: width, height: height, positionAngle: positionAngle)
        case let .horizontal(azimuthStart, azimuthSpan, minimumAltitude, maximumAltitude):
            extent = MosaicGeometry.extent(azimuthStart: azimuthStart, azimuthSpan: azimuthSpan,
                                           minimumAltitude: minimumAltitude, maximumAltitude: maximumAltitude)
        }
        let steps = AstroMath.clamp(pointsPerEdge, 2, 256)
        let half = extent.longitudeSpan / 2
        let high = extent.maximumLatitude
        let low = extent.minimumLatitude
        func point(_ longitude: Double, _ latitude: Double) -> MosaicPoint {
            MosaicGeometry.point(extent.basis.vector(longitude: longitude, latitude: latitude), kind: kind)
        }
        if extent.isRing {
            let count = steps * 4
            func circle(_ latitude: Double) -> [MosaicPoint] {
                (0..<count).map { point(180 - 360 * Double($0) / Double(count), latitude) }
            }
            return [circle(high), circle(low)]
        }
        var loop = [MosaicPoint]()
        loop.reserveCapacity(steps * 4)
        for step in 0..<steps { loop.append(point(half - extent.longitudeSpan * Double(step) / Double(steps), high)) }
        for step in 0..<steps { loop.append(point(-half, high - (high - low) * Double(step) / Double(steps))) }
        for step in 0..<steps { loop.append(point(-half + extent.longitudeSpan * Double(step) / Double(steps), low)) }
        for step in 0..<steps { loop.append(point(half, low + (high - low) * Double(step) / Double(steps))) }
        return [loop]
    }

    /// The panel at `row` and `column`, or nil if there is none.
    public func panel(row: Int, column: Int) -> MosaicPanel? {
        guard row >= 0, row < rows, column >= 0, column < columnsPerRow[row] else { return nil }
        return panels[columnsPerRow.prefix(row).reduce(0, +) + column]
    }
}
