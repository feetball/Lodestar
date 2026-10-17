import SwiftUI
import LodestarKit

/// Settings ▸ Camera & Lens: the sensor, lens and pixel size of the camera on the tripod, used for the framing
/// rectangle on the Aim screen and by the exposure tools, with a live field-of-view readout.
struct SettingsCameraSection: View {
    /// The identifier stored when the user picks a sensor that is not a preset.
    private static let customSensorID = "custom"
    /// Range accepted for a custom sensor's width and height; it matches what the settings keep on load.
    private static let customSensorRange = 1.0...100.0
    /// Range accepted for the pixel pitch; it matches what the settings keep on load.
    private static let pixelPitchRange = 0.5...20.0

    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var store = app.settingsStore
        let isCustomSensor = !SensorFormat.presets.contains { $0.id == store.settings.sensorID }
        SettingsSection(
            title: "Camera & Lens",
            footer: "Describe the camera on the tripod, not the phone. The framing rectangle on the Aim screen and "
                + "the exposure tools use these values.") {
            SettingsMenuPicker(title: "Sensor", selection: $store.settings.sensorID,
                               options: sensorOptions(storedID: store.settings.sensorID))
            if isCustomSensor {
                SettingsNumberField(title: "Sensor width", unit: "mm", value: $store.settings.customSensorWidth,
                                    range: Self.customSensorRange, fractionDigits: 1)
                SettingsNumberField(title: "Sensor height", unit: "mm", value: $store.settings.customSensorHeight,
                                    range: Self.customSensorRange, fractionDigits: 1)
            }
            SettingsNumberField(title: "Focal length", unit: "mm", value: $store.settings.focalLength,
                                range: LensSetup.focalLengthRange, fractionDigits: 1)
            SettingsNumberField(title: "Aperture", prefix: "f/", value: $store.settings.aperture,
                                range: LensSetup.apertureRange, fractionDigits: 2)
            SettingsNumberField(title: "Pixel pitch", unit: "\u{00B5}m", optionalValue: $store.settings.pixelPitch,
                                range: Self.pixelPitchRange, fractionDigits: 2)
            SettingsMegapixelsHelper(sensor: app.lensSetup.sensor, pixelPitch: $store.settings.pixelPitch,
                                     range: Self.pixelPitchRange)
            SettingsFieldOfViewReadout(setup: app.lensSetup)
            SettingsToggleRow(
                title: "Camera preview",
                caption: "Shows the iPhone's camera behind the sky on the Aim screen. Lodestar asks for camera access "
                    + "the first time you turn it on.",
                isOn: $store.settings.cameraPreviewEnabled)
        }
    }

    /// The presets, then "Custom". A stored identifier that is not a preset stands for the custom size, so it is
    /// the value of the "Custom" choice.
    private func sensorOptions(storedID: String) -> [SettingsMenuOption<String>] {
        var options = SensorFormat.presets.map { SettingsMenuOption(title: $0.name, value: $0.id) }
        let isPreset = SensorFormat.presets.contains { $0.id == storedID }
        options.append(SettingsMenuOption(title: "Custom", value: isPreset ? Self.customSensorID : storedID))
        return options
    }
}

/// Works out the pixel pitch from the camera's resolution: enter the megapixels, then apply the result.
private struct SettingsMegapixelsHelper: View {
    @Environment(\.palette) private var palette
    let sensor: SensorFormat
    @Binding var pixelPitch: Double?
    let range: ClosedRange<Double>
    @State private var megapixels: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsNumberField(title: "Resolution", unit: "MP", optionalValue: $megapixels, range: 1...500,
                                fractionDigits: 1, placeholder: "e.g. 45")
            if let derived {
                HStack {
                    Text("Pixel pitch \(derived.formatted(.number.precision(.fractionLength(2)))) \u{00B5}m")
                        .foregroundStyle(palette.secondaryText)
                    Spacer(minLength: 8)
                    Button("Use") { pixelPitch = derived }
                        .buttonStyle(.lodestarSecondary)
                }
            } else {
                SettingsCaption("Not sure of the pixel pitch? Enter the camera's resolution and Lodestar works it out "
                                + "from the sensor size. The NPF exposure rule needs it.")
            }
        }
    }

    /// The pitch for the entered resolution on the chosen sensor, when it is plausible.
    private var derived: Double? {
        guard let megapixels, let pitch = sensor.pixelPitchMicrometers(megapixels: megapixels),
              range.contains(pitch) else { return nil }
        return pitch
    }
}

/// The field of view of the chosen camera and lens, the full-frame equivalent focal length and the image scale.
private struct SettingsFieldOfViewReadout: View {
    let setup: LensSetup

    var body: some View {
        let frame = setup.fieldOfView
        VStack(alignment: .leading, spacing: 6) {
            InfoRow(label: "Field of view (landscape)",
                    value: "\(AngleFormatter.formatDegrees(frame.horizontal)) \u{00D7} "
                        + "\(AngleFormatter.formatDegrees(frame.vertical))")
            InfoRow(label: "Diagonal", value: AngleFormatter.formatDegrees(frame.diagonal))
            InfoRow(label: "Full-frame equivalent",
                    value: "\(Int(setup.equivalentFocalLengthMillimeters.rounded())) mm")
            if let scale = setup.imageScaleArcsecondsPerPixel {
                InfoRow(label: "Image scale",
                        value: "\(scale.formatted(.number.precision(.fractionLength(1))))\u{2033} per pixel")
            }
        }
    }
}
