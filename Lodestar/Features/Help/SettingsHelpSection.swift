import SwiftUI

/// The top of the Settings tab: the way into the help pages.
struct SettingsHelpSection: View {
    var body: some View {
        SettingsSection(title: "Help", footer: "Short guides to every screen, with a search. The ? buttons on the "
                        + "screens open the page that belongs to them.") {
            NavigationLink {
                HelpView()
            } label: {
                Label("Help & Guides", systemImage: "questionmark.circle")
            }
            NavigationLink {
                HelpTopicView(topic: HelpContent.topic(.gettingStarted))
            } label: {
                Label("Your First Night", systemImage: "flag")
            }
        }
    }
}
