import SwiftUI
import UniformTypeIdentifiers
import LodestarKit

/// A list read from a file, waiting in the import sheet.
struct ObjectsImportedList: Identifiable {
    let id = UUID()
    let list: ObservingListImport
}

/// Reading list files and writing the favorites as lists.
enum ObjectsListFile {
    /// The largest file that is opened, in bytes.
    private static let largestFileBytes = 16_000_000

    /// The types the file picker offers; any file can be chosen, because SkySafari lists have no common type.
    static var importTypes: [UTType] {
        [.commaSeparatedText, .plainText, InterchangeFileType.skylist, .data]
    }

    /// Reads and decodes a list off the main actor.
    ///
    /// - Throws: `InterchangeError` for a file that is not a usable list, or the error of the file system.
    static func read(_ url: URL) async throws -> ObservingListImport {
        try await Task.detached(priority: .userInitiated) {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= largestFileBytes else {
                throw InterchangeError.tooLarge(maximumScalars: ObservingListCodec.maximumTextScalars)
            }
            return try ObservingListCodec.decode(text(of: try Data(contentsOf: url)))
        }.value
    }

    /// The text of a file: UTF-16 with a byte order mark (spreadsheets write it), else UTF-8, else Windows Latin 1.
    static func text(of data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// The favorites as list entries, in the order of the favorites.
    static func entries(forFavorites ids: [String], in catalog: Catalog) -> [ObservingListEntry] {
        ids.compactMap { catalog.object(id: $0) }.map { object in
            let position = object.j2000
            return ObservingListEntry(name: object.name, designation: object.designations.first,
                                      rightAscension: position?.rightAscension, declination: position?.declination,
                                      typeName: object.category.displayName)
        }
    }

    /// What a read error says to the person.
    static func message(for error: Error) -> String {
        if let error = error as? InterchangeError {
            return error.description
        }
        return "The file could not be opened."
    }
}

/// The rows of an imported list sorted by what can be done with them.
struct ObjectsImportPlan: Sendable {
    /// A row that is in the catalog.
    struct Found: Identifiable, Sendable {
        let id: Int
        let label: String
        let object: CelestialObject
    }

    /// A row that is not in the catalog.
    struct Missing: Identifiable, Sendable {
        let id: Int
        let label: String
        /// The J2000 place of the row, when it has one: the row can then be aimed at as a custom target.
        let position: EquatorialCoordinate?
    }

    private(set) var found: [Found] = []
    private(set) var missing: [Missing] = []

    init(matches: [ObservingListMatch]) {
        var seen = Set<String>()
        for (index, match) in matches.enumerated() {
            let label = match.target.displayName ?? "Line \(match.target.line)"
            if let object = match.object {
                if seen.insert(object.id).inserted {
                    found.append(Found(id: index, label: label, object: object))
                }
            } else {
                var position: EquatorialCoordinate?
                if let rightAscension = match.target.rightAscension, let declination = match.target.declination {
                    position = EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
                }
                missing.append(Missing(id: index, label: label, position: position))
            }
        }
    }
}

/// Shows what an imported list holds, which of it Lodestar knows, and adds the known objects to the favorites.
struct ObjectsImportSheet: View {
    let imported: ObjectsImportedList

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var plan: ObjectsImportPlan?

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    content(plan)
                } else {
                    VStack(spacing: 12) {
                        ProgressView().tint(palette.accent)
                        Text("Matching the list\u{2026}").foregroundStyle(palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .screenBackground(palette)
            .navigationTitle("Import List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(palette.background)
        .task {
            await match()
        }
    }

    // MARK: Content

    private func content(_ plan: ObjectsImportPlan) -> some View {
        let favorites = Set(app.settings.favoriteObjectIDs)
        let fresh = plan.found.filter { !favorites.contains($0.object.id) }
        let room = max(AppSettings.maximumFavorites - favorites.count, 0)
        let toAdd = min(fresh.count, room)
        return List {
            summarySection(plan, toAdd: toAdd, fresh: fresh.count, room: room)
            if !plan.found.isEmpty {
                Section {
                    ForEach(plan.found) { item in
                        HStack {
                            Text(item.label).foregroundStyle(palette.primaryText)
                            Spacer(minLength: 8)
                            Text(favorites.contains(item.object.id) ? "Already a favorite" : item.object.name)
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryText)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("In the Catalog").foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(palette.surface)
                .listRowSeparatorTint(palette.stroke)
            }
            if !plan.missing.isEmpty {
                missingSection(plan)
            }
            if !imported.list.errors.isEmpty {
                problemsSection
            }
        }
        .themedList(palette)
        .safeAreaInset(edge: .bottom) {
            Button {
                addFavorites(plan)
            } label: {
                Label(toAdd == 0 ? "Nothing to Add" : "Add \(toAdd) to Favorites", systemImage: "star")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarPrimary)
            .disabled(toAdd == 0)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(palette.surface)
        }
    }

    private func summarySection(_ plan: ObjectsImportPlan, toAdd: Int, fresh: Int, room: Int) -> some View {
        Section {
            InfoRow(label: "Format", value: imported.list.format.displayName)
            InfoRow(label: "Rows", value: "\(imported.list.targets.count)")
            InfoRow(label: "In the catalog", value: "\(plan.found.count)")
            InfoRow(label: "Not in the catalog", value: "\(plan.missing.count)")
            if imported.list.isTruncated {
                Text("Only the first \(ObservingListCodec.maximumTargets) rows were read.")
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
            }
            if fresh > room {
                Text("Favorites hold \(AppSettings.maximumFavorites) objects, so only \(toAdd) can be added.")
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
            }
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.stroke)
    }

    private func missingSection(_ plan: ObjectsImportPlan) -> some View {
        Section {
            ForEach(plan.missing) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label).foregroundStyle(palette.primaryText)
                        Text(item.position == nil ? "Skipped: no coordinates" : "Has coordinates")
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer(minLength: 8)
                    if let position = item.position {
                        Button("Aim") {
                            dismiss()
                            app.aim(at: CelestialObject.custom(name: item.label, j2000: position))
                        }
                        .buttonStyle(.lodestarSecondary)
                    }
                }
            }
        } header: {
            Text("Not in the Catalog").foregroundStyle(palette.secondaryText)
        } footer: {
            Text("A row with coordinates can be aimed at as a custom target. Custom targets are not kept in the favorites.")
                .foregroundStyle(palette.tertiaryText)
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.stroke)
    }

    private var problemsSection: some View {
        Section {
            ForEach(Array(imported.list.errors.prefix(200).enumerated()), id: \.offset) { _, error in
                Text("Line \(error.line): \(error.reason.message)")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        } header: {
            Text("Problems").foregroundStyle(palette.secondaryText)
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.stroke)
    }

    // MARK: Actions

    /// Matches the rows against the catalog off the main actor.
    private func match() async {
        guard let catalog = app.catalog.catalog else {
            plan = ObjectsImportPlan(matches: imported.list.targets.map { ObservingListMatch(target: $0, object: nil) })
            return
        }
        let targets = imported.list.targets
        plan = await Task.detached(priority: .userInitiated) {
            ObjectsImportPlan(matches: ObservingListMatcher.match(targets, in: catalog))
        }.value
    }

    private func addFavorites(_ plan: ObjectsImportPlan) {
        var ids = app.settings.favoriteObjectIDs
        var known = Set(ids)
        for item in plan.found where !known.contains(item.object.id) {
            guard ids.count < AppSettings.maximumFavorites else { break }
            ids.append(item.object.id)
            known.insert(item.object.id)
        }
        app.settingsStore.settings.favoriteObjectIDs = ids
        dismiss()
    }
}
