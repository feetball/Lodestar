import SwiftUI
import WidgetKit

/// The widgets Lodestar offers on the Home Screen and the Lock Screen, the Live Activity of a followed satellite pass, and
/// the Control Center controls (iOS 18 and later).
@main
struct LodestarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TonightWidget()
        SatellitePassLiveActivity()
        if #available(iOS 18.0, *) {
            NightModeControl()
            RedTorchControl()
            AimControl()
        }
    }
}
