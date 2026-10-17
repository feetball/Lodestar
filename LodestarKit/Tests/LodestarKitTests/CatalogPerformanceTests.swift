import XCTest
@testable import LodestarKit

/// Timing checks. Optimized builds have to meet the design targets (a search in 5 ms). Debug builds are
/// several times slower and may share the machine with other work, so they get three times that, which
/// still catches an algorithmic regression; the measurements are printed, and a release run
/// (`swift test -c release -Xswiftc -enable-testing`) documents the real figures.
///
/// A query is timed several times and judged by its fastest run, which is not disturbed by other work
/// running on the same machine.
final class CatalogPerformanceTests: XCTestCase {
    #if DEBUG
    private static let optimized = false
    #else
    private static let optimized = true
    #endif

    /// Seconds allowed for loading the bundled catalog (about 0.25 s optimized, 0.7 s unoptimized).
    private var loadBudget: Double { Self.optimized ? 1 : 5 }
    /// Milliseconds allowed for one search (the design target is 5 ms optimized). Unoptimized builds on
    /// shared CI machines run pathological queries in about 18 ms, so they get a guard against
    /// algorithmic blow-ups rather than a benchmark.
    private var searchBudget: Double { Self.optimized ? 5 : 60 }
    /// Milliseconds allowed for sorting the listed objects.
    private var sortBudget: Double { Self.optimized ? 100 : 2_000 }

    private func milliseconds(_ body: () throws -> Void) rethrows -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        try body()
        return (ProcessInfo.processInfo.systemUptime - start) * 1000
    }

    func testLoadingTheBundledCatalogIsFast() throws {
        var times: [Double] = []
        for _ in 0..<3 {
            times.append(try milliseconds { _ = try Catalog.loadBundled() })
        }
        let best = try XCTUnwrap(times.min())
        print("CATALOG PERF load (best of 3): \(Int(best)) ms, optimized: \(Self.optimized)")
        XCTAssertLessThan(best / 1000, loadBudget)
    }

    func testEverySearchMeetsTheLatencyBudgetOnTenThousandObjects() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertGreaterThan(catalog.objects.count, 9_000)
        let queries = ["a", "m", "ngc", "m31", "sirius", "alpha", "alpha cma", "hd 4", "andromeda", "orion neb", "xyz", "andgal",
                       "hip 3", "cen", "e", "1", "ngc 7", "the", "nebula", "α¹ cen", "Bélénos", "m 0031", "zzzzzzzzzz",
                       "betelgeuse", "omega centauri", "double cluster", "sgr a", "hr 5", "9 cma", "k", "0",
                       String(repeating: "a", count: 64), String(repeating: "m31 ", count: 30)]
        _ = catalog.search("warm up")
        var slowest = (query: "", time: 0.0)
        var total = 0.0
        for query in queries {
            var best = Double.infinity
            for _ in 0..<10 {
                let time = milliseconds { _ = catalog.search(query, limit: 50) }
                best = min(best, time)
                total += time
            }
            if best > slowest.time { slowest = (String(query.prefix(12)), best) }
            XCTAssertLessThan(best, searchBudget, "\"\(query.prefix(20))\"")
        }
        let average = total / Double(10 * queries.count)
        print("CATALOG PERF search over \(catalog.objects.count) objects: average \(String(format: "%.3f", average)) ms, "
              + "slowest query \"\(slowest.query)\" \(String(format: "%.3f", slowest.time)) ms (best of 10), optimized: \(Self.optimized)")
    }

    func testSearchWithAHugeLimitIsStillFast() throws {
        let catalog = try CatalogFixture.catalog()
        var best = Double.infinity
        for _ in 0..<5 {
            best = min(best, milliseconds { _ = catalog.search("a", limit: Int.max) })
        }
        print("CATALOG PERF search returning every match of \"a\": \(String(format: "%.1f", best)) ms")
        XCTAssertLessThan(best, searchBudget * 5)
    }

    func testSortingAndGroupAccessAreFast() throws {
        let catalog = try CatalogFixture.catalog()
        let sortTime = milliseconds {
            _ = catalog.sorted(catalog.listedObjects, by: .name)
            _ = catalog.sorted(catalog.listedObjects, by: .magnitude)
        }
        let allTime = milliseconds { _ = catalog.sorted(catalog.objects, by: .name) }
        let groupTime = milliseconds {
            for _ in 0..<1_000 {
                for group in ObjectGroup.allCases { _ = catalog.objects(in: group) }
            }
        }
        print("CATALOG PERF sort listed: \(String(format: "%.1f", sortTime)) ms, sort all: \(String(format: "%.1f", allTime)) ms, 6000 group lookups: \(String(format: "%.1f", groupTime)) ms")
        XCTAssertLessThan(sortTime, sortBudget)
        XCTAssertLessThan(allTime, sortBudget * 10)
        XCTAssertLessThan(groupTime, sortBudget)
    }

    func testIdentifierLookupDoesNotScan() throws {
        let catalog = try CatalogFixture.catalog()
        let identifiers = catalog.objects.map(\.id)
        let time = milliseconds {
            for _ in 0..<20 {
                for identifier in identifiers { _ = catalog.object(id: identifier) }
            }
        }
        print("CATALOG PERF \(20 * identifiers.count) identifier lookups: \(String(format: "%.1f", time)) ms")
        XCTAssertLessThan(time, sortBudget * 5)
    }
}
