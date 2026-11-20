import SwiftUI
import LodestarKit

/// The comets that are brighter than magnitude 10 and at least 25° from the Sun on the chosen night, brightest first,
/// each opening its detail screen; "Comets and Asteroids" opens the full lists. An empty list is normal and says so,
/// unless the Comets feed is off: then the card says where to switch it on.
struct SmallBodyTonightCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let entries: [SmallBodyListEntry]
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Bright Comets", systemImage: ObjectCategory.comet.systemImageName)
            if entries.isEmpty {
                TonightNote(text: SmallBodyTonightPlanner.emptyCardMessage(cometsAreOn: app.online.isEnabled(.comets)))
            } else {
                ForEach(entries) { entry in
                    if entry.id != entries.first?.id {
                        TonightRowSeparator()
                    }
                    NavigationLink(value: entry.object) {
                        SmallBodyListRow(entry: entry, timeZone: timeZone)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                TonightNote(text: SmallBodyText.footnote, style: .footnote)
            }
            NavigationLink(value: SmallBodyListRoute()) {
                Text("Comets and Asteroids")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }
}
