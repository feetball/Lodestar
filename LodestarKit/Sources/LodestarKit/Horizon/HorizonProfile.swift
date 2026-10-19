import Foundation

/// A stretch of azimuth, measured clockwise (from north through east) from `start`.
///
/// Construction normalizes `start` to [0, 360) and clamps `length` to [0, 360]; a value that is not finite
/// becomes 0. A range may run through north (`start` 350, `length` 20).
public struct AzimuthRange: Sendable, Hashable {
    /// The first azimuth of the range in degrees, [0, 360).
    public let start: Double
    /// The extent of the range in degrees, [0, 360]; 360 is the whole circle.
    public let length: Double

    /// Creates a range, normalizing `start` to [0, 360) and clamping `length` to [0, 360].
    public init(start: Double, length: Double) {
        self.start = start.isFinite ? AstroMath.normalizeDegrees(start) : 0
        self.length = length.isFinite ? AstroMath.clamp(length, 0, 360) : 0
    }

    /// The range that runs clockwise from `start` to `end`. Equal azimuths give an empty range, not the whole
    /// circle; use `full` for that.
    public init(from start: Double, to end: Double) {
        if start.isFinite, end.isFinite {
            self.init(start: start, length: AstroMath.normalizeDegrees(end - start))
        } else {
            self.init(start: 0, length: 0)
        }
    }

    /// The whole circle.
    public static let full = AzimuthRange(start: 0, length: 360)

    /// The last azimuth of the range in degrees, [0, 360).
    public var end: Double { AstroMath.normalizeDegrees(start + length) }

    /// Whether `azimuth` (any angle, in degrees) lies in the range, its ends included.
    public func contains(_ azimuth: Double) -> Bool {
        guard azimuth.isFinite else { return false }
        return AstroMath.normalizeDegrees(azimuth - start) <= length
    }
}

/// One point of the skyline drawn as a line: an azimuth and the altitude of the skyline there, both in
/// degrees. The azimuth is **not** wrapped, so a line that runs through north keeps increasing (350, 360, 370).
public struct SkylinePoint: Sendable, Hashable {
    /// Azimuth in degrees from north through east, as requested from `HorizonProfile.polyline(from:to:step:)`.
    public let azimuth: Double
    /// Altitude of the skyline in degrees.
    public let altitude: Double

    /// Creates a point.
    public init(azimuth: Double, altitude: Double) {
        self.azimuth = azimuth
        self.altitude = altitude
    }
}

/// The skyline of an observing site: the altitude at which the sky starts, for every azimuth.
///
/// Trees, ridges and buildings hide the sky near the horizon. The profile stores the altitude of that
/// skyline at every whole degree of azimuth (360 values, azimuth 0° = north, increasing through east) and
/// interpolates linearly in between, wrapping from 359° to 0°. Altitudes are **apparent** (where the
/// obstacle is seen from the observer), between −10° and +60°, and rounded to 0.1°, so a profile that is
/// stored and loaded again is equal to itself. The flat default (0° everywhere) is `flat`.
///
/// A profile is a small immutable value: the JSON form is about 1.2 KB for a typical skyline, 750 bytes for a flat
/// one and never more than 1.9 KB, so one can be stored with every observing site. Its keys are `version` (1)
/// and `altitudeTenths`, an array of 360 integers, the altitudes in tenths of a degree, e.g.
/// `{"version":1,"altitudeTenths":[0,0,25,31,…]}`. Decoding checks the version, the length, that every number is an
/// integer, and the −100…600 range.
public struct HorizonProfile: Sendable, Hashable, Codable {
    /// The number of stored altitudes: one per whole degree of azimuth.
    public static let binCount = 360
    /// The lowest altitude, in degrees, a skyline may have.
    public static let lowestAltitude = -10.0
    /// The highest altitude, in degrees, a skyline may have.
    public static let highestAltitude = 60.0
    /// The version number of the JSON form.
    public static let formatVersion = 1

    private static let lowestTenths = -100
    private static let highestTenths = 600

    /// The skyline altitude at azimuth 0°, 1°, … 359° in degrees; 360 multiples of 0.1.
    public let altitudes: [Double]

    /// The flat skyline: 0° at every azimuth.
    public static let flat = HorizonProfile(validated: [Double](repeating: 0, count: binCount))

    private init(validated altitudes: [Double]) {
        self.altitudes = altitudes
    }

    /// The profile with the given skyline `altitudes` (degrees at azimuth 0°, 1°, … 359°), rounded to 0.1°;
    /// `nil` unless there are exactly 360 finite values between −10° and +60°.
    public init?(altitudes: [Double]) {
        guard altitudes.count == Self.binCount else { return nil }
        var tenths = [Int]()
        tenths.reserveCapacity(Self.binCount)
        for value in altitudes {
            guard value.isFinite else { return nil }
            let scaled = (value * 10).rounded()
            guard scaled >= Double(Self.lowestTenths), scaled <= Double(Self.highestTenths) else { return nil }
            tenths.append(Int(scaled))
        }
        guard let profile = Self.fromTenths(tenths) else { return nil }
        self = profile
    }

    /// A skyline at the same `altitude` all round (limited to −10…+60°; not finite gives 0°).
    public static func constant(_ altitude: Double) -> HorizonProfile {
        fromClamped([Double](repeating: altitude.isFinite ? altitude : 0, count: binCount))
    }

    /// The profile with altitudes of `tenths / 10` degrees; `tenths` must have 360 values in range.
    static func fromTenths(_ tenths: [Int]) -> HorizonProfile? {
        guard tenths.count == binCount else { return nil }
        guard !tenths.contains(where: { $0 < lowestTenths || $0 > highestTenths }) else { return nil }
        return HorizonProfile(validated: tenths.map { Double($0) / 10.0 })
    }

    /// Rounds `values` (360 numbers) to 0.1° and limits them to the allowed range.
    static func fromClamped(_ values: [Double]) -> HorizonProfile {
        let tenths = values.map { value -> Int in
            let scaled = value.isFinite ? (value * 10).rounded() : 0
            return Int(AstroMath.clamp(scaled, Double(lowestTenths), Double(highestTenths)))
        }
        return HorizonProfile(validated: tenths.map { Double($0) / 10.0 })
    }

    /// The altitudes in tenths of a degree (the JSON numbers).
    var tenths: [Int] { altitudes.map { Int(($0 * 10).rounded()) } }

    /// `true` when the skyline is at 0° all round, i.e. the profile changes nothing.
    public var isFlat: Bool { altitudes.allSatisfy { $0 == 0 } }

    /// The highest skyline altitude in degrees.
    public var maximumAltitude: Double { altitudes.max() ?? 0 }

    /// The lowest skyline altitude in degrees.
    public var minimumAltitude: Double { altitudes.min() ?? 0 }

    /// The skyline altitude in degrees at `azimuth` (any angle in degrees, wrapped into [0, 360)): the linear
    /// interpolation between the two nearest whole degrees, which wraps from 359° to 0°. A non-finite azimuth
    /// gives 0.
    public func altitude(at azimuth: Double) -> Double {
        guard azimuth.isFinite else { return 0 }
        let wrapped = AstroMath.normalizeDegrees(azimuth)
        let lower = Int(wrapped.rounded(.down))
        let fraction = wrapped - Double(lower)
        let first = altitudes[lower]
        if fraction == 0 { return first }
        let second = altitudes[lower + 1 == Self.binCount ? 0 : lower + 1]
        return first + (second - first) * fraction
    }

    /// The skyline as a line for drawing, from azimuth `from` to azimuth `to` (degrees; the azimuths of the
    /// points are not wrapped, so `from: 340, to: 380` runs through north in increasing order).
    ///
    /// The line has a point at `from`, at `to` and at every multiple of `step` in between. Because the skyline
    /// is linear between whole degrees, the default `step` of 1° reproduces it exactly; a larger step gives a
    /// coarser line. `step` is limited to 0.1…45; a span longer than 360° is cut to 360°; the whole circle
    /// (`from: 0, to: 360`) has 361 points, the last one the same as the first. Returns an empty array when
    /// `from` or `to` is not finite or beyond ±10⁹°, or `to` is smaller than `from`.
    public func polyline(from: Double = 0, to: Double = 360, step: Double = 1) -> [SkylinePoint] {
        guard from.isFinite, to.isFinite, abs(from) <= 1e9, abs(to) <= 1e9, to >= from else { return [] }
        let end = min(to, from + 360)
        let spacing = step.isFinite ? AstroMath.clamp(step, 0.1, 45) : 1
        var points = [SkylinePoint(azimuth: from, altitude: altitude(at: from))]
        var index = Int((from / spacing).rounded(.down)) + 1
        while Double(index) * spacing < end {
            let azimuth = Double(index) * spacing
            points.append(SkylinePoint(azimuth: azimuth, altitude: altitude(at: azimuth)))
            index += 1
        }
        if end > from { points.append(SkylinePoint(azimuth: end, altitude: altitude(at: end))) }
        return points
    }

    // MARK: Editing

    /// The profile with `delta` degrees added to the skyline in `range` (negative lowers it). The result is
    /// limited to `lowestAltitude`…`highestAltitude`. A `delta` that is not finite changes nothing.
    public func raised(by delta: Double, in range: AzimuthRange) -> HorizonProfile {
        guard delta.isFinite else { return self }
        var values = altitudes
        for index in values.indices where range.contains(Double(index)) { values[index] += delta }
        return Self.fromClamped(values)
    }

    /// The profile with the skyline in `range` set to `altitude` degrees (limited to
    /// `lowestAltitude`…`highestAltitude`). A non-finite `altitude` changes nothing.
    public func setting(to altitude: Double, in range: AzimuthRange) -> HorizonProfile {
        guard altitude.isFinite else { return self }
        var values = altitudes
        for index in values.indices where range.contains(Double(index)) { values[index] = altitude }
        return Self.fromClamped(values)
    }

    /// The profile with the skyline in `range` taken from `other` and the rest kept.
    public func replacing(_ range: AzimuthRange, with other: HorizonProfile) -> HorizonProfile {
        var values = altitudes
        for index in values.indices where range.contains(Double(index)) { values[index] = other.altitudes[index] }
        return Self.fromClamped(values)
    }

    /// The profile that is at every azimuth the higher of this skyline and `other`: both sets of obstacles.
    public func maximum(with other: HorizonProfile) -> HorizonProfile {
        Self.fromClamped((0..<Self.binCount).map { max(altitudes[$0], other.altitudes[$0]) })
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case version, altitudeTenths
    }

    /// Decodes and validates a profile; throws for another version, a length other than 360, a number that
    /// is not an integer, or a value outside −100…600.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Double.self, forKey: .version)
        guard version == Double(Self.formatVersion) else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Unsupported horizon profile version.")
        }
        var numbers = try container.nestedUnkeyedContainer(forKey: .altitudeTenths)
        var tenths = [Int]()
        tenths.reserveCapacity(Self.binCount)
        while !numbers.isAtEnd {
            guard tenths.count < Self.binCount else {
                throw DecodingError.dataCorruptedError(forKey: .altitudeTenths, in: container,
                                                       debugDescription: "A horizon profile needs \(Self.binCount) altitudes.")
            }
            let value = try numbers.decode(Double.self)
            guard value == value.rounded(.down), value >= Double(Self.lowestTenths),
                  value <= Double(Self.highestTenths) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .altitudeTenths, in: container,
                    debugDescription: "Altitude \(tenths.count) is not a whole number of tenths from -100 to 600.")
            }
            tenths.append(Int(value))
        }
        guard let profile = Self.fromTenths(tenths) else {
            throw DecodingError.dataCorruptedError(forKey: .altitudeTenths, in: container,
                                                   debugDescription: "A horizon profile needs \(Self.binCount) altitudes.")
        }
        self = profile
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .version)
        try container.encode(tenths, forKey: .altitudeTenths)
    }
}

extension HorizonProfile: CustomStringConvertible {
    public var description: String {
        "HorizonProfile(flat=\(isFlat), minimum=\(minimumAltitude), maximum=\(maximumAltitude))"
    }
}
