import SwiftUI
import LodestarKit

/// Everything about one object: what it is, where it is now, how tonight goes, and how to photograph it.
///
/// Push it from any `NavigationStack`; its "Aim" button points the Aim screen at the object.
struct ObjectDetailView: View {
    let object: CelestialObject

    init(object: CelestialObject) {
        self.object = object
    }

    var body: some View {
        ObjectDetailContent(object: object)
            // A different object starts from scratch instead of showing the previous one's data.
            .id(object.id)
    }
}

/// The detail screen's scrolling content and the task that keeps its data fresh.
private struct ObjectDetailContent: View {
    /// How often the object's position and the night's data are refreshed while the screen is open.
    private static let refreshInterval: Duration = .seconds(30)

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let object: CelestialObject
    @State private var snapshot: ObjectDetailSnapshot?

    var body: some View {
        let context = app.observerContext
        ScrollView {
            VStack(spacing: 16) {
                ObjectDetailHeader(object: object)
                if let context {
                    ObjectDetailNowCard(current: snapshot?.current, style: app.settings.coordinateStyle)
                    ObjectDetailTonightCard(object: object, night: snapshot?.night, now: snapshot?.current.date,
                                            timeZone: context.timeZone)
                } else {
                    NeedsLocationView()
                        .frame(minHeight: 300)
                        .card(palette)
                }
                SmallBodyTailCard(detail: snapshot?.current.smallBody)
                ObjectDetailPhotographyCard(object: object, snapshot: snapshot, lens: app.lensSetup,
                                            timeZone: context?.timeZone ?? .autoupdatingCurrent)
                if ObjectDetailAboutCard.hasContent(for: object) {
                    ObjectDetailAboutCard(object: object)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .screenBackground(palette)
        .navigationTitle(SmallBodyText.displayName(object))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: context) {
            await keepSnapshotFresh(for: context)
        }
    }

    /// Computes the snapshot right away and then every `refreshInterval` until the task is cancelled.
    private func keepSnapshotFresh(for context: ObserverContext?) async {
        guard let context else {
            snapshot = nil
            return
        }
        var night: ObjectDetailNight?
        while !Task.isCancelled {
            let input = ObjectDetailInput(object: object, context: context, date: app.clock.now, previousNight: night)
            let computed = await Task.detached(priority: .userInitiated) {
                ObjectDetailCalculator.snapshot(for: input)
            }.value
            guard !Task.isCancelled else { return }
            night = computed.night
            snapshot = computed
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}

/// The top card of the detail screen: names, type chips and the Aim and favorite buttons.
struct ObjectDetailHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let object: CelestialObject

    private var isFavorite: Bool {
        app.settings.favoriteObjectIDs.contains(object.id)
    }

    /// Custom targets are not in the catalog, so they could not be found again as favorites.
    private var canBeFavorite: Bool {
        !object.id.hasPrefix("custom.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ObjectIcon(category: object.category, size: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(object.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                    if let designations = ObjectsFormat.designationsLine(of: object) {
                        Text(designations)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }
            HStack(spacing: 10) {
                aimButton
                if canBeFavorite {
                    favoriteButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    @ViewBuilder
    private var chips: some View {
        StatusChip(systemImage: object.category.systemImageName, text: object.category.displayName)
        if let constellation = object.constellationName {
            StatusChip(systemImage: "map", text: constellation)
        }
        if let magnitude = object.magnitude {
            StatusChip(systemImage: "sparkle", text: AppFormat.magnitude(magnitude))
        }
        if object.isDeepSky {
            StatusChip(systemImage: "star.circle", text: object.prominence.displayName)
        }
        if object.category == .sun {
            StatusChip(systemImage: "exclamationmark.triangle", text: "Solar filter required", tone: .warning)
        }
    }

    private var aimButton: some View {
        Button {
            app.aim(at: object)
        } label: {
            // Comet designations are long; with large text the name wraps instead of being cut off.
            Label("Aim at \(SmallBodyText.displayName(object))", systemImage: "scope")
                .lineLimit(4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.lodestarPrimary)
    }

    private var favoriteButton: some View {
        Button {
            app.settingsStore.toggleFavorite(object.id)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .frame(minWidth: 24)
        }
        .buttonStyle(.lodestarSecondary)
        .disabled(!isFavorite && app.settings.favoriteObjectIDs.count >= AppSettings.maximumFavorites)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }
}
