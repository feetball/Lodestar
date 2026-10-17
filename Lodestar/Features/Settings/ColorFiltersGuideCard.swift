import SwiftUI

/// How to turn the whole iPhone red with iOS Color Filters and the Accessibility Shortcut, which is the only way to
/// make system-drawn content (maps, keyboards, other apps) night-safe.
struct ColorFiltersGuideCard: View {
    private static let steps = [
        "Open the iOS Settings app, then Accessibility \u{25B8} Display & Text Size \u{25B8} Color Filters.",
        "Turn on Color Filters and choose Color Tint.",
        "Drag both Intensity and Hue all the way to the right. That gives a pure red; anything less looks "
            + "pinkish-orange.",
        "Optional: in Display & Text Size, turn on Reduce White Point to tone down the brightest colors.",
        "Go to Accessibility \u{25B8} Accessibility Shortcut and choose Color Filters. Triple-click the side button "
            + "(or the Home button) to switch the red screen on and off. Back Tap, Control Center and the Action "
            + "Button work too.",
    ]

    @Environment(\.palette) private var palette
    /// Whether the card repeats the title (leave it off when a section header already says it).
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                CardTitle(title: "Pure red for the whole iPhone", systemImage: "iphone")
            }
            Text("Lodestar draws everything it controls in red. For everything else, use iOS Color Filters, "
                 + "which tint the entire screen:")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(palette.accent))
                        .accessibilityHidden(true)
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step)")
            }
            Text("Color filters change everything on the iPhone, including photos and videos you view, but not the "
                 + "flashlight. Night Shift switches them off, so do not use both.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
