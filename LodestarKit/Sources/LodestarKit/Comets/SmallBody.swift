import Foundation

/// A comet or an asteroid: identity, orbit and brightness model. Immutable; build one with the parsers
/// (`CometElementsParser`, `MinorPlanetElementsParser`, `SmallBodyJSONParser`) or with the failable initializer.
public struct SmallBody: Hashable, Sendable {
    /// A stable identifier for lists and favourites: `"comet.C/2023 A3"`, `"comet.12P"`, `"asteroid.4"` (a numbered
    /// asteroid) or `"asteroid.2024 YR4"`. It is made of `kind` and `designation` only, so it survives element updates.
    public let id: String
    /// The official designation without the name: `"C/2023 A3"`, `"12P"` (a periodic comet with its number),
    /// `"73P-B"` (a fragment), `"P/2020 K9"`, `"4"` (a numbered asteroid) or `"2024 YR4"`.
    public let designation: String
    /// The common name (`"Tsuchinshan-ATLAS"`, `"Pons-Brooks"`, `"Vesta"`), or an empty string.
    public let name: String
    /// Comet or asteroid.
    public let kind: SmallBodyKind
    /// The periodic-comet number (12 for 12P) or the asteroid number, if it has one.
    public let number: Int?
    /// The heliocentric orbit.
    public let orbit: OrbitalElements
    /// How to compute the magnitude; `nil` when the source gave no magnitude parameters.
    public let photometry: SmallBodyPhotometry?

    /// The longest accepted designation or name, in characters.
    public static let maximumTextLength = 80

    /// Creates a body, or returns `nil` if `designation` is empty after trimming, a text is longer than
    /// `maximumTextLength` characters or contains control characters, or `number` is not in 1…99 999 999.
    /// Surrounding spaces of the texts are removed. The identifier is built from `kind` and `designation`.
    public init?(designation: String, name: String = "", kind: SmallBodyKind, number: Int? = nil, orbit: OrbitalElements,
                 photometry: SmallBodyPhotometry? = nil) {
        guard let cleanDesignation = Self.cleaned(designation), let cleanName = Self.cleaned(name) else { return nil }
        guard !cleanDesignation.isEmpty else { return nil }
        if let number, number < 1 || number > 99_999_999 { return nil }
        self.id = "\(kind.rawValue).\(cleanDesignation)"
        self.designation = cleanDesignation
        self.name = cleanName
        self.kind = kind
        self.number = number
        self.orbit = orbit
        self.photometry = photometry
    }

    /// The name if there is one, else the designation.
    public var displayName: String { name.isEmpty ? designation : name }

    /// The full title as astronomers write it: `"C/2023 A3 (Tsuchinshan-ATLAS)"`, `"12P/Pons-Brooks"`, `"(4) Vesta"`,
    /// `"2024 YR4"`.
    public var title: String {
        switch kind {
        case .comet:
            if name.isEmpty { return designation }
            if number != nil { return "\(designation)/\(name)" }
            return "\(designation) (\(name))"
        case .asteroid:
            if number != nil && name.isEmpty { return "(\(designation))" }
            if number != nil { return "(\(designation)) \(name)" }
            return designation
        }
    }

    /// `text` without surrounding spaces and tabs, or `nil` if it is too long or has control characters.
    static func cleaned(_ text: String) -> String? {
        let scalars = Array(text.unicodeScalars)
        var first = 0
        var last = scalars.count
        while first < last && (scalars[first].value == 0x20 || scalars[first].value == 0x09) { first += 1 }
        while last > first && (scalars[last - 1].value == 0x20 || scalars[last - 1].value == 0x09) { last -= 1 }
        if last - first > maximumTextLength { return nil }
        for index in first..<last {
            let scalar = scalars[index].value
            if scalar < 0x20 || (scalar >= 0x7F && scalar <= 0x9F) { return nil }
        }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars[first..<last])
        return String(result)
    }
}
