import SwiftUI
import LodestarKit

/// A line drawing of a mount at its home position, seen from the side with north on the right: where the telescope or
/// camera points and, for an equatorial mount, where the polar axis and the counterweight shaft are.
struct MountHomeDrawing: View {
    let arrangement: SkyWatcherMountMode
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 200, size.height / 120)
            let origin = CGPoint(x: (size.width - 200 * unit) / 2, y: (size.height - 120 * unit) / 2)
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
            }
            let line = palette.secondaryText
            let highlight = palette.accent

            // The ground and the tripod.
            var ground = Path()
            ground.move(to: point(10, 108))
            ground.addLine(to: point(190, 108))
            context.stroke(ground, with: .color(palette.tertiaryText), lineWidth: 2)
            var tripod = Path()
            tripod.move(to: point(100, 72))
            tripod.addLine(to: point(70, 108))
            tripod.move(to: point(100, 72))
            tripod.addLine(to: point(130, 108))
            tripod.move(to: point(100, 72))
            tripod.addLine(to: point(100, 108))
            context.stroke(tripod, with: .color(line), lineWidth: 2.5)

            switch arrangement {
            case .altAzimuth:
                // A level base and a level telescope pointing north (to the right), with the spirit level line.
                let base = Path(roundedRect: CGRect(x: point(88, 60).x, y: point(88, 60).y, width: 24 * unit, height: 12 * unit),
                                cornerRadius: 3 * unit)
                context.stroke(base, with: .color(line), lineWidth: 2.5)
                let tube = Path(roundedRect: CGRect(x: point(96, 40).x, y: point(96, 40).y, width: 62 * unit, height: 12 * unit),
                                cornerRadius: 3 * unit)
                context.stroke(tube, with: .color(highlight), lineWidth: 3)
                var support = Path()
                support.move(to: point(100, 60))
                support.addLine(to: point(100, 52))
                context.stroke(support, with: .color(line), lineWidth: 2.5)
                var level = Path()
                level.move(to: point(60, 46))
                level.addLine(to: point(168, 46))
                context.stroke(level, with: .color(palette.tertiaryText),
                               style: StrokeStyle(lineWidth: 1, dash: [4 * unit, 3 * unit]))
                arrow(from: point(160, 46), to: point(184, 46), color: highlight, in: &context, unit: unit)
                context.draw(Text("N").font(.caption.weight(.bold)).foregroundStyle(highlight), at: point(188, 34))
                context.draw(Text("level").font(.caption2).foregroundStyle(line), at: point(34, 38))
            case .equatorial:
                // The polar axis rises to the right towards the pole; the camera lies along it; the counterweight shaft
                // hangs straight down.
                let pivot = point(100, 72)
                let pole = point(160, 20)
                var axis = Path()
                axis.move(to: pivot)
                axis.addLine(to: pole)
                context.stroke(axis, with: .color(line), lineWidth: 3)
                var camera = Path()
                camera.move(to: point(112, 62))
                camera.addLine(to: point(152, 28))
                context.stroke(camera, with: .color(highlight), lineWidth: 8 * unit)
                context.fill(Path(ellipseIn: CGRect(x: pole.x - 4 * unit, y: pole.y - 4 * unit, width: 8 * unit, height: 8 * unit)),
                             with: .color(highlight))
                context.draw(Text("pole").font(.caption.weight(.bold)).foregroundStyle(highlight), at: point(176, 14))
                var shaft = Path()
                shaft.move(to: point(100, 72))
                shaft.addLine(to: point(100, 100))
                context.stroke(shaft, with: .color(line), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: point(92, 92).x, y: point(92, 92).y, width: 16 * unit, height: 16 * unit)),
                             with: .color(highlight))
                // Level with the weight and right of the tripod's leg, which runs through x 118 to 128 at that height.
                context.draw(Text("counterweight").font(.caption2).foregroundStyle(line), at: point(134, 100), anchor: .leading)
            }
        }
        .aspectRatio(200.0 / 120.0, contentMode: .fit)
        .frame(maxWidth: 260)
        .accessibilityElement()
        .accessibilityLabel(Self.description(of: arrangement))
    }

    /// What the picture shows, for VoiceOver.
    static func description(of arrangement: SkyWatcherMountMode) -> String {
        switch arrangement {
        case .altAzimuth:
            return """
                Picture of the alt-azimuth home position: the tripod and the mount base level, the telescope level and \
                pointing north.
                """
        case .equatorial:
            return """
                Picture of the equatorial home position: the polar axis pointing at the celestial pole, the counterweight \
                bar pointing down at the ground, the telescope parallel to the polar axis and pointing at the pole.
                """
        }
    }

    private func arrow(from start: CGPoint, to end: CGPoint, color: Color, in context: inout GraphicsContext, unit: Double) {
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: end)
        context.stroke(shaft, with: .color(color), lineWidth: 2)
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - 5 * unit, y: end.y - 3 * unit))
        head.addLine(to: CGPoint(x: end.x - 5 * unit, y: end.y + 3 * unit))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}

/// The name of a set-up in the texts and the pickers.
func mountArrangementTitle(_ mode: SkyWatcherMountMode) -> String {
    switch mode {
    case .altAzimuth: return "Alt-azimuth (AZ-GTi on its tripod)"
    case .equatorial: return "Equatorial (Star Adventurer GTi, EQ mounts, AZ-GTi on a wedge)"
    }
}

/// What to do with the mount before it is switched on, for each set-up.
func mountHomeSteps(_ mode: SkyWatcherMountMode) -> String {
    switch mode {
    case .altAzimuth:
        return """
            Level the tripod and the mount base. Point the telescope or camera level, not tilted, and towards north. A \
            compass is enough: 5\u{00B0} off is fine, the alignment finds the rest.
            """
    case .equatorial:
        return """
            Point the polar axis at the celestial pole as well as you can. Turn the counterweight bar so that it points \
            down at the ground. Point the telescope or camera parallel to the polar axis, at the pole.
            """
    }
}

/// How to bring a Sky-Watcher mount to its home position before it is switched on: the words and a drawing for the
/// chosen set-up, or for both while the set-up is left to the mount model. The mount counts its motor steps from the
/// position it is switched on in and knows nothing about the sky.
struct MountHomeGuide: View {
    let arrangement: MountArrangementChoice
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text("Before you switch the mount on")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                SettingsCaption("""
                    Put the mount at its home position, and only then switch it on. The mount remembers where it stood \
                    when it was switched on and Lodestar counts every move from there, so do not turn the mount by hand \
                    afterwards.
                    """)
                if arrangement == .automatic {
                    SettingsCaption("""
                        Lodestar takes the arrangement from the mount model when it connects. For an AZ-GTi on a wedge \
                        choose Equatorial under Advanced options.
                        """)
                }
            }
            ForEach(modes, id: \.self) { mode in
                VStack(alignment: .leading, spacing: 8) {
                    Text(mountArrangementTitle(mode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    MountHomeDrawing(arrangement: mode)
                        .frame(maxWidth: .infinity)
                    SettingsCaption(mountHomeSteps(mode))
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var modes: [SkyWatcherMountMode] {
        arrangement.mode.map { [$0] } ?? [.altAzimuth, .equatorial]
    }
}
