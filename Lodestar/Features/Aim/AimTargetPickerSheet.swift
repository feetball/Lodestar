import SwiftUI
import LodestarKit

/// Chooses what to aim at: quick picks, favorites and recent targets, and a search over the whole catalog.
struct AimTargetPickerSheet: View {
    let model: AimViewModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CelestialObject] = []
    /// The text `results` were found for, so "no matches" is not claimed for a text that has not been searched yet.
    @State private var searchedText = ""

    /// Longest search text accepted, in characters.
    private static let maximumQueryLength = 64
    private static let maximumResults = 30
    private static let maximumShortcuts = 6

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if isSearching {
                        searchResults
                    } else {
                        shortcuts
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.background)
        .foregroundStyle(palette.primaryText)
        .presentationBackground(palette.background)
        .task(id: query) {
            await search()
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedQuery.isEmpty }

    // MARK: Header and search

    private var header: some View {
        HStack {
            Text("Aim at")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.lodestarSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.tertiaryText)
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Search stars, planets, Messier, NGC\u{2026}").foregroundStyle(palette.tertiaryText))
                .textFieldStyle(.plain)
                .foregroundStyle(palette.primaryText)
                .tint(palette.accent)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Search objects")
                .onChange(of: query) { _, newValue in
                    if newValue.count > Self.maximumQueryLength {
                        query = String(newValue.prefix(Self.maximumQueryLength))
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.tertiaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.stroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
    }

    /// Looks the text up after a short pause, so typing does not search for every letter.
    private func search() async {
        let text = trimmedQuery
        guard !text.isEmpty else {
            results = []
            searchedText = ""
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        results = app.catalog.search(text, limit: Self.maximumResults).map(\.object)
        searchedText = text
    }

    // MARK: Content

    @ViewBuilder
    private var searchResults: some View {
        if results.isEmpty {
            if searchedText == trimmedQuery {
                Text("No matches for \u{201C}\(trimmedQuery)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 12)
            }
        } else {
            ForEach(results) { object in
                row(for: object)
            }
        }
    }

    @ViewBuilder
    private var shortcuts: some View {
        sectionTitle("Quick picks")
        AimFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(AimQuickPicks.picks(catalog: app.catalog, snapshot: model.skyContent?.snapshot, planetLimit: 5)) { pick in
                AimQuickPickButton(pick: pick) { choose(pick.object) }
            }
        }
        let favorites = objects(for: app.settings.favoriteObjectIDs)
        if !favorites.isEmpty {
            sectionTitle("Favorites")
            ForEach(favorites) { row(for: $0) }
        }
        let recents = objects(for: app.settings.recentObjectIDs).filter { recent in !favorites.contains { $0.id == recent.id } }
        if !recents.isEmpty {
            sectionTitle("Recent")
            ForEach(recents) { row(for: $0) }
        }
        sectionTitle("More")
        Button {
            app.selectedTab = .objects
            dismiss()
        } label: {
            Label("Browse all objects", systemImage: "sparkles")
        }
        .buttonStyle(.lodestarSecondary)
        if app.target != nil {
            Button {
                app.clearTarget()
                dismiss()
            } label: {
                Label("Clear target", systemImage: "xmark")
            }
            .buttonStyle(.lodestarSecondary)
        }
    }

    private func objects(for identifiers: [String]) -> [CelestialObject] {
        Array(identifiers.compactMap { app.catalog.object(id: $0) }.prefix(Self.maximumShortcuts))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(palette.secondaryText)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(for object: CelestialObject) -> some View {
        Button {
            choose(object)
        } label: {
            HStack(spacing: 12) {
                ObjectIcon(category: object.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(object.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(object.subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 8)
                if app.target?.id == object.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Current target")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func choose(_ object: CelestialObject) {
        app.select(target: object)
        dismiss()
    }
}
