import SwiftUI
import LodestarKit

// The Tracked, Alt-Az Mount and Moon sections of the exposure calculator.

/// Where the target and the Moon are at one instant: what the Alt-Az Mount and Moon sections need.
struct ExposureSky: Sendable, Equatable {
    /// The target's azimuth in degrees, or nil without a target or a location.
    let targetAzimuth: Double?
    /// The target's altitude in degrees, or nil without a target or a location.
    let targetAltitude: Double?
    /// The lit fraction of the Moon's disc, 0 to 1.
    let moonIlluminatedFraction: Double
    /// The Moon's altitude in degrees, or nil without a location.
    let moonAltitude: Double?
    /// The Moon's apparent diameter in degrees.
    let moonDiameterDegrees: Double
}

/// The astronomy behind `ExposureSky`. Pure, so it can run on any thread.
enum ExposureSkyCalculator {
    /// Where `target` and the Moon are at `date`. Without an `observer` the Moon's phase and size are worked out from
    /// the equator (they hardly depend on the place) and no altitude is given.
    static func compute(observer: Observer?, target: CelestialObject?, date: Date) -> ExposureSky {
        let frame = SkyFrame(date: date,
                             observer: observer ?? Observer(location: GeographicLocation(latitude: 0, longitude: 0)))
        let targetPlace: HorizontalCoordinate? = observer == nil
            ? nil
            : target.map { frame.horizontal(of: $0, refraction: true) }
        let moon = frame.state(of: .moon)
        return ExposureSky(
            targetAzimuth: targetPlace?.azimuth,
            targetAltitude: targetPlace?.altitude,
            moonIlluminatedFraction: moon.illuminatedFraction ?? 1,
            moonAltitude: observer == nil ? nil : frame.horizontal(of: .moon, refraction: true).altitude,
            moonDiameterDegrees: moon.angularDiameterArcseconds / AstroMath.arcsecondsPerDegree)
    }
}

/// What the calculator's refresh of the sky restarts on: another observer or another target.
struct ExposureSkyKey: Equatable {
    let context: ObserverContext?
    let targetID: String?
}

/// Number and text formats shared by the three sections.
private enum ExposureTrackedFormat {
    /// The ISO speeds of the Moon section's picker.
    static let isoChoices = [100, 200, 400, 800, 1600, 3200, 6400, 12800]

    /// The step of the altitude and azimuth steppers, in degrees.
    static let stepperStep = 5.0

    /// The altitudes the altitude stepper offers, in degrees: 5° to 85° keeps clear of the zenith, where the rate diverges.
    static let stepperAltitudeRange = 5.0...85.0

    /// A number with exactly `digits` decimals in the user's format.
    static func decimal(_ value: Double, _ digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    /// "0.26″/s": a rate in arcseconds per second, with fewer decimals the larger it is.
    static func rate(_ arcsecondsPerSecond: Double) -> String {
        let digits = arcsecondsPerSecond >= 100 ? 0 : (arcsecondsPerSecond >= 10 ? 1 : 2)
        return "\(decimal(arcsecondsPerSecond, digits))\u{2033}/s"
    }

    /// The pixel pitch assumed when none is set, e.g. "4.0".
    static var defaultPitchText: String {
        decimal(ExposureCalculator.defaultPixelPitchMicrometers, 1)
    }

    static var defaultPitchCaption: String {
        "The limits assume a pixel pitch of \(defaultPitchText)\u{00A0}\u{00B5}m because yours is not set."
    }

    /// The tolerance of the limits in pixels, e.g. "1.5".
    static var toleranceText: String {
        decimal(TrackedExposure.defaultTolerancePixels, 1)
    }

    /// The choice of the ISO picker closest to `iso`: stored values need not be one of the choices.
    static func nearestISO(_ iso: Int) -> Int {
        isoChoices.min { abs($0 - iso) < abs($1 - iso) } ?? isoChoices[0]
    }

    /// Azimuth in [0, 360).
    static func wrapAzimuth(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}

// MARK: Tracked

/// A tracker whose axis is off the pole: the drift rate and the longest exposure for the current lens.
struct ExposureTrackedSection: View {
    @Environment(AppModel.self) private var app
    let setup: LensSetup

    var body: some View {
        @Bindable var store = app.settingsStore
        let error = store.settings.polarErrorDegrees
        let drift = TrackedExposure.driftRate(polarErrorDegrees: error)
        let seconds = TrackedExposure.maxExposureForPolarError(setup: setup, polarErrorDegrees: error)
        SettingsSection(
            title: "Tracked",
            footer: "Worst case: a tracker whose axis is off the pole drifts the stars by up to 15.04\u{2033} \u{00D7} "
                + "sin(error) a second. The limit allows \(ExposureTrackedFormat.toleranceText)\u{00A0}px of drift.") {
            SettingsSliderRow(title: "Polar alignment error",
                              valueText: "\(ExposureTrackedFormat.decimal(error, 1))\u{00B0}",
                              value: $store.settings.polarErrorDegrees, range: AppSettings.polarErrorRange, step: 0.1)
            InfoRow(label: "Drift rate", value: ExposureTrackedFormat.rate(drift))
            InfoRow(label: "Longest exposure", value: AngleFormatter.formatExposure(seconds: seconds))
            if setup.pixelPitchMicrometers == nil {
                SettingsCaption(ExposureTrackedFormat.defaultPitchCaption)
            }
        }
    }
}

// MARK: Alt-az mount

/// The field rotation of an alt-azimuth mount: the rate and the longest exposure at the target's place now, or at the
/// place set with the steppers when there is no target (or no location to place it).
struct ExposureAltAzSection: View {
    let setup: LensSetup
    let target: CelestialObject?
    let sky: ExposureSky?
    /// The observer's latitude in degrees, or nil when no location is known.
    let latitude: Double?
    @Binding var altitude: Double
    @Binding var azimuth: Double

    /// The target's place now, or nil when there is no target or it cannot be placed.
    private var targetPlace: (azimuth: Double, altitude: Double)? {
        guard target != nil, let placeAzimuth = sky?.targetAzimuth, let placeAltitude = sky?.targetAltitude else {
            return nil
        }
        return (placeAzimuth, placeAltitude)
    }

    var body: some View {
        let place = targetPlace
        let shownAzimuth = place?.azimuth ?? azimuth
        let shownAltitude = place?.altitude ?? altitude
        let observerLatitude = latitude ?? 0
        let rate = TrackedExposure.fieldRotationRate(latitude: observerLatitude, azimuth: shownAzimuth,
                                                     altitude: shownAltitude)
        let seconds = TrackedExposure.maxExposureForFieldRotation(
            setup: setup, latitude: observerLatitude, azimuth: shownAzimuth, altitude: shownAltitude)
        SettingsSection(
            title: "Alt-Az Mount",
            footer: "An alt-azimuth mount keeps the target centred but turns the field about it. The limit allows "
                + "\(ExposureTrackedFormat.toleranceText)\u{00A0}px of trailing at the corner of the frame.") {
            if let target, place != nil {
                InfoRow(label: target.name,
                        value: "\(AppFormat.azimuth(shownAzimuth)) \u{00B7} \(AppFormat.altitude(shownAltitude))")
            } else {
                SettingsCaption(target.map { "Lodestar needs a location to place \($0.name). Set its place here instead." }
                    ?? "Choose a target on the Objects tab to use its place here, or set one below.")
                ExposureStepperRow(
                    title: "Altitude", valueText: AppFormat.altitude(altitude),
                    canDecrement: altitude > ExposureTrackedFormat.stepperAltitudeRange.lowerBound,
                    canIncrement: altitude < ExposureTrackedFormat.stepperAltitudeRange.upperBound,
                    onDecrement: { altitude = clampedAltitude(altitude - ExposureTrackedFormat.stepperStep) },
                    onIncrement: { altitude = clampedAltitude(altitude + ExposureTrackedFormat.stepperStep) })
                ExposureStepperRow(
                    title: "Azimuth", valueText: AppFormat.azimuth(azimuth),
                    canDecrement: true, canIncrement: true,
                    onDecrement: { azimuth = ExposureTrackedFormat.wrapAzimuth(azimuth - ExposureTrackedFormat.stepperStep) },
                    onIncrement: { azimuth = ExposureTrackedFormat.wrapAzimuth(azimuth + ExposureTrackedFormat.stepperStep) })
            }
            InfoRow(label: "Field rotation", value: ExposureTrackedFormat.rate(rate))
            InfoRow(label: "Longest exposure", value: seconds.map { AngleFormatter.formatExposure(seconds: $0) } ?? "No limit")
            if seconds == nil {
                SettingsCaption("No field rotation here: due east or west an alt-azimuth mount keeps the sky upright.")
            }
            if latitude == nil {
                SettingsCaption("Location unknown: assuming the equator, where the field turns fastest.")
            }
            if setup.pixelPitchMicrometers == nil {
                SettingsCaption(ExposureTrackedFormat.defaultPitchCaption)
            }
        }
    }

    private func clampedAltitude(_ value: Double) -> Double {
        min(max(value, ExposureTrackedFormat.stepperAltitudeRange.lowerBound),
            ExposureTrackedFormat.stepperAltitudeRange.upperBound)
    }
}

/// A row with a title, a value and buttons that lower and raise it.
private struct ExposureStepperRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let valueText: String
    let canDecrement: Bool
    let canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).foregroundStyle(palette.primaryText)
                    HStack(spacing: 16) {
                        lowerButton
                        valueLabel
                        raiseButton
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text(title).foregroundStyle(palette.primaryText)
                    Spacer(minLength: 8)
                    lowerButton
                    valueLabel
                    raiseButton
                }
            }
        }
        // The buttons are the controls; without this the whole row would be one tap target in a form.
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
    }

    private var valueLabel: some View {
        Text(valueText)
            .monospacedDigit()
            .foregroundStyle(palette.secondaryText)
    }

    private var lowerButton: some View {
        Button(action: onDecrement) {
            Image(systemName: "minus.circle")
                .font(.title3)
                .foregroundStyle(canDecrement ? palette.accent : palette.tertiaryText)
        }
        .disabled(!canDecrement)
        .accessibilityLabel("Lower \(title.lowercased())")
        .accessibilityValue(valueText)
    }

    private var raiseButton: some View {
        Button(action: onIncrement) {
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(canIncrement ? palette.accent : palette.tertiaryText)
        }
        .disabled(!canIncrement)
        .accessibilityLabel("Raise \(title.lowercased())")
        .accessibilityValue(valueText)
    }
}

// MARK: Moon

/// The Moon: the shutter time for tonight's phase and height at the calculator's aperture, and its size in pixels.
struct ExposureMoonSection: View {
    @Environment(AppModel.self) private var app
    let setup: LensSetup
    let sky: ExposureSky?

    var body: some View {
        let iso = ExposureTrackedFormat.nearestISO(app.settings.exposureISO)
        SettingsSection(
            title: "Moon",
            footer: "Looney 11: f/11 at 1/ISO for a full Moon, with a longer exposure for a thinner or lower Moon. "
                + "A starting point: check the histogram.") {
            SettingsMenuPicker(
                title: "ISO",
                selection: Binding(get: { iso }, set: { app.settingsStore.settings.exposureISO = $0 }),
                options: ExposureTrackedFormat.isoChoices.map { SettingsMenuOption(title: "\($0)", value: $0) })
            if let sky {
                let suggestion = MoonExposure.suggest(
                    illuminatedFraction: sky.moonIlluminatedFraction, altitude: sky.moonAltitude ?? 90,
                    aperture: setup.aperture, iso: Double(iso))
                InfoRow(label: "Moon", value: moonSummary(sky))
                InfoRow(label: "Shutter at f/\(setup.aperture.formatted(.number.precision(.fractionLength(0...2)))), ISO \(iso)",
                        value: AngleFormatter.formatExposure(seconds: suggestion.seconds))
                SettingsCaption(suggestion.note)
                if sky.moonAltitude == nil {
                    SettingsCaption("Without a location the Moon's height is unknown: the shutter assumes it is high in the sky.")
                }
                if let size = sizeText(sky) {
                    SettingsCaption(size)
                }
            } else {
                SettingsCaption("Working out the Moon\u{2026}")
            }
        }
    }

    /// "62% lit · +34.2°", or "62% lit · below the horizon".
    private func moonSummary(_ sky: ExposureSky) -> String {
        var parts = ["\(AppFormat.percent(sky.moonIlluminatedFraction)) lit"]
        if let altitude = sky.moonAltitude {
            parts.append(altitude > 0 ? AppFormat.altitude(altitude) : "below the horizon")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "The Moon spans 454 px at your focal length", with the pixel pitch that was assumed when there is none.
    private func sizeText(_ sky: ExposureSky) -> String? {
        guard let pixels = TrackedExposure.pixelSize(angularDiameterDegrees: sky.moonDiameterDegrees, setup: setup) else {
            return nil
        }
        let text = "The Moon spans \(ExposureTrackedFormat.decimal(pixels.rounded(), 0))\u{00A0}px at your focal length"
        return setup.pixelPitchMicrometers == nil
            ? "\(text), assuming \(ExposureTrackedFormat.defaultPitchText)\u{00A0}\u{00B5}m pixels."
            : "\(text)."
    }
}
