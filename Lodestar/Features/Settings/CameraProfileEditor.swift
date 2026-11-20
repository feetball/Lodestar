import SwiftUI
import LodestarKit

/// What the camera profile editor starts from.
enum CameraProfileEditorTarget: Identifiable {
    /// A saved profile.
    case existing(CameraProfile)
    /// A new profile from a preset.
    case preset(CameraPreset)
    /// A new profile from what a photo says; the editor shows what was read.
    case photo(CameraPhotoResult)

    var id: String {
        switch self {
        case .existing(let profile): return "profile-\(profile.id.uuidString)"
        case .preset(let preset): return "preset-\(preset.id)"
        case .photo: return "photo"
        }
    }
}

/// Adds or edits a camera profile: its name, sensor, lens and pixel pitch, with the field of view they give. Save adds
/// a new profile (and makes it the active one) or changes the saved one; Cancel keeps everything as it was.
///
/// Present it in a sheet wrapped in `SettingsSheetRoot`; it brings its own navigation stack.
struct CameraProfileEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let target: CameraProfileEditorTarget
    private let existing: CameraProfile?
    @State private var profile: CameraProfile
    @State private var nameText: String
    @State private var isConfirmingDelete = false
    @State private var failureMessage: String?

    init(target: CameraProfileEditorTarget) {
        self.target = target
        let initial: CameraProfile
        switch target {
        case .existing(let saved):
            existing = saved
            initial = saved
        case .preset(let preset):
            existing = nil
            initial = CameraProfile(preset: preset)
        case .photo(let result):
            existing = nil
            initial = CameraProfile(photo: result.suggestion)
        }
        _profile = State(initialValue: initial)
        _nameText = State(initialValue: initial.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                if case .photo(let result) = target {
                    photoSection(result)
                }
                sensorSection
                lensSection
                SettingsSection(title: "Frame") {
                    SettingsFieldOfViewReadout(setup: profile.lensSetup)
                }
                if existing != nil, app.settings.cameraProfiles.count > 1 {
                    deleteSection
                }
            }
            .themedList(palette)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "New Camera" : "Edit Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onChange(of: nameText) { _, name in
                if name.count > CameraProfile.maximumNameLength {
                    nameText = String(name.prefix(CameraProfile.maximumNameLength))
                }
            }
            .onChange(of: profile.projection) { _, projection in
                if !projection.isFisheye { profile.imageCircleDiameter = nil }
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        SettingsSection(title: "Name") {
            TextField("Camera name", text: $nameText, prompt: Text("Camera name").foregroundStyle(palette.tertiaryText))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            if let failureMessage {
                Text(failureMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.critical)
            }
        }
    }

    /// What the photo said, so the photographer can check it before saving; the picture itself is not kept.
    private func photoSection(_ result: CameraPhotoResult) -> some View {
        SettingsSection(
            title: "Read from the photo",
            footer: "Check the values below before you save. The sensor comes from the crop factor, and the pixel pitch "
                + "assumes the picture is neither cropped nor reduced. Lodestar does not keep the picture.") {
            ForEach(Array(CameraPhotoText.lines(result).enumerated()), id: \.offset) { _, line in
                InfoRow(label: line.label, value: line.value)
            }
        }
    }

    private var sensorSection: some View {
        SettingsSection(
            title: "Sensor",
            footer: "The pixel pitch is the spacing of the photosites. The NPF exposure rule and the image scale need it.") {
            SettingsMenuPicker(title: "Sensor", selection: $profile.sensorID, options: sensorOptions)
            if profile.isCustomSensor {
                SettingsNumberField(title: "Sensor width", unit: "mm", value: $profile.customSensorWidth,
                                    range: CameraProfile.customSensorRange, fractionDigits: 1)
                SettingsNumberField(title: "Sensor height", unit: "mm", value: $profile.customSensorHeight,
                                    range: CameraProfile.customSensorRange, fractionDigits: 1)
            }
            SettingsNumberField(title: "Pixel pitch", unit: "\u{00B5}m", optionalValue: $profile.pixelPitch,
                                range: CameraProfile.pixelPitchRange, fractionDigits: 2)
            SettingsMegapixelsHelper(sensor: profile.sensor, pixelPitch: $profile.pixelPitch,
                                     range: CameraProfile.pixelPitchRange)
        }
    }

    private var lensSection: some View {
        SettingsSection(title: "Lens") {
            SettingsMenuPicker(
                title: "Lens type", selection: $profile.projection,
                options: LensProjection.allCases.map { SettingsMenuOption(title: $0.displayName, value: $0) })
            SettingsCaption("A fisheye lens bends straight lines and sees a much wider view; its frame is drawn curved.")
            SettingsNumberField(title: "Focal length", unit: "mm", value: $profile.focalLength,
                                range: LensSetup.focalLengthRange, fractionDigits: 1)
            SettingsNumberField(title: "Aperture", prefix: "f/", value: $profile.aperture,
                                range: LensSetup.apertureRange, fractionDigits: 2)
            if profile.projection.isFisheye {
                SettingsNumberField(title: "Image circle", unit: "mm", optionalValue: $profile.imageCircleDiameter,
                                    range: LensSetup.imageCircleRange, fractionDigits: 1, placeholder: "Fills the sensor")
                SettingsCaption("For a circular fisheye whose picture is a circle smaller than the sensor: its "
                                + "diameter on the sensor. The frame is then that circle.")
            }
        }
    }

    private var deleteSection: some View {
        SettingsSection(title: "Delete") {
            if isConfirmingDelete {
                SettingsCaption("Delete \u{201C}\(existing?.name ?? "this camera")\u{201D}? This cannot be undone.")
                Button {
                    delete()
                } label: {
                    Text("Delete Camera")
                        .foregroundStyle(palette.critical)
                }
                Button("Keep Camera") { isConfirmingDelete = false }
            } else {
                Button {
                    isConfirmingDelete = true
                } label: {
                    Text("Delete Camera\u{2026}")
                        .foregroundStyle(palette.critical)
                }
            }
        }
    }

    /// The presets, then "Custom"; a profile's own identifier for a custom size is "custom".
    private var sensorOptions: [SettingsMenuOption<String>] {
        SensorFormat.presets.map { SettingsMenuOption(title: $0.name, value: $0.id) }
            + [SettingsMenuOption(title: "Custom", value: CameraProfile.customSensorID)]
    }

    // MARK: Actions

    private func save() {
        var saved = profile
        saved.name = nameText
        saved = saved.sanitized()
        if existing != nil {
            app.settingsStore.updateCameraProfile(saved)
        } else if !app.settingsStore.addCameraProfile(saved) {
            failureMessage = "You can keep up to \(AppSettings.maximumCameraProfiles) profiles. Delete one to add another."
            return
        }
        dismiss()
    }

    private func delete() {
        if let existing { app.settingsStore.removeCameraProfile(existing.id) }
        dismiss()
    }
}

/// The sheet that lists the presets: a plain full-frame camera to start from, and the smart telescopes. Picking one
/// calls `onPick`; the editor then opens with the preset's values.
struct CameraPresetPicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onPick: (CameraPreset) -> Void

    var body: some View {
        NavigationStack {
            Form {
                SettingsSection(title: "Plain camera") {
                    row(CameraPreset.fullFrame24)
                }
                SettingsSection(
                    title: "Smart telescopes",
                    footer: "The numbers are the makers\u{2019} published specifications. A smart telescope\u{2019}s sensor "
                        + "size is its pixel count times its pixel pitch.") {
                    ForEach(CameraPreset.smartTelescopes) { preset in
                        row(preset)
                    }
                }
            }
            .themedList(palette)
            .navigationTitle("Add Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ preset: CameraPreset) -> some View {
        Button {
            onPick(preset)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .foregroundStyle(palette.primaryText)
                Text(CameraProfileText.summary(preset.setup))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The subtitle texts of camera profiles.
enum CameraProfileText {
    /// "24 mm · f/2.8 · Full Frame · 74° × 53°", with the lens type for a fisheye.
    static func summary(_ profile: CameraProfile) -> String {
        summary(profile.lensSetup)
    }

    /// `summary(_:)` of a camera and lens.
    static func summary(_ setup: LensSetup) -> String {
        let frame = setup.fieldOfView
        var parts = [
            "\(SettingsNumberText.text(for: setup.focalLengthMillimeters, fractionDigits: 1)) mm",
            "f/\(SettingsNumberText.text(for: setup.aperture, fractionDigits: 2))",
            setup.sensor.name,
        ]
        if setup.projection.isFisheye { parts.append(setup.projection.displayName) }
        parts.append("\(AngleFormatter.formatDegrees(frame.horizontal, decimals: 0)) \u{00D7} "
                     + "\(AngleFormatter.formatDegrees(frame.vertical, decimals: 0))")
        return parts.joined(separator: " \u{00B7} ")
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
struct SettingsFieldOfViewReadout: View {
    let setup: LensSetup

    var body: some View {
        let frame = setup.fieldOfView
        VStack(alignment: .leading, spacing: 6) {
            InfoRow(label: "Field of view (landscape)",
                    value: "\(AngleFormatter.formatDegrees(frame.horizontal)) \u{00D7} "
                        + "\(AngleFormatter.formatDegrees(frame.vertical))")
            InfoRow(label: "Diagonal", value: AngleFormatter.formatDegrees(frame.diagonal))
            if setup.imageCircleDiameterMillimeters != nil {
                InfoRow(label: "Frame", value: "Circle")
            }
            InfoRow(label: "Full-frame equivalent",
                    value: "\(Int(setup.equivalentFocalLengthMillimeters.rounded())) mm")
            if let scale = setup.imageScaleArcsecondsPerPixel {
                InfoRow(label: "Image scale",
                        value: "\(scale.formatted(.number.precision(.fractionLength(1))))\u{2033} per pixel")
            }
        }
    }
}
