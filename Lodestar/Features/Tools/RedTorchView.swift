import SwiftUI

/// The red torch: the whole screen in pure red, to see by without losing night vision. The screen brightness is the
/// slider's (`AppModel.syncServices` sets it and keeps the screen awake while the torch is shown). One tap asks whether to
/// switch to white light and a second one confirms; a tap on white goes back to red; a double tap closes the torch.
///
/// The colours are the torch's own, not the palette's: the light has to be the full red of the panel, and the brightness
/// is the screen's.
struct RedTorchView: View {
    @Environment(AppModel.self) private var app
    @State private var light: TorchLight = .red

    private static let red = Color(red: 1, green: 0, blue: 0)

    var body: some View {
        @Bindable var store = app.settingsStore
        ZStack {
            (light == .white ? Color.white : Self.red)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2).onEnded { close() }
                        .exclusively(before: TapGesture().onEnded { light = light.afterTap })
                )
                .accessibilityElement()
                .accessibilityLabel(light == .white ? "White light" : "Red torch")
                .accessibilityHint("Double-tap to switch the colour. Use Close to leave.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { light = light.afterTap }
            VStack(spacing: 16) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
                Spacer()
                if light == .confirmingWhite {
                    confirmation
                }
                Spacer()
                controls(brightness: $store.settings.torchBrightness)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.easeOut(duration: 0.15), value: light)
    }

    private var hint: String {
        light == .white ? "Tap for red \u{00B7} double-tap to close" : "Tap for white light \u{00B7} double-tap to close"
    }

    /// Asks before the screen turns white: white light costs the night vision of everybody around.
    private var confirmation: some View {
        VStack(spacing: 12) {
            Text("Switch to white light?")
                .font(.headline)
            Text("It spoils your night vision, and anyone else's nearby.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Keep red") { light = light.afterCancel }
                    .buttonStyle(TorchButtonStyle(filled: false))
                Button("White light") { light = light.afterConfirm }
                    .buttonStyle(TorchButtonStyle(filled: true))
            }
        }
        .foregroundStyle(Self.red)
        .padding(20)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func controls(brightness: Binding<Double>) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Brightness")
                Spacer()
                Text(AppFormat.percent(brightness.wrappedValue))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.black)
            .accessibilityHidden(true)
            TorchBrightnessBar(value: brightness)
            Button("Close") { close() }
                .buttonStyle(TorchButtonStyle(filled: true, onLight: true))
        }
        .padding(16)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func close() {
        app.isTorchShown = false
    }
}

/// A pill button in the torch: red on black inside the confirmation, black on the torch's own colour in the controls.
private struct TorchButtonStyle: ButtonStyle {
    let filled: Bool
    var onLight = false

    func makeBody(configuration: Configuration) -> some View {
        let red = Color(red: 1, green: 0, blue: 0)
        let ink: Color = onLight ? .black : red
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(filled && onLight ? red : (filled ? Color.black : ink))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                Capsule().fill(filled ? ink : Color.clear)
            }
            .overlay { Capsule().strokeBorder(ink, lineWidth: 1.5) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The brightness control: a bar to touch or drag. The system slider's track is grey, which would put green and blue light
/// into a red screen, so this one is drawn in black over the torch's own colour.
private struct TorchBrightnessBar: View {
    @Binding var value: Double

    private static let range = 0.01...1.0
    private static let step = 0.05

    private var fraction: Double {
        (value - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.25))
                Capsule().fill(Color.black).frame(width: max(width * fraction, 10))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = min(max(drag.location.x / width, 0), 1)
                    value = Self.range.lowerBound + position * (Self.range.upperBound - Self.range.lowerBound)
                }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Torch brightness")
        .accessibilityValue(AppFormat.percent(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + Self.step, Self.range.upperBound)
            case .decrement: value = max(value - Self.step, Self.range.lowerBound)
            @unknown default: break
            }
        }
    }
}
