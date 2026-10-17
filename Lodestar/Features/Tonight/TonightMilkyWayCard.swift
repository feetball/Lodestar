import SwiftUI
import LodestarKit

/// When and where the Milky Way's core, the Galactic Centre in Sagittarius, can be photographed.
struct TonightMilkyWayCard: View {
    @Environment(\.palette) private var palette

    let summary: NightSummary
    let timeZone: TimeZone

    private var core: MilkyWayCoreVisibility { summary.milkyWayCore }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Milky Way Core", systemImage: "moon.stars")
            if !summary.hasAstronomicalDarkness {
                TonightNote(text: "There is no astronomical darkness on this night, so the core cannot be"
                            + " photographed.")
            } else if core.visibleIntervals.isEmpty {
                TonightNote(text: "The Galactic Centre stays below"
                            + " \(Int(MilkyWayCoreVisibility.minimumAltitude))\u{00B0} while it is dark.")
                horizonRows
            } else {
                visibleRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    /// When the core rises and sets, for a night on which it never gets high enough in the dark.
    @ViewBuilder
    private var horizonRows: some View {
        if let rise = core.riseTransitSet.rise {
            InfoRow(label: "Rises", value: AppFormat.time(rise, in: timeZone))
        }
        if let set = core.riseTransitSet.set {
            InfoRow(label: "Sets", value: AppFormat.time(set, in: timeZone))
        }
    }

    /// The compass point of the core at its best time.
    private var directionText: String {
        guard let azimuth = core.bestAzimuth, let altitude = core.maxAltitude else { return AppFormat.missing }
        return TonightFormat.direction(azimuth: azimuth, altitude: altitude)
    }

    @ViewBuilder
    private var visibleRows: some View {
        InfoRow(label: "Visible window", value: TonightFormat.windows(core.visibleIntervals, in: timeZone))
        if core.moonFreeVisibleIntervals != core.visibleIntervals {
            InfoRow(label: "Without the Moon",
                    value: core.moonFreeVisibleIntervals.isEmpty
                        ? "The Moon is up the whole time"
                        : TonightFormat.windows(core.moonFreeVisibleIntervals, in: timeZone))
        }
        InfoRow(label: "Best time", value: AppFormat.time(core.bestTime, in: timeZone))
        InfoRow(label: "Max altitude",
                value: core.maxAltitude.map { AngleFormatter.formatDegrees($0, decimals: 0) } ?? AppFormat.missing)
        InfoRow(label: "Direction", value: directionText)
        TonightNote(text: "Visible means at least \(Int(MilkyWayCoreVisibility.minimumAltitude))\u{00B0} above the"
                    + " horizon during astronomical darkness. Direction and height are for the best time.",
                    style: .footnote)
    }
}
