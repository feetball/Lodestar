import XCTest
@testable import LodestarKit

/// Alpaca codec tests. Sources: ASCOM Alpaca Device API v1 and Management API v1 (OpenAPI definitions,
/// https://ascom-standards.org/api/AlpacaDeviceAPI_v1.yaml sha256 d08d4bfe1a01da637a9084d6a26043d669f665ecee438f6923d078539e4b8276 and
/// AlpacaManagementAPI_v1.yaml sha256 bafa24883572ad0b31efb31aa2e39aa81a945e0f4e449baab376f6c85d18aa84: paths, parameter names, response
/// shapes, error number range), `ASCOM.Common.Alpaca.AlpacaErrors` (0x400 NotImplemented … 0x4FF UnspecifiedError, driver range 0x500 to
/// 0xFFF) and ASCOM alpyca's discovery module (UDP 32227, `alpacadiscovery1`, `{"AlpacaPort": n}`, IPv6 group `ff12::a1:9aca`).
final class AlpacaCodecTests: XCTestCase {
    private func ok(_ value: String?, client: Int, server: Int = 1) -> AlpacaHTTPResponse {
        let valueText = value.map { "\"Value\": \($0), " } ?? ""
        return AlpacaHTTPResponse(
            statusCode: 200,
            body: "{\(valueText)\"ClientTransactionID\": \(client), \"ServerTransactionID\": \(server), \"ErrorNumber\": 0, \"ErrorMessage\": \"\"}")
    }

    private func failure(_ number: Int, _ message: String, client: Int) -> AlpacaHTTPResponse {
        AlpacaHTTPResponse(
            statusCode: 200,
            body: "{\"ClientTransactionID\": \(client), \"ServerTransactionID\": 3, \"ErrorNumber\": \(number), \"ErrorMessage\": \"\(message)\"}")
    }

    // MARK: Requests

    func testReadsGoInTheQueryWithClientIdentity() {
        let builder = AlpacaRequestBuilder(deviceNumber: 0, clientID: 7)
        let first = builder.rightAscension()
        XCTAssertEqual(first.method, .get)
        XCTAssertEqual(first.path, "/api/v1/telescope/0/rightascension")
        XCTAssertEqual(first.query, [AlpacaField(name: "ClientID", value: "7"), AlpacaField(name: "ClientTransactionID", value: "1")])
        XCTAssertEqual(first.target, "/api/v1/telescope/0/rightascension?ClientID=7&ClientTransactionID=1")
        XCTAssertEqual(first.body, "")
        XCTAssertNil(first.contentType)
        XCTAssertEqual(first.clientTransactionID, 1)
        let second = builder.declination()
        XCTAssertEqual(second.target, "/api/v1/telescope/0/declination?ClientID=7&ClientTransactionID=2")
        XCTAssertEqual(second.clientTransactionID, 2)
    }

    func testWritesGoInTheFormBody() throws {
        let builder = AlpacaRequestBuilder(deviceNumber: 2, clientID: 9)
        let request = try builder.slewToCoordinatesAsync(rightAscensionHours: 12.5, declination: -45.25)
        XCTAssertEqual(request.method, .put)
        XCTAssertEqual(request.path, "/api/v1/telescope/2/slewtocoordinatesasync")
        XCTAssertEqual(request.target, "/api/v1/telescope/2/slewtocoordinatesasync")
        XCTAssertEqual(request.body, "RightAscension=12.5&Declination=-45.25&ClientID=9&ClientTransactionID=1")
        XCTAssertEqual(request.contentType, "application/x-www-form-urlencoded")
        XCTAssertTrue(request.query.isEmpty)
    }

    func testEveryRequestUsesTheDocumentedNames() throws {
        let b = AlpacaRequestBuilder(deviceNumber: 0, clientID: 1)
        func check(_ request: AlpacaHTTPRequest, _ method: AlpacaMethod, _ path: String, _ parameters: String,
                   file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(request.method, method, path, file: file, line: line)
            XCTAssertEqual(request.path, "/api/v1/telescope/0/\(path)", file: file, line: line)
            let actual = method == .get ? AlpacaCodec.encodeFields(request.query) : request.body
            let identity = "ClientID=1&ClientTransactionID=\(request.clientTransactionID)"
            XCTAssertEqual(actual, parameters.isEmpty ? identity : "\(parameters)&\(identity)", path, file: file, line: line)
        }
        check(b.connected(), .get, "connected", "")
        check(b.setConnected(true), .put, "connected", "Connected=True")
        check(b.name(), .get, "name", "")
        check(b.canSlewAsync(), .get, "canslewasync", "")
        check(b.canSync(), .get, "cansync", "")
        check(b.canPulseGuide(), .get, "canpulseguide", "")
        check(b.canSetTracking(), .get, "cansettracking", "")
        check(b.canMoveAxis(.secondary), .get, "canmoveaxis", "Axis=1")
        check(b.equatorialSystem(), .get, "equatorialsystem", "")
        check(b.slewing(), .get, "slewing", "")
        check(b.tracking(), .get, "tracking", "")
        check(b.atPark(), .get, "atpark", "")
        check(b.trackingRates(), .get, "trackingrates", "")
        check(b.setTracking(false), .put, "tracking", "Tracking=False")
        check(b.abortSlew(), .put, "abortslew", "")
        check(try b.syncToCoordinates(rightAscensionHours: 1.0, declination: 2.0), .put, "synctocoordinates",
              "RightAscension=1.0&Declination=2.0")
        check(try b.pulseGuide(direction: .east, durationMilliseconds: 500), .put, "pulseguide", "Direction=2&Duration=500")
        check(try b.moveAxis(.primary, degreesPerSecond: -0.25), .put, "moveaxis", "Axis=0&Rate=-0.25")
        check(try b.setSiteLatitude(40.015), .put, "sitelatitude", "SiteLatitude=40.015")
        check(try b.setSiteLongitude(-105.27), .put, "sitelongitude", "SiteLongitude=-105.27")
        check(try b.setSiteElevation(1650.0), .put, "siteelevation", "SiteElevation=1650.0")
        let date = try b.setUTCDate(Date(timeIntervalSince1970: 1_792_296_000))
        XCTAssertTrue(date.body.hasPrefix("UTCDate=2026-10-18T04%3A00%3A00.000Z&ClientID=1"), date.body)
        let api = b.apiVersions()
        XCTAssertEqual(api.target, "/management/apiversions?ClientID=1&ClientTransactionID=\(api.clientTransactionID)")
        XCTAssertEqual(b.serverDescription().path, "/management/v1/description")
        XCTAssertEqual(b.configuredDevices().path, "/management/v1/configureddevices")
    }

    func testGuideDirectionAndAxisCodesFollowTheSpecification() {
        XCTAssertEqual(AlpacaGuideDirection.allCases.map(\.code), [0, 1, 2, 3])
        XCTAssertEqual(AlpacaGuideDirection.allCases, [.north, .south, .east, .west])
        XCTAssertEqual(AlpacaAxis.allCases.map(\.code), [0, 1, 2])
    }

    func testTransactionIdentifiersWrapAndClientIdentifiersAreClamped() {
        let builder = AlpacaRequestBuilder(deviceNumber: 0, clientID: 1, lastTransactionID: Int(Int32.max) - 1)
        XCTAssertEqual(builder.slewing().clientTransactionID, Int(Int32.max))
        XCTAssertEqual(builder.slewing().clientTransactionID, 1)
        XCTAssertEqual(builder.slewing().clientTransactionID, 2)
        XCTAssertEqual(AlpacaRequestBuilder(deviceNumber: 0, clientID: 0).clientID, 1)
        XCTAssertEqual(AlpacaRequestBuilder(deviceNumber: 0, clientID: -5).clientID, 1)
        XCTAssertEqual(AlpacaRequestBuilder(deviceNumber: 0, clientID: 65_535).clientID, 65_535)
    }

    func testCoordinatesAreValidated() throws {
        let builder = AlpacaRequestBuilder()
        for hours in [-0.1, 24.0, 30.0, Double.nan, Double.infinity] {
            assertInvalidInput(try builder.slewToCoordinatesAsync(rightAscensionHours: hours, declination: 0.0), "\(hours)")
        }
        for degrees in [90.1, -91.0, Double.nan] {
            assertInvalidInput(try builder.syncToCoordinates(rightAscensionHours: 1.0, declination: degrees), "\(degrees)")
        }
        // A right ascension that rounds up to 24 h is sent as 0.
        XCTAssertTrue(try builder.slewToCoordinatesAsync(rightAscensionHours: 23.9999999999, declination: 0.0).body.hasPrefix("RightAscension=0.0&"))
        XCTAssertTrue(try builder.slewToCoordinatesAsync(rightAscensionHours: 0.0, declination: 90.0).body
            .hasPrefix("RightAscension=0.0&Declination=90.0&"))
        XCTAssertTrue(try builder.slewToCoordinatesAsync(rightAscensionHours: 23.999999, declination: -90.0).body
            .hasPrefix("RightAscension=23.999999&Declination=-90.0&"))
    }

    func testPulseGuideDurationIsLimited() throws {
        let builder = AlpacaRequestBuilder()
        for milliseconds in [0, -5, 30_001] {
            assertInvalidInput(try builder.pulseGuide(direction: .north, durationMilliseconds: milliseconds), "\(milliseconds)")
        }
        XCTAssertTrue(try builder.pulseGuide(direction: .north, durationMilliseconds: 1).body.contains("Duration=1&"))
        XCTAssertTrue(try builder.pulseGuide(direction: .west, durationMilliseconds: 30_000).body.contains("Direction=3&Duration=30000&"))
    }

    func testPercentEncoding() {
        XCTAssertEqual(AlpacaCodec.percentEncode(""), "")
        XCTAssertEqual(AlpacaCodec.percentEncode("AZaz09-._~"), "AZaz09-._~")
        XCTAssertEqual(AlpacaCodec.percentEncode("a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9")
        XCTAssertEqual(AlpacaCodec.percentEncode("100%+1"), "100%25%2B1")
        XCTAssertEqual(AlpacaCodec.percentEncode("😀"), "%F0%9F%98%80")
        XCTAssertEqual(AlpacaCodec.encodeFields([AlpacaField(name: "a=b", value: "x&y"), AlpacaField(name: "c", value: "1")]), "a%3Db=x%26y&c=1")
    }

    func testNumberFormatting() throws {
        XCTAssertEqual(try AlpacaCodec.formatNumber(12.5), "12.5")
        XCTAssertEqual(try AlpacaCodec.formatNumber(-0.25), "-0.25")
        XCTAssertEqual(try AlpacaCodec.formatNumber(3.0), "3.0")
        XCTAssertEqual(try AlpacaCodec.formatNumber(0.0), "0.0")
        XCTAssertEqual(try AlpacaCodec.formatNumber(-0.0), "0.0")
        XCTAssertEqual(try AlpacaCodec.formatNumber(-0.0000000001), "0.0")
        XCTAssertEqual(try AlpacaCodec.formatNumber(1e-9), "0.000000001")
        XCTAssertEqual(try AlpacaCodec.formatNumber(0.1 + 0.2), "0.3")
        XCTAssertEqual(try AlpacaCodec.formatNumber(23.999999999), "23.999999999")
        XCTAssertEqual(try AlpacaCodec.formatNumber(359.1234567891), "359.123456789")
        XCTAssertEqual(try AlpacaCodec.formatNumber(1650.0), "1650.0")
        for bad in [Double.nan, Double.infinity, -Double.infinity, 2.0e9] { assertInvalidInput(try AlpacaCodec.formatNumber(bad), "\(bad)") }
        XCTAssertEqual(AlpacaCodec.formatBoolean(true), "True")
        XCTAssertEqual(AlpacaCodec.formatBoolean(false), "False")
    }

    func testUTCDateFormat() {
        XCTAssertEqual(AlpacaCodec.formatUTCDate(Date(timeIntervalSince1970: 1_792_296_000)), "2026-10-18T04:00:00.000Z")
        XCTAssertEqual(AlpacaCodec.formatUTCDate(Date(timeIntervalSince1970: 951_868_799.123)), "2000-02-29T23:59:59.123Z")
        XCTAssertEqual(AlpacaCodec.formatUTCDate(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(AlpacaCodec.formatUTCDate(Date(timeIntervalSince1970: 4_107_542_400)), "2100-03-01T00:00:00.000Z")
        XCTAssertNil(AlpacaCodec.formatUTCDate(Date(timeIntervalSince1970: -1)))
        XCTAssertNil(AlpacaCodec.formatUTCDate(Date(timeIntervalSince1970: 1.0e12)))
    }

    // MARK: Replies

    func testSuccessfulRepliesGiveTypedValues() throws {
        let builder = AlpacaRequestBuilder(deviceNumber: 0, clientID: 1)
        let ra = builder.rightAscension()
        let reply = try AlpacaResponseParser.parse(ok("12.5", client: ra.clientTransactionID, server: 17), for: ra)
        XCTAssertEqual(try reply.doubleValue(), 12.5)
        XCTAssertEqual(reply.clientTransactionID, ra.clientTransactionID)
        XCTAssertEqual(reply.serverTransactionID, 17)
        let slewing = builder.slewing()
        XCTAssertEqual(try AlpacaResponseParser.parse(ok("true", client: slewing.clientTransactionID), for: slewing).booleanValue(), true)
        let system = builder.equatorialSystem()
        XCTAssertEqual(try AlpacaResponseParser.parse(ok("2", client: system.clientTransactionID), for: system).integerValue(), 2)
        let name = builder.name()
        XCTAssertEqual(try AlpacaResponseParser.parse(ok("\"Sim\"", client: name.clientTransactionID), for: name).textValue(), "Sim")
        let rates = builder.trackingRates()
        XCTAssertEqual(try AlpacaResponseParser.parse(ok("[0,1,2,3]", client: rates.clientTransactionID), for: rates).integerList(), [0, 1, 2, 3])
        let abort = builder.abortSlew()
        XCTAssertNil(try AlpacaResponseParser.parse(ok(nil, client: abort.clientTransactionID), for: abort).value)
    }

    func testTypedAccessorsRejectWrongTypes() throws {
        let builder = AlpacaRequestBuilder()
        let request = builder.slewing()
        let id = request.clientTransactionID
        let text = try AlpacaResponseParser.parse(ok("\"yes\"", client: id), for: request)
        assertMalformed(try text.booleanValue())
        assertMalformed(try text.doubleValue())
        assertMalformed(try text.integerValue())
        assertMalformed(try text.integerList())
        let fraction = try AlpacaResponseParser.parse(ok("1.5", client: id), for: request)
        assertMalformed(try fraction.integerValue())
        assertMalformed(try fraction.textValue())
        let mixed = try AlpacaResponseParser.parse(ok("[1,\"a\"]", client: id), for: request)
        assertMalformed(try mixed.integerList())
        let huge = try AlpacaResponseParser.parse(ok("4294967296", client: id), for: request)
        assertMalformed(try huge.integerValue())
        let missing = try AlpacaResponseParser.parse(ok(nil, client: id), for: request)
        assertMalformed(try missing.booleanValue())
        let list = "[" + (1 ... 65).map(String.init).joined(separator: ",") + "]"
        let long = try AlpacaResponseParser.parse(ok(list, client: id), for: request)
        assertMalformed(try long.integerList())
    }

    func testTheEchoedTransactionNumberMustBelongToTheRequest() throws {
        let builder = AlpacaRequestBuilder()
        let request = builder.slewing()
        let id = request.clientTransactionID
        assertMalformed(try AlpacaResponseParser.parse(ok("true", client: id + 1), for: request))
        // Zero means the device did not receive a valid value; a missing member is tolerated as well.
        XCTAssertEqual(try AlpacaResponseParser.parse(ok("true", client: 0), for: request).clientTransactionID, 0)
        let bare = try AlpacaResponseParser.parse(AlpacaHTTPResponse(statusCode: 200, body: "{\"Value\": true}"), for: request)
        XCTAssertEqual(try bare.booleanValue(), true)
        XCTAssertNil(bare.clientTransactionID)
        assertMalformed(try AlpacaResponseParser.parse(
            AlpacaHTTPResponse(statusCode: 200, body: "{\"Value\": true, \"ClientTransactionID\": \"1\"}"), for: request))
        // Member names are case insensitive.
        XCTAssertEqual(
            try AlpacaResponseParser.parse(
                AlpacaHTTPResponse(statusCode: 200, body: "{\"value\": true, \"clienttransactionid\": \(id)}"), for: request).booleanValue(),
            true)
    }

    func testHttpErrorsBecomeRemoteErrors() {
        let request = AlpacaRequestBuilder().slewing()
        for status in [400, 403, 404, 500, 503] {
            let error = mountError { _ = try AlpacaResponseParser.parse(
                AlpacaHTTPResponse(statusCode: status, body: "Invalid device number\r\n"), for: request) }
            XCTAssertEqual(error, .remote(code: status, detail: "Invalid device number"), "\(status)")
        }
    }

    func testErrorNumbersAreMappedToTypedErrors() {
        let request = AlpacaRequestBuilder().slewing()
        func error(_ number: Int, _ message: String) -> MountError? {
            mountError { _ = try AlpacaResponseParser.parse(failure(number, message, client: request.clientTransactionID), for: request) }
        }
        XCTAssertEqual(error(0x400, "not implemented"), .notSupported(feature: .other))
        XCTAssertEqual(error(0x401, "bad value"), .rejected(detail: "bad value"))
        XCTAssertEqual(error(0x402, "not set"), .rejected(detail: "not set"))
        XCTAssertEqual(error(0x407, "Not connected"), .notConnected)
        XCTAssertEqual(error(0x408, "Parked"), .parked)
        XCTAssertEqual(error(0x409, ""), .rejected(detail: "the mount is slaved"))
        XCTAssertEqual(error(0x40B, "Operation failed"), .remote(code: 0x40B, detail: "Operation failed"))
        XCTAssertEqual(error(0x40B, "Target is below the horizon"), .mountHorizonLimit)
        XCTAssertEqual(error(0x40B, "Tracking must be on"), .notTracking)
        XCTAssertEqual(error(0x40C, "Action not implemented"), .notSupported(feature: .other))
        XCTAssertEqual(error(0x40E, "cancelled"), .remote(code: 0x40E, detail: "cancelled"))
        XCTAssertEqual(error(0x4FF, "unknown"), .remote(code: 0x4FF, detail: "unknown"))
        XCTAssertEqual(error(0x500, "Mount is not aligned"), .notAligned)
        XCTAssertEqual(error(0x501, "Meridian limit"), .outsideMountLimits)
        XCTAssertEqual(error(0x502, "Mount busy"), .busy)
        XCTAssertEqual(error(0xFFF, "mount is PARKED"), .parked)
        XCTAssertEqual(error(0xFFF, "Motor stalled"), .remote(code: 0xFFF, detail: "Motor stalled"))
        XCTAssertEqual(error(5, ""), .remote(code: 5, detail: ""))
    }

    func testErrorMessagesAreCleaned() {
        let request = AlpacaRequestBuilder().slewing()
        let message = "bad\\u0007 thing" + String(repeating: "x", count: 300)
        guard case let .remote(_, detail)? = mountError({ _ = try AlpacaResponseParser.parse(
            failure(0x4FF, message, client: request.clientTransactionID), for: request) }) else {
            return XCTFail("expected a remote error")
        }
        XCTAssertLessThanOrEqual(detail.count, AlpacaCodec.maximumMessageLength)
        XCTAssertTrue(detail.hasPrefix("bad thing"))
    }

    func testBrokenBodiesAreRejected() {
        let request = AlpacaRequestBuilder().slewing()
        let bodies = [
            "", "OK", "[1]", "true", "{\"Value\": true", "{\"Value\": }", "{\"ErrorNumber\": \"x\"}", "{\"ErrorNumber\": 1.5}",
            "{\"ServerTransactionID\": 1.5, \"Value\": true}", "<html></html>",
        ]
        for body in bodies { assertMalformed(try AlpacaResponseParser.parse(AlpacaHTTPResponse(statusCode: 200, body: body), for: request), body) }
    }

    // MARK: Discovery

    func testDiscoveryDatagram() {
        XCTAssertEqual(AlpacaDiscovery.port, 32_227)
        XCTAssertEqual(AlpacaDiscovery.ipv6MulticastGroup, "ff12::a1:9aca")
        XCTAssertEqual(AlpacaDiscovery.requestPayload, Array("alpacadiscovery1".utf8))
        XCTAssertEqual(AlpacaDiscovery.requestPayload.count, 16)
        XCTAssertTrue(AlpacaDiscovery.isRequest(Array("alpacadiscovery1".utf8)))
        XCTAssertFalse(AlpacaDiscovery.isRequest(Array("alpacadiscovery2".utf8)))
        XCTAssertFalse(AlpacaDiscovery.isRequest([]))
    }

    func testDiscoveryReplies() throws {
        XCTAssertEqual(try AlpacaDiscovery.parseResponse(Array("{\"AlpacaPort\": 32323}".utf8)), 32_323)
        XCTAssertEqual(try AlpacaDiscovery.parseResponse(Array("{\"alpacaport\":11111,\"Extra\":[1]}".utf8)), 11_111)
        XCTAssertEqual(try AlpacaDiscovery.parseResponse(Array("{\"AlpacaPort\":1}".utf8)), 1)
        XCTAssertEqual(try AlpacaDiscovery.parseResponse(Array("{\"AlpacaPort\":65535}".utf8)), 65_535)
        XCTAssertEqual(try AlpacaDiscovery.parseResponse(AlpacaDiscovery.responsePayload(alpacaPort: 4_321)), 4_321)
        let bad = [
            "", "{}", "{\"AlpacaPort\":0}", "{\"AlpacaPort\":65536}", "{\"AlpacaPort\":-1}", "{\"AlpacaPort\":1.5}",
            "{\"AlpacaPort\":\"11111\"}", "[11111]", "AlpacaPort", "{\"AlpacaPort\":", "alpacadiscovery1",
        ]
        for text in bad { assertMalformed(try AlpacaDiscovery.parseResponse(Array(text.utf8)), text) }
        assertMalformed(try AlpacaDiscovery.parseResponse([UInt8](repeating: UInt8(ascii: " "), count: 1025)))
    }

    func testEndpoints() {
        XCTAssertEqual(AlpacaEndpoint(host: "192.168.4.1", port: 11_111).baseURL, "http://192.168.4.1:11111")
        XCTAssertEqual(AlpacaEndpoint(host: "fe80::1", port: 32_323).baseURL, "http://[fe80::1]:32323")
        XCTAssertEqual(AlpacaEndpoint.validated(host: "mount.local", port: 80)?.baseURL, "http://mount.local:80")
        for host in ["", "a b", "a/b", "a?b", "a#b", "u@h", "[::1]", String(repeating: "x", count: 254)] {
            XCTAssertNil(AlpacaEndpoint.validated(host: host, port: 80), host)
        }
        XCTAssertNil(AlpacaEndpoint.validated(host: "host", port: 0))
        XCTAssertNil(AlpacaEndpoint.validated(host: "host", port: 65_536))
    }

    // MARK: Management API

    func testConfiguredDevices() throws {
        let builder = AlpacaRequestBuilder()
        let request = builder.configuredDevices()
        let body = "{\"Value\":[{\"DeviceName\":\"Star Adventurer GTi\",\"DeviceType\":\"Telescope\",\"DeviceNumber\":0,"
            + "\"UniqueID\":\"3bf1\"},{\"DeviceName\":\"Cam\",\"DeviceType\":\"Camera\",\"DeviceNumber\":1,\"UniqueID\":\"c1\"},"
            + "{\"DeviceName\":\"Second\",\"DeviceType\":\"telescope\",\"DeviceNumber\":4,\"UniqueID\":\"x\"}],"
            + "\"ClientTransactionID\":\(request.clientTransactionID),\"ServerTransactionID\":4}"
        let devices = try AlpacaResponseParser.configuredDevices(AlpacaHTTPResponse(statusCode: 200, body: body), for: request)
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0], AlpacaDevice(deviceName: "Star Adventurer GTi", deviceType: "Telescope", deviceNumber: 0, uniqueID: "3bf1"))
        XCTAssertEqual(devices.filter(\.isTelescope).map(\.deviceNumber), [0, 4])
        XCTAssertFalse(devices[1].isTelescope)
    }

    func testConfiguredDevicesAreValidated() throws {
        let request = AlpacaRequestBuilder().configuredDevices()
        let many = "{\"Value\":[" + (1 ... 65).map { "{\"DeviceType\":\"Telescope\",\"DeviceNumber\":\($0)}" }.joined(separator: ",") + "]}"
        let bodies = [
            "{\"Value\":{}}", "{\"Value\":[1]}", "{\"Value\":[{\"DeviceType\":\"Telescope\"}]}",
            "{\"Value\":[{\"DeviceType\":\"Telescope\",\"DeviceNumber\":-1}]}",
            "{\"Value\":[{\"DeviceType\":\"Telescope\",\"DeviceNumber\":1.5}]}", many,
        ]
        for body in bodies {
            assertMalformed(try AlpacaResponseParser.configuredDevices(AlpacaHTTPResponse(statusCode: 200, body: body), for: request), body)
        }
        let empty = try AlpacaResponseParser.configuredDevices(AlpacaHTTPResponse(statusCode: 200, body: "{\"Value\":[]}"), for: request)
        XCTAssertTrue(empty.isEmpty)
    }

    func testApiVersionsAndDescription() throws {
        let builder = AlpacaRequestBuilder()
        let versions = builder.apiVersions()
        XCTAssertEqual(try AlpacaResponseParser.apiVersions(AlpacaHTTPResponse(statusCode: 200, body: "{\"Value\":[1]}"), for: versions), [1])
        let description = builder.serverDescription()
        let body = "{\"Value\":{\"ServerName\":\"Omni\",\"Manufacturer\":\"ASCOM\",\"ManufacturerVersion\":\"7.0\",\"Location\":\"Home\"}}"
        XCTAssertEqual(
            try AlpacaResponseParser.serverDescription(AlpacaHTTPResponse(statusCode: 200, body: body), for: description),
            AlpacaServerDescription(serverName: "Omni", manufacturer: "ASCOM", manufacturerVersion: "7.0", location: "Home"))
        assertMalformed(try AlpacaResponseParser.serverDescription(AlpacaHTTPResponse(statusCode: 200, body: "{\"Value\":[]}"), for: description))
        XCTAssertTrue(try XCTUnwrap(mountError {
            _ = try AlpacaResponseParser.apiVersions(AlpacaHTTPResponse(statusCode: 403, body: "Forbidden"), for: versions)
        }).isRemote)
    }
}
