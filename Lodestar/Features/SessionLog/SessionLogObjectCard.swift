import SwiftUI
import LodestarKit

/// The "Session log" card of an object's page: a button that logs a session and the object's earlier entries.
struct SessionLogObjectCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let object: CelestialObject
    @State private var presented: SessionLogSheetItem?
    @State private var entryToDelete: SessionLogEntry?

    private var entries: [SessionLogEntry] {
        app.sessionLog.entries(forTarget: object.id)
    }

    var body: some View {
        let logged = entries
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Session log", systemImage: "book.closed")
            Button {
                presented = SessionLogSheetItem(draft: newDraft(), isNew: true)
            } label: {
                Label("Log a Session", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
            if logged.isEmpty {
                Text("Nothing logged for this object yet.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            } else {
                ForEach(logged) { entry in
                    entryRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
        .sheet(item: $presented) { item in
            SessionLogEntrySheet(draft: item.draft, isNew: item.isNew)
                .environment(app)
                .themedRoot(palette, redFilter: app.settings.redFilterOverlay)
        }
        .confirmationDialog("Delete this entry?", isPresented: isConfirmingDelete, titleVisibility: .visible,
                            presenting: entryToDelete) { entry in
            Button("Delete Entry", role: .destructive) {
                app.sessionLog.delete(ids: [entry.id])
            }
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } })
    }

    private func newDraft() -> SessionLogDraft {
        SessionLogDraft.new(for: object, context: app.observerContext, lens: app.lensSetup,
                            filter: app.settings.imagingFilter, now: app.clock.now)
    }

    private func entryRow(_ entry: SessionLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                presented = SessionLogSheetItem(draft: SessionLogDraft(editing: entry), isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SessionLogFormat.dateText(of: entry))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(SessionLogFormat.summary(of: entry))
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                    if !entry.siteName.isEmpty {
                        Text(entry.siteName)
                            .font(.caption)
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the entry")
            Button {
                entryToDelete = entry
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(palette.secondaryText)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete entry")
        }
    }
}
