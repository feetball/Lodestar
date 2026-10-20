import SwiftUI
import LodestarKit

/// The words of the "Clouds tonight" card. The Android app uses the same texts.
enum CloudCardText {
    static let title = "Clouds tonight"
    static let loading = "Loading the forecast\u{2026}"
    static let attribution = "Forecast: MET Norway"
    static let rounding = "Location rounded to about 10 km."
    static let beforeForecast = "The forecast covers only the time from now on."
    static let beyondForecast = "No forecast for this night yet. The forecast reaches about nine days ahead."
    static let coarse = "Further ahead the forecast has one value every six hours."

    /// "Issued 19:17 · Forecast: MET Norway · Location rounded to about 10 km." The issue time carries its date when the
    /// forecast was not issued today.
    static func footnote(issuedText: String) -> String {
        "Issued \(issuedText) \u{00B7} \(attribution) \u{00B7} \(rounding)"
    }

    /// "This forecast is 14 hours old and has not been refreshed." Whole days from two days on.
    static func stale(ageHours: Int) -> String {
        let age = ageHours < 48 ? "\(ageHours) hours" : "\(ageHours / 24) days"
        return "This forecast is \(age) old and has not been refreshed."
    }
}

/// "Clouds tonight": the hourly cloud cover from dusk to dawn of the night shown, total and the low, medium and high
/// layers, as a compact strip with a summary of the clear spells. Appears only while the Cloud forecast is switched on.
/// `night` is the Tonight screen's own night (sunset to sunrise) at `place`.
struct TonightCloudCard: View {
    let place: GeographicLocation
    let night: DateInterval
    let timeZone: TimeZone
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    /// The forecast is looked at again every quarter of an hour while the card is in view; the server's `Expires` decides
    /// whether anything is requested. Nothing runs while the app is in the background.
    private static let recheck: Duration = .seconds(15 * 60)

    /// What restarts the refresh loop: another place (more than the rounding) or the app coming back to the front.
    private struct RefreshKey: Equatable {
        var place: String
        var isActive: Bool
    }

    var body: some View {
        let online = app.online
        if online.isEnabled(.clouds) {
            let key = OnlineCoordinates.key(latitude: place.latitude, longitude: place.longitude)
            let forecast = online.forecast.flatMap { $0.key == key ? $0 : nil }
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: CloudCardText.title, systemImage: "cloud")
                if let forecast {
                    CloudForecastContent(forecast: forecast, night: night, timeZone: timeZone, now: app.clock.now)
                } else {
                    let status = online.status(.clouds)
                    TonightNote(text: status.isUpdating ? CloudCardText.loading : (status.error ?? CloudCardText.loading))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(palette)
            .task(id: RefreshKey(place: key, isActive: app.scenePhase == .active)) {
                guard app.scenePhase == .active else { return }
                while !Task.isCancelled {
                    app.online.refreshForecast()
                    try? await Task.sleep(for: Self.recheck)
                }
            }
        }
    }
}

private struct CloudForecastContent: View {
    let forecast: CloudForecast
    let night: DateInterval
    let timeZone: TimeZone
    /// The live time (not a time-travel date), which the age of the forecast is measured against.
    let now: Date
    @Environment(\.palette) private var palette

    /// A forecast issued longer ago than this is flagged: the last refresh failed or has not happened, and the saved
    /// forecast still covers tonight (it reaches about nine days ahead).
    private static let staleAfter: TimeInterval = 12 * 3600

    var body: some View {
        let slots = ForecastNight.slots(forecast, night: night)
        let timeText: (Date) -> String = { AppFormat.time($0, in: timeZone) }
        let age = now.timeIntervalSince(forecast.issuedAt)
        if age > Self.staleAfter {
            TonightNote(text: CloudCardText.stale(ageHours: Int(age / 3600)), style: .warning)
        }
        if slots.isEmpty {
            let beforeStart = forecast.hours.first.map { night.end <= $0.time } ?? false
            TonightNote(text: beforeStart ? CloudCardText.beforeForecast : CloudCardText.beyondForecast)
        } else {
            if let summary = ForecastNight.summary(slots, timeText: timeText) {
                Text(summary)
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
            }
            CloudStrip(slots: slots, timeZone: timeZone,
                       description: ForecastNight.spokenSummary(slots, timeText: timeText) ?? "")
            if slots.contains(where: { $0.seconds > 3601 }) {
                TonightNote(text: CloudCardText.coarse, style: .footnote)
            }
        }
        TonightNote(text: CloudCardText.footnote(issuedText: issuedText(timeText: timeText)), style: .footnote)
    }

    /// The issue time of the forecast, with its date when that is not today in the observer's time zone.
    private func issuedText(timeText: (Date) -> String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(forecast.issuedAt, inSameDayAs: now) { return timeText(forecast.issuedAt) }
        return AppFormat.dateTime(forecast.issuedAt, in: timeZone)
    }
}

/// One column per forecast slot: a bar as high as the total cloud, and under it three thin cells shaded by the high,
/// medium and low layers. Drawn from the palette only, so it is red at night.
private struct CloudStrip: View {
    let slots: [CloudSlot]
    let timeZone: TimeZone
    let description: String
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .caption2) private var unit: CGFloat = 1

    private static let totalHeight: CGFloat = 40
    private static let layerHeight: CGFloat = 10
    private static let gap: CGFloat = 3
    private static let axisHeight: CGFloat = 16
    private static let labelWidth: CGFloat = 38

    var body: some View {
        let height = (Self.totalHeight + 3 * (Self.layerHeight + Self.gap) + Self.axisHeight) * max(unit, 1)
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard let first = slots.first, let last = slots.last else { return }
        let scale = max(unit, 1)
        let totalHeight = Self.totalHeight * scale
        let layerHeight = Self.layerHeight * scale
        let gap = Self.gap * scale
        let labelWidth = Self.labelWidth * scale
        let left = labelWidth
        let width = size.width - labelWidth
        let span = last.end.timeIntervalSince(first.start)
        guard span > 0, width > 0 else { return }
        func x(_ time: Date) -> CGFloat { left + CGFloat(time.timeIntervalSince(first.start) / span) * width }

        let labelFont = Font.system(size: 10 * scale)
        func label(_ text: String, centerY: CGFloat) {
            context.draw(Text(text).font(labelFont).foregroundStyle(palette.secondaryText),
                         at: CGPoint(x: 0, y: centerY), anchor: .leading)
        }
        label("Total", centerY: totalHeight / 2)
        let rows: [(String, KeyPath<CloudSlot, Double>)] = [("High", \.high), ("Mid", \.medium), ("Low", \.low)]
        for (index, row) in rows.enumerated() {
            label(row.0, centerY: totalHeight + gap + CGFloat(index) * (layerHeight + gap) + layerHeight / 2)
        }

        // A faint floor for the bars, so an empty (clear) hour still shows as a slot.
        context.fill(Path(CGRect(x: left, y: totalHeight - 1, width: width, height: 1)), with: .color(palette.stroke))
        for slot in slots {
            let slotLeft = x(slot.start)
            let slotWidth = max(x(slot.end) - slotLeft - 1, 1)
            let barHeight = CGFloat(slot.total / 100) * totalHeight
            context.fill(Path(CGRect(x: slotLeft, y: totalHeight - barHeight, width: slotWidth, height: barHeight)),
                         with: .color(palette.accent.opacity(0.85)))
            for (index, row) in rows.enumerated() {
                let top = totalHeight + gap + CGFloat(index) * (layerHeight + gap)
                let cell = CGRect(x: slotLeft, y: top, width: slotWidth, height: layerHeight)
                context.fill(Path(cell), with: .color(palette.surfaceRaised))
                let amount = min(max(slot[keyPath: row.1] / 100, 0), 1) * 0.9
                context.fill(Path(cell), with: .color(palette.primaryText.opacity(amount)))
            }
        }

        // Hour labels on the whole hours of the observer's time zone, thinned further when the (larger) labels would
        // touch at a big text size.
        let axisTop = totalHeight + 3 * (layerHeight + gap)
        let hourFormat = Date.FormatStyle(timeZone: timeZone).hour()
        let ticks = Self.hourTicks(from: first.start, to: last.end, timeZone: timeZone).map { tick in
            (tick, context.resolve(Text(tick.formatted(hourFormat))
                .font(labelFont.monospacedDigit())
                .foregroundStyle(palette.secondaryText)))
        }
        let hourLabelWidth = ticks.map { $0.1.measure(in: size).width }.max() ?? 0
        var step = 1
        if ticks.count > 1 {
            let pitch = abs(x(ticks[1].0) - x(ticks[0].0))
            step = [1, 2, 3, 4, 6].first { pitch * CGFloat($0) >= hourLabelWidth + 8 * scale } ?? 12
        }
        for (index, entry) in ticks.enumerated() where index % step == 0 {
            let tickX = min(max(x(entry.0), left + hourLabelWidth / 2), size.width - hourLabelWidth / 2)
            context.draw(entry.1, at: CGPoint(x: tickX, y: axisTop + 2), anchor: .top)
        }
    }

    /// The whole hours inside the night that get a label: every hour, or every second, third, fourth or sixth one.
    static func hourTicks(from start: Date, to end: Date, timeZone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hours = end.timeIntervalSince(start) / 3600
        let spacing = [1, 2, 3, 4].first { hours / Double($0) <= 7.5 } ?? 6
        var ticks: [Date] = []
        var cursor = start
        for _ in 0..<48 {
            guard let next = calendar.nextDate(after: cursor, matching: DateComponents(minute: 0, second: 0),
                                               matchingPolicy: .nextTime), next < end else { break }
            if calendar.component(.hour, from: next) % spacing == 0 { ticks.append(next) }
            cursor = next
        }
        return ticks
    }
}
