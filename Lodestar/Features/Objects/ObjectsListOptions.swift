import Foundation

/// How the Objects list divides its objects into sections.
enum ObjectsGrouping: String, CaseIterable, Identifiable, Sendable {
    /// One section per object type group (Solar System, Stars, Galaxies, …).
    case type
    /// A single section holding every object.
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: return "Object Type"
        case .none: return "No Grouping"
        }
    }

    var systemImage: String {
        switch self {
        case .type: return "square.grid.2x2"
        case .none: return "list.bullet"
        }
    }
}

/// How the objects inside a section are ordered.
enum ObjectsSortOrder: String, CaseIterable, Identifiable, Sendable {
    case name
    case brightness
    case altitude
    case riseTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .brightness: return "Brightness"
        case .altitude: return "Altitude Now"
        case .riseTime: return "Rise Time"
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .brightness: return "sparkle"
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

    var grouping: ObjectsGrouping = .type
    var sortOrder: ObjectsSortOrder = .name
    var showsOnlyAboveHorizon = false
    var hidesFaintObjects = false

    /// `true` when any option differs from the default list (the toolbar menu highlights its icon).
    var isCustomized: Bool {
        self != ObjectsListOptions()
    }
}
