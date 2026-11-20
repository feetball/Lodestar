import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `ObjectMoonGeometry`, `ObjectMoonAssessment` and `ObjectMoonText` (Features/Objects/ObjectMoon.swift): where the Moon is
/// relative to an object, what that does to a shot through the user's filter, and the words for it.
final class ObjectsMoonTests: XCTestCase {
    private let dot = "\u{00B7}"

    // MARK: The geometry

    func testTheGeometryIsWhatTheEngineSaysAtThatInstant() {
        let denver = Observer(location: GeographicLocation(latitude: 40, longitude: -105, elevation: 1600))
        let object = CelestialObject.custom(name: "Spot", j2000: EquatorialCoordinate(rightAscension: 100, declination: 20))
        let date = Date(timeIntervalSince1970: 1_792_551_600)
        let geometry = ObjectMoonGeometry(of: object, observer: denver, at: date)
        let frame = SkyFrame(date: date, observer: denver)
        let moon = frame.horizontal(of: .moon, refraction: false)
        XCTAssertEqual(geometry.moonAltitude, moon.altitude, accuracy: 1e-9)
        XCTAssertEqual(geometry.separation, frame.horizontal(of: object, refraction: false).angularSeparation(to: moon),
                       accuracy: 1e-9)
        XCTAssertEqual(geometry.illuminatedFraction, frame.state(of: .moon).illuminatedFraction ?? 0, accuracy: 1e-12)
    }

    func testAssessingAGeometryJudgesItWithAndWithoutTheFilter() {
        // A bright Moon close to the object, well up: severe without a filter.
        let close = ObjectMoonGeometry(moonAltitude: 40, separation: 10, illuminatedFraction: 0.95)
        let plain = close.assess(filter: .none, kind: .galaxy)
        XCTAssertEqual(plain.level, .severe)
        XCTAssertEqual(plain.broadbandLevel, .severe)
        XCTAssertFalse(plain.isRelaxed)
        // A narrowband filter relaxes the level for an emission nebula, and the broadband level is still the unfiltered one.
        let narrow = close.assess(filter: .narrowband, kind: .emissionNebula)
        XCTAssertEqual(narrow.broadbandLevel, .severe)
        XCTAssertNotEqual(narrow.level, .severe)
        XCTAssertTrue(narrow.isRelaxed)
    }

    func testAMoonBelowTheHorizonIsDownForEveryFilter() {
        let down = ObjectMoonGeometry(moonAltitude: -10, separation: 10, illuminatedFraction: 1)
        for filter in ImagingFilter.allCases {
            let assessment = down.assess(filter: filter, kind: .emissionNebula)
            XCTAssertEqual(assessment.level, .moonDown, "\(filter)")
            XCTAssertFalse(assessment.isRelaxed)
        }
    }

    // MARK: The words

    private func assessment(_ level: MoonImpact.Level, broadband: MoonImpact.Level? = nil) -> ObjectMoonAssessment {
        ObjectMoonAssessment(level: level, broadbandLevel: broadband ?? level)
    }

    func testTheFilterIsNamedAsItReadsInAnAdvice() {
        XCTAssertEqual(ObjectMoonText.filterName(.none), "")
        XCTAssertEqual(ObjectMoonText.filterName(.lightPollution), "light-pollution")
        XCTAssertEqual(ObjectMoonText.filterName(.dualNarrowband), "dual narrowband")
        XCTAssertEqual(ObjectMoonText.filterName(.narrowband), "narrowband")
    }

    func testTheAdviceSaysWhatTheMoonDoes() {
        XCTAssertEqual(ObjectMoonText.advice(assessment(.moonDown), filter: .none), "The Moon is down, so the sky stays dark.")
        XCTAssertEqual(ObjectMoonText.advice(assessment(.minor), filter: .none), "The Moon has little effect on this target.")
        XCTAssertEqual(ObjectMoonText.advice(assessment(.moderate), filter: .none),
                       "Moonlight will brighten the sky around this target.")
        XCTAssertEqual(ObjectMoonText.advice(assessment(.severe), filter: .none),
                       "A bright Moon close by will wash out faint detail.")
    }

    func testTheAdviceSaysWhatAFilterAchieved() {
        XCTAssertEqual(ObjectMoonText.advice(assessment(.minor, broadband: .severe), filter: .narrowband),
                       "Severe \(dot) fine with your narrowband filter")
        XCTAssertEqual(ObjectMoonText.advice(assessment(.moderate, broadband: .severe), filter: .dualNarrowband),
                       "Severe \(dot) manageable with your dual narrowband filter")
        XCTAssertEqual(ObjectMoonText.advice(assessment(.minor, broadband: .moderate), filter: .lightPollution),
                       "Moderate \(dot) fine with your light-pollution filter")
        XCTAssertEqual(ObjectMoonText.advice(assessment(.moonDown, broadband: .minor), filter: .narrowband),
                       "Minor \(dot) fine with your narrowband filter")
    }

    func testTheChipIsShort() {
        XCTAssertEqual(ObjectMoonText.chip(assessment(.moonDown)), "Moon down")
        XCTAssertEqual(ObjectMoonText.chip(assessment(.minor)), "Moon: minor")
        XCTAssertEqual(ObjectMoonText.chip(assessment(.moderate)), "Moon: moderate")
        XCTAssertEqual(ObjectMoonText.chip(assessment(.severe)), "Moon: severe")
        XCTAssertEqual(ObjectMoonText.chip(assessment(.minor, broadband: .severe)), "Moon: fine with your filter")
        XCTAssertEqual(ObjectMoonText.chip(assessment(.severe, broadband: .severe)), "Moon: severe")
        XCTAssertEqual(ObjectMoonText.chip(assessment(.moderate, broadband: .severe)), "Moon: manageable with your filter")
    }

    func testAnAssessmentIsRelaxedOnlyWhenTheFilterChangedTheLevel() {
        XCTAssertFalse(assessment(.moderate).isRelaxed)
        XCTAssertTrue(assessment(.minor, broadband: .moderate).isRelaxed)
    }
}
