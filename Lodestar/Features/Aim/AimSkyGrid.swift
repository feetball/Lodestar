import Foundation
import LodestarKit

/// The fixed lines of the horizon frame (altitude circles, azimuth lines, the horizon, the compass points) as ENU
/// directions, made once.
enum AimSkyGrid {
    struct AltitudeCircle: Sendable {
        let altitude: Double
        let points: [Vector3]
    }

    struct CompassLabel: Sendable {
        let text: String
        let direction: Vector3
        /// `true` for N, E, S and W.
        let isCardinal: Bool
    }

    /// Altitude circles every 10° from −80° to 80°, except the horizon.
    static let altitudeCircles: [AltitudeCircle] = stride(from: -80.0, through: 80.0, by: 10.0)
        .filter { $0 != 0 }
        .map { altitude in
            AltitudeCircle(altitude: altitude, points: stride(from: 0.0, to: 360.0, by: 2.0).map {
                HorizontalCoordinate(azimuth: $0, altitude: altitude).unitVector
            })
        }

    /// Azimuth lines every 10°, from the nadir over the horizon to the zenith.
    static let azimuthLines: [[Vector3]] = stride(from: 0.0, to: 360.0, by: 10.0).map { azimuth in
        stride(from: -90.0, through: 90.0, by: 5.0).map { HorizontalCoordinate(azimuth: azimuth, altitude: $0).unitVector }
    }

    static let horizon: [Vector3] = stride(from: 0.0, to: 360.0, by: 2.0).map {
        HorizontalCoordinate(azimuth: $0, altitude: 0).unitVector
    }

    /// Ticks every 5° along the horizon; every second one is a major tick (10°).
    static let horizonTicks: [(base: Vector3, isMajor: Bool)] = (0..<72).map { index in
        (HorizontalCoordinate(azimuth: Double(index) * 5, altitude: 0).unitVector, index % 2 == 0)
    }

    /// N, NE, E, SE, S, SW, W, NW on the horizon.
    static let compassLabels: [CompassLabel] = CompassPoint.allCases.filter { $0.rawValue % 2 == 0 }.map { point in
        CompassLabel(text: point.abbreviation,
                     direction: HorizontalCoordinate(azimuth: point.centerAzimuth, altitude: 0).unitVector,
                     isCardinal: point.rawValue % 4 == 0)
    }
}
