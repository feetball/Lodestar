import Foundation

/// The direction of a target at one instant of an altitude curve.
public struct AltitudeSample: Sendable, Hashable {
    /// The instant of the sample.
    public let date: Date
    /// Altitude above the horizon in degrees. The planner's own curves are geometric (no
    /// refraction); a custom position function decides what its own curve reports.
    public let altitude: Double
    /// Azimuth in degrees from north through east, [0, 360).
    public let azimuth: Double

    /// Creates a sample.
    public init(date: Date, altitude: Double, azimuth: Double) {
        self.date = date
        self.altitude = altitude
        self.azimuth = azimuth
    }
}
