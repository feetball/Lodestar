import Foundation
import LodestarKit

/// The words of the ISS transit section and its detail. The Android app uses the same texts.
enum EventsTransitText {
    static let title = "ISS transits of the Sun and Moon"
    static let offHint = "Switch on Satellite passes in Online Data to predict when the ISS crosses the Sun or the Moon."
    static let dataHint = "ISS transits need fresh orbit data. Update it in Online Data."
    static let onlineData = "Online Data"
    static let finding = "Finding transits\u{2026}"
    static let none = "No transits in the next 14 days within 50 km of here."
    static let note = "The next 14 days, within 50 km of here. Times are to the second; check again on the day, "
        + "because the orbit changes."
    static let exposureSun = "Burst mode, 1/2000 s or faster; a solar filter is mandatory for the Sun \u{2014} never "
        + "look at or image the Sun without one."
    static let exposureMoon = "Burst mode, 1/2000 s or faster. Start the burst a few seconds early."
    static let exposureTitle = "Exposure"
    static let centrelineTitle = "Centreline"
    static let centrelineNote = "From a place on the centreline the satellite crosses the middle of the disc at the same "
        + "moment. Your elevation is assumed; check the ground and the horizon before you drive."
    static let fromHereNote = "The satellite crosses the disc as seen from where you are. The centreline gives the "
        + "longest crossing."
    static let noCentreline = "The centreline is farther than 50 km from here."
    static let copy = "Copy coordinates"
    static let copied = "Coordinates copied"
    static let detailTitle = "Transit"

    /// "Sun" or "Moon".
    static func bodyName(_ body: SolarSystemBody) -> String { body == .sun ? "Sun" : "Moon" }

    /// "Sun transit", or "Moon transit from here" when the satellite crosses the disc as seen from the site.
    static func title(_ item: EventsTransitItem) -> String {
        "\(bodyName(item.transit.body)) transit" + (item.transit.isFromSite ? " from here" : "")
    }

    /// "Aim at the Sun" / "Aim at the Moon".
    static func aimLabel(_ body: SolarSystemBody) -> String { "Aim at the \(bodyName(body))" }

    /// "Sat 21:14:07": the weekday and the time to the second in the user's 12 or 24 hour style.
    static func whenText(_ date: Date, in timeZone: TimeZone) -> String {
        let weekday = date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
        return "\(weekday) \(SatelliteText.timeWithSeconds(date, in: timeZone))"
    }

    /// "0.6 s", or "<0.1 s" for a crossing shorter than that.
    static func duration(_ seconds: Double) -> String {
        if !seconds.isFinite || seconds < 0.05 { return "<0.1 s" }
        return "\(seconds.formatted(.number.precision(.fractionLength(1)))) s"
    }

    /// A ground distance: "800 m", "2.3 km", "12 km".
    static func distance(_ meters: Double) -> String {
        guard meters.isFinite else { return AppFormat.missing }
        if meters < 950 { return "\(Int((meters / 10).rounded()) * 10) m" }
        let kilometers = meters / 1000
        if kilometers >= 9.95 { return "\(Int(kilometers.rounded()).formatted(.number)) km" }
        return "\(kilometers.formatted(.number.precision(.fractionLength(1)))) km"
    }

    /// "centreline 12 km NE".
    static func centrelineSummary(_ centreline: SatelliteTransitCentreline) -> String {
        "centreline \(distance(centreline.distanceMeters)) "
            + AngleFormatter.compassPoint(azimuth: centreline.bearing).abbreviation
    }

    /// The second line of a row: "Sat 21:14:07 · 0.6 s" from the site, else "Sat 21:14:07 · centreline 12 km NE".
    static func rowDetail(_ item: EventsTransitItem, in timeZone: TimeZone) -> String {
        let transit = item.transit
        let tail = transit.isFromSite
            ? duration(transit.siteDurationSeconds)
            : (transit.centreline.map(centrelineSummary) ?? "")
        return "\(whenText(transit.date, in: timeZone)) \u{00B7} \(tail)"
    }

    /// What a screen reader says for a row.
    static func spokenRow(_ item: EventsTransitItem, in timeZone: TimeZone) -> String {
        "\(item.satelliteName), \(title(item)), "
            + rowDetail(item, in: timeZone).replacingOccurrences(of: " \u{00B7} ", with: ", ")
    }

    /// "Daylight", "Twilight" or "Night" for the Sun's altitude at the transit.
    static func sky(isDaylight: Bool, isNight: Bool) -> String {
        if isDaylight { return "Daylight" }
        return isNight ? "Night" : "Twilight"
    }

    /// The satellite's span and angular size: "109 m · 0.014° across".
    static func size(catalogNumber: Int, angularSize: Double) -> String {
        let meters = Int(SatelliteTransitFinder.satelliteSpanMeters(catalogNumber: catalogNumber).rounded())
        return "\(meters) m \u{00B7} \(angularSize.formatted(.number.precision(.fractionLength(3))))\u{00B0} across"
    }

    /// "612 km".
    static func range(_ kilometers: Double) -> String { "\(Int(kilometers.rounded()).formatted(.number)) km" }

    /// "Crosses the disc" or "Misses the disc by 7′": how the transit looks from the observer's own site.
    static func fromHere(isFromSite: Bool, separation: Double, bodyRadius: Double) -> String {
        isFromSite ? "Crosses the disc" : "Misses the disc by \(AppFormat.separation(separation - bodyRadius))"
    }

    /// "NE (45°)": the compass point and the bearing.
    static func bearing(_ degrees: Double) -> String {
        "\(AngleFormatter.compassPoint(azimuth: degrees).abbreviation) (\(AngleFormatter.formatDegrees(degrees, decimals: 0)))"
    }

    /// "40.12345, -105.23456": decimal degrees that a maps app takes as they are.
    static func coordinates(_ location: GeographicLocation) -> String {
        String(format: "%.5f, %.5f", location.latitude, location.longitude)
    }
}
