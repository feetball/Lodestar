#if DEBUG
import Foundation
import SwiftUI
import UIKit
import LodestarKit

/// Gets a screen ready for the capture script (`Tools/review/capture.sh`) and pages through it.
///
/// After launch it does what the screen needs besides opening: connects the simulated mount, sends it to the target.
/// Then it keeps a small state file in the app's Documents folder up to date (`review-state.txt`: the screen, whether
/// the set-up is done, the page shown and the number of pages the screen has) and obeys the page the script writes to
/// `review-cmd.txt` (`page=<n>`) by scrolling the largest scroll view that is on screen, one screenful less a few
/// lines at a time. Pages are counted from the scroll view as it is, so a lazily built list can have more pages once
/// the script has scrolled to the end.
@MainActor
final class ReviewDriver {
    static let shared = ReviewDriver()

    private var task: Task<Void, Never>?
    private var isReady = false
    private var page = 0
    private var lastState = ""

    /// Starts the driver when the launch arguments ask for it. Call once, after launch.
    func start(app: AppModel) {
        guard task == nil, let mode = ScreenshotMode.current, mode.runsReviewDriver else { return }
        task = Task { [weak self] in
            await self?.run(app: app, mode: mode)
        }
    }

    private var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func run(app: AppModel, mode: ScreenshotMode) async {
        write(state: "")
        await app.catalog.load()
        if mode.addsOnlineData {
            let place = app.observerContext?.location
            app.online.installReviewData(
                satellites: ReviewFixtures.satelliteGroups(now: Date()),
                forecast: place.flatMap {
                    ReviewFixtures.forecast(around: app.clock.now, latitude: $0.latitude, longitude: $0.longitude)
                },
                now: Date())
        }
        if let screen = mode.screen {
            await prepareMount(app: app, screen: screen)
            await prepareSatellite(app: app, screen: screen)
        }
        // Let the screen finish its first layout and its own background work before the script looks.
        try? await Task.sleep(for: .seconds(2))
        isReady = true
        while !Task.isCancelled {
            if let command = readCommand(), command != page {
                page = command
            }
            let pages = scroll(to: page)
            write(state: "page=\(page)\npages=\(pages)")
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    // MARK: Mount

    private func prepareMount(app: AppModel, screen: ReviewScreen) async {
        let service = MountService.shared
        let observer = app.observerContext?.observer
        switch screen.mount {
        case .none:
            return
        case .chooseSkyWatcher(let equatorial):
            service.selectedOptionID = MountConnectionOption.skyWatcher.id
            service.settings.arrangement = equatorial ? .equatorial : .altAzimuth
        case .demo:
            service.connectDemo(observer: observer)
            await waitForConnection(service)
            guard screen.slews, service.isConnected, let target = app.target, let observer else { return }
            await service.goTo(target, observer: observer)
        case .skyWatcher(let syncs):
            service.connectDemo(.demoSkyWatcher, observer: observer)
            await waitForConnection(service)
            guard service.isConnected, let observer, let catalog = app.catalog.catalog else { return }
            // Stars the way the set-up screen suggests them, for the real time: the simulated mount runs on it.
            var used: [EquatorialCoordinate] = []
            for index in 0...syncs {
                let date = Date()
                let candidates = await Task.detached(priority: .userInitiated) {
                    MountAlignmentSuggestions.candidates(catalog: catalog, observer: observer, date: date)
                }.value
                guard let star = MountAlignmentSuggestions.suggest(candidates, used: used, count: 1).first?.candidate
                else { return }
                if index == syncs {
                    // The last star is the target the screen offers to sync on.
                    app.select(target: star.object)
                    return
                }
                await service.centreSimulatedMount(on: star.object, observer: observer)
                await service.syncMount(to: star.object, observer: observer)
                used.append(star.j2000)
            }
        }
    }

    // MARK: Satellite

    /// Leads Aim to the first pass of the ISS (or of whatever satellite comes first): the satellite itself or the point where
    /// the pass peaks.
    private func prepareSatellite(app: AppModel, screen: ReviewScreen) async {
        guard screen == .aimSatellite || screen == .aimSatellitePeak,
              let observer = app.observerContext?.observer else { return }
        let library = app.online.satellites
        let start = app.clock.now
        let items = await Task.detached(priority: .userInitiated) {
            SatellitePasses.compute(library: library, observer: observer, start: start)
        }.value
        guard let item = items.first(where: \.isISS) ?? items.first else { return }
        app.satelliteAim.start(screen == .aimSatellite ? .follow(item, observer: observer) : .peak(item, observer: observer))
    }

    private func waitForConnection(_ service: MountService) async {
        for _ in 0..<50 {
            if service.isConnected { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: Files

    private func readCommand() -> Int? {
        guard let url = documents?.appendingPathComponent("review-cmd.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("page=") {
            return Int(line.dropFirst("page=".count))
        }
        return nil
    }

    private func write(state: String) {
        let mode = ScreenshotMode.current
        let name = mode?.screen == nil ? "none" : (mode?.screenName ?? "none")
        let text = "screen=\(name)\nready=\(isReady ? 1 : 0)\n\(state)\n"
        guard text != lastState, let url = documents?.appendingPathComponent("review-state.txt") else { return }
        lastState = text
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Scrolling

    /// Scrolls to `page` (counted from 0, clamped to the last) and returns how many pages the scroll view has.
    private func scroll(to page: Int) -> Int {
        guard let scrollView = pagedScrollView() else { return 1 }
        let insets = scrollView.adjustedContentInset
        let visible = scrollView.bounds.height - insets.top - insets.bottom
        let step = max(visible - 80, 120)
        let minimum = -insets.top
        let maximum = max(minimum, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        let pages = Int(((maximum - minimum) / step).rounded(.up)) + 1
        let target = min(minimum + CGFloat(page) * step, maximum)
        if abs(scrollView.contentOffset.y - target) > 1 {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
        }
        return pages
    }

    /// The vertical scroll view that has the most of the screen: the one of the topmost presented screen.
    private func pagedScrollView() -> UIScrollView? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { return nil }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let root = controller?.view else { return nil }
        var best: (view: UIScrollView, area: CGFloat)?
        func visit(_ view: UIView) {
            if let scrollView = view as? UIScrollView, !scrollView.isHidden, scrollView.alpha > 0.01,
               scrollView.window != nil, scrollView.bounds.width > 150,
               scrollView.contentSize.height > scrollView.bounds.height + 20 {
                let frame = scrollView.convert(scrollView.bounds, to: window).intersection(window.bounds)
                let area = frame.isNull ? 0 : frame.width * frame.height
                if area > (best?.area ?? 0) { best = (scrollView, area) }
            }
            for subview in view.subviews { visit(subview) }
        }
        visit(root)
        return best?.view
    }
}
#endif
