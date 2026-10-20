import SwiftUI

// MARK: - The list

/// The help center: every topic by group, with a search over their text.
struct HelpView: View {
    private static let supportURL = URL(string: "https://feetball.github.io/Lodestar/support.html")
    private static let issuesURL = URL(string: "https://github.com/feetball/Lodestar/issues")

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            if trimmedQuery.isEmpty {
                ForEach(HelpCategory.allCases) { category in
                    let topics = HelpContent.topics(in: category)
                    if !topics.isEmpty {
                        SettingsSection(title: category.title) {
                            ForEach(topics) { topic in
                                NavigationLink {
                                    HelpTopicView(topic: topic)
                                } label: {
                                    HelpTopicRow(topic: topic)
                                }
                            }
                        }
                    }
                }
                supportSection
            } else {
                searchResults
            }
        }
        .themedList(palette)
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search help")
    }

    @ViewBuilder
    private var searchResults: some View {
        let matches = HelpContent.all.filter { $0.matches(trimmedQuery) }
        if matches.isEmpty {
            SettingsSection(title: "No Results") {
                Text("No help page mentions \u{201C}\(trimmedQuery)\u{201D}. Try a shorter or simpler word.")
                    .foregroundStyle(palette.secondaryText)
            }
        } else {
            SettingsSection(title: matches.count == 1 ? "1 Result" : "\(matches.count) Results") {
                ForEach(matches) { topic in
                    NavigationLink {
                        HelpTopicView(topic: topic)
                    } label: {
                        HelpTopicRow(topic: topic)
                    }
                }
            }
        }
    }

    private var supportSection: some View {
        SettingsSection(title: "Still Stuck?", footer: "Links open in Safari.") {
            linkRow("Support Website", systemImage: "globe", url: Self.supportURL)
            linkRow("Report a Problem", systemImage: "exclamationmark.bubble", url: Self.issuesURL)
        }
    }

    private func linkRow(_ title: String, systemImage: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(palette.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint("Opens a web page in Safari")
    }
}

/// A topic in a list: its symbol, title and one-line summary.
private struct HelpTopicRow: View {
    @Environment(\.palette) private var palette
    let topic: HelpTopic

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: topic.systemImage)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .foregroundStyle(palette.primaryText)
                Text(topic.summary)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A topic

/// One help page: its text, and the pages to read next.
struct HelpTopicView: View {
    @Environment(\.palette) private var palette
    let topic: HelpTopic
    /// Whether the end of the page leads to the list of all topics (for a page opened from a button on a screen).
    var offersAllTopics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    HelpBlockView(block: block)
                }
                relatedTopics
                if offersAllTopics {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("All Help Topics", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.lodestarSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground(palette)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: topic.systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(topic.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var relatedTopics: some View {
        let related = topic.related.map { HelpContent.topic($0) }.filter { $0.topic != topic.topic }
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(title: "Read Next", systemImage: "book")
                ForEach(related) { next in
                    NavigationLink {
                        HelpTopicView(topic: next)
                    } label: {
                        HStack {
                            Label(next.title, systemImage: next.systemImage)
                                .foregroundStyle(palette.primaryText)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(palette.tertiaryText)
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(palette.stroke, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One block of a topic, drawn in the palette.
private struct HelpBlockView: View {
    @Environment(\.palette) private var palette
    let block: HelpBlock

    var body: some View {
        switch block {
        case .paragraph(let string):
            text(string)
        case .steps(let items):
            steps(items)
        case .bullets(let items):
            bullets(items)
        case .tip(let string):
            callout(string, title: "Tip", systemImage: "lightbulb", color: palette.accent)
        case .caution(let string):
            callout(string, title: "Careful", systemImage: "exclamationmark.triangle.fill", color: palette.warning)
        case .terms(let terms):
            glossary(terms)
        }
    }

    /// Text with `**bold**` and `*italic*` drawn as such.
    private func text(_ string: String, font: Font = .body, color: Color? = nil) -> some View {
        Text(LocalizedStringKey(string))
            .font(font)
            .foregroundStyle(color ?? palette.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(palette.accent))
                    text(item)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\u{2022}")
                        .font(.body.weight(.bold))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                    text(item)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func callout(_ string: String, title: String, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            text(string, font: .subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette, padding: 12)
        .accessibilityElement(children: .combine)
    }

    private func glossary(_ terms: [HelpTerm]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(terms, id: \.self) { term in
                VStack(alignment: .leading, spacing: 2) {
                    Text(term.term)
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    text(term.meaning, font: .subheadline, color: palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }
}

// MARK: - From a screen

/// Help presented over a screen: the page that belongs to it, with the way to all the others.
struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let topic: HelpTopic.ID

    var body: some View {
        SettingsSheetRoot {
            NavigationStack {
                HelpTopicView(topic: HelpContent.topic(topic), offersAllTopics: true)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }
}

/// A button that opens the help page that belongs to the screen it is on.
struct HelpButton: View {
    enum Appearance {
        /// A plain symbol, for a navigation bar.
        case toolbar
        /// A plain symbol padded to the minimum touch target, for use outside a navigation bar.
        case inline
        /// A round chip like the status chips of the Aim screen.
        case chip
    }

    @Environment(\.palette) private var palette
    let topic: HelpTopic.ID
    var appearance = Appearance.toolbar
    /// Opens the page through a presenter further up instead of the button's own sheet: needed where the button sits
    /// in a view that is rebuilt while the page is open, or next to other sheets of the same screen.
    var action: (() -> Void)? = nil
    @State private var isShowing = false

    var body: some View {
        Button {
            if let action {
                action()
            } else {
                isShowing = true
            }
        } label: {
            switch appearance {
            case .toolbar:
                Image(systemName: "questionmark.circle")
            case .inline:
                Image(systemName: "questionmark.circle")
                    // Padded to the minimum touch target.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            case .chip:
                Image(systemName: "questionmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(palette.secondaryText)
                    .background(Circle().fill(palette.surface.opacity(0.85)))
                    .overlay(Circle().strokeBorder(palette.secondaryText.opacity(0.45), lineWidth: 0.75))
                    // Padded to the minimum touch target.
                    .padding(9)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel("Help")
        .accessibilityHint("Explains this screen")
        .sheet(isPresented: $isShowing) {
            HelpSheet(topic: topic)
        }
    }
}
