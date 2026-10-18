import Foundation

/// The frames shared by every target that is followed for one observer: one `SkyFrame` per six hours, from
/// which the Earth's rotation carries a target across the sky.
///
/// It is what `RiseSetCalculator.Sampler` keeps privately, held apart so that a batch of targets builds each
/// frame once. Not thread safe.
final class HorizonSkyFrames {
    /// Everything that is fixed while the Earth turns, for one six-hour stretch.
    final class Chunk {
        let referenceTime: Double
        /// Local apparent sidereal time at `referenceTime`, in degrees.
        let referenceSiderealAngle: Double
        /// Rotation from the Earth-fixed equatorial frame (x towards the meridian) to ENU.
        let localToHorizontal: Matrix3
        /// J2000 mean equatorial to true equatorial of date.
        let precessionNutation: Matrix3
        /// The observer's geocentric position in the Earth-fixed equatorial frame (AU).
        let observerEarthFixed: Vector3
        /// The frame of the stretch's middle, for the apparent places of fixed targets.
        let frame: SkyFrame

        init(referenceTime: Double, referenceSiderealAngle: Double, localToHorizontal: Matrix3,
             precessionNutation: Matrix3, observerEarthFixed: Vector3, frame: SkyFrame) {
            self.referenceTime = referenceTime
            self.referenceSiderealAngle = referenceSiderealAngle
            self.localToHorizontal = localToHorizontal
            self.precessionNutation = precessionNutation
            self.observerEarthFixed = observerEarthFixed
            self.frame = frame
        }
    }

    static let chunkLength: Double = 6 * 3600
    /// Times further than this (about 300 000 years) from the reference date are not evaluated.
    static let maximumTime: Double = 1e13
    /// The rate at which local sidereal time advances, in degrees per second of UT.
    static let siderealDegreesPerSecond = 360.985_647_366_29 / JulianDate.secondsPerDay

    let observer: Observer
    private var chunks = [Int: Chunk]()
    private var lastIndex = 0
    private var lastChunk: Chunk?

    init(observer: Observer) {
        self.observer = observer
    }

    /// The chunk that contains `time` (seconds since the Foundation reference date).
    func chunk(containing time: Double) -> Chunk {
        let index = Int((time / Self.chunkLength).rounded(.down))
        if let last = lastChunk, lastIndex == index { return last }
        if let cached = chunks[index] {
            lastChunk = cached
            lastIndex = index
            return cached
        }
        let referenceTime = (Double(index) + 0.5) * Self.chunkLength
        let frame = SkyFrame(date: Date(timeIntervalSinceReferenceDate: referenceTime), observer: observer)
        let siderealAngle = frame.localApparentSiderealTime
        let toEarthFixed = Matrix3.frameRotationZ(AstroMath.radians(siderealAngle))
        let chunk = Chunk(referenceTime: referenceTime,
                          referenceSiderealAngle: siderealAngle,
                          localToHorizontal: frame.equatorialOfDateToHorizontal * toEarthFixed.transposed,
                          precessionNutation: frame.precessionNutationMatrix,
                          observerEarthFixed: toEarthFixed * frame.observerPositionOfDate,
                          frame: frame)
        chunks[index] = chunk
        lastChunk = chunk
        lastIndex = index
        return chunk
    }
}

/// Where one target is in the sky at a time: `evaluate` computes the geometric altitude, the azimuth and, for
/// the Moon, the limb allowance, and leaves them in the properties.
///
/// The altitude and azimuth are not a number for a time that is not finite. The base class is a target with
/// no position (always not a number); the subclasses follow a fixed object, a solar-system body or a function.
/// Not thread safe.
class HorizonSkyTrack {
    /// Geometric topocentric altitude of the target's centre at the last `evaluate`, in degrees.
    fileprivate(set) var altitude = Double.nan
    /// Azimuth in degrees, [0, 360), at the last `evaluate`; 0 when it was not asked for.
    fileprivate(set) var azimuth = Double.nan
    /// Degrees added to the centre altitude to reach the limb that defines a rise or set (the Moon); else 0.
    fileprivate(set) var limbAllowance = 0.0

    /// Computes the position at `time` (seconds since the Foundation reference date); `wantsAzimuth` asks for
    /// the azimuth too.
    func evaluate(time: Double, wantsAzimuth: Bool) {
        invalidate()
    }

    /// Leaves the altitude and, if wanted, the azimuth of the ENU direction (east, north, up) in the properties.
    fileprivate final func store(east: Double, north: Double, up: Double, wantsAzimuth: Bool) {
        altitude = AstroMath.atan2Deg(up, (east * east + north * north).squareRoot())
        azimuth = wantsAzimuth ? AstroMath.normalizeDegrees(AstroMath.atan2Deg(east, north)) : 0
    }

    /// Marks the properties as not computed.
    fileprivate final func invalidate() {
        altitude = .nan
        azimuth = .nan
        limbAllowance = 0
    }
}

/// A fixed object (a star or deep-sky object) given by its J2000 place and optional proper motion.
final class HorizonFixedTrack: HorizonSkyTrack {
    private let frames: HorizonSkyFrames
    private let position: EquatorialCoordinate
    private let properMotion: ProperMotion?
    private var directionChunk: HorizonSkyFrames.Chunk?
    private var direction = Vector3.zero

    init(frames: HorizonSkyFrames, position: EquatorialCoordinate, properMotion: ProperMotion?) {
        self.frames = frames
        self.position = position
        self.properMotion = properMotion
    }

    override func evaluate(time: Double, wantsAzimuth: Bool) {
        guard time.isFinite, abs(time) < HorizonSkyFrames.maximumTime else {
            invalidate()
            return
        }
        let chunk = frames.chunk(containing: time)
        if directionChunk !== chunk {
            direction = chunk.frame.apparentPlace(j2000: position, properMotion: properMotion).unitVector
            directionChunk = chunk
        }
        let siderealAngle = chunk.referenceSiderealAngle
            + HorizonSkyFrames.siderealDegreesPerSecond * (time - chunk.referenceTime)
        let angle = AstroMath.radians(siderealAngle)
        let c = cos(angle)
        let s = sin(angle)
        let rotatedX = c * direction.x + s * direction.y
        let rotatedY = -s * direction.x + c * direction.y
        let rotatedZ = direction.z
        let l0 = chunk.localToHorizontal.r0
        let l1 = chunk.localToHorizontal.r1
        let l2 = chunk.localToHorizontal.r2
        limbAllowance = 0
        store(east: l0.x * rotatedX + l0.y * rotatedY + l0.z * rotatedZ,
              north: l1.x * rotatedX + l1.y * rotatedY + l1.z * rotatedZ,
              up: l2.x * rotatedX + l2.y * rotatedY + l2.z * rotatedZ,
              wantsAzimuth: wantsAzimuth)
    }
}

/// The Sun, the Moon or a planet, from its geocentric apparent position interpolated between ephemeris nodes
/// (hourly for the Moon, three-hourly for the others, cubic Lagrange interpolation as in
/// `RiseSetCalculator.Sampler`).
final class HorizonBodyTrack: HorizonSkyTrack {
    private let frames: HorizonSkyFrames
    private let body: SolarSystemBody
    private let nodeSpacing: Double
    private var nodeCache = [Int: Vector3]()
    private var windowBase = 0
    private var cachedWindow: [Vector3]?

    init(frames: HorizonSkyFrames, body: SolarSystemBody) {
        self.frames = frames
        self.body = body
        nodeSpacing = body != .moon ? 3 * 3600 : 3600
    }

    override func evaluate(time: Double, wantsAzimuth: Bool) {
        guard time.isFinite, abs(time) < HorizonSkyFrames.maximumTime else {
            invalidate()
            return
        }
        let chunk = frames.chunk(containing: time)
        let siderealAngle = chunk.referenceSiderealAngle
            + HorizonSkyFrames.siderealDegreesPerSecond * (time - chunk.referenceTime)
        let angle = AstroMath.radians(siderealAngle)
        let c = cos(angle)
        let s = sin(angle)

        let nodes = window(around: time)
        let u = time / nodeSpacing - Double(windowBase)
        let w0 = -u * (u - 1) * (u - 2) / 6
        let w1 = (u + 1) * (u - 1) * (u - 2) / 2
        let w2 = -(u + 1) * u * (u - 2) / 2
        let w3 = (u + 1) * u * (u - 1) / 6
        let n0 = nodes[0]
        let n1 = nodes[1]
        let n2 = nodes[2]
        let n3 = nodes[3]
        let geocentricX = n0.x * w0 + n1.x * w1 + n2.x * w2 + n3.x * w3
        let geocentricY = n0.y * w0 + n1.y * w1 + n2.y * w2 + n3.y * w3
        let geocentricZ = n0.z * w0 + n1.z * w1 + n2.z * w2 + n3.z * w3

        let p0 = chunk.precessionNutation.r0
        let p1 = chunk.precessionNutation.r1
        let p2 = chunk.precessionNutation.r2
        let equatorialX = p0.x * geocentricX + p0.y * geocentricY + p0.z * geocentricZ
        let equatorialY = p1.x * geocentricX + p1.y * geocentricY + p1.z * geocentricZ
        let equatorialZ = p2.x * geocentricX + p2.y * geocentricY + p2.z * geocentricZ

        let observerFixed = chunk.observerEarthFixed
        let relativeX = c * equatorialX + s * equatorialY - observerFixed.x
        let relativeY = -s * equatorialX + c * equatorialY - observerFixed.y
        let relativeZ = equatorialZ - observerFixed.z

        let l0 = chunk.localToHorizontal.r0
        let l1 = chunk.localToHorizontal.r1
        let l2 = chunk.localToHorizontal.r2
        let x = l0.x * relativeX + l0.y * relativeY + l0.z * relativeZ
        let y = l1.x * relativeX + l1.y * relativeY + l1.z * relativeZ
        let z = l2.x * relativeX + l2.y * relativeY + l2.z * relativeZ
        limbAllowance = 0
        store(east: x, north: y, up: z, wantsAzimuth: wantsAzimuth)
        if body == .moon {
            let distanceKilometers = (x * x + y * y + z * z).squareRoot() * SkyFrame.kilometersPerAU
            limbAllowance = AstroMath.asinDeg(body.meanRadiusKilometers / distanceKilometers)
        }
    }

    /// The four nodes `base - 1 ... base + 2` around `time`; the index `base` is left in `windowBase`.
    private func window(around time: Double) -> [Vector3] {
        let base = Int((time / nodeSpacing).rounded(.down))
        if let cached = cachedWindow, windowBase == base { return cached }
        let fresh = [node(base - 1), node(base), node(base + 1), node(base + 2)]
        cachedWindow = fresh
        windowBase = base
        return fresh
    }

    private func node(_ index: Int) -> Vector3 {
        if let cached = nodeCache[index] { return cached }
        let date = Date(timeIntervalSinceReferenceDate: Double(index) * nodeSpacing)
        let position = Ephemeris.geocentricJ2000(of: body, at: JulianDate(date: date))
        nodeCache[index] = position
        return position
    }
}

/// A target given by a function of time that returns its geometric (or refracted) horizontal coordinates.
final class HorizonFunctionTrack: HorizonSkyTrack {
    private let position: (Date) -> HorizontalCoordinate

    init(position: @escaping (Date) -> HorizontalCoordinate) {
        self.position = position
    }

    override func evaluate(time: Double, wantsAzimuth: Bool) {
        guard time.isFinite else {
            invalidate()
            return
        }
        let horizontal = position(Date(timeIntervalSinceReferenceDate: time))
        limbAllowance = 0
        altitude = horizontal.altitude
        azimuth = horizontal.azimuth
    }
}
