import SwiftUI
import LodestarKit

/// The toolbar menu that groups, orders and filters the Objects list.
struct ObjectsOptionsMenu: View {
    @Binding var grouping: ObjectsGrouping
    @Binding var sortOrder: ObjectsSortOrder
    @Binding var showsOnlyAboveHorizon: Bool
    @Binding var showsOnlyVisibleTonight: Bool
    @Binding var hidesFaintObjects: Bool
    @Binding var showsOnlyPopular: Bool
    @Binding var showsOnlyImaged: Bool
    /// Filled when any option differs from the default list.
    let isCustomized: Bool
    /// The horizon and tonight filters and the altitude, rise-time and hours-tonight orders need an observer.
    let hasLocation: Bool
    /// Opens the file picker of "Import List\u{2026}".
    let onImport: () -> Void
    /// Starts the export of the favorites in `format` (a table or a SkySafari list).
    let onExport: (ObservingListFormat) -> Void
    /// Whether there are favorites to export.
    let hasFavorites: Bool

    /// The order the list is really in: without a location the orders that need the sky's positions fall back to name
    /// order (see `ObjectsListBuilder.sections`), so the menu checks that one instead of the unusable choice.
    private var shownSortOrder: Binding<ObjectsSortOrder> {
        Binding(get: { !hasLocation && sortOrder.needsObserver ? .name : sortOrder },
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
                            .disabled(!hasLocation && option.needsObserver)
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
                Toggle(isOn: $showsOnlyVisibleTonight) {
                    Label("Visible \u{2265} 1 h Tonight", systemImage: "moon.stars")
                }
                .disabled(!hasLocation)
                Toggle(isOn: $hidesFaintObjects) {
                    Label("Hide Faint (mag > \(Int(ObjectsListOptions.faintMagnitudeLimit)))",
                          systemImage: "eye.slash")
                }
                Toggle(isOn: $showsOnlyPopular) {
                    Label("Popular Only", systemImage: "star.circle")
                }
                Toggle(isOn: $showsOnlyImaged) {
                    Label("Imaged Only", systemImage: "checkmark.circle")
                }
            }
            Section("Lists") {
                Button {
                    onImport()
                } label: {
                    Label("Import List\u{2026}", systemImage: "square.and.arrow.down")
                }
                Menu {
                    Button("CSV Table\u{2026}") { onExport(.genericCSV) }
                    Button("SkySafari List\u{2026}") { onExport(.skySafari) }
                } label: {
                    Label("Export Favorites\u{2026}", systemImage: "square.and.arrow.up")
                }
                .disabled(!hasFavorites)
            }
        } label: {
            Label("Group, Sort and Filter",
                  systemImage: isCustomized ? "line.3.horizontal.decrease.circle.fill"
                                            : "line.3.horizontal.decrease.circle")
        }
    }
}
