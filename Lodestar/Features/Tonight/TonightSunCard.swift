import SwiftUI
import LodestarKit

/// Sunset, the three twilights and sunrise, with the length of the dark in between.
struct TonightSunCard: View {
    @Environment(\.palette) private var palette

    let summary: NightSummary
    let timeZone: TimeZone

    var body: some View {
        let twilight = summary.twilight
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Sun & Twilight", systemImage: "sunset")
            timeRow("Sunset", twilight.sunset)
            timeRow("Civil dusk", twilight.civilDusk)
            timeRow("Nautical dusk", twilight.nauticalDusk)
            timeRow("Astronomical dusk", twilight.astronomicalDusk)
            darkRow
            timeRow("Astronomical dawn", twilight.astronomicalDawn)
            timeRow("Nautical dawn", twilight.nauticalDawn)
            timeRow("Civil dawn", twilight.civilDawn)
            timeRow("Sunrise", twilight.sunrise)
            TonightNote(text: "Dusk and dawn are when the Sun is 6\u{00B0}, 12\u{00B0} and 18\u{00B0} below the"
                        + " horizon. The sky is fully dark between astronomical dusk and dawn.", style: .footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func timeRow(_ label: String, _ date: Date?) -> some View {
        InfoRow(label: label, value: AppFormat.time(date, in: timeZone))
    }

    @ViewBuilder
    private var darkRow: some View {
        if summary.hasAstronomicalDarkness {
            InfoRow(label: "Dark sky",
                    value: TonightFormat.windows(summary.astronomicalDarknessIntervals, in: timeZone)
                        + " (\(TonightFormat.duration(hours: summary.astronomicalDarkHours)))")
        } else {
            InfoRow(label: "Dark sky", value: "No astronomical darkness")
        }
    }
}
