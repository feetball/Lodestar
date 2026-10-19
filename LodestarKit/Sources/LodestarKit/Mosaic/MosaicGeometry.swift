import Foundation

/// A latitude and longitude grid on the celestial sphere or the sky dome: a pole, the direction of longitude 0
/// on the grid's equator (`x`) and the direction of longitude 90 (`y = pole × x`). Longitude grows
/// counter-clockwise seen from outside the sphere above the pole, so it grows towards the left of a
/// camera frame whose top edge points to the pole.
struct MosaicBasis: Sendable {
    let pole: Vector3
    let x: Vector3
    let y: Vector3

    /// The unit vector at `longitude` and `latitude`, both in degrees.
    func vector(longitude: Double, latitude: Double) -> Vector3 {
        let cosLatitude = AstroMath.cosDeg(latitude)
        return x * (cosLatitude * AstroMath.cosDeg(longitude))
            + y * (cosLatitude * AstroMath.sinDeg(longitude))
            + pole * AstroMath.sinDeg(latitude)
    }
}

/// The region to cover in grid terms: the longitude span about longitude 0 and the latitude range.
struct MosaicExtent: Sendable {
    let kind: MosaicFrameKind
    let basis: MosaicBasis
    /// The extent in longitude, degrees in (0, 360]; 360 is a full circle.
    let longitudeSpan: Double
    let minimumLatitude: Double
    let maximumLatitude: Double

    /// Whether the region wraps all the way round the pole.
    var isRing: Bool { longitudeSpan >= 360 - MosaicGeometry.tolerance }

    /// The area of the region in square degrees.
    var areaSquareDegrees: Double {
        AstroMath.radians(longitudeSpan)
            * (AstroMath.sinDeg(maximumLatitude) - AstroMath.sinDeg(minimumLatitude))
            * AstroMath.degreesPerRadian * AstroMath.degreesPerRadian
    }
}

/// The rows and columns of a layout, in grid coordinates. Rows run from the top (highest latitude).
struct MosaicLayout: Sendable {
    let rowLatitudes: [Double]
    let columnLongitudes: [[Double]]
    let columnSpacings: [Double]
    let rowWidths: [Double]
    let rowStep: Double

    var panelCount: Int { columnLongitudes.reduce(0) { $0 + $1.count } }
}

/// A frame placed on the sphere: its centre and the unit vectors along its right and up edges.
struct MosaicAxes: Sendable {
    let center: Vector3
    let right: Vector3
    let up: Vector3
}

/// The geometry behind `MosaicPlanner`: grids, row and column layouts, and the coverage check.
enum MosaicGeometry {
    /// Slack for comparisons that should hold exactly.
    static let tolerance = 1e-9

    /// Points per band, along the latitude, at which the narrowest frame width is measured.
    static let bandSamples = 5

    /// The size of the lattice that checks the coverage of the region.
    static let latitudeSamples = 41
    static let longitudeSamples = 61

    /// How much overlap and padding each further attempt adds, as a fraction of the frame.
    static let attemptStep = 0.02

    /// The number of attempts: 0 to 0.4 of extra overlap and padding.
    static let maximumAttempts = 21

    /// The largest overlap an attempt may use.
    static let maximumOverlap = 0.9

    // MARK: Region

    /// The grid and extent of an equatorial region that has been validated.
    static func extent(center: EquatorialCoordinate, width: Double, height: Double, positionAngle: Double) -> MosaicExtent {
        let c = center.unitVector
        let sinDeclination = AstroMath.sinDeg(center.declination)
        let cosDeclination = max(0, AstroMath.cosDeg(center.declination))
        let east = cosDeclination > 1e-12
            ? Vector3(-c.y, c.x, 0) / hypot(c.x, c.y)
            : Vector3(0, 1, 0)
        let north = c.cross(east)
        let direction = north * AstroMath.cosDeg(positionAngle) + east * AstroMath.sinDeg(positionAngle)
        let pole = (c * sinDeclination + direction * cosDeclination).normalized
        let projected = c - pole * c.dot(pole)
        let x = projected.length > 1e-9 ? projected.normalized : (north - pole * north.dot(pole)).normalized
        let basis = MosaicBasis(pole: pole, x: x, y: pole.cross(x))
        let span = cosDeclination > 1e-9 ? min(360, width / cosDeclination) : 360
        return MosaicExtent(kind: .equatorial, basis: basis, longitudeSpan: span,
                            minimumLatitude: max(-90, center.declination - height / 2),
                            maximumLatitude: min(90, center.declination + height / 2))
    }

    /// The grid and extent of a horizontal region that has been validated.
    static func extent(azimuthStart: Double, azimuthSpan: Double, minimumAltitude: Double,
                       maximumAltitude: Double) -> MosaicExtent {
        let centerAzimuth = AstroMath.normalizeDegrees(azimuthStart + azimuthSpan / 2)
        let x = Vector3(AstroMath.sinDeg(centerAzimuth), AstroMath.cosDeg(centerAzimuth), 0)
        let zenith = Vector3(0, 0, 1)
        return MosaicExtent(kind: .horizontal, basis: MosaicBasis(pole: zenith, x: x, y: zenith.cross(x)),
                            longitudeSpan: azimuthSpan, minimumLatitude: minimumAltitude,
                            maximumLatitude: maximumAltitude)
    }

    // MARK: Frames

    /// Half the longitude, in degrees, that a frame centred at latitude `centerLatitude` covers on the parallel
    /// at `latitude`: the frame has half-sizes `tanHalfWidth` and `tanHalfHeight` in the tangent plane, its
    /// top edge points to the pole and its centre is at longitude 0. 180 means the whole parallel is inside; 0
    /// means the parallel does not meet the frame at longitude 0.
    static func longitudeHalfExtent(centerLatitude: Double, latitude: Double, tanHalfWidth: Double,
                                    tanHalfHeight: Double) -> Double {
        let sinCenter = AstroMath.sinDeg(centerLatitude)
        let cosCenter = AstroMath.cosDeg(centerLatitude)
        let sinLatitude = AstroMath.sinDeg(latitude)
        let cosLatitude = AstroMath.cosDeg(latitude)
        func inside(_ longitude: Double) -> Bool {
            let cosLongitude = AstroMath.cosDeg(longitude)
            let cosDistance = sinCenter * sinLatitude + cosCenter * cosLatitude * cosLongitude
            guard cosDistance > 1e-12 else { return false }
            let x = cosLatitude * AstroMath.sinDeg(longitude) / cosDistance
            let y = (cosCenter * sinLatitude - sinCenter * cosLatitude * cosLongitude) / cosDistance
            return abs(x) <= tanHalfWidth * (1 + tolerance) && abs(y) <= tanHalfHeight * (1 + tolerance)
        }
        guard inside(0) else { return 0 }
        var low = 0.0
        var high = 1.0
        while high <= 180 {
            if !inside(high) {
                for _ in 0..<40 {
                    let middle = (low + high) / 2
                    if inside(middle) { low = middle } else { high = middle }
                }
                return low
            }
            low = high
            high += 1
        }
        return 180
    }

    /// `vector` as a point of the plan's coordinate system: equatorial or horizontal coordinates.
    static func point(_ vector: Vector3, kind: MosaicFrameKind) -> MosaicPoint {
        switch kind {
        case .equatorial: .equatorial(EquatorialCoordinate(vector: vector))
        case .horizontal: .horizontal(HorizontalCoordinate(vector: vector))
        }
    }

    /// The axes of the frame at `longitude` and `latitude` with its top edge pointing to the pole.
    static func axes(basis: MosaicBasis, longitude: Double, latitude: Double) -> MosaicAxes {
        let center = basis.vector(longitude: longitude, latitude: latitude)
        let towardsPole = basis.pole - center * basis.pole.dot(center)
        let up = towardsPole.length > 1e-12 ? towardsPole.normalized : basis.x
        return MosaicAxes(center: center, right: center.cross(up), up: up)
    }

    /// The corner of a frame: `horizontalSign` +1 is towards its right edge, `verticalSign` +1 towards its top edge.
    static func corner(axes: MosaicAxes, horizontalSign: Double, verticalSign: Double, tanHalfWidth: Double,
                       tanHalfHeight: Double) -> Vector3 {
        (axes.center + axes.right * (horizontalSign * tanHalfWidth) + axes.up * (verticalSign * tanHalfHeight)).normalized
    }

    /// The solid angle in square degrees of a frame with the given tangent-plane half-sizes.
    static func frameAreaSquareDegrees(tanHalfWidth: Double, tanHalfHeight: Double) -> Double {
        4 * atan(tanHalfWidth * tanHalfHeight / (1 + tanHalfWidth * tanHalfWidth + tanHalfHeight * tanHalfHeight).squareRoot())
            * AstroMath.degreesPerRadian * AstroMath.degreesPerRadian
    }

    // MARK: Layout

    /// Lays out rows and columns for `extent`.
    ///
    /// Rows are circles of latitude, spaced so that neighbouring frames overlap by `overlap` of `frameHeight`
    /// on the central meridian, centred on the region, with as many rows as it takes for the top edge of the
    /// first row and the bottom edge of the last to reach the region's edges plus `padding` of the frame.
    /// Each row gets as many columns as it takes for neighbouring frames, which overlap by `overlap` of the
    /// narrowest longitude width the frame has within the row's band of latitudes, to reach the region's
    /// side edges plus `padding`; the columns are centred on the region.
    ///
    /// - Throws: `MosaicError.tooManyPanels` if the layout has more than `MosaicPlanner.maximumPanelCount` panels.
    static func layout(extent: MosaicExtent, tanHalfWidth: Double, tanHalfHeight: Double, frameHeight: Double,
                       overlap: Double, padding: Double) throws -> MosaicLayout {
        let limit = MosaicPlanner.maximumPanelCount
        let low = extent.minimumLatitude
        let high = extent.maximumLatitude
        let paddedHeight = (high - low) + 2 * padding * frameHeight

        // Rows.
        let rowCount: Int
        let centers: [Double]
        var step = 0.0
        if paddedHeight <= frameHeight + tolerance {
            rowCount = 1
            centers = [(low + high) / 2]
        } else {
            step = frameHeight * (1 - overlap)
            let intervals = ceil((paddedHeight - frameHeight) / step - tolerance)
            if intervals + 1 > Double(limit) {
                throw MosaicError.tooManyPanels(count: clampedCount(intervals + 1), limit: limit)
            }
            rowCount = Int(intervals) + 1
            let middle = (low + high) / 2
            centers = (0..<rowCount).map { middle + (Double(rowCount - 1) / 2 - Double($0)) * step }
        }
        let bandHalfHeight = rowCount == 1 ? min(paddedHeight / 2, 0.49 * frameHeight) : step / 2

        // Columns.
        var longitudes = [[Double]]()
        longitudes.reserveCapacity(rowCount)
        var spacings = [Double](repeating: 0, count: rowCount)
        var widths = [Double](repeating: 0, count: rowCount)
        var total = 0.0
        for row in 0..<rowCount {
            var narrowest = 180.0
            for sample in 0..<bandSamples {
                let latitude = centers[row] - bandHalfHeight + 2 * bandHalfHeight * Double(sample) / Double(bandSamples - 1)
                narrowest = min(narrowest, longitudeHalfExtent(centerLatitude: centers[row], latitude: latitude,
                                                               tanHalfWidth: tanHalfWidth, tanHalfHeight: tanHalfHeight))
            }
            let width = max(2 * narrowest, 1e-6)
            let span = extent.longitudeSpan + 2 * padding * width
            let maximumStep = (1 - overlap) * width
            let columns: [Double]
            if extent.isRing || span >= 360 - tolerance {
                let count = width >= 360 - tolerance ? 1.0 : max(1.0, ceil(360 / maximumStep - tolerance))
                total += count
                if total > Double(limit) { throw MosaicError.tooManyPanels(count: clampedCount(total), limit: limit) }
                let spacing = 360 / count
                columns = (0..<Int(count)).map { ((count - 1) / 2 - Double($0)) * spacing }
                spacings[row] = count > 1 ? spacing : 0
            } else if width >= span {
                total += 1
                columns = [0]
                spacings[row] = 0
            } else {
                let count = ceil((span - width) / maximumStep - tolerance) + 1
                total += count
                if total > Double(limit) { throw MosaicError.tooManyPanels(count: clampedCount(total), limit: limit) }
                columns = (0..<Int(count)).map { ((count - 1) / 2 - Double($0)) * maximumStep }
                spacings[row] = maximumStep
            }
            widths[row] = width
            longitudes.append(columns)
        }
        if total > Double(limit) { throw MosaicError.tooManyPanels(count: clampedCount(total), limit: limit) }
        return MosaicLayout(rowLatitudes: centers, columnLongitudes: longitudes, columnSpacings: spacings,
                            rowWidths: widths, rowStep: step)
    }

    private static func clampedCount(_ count: Double) -> Int {
        count >= 1e9 ? 1_000_000_000 : Int(count)
    }

    /// The axes of every frame of `layout`, row by row.
    static func axes(layout: MosaicLayout, basis: MosaicBasis) -> [MosaicAxes] {
        var result = [MosaicAxes]()
        result.reserveCapacity(layout.panelCount)
        for row in layout.rowLatitudes.indices {
            for longitude in layout.columnLongitudes[row] {
                result.append(axes(basis: basis, longitude: longitude, latitude: layout.rowLatitudes[row]))
            }
        }
        return result
    }

    // MARK: Coverage

    /// The lattice of points of the region, as `x, y, z` triples, that the coverage check uses.
    static func samples(extent: MosaicExtent) -> [Double] {
        var result = [Double](repeating: 0, count: latitudeSamples * longitudeSamples * 3)
        var offset = 0
        for row in 0..<latitudeSamples {
            let latitude = extent.minimumLatitude
                + (extent.maximumLatitude - extent.minimumLatitude) * Double(row) / Double(latitudeSamples - 1)
            for column in 0..<longitudeSamples {
                let longitude: Double
                if extent.isRing {
                    longitude = -180 + 360 * (Double(column) + 0.5) / Double(longitudeSamples)
                } else {
                    longitude = -extent.longitudeSpan / 2 + extent.longitudeSpan * Double(column) / Double(longitudeSamples - 1)
                }
                let vector = extent.basis.vector(longitude: longitude, latitude: latitude)
                result[offset] = vector.x
                result[offset + 1] = vector.y
                result[offset + 2] = vector.z
                offset += 3
            }
        }
        return result
    }

    /// The fraction of `samples` that lie inside at least one of `frames`. With `stopAtGap` the count ends at
    /// the first point that is outside every frame and the result is below 1.
    static func coveredFraction(samples: [Double], frames: [MosaicAxes], tanHalfWidth: Double,
                                tanHalfHeight: Double, stopAtGap: Bool) -> Double {
        let total = samples.count / 3
        let reach = 1 / (1 + tanHalfWidth * tanHalfWidth + tanHalfHeight * tanHalfHeight).squareRoot() * (1 - tolerance)
        var covered = 0
        for index in 0..<total {
            let x = samples[index * 3]
            let y = samples[index * 3 + 1]
            let z = samples[index * 3 + 2]
            var inside = false
            for frame in frames {
                let depth = x * frame.center.x + y * frame.center.y + z * frame.center.z
                if depth < reach { continue }
                let right = x * frame.right.x + y * frame.right.y + z * frame.right.z
                let up = x * frame.up.x + y * frame.up.y + z * frame.up.z
                if abs(right) <= tanHalfWidth * depth * (1 + tolerance) && abs(up) <= tanHalfHeight * depth * (1 + tolerance) {
                    inside = true
                    break
                }
            }
            if inside {
                covered += 1
            } else if stopAtGap {
                return Double(covered) / Double(total)
            }
        }
        return Double(covered) / Double(total)
    }
}
