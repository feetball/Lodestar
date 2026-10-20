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
    /// Further from the site than this, the compass is corrected for the declination of the wrong place.
    private static let nearSiteMetres = 100_000.0
    /// The share of the screen height the top panel may take before it scrolls.
    private static let panelHeightShare = 0.45

    /// Done was tapped before the circle was complete.
    private struct Incomplete: Equatable {
        var coverage: Double
        var gaps: [AzimuthRange]
    }

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let site: SavedSite
    @State private var model: HorizonRecordingModel
    @State private var isConfirmingCancel = false
    @State private var incomplete: Incomplete?
    @State private var lastAnnouncement = Date.distantPast

    init(site: SavedSite, app: AppModel) {
        self.site = site
        _model = State(initialValue: HorizonRecordingModel(app: app, base: site.horizon))
    }

    /// Whether the camera picture is wanted behind the crosshair: the Aim screen's preferences, night mode included.
    private var isCameraWanted: Bool {
        let settings = app.settings
        return settings.cameraPreviewEnabled && (!palette.isNight || settings.cameraPreviewAtNight)
    }

    var body: some View {
        let reading = model.reading
        ZStack {
            palette.background
                .ignoresSafeArea()
            if isCameraWanted {
                HorizonCameraBackdrop()
                    .ignoresSafeArea()
            }
            HorizonCrosshair()
                .ignoresSafeArea()
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    topPanel(reading, maxHeight: proxy.size.height * Self.panelHeightShare)
                    Spacer(minLength: 0)
                    bottomPanel(reading)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .task {
            await model.run()
        }
        .onAppear {
            app.keepsMotionRunning = true
            app.keepsScreenAwake = true
        }
        .onChange(of: isCameraWanted, initial: true) { _, wanted in
            app.keepsCameraRunning = wanted
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
        .confirmationDialog("Discard This Recording?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Keep Recording", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("What you have recorded so far is not saved.")
        }
        .confirmationDialog("Not All the Way Round", isPresented: isAskingAboutGaps, titleVisibility: .visible,
                            presenting: incomplete) { _ in
            incompleteChoices
        } message: { pending in
            Text(incompleteMessage(pending))
        }
    }

    // MARK: Top

    /// Cancel, the title and Done; under them the feedback, the instruction and, if needed, the camera access offer.
    /// What is under the bar scrolls when the panel would take more than `maxHeight`; the bar stays in place.
    private func topPanel(_ reading: HorizonReading, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            topBar(reading)
            ViewThatFits(in: .vertical) {
                topMessages(reading)
                ScrollView {
                    topMessages(reading)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous)
                .fill(palette.background.opacity(0.86))
                .ignoresSafeArea(edges: .top)
        }
    }

    private func topMessages(_ reading: HorizonReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            messages(reading)
            cameraAccess
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func topBar(_ reading: HorizonReading) -> some View {
        HStack(spacing: 8) {
            Button("Cancel") {
                if reading.hasSamples {
                    isConfirmingCancel = true
                } else {
                    dismiss()
                }
            }
            .frame(minHeight: 44)
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                Text("Record Skyline")
                    .font(.headline)
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
                finish()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
            }
            .frame(minHeight: 44)
            .disabled(!reading.hasSamples)
            .accessibilityHint("Saves the skyline with the site")
        }
        .padding(.horizontal, 12)
    }

    /// Feedback (spoken when it changes), warnings and the instruction.
    private func messages(_ reading: HorizonReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let hint = reading.hint {
                HorizonHintRow(hint: hint)
            }
            if !reading.isComplete {
                Text("Aim at the skyline and turn slowly all the way round; sweep back over a stretch to redo it.")
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = locationWarning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isCameraWanted {
                Text("The camera picture is off in Settings (Camera, and Night Mode at night). You can still record "
                     + "by pointing the back of the phone along the skyline.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Why the directions might be off for this site, or `nil`.
    private var locationWarning: String? {
        guard let observer = app.observerContext?.location else {
            return "Lodestar does not know where you are yet, so it cannot turn compass directions into true north. "
                + "Choose this site or Current Location as your observing location first."
        }
        if HorizonText.distanceMetres(observer, site.location) > Self.nearSiteMetres {
            return "You are observing from a place far from this site, so the compass is corrected for the wrong "
                + "location. Choose this site or Current Location as your observing location first."
        }
        return nil
    }

    /// Explains the camera picture and asks for access, as the Aim screen does.
    @ViewBuilder private var cameraAccess: some View {
        let authorization = app.camera.authorization
        if isCameraWanted, authorization == .notDetermined || authorization == .denied {
            let isDenied = authorization == .denied
            VStack(alignment: .leading, spacing: 6) {
                Text("Show the skyline through the camera?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(isDenied
                     ? "Camera access is off for Lodestar. Allow it in the iOS Settings app to keep the skyline on "
                        + "the crosshair. Without it you can still record, but you have to aim by eye."
                     : "The live picture helps you keep the skyline on the crosshair. Nothing is recorded or saved. "
                        + "Without it you can still record, but you have to aim by eye.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if isDenied {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } else {
                        Task { _ = await app.camera.requestAccess() }
                    }
                } label: {
                    Label(isDenied ? "Open iOS Settings" : "Enable Camera", systemImage: "camera.fill")
                }
                .buttonStyle(.lodestarSecondary)
            }
        }
    }

    // MARK: Bottom

    private func bottomPanel(_ reading: HorizonReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HorizonDirectionReadout(reading: reading)
            HorizonSkylineStrip(reading: reading)
            coverageRow(reading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .fill(palette.background.opacity(0.86))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The share recorded, what is still to sweep, and Start Over.
    private func coverageRow(_ reading: HorizonReading) -> some View {
        let showsGaps = reading.coverage >= HorizonSkylineStrip.showGapsFrom && !reading.gaps.isEmpty
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(AppFormat.percent(reading.coverage)) covered")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryText)
                if showsGaps {
                    Text("Still to sweep: \(HorizonText.gapsText(reading.gaps))")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            Button("Start Over") {
                model.startOver()
            }
            .frame(minHeight: 44)
            .disabled(!reading.hasSamples)
        }
    }

    // MARK: Finishing

    /// Saves a complete sweep; for a partial one the person chooses what happens to the rest.
    private func finish() {
        let recording = model.finish(fill: .keepBase)
        if recording.isComplete {
            save(recording)
        } else {
            incomplete = Incomplete(coverage: recording.coverage, gaps: recording.gaps)
        }
    }

    private var isAskingAboutGaps: Binding<Bool> {
        Binding(get: { incomplete != nil }, set: { isPresented in
            if !isPresented { incomplete = nil }
        })
    }

    /// Keep sweeping, keep the old skyline (or leave the rest open) for what is missing, or join the ends.
    @ViewBuilder private var incompleteChoices: some View {
        Button("Keep Sweeping", role: .cancel) {}
        Button(site.horizon != nil ? "Keep the Old Skyline for the Rest" : "Leave the Rest Open") {
            save(model.finish(fill: .keepBase), keepsOldSkyline: site.horizon != nil)
        }
        Button("Join the Ends With Straight Lines") {
            save(model.finish(fill: .interpolate))
        }
    }

    private func incompleteMessage(_ pending: Incomplete) -> String {
        let recorded = "\(AppFormat.percent(pending.coverage)) of the circle is recorded. "
            + "Not yet swept: \(HorizonText.gapsText(pending.gaps))."
        if site.horizon != nil {
            return "\(recorded) The old skyline can stay in those stretches."
        }
        return "\(recorded) Those stretches can stay open, as a clear horizon, or be joined by straight lines."
    }

    /// Stores the skyline with the site (a flat one means an open horizon) and closes the screen. `keepsOldSkyline`
    /// is set when the stretches this sweep did not reach keep the site's old skyline.
    private func save(_ recording: HorizonRecorder.Recording, keepsOldSkyline: Bool = false) {
        let store = app.settingsStore
        // The stored site may have changed while recording (the editor only keeps a draft), so build on that one.
        if var saved = store.settings.savedSites.first(where: { $0.id == site.id }) {
            // The coverage shown is that of the whole skyline: where the old one stays, what it covered counts too
            // (and when that is not known, neither is the total). It is read before the skyline is replaced.
            let swept = model.recordedMask
            let sweep = HorizonCoverageMemory.Entry(coverage: recording.coverage, mask: swept)
            var remembered: HorizonCoverageMemory.Entry? = sweep
            if keepsOldSkyline, saved.horizon != nil {
                remembered = HorizonCoverageMemory.merged(sweep: swept, over: saved)
            }
            saved.horizon = recording.profile.isFlat ? nil : recording.profile
            store.updateSite(saved)
            if let remembered {
                HorizonCoverageMemory.store(siteID: site.id, horizon: saved.horizon, coverage: remembered.coverage,
                                            mask: remembered.mask)
            } else {
                HorizonCoverageMemory.forget(siteID: site.id)
            }
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

/// The camera's azimuth and altitude now.
private struct HorizonDirectionReadout: View {
    @Environment(\.palette) private var palette
    let reading: HorizonReading

    var body: some View {
        HStack(spacing: 24) {
            value(title: "Azimuth", text: reading.azimuth.map(AppFormat.azimuth) ?? AppFormat.missing)
            value(title: "Altitude", text: reading.altitude.map(AppFormat.altitude) ?? AppFormat.missing)
        }
        .frame(maxWidth: .infinity)
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
                .font(.subheadline.weight(.semibold))
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
