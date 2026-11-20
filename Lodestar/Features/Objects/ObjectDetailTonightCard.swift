import SwiftUI
import LodestarKit

/// When the object rises, culminates and sets tonight, with the altitude chart.
struct ObjectDetailTonightCard: View {
    @Environment(\.palette) private var palette
    @Environment(AppModel.self) private var app

    let object: CelestialObject
    let night: ObjectDetailNight?
    /// The present moment, for the chart's "now" line.
    let now: Date?
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Tonight", systemImage: "moon.stars")
            if let night {
                content(for: night)
            } else {
                ObjectDetailPending()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    @ViewBuilder
    private func content(for night: ObjectDetailNight) -> some View {
        let day = AppFormat.day(night.interval.start, in: timeZone)
        Text("Night of \(day) \u{00B7} times in \(zoneName(at: night.interval.start))")
            .font(.footnote)
            .foregroundStyle(palette.secondaryText)
        ObjectDetailAltitudeChart(night: night, now: now, timeZone: timeZone)
        Text("Lighter bands show twilight; the dashed line is the horizon.")
            .font(.caption)
            .foregroundStyle(palette.tertiaryText)
        eventRows(for: night)
        darknessRows(for: night)
        if night.appliesSkyline {
            Label {
                Text("\(HorizonText.applied(app.observerContext?.horizonSource)): the object rises when it clears the skyline"
                     + " and sets when it sinks behind it. Hours above the skyline count the dark time the object is at"
                     + " least \(Int(ObjectsTonight.minimumAltitude))\u{00B0} high.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "mountain.2")
            }
            .font(.footnote)
            .foregroundStyle(palette.tertiaryText)
            .accessibilityElement(children: .combine)
        }
    }

    /// The observer's time zone as people write it, such as "MDT".
    private func zoneName(at date: Date) -> String {
        timeZone.abbreviation(for: date) ?? timeZone.identifier
    }

    @ViewBuilder
    private func eventRows(for night: ObjectDetailNight) -> some View {
        switch night.events.circumstance {
        case .alwaysDown:
            InfoRow(label: "Visibility",
                    value: night.appliesSkyline ? "Stays behind the skyline" : "Stays below the horizon")
        case .alwaysUp:
            InfoRow(label: "Visibility",
                    value: night.appliesSkyline ? "Always above the skyline" : "Always above the horizon")
            timelineRows(for: night)
        case .normal:
            timelineRows(for: night)
        }
    }

    private func timelineRows(for night: ObjectDetailNight) -> some View {
        ForEach(night.timeline) { event in
            InfoRow(label: title(of: event.kind, in: night), value: value(of: event, in: night))
        }
    }

    private func title(of kind: ObjectDetailEvent.Kind, in night: ObjectDetailNight) -> String {
        switch kind {
        case .rise: return night.appliesSkyline ? "Clears the skyline" : "Rises"
        case .transit: return "Highest point"
        case .set: return night.appliesSkyline ? "Sinks behind the skyline" : "Sets"
        }
    }

    /// The time of an event; for the highest point also the altitude reached.
    private func value(of event: ObjectDetailEvent, in night: ObjectDetailNight) -> String {
        let time = AppFormat.time(event.date, in: timeZone)
        guard event.kind == .transit, let altitude = night.transitAltitude else { return time }
        return "\(time)\u{00A0}\u{00B7} \(AppFormat.altitude(altitude))"
    }

    @ViewBuilder
    private func darknessRows(for night: ObjectDetailNight) -> some View {
        if let darkness = night.darkness {
            let start = AppFormat.time(darkness.start, in: timeZone)
            let end = AppFormat.time(darkness.end, in: timeZone)
            InfoRow(label: "Dark sky", value: "\(start) \u{2013} \(end)")
            if object.category != .sun, let best = night.bestInDarkness {
                InfoRow(label: "Highest in the dark", value: highestText(best))
            } else if object.category != .sun, night.appliesSkyline {
                InfoRow(label: "Highest in the dark", value: "Behind the skyline")
            }
            if object.category != .sun, let unobstructed = night.unobstructed {
                InfoRow(label: "Above your skyline", value: skylineHoursText(unobstructed))
            }
        } else {
            InfoRow(label: "Dark sky", value: "No astronomical darkness tonight")
        }
    }

    /// The stretches of the dark above the skyline with their total, such as "21:40 – 01:10 (3.5 h)".
    private func skylineHoursText(_ unobstructed: UnobstructedVisibility) -> String {
        guard !unobstructed.intervals.isEmpty else { return "None tonight" }
        return "\(TonightFormat.windows(unobstructed.intervals, in: timeZone)) (\(ObjectsFormat.hours(unobstructed.hours)))"
    }

    private func highestText(_ best: ObjectDetailPeak) -> String {
        guard best.altitude > 0 else { return "Below the horizon" }
        return "\(AppFormat.altitude(best.altitude)) at \(AppFormat.time(best.date, in: timeZone))"
    }
}
