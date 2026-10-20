import Foundation

/// Settings of an `AlpacaDriver`.
///
/// Values are clamped to their ranges when the configuration is created.
public struct AlpacaConfiguration: Hashable, Sendable {
    /// The telescope's device number from the management API (0 or more).
    public let deviceNumber: Int
    /// The `ClientID` sent with every request (1 or more).
    public let clientID: Int
    /// How long one HTTP exchange may take (1 to 60 s).
    public let exchangeTimeoutSeconds: Double
    /// Whether a positive `moveaxis` rate on the primary axis moves east (increasing right ascension or azimuth).
    /// ASCOM leaves the sign of `moveaxis` to the driver; set false for a mount that turns the other way.
    public let primaryPositiveIsEast: Bool
    /// Whether a positive `moveaxis` rate on the secondary axis moves north (increasing declination or altitude).
    public let secondaryPositiveIsNorth: Bool

    /// Device 0, client 1, 10 s timeout, positive rates move east and north.
    public static let standard = AlpacaConfiguration()

    /// Creates a configuration; out-of-range values are clamped.
    public init(deviceNumber: Int = 0, clientID: Int = 1, exchangeTimeoutSeconds: Double = 10.0, primaryPositiveIsEast: Bool = true,
                secondaryPositiveIsNorth: Bool = true) {
        self.deviceNumber = max(deviceNumber, 0)
        self.clientID = max(clientID, 1)
        self.exchangeTimeoutSeconds = exchangeTimeoutSeconds.isNaN ? 10.0 : min(max(exchangeTimeoutSeconds, 1.0), 60.0)
        self.primaryPositiveIsEast = primaryPositiveIsEast
        self.secondaryPositiveIsNorth = secondaryPositiveIsNorth
    }
}

/// Drives an ASCOM Alpaca telescope over an `AlpacaTransport`. See `AlpacaRequestBuilder` for the requests used.
///
/// Coordinates follow the mount's `equatorialsystem`: topocentric (JNow of the local sky, `MountEpoch.apparentOfDate`)
/// or J2000; other systems are refused at `connect`. Slews are asynchronous (`slewtocoordinatesasync`), completion is
/// read from `slewing`. Short nudges at the guide rate use `pulseguide`, whose direction is standardised and whose
/// duration the mount enforces; faster nudges use `moveaxis`, whose sign the mount defines (`AlpacaConfiguration`).
public final class AlpacaDriver: MountDriver {
    private static let topocentricSystem = 1
    private static let j2000System = 2

    private let transport: AlpacaTransport
    private let requests: AlpacaRequestBuilder
    private var resolvedEpoch: MountEpoch = .apparentOfDate
    private var canSlewAsync = true
    private var canSync = true
    private var canPulseGuide = false
    private var canSetTracking = true
    private var canMovePrimary = false
    private var canMoveSecondary = false
    private var movingAxes: [AlpacaAxis] = []

    /// The settings in use.
    public let configuration: AlpacaConfiguration

    public var kind: MountProtocol { .alpaca }

    public var epoch: MountEpoch { resolvedEpoch }

    public init(transport: AlpacaTransport, configuration: AlpacaConfiguration = .standard) {
        self.transport = transport
        self.configuration = configuration
        requests = AlpacaRequestBuilder(deviceNumber: configuration.deviceNumber, clientID: configuration.clientID)
    }

    public func connect() throws -> MountCapabilities {
        _ = try perform(requests.setConnected(true))
        if !(try perform(requests.connected()).booleanValue()) { throw MountError.notConnected }
        let system: Int
        do {
            system = try perform(requests.equatorialSystem()).integerValue()
        } catch MountError.notSupported {
            system = AlpacaDriver.topocentricSystem
        }
        switch system {
        case AlpacaDriver.topocentricSystem: resolvedEpoch = .apparentOfDate
        case AlpacaDriver.j2000System: resolvedEpoch = .j2000
        default: throw MountError.unsupportedCoordinateSystem(code: system)
        }
        canSlewAsync = try probe(requests.canSlewAsync())
        canSync = try probe(requests.canSync())
        canPulseGuide = try probe(requests.canPulseGuide())
        canSetTracking = try probe(requests.canSetTracking())
        canMovePrimary = try probe(requests.canMoveAxis(.primary))
        canMoveSecondary = try probe(requests.canMoveAxis(.secondary))
        var name = ""
        do {
            name = MountText.sanitized(try perform(requests.name()).textValue(), limit: 60)
        } catch MountError.notSupported {
            name = ""
        }
        _ = try readPosition()
        return MountCapabilities(
            kind: .alpaca, name: name.isEmpty ? "Alpaca telescope" : name, firmware: nil, canSlew: canSlewAsync, canSync: canSync,
            canAbort: true, canSetTracking: canSetTracking, canNudge: canPulseGuide || (canMovePrimary && canMoveSecondary),
            canSetSiteAndTime: true, gotoNeedsAlignment: false, isAligned: nil)
    }

    public func disconnect() {
        movingAxes.removeAll()
        // The session ends either way, so a failure to say goodbye is not reported.
        _ = try? perform(requests.setConnected(false))
    }

    public func readPosition() throws -> EquatorialCoordinate {
        let hours = try perform(requests.rightAscension()).doubleValue()
        let declination = try perform(requests.declination()).doubleValue()
        if !(hours >= 0 && hours <= 24) || !(declination >= -90 && declination <= 90) {
            throw MountError.malformedReply(detail: "position out of range")
        }
        return EquatorialCoordinate(rightAscensionHours: hours, declination: declination)
    }

    public func readSlewing() throws -> Bool { try perform(requests.slewing()).booleanValue() }

    public func readTracking() throws -> Bool? { try perform(requests.tracking()).booleanValue() }

    public func readAligned() throws -> Bool? { nil }

    public func slew(to target: EquatorialCoordinate) throws {
        if !canSlewAsync { throw MountError.notSupported(feature: .slew) }
        let rightAscensionHours = try hours(target)
        if try isParked() { throw MountError.parked }
        _ = try perform(requests.slewToCoordinatesAsync(rightAscensionHours: rightAscensionHours, declination: target.declination))
    }

    public func sync(to target: EquatorialCoordinate) throws {
        if !canSync { throw MountError.notSupported(feature: .sync) }
        _ = try perform(requests.syncToCoordinates(rightAscensionHours: try hours(target), declination: target.declination))
    }

    public func abort() throws {
        _ = try perform(requests.abortSlew())
    }

    public func setTracking(_ enabled: Bool) throws {
        if !canSetTracking { throw MountError.notSupported(feature: .tracking) }
        _ = try perform(requests.setTracking(enabled))
    }

    public func startNudge(direction: MountNudgeDirection, rate: MountNudgeRate, durationSeconds: Double) throws {
        let nudgeAxis = axis(direction)
        let canMove = nudgeAxis == .primary ? canMovePrimary : canMoveSecondary
        if canPulseGuide && (rate == .guide || !canMove) {
            let milliseconds = durationSeconds.isFinite ? min(max(Int(min(max(durationSeconds * 1000, 0), 1.0e9).rounded(.up)), 1), 30_000) : 1
            _ = try perform(requests.pulseGuide(direction: guideDirection(direction), durationMilliseconds: milliseconds))
            return
        }
        if !canMove { throw MountError.notSupported(feature: .nudge) }
        let magnitude = rate.degreesPerSecond
        let positive: Bool
        switch direction {
        case .east: positive = configuration.primaryPositiveIsEast
        case .west: positive = !configuration.primaryPositiveIsEast
        case .north: positive = configuration.secondaryPositiveIsNorth
        case .south: positive = !configuration.secondaryPositiveIsNorth
        }
        // The mount may have executed the request although its reply was lost, so the axis counts as moving from the moment
        // the request is sent and `stopNudge` always sends rate 0 for it. Only a refusal by the mount (not a failure of the
        // link) says for sure that nothing moves.
        let wasMoving = movingAxes.contains(nudgeAxis)
        if !wasMoving { movingAxes.append(nudgeAxis) }
        do {
            _ = try perform(requests.moveAxis(nudgeAxis, degreesPerSecond: positive ? magnitude : -magnitude))
        } catch let error as MountError {
            if !wasMoving && !error.isCommunicationFailure { movingAxes.removeAll { $0 == nudgeAxis } }
            throw error
        }
    }

    public func stopNudge(direction: MountNudgeDirection) throws {
        let nudgeAxis = axis(direction)
        if !movingAxes.contains(nudgeAxis) { return }
        _ = try perform(requests.moveAxis(nudgeAxis, degreesPerSecond: 0.0))
        movingAxes.removeAll { $0 == nudgeAxis }
    }

    public func setSiteAndTime(location: GeographicLocation, date: Date) throws {
        let dateRequest = try requests.setUTCDate(date)
        _ = try perform(requests.setSiteLatitude(location.latitude))
        _ = try perform(requests.setSiteLongitude(location.longitude))
        // ASCOM limits SiteElevation to -300...10000 m, narrower than the engine's -1000...12000 m (the Dead Sea is at about
        // -430 m), and a device answers InvalidValue to anything outside.
        _ = try perform(requests.setSiteElevation(min(max(location.elevation, -300.0), 10_000.0)))
        _ = try perform(dateRequest)
    }

    // MARK: Exchanges

    private func perform(_ request: AlpacaHTTPRequest) throws -> AlpacaReply {
        let response: AlpacaHTTPResponse
        do {
            response = try transport.send(request, timeoutSeconds: configuration.exchangeTimeoutSeconds)
        } catch let error as MountError {
            throw error
        } catch {
            throw MountError.transport(detail: MountText.sanitized(error.localizedDescription, limit: 120))
        }
        return try AlpacaResponseParser.parse(response, for: request)
    }

    /// A capability flag; a device that does not implement the property counts as "no".
    private func probe(_ request: AlpacaHTTPRequest) throws -> Bool {
        do {
            return try perform(request).booleanValue()
        } catch MountError.notSupported {
            return false
        }
    }

    private func isParked() throws -> Bool {
        do {
            return try perform(requests.atPark()).booleanValue()
        } catch MountError.notSupported {
            return false
        }
    }

    private func hours(_ target: EquatorialCoordinate) throws -> Double {
        if !target.rightAscension.isFinite || !target.declination.isFinite {
            throw MountError.invalidInput(detail: "the target coordinates are not numbers")
        }
        return target.rightAscension / 15.0
    }

    private func axis(_ direction: MountNudgeDirection) -> AlpacaAxis {
        switch direction {
        case .east, .west: .primary
        case .north, .south: .secondary
        }
    }

    private func guideDirection(_ direction: MountNudgeDirection) -> AlpacaGuideDirection {
        switch direction {
        case .north: .north
        case .south: .south
        case .east: .east
        case .west: .west
        }
    }
}
