import Foundation
import LodestarKit

/// The preferences and calibration the Aim screen aims and draws with, gathered from the app model. It is
/// compared as a whole, so the screen reacts once when anything in it changes.
struct AimConfiguration: Equatable {
    var mount: MountProfile
    var alignment: AlignmentModel
    /// The DSLR's picture in landscape orientation, in degrees.
    var lensFrame: FrameSize
    var showConstellationLines: Bool
    var showConstellationNames: Bool
    var showDeepSkyObjects: Bool
    var showMilkyWay: Bool
    /// How much of the deep sky is drawn: 1 showpieces … 4 everything.
    var deepSkyProminence: Int
    var starMagnitudeLimit: Double
    /// Whether the camera picture is wanted behind the sky (it also has to run). Never with a mount that points the
    /// phone's camera somewhere else than the lens.
    var wantsCameraPreview: Bool
    var isNight: Bool

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

    /// Whether the phone's back camera looks along the lens. It does not when the phone lies on top of the camera:
    /// its picture then shows the ground, and the sky is drawn as seen from the lens instead.
    static func phoneCameraFollowsLens(_ mount: MountProfile) -> Bool {
        mount.cameraAxis.dot(DeviceAttitude.backCameraAxis) > 0.99
    }

    var phoneCameraFollowsLens: Bool { Self.phoneCameraFollowsLens(mount) }

    /// The compass correction of the alignment, for everything drawn from the phone's own camera.
    var headingOffset: Double { alignment.headingOffset(for: mount) }

    /// Separation in degrees within which the DSLR counts as pointing at the target.
    var onTargetThreshold: Double {
        GuidanceTracker.defaultOnTargetThreshold(horizontalFieldOfView: lensFrame.horizontal,
                                                 verticalFieldOfView: lensFrame.vertical)
    }

    var skyOptions: SkySnapshotOptions {
        var options = SkySnapshotOptions()
        options.starMagnitudeLimit = starMagnitudeLimit
        options.includeConstellations = showConstellationLines || showConstellationNames
        options.includeDeepSky = showDeepSkyObjects
        options.includeMilkyWay = showMilkyWay
        options.deepSkyProminence = SkySnapshotOptions.prominence(forSetting: deepSkyProminence)
        return options
    }
}

/// Everything that makes the sky snapshot behind the overlay out of date.
struct AimSkyInputs: Equatable, Sendable {
    var observer: Observer
    var options: SkySnapshotOptions
    var target: CelestialObject?
    /// The site's recorded skyline; `nil` for an open horizon.
    var horizon: HorizonProfile?
    /// The mosaic being shot, whose panels are drawn.
    var mosaic: MosaicPlan?
}

/// The sheets the Aim screen presents.
enum AimSheet: String, Identifiable {
    case targetPicker, alignment, mosaic, mount

    var id: String { rawValue }
}

/// When the target is next above the horizon, for the below-horizon warning.
struct AimRiseInfo: Sendable, Equatable {
    let targetID: String
    let nextRise: Date?
    let circumstance: RiseTransitSet.Circumstance

    /// The first rise within the next 24 hours. Searches the ephemeris, so run it off the main actor.
    static func compute(for object: CelestialObject, observer: Observer, from date: Date) -> AimRiseInfo {
        let day = DateInterval(start: date, duration: 24 * 3600)
        let result = RiseSetCalculator.riseTransitSet(for: object, observer: observer, within: day)
        return AimRiseInfo(targetID: object.id, nextRise: result.rise, circumstance: result.circumstance)
    }
}
