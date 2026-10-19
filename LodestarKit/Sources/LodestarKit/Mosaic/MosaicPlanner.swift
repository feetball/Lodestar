import Foundation

/// Plans the panels of a mosaic: how many frames cover a region of the sky, where each one points, and in
/// what order to shoot them.
///
/// ## Geometry
///
/// The rows of a mosaic follow circles of constant latitude about a pole: the celestial pole for an
/// equatorial plan, the zenith for a horizontal plan. Every frame is a rectilinear (gnomonic) view whose top
/// edge points to that pole, so its edges are great-circle arcs. The number of rows follows from the extent
/// across the rows. The number of columns is worked out for each row from its real width on the sphere: a
/// row near the pole is shorter than one at the equator, and a frame also covers less longitude on the
/// side of its band that lies nearer the equator, so each row is spaced for the narrowest longitude width
/// the frame has within the band of latitudes that row is responsible for.
///
/// The **overlap** is the fraction of the frame that neighbouring panels share, measured along the row at the
/// row's narrowest latitude and across the rows on the central meridian: with 25 % overlap a 54° frame
/// advances 40.5°. Because the edges of a frame are great circles, not circles of latitude, a frame's top
/// and bottom edges bow away from the grid towards the sides, which leaves slivers uncovered at the region's
/// edges. The planner checks every plan on a lattice of 41 × 61 points of the region (including its edges and
/// corners) and, when a point is outside every frame, adds a little overlap and extends the grid beyond the
/// region by the same fraction of the frame, repeating up to 20 times. The extension is at most 0.4 of a
/// frame. If the region is still not covered the plan carries `MosaicWarning.overlapNotMet`.
///
/// ## Cost
///
/// A plan takes about a millisecond for a dozen panels and a few milliseconds for 100; a plan that needs the
/// largest number of attempts is a few times slower. Plan when the user changes an input, not per frame.
public enum MosaicPlanner {
    /// The overlap used when the caller has no preference: 25 % of the frame.
    public static let defaultOverlap = 0.25

    /// The overlaps the planner accepts: 10 % to 50 % of the frame.
    public static let overlapRange: ClosedRange<Double> = 0.10...0.50

    /// Plans with more panels than this carry `MosaicWarning.tooManyPanels`.
    public static let recommendedPanelLimit = 100

    /// Plans with more panels than this are refused with `MosaicError.tooManyPanels`.
    public static let maximumPanelCount = 500

    /// Plans a mosaic for a camera with the given `frame` size (landscape, as `LensSetup.fieldOfView` reports it).
    ///
    /// - Parameters:
    ///   - region: The part of the sky to cover.
    ///   - frame: The angular size of one frame in landscape orientation.
    ///   - orientation: How the camera is held: landscape keeps the long side along the rows.
    ///   - overlap: The fraction of the frame that neighbouring panels share, in `overlapRange`.
    ///   - observerLatitude: The observer's latitude in degrees, [−90, 90], used to find which panels of an
    ///     equatorial plan set first; nil orders them by right ascension alone (the western end first).
    ///   - reverseOrder: Reverses the shooting order, to start from the other end.
    /// - Throws: `MosaicError` for a region, frame, overlap or latitude that is not usable, and when the mosaic
    ///   needs more than `maximumPanelCount` panels.
    public static func plan(region: MosaicRegion, frame: FrameSize, orientation: MosaicOrientation = .landscape,
                            overlap: Double = MosaicPlanner.defaultOverlap, observerLatitude: Double? = nil,
                            reverseOrder: Bool = false) throws -> MosaicPlan {
        try plan(region: region, frame: frame, orientation: orientation, overlap: overlap,
                 observerLatitude: observerLatitude, reverseOrder: reverseOrder,
                 maximumAttempts: MosaicGeometry.maximumAttempts)
    }

    /// `plan(region:frame:orientation:overlap:observerLatitude:reverseOrder:)` with a limit on the attempts that
    /// widen the layout to close gaps; the tests use it to reach the warning.
    static func plan(region: MosaicRegion, frame: FrameSize, orientation: MosaicOrientation, overlap: Double,
                     observerLatitude: Double?, reverseOrder: Bool, maximumAttempts: Int) throws -> MosaicPlan {
        let extent = try validated(region)
        guard frame.horizontal.isFinite, frame.vertical.isFinite else { throw MosaicError.nonFiniteInput }
        guard frame.horizontal > 0, frame.horizontal < 180, frame.vertical > 0, frame.vertical < 180 else {
            throw MosaicError.invalidFrame(horizontal: frame.horizontal, vertical: frame.vertical)
        }
        guard overlapRange.contains(overlap) else { throw MosaicError.invalidOverlap(value: overlap) }
        if let latitude = observerLatitude, !(latitude >= -90 && latitude <= 90) {
            throw MosaicError.invalidLatitude(value: latitude)
        }

        let oriented = orientation.oriented(frame)
        let tanHalfWidth = AstroMath.tanDeg(oriented.horizontal / 2)
        let tanHalfHeight = AstroMath.tanDeg(oriented.vertical / 2)
        let samples = MosaicGeometry.samples(extent: extent)

        var attempt = 0
        var layout = try MosaicGeometry.layout(extent: extent, tanHalfWidth: tanHalfWidth, tanHalfHeight: tanHalfHeight,
                                               frameHeight: oriented.vertical, overlap: overlap, padding: 0)
        var axes = MosaicGeometry.axes(layout: layout, basis: extent.basis)
        while MosaicGeometry.coveredFraction(samples: samples, frames: axes, tanHalfWidth: tanHalfWidth,
                                             tanHalfHeight: tanHalfHeight, stopAtGap: true) < 1,
              attempt + 1 < maximumAttempts {
            attempt += 1
            let padding = Double(attempt) * MosaicGeometry.attemptStep
            let effective = min(overlap + padding, MosaicGeometry.maximumOverlap)
            guard let next = try? MosaicGeometry.layout(extent: extent, tanHalfWidth: tanHalfWidth,
                                                        tanHalfHeight: tanHalfHeight, frameHeight: oriented.vertical,
                                                        overlap: effective, padding: padding) else { break }
            layout = next
            axes = MosaicGeometry.axes(layout: next, basis: extent.basis)
        }
        let covered = MosaicGeometry.coveredFraction(samples: samples, frames: axes, tanHalfWidth: tanHalfWidth,
                                                     tanHalfHeight: tanHalfHeight, stopAtGap: false)

        let columnsPerRow = layout.columnLongitudes.map(\.count)
        let order = shootingOrder(region: region, columnsPerRow: columnsPerRow, axes: axes,
                                  observerLatitude: observerLatitude, reverseOrder: reverseOrder)
        var position = [Int](repeating: 0, count: axes.count)
        for (place, index) in order.enumerated() { position[index] = place }

        var panels = [MosaicPanel]()
        panels.reserveCapacity(axes.count)
        var index = 0
        for row in columnsPerRow.indices {
            for column in 0..<columnsPerRow[row] {
                let frameAxes = axes[index]
                let corners = [
                    point(MosaicGeometry.corner(axes: frameAxes, horizontalSign: -1, verticalSign: 1,
                                                tanHalfWidth: tanHalfWidth, tanHalfHeight: tanHalfHeight), kind: extent.kind),
                    point(MosaicGeometry.corner(axes: frameAxes, horizontalSign: 1, verticalSign: 1,
                                                tanHalfWidth: tanHalfWidth, tanHalfHeight: tanHalfHeight), kind: extent.kind),
                    point(MosaicGeometry.corner(axes: frameAxes, horizontalSign: 1, verticalSign: -1,
                                                tanHalfWidth: tanHalfWidth, tanHalfHeight: tanHalfHeight), kind: extent.kind),
                    point(MosaicGeometry.corner(axes: frameAxes, horizontalSign: -1, verticalSign: -1,
                                                tanHalfWidth: tanHalfWidth, tanHalfHeight: tanHalfHeight), kind: extent.kind),
                ]
                panels.append(MosaicPanel(index: index, row: row, column: column,
                                          center: point(frameAxes.center, kind: extent.kind), corners: corners,
                                          shootingPosition: position[index]))
                index += 1
            }
        }

        var warnings = [MosaicWarning]()
        if panels.count > recommendedPanelLimit { warnings.append(.tooManyPanels(count: panels.count)) }
        if covered < 1 { warnings.append(.overlapNotMet(coveredFraction: covered)) }

        return MosaicPlan(
            region: region, kind: extent.kind, orientation: orientation, frame: oriented, overlap: overlap,
            achievedOverlap: achievedOverlap(layout: layout, frameHeight: oriented.vertical),
            rows: columnsPerRow.count, columnsPerRow: columnsPerRow, panels: panels, shootingOrder: order,
            pole: point(extent.basis.pole, kind: extent.kind),
            coverage: coverage(extent: extent, layout: layout, frame: oriented, coveredFraction: covered,
                               panelCount: panels.count, tanHalfWidth: tanHalfWidth, tanHalfHeight: tanHalfHeight),
            warnings: warnings)
    }

    /// Plans a mosaic for a lens and sensor, see the version with a frame size.
    ///
    /// - Parameter setup: The camera and lens; its `LensSetup.fieldOfView` is the landscape frame.
    public static func plan(region: MosaicRegion, setup: LensSetup, orientation: MosaicOrientation = .landscape,
                            overlap: Double = MosaicPlanner.defaultOverlap, observerLatitude: Double? = nil,
                            reverseOrder: Bool = false) throws -> MosaicPlan {
        try plan(region: region, frame: setup.fieldOfView, orientation: orientation, overlap: overlap,
                 observerLatitude: observerLatitude, reverseOrder: reverseOrder)
    }

    /// The orientation that covers `region` with fewer panels; landscape when both need the same number
    /// or when neither can be planned within `maximumPanelCount`.
    ///
    /// Plans the region twice.
    ///
    /// - Throws: `MosaicError` for a region, frame or overlap that is not usable.
    public static func recommendedOrientation(region: MosaicRegion, frame: FrameSize,
                                              overlap: Double = MosaicPlanner.defaultOverlap) throws -> MosaicOrientation {
        let landscape = try panelCount(region: region, frame: frame, orientation: .landscape, overlap: overlap)
        let portrait = try panelCount(region: region, frame: frame, orientation: .portrait, overlap: overlap)
        return portrait < landscape ? .portrait : .landscape
    }

    // MARK: Validation

    private static func validated(_ region: MosaicRegion) throws -> MosaicExtent {
        switch region {
        case let .equatorial(center, width, height, positionAngle):
            guard center.rightAscension.isFinite, center.declination.isFinite, width.isFinite, height.isFinite,
                  positionAngle.isFinite else { throw MosaicError.nonFiniteInput }
            guard width > 0, width <= 360 else { throw MosaicError.invalidWidth(value: width) }
            guard height > 0, height <= 180 else { throw MosaicError.invalidHeight(value: height) }
            return MosaicGeometry.extent(center: center, width: width, height: height, positionAngle: positionAngle)

        case let .horizontal(azimuthStart, azimuthSpan, minimumAltitude, maximumAltitude):
            guard azimuthStart.isFinite, azimuthSpan.isFinite, minimumAltitude.isFinite,
                  maximumAltitude.isFinite else { throw MosaicError.nonFiniteInput }
            guard azimuthSpan > 0, azimuthSpan <= 360 else { throw MosaicError.invalidAzimuthSpan(value: azimuthSpan) }
            guard minimumAltitude >= -90, maximumAltitude <= 90, minimumAltitude < maximumAltitude else {
                throw MosaicError.invalidAltitudeRange(minimum: minimumAltitude, maximum: maximumAltitude)
            }
            return MosaicGeometry.extent(azimuthStart: azimuthStart, azimuthSpan: azimuthSpan,
                                         minimumAltitude: minimumAltitude, maximumAltitude: maximumAltitude)
        }
    }

    private static func panelCount(region: MosaicRegion, frame: FrameSize, orientation: MosaicOrientation,
                                   overlap: Double) throws -> Int {
        do {
            return try plan(region: region, frame: frame, orientation: orientation, overlap: overlap).panelCount
        } catch MosaicError.tooManyPanels {
            return Int.max
        }
    }

    // MARK: Assembly

    private static func point(_ vector: Vector3, kind: MosaicFrameKind) -> MosaicPoint {
        MosaicGeometry.point(vector, kind: kind)
    }

    private static func achievedOverlap(layout: MosaicLayout, frameHeight: Double) -> Double? {
        var result: Double?
        for row in layout.rowLatitudes.indices where layout.columnLongitudes[row].count > 1 {
            let overlap = 1 - layout.columnSpacings[row] / layout.rowWidths[row]
            result = result.map { min($0, overlap) } ?? overlap
        }
        if layout.rowLatitudes.count > 1 {
            let overlap = 1 - layout.rowStep / frameHeight
            result = result.map { min($0, overlap) } ?? overlap
        }
        return result
    }

    private static func coverage(extent: MosaicExtent, layout: MosaicLayout, frame: FrameSize, coveredFraction: Double,
                                 panelCount: Int, tanHalfWidth: Double, tanHalfHeight: Double) -> MosaicCoverage {
        let rows = layout.rowLatitudes.count
        let middle = (extent.minimumLatitude + extent.maximumLatitude) / 2
        var central = 0
        for row in 1..<max(rows, 1) where abs(layout.rowLatitudes[row] - middle) < abs(layout.rowLatitudes[central] - middle) {
            central = row
        }
        let columns = layout.columnLongitudes[central]
        let span: Double
        if extent.isRing {
            span = 360
        } else {
            span = min(360, ((columns.first ?? 0) - (columns.last ?? 0)) + layout.rowWidths[central])
        }
        return MosaicCoverage(
            widthDegrees: span * AstroMath.cosDeg(layout.rowLatitudes[central]),
            heightDegrees: ((layout.rowLatitudes.first ?? 0) - (layout.rowLatitudes.last ?? 0)) + frame.vertical,
            longitudeSpanDegrees: span,
            regionAreaSquareDegrees: extent.areaSquareDegrees,
            panelAreaSquareDegrees: Double(panelCount)
                * MosaicGeometry.frameAreaSquareDegrees(tanHalfWidth: tanHalfWidth, tanHalfHeight: tanHalfHeight),
            coveredFraction: coveredFraction)
    }

    // MARK: Shooting order

    /// The panel indices in shooting order: a serpentine through the rows. Horizontal plans start at the left
    /// end of the bottom row. Equatorial plans start at the corner panel that sets first and move on to the
    /// neighbouring row at the end of each row.
    private static func shootingOrder(region: MosaicRegion, columnsPerRow: [Int], axes: [MosaicAxes],
                                      observerLatitude: Double?, reverseOrder: Bool) -> [Int] {
        let rows = columnsPerRow.count
        var offsets = [Int](repeating: 0, count: rows)
        for row in 1..<max(rows, 1) { offsets[row] = offsets[row - 1] + columnsPerRow[row - 1] }
        var startAtTop = false
        var startAtLeft = true
        if case let .equatorial(center, _, _, _) = region {
            let candidates: [(top: Bool, left: Bool, index: Int)] = [
                (true, true, offsets[0]),
                (true, false, offsets[0] + columnsPerRow[0] - 1),
                (false, true, offsets[rows - 1]),
                (false, false, offsets[rows - 1] + columnsPerRow[rows - 1] - 1),
            ]
            var best = Double.infinity
            for candidate in candidates {
                let key = settingKey(center: axes[candidate.index].center, centerRightAscension: center.rightAscension,
                                     observerLatitude: observerLatitude)
                if key < best {
                    best = key
                    startAtTop = candidate.top
                    startAtLeft = candidate.left
                }
            }
        }
        var result = [Int]()
        result.reserveCapacity(axes.count)
        for step in 0..<rows {
            let row = startAtTop ? step : rows - 1 - step
            let leftToRight = startAtLeft == (step % 2 == 0)
            let count = columnsPerRow[row]
            for k in 0..<count {
                result.append(offsets[row] + (leftToRight ? k : count - 1 - k))
            }
        }
        return reverseOrder ? Array(result.reversed()) : result
    }

    /// A number that is smaller for a panel that sets earlier: its right ascension relative to the region's
    /// centre, plus the hour angle at which a star of its declination sets for the observer. Without a latitude
    /// the stars are assumed to set at an hour angle of 90°, as on the equator.
    private static func settingKey(center: Vector3, centerRightAscension: Double, observerLatitude: Double?) -> Double {
        let rightAscension = AstroMath.atan2Deg(center.y, center.x)
        let declination = AstroMath.asinDeg(center.z)
        return AstroMath.normalizeSignedDegrees(rightAscension - centerRightAscension)
            + settingHourAngle(declination: declination, observerLatitude: observerLatitude)
    }

    /// The hour angle, [0, 180], at which a star of `declination` sets: 180 if it never does, 0 if it never rises.
    static func settingHourAngle(declination: Double, observerLatitude: Double?) -> Double {
        guard let latitude = observerLatitude else { return 90 }
        let numerator = AstroMath.sinDeg(latitude) * AstroMath.sinDeg(declination)
        let denominator = AstroMath.cosDeg(latitude) * AstroMath.cosDeg(declination)
        if !(denominator > 1e-12) {
            return numerator > 0 ? 180 : (numerator < 0 ? 0 : 90)
        }
        return AstroMath.acosDeg(AstroMath.clamp(-numerator / denominator, -1, 1))
    }
}
