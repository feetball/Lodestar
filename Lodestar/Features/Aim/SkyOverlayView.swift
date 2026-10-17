import SwiftUI

/// The sky laid over the camera picture: a `Canvas` redrawn about 30 times a second from the newest motion sample.
///
/// The frame is pulled from the engine inside the timeline, so the sensor rate never reaches SwiftUI's observation;
/// the timeline pauses while the Aim tab is not showing.
struct SkyOverlayView: View {
    let model: AimViewModel
    let isActive: Bool
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let frame = model.engine.frame()
            let content = model.skyContent
            let configuration = model.configuration
            let camera = model.cameraGeometry
            let virtualFieldOfView = model.virtualFieldOfView
            let hudRotation = model.hudRotation
            // The target ring holds still for people who asked for less motion.
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let palette = palette
            Canvas { context, size in
                guard let frame,
                      var renderer = SkyOverlayRenderer(frame: frame, content: content, configuration: configuration,
                                                        palette: palette, camera: camera,
                                                        virtualFieldOfView: virtualFieldOfView,
                                                        hudRotation: hudRotation, time: time, size: size) else { return }
                renderer.draw(in: context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
