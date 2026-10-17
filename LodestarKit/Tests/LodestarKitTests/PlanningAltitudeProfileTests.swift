import XCTest
@testable import LodestarKit

/// The sampled-altitude machinery against a model whose answers are known in closed form: a fixed
/// target's sin(altitude) is `sin φ sin δ + cos φ cos δ cos H`, with the hour angle H advancing at the
/// sidereal rate.
final class PlanningAltitudeProfileTests: XCTestCase {
    private typealias Profile = NightPlanner.AltitudeProfile

    /// Hour angle advance in degrees per second of solar time.
    private let rate = 360.985_647_366_29 / 86_400

    private struct Model {
        let latitude: Double
        let declination: Double
        let hourAngleAtStart: Double
        let rate: Double

        func sine(at seconds: Double) -> Double {
            let hourAngle = hourAngleAtStart + rate * seconds
            return AstroMath.sinDeg(latitude) * AstroMath.sinDeg(declination)
                + AstroMath.cosDeg(latitude) * AstroMath.cosDeg(declination) * AstroMath.cosDeg(hourAngle)
        }

        /// Seconds from the start at which the hour angle is `hourAngle` (degrees).
        func time(ofHourAngle hourAngle: Double) -> Double { (hourAngle - hourAngleAtStart) / rate }
    }

    /// A profile of the model over `duration` seconds, sampled every `step` seconds.
    private func profile(of model: Model, duration: Double, step: Double = 600) -> Profile {
        let count = Int((duration / step).rounded())
        return Profile(step: duration / Double(count), sines: (0...count).map { model.sine(at: Double($0) * duration / Double(count)) })
    }

    /// Declination −29° seen from 40° N, from 6 hours before to 6 hours after transit.
    private var galacticCentreLike: Model { Model(latitude: 40, declination: -29, hourAngleAtStart: -90, rate: rate) }

    // MARK: Interpolation

    func testInterpolationIsExactAtTheSamples() {
        let model = galacticCentreLike
        let profile = profile(of: model, duration: 43_200)
        for index in stride(from: 0, through: profile.sines.count - 1, by: 7) {
            XCTAssertEqual(profile.sine(atIndex: Double(index)), profile.sines[index], accuracy: 1e-15)
        }
    }

    func testInterpolationBetweenSamplesFollowsTheSinusoidToTenMillionths() {
        let model = galacticCentreLike
        let profile = profile(of: model, duration: 43_200)
        var worst = 0.0
        for tick in 0...1_000 {
            let seconds = 43_200 * Double(tick) / 1_000
            worst = max(worst, abs(profile.sine(atIndex: seconds / profile.step) - model.sine(at: seconds)))
        }
        XCTAssertLessThan(worst, 2e-7)
    }

    func testShortProfilesInterpolateExactlyWithLowerDegrees() {
        let linear = Profile(step: 10, sines: [0.2, 0.6])
        XCTAssertEqual(linear.sine(atIndex: 0.25), 0.3, accuracy: 1e-15)
        let quadratic = Profile(step: 10, sines: [1, 0, 1])      // x² − 2x + 1 sampled at 0, 1, 2
        XCTAssertEqual(quadratic.sine(atIndex: 0.5), 0.25, accuracy: 1e-15)
        XCTAssertEqual(quadratic.sine(atIndex: 1.5), 0.25, accuracy: 1e-15)
        XCTAssertEqual(linear.duration, 10)
        XCTAssertEqual(quadratic.duration, 20)
    }

    // MARK: Maximum

    func testMaximumIsTheCulminationOfTheSinusoid() {
        let model = galacticCentreLike
        let profile = profile(of: model, duration: 43_200)
        let peak = profile.maximum(from: 0, to: profile.duration)
        XCTAssertEqual(peak.offset, model.time(ofHourAngle: 0), accuracy: 0.5)
        // The culmination altitude is 90° − |latitude − declination| = 90° − 69°.
        XCTAssertEqual(peak.sine, AstroMath.cosDeg(69), accuracy: 1e-7)
        XCTAssertEqual(AstroMath.asinDeg(peak.sine), 21, accuracy: 1e-5)
    }

    func testMaximumOfAPartOfTheProfileRespectsTheBounds() {
        let model = galacticCentreLike
        let profile = profile(of: model, duration: 43_200)
        let transit = model.time(ofHourAngle: 0)
        let before = profile.maximum(from: 1_000, to: transit - 3_000)
        XCTAssertEqual(before.offset, transit - 3_000, accuracy: 1e-6, "rising: the best moment is the end of the range")
        XCTAssertEqual(before.sine, model.sine(at: transit - 3_000), accuracy: 1e-7)
        let after = profile.maximum(from: transit + 2_345, to: 40_000)
        XCTAssertEqual(after.offset, transit + 2_345, accuracy: 1e-6, "falling: the best moment is the start of the range")
        let around = profile.maximum(from: transit - 100, to: transit + 5_000)
        XCTAssertEqual(around.offset, transit, accuracy: 0.5)
        let point = profile.maximum(from: 5_000, to: 5_000)
        XCTAssertEqual(point.offset, 5_000, accuracy: 1e-9)
        XCTAssertEqual(point.sine, model.sine(at: 5_000), accuracy: 1e-7)
    }

    func testMaximumClampsOffsetsOutsideTheProfile() {
        let profile = profile(of: galacticCentreLike, duration: 43_200)
        let whole = profile.maximum(from: -1e9, to: 1e9)
        XCTAssertEqual(whole.offset, profile.maximum(from: 0, to: profile.duration).offset, accuracy: 1e-9)
    }

    func testMaximumOfAShortProfileIsItsHigherEnd() {
        let two = Profile(step: 60, sines: [0.1, 0.4])
        XCTAssertEqual(two.maximum(from: 0, to: 60).offset, 60, accuracy: 1e-9)
        XCTAssertEqual(two.maximum(from: 0, to: 60).sine, 0.4, accuracy: 1e-12)
    }

    /// A target that passes within a hundredth of a degree of the zenith has a sharp altitude peak that
    /// ten-minute samples of the altitude itself could not follow; the sine is smooth.
    func testNearZenithPeakIsReproducedThroughTheSine() {
        let model = Model(latitude: 40, declination: 39.99, hourAngleAtStart: -90, rate: rate)
        let profile = profile(of: model, duration: 43_200)
        let peak = profile.maximum(from: 0, to: profile.duration)
        XCTAssertEqual(AstroMath.asinDeg(peak.sine), 89.99, accuracy: 0.03)
        XCTAssertEqual(peak.offset, model.time(ofHourAngle: 0), accuracy: 30)
    }

    // MARK: Threshold crossings

    func testStretchesAboveAThresholdMatchTheClosedForm() throws {
        let model = galacticCentreLike
        let profile = profile(of: model, duration: 43_200)
        for altitude in [-0.5667, 5.0, 10.0, 15.0, 20.0] {
            let threshold = AstroMath.sinDeg(altitude)
            let cosine = (threshold - AstroMath.sinDeg(40) * AstroMath.sinDeg(-29)) / (AstroMath.cosDeg(40) * AstroMath.cosDeg(-29))
            let spans = profile.offsets(atOrAbove: threshold)
            let halfWidth = AstroMath.acosDeg(cosine)
            XCTAssertEqual(spans.count, 1, "altitude \(altitude)")
            let span = try XCTUnwrap(spans.first)
            XCTAssertEqual(span.start, model.time(ofHourAngle: -halfWidth), accuracy: 0.5, "rise at \(altitude)")
            XCTAssertEqual(span.end, model.time(ofHourAngle: halfWidth), accuracy: 0.5, "set at \(altitude)")
        }
    }

    func testStretchesWhenTheProfileStartsOrEndsAboveTheThreshold() throws {
        let model = Model(latitude: 40, declination: -29, hourAngleAtStart: -30, rate: rate)
        let profile = profile(of: model, duration: 20_000)        // from H = −30° to +50°
        let threshold = AstroMath.sinDeg(15)
        let spans = profile.offsets(atOrAbove: threshold)
        XCTAssertEqual(spans.count, 1)
        let span = try XCTUnwrap(spans.first)
        XCTAssertEqual(span.start, 0)
        let cosine = (threshold - AstroMath.sinDeg(40) * AstroMath.sinDeg(-29)) / (AstroMath.cosDeg(40) * AstroMath.cosDeg(-29))
        XCTAssertEqual(span.end, model.time(ofHourAngle: AstroMath.acosDeg(cosine)), accuracy: 0.5)

        let everywhere = profile.offsets(atOrAbove: -1)
        XCTAssertEqual(everywhere.count, 1)
        XCTAssertEqual(everywhere.first?.start, 0)
        XCTAssertEqual(everywhere.first?.end ?? .nan, profile.duration, accuracy: 1e-9)
        XCTAssertTrue(profile.offsets(atOrAbove: 0.99).isEmpty)
    }

    func testTwoSeparateStretchesWhenTheTargetCulminatesTwiceInTheProfile() throws {
        // A 32-hour profile of a circumpolar target covers two upper culminations (H = 0° and 360°).
        // The target stays between 50° (lower culmination) and 70° (upper culmination) high.
        let model = Model(latitude: 60, declination: 80, hourAngleAtStart: -60, rate: rate)
        let profile = profile(of: model, duration: 32 * 3_600)
        let threshold = AstroMath.sinDeg(65)
        let cosine = (threshold - AstroMath.sinDeg(60) * AstroMath.sinDeg(80)) / (AstroMath.cosDeg(60) * AstroMath.cosDeg(80))
        let halfWidth = AstroMath.acosDeg(cosine)
        let spans = profile.offsets(atOrAbove: threshold)
        XCTAssertEqual(spans.count, 2)
        let first = try XCTUnwrap(spans.first), second = try XCTUnwrap(spans.last)
        XCTAssertEqual(first.start, model.time(ofHourAngle: -halfWidth), accuracy: 0.5)
        XCTAssertEqual(first.end, model.time(ofHourAngle: halfWidth), accuracy: 0.5)
        XCTAssertEqual(second.start, model.time(ofHourAngle: 360 - halfWidth), accuracy: 0.5)
        XCTAssertEqual(second.end, model.time(ofHourAngle: 360 + halfWidth), accuracy: 0.5)

        let always = profile.offsets(atOrAbove: AstroMath.sinDeg(49.9))
        XCTAssertEqual(always.count, 1)
        XCTAssertEqual(always.first?.start, 0)
        XCTAssertEqual(always.first?.end ?? .nan, profile.duration, accuracy: 1e-9)
    }

    func testAThresholdAtASampleValueCountsTheSampleAsAbove() {
        let profile = Profile(step: 60, sines: [0, 0.5, 0.5, 0])
        let spans = profile.offsets(atOrAbove: 0.5)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.start ?? .nan, 60, accuracy: 3)
        XCTAssertEqual(spans.first?.end ?? .nan, 120, accuracy: 3)
    }
}
