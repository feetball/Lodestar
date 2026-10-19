import SwiftUI
import LodestarKit

/// The set-up of a connected Sky-Watcher mount in three steps: the start position, the location and time, and the alignment
/// on one to three stars (up to eight) with the stars so far, how well they fit, and the next stars to try.
///
/// The rows are a `Group`, so they become rows in a form and a stack in a card. `onSync` opens the confirmation to sync on the
/// Aim target; without it (Settings) the last row points to the Aim screen, where the nudge pad and the sky are.
struct MountSkyWatcherSetupRows: View {
    var onSync: (() -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var candidates: [MountStarCandidate] = []
    @State private var confirmation: MountConfirmation?
    private var service: MountService { MountService.shared }

    static let footer = "The mount has no sky of its own: Lodestar learns from the stars you centre where the mount really points."

    private static let alignmentGuide = """
        Pick a bright star that is high in the sky and make it the target. Switch tracking on with the Tracking switch so it \
        stays put, then centre it in the camera with the nudge arrows (Guide, Center and Find speeds) and tap Sync. Go to \
        stays off until the first star is synced. A second and third star far from the first make the mount much more \
        accurate.
        """

    private static let simulatedGuide = """
        Simulated mount: the Sync screen has a button that puts the simulated telescope on the target for you, instead of \
        the nudge arrows.
        """

    private static let maximumStars = 8
    private static let addStarsAboveDegrees = 0.3
    private static let suggestionRefresh: Duration = .seconds(30)

    var body: some View {
        Group {
            startPosition
            locationAndTime
            // The list of stars is kept current by one task, which belongs to this row alone.
            alignmentIntro
                .task(id: SuggestionKey(observer: app.observerContext?.observer,
                                        isCatalogLoaded: app.catalog.loadState == .loaded)) {
                    await keepSuggestionsCurrent()
                }
            summary
            starRows
            suggestionRows
            syncRow
        }
    }

    // MARK: 1. Start position

    private var startPosition: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepTitle("1. Start position")
            let away = service.startsAwayFromHome
            if let line = service.startPositionLine {
                Label(line, systemImage: away ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(away ? palette.warning : palette.positive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if away, let first = service.driverDetail?.startAxis1Degrees, let second = service.driverDetail?.startAxis2Degrees {
                InfoRow(label: "Axis angles at start",
                        value: "\(AngleFormatter.formatSignedDegrees(first, decimals: 1)) / "
                            + AngleFormatter.formatSignedDegrees(second, decimals: 1))
            }
            Button {
                Task { await service.declareHomePosition() }
            } label: {
                Label("This is home", systemImage: "location.fill")
            }
            .buttonStyle(.lodestarSecondary)
            .disabled(service.isWorking)
            SettingsCaption("""
                Tap this when the mount stands at its home position now, for example after you moved it there with the \
                arrows. It clears the star alignment.
                """)
        }
    }

    // MARK: 2. Location and time

    private var locationAndTime: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepTitle("2. Location and time")
            Text(MountAlignmentText.siteAndTime)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            SettingsCaption("Check that the phone's clock is set automatically.")
        }
    }

    // MARK: 3. Alignment

    private var alignmentIntro: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepTitle("3. Align on one to three stars")
            Text(Self.alignmentGuide)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if service.isDemo {
                SettingsCaption(Self.simulatedGuide)
            }
        }
    }

    /// The alignment so far: the line, the home position error and the accuracy, and Start over.
    private var summary: some View {
        let alignment = service.driverDetail?.alignment
        let isAligned = !(alignment?.stars.isEmpty ?? true)
        return VStack(alignment: .leading, spacing: 6) {
            Text(MountAlignmentText.line(alignment))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isAligned ? palette.positive : palette.warning)
                .fixedSize(horizontal: false, vertical: true)
            if isAligned, let home = service.alignmentHomeError {
                InfoRow(label: "Home position error", value: AngleFormatter.formatDegrees(home, decimals: 1))
            }
            if let predicted = alignment?.predictedErrorDegrees, isAligned {
                InfoRow(label: "Accuracy", value: "\u{2248} \(MountAlignmentText.accuracy(predicted)) away from these stars")
            }
            if isAligned, let count = alignment?.stars.count, count < Self.maximumStars,
               (alignment?.predictedErrorDegrees ?? 0) > Self.addStarsAboveDegrees {
                SettingsCaption("Add stars while the accuracy is poor, up to \(Self.maximumStars).")
            }
            if isAligned {
                Button {
                    Task { await service.clearAlignment() }
                } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(palette.critical)
                }
                .disabled(service.isWorking || service.status.phase != .idle)
            }
        }
    }

    /// The stars of the alignment, each with its residual and a way to drop it.
    @ViewBuilder
    private var starRows: some View {
        let stars = service.alignedStars
        ForEach(stars) { star in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(star.name)
                        .font(.body)
                        .foregroundStyle(palette.primaryText)
                    if stars.count > 1, let residual = star.residualDegrees {
                        Text("\(AngleFormatter.formatDegrees(residual, decimals: 2)) residual")
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                Button("Remove") {
                    Task { await service.removeAlignedStar(at: star.index) }
                }
                .buttonStyle(.lodestarSecondary)
                .disabled(service.isWorking || service.status.phase != .idle)
                .accessibilityLabel("Remove \(star.name) from the alignment")
            }
        }
    }

    /// The stars to try next; tapping one makes it the target.
    @ViewBuilder
    private var suggestionRows: some View {
        let used = (service.driverDetail?.alignment?.stars ?? []).map(\.place)
        let suggestions = MountAlignmentSuggestions.suggest(candidates, used: used)
        let isAligned = !used.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            Text(isAligned ? "Next star" : "First star")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.primaryText)
                .accessibilityAddTraits(.isHeader)
            if suggestions.isEmpty {
                SettingsCaption("No bright star is well placed right now. Try again when the sky has darkened.")
            } else {
                SettingsCaption(isAligned
                    ? "Bright and high, and at least 30\u{00B0} from the stars you used. Tap one to make it the target."
                    : "Bright and high in the sky. Tap one to make it the target.")
            }
        }
        .sheet(item: $confirmation) { confirmation in
            MountConfirmationSheet(confirmation: confirmation)
                .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        ForEach(suggestions) { suggestion in
            suggestionRow(suggestion, canGoTo: isAligned && service.status.phase == .idle)
        }
    }

    private func suggestionRow(_ suggestion: MountStarSuggestion, canGoTo: Bool) -> some View {
        let candidate = suggestion.candidate
        let isTarget = app.target?.id == candidate.object.id
        let away = suggestion.separationDegrees.map { " \u{00B7} \(AppFormat.separation($0)) from the nearest used" } ?? ""
        return HStack(spacing: 12) {
            Button {
                app.select(target: candidate.object)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.object.name + (isTarget ? " \u{00B7} target" : ""))
                        .font(.body)
                        .foregroundStyle(palette.primaryText)
                    Text("\(AppFormat.magnitude(candidate.magnitude)) \u{00B7} "
                        + "\(AppFormat.altitude(candidate.horizontal.altitude)) \u{00B7} "
                        + "\(AppFormat.azimuth(candidate.horizontal.azimuth))\(away)")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isTarget ? .isSelected : [])
            if canGoTo {
                Button("Go to") {
                    app.select(target: candidate.object)
                    confirmation = MountConfirmation(kind: .goTo, object: candidate.object)
                }
                .buttonStyle(.lodestarSecondary)
                .accessibilityLabel("Slew the mount to \(candidate.object.name)")
            }
        }
    }

    /// The step after the centring: tap Sync on the target, or open the Aim screen where the nudge pad and the sky are.
    private var syncRow: some View {
        let target = app.target
        return VStack(alignment: .leading, spacing: 6) {
            if let onSync, let target {
                Button(action: onSync) {
                    Label("Sync on \(target.name)", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                        .lineLimit(2)
                }
                .buttonStyle(.lodestarPrimary)
                .disabled(service.isWorking || service.status.phase != .idle)
                SettingsCaption("Only when the star is in the middle of the camera's frame.")
            } else if let target {
                Button {
                    app.selectedTab = .aim
                } label: {
                    Label("Open the Aim screen", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarSecondary)
                SettingsCaption("Centre \(target.name) with the nudge arrows there, then tap Sync.")
            } else {
                SettingsCaption("Choose a star above, or on the Aim screen, to make it the target.")
            }
        }
    }

    private func stepTitle(_ text: String) -> some View {
        Text(text)
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Suggestions

    private struct SuggestionKey: Equatable {
        var observer: Observer?
        var isCatalogLoaded: Bool
    }

    /// Makes the list of well-placed bright stars now and again every half minute.
    private func keepSuggestionsCurrent() async {
        guard let observer = app.observerContext?.observer, let catalog = app.catalog.catalog else { return }
        while !Task.isCancelled {
            let date = Date()
            let found = await Task.detached(priority: .userInitiated) {
                MountAlignmentSuggestions.candidates(catalog: catalog, observer: observer, date: date)
            }.value
            guard !Task.isCancelled else { return }
            candidates = found
            try? await Task.sleep(for: Self.suggestionRefresh)
        }
    }
}

/// The set-up in a card, for the Aim screen's mount sheet.
struct MountSkyWatcherSetupCard: View {
    var onSync: (() -> Void)?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Set up this mount", systemImage: "scope")
            MountSkyWatcherSetupRows(onSync: onSync)
            Text(MountSkyWatcherSetupRows.footer)
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(palette)
    }
}
