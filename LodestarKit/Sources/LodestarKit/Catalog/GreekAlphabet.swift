import Foundation

/// The Greek letters used in Bayer designations, with the spellings people type.
enum GreekAlphabet {
    struct Letter: Sendable {
        /// The English name in lower case ("alpha").
        let name: String
        /// The three-letter forms used by catalogs and SIMBAD ("alp", "alf"), other than the full name.
        let abbreviations: [String]

        /// The name with a capital initial ("Alpha").
        var capitalizedName: String { name.prefix(1).uppercased() + name.dropFirst() }
    }

    /// The 24 letters from alpha to omega.
    static let letters: [Letter] = [
        Letter(name: "alpha", abbreviations: ["alp", "alf"]),
        Letter(name: "beta", abbreviations: ["bet"]),
        Letter(name: "gamma", abbreviations: ["gam"]),
        Letter(name: "delta", abbreviations: ["del"]),
        Letter(name: "epsilon", abbreviations: ["eps"]),
        Letter(name: "zeta", abbreviations: ["zet"]),
        Letter(name: "eta", abbreviations: []),
        Letter(name: "theta", abbreviations: ["the", "tet"]),
        Letter(name: "iota", abbreviations: ["iot"]),
        Letter(name: "kappa", abbreviations: ["kap"]),
        Letter(name: "lambda", abbreviations: ["lam"]),
        Letter(name: "mu", abbreviations: []),
        Letter(name: "nu", abbreviations: []),
        Letter(name: "xi", abbreviations: ["ksi"]),
        Letter(name: "omicron", abbreviations: ["omi"]),
        Letter(name: "pi", abbreviations: []),
        Letter(name: "rho", abbreviations: []),
        Letter(name: "sigma", abbreviations: ["sig"]),
        Letter(name: "tau", abbreviations: []),
        Letter(name: "upsilon", abbreviations: ["ups"]),
        Letter(name: "phi", abbreviations: []),
        Letter(name: "chi", abbreviations: ["khi"]),
        Letter(name: "psi", abbreviations: []),
        Letter(name: "omega", abbreviations: ["ome"]),
    ]

    /// The names of `letters` as lower-case ASCII bytes, for the text normalizer.
    static let nameBytes: [[UInt8]] = letters.map { Array($0.name.utf8) }

    /// The position in `letters` of the Greek letter written as `scalar`, in lower or upper case
    /// (including final sigma and the symbol variants of theta, kappa, phi, pi, rho and epsilon).
    static func index(of scalar: Unicode.Scalar) -> Int? {
        let offset: Int
        switch scalar.value {
        case 0x0391...0x03A1, 0x03A3...0x03A9: offset = Int(scalar.value) - 0x0391
        case 0x03B1...0x03C9: offset = Int(scalar.value) - 0x03B1
        case 0x03D1, 0x03F4: return 7
        case 0x03D5: return 20
        case 0x03D6: return 15
        case 0x03F0: return 9
        case 0x03F1: return 16
        case 0x03F5: return 4
        default: return nil
        }
        // Between rho and sigma Unicode has a slot for the final sigma (lower case; upper case has
        // none). It counts as sigma, and the letters after sigma sit one place past their alphabet
        // position.
        return offset <= 17 ? offset : offset - 1
    }

    /// The letter written as `scalar`, if it is a Greek letter.
    static func letter(for scalar: Unicode.Scalar) -> Letter? {
        index(of: scalar).map { letters[$0] }
    }
}
