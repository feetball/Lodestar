import SwiftUI
import UIKit

/// A section title with the number of objects in the section.
struct ObjectsSectionHeader: View {
    @Environment(\.palette) private var palette

    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            CardTitle(title: title, systemImage: systemImage)
            Text(count.formatted())
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(palette.tertiaryText)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "object" : "objects")")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Fills a pressed row with the palette's raised surface instead of the system's grey highlight.
struct ObjectsRowButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? palette.surfaceRaised : .clear)
    }
}

/// Icons for swipe actions in a fixed colour.
///
/// List swipe actions draw their labels in white, which is not night-safe. An image rendered in its original
/// mode keeps the colour it was given.
enum ObjectsSwipeGlyph {
    static func image(systemName: String, color: Color) -> Image {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        guard let image = UIImage(systemName: systemName, withConfiguration: configuration)?
            .withTintColor(UIColor(color), renderingMode: .alwaysOriginal) else {
            return Image(systemName: systemName)
        }
        return Image(uiImage: image)
    }
}

/// Shown while the catalog loads.
struct ObjectsLoadingView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(palette.accent)
            Text("Loading the sky catalog\u{2026}")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground(palette)
        .accessibilityElement(children: .combine)
    }
}

/// A list row explaining why altitudes and rising times are missing.
struct ObjectsLocationNotice: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
                .foregroundStyle(palette.tertiaryText)
                .accessibilityHidden(true)
            Text("Add a location to see where objects are in your sky.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
            Spacer(minLength: 0)
            Button("Settings") {
                app.selectedTab = .settings
            }
            .buttonStyle(.plain)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.accent)
        }
    }
}

/// A list row saying that the recorded skyline decides what is visible and when objects rise.
struct ObjectsSkylineNotice: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Label {
            Text("Skyline applied: \u{201C}Behind skyline\u{201D} and the rising times follow your recorded skyline.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "mountain.2")
        }
        .font(.footnote)
        .foregroundStyle(palette.secondaryText)
        .accessibilityElement(children: .combine)
    }
}
