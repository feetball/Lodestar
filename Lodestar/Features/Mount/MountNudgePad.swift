import SwiftUI
import LodestarKit

/// The four arrows that nudge the mount, the speed to nudge at, and a Stop button in the middle.
struct MountNudgeCard: View {
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var service = MountService.shared
        let rate = service.settings.nudgeRate
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Nudge", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            if service.capabilities?.canNudge == true {
                MountNudgePad()
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Speed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityHidden(true)
                    Picker("Nudge speed", selection: $service.settings.nudgeRate) {
                        ForEach(MountNudgeRate.allCases, id: \.self) { option in
                            Text(Self.title(of: option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(Self.caption(of: rate))
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Hold an arrow to keep moving, let go to stop. N, E, S and W are directions on the sky as on a "
                     + "sky chart: east is to the left when north is up. VoiceOver users double tap for a short move.")
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This mount cannot be nudged by Lodestar.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    static func title(of rate: MountNudgeRate) -> String {
        switch rate {
        case .guide: return "Guide"
        case .center: return "Center"
        case .find: return "Find"
        case .slew: return "Slew"
        }
    }

    /// "8\u{00D7} sidereal, about 2\u{2032} per second."
    static func caption(of rate: MountNudgeRate) -> String {
        let multiple = Int(rate.siderealMultiple)
        return "\(title(of: rate)): \(multiple)\u{00D7} the speed of the stars, about "
            + "\(AppFormat.separation(rate.degreesPerSecond)) per second."
    }
}

/// North on top, south below, east to the left and west to the right, Stop in the middle.
struct MountNudgePad: View {
    private var service: MountService { MountService.shared }

    var body: some View {
        let isEnabled = service.capabilities?.canNudge == true && service.status.phase != .slewing
        VStack(spacing: 8) {
            MountNudgeButton(direction: .north, symbol: "arrow.up", isEnabled: isEnabled)
            HStack(spacing: 8) {
                MountNudgeButton(direction: .east, symbol: "arrow.left", isEnabled: isEnabled)
                MountStopButton(isCompact: true, minHeight: 64)
                    .frame(width: 76)
                MountNudgeButton(direction: .west, symbol: "arrow.right", isEnabled: isEnabled)
            }
            MountNudgeButton(direction: .south, symbol: "arrow.down", isEnabled: isEnabled)
        }
    }
}

/// One arrow. Pressing it starts the nudge and lifting the finger ends it; a gesture that is cancelled (a call, a
/// system gesture, the view going away) ends it as well.
private struct MountNudgeButton: View {
    let direction: MountNudgeDirection
    let symbol: String
    let isEnabled: Bool
    @Environment(\.palette) private var palette
    @GestureState private var isHeld = false
    private var service: MountService { MountService.shared }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
            Text(letter)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(isHeld ? palette.onAccent : palette.accent)
        .frame(width: 76, height: 64)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isHeld ? palette.accent : palette.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.stroke, lineWidth: 1))
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isHeld) { _, state, _ in state = isEnabled }
        )
        .onChange(of: isHeld) { _, held in
            if held {
                service.beginNudge(direction)
            } else {
                service.endNudge()
            }
        }
        .onDisappear { service.endNudge() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Move \(name)")
        .accessibilityHint("Double tap for a short move.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled { service.nudgeOnce(direction) } }
    }

    private var letter: String {
        switch direction {
        case .north: return "N"
        case .south: return "S"
        case .east: return "E"
        case .west: return "W"
        }
    }

    private var name: String {
        switch direction {
        case .north: return "north"
        case .south: return "south"
        case .east: return "east"
        case .west: return "west"
        }
    }
}
