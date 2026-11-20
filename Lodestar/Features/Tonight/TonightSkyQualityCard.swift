import SwiftUI
import LodestarKit

/// The Sky quality card: the Bortle estimate of the site, the darkest direction and the imaging score of the night with its
/// parts. The cloud part appears only while the cloud forecast is on, matches the place, is under 12 hours old and reaches
/// the night. Nothing until the estimate is worked out, and nothing when the map is unavailable.
struct TonightSkyQualityCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let summary: NightSummary
    let night: DateInterval

    @State private var reading: SkyReading?
    /// The time the forecast's age is judged at, taken from the clock once a minute. The age counts in hours, and
    /// reading the clock in `body` would draw the card again every second.
    @State private var now = Date()

    /// A forecast older than this does not go into the imaging score.
    private static let forecastFreshFor: TimeInterval = 12 * 3600

    var body: some View {
        Group {
            if let reading {
                content(reading)
            }
        }
        .task(id: SkyQualityKey(summary.observer.location)) {
            reading = await SkyQualityMapStore.shared.reading(at: summary.observer.location)
        }
        .task {
            await keepNowFresh()
        }
    }

    /// Takes the clock's time once a minute for `now`.
    private func keepNowFresh() async {
        while !Task.isCancelled {
            now = app.clock.now
            try? await Task.sleep(for: .seconds(60))
        }
    }

    private func content(_ reading: SkyReading) -> some View {
        let estimate = reading.estimate
        let score = SkyQualityScore.imaging(night: summary, bortle: estimate, cloudFraction: nightCloudFraction)
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Sky quality", systemImage: "moon.stars")
            InfoRow(label: "Sky", value: estimate.summary)
            InfoRow(label: "Darkest sky",
                    value: reading.directions.darkestHint.map { "toward \($0.direction.abbreviation)" }
                        ?? "No clear difference within 30 km")
            Text("Imaging score \(Self.oneDecimal(score.total)) / 10 \u{00B7} \(Self.ratingText(score.rating))")
                .font(.headline)
                .foregroundStyle(palette.primaryText)
                .accessibilityElement(children: .combine)
            ForEach(score.components, id: \.kind) { part in
                scoreLine(part, detail: detail(of: part, estimate: estimate))
            }
            TonightNote(text: score.includesClouds
                        ? "Out of 10: dark hours, the Moon, the sky's brightness and the cloud forecast."
                        : "Out of 10: dark hours, the Moon and the sky's brightness. The cloud forecast is not part of "
                            + "it (it is off or not up to date).",
                        style: .footnote)
            TonightNote(text: BortleEstimate.caveat + ".", style: .footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    /// One part of the score: its name and points, and a line saying what it rests on.
    private func scoreLine(_ part: ImagingScoreComponent, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.partName(part.kind))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer(minLength: 12)
                Text("\(Self.oneDecimal(part.points)) / \(Self.oneDecimal(part.weight))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryText)
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// What one part of the score rests on, in a few words.
    private func detail(of part: ImagingScoreComponent, estimate: BortleEstimate) -> String {
        switch part.kind {
        case .darknessHours:
            return summary.hasAstronomicalDarkness
                ? "\(TonightFormat.duration(hours: summary.astronomicalDarkHours)) of astronomical darkness"
                : "No astronomical darkness"
        case .moon:
            guard summary.hasAstronomicalDarkness else { return "No astronomical darkness" }
            let moonUpHours = summary.astronomicalDarkHours - summary.moonFreeDarkHours
            if moonUpHours < 1.0 / 60 { return "Not up in the dark" }
            return "Up for \(TonightFormat.duration(hours: moonUpHours)) of the dark, "
                + "\(AppFormat.percent(summary.moon.illuminatedFraction)) lit"
        case .skyBrightness:
            return "Bortle ~\(estimate.bortleClass), \(estimate.label.lowercased())"
        case .clouds:
            return "About \(AppFormat.percent(1 - part.quality)) cloud forecast for the night"
        }
    }

    private static func partName(_ kind: ImagingScoreComponentKind) -> String {
        switch kind {
        case .darknessHours: return "Dark hours"
        case .moon: return "Moon"
        case .skyBrightness: return "Sky brightness"
        case .clouds: return "Clouds"
        }
    }

    private static func ratingText(_ rating: ImagingRating) -> String {
        switch rating {
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }

    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// The cloud cover of the night at the place from the optional MET Norway forecast, 0 to 1, or `nil` when the feed is
    /// off, the forecast is for another place, older than 12 hours or does not reach the night.
    private var nightCloudFraction: Double? {
        let online = app.online
        guard online.isEnabled(.clouds) else { return nil }
        let place = summary.observer.location
        let key = OnlineCoordinates.key(latitude: place.latitude, longitude: place.longitude)
        guard let forecast = online.forecast, forecast.key == key else { return nil }
        guard now.timeIntervalSince(forecast.issuedAt) <= Self.forecastFreshFor else { return nil }
        let slots = ForecastNight.slots(forecast, night: night)
        guard !slots.isEmpty else { return nil }
        return ForecastNight.meanTotal(slots) / 100
    }
}
