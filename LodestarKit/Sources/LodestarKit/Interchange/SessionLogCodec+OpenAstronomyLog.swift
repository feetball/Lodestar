import Foundation

extension SessionLogCodec {
    /// The XML namespace of OpenAstronomyLog.
    static let openAstronomyLogNamespace = "http://groups.google.com/group/openastronomylog"

    /// The name written for the observer when none is given.
    static let defaultObserverName = "Lodestar Observer"

    /// The log as an OpenAstronomyLog 2.1 document (https://github.com/openastronomylog/openastronomylog, schema
    /// `src/oal21.xsd`; the document is valid against it).
    ///
    /// - The document has one observer, and every site, session, target, scope (the lens: focal length and aperture),
    ///   filter and imager (camera and sensor pixels) that the entries use once, referenced by `IDREF`.
    /// - A site is written when an entry has coordinates; the entries of one night at one site form a session.
    /// - A target is written with its J2000 position (`deg`, frame geocentric J2000) when known.
    /// - Each entry becomes one observation: begin, end (begin plus the frames' total exposure), and a result that says
    ///   what was shot (frames, exposure, ISO, filter, lens, camera, imaged or not) and carries the notes.
    /// - Imagers need the sensor's pixel counts (OpenAstronomyLog's `ccdCameraType`), scopes the focal length and aperture;
    ///   without them the observation has no imager or scope and the camera is only named in the result.
    /// - Text is escaped (`& < > " '`), characters XML 1.0 cannot carry are dropped, dates are UTC.
    ///
    /// - Parameter observer: The observer's name; the last word becomes the surname. Empty gives `defaultObserverName`.
    public static func encodeOpenAstronomyLog(_ entries: [SessionLogEntry], observer: String = "") -> String {
        var document = OpenAstronomyLogDocument()
        let observerName = InterchangeText.singleLine(observer, limit: SessionLogEntry.maximumNameLength)
        document.setObserver(observerName.isEmpty ? defaultObserverName : observerName)
        for entry in ordered(entries) {
            document.add(entry)
        }
        return document.text()
    }
}

/// Collects the parts of an OpenAstronomyLog document and writes them in the order of the schema.
private struct OpenAstronomyLogDocument {
    /// Parts that are written once and referenced by their identifier, in the order they were first used.
    private struct Registry {
        private var identifiers: [String: String] = [:]
        private(set) var elements: [String] = []
        let prefix: String

        init(prefix: String) {
            self.prefix = prefix
        }

        /// The identifier of the part with `key`; `makeElement` writes it with its new identifier the first time.
        mutating func identifier(for key: String, makeElement: (String) -> String) -> String {
            if let existing = identifiers[key] { return existing }
            let identifier = "\(prefix)_\(elements.count + 1)"
            identifiers[key] = identifier
            elements.append(makeElement(identifier))
            return identifier
        }
    }

    private struct Session {
        let identifier: String
        let siteIdentifier: String
        var begin: Int64
        var end: Int64
    }

    private var observerElement = ""
    private var sites = Registry(prefix: "site")
    private var targets = Registry(prefix: "target")
    private var scopes = Registry(prefix: "scope")
    private var filters = Registry(prefix: "filter")
    private var imagers = Registry(prefix: "imager")
    private var sessionIndex: [String: Int] = [:]
    private var sessions: [Session] = []
    private var observations: [String] = []

    private static func element(_ name: String, _ text: String, attributes: String = "", indent: Int) -> String {
        String(repeating: "  ", count: indent) + "<\(name)\(attributes)>\(InterchangeText.xml(text))</\(name)>\n"
    }

    mutating func setObserver(_ fullName: String) {
        let words = fullName.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let surname = words.last ?? ""
        let name = words.dropLast().joined(separator: " ")
        observerElement = "    <observer id=\"observer_1\">\n"
            + Self.element("name", name, indent: 3)
            + Self.element("surname", surname, indent: 3)
            + "    </observer>\n"
    }

    mutating func add(_ entry: SessionLogEntry) {
        let begin = InterchangeText.wholeSeconds(of: entry.date)
        let isTimed = entry.frameCount > 0 && entry.exposureSeconds > 0
        let end = isTimed ? begin + Int64(entry.totalExposureSeconds.rounded()) : begin

        var siteIdentifier: String?
        if let latitude = entry.siteLatitude, let longitude = entry.siteLongitude {
            let offset = entry.siteUTCOffsetMinutes ?? 0
            let key = "\(entry.siteName)|\(InterchangeText.fixed(latitude, decimals: 6))|\(InterchangeText.fixed(longitude, decimals: 6))|\(offset)"
            siteIdentifier = sites.identifier(for: key) { identifier in
                "    <site id=\"\(identifier)\">\n"
                    + Self.element("name", entry.siteName.isEmpty ? "Site" : entry.siteName, indent: 3)
                    + Self.element("longitude", InterchangeText.fixed(longitude, decimals: 6), attributes: " unit=\"deg\"", indent: 3)
                    + Self.element("latitude", InterchangeText.fixed(latitude, decimals: 6), attributes: " unit=\"deg\"", indent: 3)
                    + Self.element("timezone", String(offset), indent: 3)
                    + "    </site>\n"
            }
        }

        var sessionIdentifier: String?
        if let siteIdentifier {
            let key = "\(entry.night)|\(siteIdentifier)"
            if let index = sessionIndex[key] {
                sessions[index].begin = min(sessions[index].begin, begin)
                sessions[index].end = max(sessions[index].end, end)
                sessionIdentifier = sessions[index].identifier
            } else {
                let identifier = "session_\(sessions.count + 1)"
                sessionIndex[key] = sessions.count
                sessions.append(Session(identifier: identifier, siteIdentifier: siteIdentifier, begin: begin, end: end))
                sessionIdentifier = identifier
            }
        }

        let targetIdentifier = targets.identifier(for: entry.targetID.isEmpty ? entry.targetName : entry.targetID) { identifier in
            var text = "    <target id=\"\(identifier)\">\n"
                + Self.element("datasource", "Lodestar", indent: 3)
                + Self.element("name", entry.targetName, indent: 3)
            if let rightAscension = entry.rightAscension, let declination = entry.declination {
                text += "      <position>\n"
                    + Self.element("ra", InterchangeText.fixed(rightAscension, decimals: 5), attributes: " unit=\"deg\"", indent: 4)
                    + Self.element("dec", InterchangeText.fixed(declination, decimals: 5), attributes: " unit=\"deg\"", indent: 4)
                    + "        <frame>\n"
                    + Self.element("origin", "geo", indent: 5)
                    + Self.element("equinox", "J2000", indent: 5)
                    + "        </frame>\n"
                    + "      </position>\n"
            }
            return text + "    </target>\n"
        }

        var scopeIdentifier: String?
        var lensText = ""
        if let focalLength = entry.focalLength, let aperture = entry.lensAperture {
            let focalLengthText = InterchangeText.decimal(focalLength, maximumDecimals: 1)
            let apertureText = InterchangeText.decimal(aperture, maximumDecimals: SessionLogCodec.apertureDecimals)
            lensText = "\(focalLengthText) mm f/\(apertureText)"
            scopeIdentifier = scopes.identifier(for: lensText) { identifier in
                "    <scope id=\"\(identifier)\" xsi:type=\"oal:scopeType\">\n"
                    + Self.element("model", "Camera lens \(lensText)", indent: 3)
                    + Self.element("aperture", InterchangeText.decimal(focalLength / aperture, maximumDecimals: 2), indent: 3)
                    + Self.element("focalLength", InterchangeText.decimal(focalLength, maximumDecimals: 1), indent: 3)
                    + "    </scope>\n"
            }
        }

        var filterIdentifier: String?
        if !entry.filter.isEmpty {
            filterIdentifier = filters.identifier(for: entry.filter) { identifier in
                "    <filter id=\"\(identifier)\">\n"
                    + Self.element("model", entry.filter, indent: 3)
                    + Self.element("type", "other", indent: 3)
                    + "    </filter>\n"
            }
        }

        var imagerIdentifier: String?
        if let pixelsX = entry.sensorPixelsX, let pixelsY = entry.sensorPixelsY {
            let model = entry.camera.isEmpty ? "Camera" : entry.camera
            imagerIdentifier = imagers.identifier(for: "\(model)|\(pixelsX)|\(pixelsY)") { identifier in
                "    <imager id=\"\(identifier)\" xsi:type=\"oal:ccdCameraType\">\n"
                    + Self.element("model", model, indent: 3)
                    + Self.element("pixelsX", String(pixelsX), indent: 3)
                    + Self.element("pixelsY", String(pixelsY), indent: 3)
                    + Self.element("binning", "1", indent: 3)
                    + "    </imager>\n"
            }
        }

        var observation = "  <observation id=\"observation_\(observations.count + 1)\">\n"
            + Self.element("observer", "observer_1", indent: 2)
        if let siteIdentifier { observation += Self.element("site", siteIdentifier, indent: 2) }
        if let sessionIdentifier { observation += Self.element("session", sessionIdentifier, indent: 2) }
        observation += Self.element("target", targetIdentifier, indent: 2)
            + Self.element("begin", InterchangeText.dateTimeText(epochSeconds: begin), indent: 2)
        if isTimed { observation += Self.element("end", InterchangeText.dateTimeText(epochSeconds: end), indent: 2) }
        if let scopeIdentifier { observation += Self.element("scope", scopeIdentifier, indent: 2) }
        if let filterIdentifier { observation += Self.element("filter", filterIdentifier, indent: 2) }
        if let imagerIdentifier { observation += Self.element("imager", imagerIdentifier, indent: 2) }
        observation += "    <result lang=\"en\">\n"
            + Self.element("description", Self.resultText(of: entry, lens: lensText), indent: 3)
            + "    </result>\n"
        observation += "  </observation>\n"
        observations.append(observation)
    }

    /// What the result of an observation says: whether it was imaged, the frames, ISO, filter, lens and camera, then the notes.
    private static func resultText(of entry: SessionLogEntry, lens: String) -> String {
        var parts: [String] = []
        let exposureDecimals = SessionLogCodec.exposureDecimals
        let exposureText = InterchangeText.decimal(entry.exposureSeconds, maximumDecimals: exposureDecimals)
        if entry.frameCount > 0 && entry.exposureSeconds > 0 {
            parts.append("\(entry.frameCount) × \(exposureText) s")
        } else if entry.frameCount > 0 {
            parts.append("\(entry.frameCount) frames")
        } else if entry.exposureSeconds > 0 {
            parts.append("\(exposureText) s")
        }
        if entry.iso > 0 { parts.append("ISO \(entry.iso)") }
        if !entry.filter.isEmpty { parts.append("filter \(entry.filter)") }
        if !lens.isEmpty { parts.append("lens \(lens)") }
        if !entry.camera.isEmpty { parts.append("camera \(entry.camera)") }
        var text = entry.isImaged ? "Imaged" : "Not imaged"
        if !parts.isEmpty { text += ": " + parts.joined(separator: ", ") }
        text += "."
        if !entry.notes.isEmpty { text += "\n" + entry.notes }
        return text
    }

    /// The document text.
    func text() -> String {
        var result = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        result += "<oal:observations version=\"2.1\" xmlns:oal=\"\(SessionLogCodec.openAstronomyLogNamespace)\""
        result += " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""
        result += " xsi:schemaLocation=\"\(SessionLogCodec.openAstronomyLogNamespace) oal21.xsd\">\n"
        result += "  <observers>\n" + observerElement + "  </observers>\n"
        result += container("sites", sites.elements)
        result += "  <sessions>\n"
        for session in sessions {
            result += "    <session id=\"\(session.identifier)\">\n"
                + Self.element("begin", InterchangeText.dateTimeText(epochSeconds: session.begin), indent: 3)
                + Self.element("end", InterchangeText.dateTimeText(epochSeconds: session.end), indent: 3)
                + Self.element("site", session.siteIdentifier, indent: 3)
                + "    </session>\n"
        }
        result += "  </sessions>\n"
        result += container("targets", targets.elements)
        result += container("scopes", scopes.elements)
        result += container("eyepieces", [])
        result += container("lenses", [])
        result += container("filters", filters.elements)
        result += container("imagers", imagers.elements)
        for observation in observations { result += observation }
        result += "</oal:observations>\n"
        return result
    }

    /// A container element; the schema needs every container to be present, empty ones as `<name/>`.
    private func container(_ name: String, _ elements: [String]) -> String {
        elements.isEmpty ? "  <\(name)/>\n" : "  <\(name)>\n" + elements.joined() + "  </\(name)>\n"
    }
}
