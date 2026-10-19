import SwiftUI
import LodestarKit

/// The buttons of the screen: target, align, camera, night mode and zoom, in a row or, in a wide HUD, in a column.
struct AimControlsBar: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    var axis: Axis = .horizontal
    @Environment(AppModel.self) private var app

    var body: some View {
        let previewOn = model.configuration.wantsCameraPreview
        let nightMode = app.settings.nightMode
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            control("Target", systemImage: "scope") { sheet = .targetPicker }
                .accessibilityLabel("Choose target")
                .accessibilityValue(model.guidanceTarget?.name ?? "None")
            control("Align", systemImage: "dot.viewfinder", isOn: app.alignment.isAligned) { sheet = .alignment }
                .accessibilityLabel("Align on a star")
                .accessibilityValue(app.alignment.isAligned ? "Aligned" : "Not aligned")
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
        .frame(width: axis == .vertical ? 66 : nil)
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
