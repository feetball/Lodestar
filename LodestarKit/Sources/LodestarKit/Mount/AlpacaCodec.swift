import Foundation

/// The HTTP method of an Alpaca request: `GET` reads (parameters in the query), `PUT` writes (parameters in the body).
public enum AlpacaMethod: String, CaseIterable, Hashable, Sendable {
    /// Parameters travel in the URL query string.
    case get = "GET"
    /// Parameters travel in an `application/x-www-form-urlencoded` body.
    case put = "PUT"
}

/// One request parameter: a name and its text value (encoded when the request is turned into a URL or body).
public struct AlpacaField: Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// An Alpaca request as a value. The app's HTTP client sends `method` to `http://host:port` + `target` with `body` and
/// `contentType` (for `PUT`) and hands the status code and body text back as an `AlpacaHTTPResponse`.
public struct AlpacaHTTPRequest: Hashable, Sendable {
    /// `GET` or `PUT`.
    public let method: AlpacaMethod
    /// The path, for example `/api/v1/telescope/0/rightascension`.
    public let path: String
    /// Query parameters (`GET`), including `ClientID` and `ClientTransactionID`.
    public let query: [AlpacaField]
    /// Form parameters (`PUT`), including `ClientID` and `ClientTransactionID`.
    public let form: [AlpacaField]
    /// The `ClientTransactionID` sent, which the reply must echo.
    public let clientTransactionID: Int

    public init(method: AlpacaMethod, path: String, query: [AlpacaField], form: [AlpacaField], clientTransactionID: Int) {
        self.method = method
        self.path = path
        self.query = query
        self.form = form
        self.clientTransactionID = clientTransactionID
    }

    /// The request target: the path, followed by `?` and the encoded query when there is one.
    public var target: String { query.isEmpty ? path : "\(path)?\(AlpacaCodec.encodeFields(query))" }

    /// The encoded form body of a `PUT`; empty for a `GET`.
    public var body: String { AlpacaCodec.encodeFields(form) }

    /// The `Content-Type` header of a `PUT`; nil for a `GET`.
    public var contentType: String? { method == .put ? "application/x-www-form-urlencoded" : nil }
}

/// The status code and body text of an HTTP reply.
public struct AlpacaHTTPResponse: Hashable, Sendable {
    /// The HTTP status code.
    public let statusCode: Int
    /// The body decoded as UTF-8.
    public let body: String

    public init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// The directions of `pulseguide`.
public enum AlpacaGuideDirection: Int, CaseIterable, Hashable, Sendable {
    /// Towards increasing declination.
    case north = 0
    /// Towards decreasing declination.
    case south = 1
    /// Towards increasing right ascension.
    case east = 2
    /// Towards decreasing right ascension.
    case west = 3

    /// The value sent.
    public var code: Int { rawValue }
}

/// The mechanical axes of `moveaxis`.
public enum AlpacaAxis: Int, CaseIterable, Hashable, Sendable {
    /// Right ascension or azimuth.
    case primary = 0
    /// Declination or altitude.
    case secondary = 1
    /// Rotator axis of some mounts.
    case tertiary = 2

    /// The value sent.
    public var code: Int { rawValue }
}

/// The `Value` of a successful reply and the transaction numbers it carried.
public struct AlpacaReply: Hashable, Sendable {
    /// The `ClientTransactionID` the device echoed, if it did.
    public let clientTransactionID: Int?
    /// The `ServerTransactionID` of the device, if it sent one.
    public let serverTransactionID: Int?
    /// The `Value` member, absent for methods that return nothing.
    public let value: MountJSON?

    public init(clientTransactionID: Int?, serverTransactionID: Int?, value: MountJSON?) {
        self.clientTransactionID = clientTransactionID
        self.serverTransactionID = serverTransactionID
        self.value = value
    }

    /// The value as a boolean.
    public func booleanValue() throws -> Bool {
        guard case let .bool(flag)? = value else { throw wrongType("a boolean") }
        return flag
    }

    /// The value as a finite number.
    public func doubleValue() throws -> Double {
        guard case let .number(number)? = value else { throw wrongType("a number") }
        return number
    }

    /// The value as an integer.
    public func integerValue() throws -> Int {
        guard let integer = AlpacaCodec.integer(value) else { throw wrongType("an integer") }
        return integer
    }

    /// The value as text.
    public func textValue() throws -> String {
        guard case let .text(text)? = value else { throw wrongType("text") }
        return text
    }

    /// The value as a list of integers.
    public func integerList() throws -> [Int] {
        guard case let .array(items)? = value else { throw wrongType("a list") }
        if items.count > 64 { throw wrongType("a shorter list") }
        return try items.map { item in
            guard let integer = AlpacaCodec.integer(item) else { throw wrongType("a list of integers") }
            return integer
        }
    }

    private func wrongType(_ expected: String) -> MountError { MountError.malformedReply(detail: "the value is not \(expected)") }
}

/// A device listed by the management API.
public struct AlpacaDevice: Hashable, Sendable {
    /// A short display name.
    public let deviceName: String
    /// The ASCOM device type, for example `Telescope`.
    public let deviceType: String
    /// The number to use in device URLs.
    public let deviceNumber: Int
    /// A unique identifier of the device.
    public let uniqueID: String

    public init(deviceName: String, deviceType: String, deviceNumber: Int, uniqueID: String) {
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.deviceNumber = deviceNumber
        self.uniqueID = uniqueID
    }

    /// True for a telescope (mount).
    public var isTelescope: Bool { MountText.asciiLowercased(deviceType) == "telescope" }
}

/// The server description of the management API.
public struct AlpacaServerDescription: Hashable, Sendable {
    /// The server's name.
    public let serverName: String
    /// The manufacturer.
    public let manufacturer: String
    /// The server's version.
    public let manufacturerVersion: String
    /// Where the server is.
    public let location: String

    public init(serverName: String, manufacturer: String, manufacturerVersion: String, location: String) {
        self.serverName = serverName
        self.manufacturer = manufacturer
        self.manufacturerVersion = manufacturerVersion
        self.location = location
    }
}

/// Where an Alpaca server listens.
public struct AlpacaEndpoint: Hashable, Sendable {
    /// The host name or IP address (an IPv6 address without brackets).
    public let host: String
    /// The TCP port.
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// `http://host:port`, with brackets around an IPv6 address.
    public var baseURL: String { host.contains(":") ? "http://[\(host)]:\(port)" : "http://\(host):\(port)" }

    /// The endpoint, or nil if the host is empty, too long, contains blanks or slashes, or the port is not 1 to 65535.
    public static func validated(host: String, port: Int) -> AlpacaEndpoint? {
        if host.isEmpty || host.unicodeScalars.count > 253 || port < 1 || port > 65_535 { return nil }
        for scalar in host.unicodeScalars {
            if scalar.value <= 0x20 || scalar == "/" || scalar == "?" || scalar == "#" || scalar == "@" || scalar == "["
                || scalar == "]" {
                return nil
            }
        }
        return AlpacaEndpoint(host: host, port: port)
    }
}

/// Alpaca encodings: parameter formatting, URL encoding, error numbers and the discovery datagram. Sources: ASCOM Alpaca
/// Device API v1 and Management API v1 (OpenAPI definitions, MIT licence, https://ascom-standards.org/api/), the
/// `ASCOM.Common.Alpaca.AlpacaErrors` enumeration and the Alpaca discovery reference implementations (ASCOM alpyca).
public enum AlpacaCodec {
    /// Reply texts longer than this are cut when they are put into an error.
    public static let maximumMessageLength = 160

    /// Percent-encodes `text` as UTF-8 (unreserved characters `A–Z a–z 0–9 - . _ ~` stay).
    public static func percentEncode(_ text: String) -> String {
        let digits = Array("0123456789ABCDEF")
        var result = ""
        for byte in Array(text.utf8) {
            let isUnreserved = (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x30 && byte <= 0x39)
                || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
            if isUnreserved {
                result.append(Character(Unicode.Scalar(byte)))
            } else {
                result.append("%")
                result.append(digits[Int(byte >> 4)])
                result.append(digits[Int(byte & 15)])
            }
        }
        return result
    }

    /// `name=value` pairs joined by `&`, names and values percent-encoded.
    public static func encodeFields(_ fields: [AlpacaField]) -> String {
        fields.map { "\(percentEncode($0.name))=\(percentEncode($0.value))" }.joined(separator: "&")
    }

    /// A decimal number with at most 9 fraction digits and no exponent, `.` as the separator (`12.5`, `-0.25`, `3.0`).
    public static func formatNumber(_ value: Double) throws -> String {
        if !value.isFinite || abs(value) > 1.0e9 { throw MountError.invalidInput(detail: "the number is out of range") }
        let scaled = Int((abs(value) * 1.0e9).rounded())
        let whole = scaled / 1_000_000_000
        let fraction = String(scaled % 1_000_000_000)
        var digits = String(repeating: "0", count: 9 - fraction.count) + fraction
        while digits.hasSuffix("0") { digits.removeLast() }
        let sign = value < 0 && scaled > 0 ? "-" : ""
        return "\(sign)\(whole).\(digits.isEmpty ? "0" : digits)"
    }

    /// `True` or `False`.
    public static func formatBoolean(_ value: Bool) -> String { value ? "True" : "False" }

    /// The ISO 8601 UTC form `yyyy-MM-ddTHH:mm:ss.fffZ` that `UTCDate` takes, or nil outside the years 1970 to 9999.
    public static func formatUTCDate(_ date: Date) -> String? {
        guard let f = MountCalendar.fields(for: date) else { return nil }
        let year = String(f.year)
        let paddedYear = String(repeating: "0", count: max(0, 4 - year.count)) + year
        return "\(paddedYear)-\(MountCalendar.twoDigits(f.month))-\(MountCalendar.twoDigits(f.day))T"
            + "\(MountCalendar.twoDigits(f.hour)):\(MountCalendar.twoDigits(f.minute)):\(MountCalendar.twoDigits(f.second))."
            + "\(MountCalendar.threeDigits(f.millisecond))Z"
    }

    /// The JSON number `value` as an `Int` if it is a whole number in range.
    static func integer(_ value: MountJSON?) -> Int? {
        guard case let .number(number)? = value else { return nil }
        if number != number.rounded(.down) || abs(number) > Double(Int32.max) { return nil }
        return Int(number)
    }

    /// The typed error for a non-zero `ErrorNumber`. The reserved numbers of the Alpaca standard (0x400…0x40E, 0x4FF)
    /// map to specific cases; driver-specific numbers (0x500…0xFFF) and `InvalidOperation` are classified by the words
    /// of the message (horizon, limit, park, align, track, slewing) so the user gets an explanation.
    public static func error(number: Int, message: String) -> MountError {
        let text = MountText.sanitized(message, limit: maximumMessageLength)
        switch number {
        case 1024, 1036: return .notSupported(feature: .other)
        case 1025, 1026: return .rejected(detail: text)
        case 1031: return .notConnected
        case 1032: return .parked
        case 1033: return .rejected(detail: text.isEmpty ? "the mount is slaved" : text)
        default: return classify(number, text)
        }
    }

    private static func classify(_ number: Int, _ text: String) -> MountError {
        let lowered = MountText.asciiLowercased(text)
        if lowered.contains("park") { return .parked }
        if lowered.contains("align") { return .notAligned }
        if lowered.contains("horizon") || lowered.contains("below") || lowered.contains("altitude") { return .mountHorizonLimit }
        if lowered.contains("limit") { return .outsideMountLimits }
        if lowered.contains("tracking") { return .notTracking }
        if lowered.contains("slewing") || lowered.contains("in progress") || lowered.contains("moving")
            || lowered.contains("busy") {
            return .busy
        }
        return .remote(code: number, detail: text)
    }
}

/// Builds the requests of the Alpaca Telescope and Management APIs. Every request carries the `ClientID` and an
/// increasing `ClientTransactionID` (1, 2, 3 … wrapping to 1 after 2 147 483 647), which
/// `AlpacaResponseParser.parse` checks in the reply.
public final class AlpacaRequestBuilder {
    /// The device number from the management API (0 for the first telescope).
    public let deviceNumber: Int
    /// The client's identifier, 1 to 2 147 483 647.
    public let clientID: Int
    private var lastTransactionID: Int

    public init(deviceNumber: Int = 0, clientID: Int = 1) {
        self.deviceNumber = deviceNumber
        self.clientID = min(max(clientID, 1), Int(Int32.max))
        lastTransactionID = 0
    }

    init(deviceNumber: Int, clientID: Int, lastTransactionID: Int) {
        self.deviceNumber = deviceNumber
        self.clientID = min(max(clientID, 1), Int(Int32.max))
        self.lastTransactionID = lastTransactionID
    }

    private func nextTransactionID() -> Int {
        lastTransactionID = lastTransactionID >= Int(Int32.max) ? 1 : lastTransactionID + 1
        return lastTransactionID
    }

    private func get(_ path: String, _ parameters: [AlpacaField]) -> AlpacaHTTPRequest {
        let id = nextTransactionID()
        let query = parameters + [AlpacaField(name: "ClientID", value: String(clientID)),
                                  AlpacaField(name: "ClientTransactionID", value: String(id))]
        return AlpacaHTTPRequest(method: .get, path: path, query: query, form: [], clientTransactionID: id)
    }

    private func put(_ path: String, _ parameters: [AlpacaField]) -> AlpacaHTTPRequest {
        let id = nextTransactionID()
        let form = parameters + [AlpacaField(name: "ClientID", value: String(clientID)),
                                 AlpacaField(name: "ClientTransactionID", value: String(id))]
        return AlpacaHTTPRequest(method: .put, path: path, query: [], form: form, clientTransactionID: id)
    }

    private func telescope(_ method: String) -> String { "/api/v1/telescope/\(deviceNumber)/\(method)" }

    // MARK: Management API

    /// `GET /management/apiversions`.
    public func apiVersions() -> AlpacaHTTPRequest { get("/management/apiversions", []) }

    /// `GET /management/v1/description`.
    public func serverDescription() -> AlpacaHTTPRequest { get("/management/v1/description", []) }

    /// `GET /management/v1/configureddevices`.
    public func configuredDevices() -> AlpacaHTTPRequest { get("/management/v1/configureddevices", []) }

    // MARK: Telescope reads

    /// `GET connected`.
    public func connected() -> AlpacaHTTPRequest { get(telescope("connected"), []) }

    /// `GET name`.
    public func name() -> AlpacaHTTPRequest { get(telescope("name"), []) }

    /// `GET canslewasync`.
    public func canSlewAsync() -> AlpacaHTTPRequest { get(telescope("canslewasync"), []) }

    /// `GET cansync`.
    public func canSync() -> AlpacaHTTPRequest { get(telescope("cansync"), []) }

    /// `GET canpulseguide`.
    public func canPulseGuide() -> AlpacaHTTPRequest { get(telescope("canpulseguide"), []) }

    /// `GET cansettracking`.
    public func canSetTracking() -> AlpacaHTTPRequest { get(telescope("cansettracking"), []) }

    /// `GET canmoveaxis?Axis=…`.
    public func canMoveAxis(_ axis: AlpacaAxis) -> AlpacaHTTPRequest {
        get(telescope("canmoveaxis"), [AlpacaField(name: "Axis", value: String(axis.code))])
    }

    /// `GET equatorialsystem`: 1 topocentric (apparent of date), 2 J2000, 0 other, 3 J2050, 4 B1950.
    public func equatorialSystem() -> AlpacaHTTPRequest { get(telescope("equatorialsystem"), []) }

    /// `GET rightascension` (hours).
    public func rightAscension() -> AlpacaHTTPRequest { get(telescope("rightascension"), []) }

    /// `GET declination` (degrees).
    public func declination() -> AlpacaHTTPRequest { get(telescope("declination"), []) }

    /// `GET slewing`.
    public func slewing() -> AlpacaHTTPRequest { get(telescope("slewing"), []) }

    /// `GET tracking`.
    public func tracking() -> AlpacaHTTPRequest { get(telescope("tracking"), []) }

    /// `GET atpark`.
    public func atPark() -> AlpacaHTTPRequest { get(telescope("atpark"), []) }

    /// `GET trackingrates`: the supported drive rates (0 sidereal, 1 lunar, 2 solar, 3 king).
    public func trackingRates() -> AlpacaHTTPRequest { get(telescope("trackingrates"), []) }

    // MARK: Telescope writes

    /// `PUT connected`.
    public func setConnected(_ connected: Bool) -> AlpacaHTTPRequest {
        put(telescope("connected"), [AlpacaField(name: "Connected", value: AlpacaCodec.formatBoolean(connected))])
    }

    /// `PUT slewtocoordinatesasync`: `rightAscensionHours` in 0 to 24 (exclusive), `declination` in ±90.
    public func slewToCoordinatesAsync(rightAscensionHours: Double, declination: Double) throws -> AlpacaHTTPRequest {
        put(telescope("slewtocoordinatesasync"), try coordinateFields(rightAscensionHours, declination))
    }

    /// `PUT synctocoordinates`.
    public func syncToCoordinates(rightAscensionHours: Double, declination: Double) throws -> AlpacaHTTPRequest {
        put(telescope("synctocoordinates"), try coordinateFields(rightAscensionHours, declination))
    }

    /// `PUT abortslew`.
    public func abortSlew() -> AlpacaHTTPRequest { put(telescope("abortslew"), []) }

    /// `PUT tracking`.
    public func setTracking(_ tracking: Bool) -> AlpacaHTTPRequest {
        put(telescope("tracking"), [AlpacaField(name: "Tracking", value: AlpacaCodec.formatBoolean(tracking))])
    }

    /// `PUT pulseguide`: move in `direction` at the guide rate for `durationMilliseconds` (1 to 30 000).
    public func pulseGuide(direction: AlpacaGuideDirection, durationMilliseconds: Int) throws -> AlpacaHTTPRequest {
        if durationMilliseconds < 1 || durationMilliseconds > 30_000 {
            throw MountError.invalidInput(detail: "the pulse must last 1 to 30000 ms")
        }
        return put(telescope("pulseguide"), [AlpacaField(name: "Direction", value: String(direction.code)),
                                             AlpacaField(name: "Duration", value: String(durationMilliseconds))])
    }

    /// `PUT moveaxis`: turn `axis` at `degreesPerSecond` (signed; 0 stops).
    public func moveAxis(_ axis: AlpacaAxis, degreesPerSecond: Double) throws -> AlpacaHTTPRequest {
        put(telescope("moveaxis"), [AlpacaField(name: "Axis", value: String(axis.code)),
                                    AlpacaField(name: "Rate", value: try AlpacaCodec.formatNumber(degreesPerSecond))])
    }

    /// `PUT sitelatitude`.
    public func setSiteLatitude(_ degrees: Double) throws -> AlpacaHTTPRequest {
        put(telescope("sitelatitude"), [AlpacaField(name: "SiteLatitude", value: try AlpacaCodec.formatNumber(degrees))])
    }

    /// `PUT sitelongitude` (east positive).
    public func setSiteLongitude(_ degrees: Double) throws -> AlpacaHTTPRequest {
        put(telescope("sitelongitude"), [AlpacaField(name: "SiteLongitude", value: try AlpacaCodec.formatNumber(degrees))])
    }

    /// `PUT siteelevation` (metres).
    public func setSiteElevation(_ metres: Double) throws -> AlpacaHTTPRequest {
        put(telescope("siteelevation"), [AlpacaField(name: "SiteElevation", value: try AlpacaCodec.formatNumber(metres))])
    }

    /// `PUT utcdate`.
    public func setUTCDate(_ date: Date) throws -> AlpacaHTTPRequest {
        guard let text = AlpacaCodec.formatUTCDate(date) else {
            throw MountError.invalidInput(detail: "the date is outside 1970 to 9999")
        }
        return put(telescope("utcdate"), [AlpacaField(name: "UTCDate", value: text)])
    }

    private func coordinateFields(_ rightAscensionHours: Double, _ declination: Double) throws -> [AlpacaField] {
        if !rightAscensionHours.isFinite || rightAscensionHours < 0 || rightAscensionHours >= 24 {
            throw MountError.invalidInput(detail: "the right ascension must be 0 to 24 hours")
        }
        if !declination.isFinite || abs(declination) > 90 {
            throw MountError.invalidInput(detail: "the declination must be within ±90°")
        }
        let hours = try AlpacaCodec.formatNumber(rightAscensionHours)
        let checkedHours = hours.hasPrefix("24.") ? "0.0" : hours
        return [AlpacaField(name: "RightAscension", value: checkedHours),
                AlpacaField(name: "Declination", value: try AlpacaCodec.formatNumber(declination))]
    }
}

/// Validates replies of the Alpaca Device and Management APIs.
public enum AlpacaResponseParser {
    /// Turns the HTTP reply to `request` into an `AlpacaReply`.
    ///
    /// Fails with `MountError.remote` for HTTP status codes other than 200 (the body text is the message), with
    /// `MountError.malformedReply` if the body is not a JSON object, a field has the wrong type or the echoed
    /// `ClientTransactionID` belongs to another request, and with the error mapped from `ErrorNumber` (see
    /// `AlpacaCodec.error`) if the device reports one.
    public static func parse(_ response: AlpacaHTTPResponse, for request: AlpacaHTTPRequest) throws -> AlpacaReply {
        if response.statusCode != 200 {
            throw MountError.remote(code: response.statusCode,
                                    detail: MountText.sanitized(response.body, limit: AlpacaCodec.maximumMessageLength))
        }
        let root = try MountJSON.parse(response.body)
        guard case .object = root else { throw MountError.malformedReply(detail: "the reply is not a JSON object") }
        if let errorField = root.field("ErrorNumber") {
            guard let number = AlpacaCodec.integer(errorField) else {
                throw MountError.malformedReply(detail: "ErrorNumber is not an integer")
            }
            if number != 0 {
                var message = ""
                if case let .text(text)? = root.field("ErrorMessage") { message = text }
                throw AlpacaCodec.error(number: number, message: message)
            }
        }
        let echoed = try optionalInteger(root, "ClientTransactionID")
        if let echoed, echoed != 0, echoed != request.clientTransactionID {
            throw MountError.malformedReply(detail: "the reply belongs to another request")
        }
        return AlpacaReply(clientTransactionID: echoed, serverTransactionID: try optionalInteger(root, "ServerTransactionID"),
                           value: root.field("Value"))
    }

    /// The versions of the Alpaca API the server supports (`/management/apiversions`).
    public static func apiVersions(_ response: AlpacaHTTPResponse, for request: AlpacaHTTPRequest) throws -> [Int] {
        try parse(response, for: request).integerList()
    }

    /// The server description (`/management/v1/description`).
    public static func serverDescription(_ response: AlpacaHTTPResponse, for request: AlpacaHTTPRequest) throws -> AlpacaServerDescription {
        guard let value = try parse(response, for: request).value, case .object = value else {
            throw MountError.malformedReply(detail: "the description is not an object")
        }
        return AlpacaServerDescription(serverName: text(value, "ServerName"), manufacturer: text(value, "Manufacturer"),
                                       manufacturerVersion: text(value, "ManufacturerVersion"), location: text(value, "Location"))
    }

    /// The devices the server offers (`/management/v1/configureddevices`), at most 64.
    public static func configuredDevices(_ response: AlpacaHTTPResponse, for request: AlpacaHTTPRequest) throws -> [AlpacaDevice] {
        guard case let .array(items)? = try parse(response, for: request).value else {
            throw MountError.malformedReply(detail: "the device list is not an array")
        }
        if items.count > 64 { throw MountError.malformedReply(detail: "too many devices") }
        return try items.map { item in
            guard case .object = item else { throw MountError.malformedReply(detail: "a device is not an object") }
            guard let number = AlpacaCodec.integer(item.field("DeviceNumber")), number >= 0 else {
                throw MountError.malformedReply(detail: "a device has no valid number")
            }
            return AlpacaDevice(deviceName: text(item, "DeviceName"), deviceType: text(item, "DeviceType"), deviceNumber: number,
                                uniqueID: text(item, "UniqueID"))
        }
    }

    private static func optionalInteger(_ root: MountJSON, _ name: String) throws -> Int? {
        guard let field = root.field(name) else { return nil }
        guard let integer = AlpacaCodec.integer(field) else { throw MountError.malformedReply(detail: "\(name) is not an integer") }
        return integer
    }

    private static func text(_ root: MountJSON, _ name: String) -> String {
        var value = ""
        if case let .text(found)? = root.field(name) { value = found }
        return MountText.sanitized(value, limit: AlpacaCodec.maximumMessageLength)
    }
}

/// The Alpaca discovery datagram (UDP port 32227) and its reply.
public enum AlpacaDiscovery {
    /// The UDP port devices listen on.
    public static let port = 32_227

    /// The IPv6 link-local multicast group for discovery.
    public static let ipv6MulticastGroup = "ff12::a1:9aca"

    /// The 16 ASCII bytes `alpacadiscovery1` to broadcast (IPv4 broadcast address of each network, or the IPv6 group).
    public static var requestPayload: [UInt8] { MountText.ascii("alpacadiscovery1") }

    /// True if `bytes` are a discovery request (what a responder or a test double checks).
    public static func isRequest(_ bytes: [UInt8]) -> Bool { bytes == requestPayload }

    /// The reply a device sends: `{"AlpacaPort": <port>}`.
    public static func responsePayload(alpacaPort: Int) -> [UInt8] { MountText.ascii("{\"AlpacaPort\": \(alpacaPort)}") }

    /// Reads the port of the Alpaca server from a discovery reply (at most 1024 bytes of JSON).
    public static func parseResponse(_ bytes: [UInt8]) throws -> Int {
        if bytes.isEmpty || bytes.count > 1024 { throw MountError.malformedReply(detail: "discovery reply length") }
        let root = try MountJSON.parse(String(decoding: bytes, as: UTF8.self))
        guard let port = AlpacaCodec.integer(root.field("AlpacaPort")), port >= 1, port <= 65_535 else {
            throw MountError.malformedReply(detail: "discovery reply has no valid AlpacaPort")
        }
        return port
    }
}
