import SwiftUI
import LodestarKit

/// The latest catalog search and the query it answers.
private struct ObjectsSearchOutcome {
    static let empty = ObjectsSearchOutcome(query: "", objects: [])

    let query: String
    let objects: [CelestialObject]
}

/// Identifies one search: a new query, or the catalog becoming available, starts a new one.
private struct ObjectsSearchKey: Equatable {
    let query: String
    let isCatalogReady: Bool
}

/// Identifies one position-tracking run: another observer or skyline, another catalog, another catalogue list, other
/// off-list objects or leaving the tab restart it.
private struct ObjectsTrackingKey: Equatable {
    let observer: Observer?
    let skyline: HorizonProfile?
    let catalogID: ObjectIdentifier?
    let catalogue: ObjectsCatalogueFilter
    let extraIDs: [String]
    let isTabSelected: Bool
}

/// The Objects tab: browse and search everything Lodestar can aim at, see where it is in the sky now, and
/// choose a target. Rows open `ObjectDetailView`; swipes favorite an object or aim at it.
struct ObjectsView: View {
    /// The most search results shown.
    private static let searchResultLimit = 50
    /// How long typing must pause before the catalog is searched.
    private static let searchDebounce: Duration = .milliseconds(150)

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    @AppStorage("lodestar.objects.grouping") private var grouping = ObjectsGrouping.type
    @AppStorage("lodestar.objects.sortOrder") private var sortOrder = ObjectsSortOrder.name
    @AppStorage("lodestar.objects.aboveHorizonOnly") private var showsOnlyAboveHorizon = false
    @AppStorage("lodestar.objects.hideFaint") private var hidesFaintObjects = false
    @AppStorage("lodestar.objects.catalogue") private var catalogueFilter = ObjectsCatalogueFilter.all
    @AppStorage("lodestar.objects.popularOnly") private var showsOnlyPopular = false

    @State private var query = ""
    @State private var searchOutcome = ObjectsSearchOutcome.empty
    @State private var path: [CelestialObject] = []
    @State private var isShowingCustomTarget = false
    @State private var catalogIndex: ObjectsCatalogIndex?
    @State private var positions = ObjectsPositionModel()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Objects")
                .navigationDestination(for: CelestialObject.self) { object in
                    ObjectDetailView(object: object)
                }
                .nightSearchable(text: $query, prompt: "Name, M31, NGC 7000") { nightSearchRow }
                .nightInlineTitle()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .toolbar {
                    if !usesNightControls { toolbarContent }
                }
        }
        .sheet(isPresented: $isShowingCustomTarget) {
            CustomTargetSheet()
                .environment(app)
                .themedRoot(palette, redFilter: app.settings.redFilterOverlay)
        }
        .task {
            await app.catalog.load()
        }
        .task(id: catalogID) {
            await buildCatalogIndex()
        }
        .task(id: searchKey) {
            await search()
        }
        .task(id: trackingKey) {
            await trackPositions()
        }
        .onChange(of: catalogueFilter) { _, newFilter in
            // A catalogue is read by number; the other lists by name.
            if newFilter != .all, sortOrder == .name {
                sortOrder = .number
            } else if newFilter == .all, sortOrder == .number {
                sortOrder = .name
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let catalog = app.catalog.catalog, let catalogIndex {
            list(catalog: catalog, index: catalogIndex)
        } else if case .failed(let message) = app.catalog.loadState {
            EmptyStateView(title: "Catalog Unavailable", systemImage: "exclamationmark.triangle", message: message) {
                Button("Try Again") {
                    Task { await app.catalog.load() }
                }
                .buttonStyle(.lodestarPrimary)
            }
            .screenBackground(palette)
        } else {
            ObjectsLoadingView()
        }
    }

    private func list(catalog: Catalog, index: ObjectsCatalogIndex) -> some View {
        let sections = displayedSections(catalog: catalog, index: index)
        let favorites = Set(app.settings.favoriteObjectIDs)
        let timeZone = app.observerContext?.timeZone ?? .autoupdatingCurrent
        let showsProminence = catalogueFilter != .all || sortOrder == .prominence || grouping == .prominence
        return List {
            if !isShowingResults {
                Section {
                    ObjectsCatalogueChips(selection: $catalogueFilter)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if app.observerContext == nil, !isShowingResults {
                Section {
                    ObjectsLocationNotice()
                        .listRowBackground(palette.surface)
                }
            } else if hasSkyline, !isShowingResults {
                Section {
                    ObjectsSkylineNotice()
                        .listRowBackground(palette.surface)
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.objects) { object in
                        row(for: object, isFavorite: favorites.contains(object.id), timeZone: timeZone,
                            showsProminence: showsProminence)
                    }
                    // Favorite comets and asteroids without a current orbit stay in the list.
                    ForEach(section.unavailable, id: \.self) { id in
                        SmallBodyNoOrbitRow(id: id) { app.settingsStore.toggleFavorite(id) }
                    }
                } header: {
                    ObjectsSectionHeader(title: section.title, systemImage: section.systemImage,
                                         count: section.objects.count + section.unavailable.count)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .themedList(palette)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if sections.isEmpty {
                emptyState
            }
        }
    }

    private func row(for object: CelestialObject, isFavorite: Bool, timeZone: TimeZone,
                      showsProminence: Bool) -> some View {
        Button {
            path.append(object)
        } label: {
            HStack(spacing: 8) {
                ObjectRow(object: object, position: positions.position(for: object.id), isFavorite: isFavorite,
                          timeZone: timeZone, showsProminence: showsProminence)
                // The system's disclosure indicator is grey, which is not night-safe.
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(ObjectsRowButtonStyle())
        .accessibilityHint("Shows details")
        .listRowInsets(EdgeInsets())
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.stroke)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            favoriteAction(for: object, isFavorite: isFavorite)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            aimAction(for: object)
        }
    }

    private func favoriteAction(for object: CelestialObject, isFavorite: Bool) -> some View {
        Button {
            app.settingsStore.toggleFavorite(object.id)
        } label: {
            ObjectsSwipeGlyph.image(systemName: isFavorite ? "star.slash.fill" : "star.fill", color: palette.accent)
        }
        .tint(palette.surfaceRaised)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func aimAction(for object: CelestialObject) -> some View {
        Button {
            app.aim(at: object)
        } label: {
            ObjectsSwipeGlyph.image(systemName: "scope", color: palette.onAccent)
        }
        .tint(palette.accent)
        .accessibilityLabel("Aim at \(SmallBodyText.displayName(object))")
    }

    @ViewBuilder
    private var emptyState: some View {
        if isShowingResults {
            EmptyStateView(title: "No Results", systemImage: "magnifyingglass",
                           message: "Nothing in the catalog matches \u{201C}\(searchOutcome.query)\u{201D}. "
                               + "You can aim at any position with a custom target.") {
                Button("Add Custom Target") {
                    isShowingCustomTarget = true
                }
                .buttonStyle(.lodestarSecondary)
            }
        } else {
            EmptyStateView(title: "Nothing to Show", systemImage: "line.3.horizontal.decrease.circle",
                           message: "No objects match the current filters.") {
                Button("Reset Filters") {
                    showsOnlyAboveHorizon = false
                    hidesFaintObjects = false
                    showsOnlyPopular = false
                    catalogueFilter = .all
                }
                .buttonStyle(.lodestarSecondary)
            }
        }
    }

    /// Whether the night controls take the place of the system search field and toolbar buttons (iOS 26, night, `ctl`).
    private var usesNightControls: Bool { NightChrome.isActive("ctl", night: palette.isNight) }

    /// The night search row: the search field with the buttons of the toolbar beside it, drawn in the palette.
    private var nightSearchRow: some View {
        HStack(spacing: 8) {
            NightSearchField(text: $query, prompt: "Name, M31, NGC 7000")
            Button {
                isShowingCustomTarget = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Custom Target")
            ObjectsOptionsMenu(grouping: $grouping, sortOrder: $sortOrder,
                               showsOnlyAboveHorizon: $showsOnlyAboveHorizon, hidesFaintObjects: $hidesFaintObjects,
                               showsOnlyPopular: $showsOnlyPopular, isCustomized: options.isCustomized,
                               hasLocation: app.observerContext != nil)
                .disabled(isSearching)
            HelpButton(topic: .objects, appearance: .inline)
                .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(palette.background)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                isShowingCustomTarget = true
            } label: {
                Label("Custom Target", systemImage: "plus")
            }
            ObjectsOptionsMenu(grouping: $grouping, sortOrder: $sortOrder,
                               showsOnlyAboveHorizon: $showsOnlyAboveHorizon, hidesFaintObjects: $hidesFaintObjects,
                               showsOnlyPopular: $showsOnlyPopular, isCustomized: options.isCustomized, hasLocation: app.observerContext != nil)
                .disabled(isSearching)
            HelpButton(topic: .objects)
        }
    }

    // MARK: Derived state

    private var options: ObjectsListOptions {
        ObjectsListOptions(grouping: grouping, sortOrder: sortOrder, showsOnlyAboveHorizon: showsOnlyAboveHorizon,
                           hidesFaintObjects: hidesFaintObjects, catalogue: catalogueFilter,
                           showsOnlyPopular: showsOnlyPopular)
    }

    /// The site's recorded skyline, when it has one.
    private var skyline: HorizonProfile? {
        ObjectsHorizon.skyline(of: app.observerContext)
    }

    private var hasSkyline: Bool {
        skyline != nil
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// Whether the list shows search results. It keeps showing what was there until the results for a new query
    /// arrive, so typing never flashes an empty list.
    private var isShowingResults: Bool {
        !searchOutcome.query.isEmpty
    }

    private func displayedSections(catalog: Catalog, index: ObjectsCatalogIndex) -> [ObjectsListSection] {
        if isShowingResults {
            let results = ObjectsListSection(kind: .results, objects: searchOutcome.objects)
            return searchOutcome.objects.isEmpty ? [] : [results]
        }
        return ObjectsListBuilder.sections(options: options, catalog: catalog, index: index,
                                           favoriteIDs: app.settings.favoriteObjectIDs,
                                           recentIDs: app.settings.recentObjectIDs, positions: positions.positions)
    }

    /// Favorites, recents and search results that the browse listing does not include, whose positions are
    /// tracked in addition to the listed objects.
    private var offListObjects: [CelestialObject] {
        guard let catalog = app.catalog.catalog else { return [] }
        let candidates = (app.settings.favoriteObjectIDs + app.settings.recentObjectIDs)
            .compactMap { catalog.object(id: $0) } + searchOutcome.objects
        var seen = Set<String>()
        return candidates.filter { !$0.isListed && seen.insert($0.id).inserted }
    }

    /// The objects of the chosen catalogue that the browse listing does not include (the obscure ones), whose
    /// positions are tracked too.
    private var catalogueObjects: [CelestialObject] {
        guard catalogueFilter != .all, let catalog = app.catalog.catalog else { return [] }
        return catalogueFilter.objects(in: catalog).filter { !$0.isListed }
    }

    /// Changes when a different catalog becomes available.
    private var catalogID: ObjectIdentifier? {
        app.catalog.catalog.map { ObjectIdentifier($0) }
    }

    private var searchKey: ObjectsSearchKey {
        ObjectsSearchKey(query: trimmedQuery, isCatalogReady: app.catalog.catalog != nil)
    }

    private var trackingKey: ObjectsTrackingKey {
        ObjectsTrackingKey(observer: app.observerContext?.observer,
                           skyline: skyline,
                           catalogID: catalogID,
                           catalogue: catalogueFilter,
                           extraIDs: offListObjects.map(\.id),
                           isTabSelected: app.selectedTab == .objects)
    }

    // MARK: Tasks

    private func buildCatalogIndex() async {
        guard let catalog = app.catalog.catalog else {
            catalogIndex = nil
            return
        }
        catalogIndex = await Task.detached(priority: .userInitiated) {
            ObjectsCatalogIndex(catalog: catalog)
        }.value
    }

    /// Searches the catalog once typing pauses; clearing the field shows the browse list at once.
    private func search() async {
        let text = trimmedQuery
        guard !text.isEmpty else {
            searchOutcome = .empty
            return
        }
        try? await Task.sleep(for: Self.searchDebounce)
        guard !Task.isCancelled else { return }
        let results = app.catalog.search(text, limit: Self.searchResultLimit).map(\.object)
        searchOutcome = ObjectsSearchOutcome(query: text, objects: results)
    }

    /// Keeps positions fresh while the Objects tab is showing; other tabs do not need them.
    private func trackPositions() async {
        guard app.selectedTab == .objects else { return }
        guard let observer = app.observerContext?.observer else {
            positions.clear()
            return
        }
        await positions.keepFresh(observer: observer, skyline: skyline, clock: app.clock) {
            (app.catalog.catalog?.listedObjects ?? []) + offListObjects + catalogueObjects
        }
    }
}
