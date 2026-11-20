import SwiftUI

/// The watch app's Aim page: what the iPhone's Aim screen asks of the photographer, readable at a glance while both
/// hands are on the tripod head. A big arrow along the pan and tilt axes, the moves in degrees, the distance and the
/// target; a check mark when on target; "Waiting for iPhone" when the phone says nothing. In the phone's night mode the
/// page is pure red.
struct WatchAimView: View {
    @Environment(WatchAimModel.self) private var model

    var body: some View {
        // Once a second the page notices that the messages have stopped.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let message = model.current(at: context.date) {
                AimPage(message: message)
            } else {
                AimWaiting(style: isNight ? .night : .day)
            }
        }
        .containerBackground((isNight ? AimStyle.night : AimStyle.day).background, for: .tabView)
    }

    /// Whether the phone's last message said night mode.
    private var isNight: Bool { model.latest?.message.isNight ?? false }
}

/// The colours of the page: the Tonight screen's day colours, or red shades only at night.
private struct AimStyle {
    let background: Color
    let primary: Color
    let secondary: Color
    let onTarget: Color

    static let day = AimStyle(background: TonightStyle.background, primary: TonightStyle.primaryText,
                              secondary: TonightStyle.secondaryText, onTarget: Color(red: 0.30, green: 0.85, blue: 0.45))
    static let night = AimStyle(background: .black, primary: Color(red: 1, green: 0.22, blue: 0.18),
                                secondary: Color(red: 0.62, green: 0.14, blue: 0.12),
                                onTarget: Color(red: 1, green: 0.22, blue: 0.18))
}

private struct AimPage: View {
    let message: AimWristMessage

    private var style: AimStyle { message.isNight ? .night : .day }

    var body: some View {
        VStack(spacing: 4) {
            if message.isBelowHorizon {
                status(symbol: "arrow.down.to.line", text: "Below the horizon", color: style.primary)
            } else if message.isOnTarget {
                status(symbol: "checkmark.circle.fill", text: "On target", color: style.onTarget)
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(style.primary)
                    .rotationEffect(.radians(-message.arrowAngle))
                    .frame(height: 48)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(message.moves, id: \.self) { move in
                        Text(move)
                            .font(.headline)
                            .foregroundStyle(style.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Text(message.distanceText)
                    .font(.caption2)
                    .foregroundStyle(style.secondary)
            }
            if !message.targetName.isEmpty {
                Text(message.targetName)
                    .font(.caption2)
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message.spokenSummary)
    }

    private func status(symbol: String, text: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.headline)
                .foregroundStyle(color)
        }
    }
}

private struct AimWaiting: View {
    let style: AimStyle

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(style.secondary)
                .accessibilityHidden(true)
            Text("Waiting for iPhone\u{2026}")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(style.primary)
                .multilineTextAlignment(.center)
            Text("Open Aim on your iPhone and pick a target.")
                .font(.caption2)
                .foregroundStyle(style.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
