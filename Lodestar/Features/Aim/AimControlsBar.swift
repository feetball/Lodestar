import SwiftUI
import LodestarKit

/// The buttons of the screen: target, align, mosaic, camera, night mode and zoom, in a row or, in a wide HUD, in two
/// columns.
struct AimControlsBar: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    var axis: Axis = .horizontal
    @Environment(AppModel.self) private var app

    /// The two columns of a wide HUD.
    private static let columns = [GridItem(.fixed(66), spacing: 6), GridItem(.fixed(66), spacing: 6)]

    var body: some View {
        if axis == .horizontal {
            HStack(spacing: 6) { buttons }
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
            .accessibilityValue(model.guidanceTarget?.name ?? "None")
        control("Align", systemImage: "dot.viewfinder", isOn: app.alignment.isAligned) { sheet = .alignment }
            .accessibilityLabel("Align on a star")
            .accessibilityValue(app.alignment.isAligned ? "Aligned" : "Not aligned")
        control("Mosaic", systemImage: "square.grid.3x3", isOn: mosaic.isActive) { sheet = .mosaic }
            .accessibilityLabel("Plan a mosaic")
            .accessibilityValue(mosaic.isActive ? mosaic.progressText : "Off")
        control("Mount", systemImage: "antenna.radiowaves.left.and.right", isOn: MountService.shared.isConnected) {
            sheet = .mount
        }
        .accessibilityLabel("Mount control")
        .accessibilityValue(MountService.shared.isConnected ? MountService.shared.displayName : "Not connected")
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

/// Shows the field of view along the screen's long side and resets the zoom of the virtual sky. With the camera
/// picture the field of view is the camera's and cannot be changed.
private struct AimFieldOfViewButton: View {
    let model: AimViewModel
    let minHeight: CGFloat

    var body: some View {
        let camera = model.cameraGeometry
        let usesCamera = camera != nil
        let fieldOfView = camera.map { max($0.portraitHorizontalFOV, $0.portraitVerticalFOV) } ?? model.virtualFieldOfView
        let isDefault = abs(model.virtualFieldOfView - AimProjectionFactory.defaultVirtualFieldOfView) < 0.5
        Button {
            model.resetFieldOfView()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .medium))
                Text(AngleFormatter.formatDegrees(fieldOfView, decimals: 0))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(AimControlButtonStyle(minHeight: minHeight))
        .disabled(usesCamera || isDefault)
        .accessibilityLabel("Reset zoom")
        .accessibilityValue("\(usesCamera ? "Camera field of view" : "Field of view") \(AimFormat.spoken(fieldOfView))")
    }
}
