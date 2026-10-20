#if DEBUG
import Foundation
import LodestarKit

/// The sub-screens and sheets the visual review opens after launch (`-LodestarScreenshot screen=<name>`, see
/// `ScreenshotMode`). Compiled into Debug builds only.
///
/// Some are sheets of the Aim tab, which opens them itself (`aimSheet`); the others are pushed on, or presented from,
/// a navigation stack that `ReviewHost` builds around the tab they belong to.
enum ReviewScreen: Hashable {
    // The Aim tab with the mosaic planner or the GoTo mount sheet over it, or the Mount strip of its display.
    case mosaic
    case mountSheet
    case mountSheetSlewing
    case aimMount
    case aimMountSlewing
    // Tonight ▸ Upcoming events: the calendar and the detail screen of one kind of event.
    case eventsCalendar
    case event(EventKind)
    // The lists, and the detail screens of a comet and an asteroid.
    case cometsList
    case asteroidsList
    case cometDetail
    case asteroidDetail
    // Settings ▸ Tools and ▸ GoTo Mount.
    case starTrails
    case timeLapse
    case mountConnection
    case mountConnected
    // Settings ▸ Location: the skyline recorder (full screen) and the site editor (a sheet).
    case skyline
    case siteEditor
    // The Sky-Watcher mount: Settings ▸ Mount Control with the kind chosen (and its home position drawings) or with the
    // simulated mount connected, not aligned and after one and two syncs; the Aim screen's mount sheet in the same
    // states, and with the sync confirmation open.
    case mountSkyWatcher
    case mountSkyWatcherEquatorial
    case mountSkyWatcherConnected
    case mountSkyWatcherAligned1
    case mountSkyWatcherAligned2
    case mountSkyWatcherSheet
    case mountSkyWatcherSheetAligned
    case mountSkyWatcherSync
    // Online data (with fixtures instead of downloads): the satellite passes list and one pass, Aim following a satellite
    // or waiting for its peak, and the explanation that comes before the first feed is switched on.
    case satellitePasses
    case satellitePassDetail
    case aimSatellite
    case aimSatellitePeak
    case onlineFirstTime
    // Settings ▸ Help: the list, and one page of it (`help-<topic id>`, such as "help-aimScreen").
    case help
    case helpTopic(HelpTopic.ID)
    // The widgets drawn at their sizes (the widget views are in the app only in the review build), by variant.
    case widgets
    case widgetsStates
    case widgetsLargeType
    case widgetsRed

    private static let named: [String: ReviewScreen] = [
        "mosaic": .mosaic, "mount-sheet": .mountSheet, "mount-sheet-slewing": .mountSheetSlewing,
        "aim-mount": .aimMount, "aim-mount-slewing": .aimMountSlewing,
        "events-calendar": .eventsCalendar,
        "comets-list": .cometsList, "asteroids-list": .asteroidsList,
        "comet-detail": .cometDetail, "asteroid-detail": .asteroidDetail,
        "star-trails": .starTrails, "time-lapse": .timeLapse,
        "mount-connection": .mountConnection, "mount-connected": .mountConnected,
        "skyline": .skyline, "site-editor": .siteEditor,
        "mount-sw": .mountSkyWatcher, "mount-sw-equatorial": .mountSkyWatcherEquatorial,
        "mount-sw-connected": .mountSkyWatcherConnected, "mount-sw-aligned-1": .mountSkyWatcherAligned1,
        "mount-sw-aligned-2": .mountSkyWatcherAligned2, "mount-sw-sheet": .mountSkyWatcherSheet,
        "mount-sw-sheet-aligned": .mountSkyWatcherSheetAligned, "mount-sw-sync": .mountSkyWatcherSync,
        "satellite-passes": .satellitePasses, "satellite-pass-detail": .satellitePassDetail,
        "aim-satellite": .aimSatellite, "aim-satellite-peak": .aimSatellitePeak, "online-first-time": .onlineFirstTime,
        "widgets": .widgets, "widgets-states": .widgetsStates, "widgets-large-type": .widgetsLargeType,
        "widgets-red": .widgetsRed, "help": .help,
    ]

    /// The screen called `name` (exactly), or `nil`. Events are "event-" and the engine's name of the kind, such as
    /// "event-meteorShower"; help pages are "help-" and the id of the topic, such as "help-aimScreen".
    init?(name: String) {
        if let screen = Self.named[name] {
            self = screen
        } else if name.hasPrefix("event-"), let kind = EventKind(rawValue: String(name.dropFirst("event-".count))) {
            self = .event(kind)
        } else if name.hasPrefix("help-"), let topic = HelpTopic.ID(rawValue: String(name.dropFirst("help-".count))) {
            self = .helpTopic(topic)
        } else {
            return nil
        }
    }

    /// The tab the screen belongs to.
    var tab: AppTab {
        switch self {
        case .mosaic, .mountSheet, .mountSheetSlewing, .aimMount, .aimMountSlewing, .mountSkyWatcherSheet,
             .mountSkyWatcherSheetAligned, .mountSkyWatcherSync, .aimSatellite, .aimSatellitePeak:
            return .aim
        case .eventsCalendar, .event, .cometsList, .asteroidsList, .satellitePasses, .satellitePassDetail, .widgets, .widgetsStates, .widgetsLargeType,
             .widgetsRed:
            return .tonight
        case .cometDetail, .asteroidDetail:
            return .objects
        case .starTrails, .timeLapse, .mountConnection, .mountConnected, .skyline, .siteEditor, .mountSkyWatcher,
             .mountSkyWatcherEquatorial, .mountSkyWatcherConnected, .mountSkyWatcherAligned1, .mountSkyWatcherAligned2,
             .onlineFirstTime, .help, .helpTopic:
            return .settings
        }
    }

    /// Whether the screen needs the satellites and the forecast (instead of the downloads).
    var needsOnlineData: Bool {
        switch self {
        case .satellitePasses, .satellitePassDetail, .aimSatellite, .aimSatellitePeak: return true
        default: return false
        }
    }

    /// Whether the screen is the widgets, which fill the window.
    var isWidgets: Bool {
        switch self {
        case .widgets, .widgetsStates, .widgetsLargeType, .widgetsRed: return true
        default: return false
        }
    }

    /// The sheet of the Aim screen to open, for the screens that are one.
    var aimSheet: AimSheet? {
        switch self {
        case .mosaic: return .mosaic
        case .mountSheet, .mountSheetSlewing, .mountSkyWatcherSheet, .mountSkyWatcherSheetAligned,
             .mountSkyWatcherSync: return .mount
        default: return nil
        }
    }

    /// Whether `ReviewHost` builds the screen (the others are the real tab, with a sheet for the Aim tab).
    var usesHost: Bool { (tab != .aim && self != .onlineFirstTime) || isWidgets }

    /// Whether the screen is pushed on the host's navigation stack.
    var isPushed: Bool {
        switch self {
        case .skyline, .siteEditor, .onlineFirstTime: return false
        default: return usesHost
        }
    }

    /// What the mount is made to do before the screenshot.
    enum MountSetup: Equatable {
        case none
        /// The built-in simulated mount is connected.
        case demo
        /// The simulated Sky-Watcher mount is connected and synced on `syncs` stars; the next suggested star becomes
        /// the Aim target.
        case skyWatcher(syncs: Int)
        /// No mount is connected, the Sky-Watcher kind is chosen, with the given arrangement.
        case chooseSkyWatcher(equatorial: Bool)
    }

    var mount: MountSetup {
        switch self {
        case .mountSheet, .mountSheetSlewing, .aimMount, .aimMountSlewing, .mountConnected: return .demo
        case .mountSkyWatcherConnected, .mountSkyWatcherSheet: return .skyWatcher(syncs: 0)
        case .mountSkyWatcherAligned1: return .skyWatcher(syncs: 1)
        case .mountSkyWatcherAligned2, .mountSkyWatcherSheetAligned, .mountSkyWatcherSync: return .skyWatcher(syncs: 2)
        case .mountSkyWatcher: return .chooseSkyWatcher(equatorial: false)
        case .mountSkyWatcherEquatorial: return .chooseSkyWatcher(equatorial: true)
        default: return .none
        }
    }

    /// Whether the connected mount is sent to the Aim target, so that the screen shows a slew in progress.
    var slews: Bool {
        self == .mountSheetSlewing || self == .aimMountSlewing
    }

    /// Whether the screen is still moving after it has appeared (a slew), so the capture script waits a fixed time.
    var isAnimated: Bool { slews }

    /// What the list of comets and asteroids opens on.
    var listKind: SmallBodyListKind { self == .asteroidsList ? .asteroids : .comets }
}
#endif
