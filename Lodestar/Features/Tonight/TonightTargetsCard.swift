import SwiftUI
import LodestarKit

/// The deep-sky objects that rise highest in the dark, brightest and biggest first, each opening its detail screen.
struct TonightTargetsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let outcome: TonightTargetsOutcome
    let timeZone: TimeZone
    /// Whether the site's skyline decides which targets are usable.
    var appliesSkyline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Best Targets", systemImage: "scope")
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    @ViewBuilder
    private var content: some View {
        switch outcome {
        case .ranked(let targets) where targets.isEmpty:
            TonightNote(text: "No listed deep-sky object climbs above"
                        + " \(Int(TonightCalculator.minimumTargetAltitude))\u{00B0}"
                        + (appliesSkyline ? " and clears your skyline" : "") + " while it is dark.")
        case .ranked(let targets):
            ForEach(targets) { target in
                if target.id != targets.first?.id {
                    TonightRowSeparator()
                }
                TonightTargetRow(target: target, timeZone: timeZone)
            }
            TonightNote(text: "Ranked by height in the dark, brightness and size. Only objects that climb above "
                        + "\(Int(TonightCalculator.minimumTargetAltitude))\u{00B0} are listed.", style: .footnote)
            if targets.contains(where: { $0.note != nil }) {
                TonightNote(text: SmallBodyText.targetsNote, style: .footnote)
            }
            if appliesSkyline {
                TonightSkylineNote(detail: "targets hidden behind the skyline are left out.")
            }
        case .noDarkness:
            TonightNote(text: "There is no astronomical darkness on this night, so there is nothing to rank.")
        case .catalogPending:
            catalogStatus
        }
    }

    /// The catalog is still loading, or could not be loaded.
    @ViewBuilder
    private var catalogStatus: some View {
        if case .failed(let message) = app.catalog.loadState {
            TonightNote(text: message)
            Button {
                Task { await app.catalog.load() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
        } else {
            TonightNote(text: "Loading the sky catalog\u{2026}")
        }
    }
}

/// One target: what it is, how high it gets in the dark and when.
private struct TonightTargetRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let target: TonightTarget
    let timeZone: TimeZone

    private var object: CelestialObject { target.object }

    var body: some View {
        NavigationLink(value: object) {
            HStack(alignment: .top, spacing: 10) {
                ObjectIcon(category: object.category)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(target.note ?? TonightFormat.description(of: object))
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                    Text(timing)
                        .font(.footnote)
                        .foregroundStyle(palette.tertiaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(AngleFormatter.formatDegrees(target.peakAltitude, decimals: 0))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                    Text("highest")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryText)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
        .accessibilityHint("Opens details")
    }

    /// The name, with the first catalog designation when it differs: "Andromeda Galaxy · M 31".
    private var title: String {
        let name = SmallBodyText.displayName(object)
        return TonightFormat.designation(of: object).map { "\(name)\u{00A0}\u{00B7} \($0)" } ?? name
    }

    /// "Best 23:40 facing SE · 7h 12m above 20°".
    private var timing: String {
        let minimum = Int(TonightCalculator.minimumTargetAltitude)
        let best = TonightFormat.solid("Best \(AppFormat.time(target.peakTime, in: timeZone))") + " "
            + TonightFormat.solid(TonightFormat.facing(azimuth: target.peakAzimuth, altitude: target.peakAltitude))
        let above = "\(TonightFormat.duration(hours: target.hoursAboveMinimum)) above\u{00A0}\(minimum)\u{00B0}"
        // A wrapped line breaks after the dot, not between "8h 14m" and a lone "above 20°". At accessibility sizes the
        // text column is too narrow for the whole phrase in one piece, so it may break at its spaces there.
        return TonightFormat.dotted([best, dynamicTypeSize.isAccessibilitySize ? above : TonightFormat.solid(above)])
    }

    private var spokenSummary: String {
        var parts = [SmallBodyText.displayName(object), object.category.displayName]
        if let constellation = object.constellationName {
            parts.append(constellation)
        }
        parts.append("highest \(AngleFormatter.formatDegrees(target.peakAltitude, decimals: 0))"
                     + " at \(AppFormat.time(target.peakTime, in: timeZone))"
                     + ", " + TonightFormat.spokenFacing(azimuth: target.peakAzimuth, altitude: target.peakAltitude))
        parts.append("\(TonightFormat.duration(hours: target.hoursAboveMinimum)) above"
                     + " \(Int(TonightCalculator.minimumTargetAltitude)) degrees")
        return parts.joined(separator: ", ")
    }
}
