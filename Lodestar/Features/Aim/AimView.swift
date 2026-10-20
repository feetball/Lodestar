import SwiftUI
import LodestarKit

/// The Aim tab: the live sky over the camera picture with guidance to the chosen target.
///
/// Layers, back to front: the camera picture (when wanted), the sky overlay, the arrow around the reticle, and the
/// heads-up display. The sky and the picture run edge to edge; the display respects the safe area.
struct AimView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        AimScreen(app: app)
    }
}

/// Owns the view model and the sheets and starts the background work that belongs to the screen. The view model needs
/// the app model when it is made, which only the parent `AimView` can hand over.
private struct AimScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var model: AimViewModel
    @State private var sheet: AimSheet?

    init(app: AppModel) {
        _model = State(initialValue: AimViewModel(app: app))
        #if DEBUG
        // The visual review opens the sheet it asks for (`screen=mosaic`, `screen=mount-sheet`).
        _sheet = State(initialValue: ScreenshotMode.current?.screen?.aimSheet)
        #endif
    }

    /// The sensors, the timelines and the audio run only while this tab is showing and the app is in front.
    private var isActive: Bool { app.selectedTab == .aim && app.scenePhase == .active }

    /// Identifies the background work of the screen, so it restarts whenever its inputs change and stops while the
    /// screen is not in use.
    private struct WorkKey: Equatable {
        var skyInputs: AimSkyInputs?
        var isActive: Bool
    }

    var body: some View {
        let configuration = AimConfiguration(app: app)
        let skyInputs = model.skyInputs(for: configuration)
        content
            // The `TabView` does not hand the bottom inset of the app's tab bar (`AppTabBar`, set up in `RootView`) on
            // to its tabs, so the display ended behind the bar. An invisible bar of the same layout, in the same
            // place, keeps the display above the real one at every text size; the sky still runs under it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppTabBar(selection: .constant(.aim))
                    .hidden()
            }
            .screenBackground(palette)
            .sheet(item: $sheet) { sheet in
                sheetContent(sheet)
                    .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
            }
            .onChange(of: configuration, initial: true) { _, newConfiguration in
                model.apply(newConfiguration)
            }
            .onChange(of: model.guidanceTarget?.id, initial: true) {
                model.syncTarget()
            }
            .onChange(of: app.selectedTab == .aim, initial: true) { _, isShowing in
                model.useCameraZoom(isShowing: isShowing)
            }
            .task(id: WorkKey(skyInputs: skyInputs, isActive: isActive)) {
                guard isActive else { return }
                await model.keepSkyCurrent(skyInputs)
            }
            .task(id: WorkKey(skyInputs: skyInputs, isActive: isActive)) {
                guard isActive else { return }
                await model.keepRiseInfoCurrent(skyInputs)
            }
            .task(id: isActive) {
                guard isActive else {
                    model.stopFeedback()
                    return
                }
                await model.runLoop()
            }
            .onDisappear {
                model.stopFeedback()
            }
    }

    @ViewBuilder
    private var content: some View {
        if app.observerContext == nil {
            NeedsLocationView()
        } else if app.motion.status == .unavailable {
            EmptyStateView(
                title: "Motion Sensors Needed",
                systemImage: "gyroscope",
                message: "Aiming reads the gyroscope and accelerometer of an iPhone, which the Simulator does not have. Run Lodestar on a real iPhone to use this screen. Objects, the sky chart and tonight's plan work everywhere."
            )
        } else {
            AimStage(model: model, sheet: $sheet, isActive: isActive)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AimSheet) -> some View {
        switch sheet {
        case .targetPicker:
            AimTargetPickerSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .alignment:
            // The sheet stays small by default, so the sky behind it can still be seen and the tripod steered.
            AlignmentSheet(model: model)
                .presentationDetents([.fraction(0.45), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
                .presentationDragIndicator(.visible)
        case .mosaic:
            AimMosaicSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .mount:
            // Like the alignment sheet, it stays small by default so the sky behind it can still be seen.
            MountAimSheet(model: model)
                .presentationDetents([.fraction(0.5), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
                .presentationDragIndicator(.visible)
        case .help:
            HelpSheet(topic: .aimScreen)
        }
    }
}

/// The layered screen itself.
private struct AimStage: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    let isActive: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            ZStack {
                palette.background
                CameraPreviewView(isWanted: model.configuration.wantsCameraPreview)
                SkyOverlayView(model: model, isActive: isActive)
                GuidanceArrowView(model: model, isActive: isActive)
            }
            .ignoresSafeArea()
            GuidanceHUD(model: model, sheet: $sheet, isActive: isActive)
            AimAccessibilitySummary(model: model, isActive: isActive)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(zoomGesture)
        .persistentSystemOverlays(isActive ? .hidden : .automatic)
        .statusBarHidden(isActive)
    }

    /// Pinching zooms the camera picture, or the virtual sky without it.
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                model.updatePinch(magnification: Double(value.magnification))
            }
            .onEnded { _ in
                model.endPinch()
            }
    }
}
