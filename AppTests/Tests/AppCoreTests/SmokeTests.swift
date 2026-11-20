import XCTest
@testable import AppCore

/// Checks that the app's sources are compiled into the package and reachable from the tests.
final class SmokeTests: XCTestCase {
    func testTheAppSourcesAreInThePackage() {
        XCTAssertEqual(OnlineSchedule.transportRetryInterval, 600.0)
        XCTAssertEqual(HelpCategory.allCases.count, 6)
    }
}
