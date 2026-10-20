import SwiftUI
import LodestarKit

/// The planets that are high enough in the dark to photograph, each opening its detail screen.
struct TonightPlanetsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let summary: NightSummary
    let timeZone: TimeZone
    /// Whether the site's skyline decides which planets are visible.
    var appliesSkyline = false

    private var visible: [PlanetVisibility] { summary.planets.filter(\.visibleDuringDarkness) }
    private var hidden: [PlanetVisibility] { summary.planets.filter { !$0.visibleDuringDarkness } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Planets", systemImage: ObjectCategory.planet.systemImageName)
            if !summary.hasAstronomicalDarkness {
                TonightNote(text: "There is no astronomical darkness on this night.")
            } else if visible.isEmpty {
                TonightNote(text: "No planet is more than \(Int(PlanetVisibility.minimumAltitude))\u{00B0}"
                            + " above the horizon" + (appliesSkyline ? " and your skyline" : "") + " while it is dark.")
            } else {
                ForEach(visible, id: \.body) { planet in
                    if planet.body != visible.first?.body {
                        TonightRowSeparator()
                    }
                    TonightPlanetRow(planet: planet, object: app.catalog.object(id: "planet.\(planet.body.rawValue)"),
                                     timeZone: timeZone)
                }
                if !hidden.isEmpty {
                    let names = hidden.map(\.body.displayName).joined(separator: ", ")
                    TonightNote(text: "Not up in the dark: \(names).", style: .footnote)
                }
            }
            if appliesSkyline, summary.hasAstronomicalDarkness {
                TonightSkylineNote(detail: "planets behind the skyline do not count.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }
}

/// One visible planet: name, brightness, when it is up in the dark and how high it gets.
private struct TonightPlanetRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let planet: PlanetVisibility
    /// The catalog entry the row opens; `nil` while the catalog is loading.
    let object: CelestialObject?
    let timeZone: TimeZone

    var body: some View {
        if let object {
            NavigationLink(value: object) {
                row(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens details")
        } else {
            row(showsChevron: false)
        }
    }

    private func row(showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ObjectIcon(category: .planet)
            VStack(alignment: .leading, spacing: 2) {
                if dynamicTypeSize.isAccessibilitySize {
                    // The name and the magnitude each get the whole width, so the name is not broken mid-word.
                    nameText
                    magnitudeText
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        nameText
                        Spacer(minLength: 8)
                        magnitudeText
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Text(timing)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryText)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
    }

    private var nameText: some View {
        Text(planet.body.displayName)
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var magnitudeText: some View {
        Text(AppFormat.magnitude(planet.magnitude))
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(palette.secondaryText)
    }

    /// "Up 20:15 – 05:40 · highest 62°".
    private var timing: String {
        var text = "Up " + TonightFormat.windows(planet.visibleIntervals, in: timeZone)
        if let altitude = planet.maxAltitudeDuringDarkness {
            text += " \u{00B7} highest " + AngleFormatter.formatDegrees(altitude, decimals: 0)
        }
        return text
    }

    private var spokenSummary: String {
        var parts = [planet.body.displayName]
        if let magnitude = planet.magnitude, magnitude.isFinite {
            parts.append(AppFormat.magnitude(magnitude).replacingOccurrences(of: "mag ", with: "magnitude "))
        }
        parts.append("up " + TonightFormat.spokenWindows(planet.visibleIntervals, in: timeZone))
        if let altitude = planet.maxAltitudeDuringDarkness {
            parts.append("highest \(AngleFormatter.formatDegrees(altitude, decimals: 0))")
        }
        return parts.joined(separator: ", ")
    }
}
