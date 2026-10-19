import Foundation
import LodestarKit

/// How the Objects list divides its objects into sections.
enum ObjectsGrouping: String, CaseIterable, Identifiable, Sendable {
    /// One section per object type group (Solar System, Stars, Galaxies, …).
    case type
    /// One section per prominence (Showpiece, Prominent, Notable, Obscure).
    case prominence
    /// A single section holding every object.
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: return "Object Type"
        case .prominence: return "Prominence"
        case .none: return "No Grouping"
        }
    }

    var systemImage: String {
        switch self {
        case .type: return "square.grid.2x2"
        case .prominence: return "star.circle"
        case .none: return "list.bullet"
        }
    }
}

/// How the objects inside a section are ordered.
enum ObjectsSortOrder: String, CaseIterable, Identifiable, Sendable {
    case name
    /// By catalogue number: Messier, Caldwell, NGC, IC, Sharpless, Barnard, Lynds, then the clusters; objects without
    /// a number last.
    case number
    case brightness
    /// Showpieces first, then prominent, notable and obscure objects; within each by brightness (objects without a
    /// magnitude, such as dark nebulae, after those with one) and name.
    case prominence
    case altitude
    case riseTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .number: return "Catalogue Number"
        case .brightness: return "Brightness"
        case .prominence: return "Prominence"
        case .altitude: return "Altitude Now"
        case .riseTime: return "Rise Time"
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .number: return "number"
        case .brightness: return "sparkle"
        case .prominence: return "star.circle"
        case .altitude: return "arrow.up.to.line"
        case .riseTime: return "sunrise"
        }
    }

    /// `true` when the order needs each object's position in the observer's sky.
    var needsSkyPositions: Bool {
        self == .altitude || self == .riseTime
    }
}

/// What the Objects list shows: how it is grouped and ordered and which quick filters are on.
struct ObjectsListOptions: Equatable, Sendable {
    /// Objects fainter than this magnitude are hidden by `hidesFaintObjects`.
    static let faintMagnitudeLimit = 10.0
    /// The least conspicuous level `showsOnlyPopular` keeps.
    static let popularProminence = Prominence.prominent

    var grouping: ObjectsGrouping = .type
    var sortOrder: ObjectsSortOrder = .name
    var showsOnlyAboveHorizon = false
    var hidesFaintObjects = false
    /// Limits the list to one catalogue, including its obscure objects.
    var catalogue = ObjectsCatalogueFilter.all
    /// Keeps only showpiece and prominent objects.
    var showsOnlyPopular = false

    /// `true` when any option differs from the default list (the toolbar menu highlights its icon).
    var isCustomized: Bool {
        // The catalogue shows in its own chips, not in the menu.
        var menuOptions = self
        menuOptions.catalogue = .all
        return menuOptions != ObjectsListOptions()
    }
}
