import SwiftUI

/// Shows how far the camera is rolled about its optical axis, like the horizon of an aircraft's attitude indicator:
/// the line is the world's horizon as the camera sees it, so it is level when the camera is.
struct AimLevelGauge: View {
    let model: AimViewModel
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isActive)) { _ in
            AimLevelDial(roll: model.engine.frame()?.pointing.roll)
        }
    }
}

private struct AimLevelDial: View {
    /// `PointingSolution.roll` in degrees: positive when the camera is turned clockwise (its right side lower).
    let roll: Double?
    @Environment(\.palette) private var palette

    /// Rolls smaller than this count as level, in degrees.
    private static let levelTolerance = 0.5

    private var isLevel: Bool { roll.map { abs($0) <= Self.levelTolerance } ?? false }

    var body: some View {
        let color = isLevel ? palette.positive : palette.guidance
        VStack(spacing: 2) {
            ZStack {
                Circle().strokeBorder(palette.stroke, lineWidth: 1.5)
                // A camera rolled clockwise sees the horizon turn counter-clockwise; SwiftUI turns clockwise.
                Capsule()
                    .fill(color)
                    .frame(width: 42, height: 3)
                    .rotationEffect(.degrees(-(roll ?? 0)))
                Rectangle()
                    .fill(palette.tertiaryText)
                    .frame(width: 6, height: 1)
                    .offset(x: -26)
                Rectangle()
                    .fill(palette.tertiaryText)
                    .frame(width: 6, height: 1)
                    .offset(x: 26)
            }
            .frame(width: 58, height: 58)
            .background(Circle().fill(palette.surface.opacity(0.7)))
            Label(isLevel ? "Level" : rollText, systemImage: isLevel ? "checkmark" : "level")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 66)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera level")
        .accessibilityValue(isLevel ? "Level" : rollText)
    }

    private var rollText: String {
        guard let roll else { return AppFormat.missing }
        return "\(AimFormat.angle(roll)) \(roll > 0 ? "right" : "left")"
    }
}
