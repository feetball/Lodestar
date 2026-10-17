import SwiftUI

/// The heads-up display over the sky: status chips, the target and how to reach it, the level gauge and the controls.
///
/// The whole display is laid out for the orientation the phone is clamped in and turned with it, in quarter turns, so
/// its text reads upright for the photographer; a phone clamped sideways gets a wide layout. The sky itself and the big
/// arrow stay in the phone's own screen axes.
struct GuidanceHUD: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            let rotation = model.hudRotation
            let size = geometry.size
            // A sideways HUD is laid out in the swapped size and turned back into the screen.
            let layoutSize = rotation.swapsAxes ? CGSize(width: size.height, height: size.width) : size
            ZStack {
                AimHUDLayout(model: model, sheet: $sheet, isActive: isActive, isWide: layoutSize.width > layoutSize.height)
                    .frame(width: layoutSize.width, height: layoutSize.height)
                    .rotationEffect(.degrees(rotation.degrees))
                    .frame(width: size.width, height: size.height)
                    .id(rotation)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.2), value: rotation)
        }
    }
}

/// The HUD's content for a given shape: controls under the readout in a tall layout, beside it in a wide one.
private struct AimHUDLayout: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    let isActive: Bool
    let isWide: Bool
    @Environment(\.palette) private var palette

    /// The readout does not grow wider than this in a wide layout.
    private static let wideReadoutWidth: CGFloat = 420
    /// Distance of the level gauge from the top of a tall layout.
    private static let levelGaugeTopInset: CGFloat = 84

    var body: some View {
        Group {
            if isWide { wideLayout } else { tallLayout }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .foregroundStyle(palette.primaryText)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private var tallLayout: some View {
        VStack(spacing: 8) {
            AimStatusChips(model: model)
            Spacer(minLength: 0)
            AimReadout(model: model, sheet: $sheet, isActive: isActive)
            AimControlsBar(model: model, sheet: $sheet)
        }
        .overlay(alignment: .topTrailing) {
            // Below the chips and clear of the arrow around the reticle.
            AimLevelGauge(model: model, isActive: isActive)
                .padding(.top, Self.levelGaugeTopInset)
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                AimStatusChips(model: model)
                Spacer(minLength: 0)
                AimReadout(model: model, sheet: $sheet, isActive: isActive)
            }
            .frame(maxWidth: Self.wideReadoutWidth)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                AimLevelGauge(model: model, isActive: isActive)
                AimControlsBar(model: model, sheet: $sheet, axis: .vertical)
            }
        }
    }
}
