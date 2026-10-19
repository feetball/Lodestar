import SwiftUI
import LodestarKit

/// The big arrow around the reticle that points the way to the target, replaced by a ring, a check mark and the words
/// "On target" once the camera is there.
///
/// It redraws about 30 times a second on its own timeline, so the arrow follows the phone smoothly without the
/// surrounding view being touched.
struct GuidanceArrowView: View {
    let model: AimViewModel
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            let radius = AimArrowContent.orbitRadius(forScreenHeight: geometry.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { _ in
                AimArrowContent(guidance: model.engine.frame()?.guidance, rotation: model.hudRotation, radius: radius)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AimArrowContent: View {
    let guidance: Guidance?
    let rotation: AimHUDRotation
    /// Distance in points from the reticle to the middle of the arrow's glyph; also the radius of the ring.
    let radius: CGFloat
    @Environment(\.palette) private var palette

    /// The ring grows with the screen but leaves room for the panels on a small one.
    static func orbitRadius(forScreenHeight height: CGFloat) -> CGFloat {
        min(100, max(70, height * 0.115))
    }

    var body: some View {
        ZStack {
            if let guidance {
                if guidance.state == .onTarget {
                    onTargetBadge
                } else {
                    arrow(for: guidance)
                }
            }
        }
    }

    /// The arrow orbits the reticle and points along the shortest way to the target.
    ///
    /// `Guidance.arrowAngle` counts counter-clockwise from screen-right with y pointing up. SwiftUI rotates
    /// clockwise with y pointing down, so a glyph that points right is turned by the negative angle. The arrow
    /// lives in the phone's own screen axes, so it ignores the HUD rotation: it always points the way on the glass.
    private func arrow(for guidance: Guidance) -> some View {
        let scale = 0.65 + 0.35 * min(1, guidance.separation / 20)
        return ZStack {
            Circle()
                .stroke(palette.guidance.opacity(0.25), lineWidth: 1)
                .frame(width: 2 * radius, height: 2 * radius)
            AimArrowShape()
                .fill(palette.guidance)
                .overlay(AimArrowShape().stroke(Color.black.opacity(0.55), lineWidth: 1.5))
                .frame(width: 64 * scale, height: 46 * scale)
                .offset(x: radius)
                .frame(width: 2 * radius, height: 2 * radius)
                .rotationEffect(.radians(-guidance.arrowAngle))
            label(AimFormat.angle(guidance.separation), color: palette.guidance, size: 26)
        }
    }

    /// A ring, a check mark and a word: the state does not depend on colour alone.
    private var onTargetBadge: some View {
        ZStack {
            Circle()
                .stroke(palette.positive, lineWidth: 5)
                .frame(width: 2 * radius, height: 2 * radius)
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(palette.positive)
                .rotationEffect(.degrees(rotation.degrees))
                .offset(rotation.rotated(CGSize(width: 0, height: -0.32 * radius)))
            label("On target", color: palette.positive, size: 22, offset: -0.72 * radius)
        }
    }

    /// Distance of the distance readout from the reticle: inside the ring, above the reticle as the reader sees it.
    /// The texts stay in the upper half of the ring because the panels at the bottom of the screen can reach up over
    /// the lower half (with a mount connected, for example).
    private static let labelOffset: CGFloat = -50

    /// A text that turns with the HUD so it reads upright, `offset` points from the reticle (negative is up).
    private func label(_ text: String, color: Color, size: CGFloat, offset: CGFloat = labelOffset) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.7), radius: 3)
            .rotationEffect(.degrees(rotation.degrees))
            .offset(rotation.rotated(CGSize(width: 0, height: offset)))
    }
}

/// An arrow that points right: a shaft and a triangular head.
struct AimArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let headLength = rect.width * 0.46
        let shaftHalf = rect.height * 0.17
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - headLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - headLength, y: rect.midY - shaftHalf))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY - shaftHalf))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + shaftHalf))
        path.addLine(to: CGPoint(x: rect.maxX - headLength, y: rect.midY + shaftHalf))
        path.addLine(to: CGPoint(x: rect.maxX - headLength, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
