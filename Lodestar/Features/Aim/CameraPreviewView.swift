import SwiftUI

/// The camera picture behind the sky, aspect-filled and dimmed at night, and the offer to turn the camera on while
/// the person has not yet decided about camera access.
struct CameraPreviewView: View {
    @Environment(AppModel.self) private var app

    /// Whether the picture is wanted at all (the preference, taking night mode into account).
    let isWanted: Bool

    var body: some View {
        ZStack {
            if isWanted {
                AimCameraFrameImage()
                if app.camera.authorization == .notDetermined {
                    AimCameraAccessPrompt()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The newest camera frame. Kept apart so that only this small view is redrawn for every frame.
private struct AimCameraFrameImage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        if let frame = app.camera.frame {
            // The picture is scaled to cover the screen and cropped; the overlay's projection assumes exactly that.
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

/// Explains the camera picture and asks for access.
private struct AimCameraAccessPrompt: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Show the sky over your camera?")
                .font(.headline)
                .foregroundStyle(palette.primaryText)
            Text("The live picture helps you see what the overlay marks. Nothing is recorded or saved. Without it the virtual sky still works.")
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
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity, alignment: .center)
        .offset(y: -40)
    }
}
