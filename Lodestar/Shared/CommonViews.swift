import SwiftUI
import UIKit
import LodestarKit

/// The SF Symbol for an object category, coloured from the palette.
struct ObjectIcon: View {
    @Environment(\.palette) private var palette
    let category: ObjectCategory
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: category.systemImageName)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: size * 1.6, height: size * 1.6)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch category.group {
        case .solarSystem: return palette.planetMarker
        case .stars: return palette.primaryText
        case .galaxies, .nebulae, .clusters: return palette.deepSkyMarker
        case .special: return palette.accent
        }
    }
}

/// Visual tone of a status chip.
enum ChipTone {
    case neutral, positive, warning, critical
}

/// A compact capsule with an icon and a short label, used for sensor/alignment status.
struct StatusChip: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let systemImage: String
    let text: String
    var tone: ChipTone = .neutral

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            // At accessibility sizes a long chip wraps ("Visible from here") instead of being cut off.
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(foreground)
            .background(Capsule().fill(palette.surface.opacity(0.85)))
            .overlay(Capsule().strokeBorder(foreground.opacity(0.45), lineWidth: 0.75))
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return palette.secondaryText
        case .positive: return palette.positive
        case .warning: return palette.warning
        case .critical: return palette.critical
        }
    }
}

/// A label/value row used in detail cards.
struct InfoRow: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String

    var body: some View {
        // Label and value share a line when both fit on it; otherwise the value goes under the label and wraps there,
        // instead of being squeezed into a narrow column that breaks "10:54 PM" in two.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(palette.primaryText)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .foregroundStyle(palette.primaryText)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// Section title used inside scrolling card layouts.
struct CardTitle: View {
    @Environment(\.palette) private var palette
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.footnote.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Filled (primary) or outlined (secondary) capsule button drawn entirely with palette colours,
/// so it stays red-only in night mode (system prominent buttons use white text).
struct LodestarButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .foregroundStyle(kind == .primary ? palette.onAccent : palette.accent)
            .background(
                Capsule().fill(kind == .primary ? palette.accent : palette.surfaceRaised)
            )
            .overlay(Capsule().strokeBorder(palette.accent.opacity(kind == .primary ? 0 : 0.6), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == LodestarButtonStyle {
    static var lodestarPrimary: LodestarButtonStyle { LodestarButtonStyle(kind: .primary) }
    static var lodestarSecondary: LodestarButtonStyle { LodestarButtonStyle(kind: .secondary) }
}

/// Palette-coloured empty state (ContentUnavailableView uses system greys, which are not night-safe).
struct EmptyStateView<Actions: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(palette.tertiaryText)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
            actions()
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, systemImage: String, message: String) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// Shown when no observing location is available yet. Offers the next step for the current state:
/// asking for permission, waiting for the first fix, or opening iOS Settings after a refusal — and
/// always the alternative of choosing an observing site.
struct NeedsLocationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        EmptyStateView(title: title, systemImage: systemImage, message: message) {
            VStack(spacing: 10) {
                switch state {
                case .needsPermission:
                    Button("Allow Location Access") { app.location.requestAuthorization() }
                        .buttonStyle(.lodestarPrimary)
                case .denied:
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.lodestarPrimary)
                case .locating:
                    EmptyView()
                }
                Button("Choose an Observing Site") { app.selectedTab = .settings }
                    .buttonStyle(.lodestarSecondary)
            }
        }
    }

    private enum State { case needsPermission, locating, denied }

    private var state: State {
        if app.location.isDenied { return .denied }
        return app.location.isAuthorized ? .locating : .needsPermission
    }

    private var title: String {
        switch state {
        case .needsPermission: return "Location Needed"
        case .locating: return "Finding Your Location"
        case .denied: return "Location Access Is Off"
        }
    }

    private var systemImage: String {
        switch state {
        case .needsPermission: return "location"
        case .locating: return "location.magnifyingglass"
        case .denied: return "location.slash"
        }
    }

    private var message: String {
        switch state {
        case .needsPermission:
            return "Lodestar needs to know where you are to work out where things are in your sky. Approximate location is enough."
        case .locating:
            return "Waiting for the first position fix. Under open sky this takes a few seconds."
        case .denied:
            return "Turn on location access for Lodestar in iOS Settings, or choose an observing site on the map."
        }
    }
}
