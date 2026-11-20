import Foundation

/// Why a file could not be read or a document could not be made.
///
/// Problems with single rows are not errors: they are reported in `ObservingListImport.errors` and the rest of the file
/// is still read.
public enum InterchangeError: Error, Hashable, Sendable {
    /// The text has no content.
    case empty
    /// A CSV table has no column for a name or designation and no pair of right ascension and declination columns.
    case missingColumns
    /// The text is longer than `maximumScalars` Unicode scalars.
    case tooLarge(maximumScalars: Int)
    /// A quoted field that starts on `line` is never closed.
    case unterminatedQuote(line: Int)
    /// The plan is placed in azimuth and altitude, so its panels have no right ascension and declination.
    case horizontalPlan
}

extension InterchangeError: LocalizedError, CustomStringConvertible {
    /// A sentence that says what is wrong with the file.
    public var description: String {
        switch self {
        case .empty:
            "The file is empty."
        case .missingColumns:
            "The table has no name, designation or coordinate columns."
        case .tooLarge(let maximumScalars):
            "The file is larger than \(maximumScalars) characters."
        case .unterminatedQuote(let line):
            "The quotation mark on line \(line) is never closed."
        case .horizontalPlan:
            "A plan in azimuth and altitude has no fixed right ascension and declination."
        }
    }

    public var errorDescription: String? { description }
}
