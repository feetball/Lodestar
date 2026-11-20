import SwiftUI
import PhotosUI
import LodestarKit

/// The sheet Settings ▸ Camera & Lens asks for: the list of presets, or the editor of a camera profile.
enum CameraSheet: Identifiable {
    case presets
    case editor(CameraProfileEditorTarget)

    var id: String {
        switch self {
        case .presets: return "presets"
        case .editor(let target): return target.id
        }
    }
}

/// What Settings ▸ Camera & Lens has asked to be presented. The rows only set it; the sheet hangs on the Settings form
/// (`settingsCameraSheets`), because a presentation attached to one row is lost when that row has scrolled out of
/// view and a list of cameras can be long.
struct SettingsCameraPresentation {
    var sheet: CameraSheet?
}

extension View {
    /// Presents what `presentation` asks for. Attach it once, to the Settings form, which is always on screen.
    func settingsCameraSheets(_ presentation: Binding<SettingsCameraPresentation>) -> some View {
        modifier(SettingsCameraSheets(presentation: presentation))
    }
}

private struct SettingsCameraSheets: ViewModifier {
    @Binding var presentation: SettingsCameraPresentation

    func body(content: Content) -> some View {
        content
            .sheet(item: $presentation.sheet) { sheet in
                SettingsSheetRoot {
                    switch sheet {
                    case .presets:
                        // Picking a preset swaps this sheet's content for the editor, so no sheet has to wait for
                        // another to leave the screen.
                        CameraPresetPicker { preset in presentation.sheet = .editor(.preset(preset)) }
                    case .editor(let target):
                        CameraProfileEditor(target: target)
                    }
                }
            }
    }
}

/// Settings ▸ Camera & Lens: the cameras and lenses the photographer uses, one of them active. The active profile gives
/// the framing rectangle on the Aim screen and the sky chart and the numbers of the exposure tools. Tap a profile to use
/// it, the pencil to edit it, swipe it to delete it; "Add Preset…" starts from a smart telescope or a plain camera and
/// "From a Photo…" reads the camera and lens from the EXIF data of a picture. The filter in front of the sensor, which
/// relaxes the Moon warnings for emission nebulae, is one setting for all profiles.
struct SettingsCameraSection: View {
    @Environment(AppModel.self) private var app
    @Binding var presentation: SettingsCameraPresentation
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoMessage: String?

    var body: some View {
        @Bindable var store = app.settingsStore
        let settings = store.settings
        let isFull = settings.cameraProfiles.count >= AppSettings.maximumCameraProfiles
        let canDelete = settings.cameraProfiles.count > 1
        SettingsSection(
            title: "Camera & Lens",
            footer: "Describe the camera on the tripod, not the phone. The active profile gives the framing rectangle on "
                + "the Aim screen and the sky chart, and the numbers of the exposure tools. A fisheye lens draws a "
                + "curved frame. Exposure rules use the real focal length, as for any lens. Narrowband filters make "
                + "emission nebulae usable under moonlight; Lodestar relaxes its Moon warnings for them.") {
            ForEach(settings.cameraProfiles) { profile in
                CameraProfileRow(
                    profile: profile,
                    isActive: profile.id == settings.activeCameraProfile.id,
                    canDelete: canDelete,
                    onActivate: { store.activateCameraProfile(profile.id) },
                    onEdit: { presentation.sheet = .editor(.existing(profile)) },
                    onDelete: { store.removeCameraProfile(profile.id) })
            }
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    presentation.sheet = .presets
                } label: {
                    Label("Add Preset\u{2026}", systemImage: "plus.circle")
                }
                .disabled(isFull)
                SettingsCaption("Smart telescopes such as the Seestar and the Dwarf, or a plain full-frame camera to "
                                + "start from.")
            }
            VStack(alignment: .leading, spacing: 4) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label("From a Photo\u{2026}", systemImage: "photo.on.rectangle")
                }
                .disabled(isFull)
                SettingsCaption("Reads the camera and lens from the data in a picture you took. The picture is not kept.")
            }
            if let photoMessage {
                SettingsCaption(photoMessage)
            }
            if isFull {
                SettingsCaption("You have reached the limit of \(AppSettings.maximumCameraProfiles) profiles.")
            }
            SettingsFieldOfViewReadout(setup: app.lensSetup)
            VStack(alignment: .leading, spacing: 4) {
                SettingsMenuPicker(title: "Filter", selection: $store.settings.imagingFilter,
                                   options: ImagingFilter.allCases.map {
                                       SettingsMenuOption(title: $0.displayName, value: $0)
                                   })
                SettingsCaption(store.settings.imagingFilter.summary)
            }
            SettingsToggleRow(
                title: "Camera preview",
                caption: "Shows the iPhone's camera behind the sky on the Aim screen. Lodestar asks for camera access "
                    + "the first time you turn it on.",
                isOn: $store.settings.cameraPreviewEnabled)
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
    }

    /// Reads the camera and lens from the picked picture and opens the editor with them.
    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { pickedPhoto = nil }
        photoMessage = nil
        var outcome = CameraPhotoReader.Outcome.noLens
        if let data = try? await item.loadTransferable(type: Data.self) {
            outcome = await Task.detached(priority: .userInitiated) {
                CameraPhotoReader.read(fromImageData: data)
            }.value
        }
        switch outcome {
        case .result(let result):
            presentation.sheet = .editor(.photo(result))
        case .focalLengthOutOfRange(let millimeters):
            photoMessage = CameraPhotoText.focalLengthMessage(millimeters: millimeters)
        case .noLens:
            photoMessage = CameraPhotoText.noLensMessage
        }
    }
}

/// A profile in the list: tap to use it, the pencil to edit it, swipe or press and hold to delete it (the last profile
/// cannot be deleted).
private struct CameraProfileRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let profile: CameraProfile
    let isActive: Bool
    let canDelete: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At the largest text sizes the pencil would leave the text a column of a few letters, so it moves to
                // its own line under the text.
                VStack(alignment: .leading, spacing: 4) {
                    selectButton
                    editButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 12) {
                    selectButton
                    editButton
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            Button("Edit", action: onEdit)
            if canDelete {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }

    private var selectButton: some View {
        Button(action: onActivate) {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isActive ? palette.accent : palette.tertiaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CameraProfileText.summary(profile))
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint("Uses this camera")
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil.circle")
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(profile.name)")
    }
}
