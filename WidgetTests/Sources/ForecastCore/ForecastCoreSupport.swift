import Foundation

// The two small types of the app's `OnlineParsing.swift` that the forecast parser uses. That file reads the satellite and
// comet parsers as well, which this package does not compile, so these are the same declarations on their own.

/// Thrown by a parser that was handed bytes it cannot use.
struct OnlineDataError: Error, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// The result of parsing a download: the value, and the newest orbit epoch in it if it has one.
struct OnlineParsed<Value: Sendable>: Sendable {
    let value: Value
    var dataEpoch: Date?
}
