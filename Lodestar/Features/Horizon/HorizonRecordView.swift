import SwiftUI
import UIKit
import LodestarKit

/// Records the skyline of a saved site: the person holds the phone with its back camera along the skyline and turns
/// all the way round; the camera picture (when wanted) and a crosshair help to keep the skyline in the middle.
///
/// Present it with `fullScreenCover` through `.horizonFlow(...)`. It saves the skyline with the site when the person
/// taps Done and closes itself.
struct HorizonRecordView: View {
    /// Fewest seconds between two spoken hints.
    private static let announcementInterval: TimeInterval = 3

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let site: SavedSite
    @State private var model: HorizonRecordingModel
    @State private var showsCamera: Bool
    @State private var isConfirmingCancel = false
    @State private var isConfirmingStartOver = false
    @State private var isConfirmingGaps = false
    @State private var lastAnnouncement = Date.distantPast

    init(site: SavedSite, app: AppModel) {
        self.site = site
        _model = State(initialValue: HorizonRecordingModel(app: app, base: site.horizon))
        let settings = app.settings
        _showsCamera = State(initialValue: settings.cameraPreviewEnabled
                             && (!app.isNightModeActive || settings.cameraPreviewAtNight))
    }

    var body: some View {
        let reading = model.reading
        ZStack {
            palette.background
                .ignoresSafeArea()
            if showsCamera {
                HorizonCameraBackdrop()
                    .ignoresSafeArea()
            }
            HorizonCrosshair()
                .ignoresSafeArea()
            VStack(spacing: 10) {
                topBar(reading)
                HorizonDirectionReadout(reading: reading)
                if showsCamera, app.camera.authorization == .notDetermined {
                    HorizonCameraPrompt()
                }
                Spacer(minLength: 0)
                bottomPanel(reading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .task {
            await model.run()
        }
        .onAppear {
            app.keepsMotionRunning = true
            app.keepsScreenAwake = true
        }
        .onChange(of: showsCamera, initial: true) { _, wantsCamera in
            app.keepsCameraRunning = wantsCamera
        }
        .onDisappear {
            app.keepsMotionRunning = false
            app.keepsScreenAwake = false
            app.keepsCameraRunning = false
        }
        .onChange(of: reading.hint) { _, hint in
            announce(hint)
        }
        .statusBarHidden()
        .confirmationDialog("Discard this recording?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Discard Recording", role: .destructive) { dismiss() }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("The skyline you have swept so far will be lost.")
        }
        .confirmationDialog("Start the sweep again?", isPresented: $isConfirmingStartOver, titleVisibility: .visible) {
            Button("Start Over", role: .destructive) { model.startOver() }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("What you have swept so far will be forgotten.")
        }
        .confirmationDialog("Part of the horizon is missing", isPresented: $isConfirmingGaps,
                            titleVisibility: .visible) {
            gapChoices
        } message: {
            Text(gapMessage(reading))
        }
    }

    // MARK: Top

    private func topBar(_ reading: HorizonReading) -> some View {
        HStack(spacing: 8) {
            Button {
                if reading.hasSamples {
                    isConfirmingCancel = true
                } else {
                    dismiss()
                }
            } label: {
                Text("Cancel")
                    .modifier(HorizonBarLabel())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                Text("Record Skyline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(site.name)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button {
                showsCamera.toggle()
            } label: {
                Image(systemName: showsCamera ? "video.fill" : "video.slash")
                    .modifier(HorizonBarLabel())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Camera picture")
            .accessibilityValue(showsCamera ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            Button {
                isConfirmingStartOver = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .modifier(HorizonBarLabel())
            }
            .buttonStyle(.plain)
            .disabled(!reading.hasSamples)
            .opacity(reading.hasSamples ? 1 : 0.4)
            .accessibilityLabel("Start over")
        }
    }

    // MARK: Bottom

    private func bottomPanel(_ reading: HorizonReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hint = reading.hint {
                HorizonHintRow(hint: hint)
            } else {
                Text("Aim at the skyline and turn slowly all the way round; sweep back over a stretch to redo it.")
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HorizonSkylineStrip(reading: reading)
            coverageRow(reading)
            if let note = cameraNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                finish()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarPrimary)
            .disabled(!reading.hasSamples)
            .accessibilityHint("Saves the skyline with the site")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.surface.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.stroke, lineWidth: 0.5))
    }

    private func coverageRow(_ reading: HorizonReading) -> some View {
        let showsGaps = reading.hasSamples && !reading.gaps.isEmpty && reading.gaps != [.full]
        return HStack(alignment: .firstTextBaseline) {
            Text("\(AppFormat.percent(reading.coverage)) swept")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
            Spacer(minLength: 8)
            if showsGaps {
                Text("Still to sweep: \(HorizonText.describe(reading.gaps))")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityHidden(true)
    }

    /// Why there may be no camera picture, when it is wanted.
    private var cameraNote: String? {
        guard showsCamera else { return nil }
        switch app.camera.authorization {
        case .denied:
            return "Camera access is off for Lodestar, so there is no picture. The recording works without it."
        case .restricted:
            return "Camera access is restricted on this iPhone, so there is no picture. The recording works without it."
        case .unavailable:
            return "This iPhone has no usable camera, so there is no picture. The recording works without it."
        case .notDetermined, .authorized:
            return nil
        }
    }

    // MARK: Finishing

    /// Saves a complete sweep; for a partial one the person chooses what happens to the rest.
    private func finish() {
        let recording = model.finish(fill: .keepBase, keepingPrevious: true)
        if recording.isComplete {
            save(recording.profile)
        } else {
            isConfirmingGaps = true
        }
    }

    @ViewBuilder private var gapChoices: some View {
        if site.horizon != nil {
            Button("Merge with the Previous Skyline") {
                save(model.finish(fill: .keepBase, keepingPrevious: true).profile)
            }
        } else {
            Button("Treat the Rest as Open Horizon") {
                save(model.finish(fill: .keepBase, keepingPrevious: false).profile)
            }
        }
        Button("Join the Ends with Straight Lines") {
            save(model.finish(fill: .interpolate, keepingPrevious: false).profile)
        }
        Button("Keep Sweeping", role: .cancel) {}
    }

    private func gapMessage(_ reading: HorizonReading) -> String {
        var text = "\(AppFormat.percent(reading.coverage)) of the horizon is swept. Still to sweep: "
            + "\(HorizonText.describe(reading.gaps))."
        if site.horizon != nil {
            text += " Merging keeps the previous skyline for the rest."
        } else {
            text += " The rest can count as open horizon, or the ends can be joined by straight lines."
        }
        return text
    }

    /// Stores the skyline with the site (a flat one means an open horizon) and closes the screen.
    private func save(_ profile: HorizonProfile) {
        let store = app.settingsStore
        if var saved = store.settings.savedSites.first(where: { $0.id == site.id }) {
            saved.horizon = profile.isFlat ? nil : profile
            store.updateSite(saved)
        }
        dismiss()
    }

    // MARK: Accessibility

    /// Speaks a new hint, at most once every few seconds.
    private func announce(_ hint: HorizonHint?) {
        guard let hint, hint != .waiting, UIAccessibility.isVoiceOverRunning else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAnnouncement) >= Self.announcementInterval else { return }
        lastAnnouncement = now
        AccessibilityNotification.Announcement(hint.text).post()
    }
}

// MARK: - Pieces

/// A label on the top bar: a capsule of the palette's surface colour, at least 44 points tall.
private struct HorizonBarLabel: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 44)
            .background(Capsule().fill(palette.surface.opacity(0.85)))
            .overlay(Capsule().strokeBorder(palette.stroke, lineWidth: 0.5))
            .contentShape(Capsule())
    }
}

/// The camera's azimuth and altitude now.
private struct HorizonDirectionReadout: View {
    @Environment(\.palette) private var palette
    let reading: HorizonReading

    var body: some View {
        HStack(spacing: 18) {
            value(title: "Azimuth", text: reading.azimuth.map(AppFormat.azimuth) ?? AppFormat.missing)
            value(title: "Altitude", text: reading.altitude.map(AppFormat.altitude) ?? AppFormat.missing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(palette.surface.opacity(0.85)))
        .overlay(Capsule().strokeBorder(palette.stroke, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera direction")
        .accessibilityValue(spokenValue)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func value(title: String, text: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
            Text(text)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(palette.primaryText)
        }
    }

    private var spokenValue: String {
        guard let azimuth = reading.azimuth, let altitude = reading.altitude else { return "Not available yet" }
        return "Azimuth \(Int(azimuth.rounded())) degrees, \(HorizonText.direction(of: azimuth)). "
            + "Altitude \(Int(altitude.rounded())) degrees"
    }
}

/// The warning or note about the sweep, in the tone of its urgency.
private struct HorizonHintRow: View {
    @Environment(\.palette) private var palette
    let hint: HorizonHint

    var body: some View {
        Label {
            Text(hint.text)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: hint.systemImage)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch hint.tone {
        case .neutral: return palette.secondaryText
        case .positive: return palette.positive
        case .warning: return palette.warning
        case .critical: return palette.critical
        }
    }
}

/// The crosshair in the middle of the picture with a faint horizon line across it: the skyline should run through it.
private struct HorizonCrosshair: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colour = palette.guidance

            var line = Path()
            line.move(to: CGPoint(x: 0, y: center.y))
            line.addLine(to: CGPoint(x: size.width, y: center.y))
            context.stroke(line, with: .color(colour.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))

            let radius: CGFloat = 20
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: 2 * radius, height: 2 * radius)),
                           with: .color(colour), lineWidth: 1.5)
            var ticks = Path()
            let directions: [(CGFloat, CGFloat)] = [(-1, 0), (1, 0), (0, -1), (0, 1)]
            for (dx, dy) in directions {
                ticks.move(to: CGPoint(x: center.x + dx * (radius - 6), y: center.y + dy * (radius - 6)))
                ticks.addLine(to: CGPoint(x: center.x + dx * (radius + 10), y: center.y + dy * (radius + 10)))
            }
            context.stroke(ticks, with: .color(colour), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The newest camera frame, aspect-filled and dimmed at night. Kept apart so only this view is redrawn per frame.
private struct HorizonCameraBackdrop: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        if let frame = app.camera.frame {
            Color.clear
                .overlay {
                    Image(decorative: frame, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .opacity(palette.isNight ? 0.35 + 0.45 * app.settings.nightIntensity : 1)
                .accessibilityHidden(true)
        }
    }
}

/// Explains the camera picture and asks for access, while the person has not yet decided.
private struct HorizonCameraPrompt: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            Text("Show the camera picture?")
                .font(.headline)
                .foregroundStyle(palette.primaryText)
            Text("It helps you keep the crosshair on the skyline. Nothing is recorded or saved. Without it the "
                 + "recording works just the same.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                Task { _ = await app.camera.requestAccess() }
            } label: {
                Label("Enable camera", systemImage: "camera.fill")
            }
            .buttonStyle(.lodestarPrimary)
        }
        .card(palette)
    }
}
