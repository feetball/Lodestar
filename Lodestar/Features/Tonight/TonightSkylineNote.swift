import SwiftUI

/// A small line that says the site's skyline (recorded, terrain or both) was applied, with what that changed in the card
/// above it.
struct TonightSkylineNote: View {
    @Environment(\.palette) private var palette
    @Environment(AppModel.self) private var app

    /// What the skyline changed here; shown after "Skyline applied" (or "Terrain horizon applied", "Recorded + terrain applied").
    var detail: String?

    private var applied: String { HorizonText.applied(app.observerContext?.horizonSource) }

    var body: some View {
        Label {
            Text(detail.map { "\(applied): \($0)" } ?? applied)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "mountain.2")
        }
        .font(.footnote)
        .foregroundStyle(palette.tertiaryText)
        .accessibilityElement(children: .combine)
    }
}
