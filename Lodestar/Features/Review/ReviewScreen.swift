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

    private static let named: [String: ReviewScreen] = [
        "mosaic": .mosaic, "mount-sheet": .mountSheet, "mount-sheet-slewing": .mountSheetSlewing,
        "aim-mount": .aimMount, "aim-mount-slewing": .aimMountSlewing,
        "events-calendar": .eventsCalendar,
        "comets-list": .cometsList, "asteroids-list": .asteroidsList,
        "comet-detail": .cometDetail, "asteroid-detail": .asteroidDetail,
        "star-trails": .starTrails, "time-lapse": .timeLapse,
        "mount-connection": .mountConnection, "mount-connected": .mountConnected,
        "skyline": .skyline, "site-editor": .siteEditor,
    ]

    /// The screen called `name` (exactly), or `nil`. Events are "event-" and the engine's name of the kind, such as
    /// "event-meteorShower".
    init?(name: String) {
        if let screen = Self.named[name] {
            self = screen
        } else if name.hasPrefix("event-"), let kind = EventKind(rawValue: String(name.dropFirst("event-".count))) {
            self = .event(kind)
        } else {
            return nil
        }
    }

    /// The tab the screen belongs to.
    var tab: AppTab {
        switch self {
        case .mosaic, .mountSheet, .mountSheetSlewing, .aimMount, .aimMountSlewing:
            return .aim
        case .eventsCalendar, .event, .cometsList, .asteroidsList:
            return .tonight
        case .cometDetail, .asteroidDetail:
            return .objects
        case .starTrails, .timeLapse, .mountConnection, .mountConnected, .skyline, .siteEditor:
            return .settings
        }
    }

    /// The sheet of the Aim screen to open, for the screens that are one.
    var aimSheet: AimSheet? {
        switch self {
        case .mosaic: return .mosaic
        case .mountSheet, .mountSheetSlewing: return .mount
        default: return nil
        }
    }

    /// Whether `ReviewHost` builds the screen (the others are the real tab, with a sheet for the Aim tab).
    var usesHost: Bool { tab != .aim }

    /// Whether the screen is pushed on the host's navigation stack.
    var isPushed: Bool {
        switch self {
        case .skyline, .siteEditor: return false
        default: return usesHost
        }
    }

    /// Whether the built-in simulated mount is connected before the screenshot.
    var connectsMount: Bool {
        switch self {
        case .mountSheet, .mountSheetSlewing, .aimMount, .aimMountSlewing, .mountConnected: return true
        default: return false
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
