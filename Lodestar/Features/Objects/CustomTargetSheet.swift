import SwiftUI
import LodestarKit

/// A sheet for aiming at a place in the sky that is not in the catalog: a name and a J2000 right ascension
/// and declination typed in.
struct CustomTargetSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var rightAscensionText = ""
    @State private var declinationText = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, rightAscension, declination
    }

    /// The right ascension in hours, when the text is a valid one.
    private var rightAscension: Double? {
        AngleFormatter.parseRightAscension(rightAscensionText)
    }

    /// The declination in degrees, when the text is a valid one.
    private var declination: Double? {
        AngleFormatter.parseDeclination(declinationText)
    }

    private var position: EquatorialCoordinate? {
        guard let rightAscension, let declination else { return nil }
        return EquatorialCoordinate(rightAscensionHours: rightAscension, declination: declination)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                positionSection
                aimSection
            }
            .themedList(palette)
            .navigationTitle("Custom Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onSubmit(advanceFocus)
            .onChange(of: name) { _, newName in
                if newName.count > CelestialObject.maximumCustomNameLength {
                    name = String(newName.prefix(CelestialObject.maximumCustomNameLength))
                }
            }
        }
        .presentationBackground(palette.background)
        .presentationDragIndicator(.hidden)
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            LabeledContent {
                TextField("Name", text: $name, prompt: prompt("Optional"))
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(palette.primaryText)
            } label: {
                Text("Name").foregroundStyle(palette.primaryText)
            }
            .listRowBackground(palette.surface)
        } header: {
            sectionHeader("Target")
        }
    }

    private var positionSection: some View {
        Section {
            coordinateRow(title: "Right Ascension", text: $rightAscensionText, field: .rightAscension,
                          example: "05h 35m 17s", submitLabel: .next)
            fieldNote(text: rightAscensionText, field: .rightAscension,
                      accepted: rightAscension.map { AngleFormatter.formatRightAscension(hours: $0) },
                      rejection: "Not a right ascension. Try 5h 35m 17s, 05:35:17 or 83.8\u{00B0}.")
            coordinateRow(title: "Declination", text: $declinationText, field: .declination,
                          example: "\u{2212}05\u{00B0} 23\u{2032} 28\u{2033}", submitLabel: .done)
            fieldNote(text: declinationText, field: .declination,
                      accepted: declination.map { AngleFormatter.formatDeclination(degrees: $0) },
                      rejection: "Not a declination. Try \u{2212}05\u{00B0} 23\u{2032} 28\u{2033} or \u{2212}5.391.")
        } header: {
            sectionHeader("Position (J2000)")
        } footer: {
            Text("Catalogues list positions for the J2000 equinox. "
                 + "A right ascension without a \u{00B0} sign is read as hours.")
                .foregroundStyle(palette.tertiaryText)
        }
    }

    private var aimSection: some View {
        Section {
            Button {
                aim()
            } label: {
                Text("Aim at Target")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarPrimary)
            .disabled(position == nil)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: Pieces

    private func sectionHeader(_ title: String) -> some View {
        Text(title).foregroundStyle(palette.secondaryText)
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(palette.tertiaryText)
    }

    private func coordinateRow(title: String, text: Binding<String>, field: Field, example: String,
                               submitLabel: SubmitLabel) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: prompt(example))
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(palette.primaryText)
        } label: {
            Text(title).foregroundStyle(palette.primaryText)
        }
        .listRowBackground(palette.surface)
    }

    /// What was understood from a coordinate, or why it was not; nothing while the field is empty or being typed in.
    @ViewBuilder
    private func fieldNote(text: String, field: Field, accepted: String?, rejection: String) -> some View {
        if let accepted {
            Label(accepted, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .listRowBackground(palette.surface)
        } else if !text.isEmpty, focusedField != field {
            Label(rejection, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(palette.critical)
                .listRowBackground(palette.surface)
        }
    }

    // MARK: Actions

    private func advanceFocus() {
        switch focusedField {
        case .name: focusedField = .rightAscension
        case .rightAscension: focusedField = .declination
        case .declination, .none: focusedField = nil
        }
    }

    private func aim() {
        guard let position else { return }
        app.aim(at: CelestialObject.custom(name: name, j2000: position))
        dismiss()
    }
}
