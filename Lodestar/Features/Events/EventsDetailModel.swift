import Foundation
import LodestarKit

/// A label and a value in a card of the event detail screen.
struct EventsDetailRow: Identifiable, Equatable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

/// One contact of an eclipse: when it happens and where the Moon or Sun stands then.
struct EventsContactRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let time: Date
    /// Geometric altitude in degrees; negative means below the horizon.
    let altitude: Double
    let azimuth: Double

    var isBelowHorizon: Bool { altitude < 0 }
}

/// The numbers and times of the event detail screen as text rows. Pure, so it is easy to test.
enum EventsDetailModel {
    // MARK: Facts

    /// What the event is, in numbers: rate and speed of a shower, separation of a pair, magnitude of an eclipse.
    static func facts(of entry: EventsEntry, isSouthernHemisphere: Bool, timeZone: TimeZone) -> [EventsDetailRow] {
        switch entry.event.details {
        case .meteorShower(let peak):
            return meteorShowerFacts(peak, interference: entry.moonInterference)
        case .conjunction(let conjunction):
            return conjunctionFacts(conjunction, timeZone: timeZone)
        case .opposition(let opposition):
            return oppositionFacts(opposition)
        case .greatestElongation(let elongation):
            return elongationFacts(elongation)
        case .earthApsis(let apsis):
            return [EventsDetailRow(label: "Distance from the Sun",
                                    value: apsis.distanceAU.formatted(.number.precision(.fractionLength(4))) + " AU")]
        case .season(let season):
            return [EventsDetailRow(label: "Event", value: season.kind.displayName),
                    EventsDetailRow(label: "In your hemisphere",
                                    value: EventsFormat.summary(of: entry, isSouthernHemisphere: isSouthernHemisphere,
                                                                timeZone: timeZone))]
        case .fullMoonSpecial(let special):
            return fullMoonFacts(special)
        case .lunarEclipse(let eclipse):
            return lunarFacts(eclipse)
        case .solarEclipse(let eclipse):
            return solarFacts(eclipse, hasObserver: entry.event.visibility != nil, timeZone: timeZone)
        }
    }

    private static func meteorShowerFacts(_ peak: MeteorShowerPeak,
                                          interference: EventsMoonInterference?) -> [EventsDetailRow] {
        let shower = peak.shower
        let universal = TimeZone(identifier: "UTC") ?? .gmt
        let start = AppFormat.day(peak.activityStart, in: universal)
        let end = AppFormat.day(peak.activityEnd.addingTimeInterval(-1), in: universal)
        var rows = [
            EventsDetailRow(label: "Rate", value: "Up to \(shower.zhr) meteors an hour"),
            EventsDetailRow(label: "Active", value: "\(start) \u{2013} \(end) (UT)"),
            EventsDetailRow(label: "Speed", value: "\(Int(shower.velocity.rounded())) km/s"),
        ]
        if let interference {
            rows.append(EventsDetailRow(label: "Moon", value: EventsFormat.moonText(interference)))
        }
        return rows
    }

    private static func conjunctionFacts(_ conjunction: Conjunction, timeZone: TimeZone) -> [EventsDetailRow] {
        var rows = [
            EventsDetailRow(label: "Pair", value: "\(conjunction.first.displayName) and \(conjunction.second.displayName)"),
            EventsDetailRow(label: "Separation", value: AppFormat.separation(conjunction.separation)),
        ]
        if let topocentric = conjunction.topocentric {
            let time = AppFormat.time(topocentric.time, in: timeZone)
            rows.append(EventsDetailRow(
                label: "From here",
                value: topocentric.isOccultation
                    ? "Occultation, closest at \(time)"
                    : "\(AppFormat.separation(topocentric.separation)) at \(time)"))
        }
        rows.append(EventsDetailRow(label: "Distance from the Sun",
                                    value: AngleFormatter.formatDegrees(conjunction.solarElongation, decimals: 0)))
        if conjunction.occultationPossible, conjunction.topocentric?.isOccultation != true {
            rows.append(EventsDetailRow(label: "Occultation",
                                        value: conjunction.topocentric == nil ? "Possible in parts of the world"
                                                                              : "Possible elsewhere, not from here"))
        }
        return rows
    }

    private static func oppositionFacts(_ opposition: Opposition) -> [EventsDetailRow] {
        var rows = [EventsDetailRow(label: "Planet", value: opposition.planet.displayName)]
        if let magnitude = opposition.apparentMagnitude {
            rows.append(EventsDetailRow(label: "Brightness", value: AppFormat.magnitude(magnitude)))
        }
        let million = opposition.distanceAU * 149.597_870_7
        rows.append(EventsDetailRow(
            label: "Distance",
            value: "\(opposition.distanceAU.formatted(.number.precision(.fractionLength(2)))) AU"
                + " (\(million.formatted(.number.precision(.fractionLength(0)))) million km)"))
        rows.append(EventsDetailRow(
            label: "Size",
            value: "\(opposition.angularDiameterArcseconds.formatted(.number.precision(.fractionLength(1))))\u{2033}"))
        return rows
    }

    private static func elongationFacts(_ elongation: GreatestElongation) -> [EventsDetailRow] {
        let evening = elongation.direction == .east
        var rows = [
            EventsDetailRow(label: "Planet", value: elongation.planet.displayName),
            EventsDetailRow(label: "Elongation",
                            value: "\(AngleFormatter.formatDegrees(elongation.angle, decimals: 1)) "
                                + "\(evening ? "east" : "west") of the Sun"),
            EventsDetailRow(label: "Sky", value: evening ? "Evening, after sunset" : "Morning, before sunrise"),
        ]
        if let magnitude = elongation.apparentMagnitude {
            rows.append(EventsDetailRow(label: "Brightness", value: AppFormat.magnitude(magnitude)))
        }
        return rows
    }

    private static func fullMoonFacts(_ special: FullMoonSpecial) -> [EventsDetailRow] {
        [
            EventsDetailRow(label: "Kind", value: special.categories.map(\.displayName).joined(separator: ", ")),
            EventsDetailRow(label: "Distance",
                            value: special.distanceKilometers.formatted(.number.precision(.fractionLength(0))) + " km"),
            EventsDetailRow(label: "Size",
                            value: (special.angularDiameterArcseconds / 60)
                                .formatted(.number.precision(.fractionLength(1))) + "\u{2032} across"),
        ]
    }

    private static func lunarFacts(_ eclipse: LunarEclipse) -> [EventsDetailRow] {
        var rows = [
            EventsDetailRow(label: "Type", value: "\(eclipse.kind.displayName) lunar eclipse"),
            EventsDetailRow(label: "Umbral magnitude", value: EventsFormat.magnitude(eclipse.umbralMagnitude)),
            EventsDetailRow(label: "Penumbral magnitude", value: EventsFormat.magnitude(eclipse.penumbralMagnitude)),
            EventsDetailRow(label: "Penumbral phase", value: AngleFormatter.formatDuration(seconds: eclipse.penumbralDuration)),
        ]
        if eclipse.partialDuration > 0 {
            rows.append(EventsDetailRow(label: "Partial phase",
                                        value: AngleFormatter.formatDuration(seconds: eclipse.partialDuration)))
        }
        if eclipse.totalDuration > 0 {
            rows.append(EventsDetailRow(label: "Totality",
                                        value: AngleFormatter.formatDuration(seconds: eclipse.totalDuration)))
        }
        return rows
    }

    private static func solarFacts(_ eclipse: SolarEclipse, hasObserver: Bool, timeZone: TimeZone) -> [EventsDetailRow] {
        var rows = [
            EventsDetailRow(label: "Type", value: "\(eclipse.kind.displayName) solar eclipse"),
            EventsDetailRow(label: "Path", value: eclipse.isCentral ? "Central: total or annular along a track"
                                                                    : "Partial from everywhere"),
        ]
        guard hasObserver, let local = eclipse.local else { return rows }
        switch local.kind {
        case .none:
            rows.append(EventsDetailRow(label: "From here", value: "No eclipse visible"))
        case .partial, .annular, .total:
            rows.append(EventsDetailRow(label: "From here", value: "\(localKindName(local.kind)) eclipse"))
            rows.append(EventsDetailRow(label: "Magnitude", value: EventsFormat.magnitude(local.magnitude)))
            rows.append(EventsDetailRow(label: "Sun covered", value: AppFormat.percent(local.obscuration)))
            if local.kind != .partial {
                rows.append(EventsDetailRow(
                    label: local.kind == .total ? "Totality" : "Annularity",
                    value: AngleFormatter.formatDuration(seconds: local.centralDuration)))
            }
            if let altitude = local.sunAltitude, let azimuth = local.sunAzimuth {
                rows.append(EventsDetailRow(label: "Sun at maximum", value: position(altitude: altitude, azimuth: azimuth)))
            }
        }
        return rows
    }

    private static func localKindName(_ kind: LocalSolarEclipseKind) -> String {
        switch kind {
        case .none: return "No"
        case .partial: return "Partial"
        case .annular: return "Annular"
        case .total: return "Total"
        }
    }

    // MARK: When

    /// The times of the event in the observer's zone: the instant, the best window and where the subject stands.
    static func times(of entry: EventsEntry, timeZone: TimeZone) -> [EventsDetailRow] {
        let event = entry.event
        var rows: [EventsDetailRow] = []
        let instantLabel: String
        switch event.details {
        case .meteorShower: instantLabel = "Peak"
        case .conjunction: instantLabel = "Closest"
        case .opposition: instantLabel = "Opposition"
        case .greatestElongation: instantLabel = "Greatest elongation"
        case .season, .earthApsis: instantLabel = "Moment"
        case .fullMoonSpecial: instantLabel = "Full Moon"
        case .lunarEclipse: instantLabel = "Greatest eclipse"
        case .solarEclipse: instantLabel = "Greatest eclipse (anywhere)"
        }
        rows.append(EventsDetailRow(label: instantLabel, value: EventsFormat.dayAndTime(event.date, in: timeZone)))
        guard let visibility = event.visibility else { return rows }
        if let window = visibility.bestWindow {
            rows.append(EventsDetailRow(label: windowLabel(of: event), value: EventsFormat.window(window, in: timeZone)))
            if let best = visibility.bestTime {
                rows.append(EventsDetailRow(label: bestTimeLabel(of: event), value: AppFormat.time(best, in: timeZone)))
            }
        }
        if case .solarEclipse = event.details {
            return rows
        }
        if visibility.altitude > 0 {
            rows.append(EventsDetailRow(label: "At that moment",
                                        value: position(altitude: visibility.altitude, azimuth: visibility.azimuth)))
        }
        return rows
    }

    private static func bestTimeLabel(of event: AstronomicalEvent) -> String {
        switch event.details {
        case .lunarEclipse: return "Best time"
        case .solarEclipse: return "Maximum here"
        default: return "Highest at"
        }
    }

    private static func windowLabel(of event: AstronomicalEvent) -> String {
        switch event.details {
        case .meteorShower: return "Best dark window"
        case .lunarEclipse, .solarEclipse: return "Visible from here"
        default: return "Best window"
        }
    }

    /// "34\u{00B0} high, SE".
    static func position(altitude: Double, azimuth: Double) -> String {
        "\(AngleFormatter.formatDegrees(altitude, decimals: 0)) high, "
            + AngleFormatter.compassPoint(azimuth: azimuth).abbreviation
    }

    // MARK: Visibility

    /// One or two sentences on whether the event can be seen from the observer's place; `nil` for events that are
    /// not seen in the sky.
    static func visibilitySentence(of entry: EventsEntry, timeZone: TimeZone) -> String? {
        guard let visibility = entry.event.visibility, let isVisible = entry.isVisibleFromHere else { return nil }
        if case .solarEclipse(let eclipse) = entry.event.details, eclipse.local?.kind == LocalSolarEclipseKind.none {
            return "No part of the eclipse can be seen from here."
        }
        guard isVisible, let window = visibility.bestWindow else {
            switch entry.event.details {
            case .lunarEclipse:
                return "The Moon is below the horizon during the eclipse as seen from here."
            case .solarEclipse:
                return "The Sun is below the horizon during the eclipse as seen from here."
            default:
                return "There is no good viewing window from here: the target stays too low or the sky too bright that night."
            }
        }
        return "Visible from here between \(EventsFormat.window(window, in: timeZone))."
    }

    /// What a viewing window needs, in words; `nil` for eclipses (which only need the Moon or Sun above the horizon)
    /// and for events without visibility.
    static func windowRule(of entry: EventsEntry) -> String? {
        guard let visibility = entry.event.visibility, visibility.darknessLimit < 0 else { return nil }
        let limit = Int(abs(visibility.darknessLimit).rounded())
        if visibility.darknessLimit > -1 {
            return "A viewing window needs the target at least 10\u{00B0} high after sunset."
        }
        return "A viewing window needs the target at least 10\u{00B0} high and the Sun at least \(limit)\u{00B0} below the horizon."
    }

    // MARK: Contacts

    /// The contacts of an eclipse with the altitude of the Moon or Sun at each, in time order.
    static func contacts(of entry: EventsEntry) -> [EventsContactRow] {
        guard let visibility = entry.event.visibility else { return [] }
        var isTotal = false
        var isAnnular = false
        if case .solarEclipse(let eclipse) = entry.event.details, let local = eclipse.local {
            isTotal = local.kind == .total
            isAnnular = local.kind == .annular
        }
        return visibility.contacts.sorted { $0.time < $1.time }.map { contact in
            EventsContactRow(id: contact.contact.rawValue, name: contactName(contact.contact, isTotal: isTotal,
                                                                           isAnnular: isAnnular),
                             time: contact.time, altitude: contact.altitude, azimuth: contact.azimuth)
        }
    }

    private static func contactName(_ contact: EclipseContact, isTotal: Bool, isAnnular: Bool) -> String {
        let central = isTotal ? "Totality" : (isAnnular ? "Annularity" : "Central phase")
        switch contact {
        case .p1: return "Penumbra begins"
        case .u1: return "Partial phase begins"
        case .u2: return "Totality begins"
        case .greatest: return "Greatest eclipse"
        case .u3: return "Totality ends"
        case .u4: return "Partial phase ends"
        case .p4: return "Penumbra ends"
        case .c1: return "Eclipse begins"
        case .c2: return "\(central) begins"
        case .maximum: return "Maximum"
        case .c3: return "\(central) ends"
        case .c4: return "Eclipse ends"
        }
    }
}
