import Foundation
import XCTest
@testable import AppCore

/// The Help topics: that the content is whole and consistent, and how a search matches a topic.
final class SettingsHelpContentTests: XCTestCase {
    /// Every topic id, in the order of the list (the files "Start", "Sky" and "More", in that order).
    private let expectedOrder: [HelpTopic.ID] = [
        .gettingStarted, .mounting, .aimScreen, .alignment, .compassAndGyro,
        .objects, .skyChart, .tonight, .events, .planFraming, .mosaic, .trailsAndExposure, .skyline,
        .mounts, .nightMode, .onlineData, .widgets, .troubleshooting, .glossary,
    ]

    /// Every string a block shows.
    private func strings(in block: HelpBlock) -> [String] {
        switch block {
        case .paragraph(let text), .tip(let text), .caution(let text): return [text]
        case .steps(let items), .bullets(let items): return items
        case .terms(let terms): return terms.flatMap { [$0.term, $0.meaning] }
        }
    }

    private func allStrings(in topic: HelpTopic) -> [String] {
        [topic.title, topic.summary] + topic.keywords + topic.blocks.flatMap(strings(in:))
    }

    private func sample(blocks: [HelpBlock] = [], keywords: [String] = []) -> HelpTopic {
        HelpTopic(topic: .glossary, category: .more, title: "Alpha Title", systemImage: "star", summary: "Beta summary",
                  keywords: keywords, blocks: blocks, related: [])
    }

    // MARK: The list of topics

    func testTheTopicsAreInTheOrderOfTheListAndEveryIdHasOne() {
        XCTAssertEqual(HelpContent.all.map(\.topic), expectedOrder)
        XCTAssertEqual(HelpContent.all.count, 19)
        XCTAssertEqual(Set(HelpContent.all.map(\.topic)).count, 19, "a topic id appears twice")
    }

    func testTheGroupsHoldTheirTopicsInOrder() {
        XCTAssertEqual(HelpContent.start.map(\.topic), [.gettingStarted, .mounting, .aimScreen, .alignment, .compassAndGyro])
        XCTAssertEqual(HelpContent.sky.map(\.topic),
                       [.objects, .skyChart, .tonight, .events, .planFraming, .mosaic, .trailsAndExposure, .skyline])
        XCTAssertEqual(HelpContent.more.map(\.topic), [.mounts, .nightMode, .onlineData, .widgets, .troubleshooting, .glossary])
        XCTAssertEqual(HelpContent.all, HelpContent.start + HelpContent.sky + HelpContent.more)
    }

    func testLookingUpATopicByIdReturnsThatTopic() {
        for id in expectedOrder {
            let topic = HelpContent.topic(id)
            XCTAssertEqual(topic.topic, id)
            XCTAssertEqual(topic.id, id)
        }
        XCTAssertEqual(HelpContent.topic(.glossary).title, "Glossary")
        XCTAssertEqual(HelpContent.topic(.gettingStarted).title, "Your first night")
    }

    func testTopicTitlesAreUnique() {
        let titles = HelpContent.all.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testTopicSystemImagesAreNotEmpty() {
        for topic in HelpContent.all {
            XCTAssertFalse(topic.systemImage.trimmingCharacters(in: .whitespaces).isEmpty, "\(topic.topic) has no symbol")
        }
    }

    // MARK: Categories

    func testEveryCategoryHasATitleAndTopics() {
        XCTAssertEqual(HelpCategory.allCases, [.start, .aiming, .sky, .planning, .equipment, .more])
        for category in HelpCategory.allCases {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(HelpContent.topics(in: category).isEmpty, "\(category) has no topic")
        }
    }

    func testCategoryTitlesAndIds() {
        XCTAssertEqual(HelpCategory.allCases.map(\.title),
                       ["Get started", "Aiming", "Sky and objects", "Planning a picture", "Equipment", "More"])
        XCTAssertEqual(HelpCategory.allCases.map(\.id), ["start", "aiming", "sky", "planning", "equipment", "more"])
        XCTAssertEqual(Set(HelpCategory.allCases.map(\.title)).count, 6)
    }

    func testEachCategoryListsItsTopicsInTheOrderOfTheList() {
        XCTAssertEqual(HelpContent.topics(in: .start).map(\.topic), [.gettingStarted, .mounting])
        XCTAssertEqual(HelpContent.topics(in: .aiming).map(\.topic), [.aimScreen, .alignment, .compassAndGyro])
        XCTAssertEqual(HelpContent.topics(in: .sky).map(\.topic), [.objects, .skyChart, .tonight, .events])
        XCTAssertEqual(HelpContent.topics(in: .planning).map(\.topic), [.planFraming, .mosaic, .trailsAndExposure, .skyline])
        XCTAssertEqual(HelpContent.topics(in: .equipment).map(\.topic), [.mounts])
        XCTAssertEqual(HelpContent.topics(in: .more).map(\.topic), [.nightMode, .onlineData, .widgets, .troubleshooting, .glossary])
    }

    func testTheCategoriesTogetherCoverEveryTopicOnce() {
        let covered = HelpCategory.allCases.flatMap { HelpContent.topics(in: $0).map(\.topic) }
        XCTAssertEqual(covered.count, 19)
        XCTAssertEqual(Set(covered), Set(expectedOrder))
    }

    // MARK: Completeness

    func testEveryTopicHasATitleASummaryKeywordsAndBlocks() {
        for topic in HelpContent.all {
            XCTAssertFalse(topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(topic.topic) title")
            XCTAssertFalse(topic.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(topic.topic) summary")
            XCTAssertFalse(topic.keywords.isEmpty, "\(topic.topic) keywords")
            XCTAssertFalse(topic.blocks.isEmpty, "\(topic.topic) blocks")
            XCTAssertFalse(topic.related.isEmpty, "\(topic.topic) related topics")
        }
    }

    func testNoKeywordIsEmpty() {
        for topic in HelpContent.all {
            for keyword in topic.keywords {
                XCTAssertFalse(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(topic.topic) has an empty keyword")
            }
        }
    }

    func testNoBlockIsEmpty() {
        for topic in HelpContent.all {
            for block in topic.blocks {
                switch block {
                case .steps(let items), .bullets(let items):
                    XCTAssertFalse(items.isEmpty, "\(topic.topic) has a list without items")
                case .terms(let terms):
                    XCTAssertFalse(terms.isEmpty, "\(topic.topic) has a glossary without terms")
                case .paragraph, .tip, .caution:
                    break
                }
                for text in strings(in: block) {
                    XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(topic.topic) has an empty text")
                }
            }
        }
    }

    func testEveryTopicStartsWithAParagraph() {
        for topic in HelpContent.all {
            guard case .paragraph? = topic.blocks.first else {
                XCTFail("\(topic.topic) does not open with a paragraph")
                continue
            }
        }
    }

    func testBoldAndItalicMarkersAreBalanced() {
        for topic in HelpContent.all {
            for text in allStrings(in: topic) {
                let bold = text.components(separatedBy: "**").count - 1
                XCTAssertEqual(bold % 2, 0, "unbalanced ** in \(topic.topic): \(text.prefix(60))")
                let italic = text.replacingOccurrences(of: "**", with: "").filter { $0 == "*" }.count
                XCTAssertEqual(italic % 2, 0, "unbalanced * in \(topic.topic): \(text.prefix(60))")
            }
        }
    }

    func testTheFirstNightTopicListsTheFiveStepsItPromises() throws {
        let topic = HelpContent.topic(.gettingStarted)
        XCTAssertTrue(topic.summary.hasPrefix("Five steps"))
        let steps = topic.blocks.compactMap { block -> [String]? in
            if case .steps(let items) = block { return items }
            return nil
        }
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?.count, 5)
    }

    func testTheGlossaryIsInAlphabeticalOrderAsItSays() throws {
        let topic = HelpContent.topic(.glossary)
        let terms = topic.blocks.flatMap { block -> [HelpTerm] in
            if case .terms(let terms) = block { return terms }
            return []
        }
        XCTAssertGreaterThanOrEqual(terms.count, 10)
        let names = terms.map { $0.term.lowercased() }
        XCTAssertEqual(names, names.sorted(), "the glossary says it is in alphabetical order")
        XCTAssertEqual(Set(names).count, names.count, "a glossary term is defined twice")
    }

    // MARK: Related topics

    func testRelatedTopicsPointToExistingOtherTopics() {
        let known = Set(HelpContent.all.map(\.topic))
        for topic in HelpContent.all {
            for related in topic.related {
                XCTAssertTrue(known.contains(related), "\(topic.topic) points to a missing topic")
                XCTAssertNotEqual(related, topic.topic, "\(topic.topic) points to itself")
                XCTAssertEqual(HelpContent.topic(related).topic, related)
            }
            XCTAssertEqual(Set(topic.related).count, topic.related.count, "\(topic.topic) lists a related topic twice")
        }
    }

    // MARK: Search

    func testAnEmptyOrSymbolOnlyQueryMatchesEveryTopic() {
        for query in ["", "   ", "!?", " - , . "] {
            XCTAssertEqual(HelpContent.all.filter { $0.matches(query) }.count, 19, "query \"\(query)\"")
        }
    }

    func testAQueryMatchesTheTitleTheSummaryAndTheKeywords() {
        let topic = sample(keywords: ["gamma", "delta"])
        XCTAssertTrue(topic.matches("alpha"))
        XCTAssertTrue(topic.matches("summary"))
        XCTAssertTrue(topic.matches("gamma"))
        XCTAssertTrue(topic.matches("delta"))
        XCTAssertFalse(topic.matches("omicron"))
    }

    func testAQueryMatchesTheTextOfEveryKindOfBlock() {
        let topic = sample(blocks: [
            .paragraph("epsilon paragraph"),
            .steps(["zeta first", "eta second"]),
            .bullets(["theta point", "iota point"]),
            .tip("kappa tip"),
            .caution("lambda caution"),
            .terms([HelpTerm(term: "mu term", meaning: "nu meaning")]),
        ])
        for word in ["epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "meaning"] {
            XCTAssertTrue(topic.matches(word), word)
        }
        XCTAssertFalse(topic.matches("xi"))
    }

    func testEveryWordOfTheQueryHasToAppear() {
        let topic = sample(blocks: [.paragraph("epsilon")], keywords: ["gamma"])
        XCTAssertTrue(topic.matches("alpha gamma epsilon"))
        XCTAssertFalse(topic.matches("alpha gamma omicron"))
    }

    func testAQueryIsCaseInsensitive() {
        let topic = sample(blocks: [.paragraph("Epsilon")])
        XCTAssertTrue(topic.matches("ALPHA"))
        XCTAssertTrue(topic.matches("epSILon"))
    }

    func testAQueryMatchesPartOfAWord() {
        XCTAssertTrue(sample().matches("alph"))
        XCTAssertTrue(sample().matches("itle"))
    }

    func testPunctuationAndSpacesBetweenQueryWordsDoNotMatter() {
        let topic = sample(keywords: ["gamma", "delta"])
        XCTAssertTrue(topic.matches("gamma, delta"))
        XCTAssertTrue(topic.matches("  gamma---delta!! "))
        XCTAssertTrue(topic.matches("alpha/gamma"))
    }

    func testDigitsCountAsQueryWords() {
        let topic = sample(blocks: [.paragraph("Zoom steps through 100 and 60 degrees")])
        XCTAssertTrue(topic.matches("100"))
        XCTAssertTrue(topic.matches("60 degrees"))
        XCTAssertFalse(topic.matches("200"))
    }

    func testSearchingTheRealContent() {
        // "wobble" appears once, in a bullet of the mounting topic.
        XCTAssertEqual(HelpContent.all.filter { $0.matches("wobble") }.map(\.topic), [.mounting])
        // A keyword that is not in the text.
        XCTAssertTrue(HelpContent.topic(.gettingStarted).matches("walkthrough"))
        // Words from the title, however they are punctuated.
        XCTAssertTrue(HelpContent.topic(.compassAndGyro).matches("Gyro-Lock"))
        XCTAssertTrue(HelpContent.topic(.compassAndGyro).matches("compass gyro accuracy"))
        XCTAssertFalse(HelpContent.all.contains { $0.matches("qqzzxxvv") })
        XCTAssertFalse(HelpContent.topic(.glossary).matches("wobble"))
    }

    func testEveryTopicIsFoundBySearchingItsOwnTitle() {
        for topic in HelpContent.all {
            XCTAssertTrue(topic.matches(topic.title), "\(topic.topic) is not found by its own title")
            XCTAssertTrue(topic.matches(topic.summary), "\(topic.topic) is not found by its own summary")
        }
    }

    // MARK: Blocks and topics

    func testSearchableTextOfEachKindOfBlock() {
        XCTAssertEqual(HelpBlock.paragraph("one two").searchableText, "one two")
        XCTAssertEqual(HelpBlock.tip("a tip").searchableText, "a tip")
        XCTAssertEqual(HelpBlock.caution("a caution").searchableText, "a caution")
        XCTAssertEqual(HelpBlock.steps(["first", "second"]).searchableText, "first second")
        XCTAssertEqual(HelpBlock.bullets(["x", "y", "z"]).searchableText, "x y z")
        XCTAssertEqual(HelpBlock.terms([HelpTerm(term: "Zenith", meaning: "Overhead"), HelpTerm(term: "Nadir", meaning: "Below")]).searchableText,
                       "Zenith Overhead Nadir Below")
        XCTAssertEqual(HelpBlock.steps([]).searchableText, "")
    }

    func testATopicIsIdentifiedByItsTopicId() {
        XCTAssertEqual(sample().id, .glossary)
        XCTAssertEqual(sample(), sample())
        XCTAssertNotEqual(sample(keywords: ["a"]), sample(keywords: ["b"]))
        XCTAssertEqual(HelpTerm(term: "a", meaning: "b"), HelpTerm(term: "a", meaning: "b"))
        XCTAssertNotEqual(HelpTerm(term: "a", meaning: "b"), HelpTerm(term: "a", meaning: "c"))
    }
}
