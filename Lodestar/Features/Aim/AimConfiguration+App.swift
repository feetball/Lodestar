import Foundation
import LodestarKit

/// Reads the Aim screen's configuration from the app model (the part of `AimConfiguration` that needs `AppModel`, so that the
/// struct itself can be tested without it).
extension AimConfiguration {
    @MainActor
    init(app: AppModel) {
        let settings = app.settings
        let mount = app.mountProfile
        self.mount = mount
        alignment = app.alignment
        lensFrame = app.lensSetup.fieldOfView
        showConstellationLines = settings.showConstellationLines
        showConstellationNames = settings.showConstellationNames
        showDeepSkyObjects = settings.showDeepSkyObjects
        showMilkyWay = settings.showMilkyWay
        deepSkyProminence = settings.deepSkyProminence
        starMagnitudeLimit = settings.starMagnitudeLimit
        isNight = app.isNightModeActive
        wantsCameraPreview = settings.cameraPreviewEnabled && (!isNight || settings.cameraPreviewAtNight)
            && Self.phoneCameraFollowsLens(mount)
    }
}
