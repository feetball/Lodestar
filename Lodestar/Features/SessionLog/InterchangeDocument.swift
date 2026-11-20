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
    /// Offers `export` through the system's save sheet.
    func interchangeExporter(_ export: Binding<InterchangeExport>) -> some View {
        fileExporter(isPresented: export.isPresented, document: export.wrappedValue.document,
                     contentType: export.wrappedValue.contentType,
                     defaultFilename: export.wrappedValue.filename) { _ in }
    }
}
