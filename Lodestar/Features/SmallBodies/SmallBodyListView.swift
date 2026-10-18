import SwiftUI
import LodestarKit

/// The navigation value that opens the lists of bright comets and asteroids on a navigation stack.
struct SmallBodyListRoute: Hashable {}

/// One bright comet or asteroid: icon, name with designation, kind with the magnitude estimate and the elongation, and
/// with `peakDate` the day it is brightest. VoiceOver gets one sentence. Put it in a `NavigationLink(value:)`.
struct SmallBodyListRow: View {
    @Environment(\.palette) private var palette

    let entry: SmallBodyListEntry
    /// Shows "Brightest Fri, Oct 30" (the lists of the coming month).
    var showsPeakDate = false
    let timeZone: TimeZone

    private var object: CelestialObject { entry.object }
    private var name: String { SmallBodyText.displayName(object) }

    /// The designation beside the name when it adds something ("C/2023 A3", "(4)").
    private var designation: String? {
        object.designations.first.flatMap { $0 == name ? nil : $0 }
    }

    private var peak: String? {
        showsPeakDate ? "Brightest \(AppFormat.day(entry.peakDate, in: timeZone))" : nil
    }

    private var spoken: String {
        let subtitle = SmallBodyText.subtitle(of: object, info: entry.info, isComputed: true, spoken: true)
        return [name, designation, subtitle, peak].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ObjectIcon(category: object.category)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    if let designation {
                        Text(designation)
                            .font(.subheadline)
                            .foregroundStyle(palette.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Text(SmallBodyText.summary(of: object, info: entry.info))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                if let peak {
                    Text(peak)
                        .font(.footnote)
                        .foregroundStyle(palette.tertiaryText)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.tertiaryText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Shows details")
    }
}

/// What the list screen is computed for.
private struct SmallBodyListKey: Equatable {
    let catalogID: ObjectIdentifier?
    let period: SmallBodyListPeriod
    let limit: SmallBodyMagnitudeLimit
    let kind: SmallBodyListKind
}

/// The bright comets and asteroids, now or in the next 31 days, for a magnitude limit of 6 (naked eye), 8 (binoculars,
/// wide-field camera) or 10 (camera on a tripod). A row opens the object's detail screen. Push it with
/// `SmallBodyListRoute` on a stack that also has a destination for `CelestialObject`.
struct SmallBodyListView: View {
    /// How often the list is worked out again while the screen is open.
    private static let refreshInterval: Duration = .seconds(600)

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    @State private var period = SmallBodyListPeriod.now
    @State private var limit = SmallBodyMagnitudeLimit.default
    @State private var kind = SmallBodyListKind.comets
    /// The rows; `nil` while they are being worked out.
    @State private var entries: [SmallBodyListEntry]?

    private var key: SmallBodyListKey {
        SmallBodyListKey(catalogID: app.catalog.catalog.map(ObjectIdentifier.init), period: period, limit: limit,
                         kind: kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SmallBodyChoiceChips(options: SmallBodyListPeriod.allCases, selection: $period) { $0.title }
                SmallBodyChoiceChips(options: SmallBodyListKind.allCases, selection: $kind) { $0.title }
                SmallBodyChoiceChips(options: SmallBodyMagnitudeLimit.allCases, selection: $limit) { $0.title }
                Text(limit.caption)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }
            content
        }
        .screenBackground(palette)
        .navigationTitle("Comets and Asteroids")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await app.catalog.load()
        }
        .task(id: key) {
            await keepListFresh(for: key)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let entries {
            if entries.isEmpty {
                EmptyStateView(title: "Nothing Bright", systemImage: "sparkle",
                               message: SmallBodyBrightLists.emptyMessage(period: period, limit: limit.value,
                                                                          kind: kind))
            } else {
                list(of: entries)
            }
        } else {
            ProgressView()
                .tint(palette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func list(of entries: [SmallBodyListEntry]) -> some View {
        let timeZone = app.observerContext?.timeZone ?? .autoupdatingCurrent
        return ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(entries) { entry in
                    NavigationLink(value: entry.object) {
                        SmallBodyListRow(entry: entry, showsPeakDate: period == .thisMonth, timeZone: timeZone)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
                    }
                    .buttonStyle(.plain)
                }
                Text(SmallBodyText.footnote)
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(16)
        }
    }

    /// Works the list out off the main thread, now and then every ten minutes, until the key changes.
    private func keepListFresh(for key: SmallBodyListKey) async {
        guard let catalog = app.catalog.catalog else { return }
        let (period, limit, kind) = (key.period, key.limit.value, key.kind)
        while !Task.isCancelled {
            let date = app.clock.now
            let computed = await Task.detached(priority: .userInitiated) {
                SmallBodyBrightLists.entries(in: catalog, at: date, period: period, limit: limit, kind: kind)
            }.value
            guard !Task.isCancelled else { return }
            entries = computed
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}

/// A row of exclusive choices as capsules, scrolling sideways when they do not fit.
private struct SmallBodyChoiceChips<Option: Hashable & Identifiable>: View {
    @Environment(\.palette) private var palette

    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let isSelected = option == selection
                    Button {
                        selection = option
                    } label: {
                        Text(title(option))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? palette.onAccent : palette.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(isSelected ? palette.accent : palette.surface))
                            .overlay(Capsule().strokeBorder(isSelected ? palette.accent : palette.stroke, lineWidth: 0.75))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
