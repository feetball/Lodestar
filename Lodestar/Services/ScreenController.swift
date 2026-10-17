import UIKit

/// Night-mode brightness and the idle timer.
///
/// Brightness set through `UIScreen` outlives the app until the device locks, so the user's own value is
/// remembered when the first override is applied and put back by `setBrightnessOverride(nil)` or `restore()`.
/// The screen comes from the foreground window scene because `UIScreen.main` is deprecated in iOS 26.
@MainActor
final class ScreenController {
    /// Overrides below this level also switch on software dimming, which can go darker than the panel's minimum.
    private static let softwareDimmingThreshold = 0.05

    private var originalBrightness: CGFloat?
    private var appliedBrightness: CGFloat?

    /// Dims the screen to `value` (0…1), or gives the user's brightness back when `value` is `nil`.
    /// Repeating the same value is free and does not fight a brightness change the user made meanwhile.
    func setBrightnessOverride(_ value: Double?) {
        guard let value, value.isFinite else {
            restoreBrightness()
            return
        }
        guard let screen = foregroundScreen else { return }
        let target = CGFloat(min(max(value, 0), 1))
        if originalBrightness == nil { originalBrightness = screen.brightness }
        guard appliedBrightness != target else { return }
        screen.wantsSoftwareDimming = Double(target) < Self.softwareDimmingThreshold
        screen.brightness = target
        appliedBrightness = target
    }

    /// Keeps the display awake while `disabled` is `true`; only the Aim screen should need that.
    func setIdleTimerDisabled(_ disabled: Bool) {
        let application = UIApplication.shared
        if application.isIdleTimerDisabled != disabled {
            application.isIdleTimerDisabled = disabled
        }
    }

    /// Gives back the user's brightness and lets the display sleep again. Call when leaving the app and on teardown.
    func restore() {
        restoreBrightness()
        setIdleTimerDisabled(false)
    }

    // MARK: Private

    private var foregroundScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }

    private func restoreBrightness() {
        guard let original = originalBrightness, let screen = foregroundScreen else { return }
        screen.brightness = original
        screen.wantsSoftwareDimming = false
        originalBrightness = nil
        appliedBrightness = nil
    }
}
