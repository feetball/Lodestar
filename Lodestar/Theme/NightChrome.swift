import Foundation
import UIKit

/// Switches for the ways of turning the rest of the system chrome red at night on iOS 26 (see `NightWindowFilter` and
/// `ThemedRootModifier`). The app draws its own tab bar (`AppTabBar`) and colours the placeholders and the segment titles
/// itself; what is left is the glass of the back button, the toolbar and Done capsules, the switches, the segmented
/// pickers' track, the Objects search field, the slider ticks and the large titles, which ignore the palette, so night
/// mode is not pure red on black there.
///
/// Which way works is settled by the review (`.github/workflows/review-chrome.yml`): a Debug build reads the tokens of the
/// launch argument `nightchrome=<token>[+<token>...]` (see `ScreenshotMode`). Tokens in use:
///
///     base      nothing (the control run)
///     ovl       the SwiftUI multiply overlay, forced on at night (`ovl+g` with a compositing group under it)
///     win       a red multiply view over every window (`NightWindowFilter`)
///     t         a transparent navigation bar appearance, so the large title is not hidden by the bar background
///     ctl       palette-drawn replacements for the system controls (`NightControls`, `NightBars`); includes `t`
///     compat    a tag only: the workflow adds `UIDesignRequiresCompatibility` to the Info.plist of the built app
///
/// A Release build has no launch arguments and returns the defaults, which are all off, so it behaves as before.
enum NightChrome {
    /// Whether the way called `token` is switched on. `ctl` includes `t`.
    static func has(_ token: String) -> Bool {
        #if DEBUG
        guard let tokens = ScreenshotMode.current?.chrome else { return false }
        return tokens.contains(token) || (token == "t" && tokens.contains("ctl"))
        #else
        return false
        #endif
    }

    /// Whether the way called `token` is switched on and the system is iOS 26 or later, whatever the palette. For
    /// decisions about the structure of a screen, which must not change when night mode comes and goes.
    static func isEnabled(_ token: String) -> Bool {
        if #available(iOS 26, *) { return has(token) }
        return false
    }

    /// Whether the way called `token` is switched on and applies: at night, on iOS 26 or later (the system chrome of
    /// iOS 17 to 25 follows the palette, so those keep today's code path).
    static func isActive(_ token: String, night: Bool) -> Bool {
        night && isEnabled(token)
    }

    /// Reports that a way was active. A Debug build also appends the line to `chrome-log.txt` in the app's Documents
    /// folder, which the review script (`Tools/review/capture.sh`) copies next to the pictures: a picture without such a
    /// line was taken by the base behaviour.
    static func log(_ message: String) {
        #if DEBUG
        NSLog("nightchrome: %@", message)
        NightChromeLog.append(message)
        #endif
    }
}

#if DEBUG
/// The file `chrome-log.txt`, started afresh by each launch.
private enum NightChromeLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var started = false

    static func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("chrome-log.txt") else { return }
        let line = Data((message + "\n").utf8)
        if !started || !FileManager.default.fileExists(atPath: url.path) {
            started = true
            try? line.write(to: url, options: .atomic)
        } else if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }
}

extension NightChrome {
    /// Logs what the process was started with: the tokens, and whether the Info.plist carries the compatibility key
    /// (the `compat` run adds it to the built app).
    @MainActor
    static func logLaunch() {
        let tokens = (ScreenshotMode.current?.chrome ?? []).sorted().joined(separator: "+")
        let key = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility")
        let version = UIDevice.current.systemVersion
        log("launch tokens=\(tokens.isEmpty ? "none" : tokens) ios=\(version) "
            + "UIDesignRequiresCompatibility=\(key.map { "\($0)" } ?? "absent")")
    }

    /// Logs the class of the view that would receive a touch at three places of the key window, to show that the
    /// window filter does not take touches. Call once the screen is up.
    @MainActor
    static func logHitTests() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { return }
        let bounds = window.bounds
        let probes: [(String, CGPoint)] = [
            ("tab-bar-centre", CGPoint(x: bounds.midX, y: bounds.maxY - 60)),
            ("top-right", CGPoint(x: bounds.maxX - 50, y: window.safeAreaInsets.top + 22)),
            ("centre", CGPoint(x: bounds.midX, y: bounds.midY)),
        ]
        for (name, point) in probes {
            let hit = window.hitTest(point, with: nil)
            let kind = hit.map { String(describing: type(of: $0)) } ?? "nil"
            log("hit \(name)=\(kind) isFilter=\(hit is NightFilterView)")
        }
    }
}
#endif
