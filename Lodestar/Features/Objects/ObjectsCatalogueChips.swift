import SwiftUI

/// The row of chips above the Objects list that chooses the catalogue.
struct ObjectsCatalogueChips: View {
    @Environment(\.palette) private var palette

    @Binding var selection: ObjectsCatalogueFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ObjectsCatalogueFilter.allCases) { filter in
                    chip(filter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Catalogue")
    }

    private func chip(_ filter: ObjectsCatalogueFilter) -> some View {
        let isSelected = selection == filter
        return Button {
            selection = filter
        } label: {
            Text(filter.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? palette.onAccent : palette.secondaryText)
                .background(Capsule().fill(isSelected ? palette.accent : palette.surfaceRaised))
                .overlay(Capsule().strokeBorder(palette.stroke, lineWidth: isSelected ? 0 : 0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.fullTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
