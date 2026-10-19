import Foundation
@testable import LodestarKit

/// Deterministic orbit generator for the selection tests. The generator is a 64-bit linear congruential sequence
/// (Knuth's MMIX constants) so that the Kotlin and Swift tests see the same bodies.
final class SyntheticOrbits {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// The next number in [0, 1).
    func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / 9_007_199_254_740_992.0
    }

    /// The next number in [low, high).
    func next(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * next()
    }

    /// `count` comets and asteroids with perihelion times (or epochs) within three years of 2026 October.
    func bodies(_ count: Int) -> [SmallBody] {
        var result = [SmallBody]()
        var index = 0
        while result.count < count {
            index += 1
            let isAsteroid = next() < 0.3
            let inclination = next(0.0, 180.0)
            let argument = next(0.0, 360.0)
            let node = next(0.0, 360.0)
            if isAsteroid {
                let axis = next(1.0, 4.5)
                let eccentricity = next(0.0, 0.6)
                let anomaly = next(0.0, 360.0)
                let orbit = SmallBodyElements.fromMeanAnomaly(
                    semiMajorAxisAU: axis, eccentricity: eccentricity, inclination: inclination.truncatingRemainder(dividingBy: 40),
                    argumentOfPerihelion: argument, longitudeOfAscendingNode: node, meanAnomaly: anomaly, epochJulianDayTT: 2_461_200.5)
                let magnitudes = AsteroidMagnitudes(absoluteMagnitude: next(3.0, 15.0), slopeParameter: 0.15)
                guard let orbit, let magnitudes else { continue }
                if let body = SmallBody(designation: "S\(index)", kind: .asteroid, number: index, orbit: orbit,
                                        photometry: .asteroid(magnitudes)) {
                    result.append(body)
                }
            } else {
                let shape = next()
                let perihelion = exp(next(log(0.1), log(6.0)))
                let eccentricity = shape < 0.55 ? next(0.3, 0.999) : (shape < 0.65 ? 1.0 : next(1.0, 1.02))
                let time = 2_461_300.0 + next(-1_100.0, 1_100.0)
                let orbit = SmallBodyElements(perihelionDistanceAU: perihelion, eccentricity: eccentricity, inclination: inclination,
                                            argumentOfPerihelion: argument, longitudeOfAscendingNode: node,
                                            perihelionJulianDayTT: time, epochJulianDayTT: 2_461_330.5)
                let magnitudes = CometMagnitudes(totalMagnitude: next(4.0, 16.0), totalSlope: next(5.0, 20.0))
                guard let orbit, let magnitudes else { continue }
                if let body = SmallBody(designation: "C/S\(index)", kind: .comet, orbit: orbit, photometry: .comet(magnitudes)) {
                    result.append(body)
                }
            }
        }
        return result
    }
}
