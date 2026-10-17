import SwiftUI
import LodestarKit

/// Catalog notes and the facts that do not fit anywhere else.
struct ObjectDetailAboutCard: View {
    @Environment(\.palette) private var palette

    let object: CelestialObject

    /// Whether the object has anything to show in this card.
    static func hasContent(for object: CelestialObject) -> Bool {
        object.notes != nil || !object.alternateNames.isEmpty || object.spectralType != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "About", systemImage: "info.circle")
            if let notes = object.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !object.alternateNames.isEmpty {
                InfoRow(label: "Also known as", value: object.alternateNames.joined(separator: ", "))
            }
            if let spectralType = object.spectralType {
                InfoRow(label: "Spectral type", value: spectralType)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }
}
