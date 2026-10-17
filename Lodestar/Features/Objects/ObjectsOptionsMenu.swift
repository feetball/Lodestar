import SwiftUI

/// The toolbar menu that groups, orders and filters the Objects list.
struct ObjectsOptionsMenu: View {
    @Binding var grouping: ObjectsGrouping
    @Binding var sortOrder: ObjectsSortOrder
    @Binding var showsOnlyAboveHorizon: Bool
    @Binding var hidesFaintObjects: Bool
    /// Filled when any option differs from the default list.
    let isCustomized: Bool
    /// The horizon filter needs an observer.
    let hasLocation: Bool

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
                Picker("Sort By", selection: $sortOrder) {
                    ForEach(ObjectsSortOrder.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
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
            }
        } label: {
            Label("Group, Sort and Filter",
                  systemImage: isCustomized ? "line.3.horizontal.decrease.circle.fill"
                                            : "line.3.horizontal.decrease.circle")
        }
    }
}
