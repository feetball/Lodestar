import SwiftUI
import LodestarKit

/// The numbers behind Jupiter's "Moons tonight" card. Pure, so it can be tested and run on any thread.
enum ObjectsJupiterMoons {
    /// How far ahead "tonight" looks, in hours: the evening and the night to come, whenever it is asked.
    static let tonightHours = 24.0

    /// How many moon events the card lists.
    static let eventLimit = 6

    /// The narrowest strip, in Jupiter radii either side of the planet.
    private static let minimumHalfRange = 12.0

    /// The widest strip: Callisto's orbit is 26.4 radii wide.
    private static let maximumHalfRange = 30.0

    /// The Great Red Spot transits and moon events that can be seen from the observer (Jupiter above 10° with the Sun
    /// below −6° while they happen) from `from` for `tonightHours` hours, in time order.
    static func tonight(observer: Observer, timeZone: TimeZone, from: Date, spot: GreatRedSpot) -> [AstronomicalEvent] {
        let options = EventOptions(kinds: [.greatRedSpotTransit, .jupiterMoonEvent], timeZone: timeZone,
                                   visibleOnly: true, jupiterEventDays: tonightHours / 24, greatRedSpot: spot)
        return EventCalculator.events(from: from, to: from.addingTimeInterval(tonightHours * 3600), observer: observer,
                                      options: options)
    }

    /// The first Great Red Spot transit among `events` at or after `from`.
    static func nextTransit(in events: [AstronomicalEvent], from: Date) -> AstronomicalEvent? {
        events.first { event in
            if case .greatRedSpotTransit = event.details { return event.date >= from }
            return false
        }
    }

    /// The first `eventLimit` moon events among `events` at or after `from`.
    static func moonEvents(in events: [AstronomicalEvent], from: Date) -> [AstronomicalEvent] {
        Array(events.filter { event in
            if case .jupiterMoonEvent = event.details { return event.date >= from }
            return false
        }.prefix(eventLimit))
    }

    /// Half the width of the strip in Jupiter radii: 12, 18, 24 or 30, enough for the farthest moon.
    static func halfRange(of state: GalileanMoonsState) -> Double {
        let farthest = state.moons.map { abs($0.x) }.max() ?? 0
        return min(max((farthest / 6).rounded(.up) * 6, minimumHalfRange), maximumHalfRange)
    }

    /// The diagram in words: where each moon stands, east or west of Jupiter, and in front, behind or in the shadow.
    static func summary(of state: GalileanMoonsState) -> String {
        let parts = state.moons.map { moon -> String in
            let radii = abs(moon.x).formatted(.number.precision(.fractionLength(1)))
            let side = moon.x >= 0 ? "west" : "east"
            let place: String
            if moon.isInTransit {
                place = ", in front of the disc"
            } else if moon.isBehindDisc {
                place = ", behind Jupiter"
            } else if moon.isEclipsed {
                place = ", in Jupiter's shadow"
            } else {
                place = ""
            }
            return "\(moon.moon.displayName) \(radii) radii \(side)\(place)"
        }
        let shadows = state.moons.filter { $0.shadow != nil }.map { "\($0.moon.displayName)'s shadow" }
        let shadowText = shadows.isEmpty ? "" : ". " + shadows.joined(separator: " and ") + " on the disc"
        return "East is on the left. " + parts.joined(separator: ". ") + shadowText
    }
}

/// Jupiter's four moons as a strip, east on the left and west on the right as in the sky, refreshed with `now`, and
/// what happens tonight: the next Great Red Spot transit and the moon events that can be seen from here.
struct ObjectDetailJupiterMoonsCard: View {
    /// What the list of tonight's events was worked out for: where, in which zone, from which hour, for which spot.
    private struct Key: Equatable {
        let context: ObserverContext
        let hour: Date
        let spot: GreatRedSpot
    }

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    /// The present moment of the detail screen; `nil` until its first snapshot.
    let now: Date?
    let context: ObserverContext

    @State private var events: [AstronomicalEvent]?

    private var spot: GreatRedSpot { app.settings.greatRedSpotOrDefault }

    private var key: Key? {
        guard let now else { return nil }
        return Key(context: context, hour: Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600),
                   spot: spot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Moons tonight", systemImage: "smallcircle.circle")
            if let now {
                JupiterMoonsStrip(state: GalileanMoons.positions(at: JulianDate(date: now)))
            }
            Text("East is on the left, west on the right, as in the sky. The scale is in Jupiter\u{2019}s radii.")
                .font(.caption)
                .foregroundStyle(palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let now, let events {
                tonightRows(events, from: now)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
        .task(id: key) {
            guard let key else { return }
            let observer = key.context.observer
            let timeZone = key.context.timeZone
            let hour = key.hour
            let spot = key.spot
            events = await Task.detached(priority: .userInitiated) {
                ObjectsJupiterMoons.tonight(observer: observer, timeZone: timeZone, from: hour, spot: spot)
            }.value
        }
    }

    @ViewBuilder
    private func tonightRows(_ events: [AstronomicalEvent], from now: Date) -> some View {
        let timeZone = context.timeZone
        let transit = ObjectsJupiterMoons.nextTransit(in: events, from: now)
        let moonEvents = ObjectsJupiterMoons.moonEvents(in: events, from: now)
        if transit == nil && moonEvents.isEmpty {
            Text("No Great Red Spot transit or moon event can be seen from here in the next day: Jupiter is down or the "
                 + "sky is bright.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let transit, case let .greatRedSpotTransit(details) = transit.details {
            Text("Great Red Spot crosses the central meridian at \(AppFormat.time(transit.date, in: timeZone)); "
                 + "well placed \(EventsFormat.window(details.wellPlaced, in: timeZone))")
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(moonEvents, id: \.self) { event in
            if case let .jupiterMoonEvent(details) = event.details {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(AppFormat.time(event.date, in: timeZone))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryText)
                    Text("\(details.title) (\u{00B1}\(Int(GalileanMoons.accuracyMinutes)) min)")
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
        Text("Moon positions and times are good to about \(Int(GalileanMoons.accuracyMinutes)) minutes. "
             + "The Great Red Spot\u{2019}s longitude can be set in Settings.")
            .font(.caption)
            .foregroundStyle(palette.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The diagram: Jupiter's disc on a line, each moon a disc with its initial, a shadow as a dark spot on the planet.
private struct JupiterMoonsStrip: View {
    @Environment(\.palette) private var palette
    /// The room under the line for the east and west labels, which grows with the text size.
    @ScaledMetric(relativeTo: .caption2) private var labelBand: CGFloat = 14

    let state: GalileanMoonsState

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: 62 + labelBand)
        .accessibilityElement()
        .accessibilityLabel("Jupiter\u{2019}s moons")
        .accessibilityValue(ObjectsJupiterMoons.summary(of: state))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let margin: CGFloat = 14
        let moonRadius: CGFloat = 9
        let centerX = size.width / 2
        let centerY = (size.height - labelBand) / 2
        let half = ObjectsJupiterMoons.halfRange(of: state)
        let scale = (size.width / 2 - margin - moonRadius) / CGFloat(half)
        let discRadius = max(scale, 5)
        var axis = Path()
        axis.move(to: CGPoint(x: margin, y: centerY))
        axis.addLine(to: CGPoint(x: size.width - margin, y: centerY))
        context.stroke(axis, with: .color(palette.stroke), lineWidth: 1)
        // Tick marks every six radii.
        var tick = 6.0
        while tick <= half {
            for side in [-1.0, 1.0] {
                let x = centerX + CGFloat(side * tick) * scale
                var mark = Path()
                mark.move(to: CGPoint(x: x, y: centerY - 3))
                mark.addLine(to: CGPoint(x: x, y: centerY + 3))
                context.stroke(mark, with: .color(palette.stroke), lineWidth: 1)
            }
            tick += 6
        }
        let sideFont = Font.caption2
        context.draw(Text("E").font(sideFont).foregroundStyle(palette.secondaryText),
                     at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading)
        context.draw(Text("W").font(sideFont).foregroundStyle(palette.secondaryText),
                     at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
        let disc = CGRect(x: centerX - discRadius, y: centerY - discRadius, width: discRadius * 2, height: discRadius * 2)
        context.fill(Path(ellipseIn: disc), with: .color(palette.surfaceRaised))
        context.stroke(Path(ellipseIn: disc), with: .color(palette.accent), lineWidth: 1.5)
        for moon in state.moons {
            let x = centerX + CGFloat(moon.x) * scale
            let y = centerY - CGFloat(moon.y) * scale
            let circle = CGRect(x: x - moonRadius, y: y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)
            if moon.isBehindDisc || moon.isEclipsed {
                context.stroke(Path(ellipseIn: circle), with: .color(palette.tertiaryText), lineWidth: 1)
            } else {
                context.fill(Path(ellipseIn: circle), with: .color(palette.accent))
                context.draw(Text(moon.moon.initial).font(.caption.weight(.bold)).foregroundStyle(palette.onAccent),
                             at: CGPoint(x: x, y: y))
            }
        }
        for moon in state.moons {
            guard let shadow = moon.shadow else { continue }
            let x = centerX + CGFloat(shadow.x) * discRadius
            let y = centerY - CGFloat(shadow.y) * discRadius
            let spot = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: spot), with: .color(palette.primaryText))
        }
    }
}
