import LodestarKit
import XCTest
@testable import AppCore

/// The outlines of the Milky Way as the Aim overlay prepares them: rings with their caps, layers, and the strips an
/// outline that goes all the way round the sky is cut into.
final class AimMilkyWayTests: XCTestCase {
    private enum Fixture {
        static let catalog = Result { try Catalog.loadBundled() }
    }

    private let observer = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    /// 2026-07-16 05:00 UTC, 23:00 in Colorado.
    private let date = Date(timeIntervalSince1970: 1_784_178_000)

    private var frame: SkyFrame { SkyFrame(date: date, observer: observer) }

    // MARK: Helpers

    /// Three vertices `angle` degrees from due north on the horizon, 120 degrees apart round it: a cap of that radius
    /// centred on the direction (0, 1, 0).
    private func triangle(radius angle: Double) -> [Vector3] {
        [0.0, 120.0, 240.0].map { turn in
            Vector3(AstroMath.sinDeg(angle) * AstroMath.cosDeg(turn), AstroMath.cosDeg(angle),
                    AstroMath.sinDeg(angle) * AstroMath.sinDeg(turn))
        }
    }

    /// The direction of a galactic longitude and latitude in the local frame.
    private func direction(longitude: Double, latitude: Double) -> Vector3 {
        let place = CoordinateTransforms.galacticToEquatorialJ2000(GalacticCoordinate(longitude: longitude, latitude: latitude))
        return frame.horizontalVector(j2000UnitVector: place.unitVector)
    }

    /// The galactic coordinates of a local direction.
    private func galactic(_ vector: Vector3) -> GalacticCoordinate {
        let place = EquatorialCoordinate(vector: frame.j2000ToHorizontal.transposed * vector)
        return CoordinateTransforms.equatorialJ2000ToGalactic(place)
    }

    /// The outline of the band of galactic latitudes −10…+10 all the way round the sky: along the top edge from
    /// longitude 5 round to 365, and back along the bottom edge.
    private func bandAllRound() -> [Vector3] {
        let top = stride(from: 5.0, through: 365.0, by: 10.0).map { direction(longitude: $0, latitude: 10) }
        let bottom = stride(from: 365.0, through: 5.0, by: -10.0).map { direction(longitude: $0, latitude: -10) }
        return top + bottom
    }

    private func band(level: Int = 3, polygons: [[Vector3]], holes: [[Vector3]] = []) -> SkySnapshot.MilkyWayBand {
        SkySnapshot.MilkyWayBand(level: level, polygons: polygons, holes: holes)
    }

    // MARK: Rings

    func testARingKnowsItsCentreAndTheAngleToItsFarthestVertex() throws {
        let ring = try XCTUnwrap(AimMilkyWayRing(vertices: triangle(radius: 50)))
        XCTAssertEqual(ring.vertices.count, 3)
        XCTAssertEqual(ring.center.angle(to: Vector3(0, 1, 0)), 0.0, accuracy: 1e-9)
        XCTAssertEqual(ring.center.length, 1.0, accuracy: 1e-12)
        XCTAssertEqual(ring.radius, 50.0, accuracy: 1e-9)
    }

    func testARingThatIsNotWiderThanSixtyDegreesIsAccepted() throws {
        XCTAssertEqual(AimMilkyWayRing.maximumRadius, 60.0)
        let ring = try XCTUnwrap(AimMilkyWayRing(vertices: triangle(radius: 59.5)))
        XCTAssertEqual(ring.radius, 59.5, accuracy: 1e-9)
    }

    func testARingWiderThanSixtyDegreesIsRefused() {
        XCTAssertNil(AimMilkyWayRing(vertices: triangle(radius: 60.5)))
        XCTAssertNil(AimMilkyWayRing(vertices: triangle(radius: 90)))
    }

    func testARingNeedsThreeVertices() {
        XCTAssertNil(AimMilkyWayRing(vertices: []))
        XCTAssertNil(AimMilkyWayRing(vertices: [Vector3(0, 1, 0)]))
        XCTAssertNil(AimMilkyWayRing(vertices: [Vector3(0, 1, 0), Vector3(0, 0, 1)]))
    }

    func testARingWhoseVerticesCancelOutHasNoCentre() {
        let square = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, -1, 0)]
        XCTAssertNil(AimMilkyWayRing(vertices: square))
    }

    // MARK: Layers

    func testASmallBandBecomesOneLayerWithOneRing() throws {
        let layers = AimMilkyWayLayer.layers(from: [band(polygons: [triangle(radius: 20)])], frame: frame)
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].rings.count, 1)
        XCTAssertEqual(try XCTUnwrap(layers[0].rings.first).radius, 20.0, accuracy: 1e-9)
    }

    func testThePolygonsOfABandComeBeforeItsHoles() {
        let bands = [band(polygons: [triangle(radius: 30), triangle(radius: 25)], holes: [triangle(radius: 10)])]
        let layers = AimMilkyWayLayer.layers(from: bands, frame: frame)
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].rings.map { ($0.radius * 10).rounded() / 10 }, [30.0, 25.0, 10.0])
    }

    func testTheBandsKeepTheirOrder() {
        let bands = [band(level: 1, polygons: [triangle(radius: 40)]), band(level: 2, polygons: [triangle(radius: 20)])]
        let layers = AimMilkyWayLayer.layers(from: bands, frame: frame)
        XCTAssertEqual(layers.map { $0.rings.count }, [1, 1])
        XCTAssertEqual(layers.map { ($0.rings[0].radius).rounded() }, [40.0, 20.0])
    }

    func testABandThatCannotBePreparedIsLeftOutAsAWhole() {
        let broken: [Vector3] = [Vector3(0, 1, 0), Vector3(0, 0, 1)]
        let bands = [
            band(level: 1, polygons: [broken]),
            band(level: 2, polygons: [triangle(radius: 20)]),
            // A good polygon is not drawn without its hole: the hole would otherwise be filled on its own.
            band(level: 3, polygons: [triangle(radius: 30)], holes: [broken]),
            band(level: 4, polygons: []),
        ]
        let layers = AimMilkyWayLayer.layers(from: bands, frame: frame)
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].rings.count, 1)
        XCTAssertEqual(layers[0].rings[0].radius, 20.0, accuracy: 1e-9)
    }

    func testAnOutlineAllRoundTheSkyIsCutIntoStripsThatEachFit() {
        let layers = AimMilkyWayLayer.layers(from: [band(polygons: [bandAllRound()])], frame: frame)
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].rings.count, 7)
        for ring in layers[0].rings {
            XCTAssertLessThanOrEqual(ring.radius, AimMilkyWayRing.maximumRadius)
            XCTAssertGreaterThanOrEqual(ring.vertices.count, 3)
        }
    }

    func testTheRealMilkyWayYieldsRingsThatAllFit() throws {
        let catalog = try Fixture.catalog.get()
        let snapshot = SkySnapshotBuilder.build(catalog: catalog, observer: observer, date: date,
                                                options: SkySnapshotOptions(), target: nil)
        let layers = AimMilkyWayLayer.layers(from: snapshot.milkyWay, frame: snapshot.frame)
        XCTAssertFalse(layers.isEmpty)
        XCTAssertLessThanOrEqual(layers.count, snapshot.milkyWay.count)
        for layer in layers {
            XCTAssertFalse(layer.rings.isEmpty)
            for ring in layer.rings {
                XCTAssertGreaterThanOrEqual(ring.vertices.count, 3)
                XCTAssertLessThanOrEqual(ring.radius, AimMilkyWayRing.maximumRadius)
                XCTAssertEqual(ring.center.length, 1.0, accuracy: 1e-9)
            }
        }
    }

    // MARK: Strips

    func testTheStripsAreSixtyDegreesOfGalacticLongitudeWide() {
        XCTAssertEqual(AimGalacticStrips.width, 60.0)
    }

    func testABandAllRoundTheSkyGivesOneStripPerSixtyDegreesOfLongitude() throws {
        let pieces = AimGalacticStrips.pieces(of: bandAllRound(), frame: frame)
        // Longitudes 5…365 are cut at 0, 60, … 360: six whole strips and a sliver of 5 degrees at the end.
        XCTAssertEqual(pieces.count, 7)
        let starts: [Double] = [0, 60, 120, 180, 240, 300, 360]
        for (piece, start) in zip(pieces, starts) {
            XCTAssertGreaterThanOrEqual(piece.count, 3)
            for vertex in piece {
                XCTAssertEqual(vertex.length, 1.0, accuracy: 1e-9)
                let place = galactic(vertex)
                // Inside the strip (the aberration the local frame carries moves a vertex by a few thousandths of a degree).
                XCTAssertLessThanOrEqual(abs(AstroMath.normalizeSignedDegrees(place.longitude - (start + 30))), 30.1,
                                         "strip from \(start): longitude \(place.longitude)")
                XCTAssertLessThanOrEqual(abs(place.latitude), 10.1, "strip from \(start): latitude \(place.latitude)")
            }
        }
    }

    func testTheStripsTogetherCoverTheWholeBand() {
        // Every vertex of the strips is a vertex of the band's edge or a point on a cut. Sampled at the cuts: the
        // strip that ends at longitude 120 and the strip that starts there both have vertices at ±10 degrees there.
        let pieces = AimGalacticStrips.pieces(of: bandAllRound(), frame: frame)
        let cutLatitudes = pieces.flatMap { $0 }.map { galactic($0) }
            .filter { abs(AstroMath.normalizeSignedDegrees($0.longitude - 120)) < 0.1 }
            .map { $0.latitude }
        XCTAssertTrue(cutLatitudes.contains { abs($0 - 10) < 0.1 })
        XCTAssertTrue(cutLatitudes.contains { abs($0 + 10) < 0.1 })
    }

    func testAnOutlineWithFewerThanThreeVerticesGivesNoStrips() {
        XCTAssertTrue(AimGalacticStrips.pieces(of: [], frame: frame).isEmpty)
        XCTAssertTrue(AimGalacticStrips.pieces(of: [Vector3(0, 1, 0), Vector3(0, 0, 1)], frame: frame).isEmpty)
    }

    func testAnOutlineThatWindsMoreThanFourTimesRoundGivesNoStrips() {
        // 181 vertices 10 degrees of longitude apart wind five times round the galactic equator.
        let spiral = (0...180).map { direction(longitude: Double($0) * 10, latitude: 0) }
        XCTAssertTrue(AimGalacticStrips.pieces(of: spiral, frame: frame).isEmpty)
    }

    func testAnOutlineThatWindsTwiceRoundIsStillCut() {
        let twice = (0...72).map { direction(longitude: Double($0) * 10, latitude: Double($0 % 2) * 4 - 2) }
        let pieces = AimGalacticStrips.pieces(of: twice, frame: frame)
        XCTAssertFalse(pieces.isEmpty)
    }
}
