import SwiftUI
import LodestarKit

/// Estimates the longest exposure that keeps stars looking like points, for the camera and lens from Settings or
/// any other combination tried here, and shows how long the star trails of a chosen exposure would be.
///
/// Push it inside a navigation stack (Settings ▸ Tools). Changes made here are local and never touch Settings.
struct ExposureCalculatorView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ExposureCalculatorForm(myCamera: app.lensSetup)
    }
}

/// The calculator's form. It starts from the user's camera and keeps its own copy of the inputs.
private struct ExposureCalculatorForm: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    private let myCamera: LensSetup
    @State private var rule = ExposureRule.npf
    @State private var sensor: SensorFormat
    @State private var focalLength: Double
    @State private var aperture: Double
    @State private var pixelPitch: Double?
    @State private var declination = 0.0
    @State private var targetDeclination: Double?
    @State private var testSeconds = 20.0

    init(myCamera: LensSetup) {
        self.myCamera = myCamera
        _sensor = State(initialValue: myCamera.sensor)
        _focalLength = State(initialValue: myCamera.focalLengthMillimeters)
        _aperture = State(initialValue: myCamera.aperture)
        _pixelPitch = State(initialValue: myCamera.pixelPitchMicrometers)
    }

    var body: some View {
        let setup = currentSetup
        let estimate = ExposureCalculator.maxExposure(rule: rule, setup: setup, declination: declination)
        Form {
            ruleSection
            cameraSection(setup: setup)
            declinationSection
            resultSection(estimate: estimate, setup: setup)
            comparisonSection(setup: setup)
            trailSection(setup: setup)
        }
        .themedList(palette)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Exposure Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.target?.id) {
            targetDeclination = app.target.map(apparentDeclination(of:))
        }
    }

    // MARK: Inputs

    private var currentSetup: LensSetup {
        LensSetup(sensor: sensor, focalLengthMillimeters: focalLength, aperture: aperture,
                  pixelPitchMicrometers: pixelPitch)
    }

    /// The presets, plus the user's own sensor when it is a custom size.
    private var sensorOptions: [SensorFormat] {
        SensorFormat.presets.contains(myCamera.sensor) ? SensorFormat.presets : SensorFormat.presets + [myCamera.sensor]
    }

    private var ruleSection: some View {
        SettingsSection(title: "Rule") {
            Picker("Rule", selection: $rule) {
                ForEach(ExposureRule.allCases) { option in
                    Text(option.shortName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                SettingsCaption(rule.summary)
                SettingsCaption(rule.formula)
            }
        }
    }

    private func cameraSection(setup: LensSetup) -> some View {
        SettingsSection(title: "Camera & Lens", footer: cameraFooter) {
            SettingsMenuPicker(title: "Sensor", selection: $sensor,
                               options: sensorOptions.map { SettingsMenuOption(title: $0.name, value: $0) })
            SettingsNumberField(title: "Focal length", unit: "mm", value: $focalLength,
                                range: LensSetup.focalLengthRange, fractionDigits: 1)
            SettingsNumberField(title: "Aperture", prefix: "f/", value: $aperture,
                                range: LensSetup.apertureRange, fractionDigits: 2)
            SettingsNumberField(title: "Pixel pitch", unit: "\u{00B5}m", optionalValue: $pixelPitch,
                                range: SensorFormat.pixelPitchRange, fractionDigits: 2)
            if setup != myCamera {
                Button("Reset to My Camera") {
                    sensor = myCamera.sensor
                    focalLength = myCamera.focalLengthMillimeters
                    aperture = myCamera.aperture
                    pixelPitch = myCamera.pixelPitchMicrometers
                }
            }
        }
    }

    private var cameraFooter: String {
        if rule == .npf {
            return "NPF needs the pixel pitch. Without it Lodestar assumes \(Self.defaultPitchText) \u{00B5}m, "
                + "typical of a high-resolution camera."
        }
        return "The 500, 400 and 300 rules use the focal length multiplied by the sensor's crop factor."
    }

    private var declinationSection: some View {
        SettingsSection(
            title: "Target Declination",
            footer: "Stars near the celestial pole move more slowly, so the exposure can be longer. 0\u{00B0} is the "
                + "celestial equator, the worst case.") {
            SettingsSliderRow(title: "Declination",
                              valueText: AngleFormatter.formatSignedDegrees(declination, decimals: 1),
                              value: $declination, range: -90...90, step: 1)
            if let target = app.target, let targetDeclination {
                Button {
                    declination = targetDeclination
                } label: {
                    Label("Use \(target.name) (\(AngleFormatter.formatSignedDegrees(targetDeclination, decimals: 1)))",
                          systemImage: "scope")
                }
            } else {
                SettingsCaption("Choose a target on the Objects tab to use its declination here.")
            }
        }
    }

    // MARK: Results

    private func resultSection(estimate: ExposureEstimate, setup: LensSetup) -> some View {
        SettingsSection(title: "Longest Exposure") {
            VStack(alignment: .leading, spacing: 4) {
                Text(AngleFormatter.formatExposure(seconds: estimate.seconds))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                Text("\(rule.displayName) \u{00B7} \(ExposureCalculatorForm.lensText(setup))")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityElement(children: .combine)
            InfoRow(label: "Star trail at this exposure",
                    value: ExposureCalculatorForm.trailText(seconds: estimate.seconds, declination: declination,
                                                            setup: setup))
            ForEach(estimate.notes, id: \.self) { note in
                SettingsCaption(note)
            }
            if setup.pixelPitchMicrometers == nil, rule != .npf {
                SettingsCaption("Trail lengths in pixels assume a pixel pitch of \(Self.defaultPitchText) \u{00B5}m "
                                + "because yours is not set.")
            }
        }
    }

    private func comparisonSection(setup: LensSetup) -> some View {
        SettingsSection(title: "All Rules", footer: "The same camera and declination with each rule.") {
            ForEach(ExposureRule.allCases) { other in
                let estimate = ExposureCalculator.maxExposure(rule: other, setup: setup, declination: declination)
                InfoRow(label: other.displayName, value: AngleFormatter.formatExposure(seconds: estimate.seconds))
            }
        }
    }

    private func trailSection(setup: LensSetup) -> some View {
        SettingsSection(
            title: "Check an Exposure",
            footer: "A rough guide: under one pixel stars stay points; beyond about three pixels the trails are "
                + "plain to see at full size.") {
            SettingsNumberField(title: "Exposure", unit: "s", value: $testSeconds, range: 0.1...3600, fractionDigits: 1)
            let pixels = ExposureCalculator.trailLengthPixels(exposureSeconds: testSeconds, declination: declination,
                                                              setup: setup)
            InfoRow(label: "Star trail",
                    value: ExposureCalculatorForm.trailText(seconds: testSeconds, declination: declination,
                                                            setup: setup))
            SettingsCaption(ExposureCalculatorForm.verdict(forTrailPixels: pixels))
        }
    }

    // MARK: Helpers

    /// The pixel pitch assumed when none is set, e.g. "4.0".
    private static var defaultPitchText: String {
        ExposureCalculator.defaultPixelPitchMicrometers.formatted(.number.precision(.fractionLength(1)))
    }

    private func apparentDeclination(of object: CelestialObject) -> Double {
        let observer = app.observerContext?.observer
            ?? Observer(location: GeographicLocation(latitude: 0, longitude: 0))
        return SkyFrame(date: app.clock.now, observer: observer).apparentEquatorial(of: object).declination
    }

    /// "24 mm f/2.8 on Full Frame".
    private static func lensText(_ setup: LensSetup) -> String {
        let focalLength = setup.focalLengthMillimeters.formatted(.number.precision(.fractionLength(0...1)))
        let aperture = setup.aperture.formatted(.number.precision(.fractionLength(0...2)))
        return "\(focalLength) mm f/\(aperture) on \(setup.sensor.name)"
    }

    /// "1.2 px (18″)": the length of a star trail in the image and on the sky.
    private static func trailText(seconds: Double, declination: Double, setup: LensSetup) -> String {
        let pixels = ExposureCalculator.trailLengthPixels(exposureSeconds: seconds, declination: declination,
                                                          setup: setup)
        let arcseconds = ExposureCalculator.trailLengthArcseconds(exposureSeconds: seconds, declination: declination)
        return "\(pixels.formatted(.number.precision(.fractionLength(1)))) px "
            + "(\(AppFormat.separation(arcseconds / AstroMath.arcsecondsPerDegree)))"
    }

    private static func verdict(forTrailPixels pixels: Double) -> String {
        switch pixels {
        case ..<1: return "Stars stay sharp points."
        case ..<2: return "Stars are nearly sharp; trails show only when you zoom in."
        case ..<4: return "Slight trails are visible at full size."
        default: return "Clear star trails."
        }
    }
}

private extension ExposureRule {
    /// The label used in the segmented picker.
    var shortName: String {
        switch self {
        case .rule500: return "500"
        case .rule400: return "400"
        case .rule300: return "300"
        case .npf: return "NPF"
        }
    }

    /// The rule written as a formula.
    var formula: String {
        switch self {
        case .rule500: return "Seconds = 500 \u{00F7} (focal length \u{00D7} crop factor)"
        case .rule400: return "Seconds = 400 \u{00F7} (focal length \u{00D7} crop factor)"
        case .rule300: return "Seconds = 300 \u{00F7} (focal length \u{00D7} crop factor)"
        case .npf:
            return "Seconds = (35 \u{00D7} f-number + 30 \u{00D7} pixel pitch in \u{00B5}m) \u{00F7} focal length in mm"
        }
    }
}
