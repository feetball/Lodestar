import SwiftUI

/// The toolbar menu that groups, orders and filters the Objects list.
struct ObjectsOptionsMenu: View {
    @Binding var grouping: ObjectsGrouping
    @Binding var sortOrder: ObjectsSortOrder
    @Binding var showsOnlyAboveHorizon: Bool
    @Binding var hidesFaintObjects: Bool
    @Binding var showsOnlyPopular: Bool
    /// Filled when any option differs from the default list.
    let isCustomized: Bool
    /// The horizon filter and the altitude and rise-time orders need an observer.
    let hasLocation: Bool

    /// The order the list is really in: without a location the orders that need the sky's positions fall back to name
    /// order (see `ObjectsListBuilder.sections`), so the menu checks that one instead of the unusable choice.
    private var shownSortOrder: Binding<ObjectsSortOrder> {
        Binding(get: { !hasLocation && sortOrder.needsSkyPositions ? .name : sortOrder },
                set: { sortOrder = $0 })
    }

    var body: some View {
        Menu {
            Section("Group By") {
                Picker("Group By", selection: $grouping) {
                    ForEach(ObjectsGrouping.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Sort By") {
                Picker("Sort By", selection: shownSortOrder) {
                    ForEach(ObjectsSortOrder.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .disabled(!hasLocation && option.needsSkyPositions)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Filters") {
                Toggle(isOn: $showsOnlyAboveHorizon) {
                    Label("Above Horizon Now", systemImage: "arrow.up.right")
                }
                .disabled(!hasLocation)
                Toggle(isOn: $hidesFaintObjects) {
                    Label("Hide Faint (mag > \(Int(ObjectsListOptions.faintMagnitudeLimit)))",
                          systemImage: "eye.slash")
                }
                Toggle(isOn: $showsOnlyPopular) {
                    Label("Popular Only", systemImage: "star.circle")
                }
            }
        } label: {
            Label("Group, Sort and Filter",
                  systemImage: isCustomized ? "line.3.horizontal.decrease.circle.fill"
                                            : "line.3.horizontal.decrease.circle")
        }
    }
}
