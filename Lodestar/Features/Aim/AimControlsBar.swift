import SwiftUI
import LodestarKit

/// The buttons of the screen: target, align, mosaic, camera, night mode and zoom, and with several camera profiles the
/// frame menu, in a row or, in a wide HUD, in two columns.
struct AimControlsBar: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    var axis: Axis = .horizontal
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The two columns of a wide HUD.
    private static let columns = [GridItem(.fixed(66), spacing: 6), GridItem(.fixed(66), spacing: 6)]
    /// The four columns of the bar with larger text, or with the Mount button or the Frame menu too, which have no room
    /// for all the buttons in one row.
    private static let wrappedColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    /// The most buttons that share one row.
    private static let buttonsInRow = 7

    /// Switching between cameras at the tripod needs more than one profile.
    private var showsFrameMenu: Bool { app.settings.cameraProfiles.count > 1 }

    /// Target, Align, Mosaic, Time, Camera, Night and Zoom, Mount for people who have a GoTo mount, and the Frame menu
    /// with several camera profiles.
    private var buttonCount: Int {
        Self.buttonsInRow + (MountService.shared.showsAimButton ? 1 : 0) + (showsFrameMenu ? 1 : 0)
    }

    var body: some View {
        if axis == .horizontal {
            if dynamicTypeSize > .large || buttonCount > Self.buttonsInRow {
                LazyVGrid(columns: Self.wrappedColumns, spacing: 6) { buttons }
            } else {
                HStack(spacing: 6) { buttons }
            }
        } else {
            LazyVGrid(columns: Self.columns, spacing: 6) { buttons }
                .frame(width: 2 * 66 + 6)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        let previewOn = model.configuration.wantsCameraPreview
        let nightMode = app.settings.nightMode
        let mosaic = model.mosaicSession
        control("Target", systemImage: "scope") { sheet = .targetPicker }
            .accessibilityLabel("Choose target")
            .accessibilityValue(model.guidanceTarget?.name ?? model.satelliteSource?.title ?? "None")
        control("Align", systemImage: "dot.viewfinder", isOn: app.alignment.isAligned) {
            // Aligning compares the sky with the phone's sensors now: the live sky is the one to align on.
            model.endPreview()
            sheet = .alignment
        }
        .accessibilityLabel("Align on a star")
        .accessibilityValue(app.alignment.isAligned ? "Aligned" : "Not aligned")
        control("Mosaic", systemImage: "square.grid.3x3", isOn: mosaic.isActive) { sheet = .mosaic }
            .accessibilityLabel("Plan a mosaic")
            .accessibilityValue(mosaic.isActive ? mosaic.progressText : "Off")
        let moment = model.previewMoment
        control("Time", systemImage: moment == nil ? "clock" : "clock.fill", isOn: moment != nil) {
            model.toggleTimeBar()
        }
        .accessibilityLabel("Time preview")
        .accessibilityValue(moment.map { "Previewing \($0.text)" } ?? (model.isTimeBarOpen ? "Open" : "Live"))
        .accessibilityHint("Shows or hides the time bar, to preview the sky at another time.")
        // Only for people who have a GoTo mount: the first connection is made in Settings.
        if MountService.shared.showsAimButton {
            control("Mount", systemImage: "antenna.radiowaves.left.and.right", isOn: MountService.shared.isConnected) {
                sheet = .mount
            }
            .accessibilityLabel("Mount control")
            .accessibilityValue(MountService.shared.isConnected ? MountService.shared.displayName : "Not connected")
        }
        control("Camera", systemImage: previewOn ? "camera.fill" : "video.slash", isOn: previewOn) {
            model.toggleCameraPreview()
        }
        .disabled(!model.configuration.phoneCameraFollowsLens)
        .accessibilityLabel("Camera picture")
        .accessibilityValue(previewOn ? "On" : (model.configuration.phoneCameraFollowsLens ? "Off" : "Not available with this mount"))
        control(nightTitle(nightMode), systemImage: nightIcon(nightMode), isOn: app.isNightModeActive) {
            model.cycleNightMode()
        }
        .accessibilityLabel("Night mode")
        .accessibilityValue(nightMode.title)
        .accessibilityHint("Cycles between off, on and after sunset.")
        AimFieldOfViewButton(model: model, minHeight: buttonHeight)
        if showsFrameMenu {
            AimFrameMenu(minHeight: buttonHeight)
        }
    }

    private func control(_ title: String, systemImage: String, isOn: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(AimControlButtonStyle(isOn: isOn, minHeight: buttonHeight))
    }

    /// At least 44 points either way.
    private var buttonHeight: CGFloat { axis == .horizontal ? 54 : 46 }

    private func nightTitle(_ mode: NightModeSetting) -> String {
        switch mode {
        case .off: return "Night off"
        case .on: return "Night on"
        case .automatic: return "Night auto"
        }
    }

    private func nightIcon(_ mode: NightModeSetting) -> String {
        switch mode {
        case .off: return "moon"
        case .on: return "moon.fill"
        case .automatic: return "sunset.fill"
        }
    }
}

/// Steps the zoom through its presets: the camera picture's zoom (shown as "2×") while it is behind the sky, else
/// the virtual sky's field of view along the screen's long side (shown in degrees).
private struct AimFieldOfViewButton: View {
    let model: AimViewModel
    let minHeight: CGFloat

    var body: some View {
        let usesCamera = model.cameraGeometry != nil
        Button {
            model.stepZoom()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: model.nextZoomStepZoomsIn ? "plus.magnifyingglass" : "minus.magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                Text(usesCamera ? Self.zoomText(model.cameraZoom)
                     : AngleFormatter.formatDegrees(model.fieldOfView, decimals: 0))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(AimControlButtonStyle(minHeight: minHeight))
        .accessibilityLabel("Zoom")
        .accessibilityValue(usesCamera
                            ? "Camera zoom \(Self.zoomText(model.cameraZoom)), field of view \(AimFormat.spoken(model.fieldOfView))"
                            : "Field of view \(AimFormat.spoken(model.fieldOfView))")
        .accessibilityHint(usesCamera
                           ? "Changes the camera zoom to \(Self.zoomText(model.nextCameraZoomPreset))."
                           : "Changes the field of view to \(AimFormat.spoken(model.nextFieldOfViewPreset)).")
    }

    /// "2×", or "2.5×" between whole zooms.
    private static func zoomText(_ factor: Double) -> String {
        let rounded = (factor * 10).rounded() / 10
        let digits = rounded == rounded.rounded() ? 0 : 1
        return rounded.formatted(.number.precision(.fractionLength(digits))) + "\u{00D7}"
    }
}

/// The frame button: a menu of the camera profiles for switching between bodies and lenses at the tripod. The frame on
/// the sky follows the one chosen.
private struct AimFrameMenu: View {
    @Environment(AppModel.self) private var app
    let minHeight: CGFloat

    var body: some View {
        let settings = app.settings
        Menu {
            Picker("Camera and lens", selection: activeProfile) {
                ForEach(settings.cameraProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .medium))
                Text("Frame")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 2)
        }
        .menuStyle(.button)
        .buttonStyle(AimControlButtonStyle(minHeight: minHeight))
        .accessibilityLabel("Camera frame")
        .accessibilityValue(settings.activeCameraProfile.name)
        .accessibilityHint("Choose the camera and lens.")
    }

    /// The active profile; choosing another one switches the frame.
    private var activeProfile: Binding<UUID> {
        Binding(
            get: { app.settings.activeCameraProfile.id },
            set: { app.settingsStore.activateCameraProfile($0) })
    }
}
