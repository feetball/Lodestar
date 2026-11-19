#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// The Live Activity of a followed satellite pass: the Lock Screen banner and the Dynamic Island count down to the rise
/// and then to the peak, and say how high the pass gets and where to look. The app starts it when the user follows a
/// pass in Aim and ends it with the pass or when the follow stops (`SatellitePassActivityController`); the
/// extension draws it (`LodestarWidgets/SatellitePassLiveActivity.swift`).
struct SatellitePassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Where the pass is. The app sets it at the rise and the peak; a view never shows an earlier stage than the clock
        /// says, so it stays right when the app could not update it.
        var stage: SatellitePassTimeline.Stage
    }

    /// The satellite's name, "ISS" for the station.
    let name: String
    let timeline: SatellitePassTimeline
    /// The user waits at the peak instead of following the satellite.
    let waitsAtPeak: Bool
    /// The app was in night mode when the activity started: draw in red.
    let isNight: Bool
}
#endif
