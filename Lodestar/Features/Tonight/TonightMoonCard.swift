import SwiftUI
import LodestarKit

/// The Moon's phase, when it is up, and how much of the dark it leaves alone.
struct TonightMoonCard: View {
    @Environment(\.palette) private var palette

    let summary: NightSummary
    let timeZone: TimeZone
    /// Whether the site's skyline decides when the Moon is up.
    var appliesSkyline = false

    private var moon: MoonSummary { summary.moon }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Moon", systemImage: "moon")
            header
            moonlightChip
            horizonRows
            darkHoursRow
            if appliesSkyline {
                TonightSkylineNote(detail: "the Moon is up while it clears the skyline, and the moon-free dark hours follow.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    // MARK: Phase

    private var header: some View {
        let phase = moon.phase
        return HStack(spacing: 14) {
            Image(systemName: phase.name.symbolName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 46))
                .foregroundStyle(palette.primaryText)
                // The symbols show the Moon as seen from the northern hemisphere.
                .scaleEffect(x: summary.observer.location.latitude < 0 ? -1 : 1, y: 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.name.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text("\(AppFormat.percent(moon.illuminatedFraction)) illuminated")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                Text("Age \(phase.ageDays.formatted(.number.precision(.fractionLength(1)))) days"
                     + " \u{00B7} at \(AppFormat.time(phase.date, in: timeZone))")
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A one-word verdict on how much of the dark the Moon spoils.
    @ViewBuilder
    private var moonlightChip: some View {
        if summary.hasAstronomicalDarkness {
            let moonFree = summary.moonFreeDarkHours / summary.astronomicalDarkHours
            if moonFree >= 0.75 {
                StatusChip(systemImage: "moon.stars", text: "Mostly moon-free dark", tone: .positive)
            } else if moonFree <= 0.25 {
                StatusChip(systemImage: "moon.fill", text: "Moon up for most of the dark", tone: .warning)
            } else {
                StatusChip(systemImage: "moon", text: "Partly moonlit", tone: .neutral)
            }
        }
    }

    // MARK: Times

    @ViewBuilder
    private var horizonRows: some View {
        let events = moon.riseTransitSet
        switch events.circumstance {
        case .alwaysUp:
            InfoRow(label: "Moon", value: appliesSkyline ? "Above the skyline all night" : "Above the horizon all night")
        case .alwaysDown:
            InfoRow(label: "Moon", value: appliesSkyline ? "Behind the skyline all night" : "Below the horizon all night")
        case .normal:
            if let rise = events.rise, let set = events.set, set < rise {
                InfoRow(label: "Moonset", value: AppFormat.time(set, in: timeZone))
                InfoRow(label: "Moonrise", value: AppFormat.time(rise, in: timeZone))
            } else {
                InfoRow(label: "Moonrise", value: AppFormat.time(events.rise, in: timeZone))
                InfoRow(label: "Moonset", value: AppFormat.time(events.set, in: timeZone))
            }
        }
    }

    @ViewBuilder
    private var darkHoursRow: some View {
        if summary.hasAstronomicalDarkness {
            InfoRow(label: "Moon-free dark hours",
                    value: "\(TonightFormat.duration(hours: summary.moonFreeDarkHours)) of "
                        + TonightFormat.duration(hours: summary.astronomicalDarkHours))
        } else {
            InfoRow(label: "Moon-free dark hours", value: "No astronomical darkness")
        }
    }
}
