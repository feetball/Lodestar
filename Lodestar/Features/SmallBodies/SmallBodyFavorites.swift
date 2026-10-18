import Foundation
import LodestarKit

/// Favourite comets and asteroids that the catalog does not have (a comet drops out of the orbit file after a few
/// years): they stay in the favourites and show "no current orbit" instead of vanishing. Pure.
enum SmallBodyFavorites {
    /// The favourites that are comets or asteroids the `catalog` has no orbit for, in favourites order, without
    /// repeats.
    static func withoutOrbit(favoriteIDs: [String], catalog: Catalog) -> [String] {
        var seen = Set<String>()
        return favoriteIDs.filter { id in
            SmallBodyText.kind(ofID: id) != nil && catalog.object(id: id) == nil && seen.insert(id).inserted
        }
    }

    /// The name of a favourite whose orbit is gone: its designation, such as "C/2023 A3" or "12P".
    static func name(ofID id: String) -> String {
        SmallBodyText.designation(ofID: id)
    }

    /// Comet or asteroid, for the identifier of a favourite whose orbit is gone.
    static func category(ofID id: String) -> ObjectCategory {
        SmallBodyText.kind(ofID: id) == .asteroid ? .asteroid : .comet
    }

    /// The words under the name: "Comet · no current orbit".
    static func subtitle(ofID id: String) -> String {
        "\(category(ofID: id).displayName) \u{00B7} \(SmallBodyText.noCurrentOrbit)"
    }

    /// What VoiceOver says for the row.
    static func spoken(ofID id: String) -> String {
        "\(name(ofID: id)), \(category(ofID: id).displayName), \(SmallBodyText.noCurrentOrbit), Favorite"
    }
}
