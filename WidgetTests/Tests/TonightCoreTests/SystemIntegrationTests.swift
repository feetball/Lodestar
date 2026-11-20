import XCTest
@testable import TonightCore

final class SystemIntegrationTests: XCTestCase {
    // MARK: Night mode

    func testAToggleSwitchesNightModeOnWhenItIsNotOnAndOffWhenItIs() {
        XCTAssertTrue(NightModeChange.toggle.resultingIsOn(currentlyOn: false))
        XCTAssertFalse(NightModeChange.toggle.resultingIsOn(currentlyOn: true))
    }

    func testOnAndOffDoNotDependOnTheCurrentState() {
        for current in [false, true] {
            XCTAssertTrue(NightModeChange.on.resultingIsOn(currentlyOn: current))
            XCTAssertFalse(NightModeChange.off.resultingIsOn(currentlyOn: current))
        }
    }

    // MARK: Torch

    func testATapAsksBeforeWhiteLightAndOnlyTheConfirmationTurnsItOn() {
        XCTAssertEqual(TorchLight.red.afterTap, .confirmingWhite)
        XCTAssertEqual(TorchLight.red.afterConfirm, .red)
        XCTAssertEqual(TorchLight.confirmingWhite.afterConfirm, .white)
        XCTAssertEqual(TorchLight.confirmingWhite.afterCancel, .red)
        XCTAssertEqual(TorchLight.confirmingWhite.afterTap, .red)
    }

    func testATapOnWhiteGoesBackToRedAtOnce() {
        XCTAssertEqual(TorchLight.white.afterTap, .red)
        XCTAssertEqual(TorchLight.white.afterCancel, .white)
    }

    // MARK: Commands

    @MainActor
    func testCommandsWaitForTheHandlerAndArriveInOrder() {
        let center = LodestarCommandCenter()
        center.submit(.showTorch)
        center.submit(.aim(objectID: "dso.M31"))
        var received: [LodestarCommand] = []
        center.attach { received.append($0) }
        XCTAssertEqual(received, [.showTorch, .aim(objectID: "dso.M31")])
        center.submit(.nightMode(.toggle))
        XCTAssertEqual(received.last, .nightMode(.toggle))
        XCTAssertEqual(received.count, 3)
    }

    @MainActor
    func testOnlyTheNewestWaitingCommandsAreKept() {
        let center = LodestarCommandCenter()
        for index in 0..<(LodestarCommandCenter.maximumPending + 3) {
            center.submit(.aim(objectID: "object\(index)"))
        }
        var received: [LodestarCommand] = []
        center.attach { received.append($0) }
        XCTAssertEqual(received.count, LodestarCommandCenter.maximumPending)
        XCTAssertEqual(received.first, .aim(objectID: "object3"))
    }

    // MARK: Satellite pass

    private let rise = Date(timeIntervalSince1970: 1_000_000)

    private func timeline() throws -> SatellitePassTimeline {
        try XCTUnwrap(SatellitePassTimeline(
            rise: rise, peak: rise.addingTimeInterval(180), set: rise.addingTimeInterval(360),
            riseAzimuth: 315, peakAzimuth: 45, setAzimuth: 135, peakAltitude: 64))
    }

    func testAPassNeedsMomentsInOrderAndFiniteAngles() {
        XCTAssertNil(SatellitePassTimeline(rise: rise, peak: rise.addingTimeInterval(-1), set: rise.addingTimeInterval(9),
                                           riseAzimuth: 0, peakAzimuth: 0, setAzimuth: 0, peakAltitude: 10))
        XCTAssertNil(SatellitePassTimeline(rise: rise, peak: rise, set: rise.addingTimeInterval(-1),
                                           riseAzimuth: 0, peakAzimuth: 0, setAzimuth: 0, peakAltitude: 10))
        XCTAssertNil(SatellitePassTimeline(rise: rise, peak: rise, set: rise,
                                           riseAzimuth: .nan, peakAzimuth: 0, setAzimuth: 0, peakAltitude: 10))
        XCTAssertNil(SatellitePassTimeline(rise: rise, peak: rise, set: rise,
                                           riseAzimuth: 0, peakAzimuth: 0, setAzimuth: 0, peakAltitude: .infinity))
    }

    func testTheStagesFollowTheRiseThePeakAndTheSet() throws {
        let pass = try timeline()
        XCTAssertEqual(pass.stage(at: rise.addingTimeInterval(-1)), .waiting)
        XCTAssertEqual(pass.stage(at: rise), .risen)
        XCTAssertEqual(pass.stage(at: rise.addingTimeInterval(179)), .risen)
        XCTAssertEqual(pass.stage(at: rise.addingTimeInterval(180)), .peaked)
        XCTAssertEqual(pass.stage(at: rise.addingTimeInterval(359)), .peaked)
        XCTAssertEqual(pass.stage(at: rise.addingTimeInterval(360)), .over)
        XCTAssertLessThan(SatellitePassTimeline.Stage.waiting, .over)
    }

    func testTheNextChangeIsTheNextMilestoneAndNoneAfterThePass() throws {
        let pass = try timeline()
        XCTAssertEqual(pass.nextChange(after: rise.addingTimeInterval(-60)), rise)
        XCTAssertEqual(pass.nextChange(after: rise.addingTimeInterval(10)), rise.addingTimeInterval(180))
        XCTAssertEqual(pass.nextChange(after: rise.addingTimeInterval(200)), rise.addingTimeInterval(360))
        XCTAssertNil(pass.nextChange(after: rise.addingTimeInterval(400)))
    }

    func testTheCountdownRunsToTheRiseThenToThePeakAndThenStops() throws {
        let pass = try timeline()
        XCTAssertEqual(pass.countdownTarget(in: .waiting), rise)
        XCTAssertEqual(pass.countdownTarget(in: .risen), rise.addingTimeInterval(180))
        XCTAssertNil(pass.countdownTarget(in: .peaked))
        XCTAssertNil(pass.countdownTarget(in: .over))
    }

    func testTheLookIsWhereItRisesThenWhereItPeaksThenWhereItSets() throws {
        let pass = try timeline()
        XCTAssertEqual(pass.lookAzimuth(in: .waiting), 315)
        XCTAssertEqual(pass.lookAzimuth(in: .risen), 45)
        XCTAssertEqual(pass.lookAzimuth(in: .peaked), 135)
    }

    func testAPassSurvivesJSON() throws {
        let pass = try timeline()
        let decoded = try JSONDecoder().decode(SatellitePassTimeline.self, from: JSONEncoder().encode(pass))
        XCTAssertEqual(decoded, pass)
    }

    func testTheWordsNameTheStageTheDirectionAndTheHeight() throws {
        XCTAssertEqual(SatellitePassWords.countdownLabel(.waiting), "Rises in")
        XCTAssertEqual(SatellitePassWords.countdownLabel(.risen), "Peak in")
        XCTAssertEqual(SatellitePassWords.direction(45), "NE 45\u{00B0}")
        XCTAssertEqual(SatellitePassWords.direction(-45), "NW 315\u{00B0}")
        XCTAssertEqual(SatellitePassWords.direction(359.7), "N 0\u{00B0}")
        XCTAssertEqual(SatellitePassWords.look(315, in: .waiting), "Look NW 315\u{00B0}")
        XCTAssertEqual(SatellitePassWords.look(135, in: .peaked), "Sets SE 135\u{00B0}")
        XCTAssertEqual(SatellitePassWords.maximum(63.6), "Max 64\u{00B0}")
        let pass = try timeline()
        let spoken = SatellitePassWords.spoken(name: "ISS", timeline: pass, stage: .waiting)
        XCTAssertTrue(spoken.hasPrefix("ISS rises soon in the northwest"), spoken)
        XCTAssertTrue(spoken.contains("64 degrees"), spoken)
        XCTAssertEqual(SatellitePassWords.spoken(name: "ISS", timeline: pass, stage: .over), "The ISS pass is over.")
    }

    // MARK: When is it dark

    func testTheDarkSentenceTellsTheDarknessTheMoonAndTheCore() throws {
        let place = TonightTestSupport.boulder
        let evening = try TonightTestSupport.date(2026, 7, 14, 18, in: place)
        let sentence = DarkTonightWords.sentence(for: place, at: evening)
        XCTAssertTrue(sentence.contains("Darkness"), sentence)
        XCTAssertTrue(sentence.contains("Moon:"), sentence)
        XCTAssertTrue(sentence.contains("Milky Way core"), sentence)
    }

    func testThePolarSummerHasNoFullDarknessAndSaysSo() throws {
        let place = TonightTestSupport.tromso
        let evening = try TonightTestSupport.date(2026, 6, 21, 22, in: place)
        let sentence = DarkTonightWords.sentence(for: place, at: evening)
        XCTAssertTrue(sentence.contains("no full astronomical darkness"), sentence)
    }
}
