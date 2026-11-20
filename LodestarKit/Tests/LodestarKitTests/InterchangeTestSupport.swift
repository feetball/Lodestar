import XCTest
@testable import LodestarKit

/// Reads the interchange fixtures (`Fixtures/interchange/`).
enum InterchangeTestSupport {
    static func fixture(_ name: String) throws -> String {
        let directory = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let url = directory.appendingPathComponent("interchange").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
