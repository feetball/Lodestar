import Foundation
import LodestarKit

/// The catalogue the Objects list is limited to: one of the deep-sky catalogues, or everything.
///
/// A catalogue list holds every object of the catalogue, also those the browse lists leave out because they are
/// obscure; the Sharpless, Barnard and Lynds lists are mostly such objects.
enum ObjectsCatalogueFilter: String, CaseIterable, Identifiable, Sendable {
    case all, messier, caldwell, sharpless, barnard, lynds, ngcIC, clusters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .messier: return "Messier"
        case .caldwell: return "Caldwell"
        case .sharpless: return "Sharpless"
        case .barnard: return "Barnard"
        case .lynds: return "Lynds"
        case .ngcIC: return "NGC/IC"
        case .clusters: return "Clusters"
        }
    }

    /// A longer name, for VoiceOver and the empty list.
    var fullTitle: String {
        switch self {
        case .all: return "All objects"
        case .messier: return "Messier catalogue"
        case .caldwell: return "Caldwell catalogue"
        case .sharpless: return "Sharpless catalogue of emission nebulae"
        case .barnard: return "Barnard catalogue of dark nebulae"
        case .lynds: return "Lynds catalogue of dark nebulae"
        case .ngcIC: return "NGC and IC catalogues"
        case .clusters: return "Collinder, Melotte, Trumpler and Stock clusters"
        }
    }

    /// The engine catalogues the filter stands for, in the order their numbers are listed; empty for `.all`.
    var catalogues: [DeepSkyCatalogue] {
        switch self {
        case .all: return []
        case .messier: return [.messier]
        case .caldwell: return [.caldwell]
        case .sharpless: return [.sharpless]
        case .barnard: return [.barnard]
        case .lynds: return [.lynds]
        case .ngcIC: return [.ngc, .ic]
        case .clusters: return [.collinder, .melotte, .trumpler, .stock]
        }
    }

    /// Whether `object` has a number in one of the filter's catalogues (always `true` for `.all`).
    func contains(_ object: CelestialObject) -> Bool {
        self == .all || object.catalogNumbers.contains { catalogues.contains($0.catalogue) }
    }

    /// Every object of the filter's catalogues, listed or not, in catalogue order. Nothing for `.all`.
    func objects(in catalog: Catalog) -> [CelestialObject] {
        var seen = Set<String>()
        return catalogues.flatMap { catalog.objects(in: $0) }.filter { seen.insert($0.id).inserted }
    }

    /// The order of the catalogues when objects are put in catalogue-number order across all of them.
    private static let numberingOrder: [DeepSkyCatalogue] = [
        .messier, .caldwell, .ngc, .ic, .sharpless, .barnard, .lynds, .collinder, .melotte, .trumpler, .stock,
    ]

    /// A sortable position of `object` in catalogue-number order: catalogue first, then number, then letter. The
    /// first number inside the filter's catalogues counts (the first of any catalogue for `.all`); `nil` for objects
    /// without one.
    func numberKey(of object: CelestialObject) -> Double? {
        let candidates = object.catalogNumbers.filter { self == .all || catalogues.contains($0.catalogue) }
        let ranked = candidates.compactMap { number -> (order: Int, number: CatalogNumber)? in
            let order = self == .all ? Self.numberingOrder.firstIndex(of: number.catalogue)
                                     : catalogues.firstIndex(of: number.catalogue)
            return order.map { ($0, number) }
        }
        guard let best = ranked.min(by: { $0.order != $1.order ? $0.order < $1.order : $0.number.number < $1.number.number })
        else { return nil }
        let letter = best.number.suffix.unicodeScalars.first.map { Double(min($0.value % 32, 9)) } ?? 0
        return Double(best.order) * 1_000_000 + Double(best.number.number) * 10 + letter
    }
}
