import SwiftUI

/// The sky laid over the camera picture: a `Canvas` redrawn about 30 times a second from the newest motion sample, or,
/// with the camera picture behind it, from the sample current when that picture was captured.
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
            // Over the camera picture the sky is drawn with the attitude the picture was captured at; the guidance
            // elsewhere on the screen keeps using the newest.
            let frame = model.engine.frame(capturedAt: model.cameraFrameTime)
            let content = model.skyContent
            let configuration = model.configuration
            let camera = model.cameraGeometry
            let virtualFieldOfView = model.virtualFieldOfView
            let hudRotation = model.hudRotation
            let mosaic = MosaicDisplay.current
            let mountMarker = model.mountMarker()
            // The target ring holds still for people who asked for less motion.
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let palette = palette
            Canvas { context, size in
                guard let frame,
                      var renderer = SkyOverlayRenderer(frame: frame, content: content, configuration: configuration,
                                                        palette: palette, camera: camera,
                                                        virtualFieldOfView: virtualFieldOfView,
                                                        hudRotation: hudRotation, time: time, mosaic: mosaic,
                                                        mountMarker: mountMarker, size: size) else { return }
                renderer.draw(in: context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
