import SwiftUI
import LodestarKit

/// The chart area of the Sky tab: the planisphere with the live camera layer on top, the pinch, drag
/// and tap gestures, the status chips and the callout of the selected object.
///
/// With "rotate to camera heading" on, the whole chart is redrawn from the live camera heading up to
/// 15 times a second; otherwise only the small camera layer is.
struct SkyChartSurface: View {
    /// How often the live layers are redrawn.
    private static let liveInterval = 1.0 / 15

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let model: SkyChartModel
    let content: SkyChartContent
    let layers: SkyChartLayerOptions
    let rotatesToHeading: Bool
    let timeZone: TimeZone

    @State private var headingHold = SkyChartHeadingHold()
    /// The magnification and translation already applied by the gesture in progress.
    @State private var appliedMagnification: CGFloat = 1
    @State private var appliedTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            chart(in: size)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(in: size))
                .simultaneousGesture(magnifyGesture(in: size))
                .onTapGesture { location in
                    model.handleTap(at: location, in: viewport(in: size))
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityChildren { accessibilityBodies }
        }
        .overlay(alignment: .bottom) { callout }
        .animation(.easeOut(duration: 0.2), value: model.selection != nil)
    }

    // MARK: Layers

    @ViewBuilder
    private func chart(in size: CGSize) -> some View {
        // Read here, in the body, so that a change of zoom or pan redraws the chart even while it is
        // inside a timeline that otherwise only ticks 15 times a second.
        let zoom = model.zoom
        let pan = model.pan
        if rotatesToHeading {
            TimelineView(.animation(minimumInterval: Self.liveInterval, paused: !isMotionRunning)) { _ in
                let pose = currentPose()
                let viewport = PlanisphereViewport(size: size, zoom: zoom, pan: pan,
                                                   rotation: headingHold.rotation(for: pose))
                ZStack {
                    planisphere(viewport)
                    liveOverlay(pose: pose, viewport: viewport)
                }
            }
        } else {
            let viewport = PlanisphereViewport(size: size, zoom: zoom, pan: pan)
            ZStack {
                planisphere(viewport)
                TimelineView(.animation(minimumInterval: Self.liveInterval, paused: !isMotionRunning)) { _ in
                    liveOverlay(pose: currentPose(), viewport: viewport)
                }
            }
        }
    }

    private func planisphere(_ viewport: PlanisphereViewport) -> some View {
        PlanisphereCanvas(content: content, viewport: viewport, palette: palette, layers: layers,
                          selectedDirection: model.selection?.horizontal.unitVector, mosaic: MosaicDisplay.current)
            .equatable()
    }

    /// The camera crosshair and footprint, and the chips along the top edge.
    private func liveOverlay(pose: SkyChartCameraPose?, viewport: PlanisphereViewport) -> some View {
        ZStack {
            if layers.cameraView {
                PlanisphereLiveCanvas(pose: pose, viewport: viewport, palette: palette)
            }
            VStack {
                HStack(alignment: .top, spacing: 6) {
                    StatusChip(systemImage: "location.north.line",
                               text: rotatesToHeading && pose != nil ? "Heading up" : "North up")
                    if viewport.zoom > 1.05 {
                        StatusChip(systemImage: "magnifyingglass", text: zoomText(viewport.zoom))
                    }
                    Spacer(minLength: 6)
                    if layers.cameraView, let pose {
                        SkyChartCameraReadout(pose: pose)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .allowsHitTesting(false)
        }
    }

    /// The zoom factor, such as "2.5×".
    private func zoomText(_ zoom: CGFloat) -> String {
        "\(Double(zoom).formatted(.number.precision(.fractionLength(1))))\u{00D7}"
    }

    @ViewBuilder
    private var callout: some View {
        if let selection = model.selection {
            SkyChartCallout(selection: selection, isLive: app.clock.isLive,
                            onAim: { app.aim(at: selection.object) },
                            onDetails: { model.detailObject = selection.object },
                            onDismiss: { model.clearSelection() })
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Camera

    private var isMotionRunning: Bool {
        app.motion.status == .running
    }

    private func currentPose() -> SkyChartCameraPose? {
        SkyChartCameraPose.current(from: app.motion, mount: app.mountProfile, alignment: app.alignment,
                                   frame: app.lensSetup.fieldOfView)
    }

    /// The viewport as the chart is drawn right now, for turning a tap into a chart position.
    private func viewport(in size: CGSize) -> PlanisphereViewport {
        let rotation = rotatesToHeading ? headingHold.rotation(for: currentPose()) : 0
        return PlanisphereViewport(size: size, zoom: model.zoom, pan: model.pan, rotation: rotation)
    }

    // MARK: Gestures

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard value.magnification > 0, appliedMagnification > 0 else { return }
                let anchor = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)
                model.zoom(by: value.magnification / appliedMagnification, around: anchor, in: size)
                appliedMagnification = value.magnification
            }
            .onEnded { _ in
                appliedMagnification = 1
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let step = CGSize(width: value.translation.width - appliedTranslation.width,
                                  height: value.translation.height - appliedTranslation.height)
                model.pan(by: step, in: size)
                appliedTranslation = value.translation
            }
            .onEnded { _ in
                appliedTranslation = .zero
            }
    }

    // MARK: Accessibility

    private var visibleBodies: [SkyChartBodyMarker] {
        content.scene.bodies.filter(\.isAboveHorizon)
    }

    private var accessibilitySummary: String {
        let time = AppFormat.dateTime(content.scene.date, in: timeZone)
        var parts = ["Sky chart for \(time), looking up with north at the top."]
        if visibleBodies.isEmpty {
            parts.append("The Sun, Moon and planets are all below the horizon.")
        }
        parts += visibleBodies.map(description(of:))
        if let smallBodies = SmallBodyChartMarkers.spokenSummary(content.scene.smallBodies) {
            parts.append(smallBodies)
        }
        let deepSkyCount = content.scene.deepSky.count
        if layers.deepSkyObjects, deepSkyCount > 0 {
            parts.append("\(deepSkyCount) deep-sky \(deepSkyCount == 1 ? "object" : "objects") above the horizon are drawn.")
        }
        if let skyline = content.scene.skyline {
            parts.append("The ground below your recorded skyline is shaded; the skyline rises up to \(Int(skyline.highestAltitude.rounded())) degrees.")
        }
        if let mosaic = MosaicDisplay.current {
            parts.append(mosaicDescription(mosaic))
        }
        return parts.joined(separator: " ")
    }

    /// "Mosaic of 12 panels: panel 3 is being shot."
    private func mosaicDescription(_ mosaic: MosaicDisplay) -> String {
        let panels = "Mosaic of \(mosaic.count) \(mosaic.count == 1 ? "panel" : "panels")"
        return mosaic.step < mosaic.count ? "\(panels): panel \(mosaic.step + 1) is being shot." : "\(panels): all shot."
    }

    private func description(of body: SkyChartBodyMarker) -> String {
        let direction = AngleFormatter.compassPoint(azimuth: body.horizontal.azimuth).fullName.lowercased()
        return "\(body.name), altitude \(Int(body.horizontal.altitude.rounded())) degrees, \(direction)."
    }

    /// The Sun, Moon and planets above the horizon as synthetic elements that VoiceOver can activate
    /// to select them, standing in for what the canvas draws.
    private var accessibilityBodies: some View {
        VStack {
            ForEach(visibleBodies) { body in
                Color.clear
                    .accessibilityLabel(description(of: body))
                    .accessibilityHint("Shows the object's card")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.select(body.object) }
            }
            ForEach(content.scene.smallBodies) { marker in
                Color.clear
                    .accessibilityLabel(SmallBodyChartMarkers.description(marker))
                    .accessibilityHint("Shows the object's card")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.select(marker.object) }
            }
        }
    }
}
