import SwiftUI
import LodestarKit

/// A spinner shown in a card while its data is being computed.
struct ObjectDetailPending: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ProgressView()
            .tint(palette.accent)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}

/// Where the object is right now, and what it looks like.
struct ObjectDetailNowCard: View {
    @Environment(\.palette) private var palette

    let current: ObjectDetailCurrent?
    let style: CoordinateStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Now", systemImage: "location.north.line")
            if let current {
                rows(for: current)
            } else {
                ObjectDetailPending()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    @ViewBuilder
    private func rows(for current: ObjectDetailCurrent) -> some View {
        let isUp = current.horizontal.altitude > 0 && !current.isBehindSkyline
        StatusChip(systemImage: isUp ? "arrow.up.right" : "arrow.down.right",
                   text: isUp ? "Above the horizon" : (current.isBehindSkyline ? "Behind the skyline" : "Below the horizon"),
                   tone: isUp ? .positive : .neutral)
        InfoRow(label: "Altitude", value: AppFormat.altitude(current.horizontal.altitude))
        InfoRow(label: "Azimuth", value: AppFormat.azimuth(current.horizontal.azimuth))
        InfoRow(label: "RA (of date)", value: AppFormat.rightAscension(current.equatorial, style: style))
        InfoRow(label: "Dec (of date)", value: AppFormat.declination(current.equatorial, style: style))
        if let magnitude = current.magnitude {
            InfoRow(label: "Brightness", value: AppFormat.magnitude(magnitude))
        }
        if let size = current.angularSize {
            InfoRow(label: "Apparent size", value: size.description)
        }
        if let distance = current.distance {
            InfoRow(label: "Distance", value: distance.text)
        }
        if let phase = current.moonPhase {
            let lit = AppFormat.percent(phase.illuminatedFraction)
            InfoRow(label: "Phase", value: "\(phase.name.displayName) \u{00B7} \(lit) lit")
        } else if let illuminated = current.illuminatedFraction {
            InfoRow(label: "Illuminated", value: AppFormat.percent(illuminated))
        }
    }
}
