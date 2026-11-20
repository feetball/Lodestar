import SwiftUI
import UniformTypeIdentifiers

/// The file types of the formats Lodestar writes.
enum InterchangeFileType {
    /// A SkySafari observing list (`.skylist`, plain text).
    static let skylist = UTType(filenameExtension: "skylist", conformingTo: .plainText) ?? .plainText
}

/// A text file handed to the system's "save to Files" sheet (`fileExporter`).
struct InterchangeDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText, .xml, .plainText, InterchangeFileType.skylist]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// What a `fileExporter` needs besides the document: its type and the name offered.
struct InterchangeExport {
    var document = InterchangeDocument()
    var contentType: UTType = .commaSeparatedText
    var filename = "Lodestar"
    var isPresented = false

    /// Opens the save sheet for `text`.
    mutating func present(text: String, contentType: UTType, filename: String) {
        document = InterchangeDocument(text: text)
        self.contentType = contentType
        self.filename = filename
        isPresented = true
    }
}

extension View {
    /// Offers `export` through the system's save sheet, and says so when the file could not be saved.
    func interchangeExporter(_ export: Binding<InterchangeExport>) -> some View {
        modifier(InterchangeExporter(export: export))
    }
}

/// The save sheet of an `InterchangeExport` and the alert for a file that could not be written.
private struct InterchangeExporter: ViewModifier {
    @Binding var export: InterchangeExport
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .fileExporter(isPresented: $export.isPresented, document: export.document,
                          contentType: export.contentType, defaultFilename: export.filename) { result in
                guard case .failure(let error) = result else { return }
                // Closing the sheet without saving is not a failure.
                if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled { return }
                problem = error.localizedDescription
            }
            .alert("Could Not Save the File", isPresented: isShowingProblem) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
    }

    private var isShowingProblem: Binding<Bool> {
        Binding(get: { problem != nil }, set: { isPresented in
            if !isPresented { problem = nil }
        })
    }
}
