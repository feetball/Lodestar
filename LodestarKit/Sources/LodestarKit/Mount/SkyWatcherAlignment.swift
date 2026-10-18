import Foundation

/// One alignment measurement: the star whose direction in the mount's local frame is `direction` was centred while the encoders
/// read `axis1Degrees` and `axis2Degrees`.
public struct SkyWatcherAlignmentPoint: Hashable, Sendable {
    /// The encoder angle of axis 1 in degrees (position count times 360 over the counts per revolution, signed by the axis sense).
    public let axis1Degrees: Double
    /// The encoder angle of axis 2 in degrees.
    public let axis2Degrees: Double
    /// The true direction of the star in the local frame (see `SkyWatcherPointingModel`).
    public let direction: Vector3
    /// When the measurement was taken.
    public let timestamp: Date
    /// The star's name, if the app gave one (at most 120 characters).
    public let name: String?

    public init(axis1Degrees: Double, axis2Degrees: Double, direction: Vector3, timestamp: Date, name: String? = nil) {
        self.axis1Degrees = axis1Degrees
        self.axis2Degrees = axis2Degrees
        self.direction = direction
        self.timestamp = timestamp
        self.name = name
    }
}

/// The result of fitting the pointing model to the alignment points.
public struct SkyWatcherAlignmentFit: Hashable, Sendable {
    /// The model with the fitted errors.
    public let model: SkyWatcherPointingModel
    /// For each point, the angle in degrees between the star and where the fitted model says the mount points.
    public let residualsDegrees: [Double]
    /// How far, in degrees, the model is expected to be off when it points somewhere else than at the aligned stars (the root mean
    /// square over a grid of axis angles, from the covariance of the fitted errors). A single star leaves about a degree, a well
    /// spread set of three stars a few tenths: add stars while the number is large.
    public let predictedErrorDegrees: Double

    public init(model: SkyWatcherPointingModel, residualsDegrees: [Double], predictedErrorDegrees: Double) {
        self.model = model
        self.residualsDegrees = residualsDegrees
        self.predictedErrorDegrees = predictedErrorDegrees
    }

    /// The root mean square of the residuals in degrees.
    public var rmsDegrees: Double {
        if residualsDegrees.isEmpty { return 0.0 }
        var sum = 0.0
        for value in residualsDegrees { sum += value * value }
        return (sum / Double(residualsDegrees.count)).squareRoot()
    }

    /// The largest residual in degrees.
    public var maximumResidualDegrees: Double {
        var result = 0.0
        for value in residualsDegrees where value > result { result = value }
        return result
    }

    /// False when the fitted errors are larger than a mount set up by hand can have (see `SkyWatcherAlignmentSolver.maximumIndexDegrees`
    /// and its siblings): usually a wrong star was centred, or the mount was not at its home position. The residuals may look fine
    /// then, because enough free errors can explain anything.
    public var isPlausible: Bool {
        let errors = model.errors
        return abs(errors.axis1Index) <= SkyWatcherAlignmentSolver.maximumIndexDegrees
            && abs(errors.axis2Index) <= SkyWatcherAlignmentSolver.maximumIndexDegrees
            && (errors.baseTiltX * errors.baseTiltX + errors.baseTiltY * errors.baseTiltY).squareRoot() <= SkyWatcherAlignmentSolver.maximumTiltDegrees
            && abs(errors.orthogonality) <= SkyWatcherAlignmentSolver.maximumOrthogonalityDegrees
            && abs(errors.cone) <= SkyWatcherAlignmentSolver.maximumConeDegrees
    }
}

/// How much the alignment fit trusts the points compared to what a hand-made set-up usually looks like (all in degrees). The two index
/// offsets have no prior: the home position can be off by any amount.
public struct SkyWatcherAlignmentPriors: Hashable, Sendable {
    /// The assumed scatter of one centred pointing; also covers what the model does not describe.
    public let measurementSigmaDegrees: Double
    /// The usual size of the tilt of the primary axis (polar alignment error, level error).
    public let tiltSigmaDegrees: Double
    /// The usual size of the orthogonality error.
    public let orthogonalitySigmaDegrees: Double
    /// The usual size of the cone error (a camera on a bracket is not collimated with the mount).
    public let coneSigmaDegrees: Double

    /// The values the driver uses.
    public static let standard = SkyWatcherAlignmentPriors()

    public init(measurementSigmaDegrees: Double = 0.1, tiltSigmaDegrees: Double = 1.0, orthogonalitySigmaDegrees: Double = 0.2,
                coneSigmaDegrees: Double = 1.0) {
        self.measurementSigmaDegrees = measurementSigmaDegrees
        self.tiltSigmaDegrees = tiltSigmaDegrees
        self.orthogonalitySigmaDegrees = orthogonalitySigmaDegrees
        self.coneSigmaDegrees = coneSigmaDegrees
    }
}

/// Fits the `SkyWatcherPointingModel` errors to alignment points by damped (Levenberg–Marquardt) least squares, in the spirit of
/// the phone alignment of `AlignmentSolver`: the six errors are always fitted together, and a prior on each of the four small ones
/// (what a hand-made set-up looks like, `SkyWatcherAlignmentPriors`) keeps the poorly determined ones at zero, so that a few stars never
/// invent large corrections.
///
/// One star determines the two index offsets exactly and leaves the others at zero. Two stars begin to show the tilt of the primary axis
/// (the polar alignment error of an equatorial mount, the level error of an alt-azimuth one), three well-spread stars the orthogonality
/// and cone errors as well. How much the fit can be trusted away from the stars is `SkyWatcherAlignmentFit.predictedErrorDegrees`; the
/// residuals tell how well the model explains the points: with a wrong star they are large.
public enum SkyWatcherAlignmentSolver {
    /// The most alignment points kept.
    public static let maximumPoints = 8
    /// The largest home position error (encoder zero) of a plausible alignment, degrees.
    public static let maximumIndexDegrees = 60.0
    /// The largest tilt of the primary axis (polar alignment or level error) of a plausible alignment, degrees.
    public static let maximumTiltDegrees = 6.0
    /// The largest orthogonality error of a plausible alignment, degrees.
    public static let maximumOrthogonalityDegrees = 1.5
    /// The largest cone error of a plausible alignment, degrees.
    public static let maximumConeDegrees = 1.5

    private static let maximumIterations = 80
    private static let derivativeStep = 1e-6
    private static let parameterCount = 6
    private static let equatorialSampleAxis1: [Double] = [-60, -20, 20, 60]
    private static let equatorialSampleAxis2: [Double] = [10, 40, 70, 100]
    private static let altAzimuthSampleAxis1: [Double] = [0, 60, 120, 180, 240, 300]
    private static let altAzimuthSampleAxis2: [Double] = [20, 45, 70]

    /// Fits the model.
    ///
    /// - Throws: `MountError.invalidInput` if there are no points, more than `maximumPoints` or a value is not finite.
    public static func solve(_ points: [SkyWatcherAlignmentPoint], mode: SkyWatcherMountMode, isSouthernHemisphere: Bool,
                             priors: SkyWatcherAlignmentPriors = .standard) throws -> SkyWatcherAlignmentFit {
        if points.isEmpty { throw MountError.invalidInput(detail: "there is no alignment point") }
        if points.count > maximumPoints { throw MountError.invalidInput(detail: "at most \(maximumPoints) alignment points are used") }
        for point in points {
            if !point.axis1Degrees.isFinite || !point.axis2Degrees.isFinite || !point.direction.isFinite || !(point.direction.length > 0) {
                throw MountError.invalidInput(detail: "an alignment point is not a number")
            }
        }
        let directions = points.map { $0.direction.normalized }
        var values = [Double](repeating: 0, count: parameterCount)
        initialIndex(points, directions, mode, isSouthernHemisphere, &values)

        var cost = costOf(values, points, directions, mode, isSouthernHemisphere, priors)
        var lambda = 1e-3
        for _ in 0 ..< maximumIterations {
            let residual = residuals(values, points, directions, mode, isSouthernHemisphere, priors)
            let jacobian = jacobianOf(values, points, directions, mode, isSouthernHemisphere, priors, rows: residual.count)
            let normal = normalMatrix(jacobian, rows: residual.count)
            var gradient = [Double](repeating: 0, count: parameterCount)
            for a in 0 ..< parameterCount {
                var sum = 0.0
                for row in 0 ..< residual.count { sum += jacobian[a][row] * residual[row] }
                gradient[a] = sum
            }
            var accepted = false
            var largestStep = 0.0
            var newCost = cost
            for _ in 0 ..< 14 {
                var damped = normal
                for index in 0 ..< parameterCount { damped[index][index] += lambda * (normal[index][index] + 1e-9) }
                var rightHand = [Double](repeating: 0, count: parameterCount)
                for index in 0 ..< parameterCount { rightHand[index] = -gradient[index] }
                guard let step = solveLinear(damped, rightHand) else {
                    lambda *= 4
                    continue
                }
                var trial = values
                for index in 0 ..< parameterCount { trial[index] += step[index] }
                let trialCost = costOf(trial, points, directions, mode, isSouthernHemisphere, priors)
                if trialCost < cost {
                    values = trial
                    largestStep = 0.0
                    for index in 0 ..< parameterCount { largestStep = max(largestStep, abs(step[index])) }
                    newCost = trialCost
                    lambda = max(lambda / 3, 1e-9)
                    accepted = true
                    break
                }
                lambda *= 4
            }
            if !accepted { break }
            let improvement = cost - newCost
            cost = newCost
            if largestStep < 1e-12 || improvement < 1e-14 * (1 + cost) { break }
        }

        let model = SkyWatcherPointingModel(mode: mode, isSouthernHemisphere: isSouthernHemisphere,
                                            errors: SkyWatcherPointingErrors.fromRadians(values))
        var residualsDegrees: [Double] = []
        for index in points.indices {
            let pointed = model.direction(axis1Degrees: points[index].axis1Degrees, axis2Degrees: points[index].axis2Degrees)
            residualsDegrees.append(pointed.angle(to: directions[index]))
        }
        let predicted = predictedError(values, points, directions, mode, isSouthernHemisphere, priors)
        return SkyWatcherAlignmentFit(model: model, residualsDegrees: residualsDegrees, predictedErrorDegrees: predicted)
    }

    // The index offsets that make each point fit the ideal geometry, averaged (circular mean) over the points.
    private static func initialIndex(_ points: [SkyWatcherAlignmentPoint], _ directions: [Vector3], _ mode: SkyWatcherMountMode,
                                     _ isSouthernHemisphere: Bool, _ values: inout [Double]) {
        let nominal = SkyWatcherPointingModel.nominal(mode: mode, isSouthernHemisphere: isSouthernHemisphere)
        var sin1 = 0.0
        var cos1 = 0.0
        var sin2 = 0.0
        var cos2 = 0.0
        for index in points.indices {
            let point = points[index]
            let candidates = nominal.solutions(directions[index], preferredAxis1Degrees: point.axis1Degrees)
            var bestOffset1 = 0.0
            var bestOffset2 = 0.0
            var bestCost = Double.greatestFiniteMagnitude
            for candidate in candidates {
                let offset1 = AstroMath.normalizeSignedDegrees(candidate.axis1 - point.axis1Degrees)
                let offset2 = AstroMath.normalizeSignedDegrees(candidate.axis2 - point.axis2Degrees)
                let candidateCost = abs(offset1) + abs(offset2)
                if candidateCost < bestCost {
                    bestCost = candidateCost
                    bestOffset1 = offset1
                    bestOffset2 = offset2
                }
            }
            sin1 += AstroMath.sinDeg(bestOffset1)
            cos1 += AstroMath.cosDeg(bestOffset1)
            sin2 += AstroMath.sinDeg(bestOffset2)
            cos2 += AstroMath.cosDeg(bestOffset2)
        }
        values[0] = atan2(sin1, cos1)
        values[1] = atan2(sin2, cos2)
    }

    /// The weighted residuals: three per point (the vector between the pointed and the true direction over the scatter) and four priors.
    private static func residuals(_ values: [Double], _ points: [SkyWatcherAlignmentPoint], _ directions: [Vector3],
                                  _ mode: SkyWatcherMountMode, _ isSouthernHemisphere: Bool, _ priors: SkyWatcherAlignmentPriors) -> [Double] {
        let sigma = AstroMath.radians(priors.measurementSigmaDegrees)
        var result = [Double](repeating: 0, count: 3 * points.count + 4)
        for index in points.indices {
            let pointed = SkyWatcherPointingModel.rawDirection(mode: mode, isSouthernHemisphere: isSouthernHemisphere, errors: values,
                                                               axis1Degrees: points[index].axis1Degrees,
                                                               axis2Degrees: points[index].axis2Degrees)
            result[3 * index] = (pointed.x - directions[index].x) / sigma
            result[3 * index + 1] = (pointed.y - directions[index].y) / sigma
            result[3 * index + 2] = (pointed.z - directions[index].z) / sigma
        }
        let base = 3 * points.count
        result[base] = values[2] / AstroMath.radians(priors.tiltSigmaDegrees)
        result[base + 1] = values[3] / AstroMath.radians(priors.tiltSigmaDegrees)
        result[base + 2] = values[4] / AstroMath.radians(priors.orthogonalitySigmaDegrees)
        result[base + 3] = values[5] / AstroMath.radians(priors.coneSigmaDegrees)
        return result
    }

    private static func costOf(_ values: [Double], _ points: [SkyWatcherAlignmentPoint], _ directions: [Vector3],
                               _ mode: SkyWatcherMountMode, _ isSouthernHemisphere: Bool, _ priors: SkyWatcherAlignmentPriors) -> Double {
        var sum = 0.0
        for value in residuals(values, points, directions, mode, isSouthernHemisphere, priors) { sum += value * value }
        return sum
    }

    /// The Jacobian by central differences, one row per parameter.
    private static func jacobianOf(_ values: [Double], _ points: [SkyWatcherAlignmentPoint], _ directions: [Vector3],
                                   _ mode: SkyWatcherMountMode, _ isSouthernHemisphere: Bool, _ priors: SkyWatcherAlignmentPriors,
                                   rows: Int) -> [[Double]] {
        var jacobian = [[Double]](repeating: [Double](repeating: 0, count: rows), count: parameterCount)
        for column in 0 ..< parameterCount {
            var up = values
            var down = values
            up[column] += derivativeStep
            down[column] -= derivativeStep
            let high = residuals(up, points, directions, mode, isSouthernHemisphere, priors)
            let low = residuals(down, points, directions, mode, isSouthernHemisphere, priors)
            for row in 0 ..< rows { jacobian[column][row] = (high[row] - low[row]) / (2 * derivativeStep) }
        }
        return jacobian
    }

    private static func normalMatrix(_ jacobian: [[Double]], rows: Int) -> [[Double]] {
        var normal = [[Double]](repeating: [Double](repeating: 0, count: parameterCount), count: parameterCount)
        for a in 0 ..< parameterCount {
            for b in 0 ..< parameterCount {
                var sum = 0.0
                for row in 0 ..< rows { sum += jacobian[a][row] * jacobian[b][row] }
                normal[a][b] = sum
            }
        }
        return normal
    }

    /// The root mean square over a grid of axis angles of the pointing error that the covariance of the fitted errors implies.
    private static func predictedError(_ values: [Double], _ points: [SkyWatcherAlignmentPoint], _ directions: [Vector3],
                                       _ mode: SkyWatcherMountMode, _ isSouthernHemisphere: Bool, _ priors: SkyWatcherAlignmentPriors) -> Double {
        let residual = residuals(values, points, directions, mode, isSouthernHemisphere, priors)
        let jacobian = jacobianOf(values, points, directions, mode, isSouthernHemisphere, priors, rows: residual.count)
        let normal = normalMatrix(jacobian, rows: residual.count)
        var covariance = [[Double]](repeating: [Double](repeating: 0, count: parameterCount), count: parameterCount)
        for column in 0 ..< parameterCount {
            var unit = [Double](repeating: 0, count: parameterCount)
            unit[column] = 1.0
            guard let solved = solveLinear(normal, unit) else { return 90.0 }
            for row in 0 ..< parameterCount { covariance[row][column] = solved[row] }
        }
        let grid1 = mode == .equatorial ? equatorialSampleAxis1 : altAzimuthSampleAxis1
        let grid2 = mode == .equatorial ? equatorialSampleAxis2 : altAzimuthSampleAxis2
        var total = 0.0
        var count = 0
        for axis1 in grid1 {
            for axis2 in grid2 {
                var sensitivity = [Vector3](repeating: Vector3.zero, count: parameterCount)
                for column in 0 ..< parameterCount {
                    var up = values
                    var down = values
                    up[column] += derivativeStep
                    down[column] -= derivativeStep
                    let high = SkyWatcherPointingModel.rawDirection(mode: mode, isSouthernHemisphere: isSouthernHemisphere, errors: up,
                                                                    axis1Degrees: axis1, axis2Degrees: axis2)
                    let low = SkyWatcherPointingModel.rawDirection(mode: mode, isSouthernHemisphere: isSouthernHemisphere, errors: down,
                                                                   axis1Degrees: axis1, axis2Degrees: axis2)
                    sensitivity[column] = (high - low) / (2 * derivativeStep)
                }
                var variance = 0.0
                for a in 0 ..< parameterCount {
                    for b in 0 ..< parameterCount { variance += sensitivity[a].dot(sensitivity[b]) * covariance[a][b] }
                }
                total += max(variance, 0.0)
                count += 1
            }
        }
        return AstroMath.degrees((total / Double(count)).squareRoot())
    }

    /// Solves `a x = b` by Gaussian elimination with partial pivoting; nil if the matrix is singular.
    private static func solveLinear(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)
        for row in 0 ..< n {
            for column in 0 ..< n { m[row][column] = a[row][column] }
            m[row][n] = b[row]
        }
        for column in 0 ..< n {
            var pivot = column
            for row in (column + 1) ..< n where abs(m[row][column]) > abs(m[pivot][column]) { pivot = row }
            if abs(m[pivot][column]) < 1e-300 { return nil }
            if pivot != column { m.swapAt(pivot, column) }
            for row in (column + 1) ..< n {
                let factor = m[row][column] / m[column][column]
                for k in column ..< (n + 1) { m[row][k] -= factor * m[column][k] }
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = m[row][n]
            for k in (row + 1) ..< n { sum -= m[row][k] * x[k] }
            x[row] = sum / m[row][row]
        }
        for value in x where !value.isFinite { return nil }
        return x
    }
}
