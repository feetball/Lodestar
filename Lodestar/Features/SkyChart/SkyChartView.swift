import SwiftUI
import LodestarKit

/// The Sky tab: an all-sky chart of the observer's sky at any moment within a year of now.
///
/// The chart is a planisphere: the zenith is at the centre, north at the top and east to the left,
/// as when lying down and looking up. It shows the stars, constellations, Milky Way, Sun, Moon,
/// planets and deep-sky objects, the aiming target, and where the camera on the tripod points, or, with
/// the camera frame fixed in the middle, a frame to plan a picture with by moving the sky under it.
/// Pinch and drag zoom and pan; a tap selects an object and opens its card.
struct SkyChartView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var model = SkyChartModel()
    @State private var isShowingLayers = false
    @State private var isShowingDateSheet = false
    @AppStorage("skyChart.rotatesToHeading") private var rotatesToHeading = false
    @AppStorage("skyChart.showsStarNames") private var showsStarNames = true
    @AppStorage("skyChart.showsAltitudeGrid") private var showsAltitudeGrid = true
    @AppStorage("skyChart.showsCameraView") private var showsCameraView = true
    @AppStorage("skyChart.fixesCameraFrame") private var fixesCameraFrame = false
    /// The position angle of the fixed camera frame, in degrees.
    @AppStorage("skyChart.cameraFrameAngle") private var cameraFrameAngle = 0.0

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            content
                .screenBackground(palette)
                .navigationTitle("Sky Chart")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(item: $model.detailObject) { object in
                    ObjectDetailView(object: object)
                }
        }
        .sheet(isPresented: $isShowingDateSheet) {
            SkyChartDateSheet(timeZone: app.observerContext?.timeZone ?? .autoupdatingCurrent)
                .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let observer = app.observerContext {
            VStack(spacing: 0) {
                chartArea(for: observer)
                TimeTravelBar(timeZone: observer.timeZone) { isShowingDateSheet = true }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .onChange(of: inputs(for: observer), initial: true) { _, newInputs in
                guard let catalog = app.catalog.catalog else { return }
                model.update(catalog: catalog, inputs: newInputs)
            }
            .overlay { layersMenu }
        } else {
            NeedsLocationView()
        }
    }

    @ViewBuilder
    private func chartArea(for observer: ObserverContext) -> some View {
        if let content = model.content {
            SkyChartSurface(model: model, content: content, layers: layerOptions,
                            rotatesToHeading: rotatesToHeading, timeZone: observer.timeZone,
                            framingAngle: $cameraFrameAngle)
        } else if case .failed(let message) = app.catalog.loadState {
            EmptyStateView(title: "Sky Catalog Unavailable", systemImage: "exclamationmark.triangle", message: message)
        } else {
            ProgressView {
                Text("Preparing the sky\u{2026}")
                    .foregroundStyle(palette.secondaryText)
            }
            .tint(palette.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The menu that shows and hides layers, over a transparent backdrop that dismisses it.
    @ViewBuilder
    private var layersMenu: some View {
        if isShowingLayers {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { isShowingLayers = false }
                    .accessibilityHidden(true)
                SkyChartLayersMenu(store: app.settingsStore, showsStarNames: $showsStarNames,
                                   showsAltitudeGrid: $showsAltitudeGrid, showsCameraView: $showsCameraView,
                                   fixesCameraFrame: $fixesCameraFrame,
                                   onDismiss: { isShowingLayers = false })
                    .padding(.top, 6)
                    .padding(.trailing, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
    }

    // MARK: Toolbar

    /// The toolbar buttons dim by tint rather than by `disabled`, which would draw them in system grey.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let canFollowHeading = app.motion.status != .unavailable
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                if canFollowHeading { rotatesToHeading = !rotatesToHeading }
            } label: {
                Image(systemName: rotatesToHeading ? "location.north.circle.fill" : "location.north.circle")
            }
            .tint(canFollowHeading ? palette.accent : palette.tertiaryText)
            .accessibilityLabel("Rotate chart to camera heading")
            .accessibilityValue(headingToggleValue(canFollow: canFollowHeading))
            .accessibilityAddTraits(.isToggle)

            SkyChartResetZoomButton(model: model)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { isShowingLayers = !isShowingLayers }
            } label: {
                Image(systemName: "square.stack.3d.up")
            }
            .accessibilityLabel("Layers")
            .accessibilityValue(isShowingLayers ? "Shown" : "Hidden")

            HelpButton(topic: .skyChart)
        }
    }

    private func headingToggleValue(canFollow: Bool) -> String {
        guard canFollow else { return "Unavailable without motion sensors" }
        return rotatesToHeading ? "On" : "Off"
    }

    // MARK: Inputs

    private var layerOptions: SkyChartLayerOptions {
        let settings = app.settings
        return SkyChartLayerOptions(constellationLines: settings.showConstellationLines,
                                    constellationNames: settings.showConstellationNames,
                                    milkyWay: settings.showMilkyWay,
                                    deepSkyObjects: settings.showDeepSkyObjects,
                                    starNames: showsStarNames,
                                    altitudeGrid: showsAltitudeGrid,
                                    cameraView: showsCameraView,
                                    fixedCameraFrame: fixesCameraFrame)
    }

    /// What the scene depends on. The chart's instant is rounded, so the 1 Hz clock does not rebuild it every second.
    private func inputs(for observer: ObserverContext) -> SkyChartInputs {
        let settings = app.settings
        var options = SkySnapshotOptions()
        options.starMagnitudeLimit = settings.starMagnitudeLimit
        options.includeConstellations = settings.showConstellationLines || settings.showConstellationNames
        options.includeDeepSky = settings.showDeepSkyObjects
        options.includeMilkyWay = settings.showMilkyWay
        options.deepSkyProminence = SkySnapshotOptions.prominence(forSetting: settings.deepSkyProminence)
        return SkyChartInputs(observer: observer, date: SkyChartModel.bucketed(app.clock.displayDate),
                              options: options, target: app.target, mosaic: MosaicSession.shared.plan,
                              isCatalogLoaded: app.catalog.catalog != nil)
    }
}

/// Puts the chart back at zoom 1 and centred. A view of its own, so that the toolbar does not redraw
/// with every step of a pinch or drag, which this button follows.
private struct SkyChartResetZoomButton: View {
    @Environment(\.palette) private var palette
    let model: SkyChartModel

    var body: some View {
        Button {
            model.resetViewport()
        } label: {
            Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
        }
        .tint(model.zoom != 1 || model.pan != .zero ? palette.accent : palette.tertiaryText)
        .accessibilityLabel("Reset zoom")
    }
}
