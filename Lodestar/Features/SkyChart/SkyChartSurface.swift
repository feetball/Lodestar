import SwiftUI
import LodestarKit

/// How the chart was placed when a drag of the fixed camera frame began.
private struct SkyChartDragOrigin {
    let viewport: PlanisphereViewport
    let frame: SkyFrame
}

/// The chart area of the Sky tab: the planisphere with the live camera layer on top, the pinch, drag
/// and tap gestures, the status chips and the callout of the selected object.
///
/// With "rotate to camera heading" on, the whole chart is redrawn from the live camera heading up to
/// 15 times a second; otherwise only the small camera layer is.
///
/// With the camera frame fixed in the middle, the frame is kept on the sky (a J2000 position and a position angle) and
/// the chart is placed to put it in the middle: dragging moves the frame over the sky, so it stays on the same stars as
/// time passes, a panel under it tells where it is and how it is turned, and the frame turns with two fingers or with
/// a press and hold before a drag.
struct SkyChartSurface: View {
    /// How often the live layers are redrawn.
    private static let liveInterval = 1.0 / 15
    /// How long a finger rests on the chart before dragging turns the fixed camera frame instead of moving the chart.
    private static let rotationPressDuration = 0.35
    /// Closer to the middle than this (points), the finger's angle around the frame is too unsteady to turn it by.
    private static let rotationDeadZone: CGFloat = 24
    /// Degrees the frame turns per point of sideways drag when the press began in the dead zone.
    private static let rotationPerPoint = 0.5
    /// Degrees two fingers must twist before the frame follows, so that the slight twist of a pinch turns nothing.
    private static let twistDeadZone = 8.0
    /// A tap this soon (seconds) after a turn of the frame belongs to the turn and selects nothing.
    private static let tapGraceAfterRotation = 0.4

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let model: SkyChartModel
    let content: SkyChartContent
    let layers: SkyChartLayerOptions
    let rotatesToHeading: Bool
    let timeZone: TimeZone
    /// The position angle of the fixed camera frame, in degrees.
    @Binding var framingAngle: Double

    @State private var headingHold = SkyChartHeadingHold()
    /// The magnification and translation already applied by the gesture in progress.
    @State private var appliedMagnification: CGFloat = 1
    @State private var appliedTranslation: CGSize = .zero
    /// The viewport and instant where a drag of the fixed frame began, which it is worked out from.
    @State private var dragOrigin: SkyChartDragOrigin?
    /// Whether two fingers are pinching, which then leave the fixed frame where it is.
    @State private var isPinching = false
    /// The frame's position angle when the turn in progress began.
    @State private var rotationStartAngle: Double?
    @State private var lastRotationActivity: Date?
    /// Counts the turns begun, for the tap of the haptics that confirms one.
    @State private var rotationCount = 0
    /// True while a press and hold has turned into a turn of the frame. Resets by itself however the gesture ends, so a
    /// cancelled gesture cannot leave the chart unable to move.
    @GestureState private var isHoldTurning = false

    /// Whether the camera's frame stays in the middle while the chart moves under it.
    private var showsFixedFrame: Bool {
        layers.cameraView && layers.fixedCameraFrame
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .bottom) {
                chart(in: size)
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: size))
                    .simultaneousGesture(magnifyGesture(in: size))
                    .simultaneousGesture(frameTwistGesture)
                    .simultaneousGesture(frameHoldTurnGesture(in: size))
                    .onTapGesture { location in
                        // The lift of a finger that turned the frame is not a tap.
                        if rotationStartAngle != nil { return }
                        if let last = lastRotationActivity,
                           Date.now.timeIntervalSince(last) < Self.tapGraceAfterRotation { return }
                        model.handleTap(at: location, in: viewport(in: size))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(accessibilitySummary)
                    .accessibilityChildren { accessibilityBodies }
                // Beside the chart, not on it, so the chart's gestures leave the panel's buttons alone.
                bottomPanel
            }
            .onChange(of: showsFixedFrame, initial: true) { old, fixed in
                // The first call has nothing changed: it keeps a frame left where it was.
                let isFirstLook = old == fixed
                if fixed {
                    if !isFirstLook || model.framingCenter == nil { placeFrame(in: size) }
                } else if !isFirstLook {
                    releaseFrame(in: size)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.selection != nil)
        .sensoryFeedback(.selection, trigger: rotationCount)
    }

    // MARK: Layers

    @ViewBuilder
    private func chart(in size: CGSize) -> some View {
        // Read here, in the body, so that a change of zoom, pan or frame redraws the chart even while it is
        // inside a timeline that otherwise only ticks 15 times a second.
        let zoom = model.zoom
        let modelPan = model.pan
        let center = showsFixedFrame ? model.framingCenter : nil
        if rotatesToHeading {
            TimelineView(.animation(minimumInterval: Self.liveInterval, paused: !isMotionRunning)) { _ in
                let pose = currentPose()
                let rotation = headingHold.rotation(for: pose)
                let viewport = PlanisphereViewport(
                    size: size, zoom: zoom,
                    pan: pan(centering: center, otherwise: modelPan, zoom: zoom, rotation: rotation, in: size),
                    rotation: rotation)
                ZStack {
                    planisphere(viewport)
                    fixedFrame(viewport)
                    liveOverlay(pose: pose, viewport: viewport)
                }
            }
        } else {
            let viewport = PlanisphereViewport(
                size: size, zoom: zoom,
                pan: pan(centering: center, otherwise: modelPan, zoom: zoom, rotation: 0, in: size))
            ZStack {
                planisphere(viewport)
                fixedFrame(viewport)
                TimelineView(.animation(minimumInterval: Self.liveInterval, paused: !isMotionRunning)) { _ in
                    liveOverlay(pose: currentPose(), viewport: viewport)
                }
            }
        }
    }

    /// The pan of the chart: with the camera frame fixed (`center`), the one that puts the frame's centre in the middle
    /// of the view at the instant the chart shows; otherwise `modelPan`, the one the model keeps.
    private func pan(centering center: EquatorialCoordinate?, otherwise modelPan: CGSize, zoom: CGFloat,
                     rotation: Double, in size: CGSize) -> CGSize {
        guard let center else { return modelPan }
        return SkyChartFraming.pan(centering: center, frame: content.frame, size: size, zoom: zoom, rotation: rotation)
    }

    private func planisphere(_ viewport: PlanisphereViewport) -> some View {
        PlanisphereCanvas(content: content, viewport: viewport, palette: palette, layers: layers,
                          selectedDirection: model.selection?.horizontal.unitVector, mosaic: MosaicDisplay.current)
            .equatable()
    }

    /// The camera frame fixed in the middle, when it is shown.
    @ViewBuilder
    private func fixedFrame(_ viewport: PlanisphereViewport) -> some View {
        if showsFixedFrame, let framing = makeFraming() {
            SkyChartFramingCanvas(framing: framing, viewport: viewport, palette: palette)
        }
    }

    /// The camera crosshair and footprint, and the chips along the top edge.
    private func liveOverlay(pose: SkyChartCameraPose?, viewport: PlanisphereViewport) -> some View {
        ZStack {
            if layers.cameraView {
                PlanisphereLiveCanvas(pose: pose, viewport: viewport, palette: palette,
                                      showsFootprint: !showsFixedFrame)
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

    /// The callout of the selected object or, without a selection, the panel of the fixed camera frame.
    @ViewBuilder
    private var bottomPanel: some View {
        if let selection = model.selection {
            SkyChartCallout(selection: selection, isLive: app.clock.isLive,
                            onAim: { app.aim(at: selection.object) },
                            onDetails: { model.detailObject = selection.object },
                            onDismiss: { model.clearSelection() })
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if showsFixedFrame {
            SkyChartFramingBar(framing: makeFraming(), lens: app.lensSetup,
                               coordinateStyle: app.settings.coordinateStyle, isLive: app.clock.isLive,
                               positionAngle: $framingAngle) {
                guard let framing = makeFraming() else { return }
                app.aim(at: CelestialObject.custom(name: "Planned frame", j2000: framing.equatorial))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Fixed camera frame

    /// The camera frame at its place on the sky, with the lens of Settings; `nil` before it is placed.
    private func makeFraming() -> SkyChartFraming? {
        guard let center = model.framingCenter else { return nil }
        return SkyChartFraming(center: center, frame: content.frame, size: app.lensSetup.fieldOfView,
                               positionAngle: framingAngle)
    }

    /// The chart as it would be drawn without the fixed frame: the model's pan, and the heading's rotation.
    private func freeViewport(in size: CGSize) -> PlanisphereViewport {
        let rotation = rotatesToHeading ? headingHold.rotation(for: currentPose()) : 0
        return PlanisphereViewport(size: size, zoom: model.zoom, pan: model.pan, rotation: rotation)
    }

    /// Puts the camera frame on the sky at the middle of the chart as it is now.
    private func placeFrame(in size: CGSize) {
        let free = freeViewport(in: size)
        model.setFramingCenter(SkyChartFraming.skyPosition(atScreen: free.middle, in: free, frame: content.frame))
        model.saveFramingCenter()
    }

    /// Takes the camera frame off the chart, leaving the chart where the frame had it.
    private func releaseFrame(in size: CGSize) {
        if let center = model.framingCenter {
            let rotation = rotatesToHeading ? headingHold.rotation(for: currentPose()) : 0
            model.setPan(SkyChartFraming.pan(centering: center, frame: content.frame, size: size, zoom: model.zoom,
                                             rotation: rotation), in: size)
        }
        model.clearFramingCenter()
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
        let center = showsFixedFrame ? model.framingCenter : nil
        return PlanisphereViewport(
            size: size, zoom: model.zoom,
            pan: pan(centering: center, otherwise: model.pan, zoom: model.zoom, rotation: rotation, in: size),
            rotation: rotation)
    }

    // MARK: Gestures

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard value.magnification > 0, appliedMagnification > 0 else { return }
                isPinching = true
                // A fixed frame keeps the sky under it while zooming; otherwise the sky under the fingers stays put.
                let anchor = showsFixedFrame
                    ? CGPoint(x: size.width / 2, y: size.height / 2)
                    : CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)
                model.zoom(by: value.magnification / appliedMagnification, around: anchor, in: size)
                appliedMagnification = value.magnification
            }
            .onEnded { _ in
                appliedMagnification = 1
                isPinching = false
            }
    }

    /// Moves the chart under the fingers or, with the camera frame fixed, moves the frame over the sky.
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // Fingers that turn the frame or zoom leave it where it is.
                guard !isHoldTurning, rotationStartAngle == nil, !isPinching || !showsFixedFrame else { return }
                if showsFixedFrame {
                    moveFrame(by: value.translation, in: size)
                    return
                }
                let step = CGSize(width: value.translation.width - appliedTranslation.width,
                                  height: value.translation.height - appliedTranslation.height)
                model.pan(by: step, in: size)
                appliedTranslation = value.translation
            }
            .onEnded { _ in
                appliedTranslation = .zero
                if dragOrigin != nil {
                    dragOrigin = nil
                    model.saveFramingCenter()
                }
            }
    }

    /// Drags the sky under the fixed camera frame: the frame's centre becomes the sky point that `translation` brings
    /// to the middle. It is worked out from where the drag began, so that the small rounding of refraction does not
    /// build up step by step.
    private func moveFrame(by translation: CGSize, in size: CGSize) {
        let origin = dragOrigin ?? SkyChartDragOrigin(viewport: viewport(in: size), frame: content.frame)
        dragOrigin = origin
        let source = CGPoint(x: origin.viewport.middle.x - translation.width,
                             y: origin.viewport.middle.y - translation.height)
        model.setFramingCenter(SkyChartFraming.skyPosition(atScreen: source, in: origin.viewport, frame: origin.frame))
    }

    /// Two fingers twisting turn the fixed camera frame with them.
    private var frameTwistGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard showsFixedFrame else { return }
                // The slight twist of a pinch is ignored; past it, the frame follows from where it was.
                let degrees = value.rotation.degrees
                let beyond = degrees - min(abs(degrees), Self.twistDeadZone) * (degrees < 0 ? -1 : 1)
                guard beyond != 0 || rotationStartAngle != nil else { return }
                turnFrame(clockwiseBy: beyond)
            }
            .onEnded { _ in
                rotationStartAngle = nil
                lastRotationActivity = .now
            }
    }

    /// Press and hold, then drag: turns the fixed camera frame with the finger around the middle of the view. A drag
    /// without the pause moves the chart as usual, because the press fails as soon as the finger moves.
    private func frameHoldTurnGesture(in size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: Self.rotationPressDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isHoldTurning) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard showsFixedFrame else { return }
                guard case .second(true, let drag) = value else {
                    // A new press: whatever turn came before is over.
                    rotationStartAngle = nil
                    return
                }
                guard let drag else {
                    // The press has held long enough: the next drag turns the frame.
                    beginTurn()
                    return
                }
                turnFrame(clockwiseBy: turn(of: drag, in: size))
            }
            .onEnded { _ in
                rotationStartAngle = nil
                lastRotationActivity = .now
            }
    }

    /// Starts a turn of the frame from its present angle, with a tap of the haptics.
    private func beginTurn() {
        guard rotationStartAngle == nil else { return }
        rotationStartAngle = framingAngle
        rotationCount += 1
        lastRotationActivity = .now
    }

    /// Turns the frame by `degrees` clockwise on the screen from where the turn began, snapping to right angles. The
    /// position angle grows from north through east, which is anticlockwise on this chart, so it falls.
    private func turnFrame(clockwiseBy degrees: Double) {
        beginTurn()
        guard let start = rotationStartAngle else { return }
        framingAngle = SkyChartFraming.snapped(start - degrees)
        lastRotationActivity = .now
    }

    /// How far a drag has turned the frame on the screen, in degrees clockwise: the change of the finger's angle around
    /// the middle of the view or, for a press right at the middle, the drag's sideways distance.
    private func turn(of drag: DragGesture.Value, in size: CGSize) -> Double {
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let start = drag.startLocation
        let now = drag.location
        guard hypot(start.x - middle.x, start.y - middle.y) >= Self.rotationDeadZone else {
            return Double(now.x - start.x) * Self.rotationPerPoint
        }
        let before = atan2(Double(start.y - middle.y), Double(start.x - middle.x))
        let after = atan2(Double(now.y - middle.y), Double(now.x - middle.x))
        return AstroMath.degrees(after - before)
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
        if showsFixedFrame {
            parts.append("Your camera's frame is fixed in the middle of the chart; the panel below it says where it is.")
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
