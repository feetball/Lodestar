import LodestarKit
import XCTest
@testable import AppCore

/// The service that loads the bundled catalog and the small bodies: its loading state, lookups, and the
/// callback that tells the app model the downloaded comets and asteroids have changed.
@MainActor
final class AimCatalogServiceTests: XCTestCase {
    /// The MPC line of C/2023 A3 (Tsuchinshan-ATLAS), copied from the LodestarKit test data. It is not one of the
    /// bundled asteroids, so it stands for a download.
    private let cometLine =
        "    CK23A030  2024 09 27.8337  0.391312  1.000180  308.5842   21.6759  139.0991  20261017   6.5  3.2  C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2026-O98"

    private final class Counter {
        var count = 0
    }

    private func comet() throws -> SmallBody {
        try CometElementsParser.parseLine(cometLine)
    }

    private func countChanges(of service: CatalogService) -> Counter {
        let counter = Counter()
        service.onSmallBodiesChange = { counter.count += 1 }
        return counter
    }

    // MARK: Before the load

    func testAFreshServiceIsIdleAndHasNothing() {
        let service = CatalogService()
        XCTAssertEqual(service.loadState, .idle)
        XCTAssertNil(service.catalog)
        XCTAssertNil(service.object(id: "dso.M31"))
        XCTAssertTrue(service.search("m31", limit: 5).isEmpty)
    }

    func testLoadStatesAreEqualByCaseAndMessage() {
        XCTAssertEqual(CatalogService.LoadState.idle, .idle)
        XCTAssertEqual(CatalogService.LoadState.failed("a"), .failed("a"))
        XCTAssertNotEqual(CatalogService.LoadState.failed("a"), .failed("b"))
        XCTAssertNotEqual(CatalogService.LoadState.loading, .loaded)
    }

    // MARK: Loading

    func testLoadingFillsTheCatalogWithTheBundledObjectsAndAsteroids() async throws {
        let service = CatalogService()
        await service.load()
        XCTAssertEqual(service.loadState, .loaded)
        let catalog = try XCTUnwrap(service.catalog)
        XCTAssertEqual(catalog.constellations.count, 88)
        XCTAssertEqual(service.object(id: "dso.M31")?.id, "dso.M31")
        XCTAssertNil(service.object(id: "dso.NoSuchObject"))
        // The bundled asteroids come with it: Vesta is one of them.
        XCTAssertEqual(service.object(id: "asteroid.4")?.id, "asteroid.4")
        XCTAssertGreaterThan(catalog.smallBodies.count, 100)
    }

    func testSearchFindsObjectsByNameAndHonoursTheLimit() async throws {
        let service = CatalogService()
        await service.load()
        XCTAssertEqual(service.search("m31", limit: 5).first?.object.id, "dso.M31")
        XCTAssertLessThanOrEqual(service.search("m", limit: 3).count, 3)
        XCTAssertEqual(service.search("m31", limit: 1).count, 1)
        XCTAssertTrue(service.search("m31", limit: 0).isEmpty)
        XCTAssertTrue(service.search("zzzzqqqqxxxx", limit: 5).isEmpty)
    }

    func testLoadingAgainKeepsTheLoadedCatalog() async throws {
        let service = CatalogService()
        await service.load()
        let first = try XCTUnwrap(service.catalog)
        await service.load()
        XCTAssertEqual(service.loadState, .loaded)
        XCTAssertTrue(first === service.catalog)
    }

    func testCallersThatArriveWhileALoadIsRunningWaitForIt() async throws {
        let service = CatalogService()
        async let first: Void = service.load()
        async let second: Void = service.load()
        await first
        await second
        XCTAssertEqual(service.loadState, .loaded)
        XCTAssertNotNil(service.catalog)
        XCTAssertNotNil(service.object(id: "dso.M31"))
    }

    // MARK: Downloaded comets and asteroids

    func testBodiesDownloadedBeforeTheLoadAreKeptForIt() async throws {
        let service = CatalogService()
        let changes = countChanges(of: service)
        let body = try comet()
        service.setDownloadedSmallBodies([body])
        // Nothing to replace yet, so nobody is told.
        XCTAssertNil(service.catalog)
        XCTAssertEqual(changes.count, 0)

        await service.load()
        XCTAssertEqual(service.object(id: body.id)?.id, body.id)
        XCTAssertEqual(changes.count, 0)
    }

    func testDownloadedBodiesJoinTheBundledOnesAndTheModelIsTold() async throws {
        let service = CatalogService()
        await service.load()
        let before = try XCTUnwrap(service.catalog)
        XCTAssertNil(service.object(id: try comet().id))
        let changes = countChanges(of: service)

        let body = try comet()
        service.setDownloadedSmallBodies([body])
        let after = try XCTUnwrap(service.catalog)
        XCTAssertFalse(before === after)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(after.smallBodies.count, before.smallBodies.count + 1)
        XCTAssertEqual(service.object(id: body.id)?.id, body.id)
        // The stars and the rest of the sky are the same.
        XCTAssertEqual(service.object(id: "dso.M31"), before.object(id: "dso.M31"))
        XCTAssertEqual(service.loadState, .loaded)
    }

    func testAnEmptyDownloadRemovesTheDownloadedBodiesAgain() async throws {
        let service = CatalogService()
        await service.load()
        let bundled = try XCTUnwrap(service.catalog).smallBodies.count
        let changes = countChanges(of: service)
        let body = try comet()

        service.setDownloadedSmallBodies([body])
        XCTAssertNotNil(service.object(id: body.id))
        service.setDownloadedSmallBodies([])
        XCTAssertNil(service.object(id: body.id))
        XCTAssertEqual(try XCTUnwrap(service.catalog).smallBodies.count, bundled)
        XCTAssertEqual(changes.count, 2)
        XCTAssertNotNil(service.object(id: "asteroid.4"), "the bundled asteroids stay")
    }

    func testADownloadedBodyWithABundledIdentifierIsNotCountedTwice() async throws {
        let service = CatalogService()
        await service.load()
        let before = try XCTUnwrap(service.catalog)
        let vesta = try XCTUnwrap(before.object(id: "asteroid.4")?.smallBody)
        service.setDownloadedSmallBodies([vesta])
        let after = try XCTUnwrap(service.catalog)
        XCTAssertEqual(after.smallBodies.count, before.smallBodies.count)
        XCTAssertEqual(service.object(id: "asteroid.4")?.smallBody, vesta)
    }

    func testEachNewDownloadReplacesThePreviousOne() async throws {
        let service = CatalogService()
        await service.load()
        let bundled = try XCTUnwrap(service.catalog).smallBodies.count
        let body = try comet()
        service.setDownloadedSmallBodies([body])
        service.setDownloadedSmallBodies([body])
        XCTAssertEqual(try XCTUnwrap(service.catalog).smallBodies.count, bundled + 1)
    }
}
