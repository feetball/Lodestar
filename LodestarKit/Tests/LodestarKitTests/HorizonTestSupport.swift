import XCTest
@testable import LodestarKit

/// Observers, a synthetic skyline and a sweep generator shared by the Horizon tests.
enum HorizonTestSupport {
    /// A reproducible source of random numbers (SplitMix64); the Kotlin tests use the same sequence.
    final class SeededGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// A number in [0, 1) from the top 53 bits.
        func nextDouble() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }

        /// A number in [-1, 1).
        func nextSigned() -> Double { 2 * nextDouble() - 1 }
    }

    static let boulder = Observer(location: GeographicLocation(latitude: 40, longitude: -105.27, elevation: 1650))
    static let equator = Observer(location: GeographicLocation(latitude: 0, longitude: 0, elevation: 0))
    static let tromso = Observer(location: GeographicLocation(latitude: 69.65, longitude: 18.96, elevation: 0))
    static let sydney = Observer(location: GeographicLocation(latitude: -33.87, longitude: 151.21, elevation: 0))

    /// The skyline the synthetic sweeps follow: low trees (2°) all round, a ridge to the east that peaks at 30°
    /// at azimuth 90° and falls away linearly over 40° on either side, and a 12° building from 184° to 196° with
    /// sloping sides that reach the trees at 180° and 200°. It is linear between whole degrees, so a bin's median is
    /// the skyline at its middle.
    static func truth(_ azimuth: Double) -> Double {
        var altitude = 2.0
        let ridge = 1 - abs(AstroMath.normalizeSignedDegrees(azimuth - 90)) / 40
        if ridge > 0 { altitude = max(altitude, 30 * ridge) }
        let wrapped = AstroMath.normalizeDegrees(azimuth)
        if wrapped >= 180 && wrapped <= 200 {
            altitude = max(altitude, 2 + 10 * min(1.0, min(wrapped - 180, 200 - wrapped) / 4))
        }
        return altitude
    }

    /// `truth` at every whole degree.
    static let truthProfile: HorizonProfile = {
        guard let profile = HorizonProfile(altitudes: (0..<360).map { truth(Double($0)) }) else {
            preconditionFailure("the synthetic skyline is valid")
        }
        return profile
    }()

    /// Feeds `recorder` with a camera that moves at constant speed from azimuth `from` to azimuth `to` (they may
    /// exceed 360°) at `rate` degrees per second, sampled at `hertz`, starting at time `start`, following the
    /// synthetic skyline plus `bias` and a uniform noise of ±`noise` (and, with probability `outliers`, a +15°
    /// error). Samples whose azimuth satisfies `skip` are not sent. Returns the time the sweep ends.
    @discardableResult
    static func sweep(_ recorder: inout HorizonRecorder, from: Double, to: Double, rate: Double, hertz: Double,
                      start: Double = 0, noise: Double = 0, outliers: Double = 0, bias: Double = 0,
                      random: SeededGenerator? = nil,
                      skip: (Double) -> Bool = { _ in false }) -> Double {
        let duration = abs(to - from) / rate
        let count = Int((duration * hertz).rounded(.down))
        for index in 0...count {
            let fraction = count == 0 ? 0 : Double(index) / Double(count)
            let azimuth = from + (to - from) * fraction
            if skip(azimuth) { continue }
            var altitude = truth(azimuth) + bias
            if let random {
                if noise > 0 { altitude += noise * random.nextSigned() }
                if outliers > 0, random.nextDouble() < outliers { altitude += 15 }
            }
            recorder.add(azimuth: azimuth, altitude: altitude, timestamp: start + duration * fraction)
        }
        return start + duration
    }

    /// The largest difference, over the whole degrees in `azimuths`, between a profile and the synthetic skyline.
    static func largestError(_ profile: HorizonProfile, _ azimuths: ClosedRange<Int> = 0...359) -> Double {
        azimuths.map { abs(profile.altitude(at: Double($0)) - truth(Double($0))) }.max() ?? 0
    }

    /// The mean absolute difference over the whole degrees in `azimuths`.
    static func meanError(_ profile: HorizonProfile, _ azimuths: ClosedRange<Int> = 0...359) -> Double {
        azimuths.reduce(0) { $0 + abs(profile.altitude(at: Double($1)) - truth(Double($1))) } / Double(azimuths.count)
    }

    /// A skyline of `altitude` degrees between azimuths `from` and `to` (clockwise) and 0° elsewhere.
    static func wall(_ altitude: Double, from: Double, to: Double) -> HorizonProfile {
        HorizonProfile.flat.setting(to: altitude, in: AzimuthRange(from: from, to: to))
    }

    /// An instant `seconds` after 2026-06-20T18:00:00Z.
    static func instant(_ seconds: Double) -> Date {
        date("2026-06-20T18:00:00Z").addingTimeInterval(seconds)
    }

    /// The instant of an ISO 8601 string such as "2026-06-20T18:00:00Z".
    static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else { preconditionFailure("bad date \(text)") }
        return date
    }
}
