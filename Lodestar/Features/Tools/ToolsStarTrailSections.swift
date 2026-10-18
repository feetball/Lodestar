import SwiftUI
import LodestarKit

/// The sections of the star-trail plan: camera and lens, declination, the total time, the trail it draws, the time for
/// a chosen trail, the stacking plan and where the pole is.
struct ToolsStarTrailSections: View {
    @Environment(\.palette) private var palette
    @Binding var inputs: ToolsTrailInputs
    let myCamera: LensSetup
    let sky: ToolsTrailSky?

    var body: some View {
        let setup = inputs.setup
        cameraSection(setup: setup)
        declinationSection
        durationSection
        trailSection(setup: setup)
        arcSection(setup: setup)
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
            footer: "Starts from the camera in Settings; changes here stay in this planner. Without a pixel pitch "
                + "Lodestar assumes \(Self.defaultPitchText) \u{00B5}m, typical of a high-resolution camera.") {
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
        let poleDeclination = sky?.poleDeclination ?? 90
        return SettingsSection(
            title: "Target Declination",
            footer: "A star at the celestial equator (0\u{00B0}) draws the longest trail; the closer to the pole, the "
                + "shorter. At the pole itself a star does not move.") {
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
                inputs.declination = poleDeclination
            } label: {
                Label("Use the celestial pole (\(AngleFormatter.formatSignedDegrees(poleDeclination, decimals: 0)))",
                      systemImage: "location.north.line")
            }
        }
    }

    private var durationSection: some View {
        SettingsSection(
            title: "Total Time",
            footer: "The time the trails should span, from the start of the first exposure to the end of the last. "
                + "The sky turns 15\u{00B0} in an hour.") {
            SettingsNumberField(title: "Duration", unit: "min", value: $inputs.durationMinutes,
                                range: 0.1...ToolsTrailInputs.maximumMinutes, fractionDigits: 1)
            InfoRow(label: "In hours and minutes", value: AngleFormatter.formatDuration(seconds: inputs.durationSeconds))
        }
    }

    // MARK: Results

    private func trailSection(setup: LensSetup) -> some View {
        let result = Result { try StarTrailPlanner.trail(duration: inputs.durationSeconds,
                                                         declination: inputs.declination, setup: setup) }
        return SettingsSection(title: "Star Trail", footer: ToolsPlannerText.rateNote) {
            switch result {
            case .success(let trail):
                ToolsHeadline(
                    title: ToolsPlannerText.degrees(trail.arcLengthDegrees),
                    subtitle: "long on the sky at "
                        + "\(AngleFormatter.formatSignedDegrees(trail.declination, decimals: 1)) declination")
                InfoRow(label: "Trail in the picture", value: ToolsPlannerText.pixels(trail.arcLengthPixels))
                InfoRow(label: "Turn about the pole", value: ToolsPlannerText.degrees(trail.rotationDegrees))
                InfoRow(label: "Distance from the pole", value: ToolsPlannerText.degrees(trail.radiusFromPoleDegrees))
                if trail.usedDefaultPixelPitch {
                    SettingsCaption("The length in pixels assumes a pixel pitch of \(Self.defaultPitchText) \u{00B5}m "
                                    + "because yours is not set.")
                }
                SettingsCaption("Pixels are counted at the centre of the picture. Near the edges of a wide lens the "
                                + "trails are longer.")
            case .failure(let error):
                ToolsProblemRow(message: ToolsPlannerText.message(for: error))
            }
        }
    }

    private func arcSection(setup: LensSetup) -> some View {
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
            footer: "How long stars at this declination need to draw a trail of the length you want.") {
            Picker("Unit of the trail length", selection: $inputs.arcUnit) {
                ForEach(ToolsTrailInputs.ArcUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            switch inputs.arcUnit {
            case .degrees:
                SettingsNumberField(title: "Trail length", unit: "\u{00B0}", value: $inputs.arcDegrees,
                                    range: 0.1...360, fractionDigits: 1)
            case .pixels:
                SettingsNumberField(title: "Trail length", unit: "px", value: $inputs.arcPixels,
                                    range: 1...100_000, fractionDigits: 0)
            }
            switch result {
            case .success(let seconds):
                InfoRow(label: "Time needed", value: AngleFormatter.formatDuration(seconds: seconds))
                Button("Use as the total time") {
                    inputs.durationMinutes = min(max(seconds / 60, 0.1), ToolsTrailInputs.maximumMinutes)
                }
            case .failure(let error):
                ToolsProblemRow(message: ToolsPlannerText.message(for: error))
            }
        }
    }

    private func stackSection(setup: LensSetup) -> some View {
        let result = Result { try StarTrailPlanner.stackingPlan(
            totalDuration: inputs.durationSeconds, declination: inputs.declination, setup: setup, rule: inputs.rule,
            exposureSeconds: inputs.frameSeconds, gapSeconds: inputs.gapSeconds) }
        return SettingsSection(
            title: "Stacking Plan",
            footer: "Many short exposures stacked in software draw the same trails as one long exposure, without its "
                + "noise and sensor heat. Each frame is as long as the rule allows without trailing, rounded down to "
                + "a setting you can dial.") {
            Picker("Rule", selection: $inputs.rule) {
                ForEach(ExposureRule.allCases) { option in
                    Text(option.stackShortName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            SettingsNumberField(title: "Frame length", unit: "s", optionalValue: $inputs.frameSeconds,
                                range: 0.1...StarTrailPlanner.maximumExposureSeconds, fractionDigits: 1,
                                placeholder: "Automatic")
            SettingsNumberField(title: "Gap between frames", unit: "s", value: $inputs.gapSeconds,
                                range: 0...StarTrailPlanner.maximumGapSeconds, fractionDigits: 1)
            switch result {
            case .success(let plan):
                ToolsHeadline(
                    title: "\(ToolsPlannerText.count(plan.frameCount)) frames of "
                        + AngleFormatter.formatExposure(seconds: plan.exposureSeconds),
                    subtitle: "\(ToolsPlannerText.seconds(plan.gapSeconds)) between frames \u{00B7} "
                        + plan.estimate.rule.displayName)
                InfoRow(label: "Time covered", value: AngleFormatter.formatDuration(seconds: plan.actualDuration))
                InfoRow(label: "Shutter open in all", value: AngleFormatter.formatDuration(seconds: plan.lightSeconds))
                InfoRow(label: "Longest frame by the rule",
                        value: AngleFormatter.formatExposure(seconds: plan.estimate.seconds))
                InfoRow(label: "Trail in one frame", value: ToolsPlannerText.pixels(plan.exposureTrailPixels))
                InfoRow(label: "Movement during the gap", value: ToolsPlannerText.pixels(plan.gapPixels))
                SettingsCaption(ToolsPlannerText.gapVerdict(pixels: plan.gapPixels))
                if inputs.frameSeconds != nil, plan.exposureSeconds > plan.estimate.seconds {
                    SettingsCaption("This frame is longer than the rule allows, so stars may trail within each "
                                    + "frame.")
                }
                if inputs.frameSeconds == nil {
                    ForEach(plan.estimate.notes, id: \.self) { note in
                        SettingsCaption(note)
                    }
                }
            case .failure(let error):
                ToolsProblemRow(message: ToolsPlannerText.message(for: error))
            }
        }
    }

    // MARK: The pole

    private var poleSection: some View {
        SettingsSection(
            title: "Where the Pole Is",
            footer: "Trails are arcs of circles centred on the celestial pole. Point the camera near it and the stars "
                + "draw circles around the frame; point away from it and the arcs flatten.") {
            if let sky {
                InfoRow(label: "Pole", value: sky.hemisphere == .north ? "North celestial pole" : "South celestial pole")
                InfoRow(label: "Azimuth", value: AppFormat.azimuth(sky.poleAzimuth))
                InfoRow(label: "Altitude", value: AppFormat.altitude(sky.poleAltitude))
                SettingsCaption(sky.isPoleAboveHorizon
                                ? "The pole is \(AngleFormatter.formatDegrees(sky.poleAltitude, decimals: 0)) above "
                                    + "the horizon here: aim the camera at it for full circles."
                                : "The pole is below the horizon here, so no star circles it for you; trails are "
                                    + "arcs low in the sky.")
                if let target = sky.target {
                    SettingsCaption(Self.targetLine(target))
                }
            } else {
                SettingsCaption("Lodestar needs an observing location to find the pole. Choose one in Settings.")
            }
        }
    }

    /// Where the pole falls when the camera points at the target.
    private static func targetLine(_ target: ToolsTrailSky.Target) -> String {
        guard let separation = target.separationFromPole else { return "\(target.name) is below the horizon now." }
        let placement: String
        if target.isPoleBehind {
            placement = "behind the camera"
        } else if target.poleInLandscape && target.poleInPortrait {
            placement = "inside the frame, held either way"
        } else if target.poleInLandscape {
            placement = "inside a landscape frame but outside a portrait one"
        } else if target.poleInPortrait {
            placement = "inside a portrait frame but outside a landscape one"
        } else {
            placement = "outside the frame"
        }
        return "With \(target.name) at the centre of the frame, the pole is \(AppFormat.separation(separation)) away, "
            + "\(placement)."
    }

    private static var defaultPitchText: String {
        ExposureCalculator.defaultPixelPitchMicrometers.formatted(.number.precision(.fractionLength(1)))
    }
}

/// A large result with a line under it.
struct ToolsHeadline: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
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
