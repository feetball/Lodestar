import Foundation

extension RiseSetCalculator {
    /// Geometric altitude of one target for one observer, cheap to evaluate at many nearby instants.
    ///
    /// A rise/set search samples the altitude hundreds of times within a day. Rebuilding a full
    /// `SkyFrame` and recomputing the ephemeris at every sample would dominate its cost, so this
    /// sampler reuses the slowly changing parts:
    /// - A `SkyFrame` is built once per six hours; its precession–nutation matrix and (for stars) the
    ///   apparent place are held fixed in between, which changes them by less than 0.02″. The Earth's
    ///   rotation, which is what moves the target across the sky, is applied exactly at every sample.
    /// - Solar-system bodies are evaluated on a grid of nodes (hourly for the Moon, three-hourly for the
    ///   Sun and planets) and interpolated with cubic Lagrange polynomials, whose error stays below
    ///   0.001″ at those spacings.
    ///
    /// The sampler caches as it goes, so it is a class and is not thread safe.
    final class Sampler {
        /// What the sampler follows.
        enum Target {
            case body(SolarSystemBody)
            /// A fixed object given by its J2000 catalog place and optional proper motion.
            case fixed(EquatorialCoordinate, ProperMotion?)
        }

        /// Everything that is fixed while the Earth turns, for one six-hour stretch.
        private struct Chunk {
            let referenceTime: Double
            /// Local apparent sidereal time at `referenceTime`, in degrees.
            let referenceSiderealAngle: Double
            /// Rotation from the Earth-fixed equatorial frame (x towards the meridian) to ENU.
            let localToHorizontal: Matrix3
            /// J2000 mean equatorial to true equatorial of date.
            let precessionNutation: Matrix3
            /// The observer's geocentric position in the Earth-fixed equatorial frame (AU).
            let observerEarthFixed: Vector3
            /// For a fixed target, its apparent direction in the true equatorial frame of date.
            let fixedDirection: Vector3
        }

        private static let chunkLength: TimeInterval = 6 * 3600
        /// Times further than this (about 300 000 years) from the reference date are not evaluated.
        private static let maximumTime: TimeInterval = 1e13
        /// The rate at which local sidereal time advances, in degrees per second of UT.
        private static let siderealDegreesPerSecond = 360.985_647_366_29 / JulianDate.secondsPerDay

        private let target: Target
        private let observer: Observer
        private let nodeSpacing: TimeInterval
        private var chunks = [Int: Chunk]()
        private var nodes = [Int: Vector3]()

        init(target: Target, observer: Observer) {
            self.target = target
            self.observer = observer
            if case .body(let body) = target, body != .moon {
                nodeSpacing = 3 * 3600
            } else {
                nodeSpacing = 3600
            }
        }

        /// The altitude of the target at `time` (seconds since the Foundation reference date). The result
        /// is not a number for a time that is not finite or lies more than 300 000 years from the reference date.
        func sample(at time: Double) -> Sample {
            guard time.isFinite, abs(time) < Self.maximumTime else { return Sample(centreAltitude: .nan) }
            let chunk = chunk(containing: time)
            let siderealAngle = chunk.referenceSiderealAngle
                + Self.siderealDegreesPerSecond * (time - chunk.referenceTime)
            let earthRotation = Matrix3.frameRotationZ(AstroMath.radians(siderealAngle))

            switch target {
            case .fixed:
                return Sample(centreAltitude: Self.altitude(of: chunk.localToHorizontal
                                                                       * (earthRotation * chunk.fixedDirection)))
            case .body(let body):
                let geocentric = geocentricPosition(of: body, at: time)
                let topocentric = chunk.localToHorizontal
                    * (earthRotation * (chunk.precessionNutation * geocentric) - chunk.observerEarthFixed)
                let centre = Self.altitude(of: topocentric)
                guard body == .moon else { return Sample(centreAltitude: centre) }
                // The Moon's horizon event is its upper limb, so its apparent semi-diameter matters.
                let distanceKilometers = topocentric.length * SkyFrame.kilometersPerAU
                let semiDiameter = AstroMath.asinDeg(body.meanRadiusKilometers / distanceKilometers)
                return Sample(centreAltitude: centre, limbAllowance: semiDiameter)
            }
        }

        private static func altitude(of direction: Vector3) -> Double {
            AstroMath.atan2Deg(direction.z, (direction.x * direction.x + direction.y * direction.y).squareRoot())
        }

        // MARK: Frames

        private func chunk(containing time: Double) -> Chunk {
            let index = Int((time / Self.chunkLength).rounded(.down))
            if let cached = chunks[index] { return cached }

            let referenceTime = (Double(index) + 0.5) * Self.chunkLength
            let frame = SkyFrame(date: Date(timeIntervalSinceReferenceDate: referenceTime), observer: observer)
            let siderealAngle = frame.localApparentSiderealTime
            let toEarthFixed = Matrix3.frameRotationZ(AstroMath.radians(siderealAngle))
            var fixedDirection = Vector3.zero
            if case .fixed(let position, let properMotion) = target {
                fixedDirection = frame.apparentPlace(j2000: position, properMotion: properMotion).unitVector
            }
            let chunk = Chunk(referenceTime: referenceTime,
                              referenceSiderealAngle: siderealAngle,
                              localToHorizontal: frame.equatorialOfDateToHorizontal * toEarthFixed.transposed,
                              precessionNutation: frame.precessionNutationMatrix,
                              observerEarthFixed: toEarthFixed * frame.observerPositionOfDate,
                              fixedDirection: fixedDirection)
            chunks[index] = chunk
            return chunk
        }

        // MARK: Interpolated ephemeris

        /// The geocentric apparent position of `body` (J2000 equatorial, AU) interpolated between nodes.
        private func geocentricPosition(of body: SolarSystemBody, at time: Double) -> Vector3 {
            let scaled = time / nodeSpacing
            let base = Int(scaled.rounded(.down))
            let u = scaled - Double(base)
            let weights = (-u * (u - 1) * (u - 2) / 6,
                           (u + 1) * (u - 1) * (u - 2) / 2,
                           -(u + 1) * u * (u - 2) / 2,
                           (u + 1) * u * (u - 1) / 6)
            return node(base - 1, of: body) * weights.0 + node(base, of: body) * weights.1
                + node(base + 1, of: body) * weights.2 + node(base + 2, of: body) * weights.3
        }

        private func node(_ index: Int, of body: SolarSystemBody) -> Vector3 {
            if let cached = nodes[index] { return cached }
            let date = Date(timeIntervalSinceReferenceDate: Double(index) * nodeSpacing)
            let position = Ephemeris.geocentricJ2000(of: body, at: JulianDate(date: date))
            nodes[index] = position
            return position
        }
    }
}
