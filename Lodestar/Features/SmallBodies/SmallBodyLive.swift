import SwiftUI
import LodestarKit

/// What the app knows about a comet or asteroid at the moment: `info`, or `nil` when the orbit cannot be evaluated
/// (`isComputed` says whether the position has been worked out at all yet).
struct SmallBodyLive: Sendable, Equatable {
    /// Before the first computation: nothing is claimed yet.
    static let pending = SmallBodyLive(isComputed: false, info: nil)
    /// How often the numbers are worked out again (they change slowly).
    static let refreshInterval: Duration = .seconds(10)

    let isComputed: Bool
    let info: SmallBodyInfo?

    /// The one line under the name: kind, magnitude estimate and elongation, without the warnings (the notes say
    /// them).
    func subtitle(of object: CelestialObject) -> String {
        SmallBodyText.subtitle(of: object, info: info, isComputed: isComputed, withWarnings: false)
    }

    /// The live info of `object`, worked out now and then every ten seconds until the calling task is cancelled.
    /// Hands each result to `apply`; returns at once for an object that is neither a comet nor an asteroid.
    @MainActor
    static func keepCurrent(of object: CelestialObject, clock: SkyClock, apply: @MainActor (SmallBodyLive) -> Void) async {
        guard let body = object.smallBody else { return }
        while !Task.isCancelled {
            apply(SmallBodyLive(isComputed: true, info: SmallBodyInfo.compute(body, at: clock.now)))
            try? await Task.sleep(for: refreshInterval)
        }
    }
}

/// The line under an object's name in the Aim picker: a comet's or asteroid's kind, magnitude estimate and distance
/// from the Sun (kept current), the catalog subtitle of any other object. Style it from outside.
struct SmallBodySummaryText: View {
    @Environment(AppModel.self) private var app
    let object: CelestialObject
    @State private var live = SmallBodyLive.pending

    var body: some View {
        Text(summary)
            // The whole object, not its identifier: downloaded elements keep the identifier.
            .task(id: object) {
                await SmallBodyLive.keepCurrent(of: object, clock: app.clock) { live = $0 }
            }
    }

    private var summary: String {
        guard object.smallBody != nil else { return object.subtitle }
        return live.isComputed ? SmallBodyText.summary(of: object, info: live.info) : object.category.displayName
    }
}

/// The warnings of a comet or asteroid as notes inside the Aim target card: one line for each, nothing at all when
/// there is none (so the card gains no empty space).
struct SmallBodyAimNotes: View {
    @Environment(\.palette) private var palette
    let live: SmallBodyLive

    var body: some View {
        // The subtitle already says "no brightness data".
        let warnings = (live.info?.warnings ?? []).filter { $0 != .noBrightnessData }
        ForEach(warnings, id: \.self) { warning in
            Label(SmallBodyText.sentence(warning), systemImage: warning == .twilightGlow ? "sun.horizon" : "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.warning)
        }
    }
}
