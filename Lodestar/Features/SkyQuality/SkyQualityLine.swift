import SwiftUI
import LodestarKit

/// One line about the sky of a place, "Sky: Bortle ~4 (rural/suburban transition)", for site rows and the site editor.
/// A tap shows or hides the caveat that the class is an estimate from satellite imagery. Nothing for no place, while the
/// estimate is being worked out and when the map is unavailable.
struct SkyQualityLine: View {
    @Environment(\.palette) private var palette
    let location: GeographicLocation?
    @State private var estimate: BortleEstimate?
    @State private var isExplained = false

    var body: some View {
        Group {
            if let estimate {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sky: \(estimate.summary)")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                    if isExplained {
                        Text(BortleEstimate.caveat)
                            .font(.footnote)
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isExplained.toggle() }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(isExplained ? "Hides how the sky quality is estimated"
                                   : "Shows how the sky quality is estimated")
            }
        }
        .task(id: SkyQualityKey(location)) {
            guard let location else {
                estimate = nil
                return
            }
            estimate = await SkyQualityMapStore.shared.reading(at: location)?.estimate
        }
    }
}
