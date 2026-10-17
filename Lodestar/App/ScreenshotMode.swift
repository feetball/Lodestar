#if DEBUG
import Foundation
import LodestarKit

/// Launch-argument driven demo state for App Store screenshots taken in the Simulator, which has no
/// motion sensors or real sky. Compiled into Debug builds only. Example:
///
///     -LodestarScreenshot tab=aim date=2026-07-17T05:30:00Z lat=36.0544 lon=-112.1401 elevation=2130
///         site=Grand_Canyon tz=America/Phoenix target=special.galacticCenter pointing=171,17 night=0
struct ScreenshotMode {
    var tab: AppTab
    var date: Date
    var location: GeographicLocation
    var siteName: String
    var timeZoneIdentifier: String
    var targetID: String?
    /// Where the phone's back camera points (portrait, level).
    var pointing: HorizontalCoordinate?
    var nightMode: Bool

    static let current: ScreenshotMode? = ScreenshotMode(arguments: ProcessInfo.processInfo.arguments)

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-LodestarScreenshot") else { return nil }
        var values: [String: String] = [:]
        for argument in arguments[(index + 1)...] {
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        tab = values["tab"].flatMap(AppTab.init(rawValue:)) ?? .aim
        date = values["date"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        location = GeographicLocation(latitude: values["lat"].flatMap(Double.init) ?? 36.0544,
                                      longitude: values["lon"].flatMap(Double.init) ?? -112.1401,
                                      elevation: values["elevation"].flatMap(Double.init) ?? 2130)
        siteName = (values["site"] ?? "Grand_Canyon").replacingOccurrences(of: "_", with: " ")
        timeZoneIdentifier = values["tz"] ?? "America/Phoenix"
        targetID = values["target"]
        pointing = values["pointing"].flatMap { text -> HorizontalCoordinate? in
            let numbers = text.split(separator: ",").compactMap { Double($0) }
            return numbers.count == 2 ? HorizontalCoordinate(azimuth: numbers[0], altitude: numbers[1]) : nil
        }
        nightMode = values["night"] == "1"
    }
}
#endif
