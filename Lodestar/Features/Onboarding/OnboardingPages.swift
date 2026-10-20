import SwiftUI
import UIKit
import LodestarKit

/// The common layout of an onboarding step: a symbol, a title and an introduction above the step's own content.
struct OnboardingPage<Content: View>: View {
    @Environment(\.palette) private var palette
    let systemImage: String
    let title: String
    let introduction: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(introduction)
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A symbol with a heading and a sentence, used for lists of facts and tips.
private struct OnboardingFactRow: View {
    @Environment(\.palette) private var palette
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Welcome

/// Step 1: what Lodestar does.
struct OnboardingWelcomePage: View {
    var body: some View {
        OnboardingPage(
            systemImage: "scope",
            title: "Aim at the night sky",
            introduction: "Lodestar turns your iPhone, clamped to your camera, into a smart finder. Pick a target and "
                + "arrows tell you how to pan and tilt the tripod head until it is in the frame.") {
            OnboardingFactRow(systemImage: "iphone", title: "Clamp your phone to the camera",
                              text: "Its sensors tell Lodestar where the camera points.")
            OnboardingFactRow(systemImage: "sparkles", title: "Choose a target",
                              text: "The Moon, planets, bright stars, nebulae, galaxies and the Milky Way core.")
            OnboardingFactRow(systemImage: "arrow.up.right", title: "Follow the arrows",
                              text: "Turn the head until the target sits in the middle, then shoot.")
            OnboardingFactRow(systemImage: "lock", title: "Private by design",
                              text: "Everything is worked out on your iPhone. There are no accounts and no tracking.")
            OnboardingFactRow(systemImage: "questionmark.circle", title: "Help is always at hand",
                              text: "Settings \u{25B8} Help explains every screen, and the ? buttons open the page "
                                  + "that belongs to it.")
        }
    }
}

// MARK: - Mounting

/// Step 2: how the phone is mounted.
struct OnboardingMountPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        OnboardingPage(
            systemImage: "iphone",
            title: "Mount your phone",
            introduction: "Tell Lodestar how the phone sits on the camera. You can change this later in Settings.") {
            VStack(spacing: 10) {
                ForEach(MountProfile.presets) { profile in
                    presetButton(profile)
                }
            }
            OnboardingFactRow(systemImage: "wrench.and.screwdriver", title: "Use a rigid bracket",
                              text: "Any wobble in the clamp shows up as aiming error.")
            OnboardingFactRow(systemImage: "camera", title: "Point the phone's camera along the lens",
                              text: "Keep the two roughly parallel. Lodestar corrects small tilts when you align on a "
                                  + "star.")
        }
    }

    private func presetButton(_ profile: MountProfile) -> some View {
        let isSelected = profile.id == app.mountProfile.id
        return Button {
            app.settingsStore.settings.mountPresetID = profile.id
        } label: {
            MountPresetRowLabel(profile: profile, isSelected: isSelected)
                .card(palette, padding: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.accent, lineWidth: isSelected ? 2 : 0))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Location

/// Step 3: why Lodestar wants the location, and the way around it.
struct OnboardingPermissionsPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var editorTarget: SiteEditorTarget?

    var body: some View {
        OnboardingPage(
            systemImage: "location",
            title: "Where are you?",
            introduction: "Lodestar needs your position to work out where things are in your sky. It asks only while "
                + "the app is open, an approximate position is enough, and it is never tracked. It stays on "
                + "your iPhone; only the optional cloud forecast sends it, rounded to about 10 km.") {
            HStack {
                status
                Spacer(minLength: 0)
            }
            actions
            OnboardingFactRow(systemImage: "camera", title: "The camera is optional",
                              text: "Lodestar asks for camera access the first time you show the camera picture behind "
                                  + "the sky on the Aim screen.")
        }
        .sheet(item: $editorTarget) { target in
            SettingsSheetRoot {
                SiteEditor(target: target) { site in
                    app.settingsStore.settings.locationSource = .site(site.id)
                }
            }
        }
    }

    /// Where things stand: the observing site, the device location, or what is missing.
    @ViewBuilder private var status: some View {
        switch app.settings.locationSource {
        case .site:
            StatusChip(systemImage: "mappin.and.ellipse",
                       text: "Observing from \(app.observerContext?.name ?? "your site")", tone: .positive)
        case .device:
            if app.location.isAuthorized {
                StatusChip(systemImage: "location.fill", text: "Using your current location", tone: .positive)
            } else if app.location.isDenied {
                StatusChip(systemImage: "location.slash", text: "Location access is off", tone: .warning)
            } else {
                StatusChip(systemImage: "location", text: "Location access not asked yet", tone: .neutral)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch app.settings.locationSource {
        case .device:
            if app.location.isDenied {
                OnboardingActionButton(title: "Open iOS Settings", isPrimary: true) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } else if !app.location.isAuthorized {
                OnboardingActionButton(title: "Allow Location Access", isPrimary: true) {
                    app.location.requestAuthorization()
                }
            }
            OnboardingActionButton(title: "Choose a Site Instead", isPrimary: false) {
                editorTarget = .new(SiteDraft(name: "My Site"))
            }
            SettingsCaption("No GPS, or planning from home? Pick any place on the map or type its coordinates.")
        case .site:
            OnboardingActionButton(title: "Use My Current Location Instead", isPrimary: false) {
                app.settingsStore.settings.locationSource = .device
                app.location.requestAuthorization()
            }
        }
    }
}

/// A full-width button in the onboarding flow.
private struct OnboardingActionButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LodestarButtonStyle(kind: isPrimary ? .primary : .secondary))
    }
}

// MARK: - Night vision

/// Step 4: night mode and the iOS Color Filters tip.
struct OnboardingNightPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var store = app.settingsStore
        OnboardingPage(
            systemImage: "moon.stars",
            title: "Protect your night vision",
            introduction: "A bright screen ruins dark adaptation. Night mode draws everything in pure red on black and "
                + "dims the screen. Try it now.") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Night mode")
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
                Picker("Night mode", selection: $store.settings.nightMode) {
                    ForEach(NightModeSetting.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                SettingsCaption("After Sunset switches on by itself when the Sun is more than 6\u{00B0} below the "
                                + "horizon. You can fine-tune it in Settings.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(palette)
            ColorFiltersGuideCard()
                .card(palette)
        }
    }
}
