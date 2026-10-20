import Foundation

/// The text of the Help screens, by group. Each group is written in a file of its own (`HelpContent+Start.swift`,
/// `HelpContent+Sky.swift`, `HelpContent+More.swift`); this file puts them in the order of the list.
enum HelpContent {
    /// Every topic, in the order the list shows them within each category.
    static let all: [HelpTopic] = start + sky + more

    /// The topic with this id.
    static func topic(_ id: HelpTopic.ID) -> HelpTopic {
        // Every id has a topic in the files of the groups; one that was forgotten falls back to the first topic.
        all.first { $0.topic == id } ?? all[0]
    }

    /// The topics of `category`.
    static func topics(in category: HelpCategory) -> [HelpTopic] {
        all.filter { $0.category == category }
    }
}
