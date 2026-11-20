import SwiftUI
import LodestarKit

/// A sheet that is open for one entry of the session log: new (from an object's page) or edited (from a list).
struct SessionLogSheetItem: Identifiable {
    let id = UUID()
    let draft: SessionLogDraft
    let isNew: Bool
}

/// Where and what was shot: the form of one session log entry.
struct SessionLogEntrySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SessionLogDraft
    @State private var isShowingFullAlert = false
    let isNew: Bool

    init(draft: SessionLogDraft, isNew: Bool) {
        _draft = State(initialValue: draft)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                targetSection
                framesSection
                gearSection
                notesSection
            }
            .themedList(palette)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "Log a Session" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.isValid)
                }
            }
            .alert("The Log Is Full", isPresented: $isShowingFullAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The session log holds \(SessionLogStore.maximumEntries) entries. Delete old ones in Settings \u{25B8} Session Log to make room.")
            }
        }
        .presentationBackground(palette.background)
    }

    // MARK: Sections

    private var targetSection: some View {
        Section {
            LabeledContent {
                Text(draft.targetName)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text("Target").foregroundStyle(palette.primaryText)
            }
            .listRowBackground(palette.surface)
            DatePicker(selection: $draft.date) {
                Text("Started").foregroundStyle(palette.primaryText)
            }
            .tint(palette.accent)
            .listRowBackground(palette.surface)
            textRow("Site", text: $draft.siteName, prompt: "Where you shot")
            Toggle(isOn: $draft.isImaged) {
                Text("Imaged").foregroundStyle(palette.primaryText)
            }
            .tint(palette.accent)
            .listRowBackground(palette.surface)
        } header: {
            Text("Session").foregroundStyle(palette.secondaryText)
        } footer: {
            Text("Turn on Imaged when you got the shot. A plan or a failed attempt can be logged too.")
                .foregroundStyle(palette.tertiaryText)
        }
    }

    private var framesSection: some View {
        Section {
            numberRow("Exposure (s)", text: $draft.exposureText, prompt: "120", keyboard: .decimalPad,
                      isValid: draft.exposureSeconds != nil)
            numberRow("ISO", text: $draft.isoText, prompt: "1600", keyboard: .numberPad, isValid: draft.iso != nil)
            numberRow("Frames", text: $draft.framesText, prompt: "30", keyboard: .numberPad,
                      isValid: draft.frameCount != nil)
            textRow("Filter", text: $draft.filter, prompt: "None")
        } header: {
            Text("Frames").foregroundStyle(palette.secondaryText)
        } footer: {
            Text("The exposure starts at the longest time before stars trail (the NPF rule) for the lens in Settings. "
                 + "Leave a field empty when you do not know it.")
                .foregroundStyle(palette.tertiaryText)
        }
    }

    private var gearSection: some View {
        Section {
            textRow("Camera", text: $draft.camera, prompt: "Sensor")
            if let focalLength = draft.focalLength, let aperture = draft.lensAperture {
                LabeledContent {
                    Text("\(SettingsNumberText.text(for: focalLength, fractionDigits: 1)) mm f/\(SettingsNumberText.text(for: aperture, fractionDigits: 1))")
                        .foregroundStyle(palette.secondaryText)
                } label: {
                    Text("Lens").foregroundStyle(palette.primaryText)
                }
                .listRowBackground(palette.surface)
            }
        } header: {
            Text("Gear").foregroundStyle(palette.secondaryText)
        }
    }

    private var notesSection: some View {
        Section {
            TextField("Notes", text: $draft.notes, prompt: Text("Seeing, sky, what went wrong")
                .foregroundStyle(palette.tertiaryText), axis: .vertical)
                .lineLimit(3...8)
                .foregroundStyle(palette.primaryText)
                .listRowBackground(palette.surface)
                .onChange(of: draft.notes) { _, notes in
                    if notes.count > SessionLogEntry.maximumNotesLength {
                        draft.notes = String(notes.prefix(SessionLogEntry.maximumNotesLength))
                    }
                }
        } header: {
            Text("Notes").foregroundStyle(palette.secondaryText)
        }
    }

    // MARK: Rows

    private func textRow(_ title: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(palette.tertiaryText))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(palette.primaryText)
        } label: {
            Text(title).foregroundStyle(palette.primaryText)
        }
        .listRowBackground(palette.surface)
    }

    private func numberRow(_ title: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType,
                           isValid: Bool) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(palette.tertiaryText))
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isValid ? palette.primaryText : palette.critical)
        } label: {
            Text(title).foregroundStyle(palette.primaryText)
        }
        .listRowBackground(palette.surface)
    }

    // MARK: Actions

    private func save() {
        guard draft.isValid else { return }
        let entry = draft.entry()
        if isNew {
            guard app.sessionLog.add(entry) else {
                isShowingFullAlert = true
                return
            }
        } else {
            app.sessionLog.update(entry)
        }
        dismiss()
    }
}
