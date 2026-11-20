/// One panel of a mosaic as it is written to a file.
public struct MosaicPanelRecord: Hashable, Sendable {
    /// The panel's name, "R2C3" for the third panel of the second row.
    public let panel: String
    /// The row from 1, counted from the pole side of the mosaic.
    public let row: Int
    /// The column from 1 within its row, counted from the left of the stitched image.
    public let column: Int
    /// The J2000 right ascension of the panel's centre in degrees, [0, 360).
    public let rightAscension: Double
    /// The J2000 declination of the panel's centre in degrees.
    public let declination: Double
    /// The sky position angle of the frame's top edge in degrees, [0, 360), from north through east (the angle a framing
    /// tool calls rotation).
    public let positionAngle: Double
    /// The place of the panel in the shooting order, from 1.
    public let order: Int

    public init(
        panel: String,
        row: Int,
        column: Int,
        rightAscension: Double,
        declination: Double,
        positionAngle: Double,
        order: Int
    ) {
        self.panel = panel
        self.row = row
        self.column = column
        self.rightAscension = rightAscension
        self.declination = declination
        self.positionAngle = positionAngle
        self.order = order
    }
}

/// Writes the panels of an equatorial mosaic plan as CSV and as a plain text list for planetarium and ASIAIR import.
public enum MosaicPanelCodec {
    /// The records of a plan's panels in row-major order.
    ///
    /// The position angle is that of the direction from the panel's centre to the middle of its top edge (the edge that
    /// points to the plan's pole), measured from the direction of the north celestial pole through east at the centre.
    /// At a celestial pole it is 0.
    ///
    /// - Throws: `InterchangeError.horizontalPlan` for a plan in azimuth and altitude.
    public static func records(of plan: MosaicPlan) throws -> [MosaicPanelRecord] {
        guard plan.kind == .equatorial else { throw InterchangeError.horizontalPlan }
        var result: [MosaicPanelRecord] = []
        result.reserveCapacity(plan.panels.count)
        for panel in plan.panels {
            guard let center = panel.center.equatorialCoordinate else { throw InterchangeError.horizontalPlan }
            result.append(MosaicPanelRecord(
                panel: panel.id,
                row: panel.row + 1,
                column: panel.column + 1,
                rightAscension: center.rightAscension,
                declination: center.declination,
                positionAngle: positionAngle(of: panel, center: center),
                order: panel.shootingPosition + 1
            ))
        }
        return result
    }

    private static func positionAngle(of panel: MosaicPanel, center: EquatorialCoordinate) -> Double {
        guard panel.corners.count >= 2 else { return 0 }
        let c = center.unitVector
        let pole = Vector3(0, 0, 1)
        let eastDirection = pole.cross(c)
        guard eastDirection.length > 1e-12 else { return 0 }
        let east = eastDirection.normalized
        let north = c.cross(east)
        let topMiddle = (panel.corners[0].unitVector + panel.corners[1].unitVector).normalized
        let toTop = topMiddle - c * topMiddle.dot(c)
        guard toTop.length > 1e-12 else { return 0 }
        return AstroMath.normalizeDegrees(AstroMath.atan2Deg(toTop.dot(east), toTop.dot(north)))
    }

    /// The panels as CSV (RFC 4180, CRLF): `Panel,Row,Column,RA J2000 (deg),Dec J2000 (deg),Position angle (deg),Order`,
    /// coordinates and angle in decimal degrees with five places.
    public static func csv(_ records: [MosaicPanelRecord]) -> String {
        var rows: [[String]] = [["Panel", "Row", "Column", "RA J2000 (deg)", "Dec J2000 (deg)", "Position angle (deg)", "Order"]]
        for record in records {
            rows.append([
                record.panel,
                String(record.row),
                String(record.column),
                InterchangeText.fixedAngle(record.rightAscension, decimals: 5),
                InterchangeText.fixed(record.declination, decimals: 5),
                InterchangeText.fixedAngle(record.positionAngle, decimals: 5),
                String(record.order),
            ])
        }
        return InterchangeCSV.encode(rows)
    }

    /// The panels as a text list in shooting order, one line per panel: `Name, RA hh mm ss.s, Dec ±dd mm ss`, for example
    /// `M 31 R1C2, 00 42 44.3, +41 16 09`; the name is the target name and the panel's name. Lines end with LF.
    public static func text(_ records: [MosaicPanelRecord], targetName: String) -> String {
        let cleaned = InterchangeText.singleLine(targetName, limit: SessionLogEntry.maximumNameLength)
        let name = cleaned.isEmpty ? "Mosaic" : cleaned
        var lines: [String] = []
        for record in records.sorted(by: { $0.order < $1.order }) {
            lines.append("\(name) \(record.panel), \(rightAscensionText(record.rightAscension)), \(declinationText(record.declination))")
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    /// "hh mm ss.s" for a right ascension in degrees.
    static func rightAscensionText(_ degrees: Double) -> String {
        let hours = AstroMath.normalizeDegrees(degrees) / 15
        guard let parts = NumberText.sexagesimal(magnitude: hours, secondsDecimals: 1) else { return "00 00 00.0" }
        return "\(NumberText.padded(parts.whole % 24, width: 2)) \(NumberText.padded(parts.minutes, width: 2)) \(parts.secondsText)"
    }

    /// "±dd mm ss" for a declination in degrees.
    static func declinationText(_ degrees: Double) -> String {
        let clamped = AstroMath.clamp(degrees.isFinite ? degrees : 0, -90, 90)
        guard let parts = NumberText.sexagesimal(magnitude: abs(clamped), secondsDecimals: 0) else { return "+00 00 00" }
        let sign = clamped < 0 && !parts.isZero ? "-" : "+"
        return "\(sign)\(NumberText.padded(parts.whole, width: 2)) \(NumberText.padded(parts.minutes, width: 2)) \(parts.secondsText)"
    }
}
