import SwiftUI
#if DEBUG
import LodestarKit

extension RootView {
    /// In screenshot mode with a `screen=` that is not a sheet of the Aim tab: the host that opens it, in place of the
    /// tabs. `nil` otherwise (and always in a Release build, where `ScreenshotMode` does not exist).
    var reviewHost: AnyView? {
        guard let screen = ScreenshotMode.current?.screen, screen.usesHost else { return nil }
        if screen.isWidgets { return AnyView(ReviewWidgetsScreen(screen: screen)) }
        return AnyView(ReviewHost(screen: screen))
    }
}

/// The tab bar with one tab's navigation stack in it, opened on a screen (pushed) or with a sheet over it. The stack
/// registers the same destinations as the tab it stands for, so the screen is shown the way the app shows it, with its
/// navigation bar and the tab bar under it.
struct ReviewHost: View {
    let screen: ReviewScreen

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var events = EventsModel()
    @State private var path: [ReviewScreen]
    @State private var showsSkyline: Bool
    @State private var showsSiteEditor: Bool

    init(screen: ReviewScreen) {
        self.screen = screen
        _path = State(initialValue: screen.isPushed ? [screen] : [])
        _showsSkyline = State(initialValue: screen == .skyline)
        _showsSiteEditor = State(initialValue: screen == .siteEditor)
    }

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                tabContent(tab)
                    .nightHidesTabBar()
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .nightTabBar(selection: $app.selectedTab)
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        if tab == screen.tab {
            NavigationStack(path: $path) {
                Color.clear
                    .screenBackground(palette)
                    .navigationTitle(tab.title)
                    .navigationDestination(for: ReviewScreen.self) { target in
                        ReviewDestination(screen: target)
                    }
                    .navigationDestination(for: CelestialObject.self) { object in
                        ObjectDetailView(object: object)
                    }
                    .navigationDestination(for: SmallBodyListRoute.self) { _ in
                        SmallBodyListView()
                    }
                    .eventsDestinations()
            }
            .environment(events)
            .fullScreenCover(isPresented: $showsSkyline) {
                if let site = app.settings.savedSites.first {
                    HorizonRecordView(site: site, app: app)
                        .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
                }
            }
            .sheet(isPresented: $showsSiteEditor) {
                if let site = app.settings.savedSites.first {
                    SettingsSheetRoot {
                        SiteEditor(target: .existing(site))
                    }
                }
            }
        } else {
            Color.clear
                .screenBackground(palette)
        }
    }
}

/// The screen a pushed `ReviewScreen` stands for.
private struct ReviewDestination: View {
    let screen: ReviewScreen

    var body: some View {
        switch screen {
        case .eventsCalendar:
            EventsCalendarView()
        case .event(let kind):
            ReviewEventDetail(kind: kind)
        case .cometsList, .asteroidsList:
            SmallBodyListView()
        case .cometDetail:
            ReviewObjectDetail(id: "comet.161P")
        case .asteroidDetail:
            ReviewObjectDetail(id: "asteroid.4")
        case .starTrails, .timeLapse:
            ToolsStarTrailsView()
        case .satellitePasses:
            ReviewSatellitePasses()
        case .satellitePassDetail:
            ReviewSatellitePassDetail()
        case .mountConnection, .mountConnected, .mountSkyWatcher, .mountSkyWatcherEquatorial, .mountSkyWatcherConnected,
             .mountSkyWatcherAligned1, .mountSkyWatcherAligned2:
            MountConnectionView()
        default:
            EmptyView()
        }
    }
}

/// The satellite passes list, with a board of its own.
private struct ReviewSatellitePasses: View {
    @Environment(AppModel.self) private var app
    @State private var board = SatellitePassBoard()

    var body: some View {
        SatellitePassesView(board: board)
            .task(id: app.online.satellites.generation) {
                await board.keepCurrent(app: app, observer: app.observerContext?.observer)
            }
    }
}

/// The detail screen of the first pass of the ISS (or of whatever comes first).
private struct ReviewSatellitePassDetail: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var board = SatellitePassBoard()

    var body: some View {
        Group {
            if let items = board.items, let item = items.first(where: \.isISS) ?? items.first {
                SatellitePassDetailView(item: item)
            } else {
                ProgressView()
                    .tint(palette.accent)
                    .screenBackground(palette)
            }
        }
        .task(id: app.online.satellites.generation) {
            await board.keepCurrent(app: app, observer: app.observerContext?.observer)
        }
    }
}

/// The detail screen of the first upcoming event of a kind, worked out the way the calendar does.
private struct ReviewEventDetail: View {
    let kind: EventKind

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var entry: EventsEntry?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let entry {
                EventsDetailView(entry: entry)
            } else if isMissing {
                Text("No \(kind.displayName.lowercased()) in the next twelve months.")
                    .foregroundStyle(palette.secondaryText)
                    .screenBackground(palette)
            } else {
                ProgressView()
                    .tint(palette.accent)
                    .screenBackground(palette)
            }
        }
        .task {
            guard let context = app.observerContext else { return }
            let now = app.clock.now
            let key = EventsKey(context: context, now: now)
            let entries = await Task.detached(priority: .userInitiated) {
                EventsCalculator.entries(for: key)
            }.value
            entry = entries.first { $0.event.kind == kind && $0.event.date >= now }
            isMissing = entry == nil
        }
    }
}

/// The detail screen of the catalog object with `id`, once the catalog has loaded.
private struct ReviewObjectDetail: View {
    let id: String

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var object: CelestialObject?

    var body: some View {
        Group {
            if let object {
                ObjectDetailView(object: object)
            } else {
                ProgressView()
                    .tint(palette.accent)
                    .screenBackground(palette)
            }
        }
        .task {
            await app.catalog.load()
            object = app.catalog.object(id: id)
        }
    }
}
#else
extension RootView {
    /// The review host exists in Debug builds only.
    var reviewHost: AnyView? { nil }
}
#endif
