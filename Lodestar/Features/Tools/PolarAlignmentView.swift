import SwiftUI
import LodestarKit

/// Shows where the pole star stands relative to the celestial pole right now, as a clock position on a polar-scope
/// reticle, with instructions for aligning an equatorial mount or star tracker. Updates every second.
///
/// Push it inside a navigation stack (Settings ▸ Tools).
struct PolarAlignmentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var showsInvertedView = false

    var body: some View {
        Group {
            if let context = app.observerContext {
                content(for: context)
            } else {
                NeedsLocationView()
            }
        }
        .screenBackground(palette)
        .navigationTitle("Polar Alignment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for context: ObserverContext) -> some View {
        let frame = SkyFrame(date: app.clock.now, observer: context.observer)
        let reading = PolarAlignment.polarScopeReading(frame: frame, view: showsInvertedView ? .inverted : .naked)
        return ScrollView {
            VStack(spacing: 16) {
                reticleCard(reading, context: context)
                detailsCard(reading)
                optionsCard(reading)
                instructionsCard(reading)
            }
            .padding(16)
        }
    }

    // MARK: Cards

    private func reticleCard(_ reading: PolarScopeReading, context: ObserverContext) -> some View {
        let clock = ToolsPolarClock.text(angle: reading.angle)
        let time = AppFormat.time(app.clock.now, in: context.timeZone)
        return VStack(spacing: 12) {
            ToolsPolarReticle(reading: reading)
                .frame(maxWidth: 360)
            VStack(spacing: 2) {
                Text(clock)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                Text("\(reading.referenceStarName) on its circle, clock position")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                Text("For \(time) at \(context.name)")
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryText)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .card(palette)
    }

    private func detailsCard(_ reading: PolarScopeReading) -> some View {
        let isNorth = reading.hemisphere == .north
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "The Pole Now", systemImage: "location.north.line")
            InfoRow(label: "Pole", value: isNorth ? "North celestial pole" : "South celestial pole")
            InfoRow(label: "Pole altitude", value: AngleFormatter.formatDegrees(reading.poleAltitude, decimals: 1))
            InfoRow(label: "Pole direction", value: AppFormat.azimuth(reading.poleAzimuth))
            InfoRow(label: "\(reading.referenceStarName) from the pole",
                    value: AngleFormatter.formatDegrees(reading.separationFromPole, decimals: 2))
            InfoRow(label: "\(reading.referenceStarName) hour angle",
                    value: AngleFormatter.formatSignedDegrees(reading.hourAngle, decimals: 1))
            Text("The altitude is geometric; refraction lifts the pole by about an arcminute at mid-latitudes.")
                .font(.footnote)
                .foregroundStyle(palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func optionsCard(_ reading: PolarScopeReading) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Polar scope view (inverted)", isOn: $showsInvertedView)
                .foregroundStyle(palette.primaryText)
            Text("Most polar scopes show the sky upside down. Turn this on to read the reticle as you see it "
                 + "through the scope; leave it off for the view with the naked eye, zenith at the top.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let pole = app.catalog.object(id: reading.hemisphere == .north ? "special.ncp" : "special.scp") {
                Button {
                    app.aim(at: pole)
                } label: {
                    Label("Aim at the \(reading.hemisphere == .north ? "North" : "South") Celestial Pole",
                          systemImage: "scope")
                }
                .buttonStyle(.lodestarSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func instructionsCard(_ reading: PolarScopeReading) -> some View {
        let steps = Self.steps(for: reading)
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "How to Align", systemImage: "list.number")
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(palette.accent))
                        .accessibilityHidden(true)
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    /// The alignment procedure for the reading's hemisphere, with the numbers filled in.
    private static func steps(for reading: PolarScopeReading) -> [String] {
        let isNorth = reading.hemisphere == .north
        let altitude = AngleFormatter.formatDegrees(reading.poleAltitude, decimals: 1)
        let clock = ToolsPolarClock.text(angle: reading.angle)
        var steps = [
            "Level the tripod, set the mount's latitude scale to \(altitude) and point the polar axis roughly "
                + "\(isNorth ? "north" : "south"). The Aim screen can help: aim at the celestial pole.",
            "Turn the polar scope's reticle (or the mount's right-ascension axis) until the 12 o'clock mark is "
                + "straight up.",
            "Find \(reading.referenceStarName) and use the mount's altitude and azimuth adjusters to put it on its "
                + "circle at \(clock) o'clock.",
        ]
        if !isNorth {
            steps.append("\(reading.referenceStarName) is faint, about magnitude 5.4. Let your eyes adapt, or use "
                         + "binoculars to find it.")
        }
        steps.append("The pole star circles the pole once a day, 15\u{00B0} an hour. The clock position above "
                     + "updates every second, so follow it if the alignment takes a while.")
        return steps
    }
}
