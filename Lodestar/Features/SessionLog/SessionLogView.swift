import SwiftUI
import UniformTypeIdentifiers
import LodestarKit

/// Settings ▸ Session Log: every entry grouped by night, with search, editing, deleting and export.
struct SessionLogView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    @State private var query = ""
    @State private var presented: SessionLogSheetItem?
    @State private var export = InterchangeExport()

    /// One night's entries.
    private struct Night: Identifiable {
        let night: Int64
        let entries: [SessionLogEntry]
        var id: Int64 { night }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matching: [SessionLogEntry] {
        let entries = app.sessionLog.entries
        guard !trimmedQuery.isEmpty else { return entries }
        return entries.filter { entry in
            [entry.targetName, entry.siteName, entry.filter, entry.camera, entry.notes]
                .contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }
    }

    private var nights: [Night] {
        Dictionary(grouping: matching, by: \.night)
            .map { Night(night: $0.key, entries: $0.value) }
            .sorted { $0.night > $1.night }
    }

    var body: some View {
        let groups = nights
        List {
            if app.sessionLog.entries.isEmpty {
                Section {
                    Text("Nothing logged yet. Open an object in Objects and tap Log a Session after a night out.")
                        .foregroundStyle(palette.secondaryText)
                        .listRowBackground(palette.surface)
                }
            } else {
                Section {
                    InfoRow(label: "Entries", value: "\(app.sessionLog.entries.count)")
                    InfoRow(label: "Imaged objects", value: "\(app.sessionLog.imagedTargetIDs.count)")
                    InfoRow(label: "Total exposure", value: totalExposureText)
                }
                .listRowBackground(palette.surface)
                .listRowSeparatorTint(palette.stroke)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        row(entry)
                    }
                    .onDelete { offsets in
                        app.sessionLog.delete(ids: Set(offsets.map { group.entries[$0].id }))
                    }
                } header: {
                    Text(SessionLogFormat.nightTitle(group.night))
                        .foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(palette.surface)
                .listRowSeparatorTint(palette.stroke)
            }
        }
        .themedList(palette)
        .searchable(text: $query, prompt: "Target, site, notes")
        .overlay {
            if groups.isEmpty, !app.sessionLog.entries.isEmpty {
                EmptyStateView(title: "No Results", systemImage: "magnifyingglass",
                               message: "No entry matches \u{201C}\(trimmedQuery)\u{201D}.") { EmptyView() }
            }
        }
        .navigationTitle("Session Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("CSV Table\u{2026}", systemImage: "tablecells") { exportCSV() }
                    Button("OpenAstronomyLog\u{2026}", systemImage: "doc.text") { exportOpenAstronomyLog() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(app.sessionLog.entries.isEmpty)
            }
        }
        .sheet(item: $presented) { item in
            SessionLogEntrySheet(draft: item.draft, isNew: item.isNew)
                .environment(app)
                .themedRoot(palette, redFilter: app.settings.redFilterOverlay)
        }
        .interchangeExporter($export)
    }

    private func row(_ entry: SessionLogEntry) -> some View {
        Button {
            presented = SessionLogSheetItem(draft: SessionLogDraft(editing: entry), isNew: false)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.targetName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    if entry.isImaged {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                            .accessibilityHidden(true)
                    }
                }
                Text(SessionLogFormat.summary(of: entry))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                Text(rowDetail(entry))
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits the entry")
    }

    private func rowDetail(_ entry: SessionLogEntry) -> String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        return entry.siteName.isEmpty ? time : "\(time) \u{00B7} \(entry.siteName)"
    }

    private var totalExposureText: String {
        let seconds = app.sessionLog.entries.reduce(0.0) { $0 + ($1.isImaged ? $1.totalExposureSeconds : 0) }
        return seconds > 0 ? AngleFormatter.formatDuration(seconds: seconds) : AppFormat.missing
    }

    // MARK: Export

    private func exportCSV() {
        export.present(text: SessionLogCodec.encodeCSV(app.sessionLog.entries), contentType: .commaSeparatedText,
                       filename: "Lodestar Session Log")
    }

    private func exportOpenAstronomyLog() {
        export.present(text: SessionLogCodec.encodeOpenAstronomyLog(app.sessionLog.entries), contentType: .xml,
                       filename: "Lodestar Session Log")
    }
}

/// The Session Log row of Settings.
struct SettingsSessionLogSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        SettingsSection(title: "Session Log",
                        footer: "A private diary of what you shot, kept on this device. Export it as a table or as an OpenAstronomyLog file.") {
            NavigationLink {
                SessionLogView()
            } label: {
                HStack {
                    Label("Session Log", systemImage: "book.closed")
                    Spacer()
                    Text("\(app.sessionLog.entries.count)")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }
}
