import SwiftUI
import LodestarKit

/// The sections of the star-trail plan: camera and lens, declination, the trail of a chosen time, the time for a
/// chosen trail, the stacking plan and the pole.
struct ToolsStarTrailSections: View {
    /// A gap between two exposures of a stack shows as a break in the trail above this many pixels.
    private static let visibleGapPixels = 2.0

    @Environment(\.palette) private var palette
    @Binding var inputs: ToolsTrailInputs
    let myCamera: LensSetup
    let sky: ToolsTrailSky?

    var body: some View {
        let setup = inputs.setup
        cameraSection(setup: setup)
        declinationSection
        trailSection(setup: setup)
        durationSection(setup: setup)
        stackSection(setup: setup)
        poleSection
    }

    // MARK: Inputs

    /// The presets, plus the user's own sensor when it is a custom size.
    private var sensorOptions: [SensorFormat] {
        SensorFormat.presets.contains(myCamera.sensor) ? SensorFormat.presets : SensorFormat.presets + [myCamera.sensor]
    }

    private func cameraSection(setup: LensSetup) -> some View {
        SettingsSection(
            title: "Camera & Lens",
            footer: "Starts from the camera and lens in Settings. Changes here stay in this tool. The pixel pitch "
                + "gives lengths in pixels; without it Lodestar assumes \(Self.defaultPitchText) \u{00B5}m.") {
            SettingsMenuPicker(title: "Sensor", selection: $inputs.sensor,
                               options: sensorOptions.map { SettingsMenuOption(title: $0.name, value: $0) })
            SettingsNumberField(title: "Focal length", unit: "mm", value: $inputs.focalLength,
                                range: LensSetup.focalLengthRange, fractionDigits: 1)
            SettingsNumberField(title: "Aperture", prefix: "f/", value: $inputs.aperture,
                                range: LensSetup.apertureRange, fractionDigits: 2)
            SettingsNumberField(title: "Pixel pitch", unit: "\u{00B5}m", optionalValue: $inputs.pixelPitch,
                                range: SensorFormat.pixelPitchRange, fractionDigits: 2)
            if setup != myCamera {
                Button("Reset to My Camera") {
                    inputs.sensor = myCamera.sensor
                    inputs.focalLength = myCamera.focalLengthMillimeters
                    inputs.aperture = myCamera.aperture
                    inputs.pixelPitch = myCamera.pixelPitchMicrometers
                }
            }
        }
    }

    private var declinationSection: some View {
        SettingsSection(
            title: "Target Declination",
            footer: "Stars near the celestial pole draw shorter trails. 0\u{00B0} is the celestial equator, where "
                + "trails are longest.") {
            SettingsSliderRow(title: "Declination",
                              valueText: AngleFormatter.formatSignedDegrees(inputs.declination, decimals: 1),
                              value: $inputs.declination, range: -90...90, step: 1)
            if let target = sky?.target {
                Button {
                    inputs.declination = target.declination
                } label: {
                    Label("Use \(target.name) (\(AngleFormatter.formatSignedDegrees(target.declination, decimals: 1)))",
                          systemImage: "scope")
                }
            } else {
                SettingsCaption("Choose a target on the Objects tab to use its declination here.")
            }
            Button {
                inputs.declination = sky?.poleDeclination ?? 90
            } label: {
                Label("Use the Celestial Pole", systemImage: "location.north.line")
            }
        }
    }

    // MARK: Results

    private func trailSection(setup: LensSetup) -> some View {
        let result = Result { try StarTrailPlanner.trail(duration: inputs.durationSeconds,
                                                         declination: inputs.declination, setup: setup) }
        return SettingsSection(title: "Star Trail") {
            SettingsNumberField(title: "Time", unit: "min", value: $inputs.durationMinutes,
                                range: 1...(StarTrailPlanner.maximumDurationSeconds / 60), fractionDigits: 0)
            switch result {
            case .success(let trail):
                VStack(alignment: .leading, spacing: 4) {
                    Text(ToolsPlannerText.degrees(trail.arcLengthDegrees))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                    Text("Trail on the sky \u{00B7} \(ToolsPlannerText.pixels(trail.arcLengthPixels)) in the image")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                InfoRow(label: "Sky rotation about the pole", value: ToolsPlannerText.degrees(trail.rotationDegrees))
                InfoRow(label: "Distance from the pole", value: ToolsPlannerText.degrees(trail.radiusFromPoleDegrees))
                if trail.radiusFromPoleDegrees <= 0 {
                    SettingsCaption("A star at the celestial pole stays in place and the sky turns around it. Stars "
                                    + "near the pole draw circles; the rotation above is how much of a circle they "
                                    + "complete.")
                }
                if trail.usedDefaultPixelPitch {
                    SettingsCaption("The length in pixels assumes a pixel pitch of \(Self.defaultPitchText) \u{00B5}m "
                                    + "because yours is not set.")
                }
            case .failure(let error):
                ToolsProblemRow(message: ToolsPlannerText.message(for: error))
            }
        }
    }

    private func durationSection(setup: LensSetup) -> some View {
        let result = Result { () throws -> Double in
            switch inputs.arcUnit {
            case .degrees:
                return try StarTrailPlanner.duration(forArcDegrees: inputs.arcDegrees, declination: inputs.declination)
            case .pixels:
                return try StarTrailPlanner.duration(forArcPixels: inputs.arcPixels, declination: inputs.declination,
                                                     setup: setup)
            }
        }
        return SettingsSection(
            title: "Time for a Chosen Trail",
            footer: "How long to shoot for stars at this declination to draw a trail of the length you want.") {
            Picker("Trail length in", selection: $inputs.arcUnit) {
                ForEach(ToolsTrailInputs.ArcUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            switch inputs.arcUnit {
            case .degrees:
                SettingsNumberField(title: "Trail on the sky", unit: "\u{00B0}", value: $inputs.arcDegrees,
                                    range: 0.1...360, fractionDigits: 1)
            case .pixels:
                SettingsNumberField(title: "Trail in the image", unit: "px", value: $inputs.arcPixels,
                                    range: 1...100_000, fractionDigits: 0)
            }
            switch result {
            case .success(let seconds):
                VStack(alignment: .leading, spacing: 4) {
                    Text(AngleFormatter.formatDuration(seconds: seconds))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                    Text("of shooting")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
            case .failure(let error):
                ToolsProblemRow(message: ToolsPlannerText.message(for: error))
            }
        }
    }

    private func stackSection(setup: LensSetup) -> some View {
        let result = Result { try StarTrailPlanner.stackingPlan(
            totalDuration: inputs.durationSeconds, declination: inputs.declination, setup: setup, rule: inputs.rule,
            exposureSeconds: inputs.exposure, gapSeconds: inputs.gap) }
        return SettingsSection(
            title: "Stacking Plan",
            footer: "Shoot the frames one after another, then stack them (lighten or maximum blend) into one picture. "
                + "Each frame is short enough to keep the stars sharp, and together they add up to the trail of the "
                + "time above.") {
            Picker("Rule", selection: $inputs.rule) {
                ForEach(ExposureRule.allCases) { option in
                    Text(option.stackShortName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            SettingsNumberField(title: "Exposure", unit: "s", optionalValue: $inputs.exposure,
                                range: 0.1...StarTrailPlanner.maximumExposureSeconds, fractionDigits: 1,
                                placeholder: "From the rule")
            SettingsNumberField(title: "Gap between exposures", unit: "s", value: $inputs.gap,
                                range: 0...StarTrailPlanner.maximumGapSeconds, fractionDigits: 1)
            switch result {
            case .success(let plan):
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ToolsPlannerText.count(plan.frameCount)) \(plan.frameCount == 1 ? "frame" : "frames") "
                         + "of \(AngleFormatter.formatExposure(seconds: plan.exposureSeconds))")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                    Text(inputs.exposure == nil
                         ? "The longest exposure the \(plan.estimate.rule.displayName) rule allows, rounded down."
                         : "Your exposure.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                InfoRow(label: "Time covered", value: AngleFormatter.formatDuration(seconds: plan.actualDuration))
                InfoRow(label: "Light collected", value: AngleFormatter.formatDuration(seconds: plan.lightSeconds))
                InfoRow(label: "Trail in one frame", value: ToolsPlannerText.pixels(plan.exposureTrailPixels))
                InfoRow(label: "Break between frames", value: ToolsPlannerText.pixels(plan.gapPixels))
                if plan.gapPixels > Self.visibleGapPixels {
                    SettingsCaption("The break between two frames is more than \(Int(Self.visibleGapPixels)) pixels "
                                    + "long, so it shows as a gap in the trail. Use a shorter gap or a longer "
                                    + "exposure.")
                }
                ForEach(plan.estimate.notes, id: \.self) { note in
                    SettingsCaption(note)
                }
            case .failure(let error):
                ToolsProblemRow(message: ToolsPlannerText.message(for: error))
            }
        }
    }

    private var poleSection: some View {
        SettingsSection(
            title: "Pole",
            footer: "The trails are circles around the celestial pole. Put it in the frame, and the stars draw arcs "
                + "around it.") {
            if let sky {
                let name = sky.hemisphere == .north ? "North celestial pole" : "South celestial pole"
                InfoRow(label: name, value: sky.poleAltitude >= 0 ? "Above the horizon" : "Below the horizon")
                InfoRow(label: "Altitude", value: AppFormat.altitude(sky.poleAltitude))
                InfoRow(label: "Direction", value: AppFormat.azimuth(sky.poleAzimuth))
                if let target = sky.target {
                    InfoRow(label: "From \(target.name)", value: AppFormat.separation(target.separationFromPole))
                    SettingsCaption(target.poleInFrame
                                    ? "With the camera on \(target.name) the pole is inside the frame."
                                    : "With the camera on \(target.name) the pole is outside the frame.")
                }
            } else {
                SettingsCaption("Choose an observing location in Settings to see where the pole stands.")
            }
        }
    }

    private static var defaultPitchText: String {
        ExposureCalculator.defaultPixelPitchMicrometers.formatted(.number.precision(.fractionLength(1)))
    }
}

/// A problem with the numbers entered, in the warning colour.
struct ToolsProblemRow: View {
    @Environment(\.palette) private var palette
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(palette.warning)
        .accessibilityElement(children: .combine)
    }
}

private extension ExposureRule {
    /// The label used in the segmented picker.
    var stackShortName: String {
        switch self {
        case .rule500: return "500"
        case .rule400: return "400"
        case .rule300: return "300"
        case .npf: return "NPF"
        }
    }
}
