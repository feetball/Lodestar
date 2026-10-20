import Foundation

/// One piece of a help topic.
enum HelpBlock: Hashable {
    /// A paragraph; `**bold**` and `*italic*` are drawn as such.
    case paragraph(String)
    /// Numbered steps.
    case steps([String])
    case bullets([String])
    /// A hint worth remembering.
    case tip(String)
    /// Something that goes wrong when it is ignored.
    case caution(String)
    /// Terms with their meanings, for the glossary.
    case terms([HelpTerm])

    /// Every word the block shows, for the search.
    var searchableText: String {
        switch self {
        case .paragraph(let text), .tip(let text), .caution(let text): return text
        case .steps(let items), .bullets(let items): return items.joined(separator: " ")
        case .terms(let terms): return terms.map { "\($0.term) \($0.meaning)" }.joined(separator: " ")
        }
    }
}

/// A word of the glossary and what it means.
struct HelpTerm: Hashable {
    let term: String
    let meaning: String
}

/// A group of topics in the list.
enum HelpCategory: String, CaseIterable, Identifiable {
    case start, aiming, sky, planning, equipment, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Get started"
        case .aiming: return "Aiming"
        case .sky: return "Sky and objects"
        case .planning: return "Planning a picture"
        case .equipment: return "Equipment"
        case .more: return "More"
        }
    }
}

/// A help page: what it is for, and what it says.
struct HelpTopic: Identifiable, Hashable {
    /// Stable, so a screen can ask for its own topic.
    enum ID: String, Hashable {
        case gettingStarted, mounting, aimScreen, alignment, compassAndGyro
        case objects, skyChart, planFraming, tonight, events
        case mosaic, trailsAndExposure, skyline
        case mounts, nightMode, onlineData, widgets
        case troubleshooting, glossary
    }

    let topic: ID
    let category: HelpCategory
    let title: String
    let systemImage: String
    /// One line for the list.
    let summary: String
    /// More words people may search for.
    let keywords: [String]
    let blocks: [HelpBlock]
    /// Topics worth reading next.
    let related: [ID]

    var id: ID { topic }

    /// Whether the topic answers a search for `query` (every word of it has to appear somewhere in the topic).
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !words.isEmpty else { return true }
        let haystack = ([title, summary] + keywords + blocks.map(\.searchableText)).joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}
