import Foundation
import LodestarKit

/// Reads the pole and the target from the app model (the part of `ToolsTrailSky` that needs `AppModel`, so that the struct itself
/// can be tested without it).
extension ToolsTrailSky {
    /// `nil` without an observing location.
    @MainActor
    init?(app: AppModel, frameSize: FrameSize) {
        guard let observer = app.observerContext?.observer else { return nil }
        let frame = SkyFrame(date: app.clock.now, observer: observer)
        let pole = StarTrailPlanner.pole(frame: frame)
        hemisphere = pole.hemisphere
        poleAltitude = pole.direction.altitude
        poleAzimuth = pole.direction.azimuth
        guard let object = app.target else { return }
        let declination = frame.apparentEquatorial(of: object).declination
        let pointing = frame.horizontal(of: object)
        guard pointing.altitude >= 0 else {
            target = Target(name: object.name, declination: declination)
            return
        }
        // No position means the pole is behind the camera.
        let landscape = try? StarTrailPlanner.polePosition(pole: pole.direction, pointing: pointing, frameSize: frameSize)
        let portrait = try? StarTrailPlanner.polePosition(pole: pole.direction, pointing: pointing,
                                                          frameSize: frameSize.rotated)
        target = Target(name: object.name, declination: declination,
                        separationFromPole: pointing.angularSeparation(to: pole.direction),
                        poleInLandscape: landscape?.isInFrame ?? false, poleInPortrait: portrait?.isInFrame ?? false,
                        isPoleBehind: landscape == nil)
    }
}
