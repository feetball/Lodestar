import Foundation
import LodestarKit
import Observation
import SwiftUI

/// Everything the chart's content depends on: the scene is rebuilt whenever one of these changes.
struct SkyChartInputs: Equatable, Sendable {
    let observer: ObserverContext
    /// The instant to draw, already rounded down to `SkyChartModel.timeBucket` seconds.
    let date: Date
    let options: SkySnapshotOptions
    let target: CelestialObject?
    /// The mosaic being shot, whose panels are drawn.
    let mosaic: MosaicPlan?
    /// Whether the catalog was loaded when these inputs were made (the chart cannot be built before).
    let isCatalogLoaded: Bool
}

/// The object a tap selected, with its position at the chart's instant.
struct SkyChartSelection: Equatable {
    let object: CelestialObject
    /// Refreshed whenever the chart is rebuilt for another time.
    var horizontal: HorizontalCoordinate
    /// The current magnitude, when known (the Sun, Moon and planets change theirs).
    var magnitude: Double?
    /// Distance, elongation and warnings of a selected comet or asteroid; `nil` for any other object.
    var smallBody: SmallBodyInfo?
}

/// Builds the sky chart's scene off the main actor and holds what the chart shows: the scene,
/// the zoom and pan, the selected object and the object whose detail screen is open.
///
/// The Sun, Moon and stars only move a little each second, so the scene is built for a rounded
/// instant and at most four times a second, however fast the time slider moves.
@MainActor
@Observable
final class SkyChartModel {
    /// The instants scenes are built for are multiples of this many seconds.
    static let timeBucket: TimeInterval = 30
    /// The shortest time between the starts of two scene builds.
    static let minimumRebuildInterval: Duration = .milliseconds(250)

    /// What the chart shows; `nil` until the first scene is built.
    private(set) var content: SkyChartContent?
    private(set) var selection: SkyChartSelection?
    private(set) var zoom: CGFloat = 1
    private(set) var pan: CGSize = .zero
    /// The object whose detail screen is pushed on the navigation stack.
    var detailObject: CelestialObject?

    @ObservationIgnored private var catalog: Catalog?
    @ObservationIgnored private var pending: BuildRequest?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var lastBuildStart: ContinuousClock.Instant?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var panReachesHorizon = false

    private struct BuildRequest: Sendable {
        let catalog: Catalog
        let inputs: SkyChartInputs

        func build() -> (scene: SkyChartScene, paths: SkyChartPaths, frame: SkyFrame) {
            let snapshot = SkySnapshotBuilder.build(catalog: catalog, observer: inputs.observer.observer,
                                                    date: inputs.date, options: inputs.options, target: inputs.target,
                                                    mosaic: inputs.mosaic)
            let scene = SkyChartSceneBuilder.build(from: snapshot, horizon: inputs.observer.horizon)
            return (scene, SkyChartPaths(scene: scene), snapshot.frame)
        }
    }

    /// Rounds `date` down to a multiple of `timeBucket`.
    static func bucketed(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / timeBucket).rounded(.down) * timeBucket)
    }

    // MARK: Building

    /// Requests a scene for `inputs`. Requests that arrive while one is being built or waiting
    /// out the rebuild interval replace each other; only the newest is built.
    func update(catalog: Catalog, inputs: SkyChartInputs) {
        self.catalog = catalog
        pending = BuildRequest(catalog: catalog, inputs: inputs)
        guard worker == nil else { return }
        worker = Task { await buildPendingScenes() }
    }

    private func buildPendingScenes() async {
        defer { worker = nil }
        while pending != nil {
            if let lastBuildStart {
                let wait = Self.minimumRebuildInterval - (ContinuousClock.now - lastBuildStart)
                if wait > .zero { try? await Task.sleep(for: wait) }
            }
            guard !Task.isCancelled, let request = pending else { return }
            pending = nil
            lastBuildStart = .now
            let built = await Task.detached(priority: .userInitiated) { request.build() }.value
            apply(scene: built.scene, paths: built.paths, frame: built.frame)
        }
    }

    private func apply(scene: SkyChartScene, paths: SkyChartPaths, frame: SkyFrame) {
        revision += 1
        content = SkyChartContent(scene: scene, paths: paths, frame: frame, revision: revision)
        if let current = selection {
            selection = Self.selection(for: current.object, in: scene)
        }
    }

    // MARK: Selection

    /// Selects what a tap at `location` hit, or clears the selection when it hit nothing.
    func handleTap(at location: CGPoint, in viewport: PlanisphereViewport) {
        guard let scene = content?.scene, let hit = scene.pickable(near: location, in: viewport),
              let object = hit.object ?? catalog?.object(id: hit.id) else {
            selection = nil
            return
        }
        select(object)
    }

    func select(_ object: CelestialObject) {
        guard let scene = content?.scene else { return }
        selection = Self.selection(for: object, in: scene)
    }

    func clearSelection() {
        selection = nil
    }

    private static func selection(for object: CelestialObject, in scene: SkyChartScene) -> SkyChartSelection {
        let frame = SkyFrame(date: scene.date, observer: scene.observer)
        return SkyChartSelection(object: object, horizontal: frame.horizontal(of: object, refraction: true),
                                 magnitude: frame.currentMagnitude(of: object),
                                 smallBody: object.smallBody.flatMap { SmallBodyInfo.compute($0, frame: frame) })
    }

    // MARK: Zoom and pan

    /// Zooms by `ratio` keeping the chart point under `anchor` (a position in a view of `size`) in place.
    func zoom(by ratio: CGFloat, around anchor: CGPoint, in size: CGSize) {
        let range = PlanisphereViewport.zoomRange
        let newZoom = min(max(zoom * ratio, range.lowerBound), range.upperBound)
        let anchored = PlanisphereViewport.pan(pan, keeping: anchor, fixedIn: size, from: zoom, to: newZoom)
        zoom = newZoom
        pan = PlanisphereViewport.clampedPan(anchored, zoom: newZoom, in: size, reachesHorizon: panReachesHorizon)
    }

    /// Moves the chart by `translation` points.
    func pan(by translation: CGSize, in size: CGSize) {
        let moved = CGSize(width: pan.width + translation.width, height: pan.height + translation.height)
        pan = PlanisphereViewport.clampedPan(moved, zoom: zoom, in: size, reachesHorizon: panReachesHorizon)
    }

    /// Lets the middle of the view move out to the horizon, for a camera frame fixed there, or keeps it on the chart
    /// as usual; the current pan is limited to match.
    func setPanReachesHorizon(_ reaches: Bool, in size: CGSize) {
        panReachesHorizon = reaches
        pan = PlanisphereViewport.clampedPan(pan, zoom: zoom, in: size, reachesHorizon: reaches)
    }

    func resetViewport() {
        zoom = 1
        pan = .zero
    }
}
