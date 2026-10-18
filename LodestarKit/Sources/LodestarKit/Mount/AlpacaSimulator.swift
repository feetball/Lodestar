import Foundation

/// A defect the `AlpacaSimulator` can be told to produce in its next reply to a method.
public enum AlpacaFault: Hashable, Sendable {
    /// The server answers with the HTTP status `statusCode` and `body` instead.
    case status(statusCode: Int, body: String)
    /// The reply is a normal 200 whose body is `text` (garbled JSON, wrong types …).
    case body(text: String)
    /// The device reports an error: `ErrorNumber` and `ErrorMessage`.
    case error(number: Int, message: String)
    /// The reply echoes another `ClientTransactionID`.
    case wrongTransactionID
    /// The server does not answer within the timeout.
    case timeout
}

/// An in-memory Alpaca server with one telescope behind an `AlpacaTransport`, for tests and UI previews. It validates
/// method names, parameters and `PUT` vs `GET` like a real device, answers in the documented JSON shapes (including the
/// `ErrorNumber` conventions), serves the management API and drives a `MountSimulatorModel`.
public final class AlpacaSimulator: AlpacaTransport {
    private static let writeMethods: Set<String> = [
        "connected", "slewtocoordinatesasync", "synctocoordinates", "abortslew", "tracking", "pulseguide", "moveaxis",
        "sitelatitude", "sitelongitude", "siteelevation", "utcdate",
    ]

    private let clock: ManualMountClock
    /// The moving mount behind the protocol.
    public let mount: MountSimulatorModel
    /// The `equatorialsystem` the telescope reports: 1 topocentric (apparent), 2 J2000.
    public let equatorialSystem: Int
    /// Whether `cansync` is true.
    public let canSync: Bool
    /// Whether `canpulseguide` is true.
    public let canPulseGuide: Bool
    /// Whether `canmoveaxis` is true for the primary and secondary axes.
    public let canMoveAxis: Bool
    /// The telescope's `name`.
    public let deviceName: String
    /// The device number the telescope is served as.
    public let deviceNumber: Int
    /// Simulated round-trip time added to the clock for every request.
    public let latencySeconds: Double

    /// Whether the client has connected (`PUT connected`).
    public private(set) var isConnected = false
    /// If true, `slewtocoordinatesasync` fails with `InvalidOperation` ("Tracking is off") while tracking is off.
    public var slewRequiresTracking = true

    private var siteLog: [String] = []
    private var log: [String] = []
    private var faults: [(String, AlpacaFault)] = []
    private var serverTransaction = 0
    private var movingAxes: [Double] = [0.0, 0.0]

    public init(clock: ManualMountClock, mount: MountSimulatorModel, equatorialSystem: Int = 1, canSync: Bool = true,
                canPulseGuide: Bool = true, canMoveAxis: Bool = true, deviceName: String = "Simulated Alpaca Mount",
                deviceNumber: Int = 0, latencySeconds: Double = 0.05) {
        self.clock = clock
        self.mount = mount
        self.equatorialSystem = equatorialSystem
        self.canSync = canSync
        self.canPulseGuide = canPulseGuide
        self.canMoveAxis = canMoveAxis
        self.deviceName = deviceName
        self.deviceNumber = deviceNumber
        self.latencySeconds = latencySeconds
    }

    /// The site values and clock received by `PUT`, as `name=value` texts in order.
    public var siteValues: [String] { siteLog }

    /// The methods received, in order (`rightascension`, `slewtocoordinatesasync` …).
    public var methodLog: [String] { log }

    /// Arranges for the next `times` requests of `method` (lower case, e.g. `rightascension`) to suffer `fault`.
    public func inject(_ method: String, _ fault: AlpacaFault, times: Int = 1) {
        for _ in 0 ..< max(times, 0) { faults.append((method, fault)) }
    }

    public func send(_ request: AlpacaHTTPRequest, timeoutSeconds: Double) throws -> AlpacaHTTPResponse {
        clock.advance(seconds: latencySeconds)
        let segments = request.path.split(separator: "/").map(String.init)
        let method = segments.last ?? ""
        log.append(method)
        var fault: AlpacaFault?
        if let index = faults.firstIndex(where: { $0.0 == method }) { fault = faults.remove(at: index).1 }
        if case .timeout? = fault {
            clock.advance(seconds: timeoutSeconds)
            throw MountError.timeout(operation: "simulated")
        }
        if case let .status(statusCode, body)? = fault { return AlpacaHTTPResponse(statusCode: statusCode, body: body) }
        if case let .body(text)? = fault { return AlpacaHTTPResponse(statusCode: 200, body: text) }
        let fields = request.method == .get ? request.query : request.form
        var echoed = request.clientTransactionID
        if case .wrongTransactionID? = fault { echoed += 1000 }
        serverTransaction += 1
        if case let .error(number, message)? = fault { return json(nil, echoed, number, message) }

        if segments.first == "management" { return management(method, echoed) }
        if segments.count != 5 || segments[0] != "api" || segments[1] != "v1" || segments[2] != "telescope" {
            return AlpacaHTTPResponse(statusCode: 400, body: "Unknown path")
        }
        if segments[3] != String(deviceNumber) { return AlpacaHTTPResponse(statusCode: 400, body: "Invalid device number") }
        return telescope(method, request.method, fields, echoed)
    }

    private func management(_ method: String, _ echoed: Int) -> AlpacaHTTPResponse {
        switch method {
        case "apiversions":
            return json("[1]", echoed)
        case "description":
            return json(
                "{\"ServerName\":\"Simulated Alpaca Server\",\"Manufacturer\":\"Lodestar\","
                    + "\"ManufacturerVersion\":\"1.0\",\"Location\":\"Test bench\"}", echoed)
        case "configureddevices":
            return json(
                "[{\"DeviceName\":\"\(escape(deviceName))\",\"DeviceType\":\"Telescope\",\"DeviceNumber\":\(deviceNumber),"
                    + "\"UniqueID\":\"6f0c1c9e-1111-4222-8333-444455556666\"},"
                    + "{\"DeviceName\":\"Camera\",\"DeviceType\":\"Camera\",\"DeviceNumber\":0,\"UniqueID\":\"camera-0\"}]", echoed)
        default:
            return AlpacaHTTPResponse(statusCode: 400, body: "Unknown management method")
        }
    }

    private func readValue(_ method: String) -> String? {
        switch method {
        case "connected": return isConnected ? "true" : "false"
        case "name": return "\"\(escape(deviceName))\""
        case "canslewasync", "cansettracking": return "true"
        case "cansync": return canSync ? "true" : "false"
        case "canpulseguide": return canPulseGuide ? "true" : "false"
        case "equatorialsystem": return String(equatorialSystem)
        case "rightascension": return number(mount.position.rightAscension / 15.0)
        case "declination": return number(mount.position.declination)
        case "slewing": return (mount.isSlewing || movingAxes[0] != 0.0 || movingAxes[1] != 0.0) ? "true" : "false"
        case "tracking": return mount.isTracking ? "true" : "false"
        case "atpark": return mount.isParked ? "true" : "false"
        case "trackingrates": return "[0,1,2]"
        default: return nil
        }
    }

    private func telescope(_ method: String, _ verb: AlpacaMethod, _ fields: [AlpacaField], _ echoed: Int) -> AlpacaHTTPResponse {
        if method == "canmoveaxis" {
            if verb != .get { return AlpacaHTTPResponse(statusCode: 400, body: "Method not allowed") }
            guard let axis = value(fields, "Axis").flatMap({ Int($0) }) else {
                return AlpacaHTTPResponse(statusCode: 400, body: "Axis missing")
            }
            return json((canMoveAxis && axis >= 0 && axis <= 1) ? "true" : "false", echoed)
        }
        let read = readValue(method)
        if let read, verb == .get { return json(read, echoed) }
        if !AlpacaSimulator.writeMethods.contains(method) || verb != .put {
            if read != nil || AlpacaSimulator.writeMethods.contains(method) {
                return AlpacaHTTPResponse(statusCode: 400, body: "Method not allowed")
            }
            return AlpacaHTTPResponse(statusCode: 400, body: "Unknown method \(method)")
        }
        if method != "connected" && !isConnected { return json(nil, echoed, 1031, "Not connected") }
        return write(method, fields, echoed)
    }

    private func value(_ fields: [AlpacaField], _ name: String) -> String? {
        let wanted = MountText.asciiLowercased(name)
        return fields.first { MountText.asciiLowercased($0.name) == wanted }?.value
    }

    private func flag(_ fields: [AlpacaField], _ name: String) -> Bool? {
        guard let text = value(fields, name).map({ MountText.asciiLowercased($0) }) else { return nil }
        if text == "true" { return true }
        if text == "false" { return false }
        return nil
    }

    private func write(_ method: String, _ fields: [AlpacaField], _ echoed: Int) -> AlpacaHTTPResponse {
        switch method {
        case "connected":
            guard let connected = flag(fields, "Connected") else { return invalid(echoed, "Connected") }
            isConnected = connected
        case "slewtocoordinatesasync", "synctocoordinates":
            guard let hours = value(fields, "RightAscension").flatMap({ Double($0) }),
                  let declination = value(fields, "Declination").flatMap({ Double($0) }),
                  hours >= 0, hours < 24, declination >= -90, declination <= 90 else {
                return json(nil, echoed, 1025, "Invalid coordinates")
            }
            if mount.isParked { return json(nil, echoed, 1032, "The mount is parked") }
            let target = EquatorialCoordinate(rightAscensionHours: hours, declination: declination)
            if method == "synctocoordinates" {
                if !canSync { return json(nil, echoed, 1024, "SyncToCoordinates is not implemented") }
                mount.sync(to: target)
            } else {
                if slewRequiresTracking && !mount.isTracking { return json(nil, echoed, 1035, "Tracking is off") }
                mount.beginSlew(to: target)
            }
        case "abortslew":
            movingAxes = [0.0, 0.0]
            mount.stop()
        case "tracking":
            guard let tracking = flag(fields, "Tracking") else { return invalid(echoed, "Tracking") }
            mount.isTracking = tracking
        case "pulseguide":
            if !canPulseGuide { return json(nil, echoed, 1024, "PulseGuide is not implemented") }
            guard let direction = value(fields, "Direction").flatMap({ Int($0) }), direction >= 0, direction <= 3,
                  let milliseconds = value(fields, "Duration").flatMap({ Int($0) }), milliseconds > 0 else {
                return invalid(echoed, "Direction")
            }
            let degrees = MountNudgeRate.guide.degreesPerSecond * Double(milliseconds) / 1000.0
            switch direction {
            case 0: mount.displace(rightAscensionDegrees: 0.0, declinationDegrees: degrees)
            case 1: mount.displace(rightAscensionDegrees: 0.0, declinationDegrees: -degrees)
            case 2: mount.displace(rightAscensionDegrees: degrees, declinationDegrees: 0.0)
            default: mount.displace(rightAscensionDegrees: -degrees, declinationDegrees: 0.0)
            }
        case "moveaxis":
            if !canMoveAxis { return json(nil, echoed, 1024, "MoveAxis is not implemented") }
            guard let axis = value(fields, "Axis").flatMap({ Int($0) }), axis >= 0, axis <= 1,
                  let rate = value(fields, "Rate").flatMap({ Double($0) }) else {
                return invalid(echoed, "Axis")
            }
            movingAxes[axis] = rate
            mount.setNudgeRates(rightAscensionDegreesPerSecond: movingAxes[0], declinationDegreesPerSecond: movingAxes[1])
        case "sitelatitude": siteLog.append("SiteLatitude=\(value(fields, "SiteLatitude") ?? "")")
        case "sitelongitude": siteLog.append("SiteLongitude=\(value(fields, "SiteLongitude") ?? "")")
        case "siteelevation": siteLog.append("SiteElevation=\(value(fields, "SiteElevation") ?? "")")
        case "utcdate": siteLog.append("UTCDate=\(value(fields, "UTCDate") ?? "")")
        default: return AlpacaHTTPResponse(statusCode: 400, body: "Unknown method")
        }
        return json(nil, echoed)
    }

    private func invalid(_ echoed: Int, _ parameter: String) -> AlpacaHTTPResponse {
        json(nil, echoed, 1025, "Invalid value for \(parameter)")
    }

    private func number(_ value: Double) -> String { String(format: "%.9f", value) }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func json(_ value: String?, _ echoed: Int, _ errorNumber: Int = 0, _ errorMessage: String = "") -> AlpacaHTTPResponse {
        let valueText = value.map { "\"Value\":\($0)," } ?? ""
        return AlpacaHTTPResponse(
            statusCode: 200,
            body: "{\(valueText)\"ClientTransactionID\":\(echoed),\"ServerTransactionID\":\(serverTransaction),"
                + "\"ErrorNumber\":\(errorNumber),\"ErrorMessage\":\"\(escape(errorMessage))\"}")
    }
}
