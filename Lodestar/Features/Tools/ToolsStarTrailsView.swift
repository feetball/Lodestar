import SwiftUI
import LodestarKit

/// Plans star-trail photographs and time-lapses: how long a trail the sky draws in a chosen time, how long to shoot
/// for a chosen trail, how to stack short exposures into one, and how many frames, how much time and storage a
/// time-lapse takes.
///
/// Push it inside a navigation stack (Settings ▸ Tools). It starts from the camera and lens in Settings; changes made
/// here are local and never touch Settings.
struct ToolsStarTrailsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ToolsStarTrailsForm(myCamera: app.lensSetup)
    }
}

/// The two plans of the screen.
private enum ToolsPlannerMode: String, CaseIterable, Identifiable {
    case starTrails, timeLapse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .starTrails: return "Star Trails"
        case .timeLapse: return "Time-Lapse"
        }
    }
}

/// The screen's form. Both plans keep their inputs here, so switching between them loses nothing.
private struct ToolsStarTrailsForm: View {
    /// How often the pole and the target are looked up again (they move 15° an hour).
    private static let skyRefreshInterval: Duration = .seconds(30)

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    private let myCamera: LensSetup
    @State private var mode = ToolsPlannerMode.starTrails
    @State private var trail: ToolsTrailInputs
    @State private var lapse = ToolsLapseInputs()
    @State private var sky: ToolsTrailSky?

    init(myCamera: LensSetup) {
        self.myCamera = myCamera
        _trail = State(initialValue: ToolsTrailInputs(camera: myCamera))
        #if DEBUG
        // The visual review opens the time-lapse plan (`screen=time-lapse`).
        if ScreenshotMode.current?.screen == .timeLapse { _mode = State(initialValue: .timeLapse) }
        #endif
    }

    /// What the sky information depends on.
    private struct SkyKey: Equatable {
        var observer: Observer?
        var targetID: String?
        var frame: FrameSize
    }

    var body: some View {
        Form {
            SettingsSection(title: "Plan") {
                ThemedSegmentedPicker("Plan", selection: $mode, options: ToolsPlannerMode.allCases, label: \.title)
            }
            switch mode {
            case .starTrails:
                ToolsStarTrailSections(inputs: $trail, myCamera: myCamera, sky: sky)
            case .timeLapse:
                ToolsTimeLapseSections(inputs: $lapse)
            }
        }
        .themedList(palette)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Star Trails & Time-Lapse")
        .navigationBarTitleDisplayMode(.inline)
        .nightBackButton()
        .task(id: SkyKey(observer: app.observerContext?.observer, targetID: app.target?.id,
                         frame: trail.setup.fieldOfView)) {
            while !Task.isCancelled {
                sky = ToolsTrailSky(app: app, frameSize: trail.setup.fieldOfView)
                try? await Task.sleep(for: Self.skyRefreshInterval)
            }
        }
    }
}
