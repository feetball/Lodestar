import LodestarKit
import XCTest
@testable import AppCore

/// The mosaic planner of the Aim screen: what a request turns into, and the words for what cannot be planned.
final class AimMosaicPlannerTests: XCTestCase {
    private enum Fixture {
        static let catalog = Result { try Catalog.loadBundled() }
        /// The MPC line of C/2023 A3 (Tsuchinshan-ATLAS), copied from the LodestarKit test data.
        static let cometLine =
            "    CK23A030  2024 09 27.8337  0.391312  1.000180  308.5842   21.6759  139.0991  20261017   6.5  3.2  C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2026-O98"
    }

    private struct WrongPlanKind: Error {}

    private let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    /// 2026-07-16 05:00 UTC, 23:00 in Colorado.
    private let july = Date(timeIntervalSince1970: 1_784_178_000)
    private let sixHours: TimeInterval = 21_600

    // MARK: Helpers

    private func lens(_ focalLength: Double) -> FrameSize {
        FieldOfView.of(sensor: .fullFrame, focalLength: focalLength)
    }

    private func object(_ id: String) throws -> CelestialObject {
        let catalog = try Fixture.catalog.get()
        return try XCTUnwrap(catalog.object(id: id), id)
    }

    private func atlasComet() throws -> CelestialObject {
        CelestialObject(smallBody: try CometElementsParser.parseLine(Fixture.cometLine))
    }

    private func request(_ source: AimMosaicRequest.Source, overlap: Double = 0.25, orientation: MosaicOrientation? = nil,
                         frame: FrameSize? = nil, observer: Observer? = nil, date: Date? = nil) -> AimMosaicRequest {
        AimMosaicRequest(source: source, overlap: overlap, orientation: orientation, frame: frame ?? lens(50),
                         observer: observer ?? boulder, date: date ?? july)
    }

    private func planned(_ request: AimMosaicRequest, file: StaticString = #filePath,
                         line: UInt = #line) throws -> AimMosaicPlanResult {
        switch AimMosaicPlanner.plan(for: request) {
        case .success(let result):
            return result
        case .failure(let problem):
            XCTFail("Planning failed: \(problem.message)", file: file, line: line)
            throw problem
        }
    }

    private func failureMessage(_ request: AimMosaicRequest, file: StaticString = #filePath,
                                line: UInt = #line) -> String? {
        switch AimMosaicPlanner.plan(for: request) {
        case .success:
            XCTFail("Expected the planning to fail", file: file, line: line)
            return nil
        case .failure(let problem):
            return problem.message
        }
    }

    private func equatorialCentre(of plan: MosaicPlan, file: StaticString = #filePath,
                                  line: UInt = #line) throws -> EquatorialCoordinate {
        guard case let .equatorial(center, _, _, _) = plan.region else {
            XCTFail("The plan is not equatorial", file: file, line: line)
            throw WrongPlanKind()
        }
        return center
    }

    private func equatorialPlan(declination: Double, width: Double, height: Double, focalLength: Double) throws -> MosaicPlan {
        let region = MosaicRegion.equatorial(center: EquatorialCoordinate(rightAscensionHours: 5, declination: declination),
                                             width: width, height: height)
        return try MosaicPlanner.plan(region: region, frame: lens(focalLength))
    }

    private let planetsText = "The Sun, the Moon and the planets move across the sky, so a mosaic cannot be planned for them."
    private let noSizeTail = "has no known angular size. Choose a nebula, galaxy or large cluster, or use a custom size."

    // MARK: Objects

    func testAnObjectThatFitsInOneFrameIsOnePanelNamedAfterIt() throws {
        let m31 = try object("dso.M31")
        let result = try planned(request(.target(m31), frame: lens(200)))
        XCTAssertEqual(result.title, m31.name)
        XCTAssertEqual(result.plan.panelCount, 1)
        XCTAssertEqual(result.plan.kind, .equatorial)
        XCTAssertEqual(result.plan.overlap, 0.25)
        XCTAssertEqual(result.plan.frame, lens(200))
        XCTAssertTrue(result.plan.warnings.isEmpty)
        XCTAssertEqual(result.recommendedOrientation, .landscape)
        XCTAssertEqual(result.plan.orientation, .landscape)
        XCTAssertEqual(AimMosaicPlanner.gridText(result.plan), "1 panel")
    }

    func testTheAreaOfAnObjectIsItsCatalogSizeWithTheFitMargin() throws {
        let m31 = try object("dso.M31")
        let result = try planned(request(.target(m31), frame: lens(200)))
        guard case let .equatorial(center, width, height, positionAngle) = result.plan.region else {
            return XCTFail("The plan is not equatorial")
        }
        let position = try XCTUnwrap(m31.j2000)
        let size = try XCTUnwrap(m31.angularSize)
        let minor = try XCTUnwrap(size.minorArcminutes)
        let angle = try XCTUnwrap(size.positionAngle)
        XCTAssertEqual(AimMosaicPlanner.fitMargin, 0.2)
        XCTAssertEqual(center.angularSeparation(to: position), 0.0, accuracy: 1e-9)
        XCTAssertEqual(width, size.majorArcminutes / 60 * 1.2, accuracy: 1e-9)
        XCTAssertEqual(height, minor / 60 * 1.2, accuracy: 1e-9)
        XCTAssertEqual(positionAngle, AstroMath.normalizeDegrees(angle - 90), accuracy: 1e-9)
    }

    func testALongLensNeedsTwoPanelsForTheSameObject() throws {
        let m31 = try object("dso.M31")
        let result = try planned(request(.target(m31), frame: lens(600)))
        XCTAssertEqual(result.plan.panelCount, 2)
        XCTAssertEqual(result.plan.rows, 1)
        XCTAssertEqual(result.plan.columns, 2)
        XCTAssertEqual(AimMosaicPlanner.gridText(result.plan), "1 row \u{00D7} 2 columns \u{00B7} 2 panels")
        XCTAssertEqual(result.recommendedOrientation, .landscape)
        XCTAssertEqual(result.plan.orientation, .landscape)
    }

    func testAChosenOrientationIsUsedAndTheRecommendationIsStillReported() throws {
        let m31 = try object("dso.M31")
        let result = try planned(request(.target(m31), orientation: .portrait, frame: lens(600)))
        XCTAssertEqual(result.plan.orientation, .portrait)
        XCTAssertEqual(result.plan.frame, lens(600).rotated)
        XCTAssertEqual(result.recommendedOrientation, .landscape)
    }

    func testAnObjectWithoutASizeCannotBePlanned() throws {
        let sirius = try object("star.hip32349")
        let message = try XCTUnwrap(failureMessage(request(.target(sirius))))
        XCTAssertTrue(message.contains(noSizeTail), message)
    }

    func testTheMoonAndThePlanetsCannotBePlanned() throws {
        XCTAssertEqual(failureMessage(request(.target(try object("planet.mars")))), planetsText)
        XCTAssertEqual(failureMessage(request(.target(try object("moon")))), planetsText)
        XCTAssertEqual(failureMessage(request(.target(try object("sun")))), planetsText)
    }

    func testACometCannotBePlannedAsATarget() throws {
        // Only the fact that it fails is asserted: see the report about the words plan(for:) uses for it.
        XCTAssertNotNil(failureMessage(request(.target(try atlasComet()))))
    }

    // MARK: Orientation

    func testATallAreaRecommendsPortraitAndAWideLensKeepsItInOnePanel() throws {
        let center = HorizontalCoordinate(azimuth: 180, altitude: 45)
        let tall = AimMosaicRequest.Source.custom(width: 10, height: 60, center: center)
        let automatic = try planned(request(tall, frame: lens(24)))
        XCTAssertEqual(automatic.recommendedOrientation, .portrait)
        XCTAssertEqual(automatic.plan.orientation, .portrait)
        XCTAssertEqual(automatic.plan.panelCount, 1)

        let forced = try planned(request(tall, orientation: .landscape, frame: lens(24)))
        XCTAssertEqual(forced.plan.orientation, .landscape)
        XCTAssertEqual(forced.recommendedOrientation, .portrait)
        XCTAssertGreaterThan(forced.plan.panelCount, 1)
    }

    // MARK: Custom areas

    func testACustomAreaHasTheRequestedSizeAndATitleWithIt() throws {
        let center = HorizontalCoordinate(azimuth: 135, altitude: 40)
        let result = try planned(request(.custom(width: 60, height: 40, center: center), frame: lens(24)))
        XCTAssertEqual(result.title, "Custom 60\u{00B0} \u{00D7} 40\u{00B0}")
        guard case let .equatorial(_, width, height, positionAngle) = result.plan.region else {
            return XCTFail("The plan is not equatorial")
        }
        XCTAssertEqual(width, 60.0)
        XCTAssertEqual(height, 40.0)
        XCTAssertEqual(positionAngle, 0.0)
    }

    func testTheSizeInTheTitleIsRoundedToWholeDegrees() throws {
        let center = HorizontalCoordinate(azimuth: 135, altitude: 40)
        let result = try planned(request(.custom(width: 29.6, height: 20.4, center: center), frame: lens(24)))
        XCTAssertEqual(result.title, "Custom 30\u{00B0} \u{00D7} 20\u{00B0}")
    }

    func testACustomAreaIsCentredOnThePlaceTheCameraPointedAt() throws {
        let pointed = HorizontalCoordinate(azimuth: 135, altitude: 40)
        let result = try planned(request(.custom(width: 60, height: 40, center: pointed), frame: lens(24)))
        let centre = try equatorialCentre(of: result.plan)
        let sky = SkyFrame(date: july, observer: boulder)
        let seen = sky.horizontal(j2000: centre, properMotion: nil, refraction: true)
        XCTAssertEqual(AstroMath.normalizeSignedDegrees(seen.azimuth - 135), 0.0, accuracy: 0.01)
        XCTAssertEqual(seen.altitude, 40.0, accuracy: 0.01)
    }

    func testACustomCentreIsTakenAtTheDateOfTheRequest() throws {
        // The documented contract of `AimMosaicRequest.date`: it is the instant the custom centre was taken at.
        let pointed = HorizontalCoordinate(azimuth: 180, altitude: 45)
        let source = AimMosaicRequest.Source.custom(width: 20, height: 20, center: pointed)
        let laterDate = july.addingTimeInterval(sixHours)
        let early = try equatorialCentre(of: try planned(request(source, date: july)).plan)
        let late = try equatorialCentre(of: try planned(request(source, date: laterDate)).plan)

        // Same direction on the screen, six hours apart: the stars have turned a quarter of a circle.
        XCTAssertGreaterThan(early.angularSeparation(to: late), 80.0)

        // Each centre is the pointed direction at its own date ...
        let earlySky = SkyFrame(date: july, observer: boulder)
        let lateSky = SkyFrame(date: laterDate, observer: boulder)
        let earlySeen = earlySky.horizontal(j2000: early, properMotion: nil, refraction: true)
        let lateSeen = lateSky.horizontal(j2000: late, properMotion: nil, refraction: true)
        XCTAssertEqual(earlySeen.angularSeparation(to: pointed), 0.0, accuracy: 0.01)
        XCTAssertEqual(lateSeen.angularSeparation(to: pointed), 0.0, accuracy: 0.01)

        // ... and not at the other one.
        let drifted = lateSky.horizontal(j2000: early, properMotion: nil, refraction: true)
        XCTAssertGreaterThan(drifted.angularSeparation(to: pointed), 40.0)
    }

    func testTheObserversLatitudeDecidesWhichEndOfAnEquatorialPlanIsShotFirst() throws {
        // A tall strip of sky is planned in two rows. The panel that sets first is shot first: in the northern hemisphere
        // that is the southern row, in the southern hemisphere the northern one. Rows count from the north.
        let southern = Observer(location: GeographicLocation(latitude: -40, longitude: 150, elevation: 0))
        let northCentre = HorizontalCoordinate(azimuth: 180, altitude: 45)
        let southCentre = HorizontalCoordinate(azimuth: 0, altitude: 45)
        let north = try planned(request(.custom(width: 10, height: 60, center: northCentre), orientation: .landscape,
                                        frame: lens(24))).plan
        let south = try planned(request(.custom(width: 10, height: 60, center: southCentre), orientation: .landscape,
                                        frame: lens(24), observer: southern)).plan
        XCTAssertGreaterThan(north.rows, 1)
        XCTAssertGreaterThan(south.rows, 1)
        XCTAssertEqual(north.panels[north.shootingOrder[0]].row, north.rows - 1)
        XCTAssertEqual(south.panels[south.shootingOrder[0]].row, 0)
    }

    // MARK: The Milky Way

    func testTheMilkyWayArchIsPlannedAsAHorizontalPanoramaOfTheEngine() throws {
        let result = try planned(request(.milkyWayArch, frame: lens(24)))
        XCTAssertEqual(result.title, "Milky Way arch")
        XCTAssertEqual(result.plan.kind, .horizontal)
        let sky = SkyFrame(date: july, observer: boulder)
        let expected = try XCTUnwrap(MilkyWayPanorama.arch(frame: sky).panoramaRegion())
        XCTAssertEqual(result.plan.region, expected)
        guard case let .horizontal(_, span, low, high) = result.plan.region else {
            return XCTFail("The plan is not horizontal")
        }
        XCTAssertGreaterThan(span, 100.0)
        XCTAssertLessThan(low, high)
        XCTAssertGreaterThan(result.plan.panelCount, 1)
        XCTAssertEqual(result.plan.orientation, result.recommendedOrientation)
    }

    func testTheMilkyWayArchIsWorkedOutAtTheDateOfTheRequest() throws {
        let now = try planned(request(.milkyWayArch, frame: lens(24)))
        let later = try planned(request(.milkyWayArch, frame: lens(24), date: july.addingTimeInterval(3 * 3600)))
        XCTAssertNotEqual(now.plan.region, later.plan.region)
    }

    func testTheMilkyWayLyingAlongTheHorizonCannotBePlanned() {
        // At 27 degrees north the north galactic pole (RA 12h 52m, Dec +27) crosses the zenith at 17:15 UT on 2026-07-16
        // on the meridian of Greenwich: the galactic plane then lies along the horizon, nowhere 5 degrees high.
        let observer = Observer(location: GeographicLocation(latitude: 27.0, longitude: 0, elevation: 0))
        let date = Date(timeIntervalSince1970: 1_784_222_100)
        let message = failureMessage(request(.milkyWayArch, frame: lens(24), observer: observer, date: date))
        XCTAssertEqual(message, "The Milky Way is below the horizon right now.")
    }

    // MARK: Things that cannot be planned

    func testAnOverlapOutsideTenToFiftyPercentIsRefused() throws {
        let m31 = try object("dso.M31")
        for overlap in [0.09, 0.51, 0.0, 1.0, -0.2, Double.nan] {
            XCTAssertEqual(failureMessage(request(.target(m31), overlap: overlap, frame: lens(200))),
                           "The overlap must be between 10% and 50%.", "overlap \(overlap)")
        }
    }

    func testTheOverlapLimitsThemselvesAreAccepted() throws {
        let m31 = try object("dso.M31")
        for overlap in [0.10, 0.50] {
            let result = try planned(request(.target(m31), overlap: overlap, frame: lens(200)))
            XCTAssertEqual(result.plan.overlap, overlap)
        }
    }

    func testALensWithoutAFieldOfViewIsRefused() {
        let center = HorizontalCoordinate(azimuth: 180, altitude: 45)
        let source = AimMosaicRequest.Source.custom(width: 30, height: 20, center: center)
        let empty = FrameSize(horizontal: 0, vertical: 0, diagonal: 0)
        XCTAssertEqual(failureMessage(request(source, frame: empty)),
                       "The lens in Settings has no usable field of view. Check the focal length and sensor.")
        let tooWide = FrameSize(horizontal: 180, vertical: 120, diagonal: 180)
        XCTAssertEqual(failureMessage(request(source, frame: tooWide)),
                       "The lens in Settings has no usable field of view. Check the focal length and sensor.")
    }

    func testALensWithANumberThatIsNotFiniteIsRefused() {
        let center = HorizontalCoordinate(azimuth: 180, altitude: 45)
        let source = AimMosaicRequest.Source.custom(width: 30, height: 20, center: center)
        let broken = FrameSize(horizontal: .nan, vertical: 20, diagonal: 20)
        XCTAssertEqual(failureMessage(request(source, frame: broken)), "This mosaic cannot be planned.")
    }

    func testAnAreaThatIsTooLargeIsRefused() {
        let center = HorizontalCoordinate(azimuth: 180, altitude: 45)
        let tooLarge = "The area is too large to map. Choose a smaller one."
        XCTAssertEqual(failureMessage(request(.custom(width: 400, height: 20, center: center))), tooLarge)
        XCTAssertEqual(failureMessage(request(.custom(width: 30, height: 200, center: center))), tooLarge)
    }

    func testAMosaicOfMoreThanFiveHundredPanelsIsRefusedWithTheLimit() throws {
        let center = HorizontalCoordinate(azimuth: 180, altitude: 45)
        let huge = request(.custom(width: 180, height: 120, center: center), frame: lens(600))
        let message = try XCTUnwrap(failureMessage(huge))
        XCTAssertTrue(message.hasPrefix("This would take "), message)
        XCTAssertTrue(message.hasSuffix(" panels; the limit is 500. Use a wider lens or a smaller area."), message)
    }

    // MARK: Messages

    func testEveryErrorHasWordsForThePerson() throws {
        let tooLarge = "The area is too large to map. Choose a smaller one."
        XCTAssertEqual(AimMosaicPlanner.message(for: .invalidWidth(value: 400)), tooLarge)
        XCTAssertEqual(AimMosaicPlanner.message(for: .invalidHeight(value: 200)), tooLarge)
        XCTAssertEqual(AimMosaicPlanner.message(for: .invalidAzimuthSpan(value: 400)), tooLarge)
        XCTAssertEqual(AimMosaicPlanner.message(for: .invalidAltitudeRange(minimum: -120, maximum: 95)), tooLarge)
        XCTAssertEqual(AimMosaicPlanner.message(for: .invalidFrame(horizontal: 0, vertical: 0)),
                       "The lens in Settings has no usable field of view. Check the focal length and sensor.")
        XCTAssertEqual(AimMosaicPlanner.message(for: .invalidOverlap(value: 0.7)), "The overlap must be between 10% and 50%.")
        XCTAssertEqual(AimMosaicPlanner.message(for: .invalidMargin(value: 3)), "This mosaic cannot be planned.")
        XCTAssertEqual(AimMosaicPlanner.message(for: .invalidLatitude(value: 100)), "This mosaic cannot be planned.")
        XCTAssertEqual(AimMosaicPlanner.message(for: .nonFiniteInput), "This mosaic cannot be planned.")
        XCTAssertEqual(AimMosaicPlanner.message(for: .tooManyPanels(count: 612, limit: 500)),
                       "This would take 612 panels; the limit is 500. Use a wider lens or a smaller area.")
    }

    func testTheWordsForAnObjectWithoutASizeNameTheObject() throws {
        let sirius = try object("star.hip32349")
        XCTAssertEqual(AimMosaicPlanner.message(for: .objectHasNoSize(objectID: sirius.id), object: sirius),
                       "\(sirius.name) \(noSizeTail)")
        XCTAssertEqual(AimMosaicPlanner.message(for: .objectHasNoSize(objectID: "star.x")), "This object \(noSizeTail)")
    }

    func testTheWordsForAMovingObjectDependOnItsKind() throws {
        let mars = try object("planet.mars")
        XCTAssertEqual(AimMosaicPlanner.message(for: .objectNotFixed(objectID: mars.id), object: mars), planetsText)
        XCTAssertEqual(AimMosaicPlanner.message(for: .objectNotFixed(objectID: "planet.mars")), planetsText)

        let atlas = try atlasComet()
        let message = AimMosaicPlanner.message(for: .objectNotFixed(objectID: atlas.id), object: atlas)
        XCTAssertEqual(message, SmallBodyText.mosaicRefusal(for: atlas))
        XCTAssertTrue(message.hasPrefix("Tsuchinshan-ATLAS moves among the stars"), message)
    }

    func testWhyAnObjectCannotBeFitted() throws {
        XCTAssertEqual(AimMosaicPlanner.fitProblem(for: nil), "Choose a target first.")
        XCTAssertNil(AimMosaicPlanner.fitProblem(for: try object("dso.M31")))

        let sirius = try object("star.hip32349")
        XCTAssertEqual(AimMosaicPlanner.fitProblem(for: sirius), "\(sirius.name) \(noSizeTail)")

        let custom = CelestialObject.custom(name: "My field", j2000: EquatorialCoordinate(rightAscension: 150, declination: 10))
        XCTAssertEqual(AimMosaicPlanner.fitProblem(for: custom), "My field \(noSizeTail)")

        XCTAssertEqual(AimMosaicPlanner.fitProblem(for: try object("moon")), planetsText)

        let atlas = try atlasComet()
        XCTAssertEqual(AimMosaicPlanner.fitProblem(for: atlas), SmallBodyText.mosaicRefusal(for: atlas))
    }

    // MARK: Descriptions

    func testTheGridIsDescribedByItsRowsAndColumns() throws {
        XCTAssertEqual(AimMosaicPlanner.gridText(try equatorialPlan(declination: 0, width: 20, height: 15, focalLength: 50)),
                       "1 panel")
        XCTAssertEqual(AimMosaicPlanner.gridText(try equatorialPlan(declination: 0, width: 40, height: 10, focalLength: 50)),
                       "1 row \u{00D7} 2 columns \u{00B7} 2 panels")
        XCTAssertEqual(AimMosaicPlanner.gridText(try equatorialPlan(declination: 0, width: 80, height: 50, focalLength: 50)),
                       "3 rows \u{00D7} 3 columns \u{00B7} 9 panels")
        XCTAssertEqual(AimMosaicPlanner.gridText(try equatorialPlan(declination: 0, width: 10, height: 60, focalLength: 24)),
                       "2 rows \u{00D7} 1 column \u{00B7} 2 panels")
    }

    func testAGridWhoseRowsDifferIsDescribedByItsPanelCount() throws {
        // Near the pole the rows are shorter, so the upper one needs fewer panels.
        let plan = try equatorialPlan(declination: 60, width: 80, height: 50, focalLength: 50)
        XCTAssertEqual(plan.columnsPerRow, [1, 4, 5])
        XCTAssertEqual(AimMosaicPlanner.gridText(plan), "10 panels in 3 rows")
    }

    func testTheWarningsOfAPlanAreExplained() {
        XCTAssertEqual(AimMosaicPlanner.text(for: .tooManyPanels(count: 120)),
                       "120 panels is a lot: shooting takes long and the sky moves meanwhile. A wider lens or a smaller area helps.")
        XCTAssertEqual(AimMosaicPlanner.text(for: .overlapNotMet(coveredFraction: 0.987)),
                       "99% of the area is covered. Raise the overlap or use a wider lens.")
        XCTAssertEqual(AimMosaicPlanner.text(for: .overlapNotMet(coveredFraction: 0.5)),
                       "50% of the area is covered. Raise the overlap or use a wider lens.")
    }

    func testTheOrientationsHaveNames() {
        XCTAssertEqual(AimMosaicPlanner.name(of: .landscape), "Landscape")
        XCTAssertEqual(AimMosaicPlanner.name(of: .portrait), "Portrait")
    }

    func testTheSizeLimitsOfACustomAreaAreTheSliderRanges() {
        XCTAssertEqual(AimMosaicPlanner.customWidthRange, 2.0...180.0)
        XCTAssertEqual(AimMosaicPlanner.customHeightRange, 2.0...120.0)
    }

    // MARK: Requests

    func testRequestsAreEqualOnlyWhenEverythingTheyAskForIsEqual() throws {
        let center = HorizontalCoordinate(azimuth: 180, altitude: 45)
        let source = AimMosaicRequest.Source.custom(width: 30, height: 20, center: center)
        let base = request(source)
        XCTAssertEqual(base, request(source))
        XCTAssertNotEqual(base, request(source, date: july.addingTimeInterval(1)))
        XCTAssertNotEqual(base, request(source, overlap: 0.3))
        XCTAssertNotEqual(base, request(source, orientation: .portrait))
        XCTAssertNotEqual(base, request(source, frame: lens(35)))
        XCTAssertNotEqual(base, request(.milkyWayArch))
        XCTAssertNotEqual(base, request(.custom(width: 31, height: 20, center: center)))
        XCTAssertEqual(AimMosaicRequest.Source.target(try object("dso.M31")), .target(try object("dso.M31")))
        XCTAssertNotEqual(AimMosaicRequest.Source.target(try object("dso.M31")), .target(try object("dso.M42")))
    }

    func testAProblemIsEqualToAProblemWithTheSameWords() {
        XCTAssertEqual(AimMosaicProblem(message: "a"), AimMosaicProblem(message: "a"))
        XCTAssertNotEqual(AimMosaicProblem(message: "a"), AimMosaicProblem(message: "b"))
    }
}
