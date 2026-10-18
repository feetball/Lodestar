import SwiftUI

/// A small line that says the site's recorded skyline was applied, with what that changed in the card above it.
struct TonightSkylineNote: View {
    @Environment(\.palette) private var palette

    /// What the skyline changed here; shown after "Skyline applied".
    var detail: String?

    var body: some View {
        Label {
            Text(detail.map { "Skyline applied: \($0)" } ?? "Skyline applied")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "mountain.2")
        }
        .font(.footnote)
        .foregroundStyle(palette.tertiaryText)
        .accessibilityElement(children: .combine)
    }
}
