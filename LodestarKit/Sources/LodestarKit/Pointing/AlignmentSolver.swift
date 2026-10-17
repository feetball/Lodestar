import Foundation

/// Finds the heading offset and device-frame correction that bring the phone-derived boresights
/// onto the true positions of the aligned objects.
///
/// The model for point *i* is `boresightᵢ = Rz(−heading) · Dᵢ · R(ω) · a₀`: the raw device-to-world
/// rotation `Dᵢ`, the mount's nominal camera axis `a₀` turned by the device-frame rotation vector
/// `ω`, then the world yawed by the heading offset. `ω` has no component along `a₀` (a twist about
/// the optical axis does not move the boresight), so it is written `θ_r·right + θ_u·up`.
enum AlignmentSolver {
    struct Fit {
        /// Compass correction in degrees.
        let headingOffset: Double
        /// Device-frame rotation vector in degrees.
        let deviceCorrection: Vector3
        /// Angular distance in degrees between each corrected boresight and its target.
        let residuals: [Double]
        /// Expected pointing error in degrees away from the points (see `Problem.uncertainty`).
        let uncertainty: Double
    }

    /// Assumed scatter of one centred pointing measurement (radians). Weights the data against the prior.
    private static let measurementSigma = AstroMath.radians(0.25)
    /// Prior scatter of the device-frame angles (radians): irrelevant for well-spread points, but it
    /// keeps degenerate sets (all at one altitude and roll) from inventing large corrections.
    private static let correctionSigma = AstroMath.radians(10)
    /// Mean of cos²(altitude) over the sky above the horizon: how much of the compass error shows
    /// up as pointing error when the camera looks at a random direction in the sky.
    private static let meanSquaredAltitudeCosine = 2.0 / 3
    /// Cap on the reported uncertainty, degrees.
    private static let maximumUncertainty = 90.0
    private static let maximumIterations = 100
    /// Damping increases tried per iteration before the search is declared converged.
    private static let maximumDampingAttempts = 12
    /// Convergence threshold for the largest parameter step, radians.
    private static let stepTolerance = 1e-11
    /// Step of the central differences for the Jacobian, radians.
    private static let differenceStep = 1e-6

    /// Fits the model to validated points (at least one). A single point is solved in closed form;
    /// more points are refined by Levenberg–Marquardt starting from the newest point's solution.
    static func fit(_ points: [AlignmentPoint], mount: MountProfile) -> Fit {
        let problem = Problem(points: points, mount: mount)
        var parameters = closedForm(for: points[points.count - 1], mount: mount)
        if points.count > 1 {
            parameters = refine(problem, from: parameters)
        }
        return problem.fit(parameters)
    }

    /// Exact solution for one point as `[heading, θ_r, θ_u]` in radians: the altitude error is removed
    /// by the smallest device-frame rotation about the horizontal axis perpendicular to the measured
    /// boresight (valid for any camera roll), the remaining azimuth error becomes the heading offset.
    private static func closedForm(for point: AlignmentPoint, mount: MountProfile) -> [Double] {
        let deviceToWorld = point.attitude.deviceToWorld
        let measured = (deviceToWorld * mount.cameraAxis).normalized
        let coordinate = HorizontalCoordinate(vector: measured)
        // Rotating by +θ about ẑ × b lowers b along its vertical circle by θ.
        let horizontalAxis = PointingMath.worldUp.cross(measured).normalized
        let tilt = AstroMath.radians(coordinate.altitude - point.target.altitude)
        let deviceRotation = (deviceToWorld.transposed * horizontalAxis) * tilt
        let heading = AstroMath.radians(AstroMath.normalizeSignedDegrees(point.target.azimuth - coordinate.azimuth))
        return [heading, deviceRotation.dot(mount.cameraRight), deviceRotation.dot(mount.cameraUp)]
    }

    /// Levenberg–Marquardt with Marquardt scaling on the three parameters.
    private static func refine(_ problem: Problem, from start: [Double]) -> [Double] {
        var parameters = start
        var residuals = problem.residualVector(parameters)
        var cost = residuals.reduce(0) { $0 + $1 * $1 }
        var damping = 1e-3
        for _ in 0..<maximumIterations {
            let (hessian, gradient) = problem.normalEquations(at: parameters, residuals: residuals)
            var accepted = false
            var converged = false
            for _ in 0..<maximumDampingAttempts {
                var damped = hessian
                for a in 0..<3 { damped[a][a] += damping * max(hessian[a][a], 1e-9) }
                if let step = solve(damped, gradient.map { -$0 }) {
                    let candidate = [parameters[0] + step[0], parameters[1] + step[1], parameters[2] + step[2]]
                    let candidateResiduals = problem.residualVector(candidate)
                    let candidateCost = candidateResiduals.reduce(0) { $0 + $1 * $1 }
                    if candidateCost < cost {
                        parameters = candidate
                        residuals = candidateResiduals
                        cost = candidateCost
                        damping = max(damping / 5, 1e-12)
                        accepted = true
                        converged = step.allSatisfy { abs($0) < stepTolerance }
                        break
                    }
                }
                damping *= 5
            }
            if !accepted || converged { break }
        }
        return parameters
    }

    /// Gaussian elimination with partial pivoting for a 3×3 system; `nil` when singular.
    private static func solve(_ matrix: [[Double]], _ right: [Double]) -> [Double]? {
        var a = matrix
        var b = right
        for column in 0..<3 {
            var pivot = column
            for row in (column + 1)..<3 where abs(a[row][column]) > abs(a[pivot][column]) { pivot = row }
            guard abs(a[pivot][column]) > 1e-300 else { return nil }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for row in (column + 1)..<3 {
                let factor = a[row][column] / a[column][column]
                for k in column..<3 { a[row][k] -= factor * a[column][k] }
                b[row] -= factor * b[column]
            }
        }
        var x = [0.0, 0.0, 0.0]
        for row in stride(from: 2, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<3 { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x
    }

    /// The measurements in a form that can be evaluated quickly for trial parameters.
    private struct Problem {
        let deviceToWorld: [Matrix3]
        let targets: [Vector3]
        let axis: Vector3
        let right: Vector3
        let up: Vector3

        init(points: [AlignmentPoint], mount: MountProfile) {
            deviceToWorld = points.map { $0.attitude.deviceToWorld }
            targets = points.map { $0.target.unitVector }
            axis = mount.cameraAxis
            right = mount.cameraRight
            up = mount.cameraUp
        }

        /// Device-frame rotation vector (radians) for the parameters.
        func rotationVector(_ p: [Double]) -> Vector3 { right * p[1] + up * p[2] }

        /// Corrected world boresights for the parameters `[heading, θ_r, θ_u]` (radians).
        func boresights(_ p: [Double]) -> [Vector3] {
            let correctedAxis = PointingMath.rotationMatrix(rotationVector: rotationVector(p)) * axis
            let headingDegrees = AstroMath.degrees(p[0])
            return deviceToWorld.map { PointingMath.yawed($0 * correctedAxis, byAzimuth: headingDegrees) }
        }

        /// Weighted chord residuals (three per point) followed by the two prior terms.
        func residualVector(_ p: [Double]) -> [Double] {
            var out = [Double]()
            out.reserveCapacity(3 * targets.count + 2)
            for (boresight, target) in zip(boresights(p), targets) {
                let difference = (boresight - target) / AlignmentSolver.measurementSigma
                out.append(contentsOf: [difference.x, difference.y, difference.z])
            }
            out.append(p[1] / AlignmentSolver.correctionSigma)
            out.append(p[2] / AlignmentSolver.correctionSigma)
            return out
        }

        /// The Gauss–Newton normal matrix `JᵀJ` and gradient `Jᵀr` at the parameters.
        func normalEquations(at p: [Double], residuals: [Double]) -> (hessian: [[Double]], gradient: [Double]) {
            var hessian = [[Double]](repeating: [0, 0, 0], count: 3)
            var gradient = [0.0, 0.0, 0.0]
            for (row, derivative) in jacobian(at: p).enumerated() {
                for a in 0..<3 {
                    gradient[a] += derivative[a] * residuals[row]
                    for b in 0..<3 { hessian[a][b] += derivative[a] * derivative[b] }
                }
            }
            return (hessian, gradient)
        }

        /// Central-difference Jacobian of `residualVector`, one row per residual.
        func jacobian(at p: [Double]) -> [[Double]] {
            let h = AlignmentSolver.differenceStep
            var columns = [[Double]]()
            for index in 0..<3 {
                var plus = p, minus = p
                plus[index] += h
                minus[index] -= h
                let high = residualVector(plus), low = residualVector(minus)
                columns.append(zip(high, low).map { ($0 - $1) / (2 * h) })
            }
            return (0..<columns[0].count).map { [columns[0][$0], columns[1][$0], columns[2][$0]] }
        }

        /// Expected pointing error in degrees away from the points, from the parameter covariance
        /// `(JᵀJ)⁻¹` (the prior keeps it finite). A heading error moves the boresight by cos(altitude)
        /// times its size and the two device angles move it one-for-one in perpendicular directions,
        /// so the mean squared error over the sky and over camera rolls (which average out the
        /// cross terms) is `⟨cos²⟩·var(heading) + var(θ_r) + var(θ_u)`.
        func uncertainty(at p: [Double]) -> Double {
            let (hessian, _) = normalEquations(at: p, residuals: residualVector(p))
            func variance(_ index: Int) -> Double? {
                var unit = [0.0, 0.0, 0.0]
                unit[index] = 1
                return AlignmentSolver.solve(hessian, unit)?[index]
            }
            guard let heading = variance(0), let right = variance(1), let up = variance(2) else {
                return AlignmentSolver.maximumUncertainty
            }
            let meanSquare = AlignmentSolver.meanSquaredAltitudeCosine * heading + right + up
            return min(AstroMath.degrees(max(meanSquare, 0).squareRoot()), AlignmentSolver.maximumUncertainty)
        }

        func fit(_ p: [Double]) -> Fit {
            let residuals = zip(boresights(p), targets).map { $0.angle(to: $1) }
            return Fit(headingOffset: AstroMath.normalizeSignedDegrees(AstroMath.degrees(p[0])),
                       deviceCorrection: rotationVector(p) * AstroMath.degreesPerRadian,
                       residuals: residuals,
                       uncertainty: uncertainty(at: p))
        }
    }
}
