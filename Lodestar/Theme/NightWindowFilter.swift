import UIKit

/// A red view that multiplies everything under it: white becomes red, green and blue become black.
///
/// Solves: on iOS 26 the system chrome (the glass tab bar, back button, Done capsule, switches, segmented pickers, the
/// search field) ignores the palette, so night mode shows white and grey pixels. A multiply by pure red turns every
/// pixel of the window red or black, whoever drew it. Touches pass through it. It only uses public API
/// (`CALayer.compositingFilter` with the name of a Core Image blend filter); no private filter class is involved.
@MainActor
final class NightFilterView: UIView {
    /// Identifies the view among the subviews of a window.
    static let marker = 0x4E46

    override init(frame: CGRect) {
        super.init(frame: frame)
        tag = Self.marker
        backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        layer.compositingFilter = "multiplyBlendMode"
        // Sheets and alerts add their containers to the window after this view; a high z position keeps them under it.
        layer.zPosition = 1_000_000
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Never the target of a touch.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Puts a `NightFilterView` over every normal-level window of the app at night, and takes it away by day.
///
/// Called with `true` only on iOS 26 and later (the caller checks, see `NightChrome.isActive`). A window that appears
/// later (a scene that connects, a sheet's window) gets the view when the notification below arrives.
@MainActor
enum NightWindowFilter {
    private static var isOn = false
    private static var observers: [NSObjectProtocol] = []
    private static var lastReport = ""

    /// Switches the filter on or off for the windows that exist now and the ones that appear later.
    static func setActive(_ on: Bool) {
        guard on || isOn else { return }
        isOn = on
        startObserving()
        refresh()
        // At launch the window may not exist yet, and a sheet that is being presented adds its container a moment later.
        Task { @MainActor in
            refresh()
        }
    }

    private static func startObserving() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [UIScene.didActivateNotification, UIWindow.didBecomeVisibleNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    NightWindowFilter.refresh()
                }
            }
        }
    }

    /// Adds, raises or removes the filter view of each window to match `isOn`.
    static func refresh() {
        var windows = 0
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.windowLevel == .normal {
                let existing = window.subviews.compactMap { $0 as? NightFilterView }.first
                guard isOn else {
                    existing?.removeFromSuperview()
                    continue
                }
                let filter = existing ?? NightFilterView(frame: window.bounds)
                if existing == nil { window.addSubview(filter) }
                if window.subviews.last !== filter { window.bringSubviewToFront(filter) }
                windows += 1
            }
        }
        let report = isOn ? "win: filter on \(windows) window(s), filter=multiplyBlendMode" : "win: filter off"
        if report != lastReport {
            lastReport = report
            NightChrome.log(report)
        }
    }
}
