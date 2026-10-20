import Foundation
import XCTest
@testable import AppCore

/// `NotificationObservations`: block observers that are removed when their owner is released. Every test posts on a
/// `NotificationCenter` of its own, so nothing leaves the test.
final class SettingsNotificationObservationsTests: XCTestCase {
    /// Collects what the handlers saw. Handlers run on the posting thread, so access is locked.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []

        func record(_ entry: String) {
            lock.lock()
            entries.append(entry)
            lock.unlock()
        }

        var values: [String] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }

        var count: Int { values.count }
    }

    private let ping = Notification.Name("SettingsNotificationObservationsTests.ping")
    private let pong = Notification.Name("SettingsNotificationObservationsTests.pong")

    func testTheHandlerRunsOncePerMatchingNotification() {
        let center = NotificationCenter()
        let observations = NotificationObservations(center: center)
        defer { withExtendedLifetime(observations) {} }
        let recorder = Recorder()
        observations.observe(ping) { _ in recorder.record("ping") }

        XCTAssertEqual(recorder.count, 0)
        center.post(name: ping, object: nil)
        XCTAssertEqual(recorder.count, 1)
        center.post(name: ping, object: nil)
        center.post(name: ping, object: nil)
        XCTAssertEqual(recorder.values, ["ping", "ping", "ping"])
    }

    func testNotificationsWithAnotherNameAreNotDelivered() {
        let center = NotificationCenter()
        let observations = NotificationObservations(center: center)
        defer { withExtendedLifetime(observations) {} }
        let recorder = Recorder()
        observations.observe(ping) { _ in recorder.record("ping") }

        center.post(name: pong, object: nil)
        XCTAssertEqual(recorder.count, 0)
    }

    func testTheHandlerReceivesTheNotification() {
        let center = NotificationCenter()
        let observations = NotificationObservations(center: center)
        defer { withExtendedLifetime(observations) {} }
        let recorder = Recorder()
        observations.observe(ping) { notification in
            recorder.record("\(notification.name.rawValue)|\(notification.userInfo?["value"] as? Int ?? -1)")
        }

        center.post(name: ping, object: nil, userInfo: ["value": 7])
        XCTAssertEqual(recorder.values, ["\(ping.rawValue)|7"])
    }

    func testObservingOneSenderIgnoresTheOthers() {
        let center = NotificationCenter()
        let observations = NotificationObservations(center: center)
        defer { withExtendedLifetime(observations) {} }
        let recorder = Recorder()
        let sender = NSObject()
        observations.observe(ping, object: sender) { _ in recorder.record("sender") }

        center.post(name: ping, object: NSObject())
        center.post(name: ping, object: nil)
        XCTAssertEqual(recorder.count, 0)
        center.post(name: ping, object: sender)
        XCTAssertEqual(recorder.values, ["sender"])
    }

    func testWithoutASenderTheHandlerHearsEverySender() {
        let center = NotificationCenter()
        let observations = NotificationObservations(center: center)
        defer { withExtendedLifetime(observations) {} }
        let recorder = Recorder()
        observations.observe(ping) { _ in recorder.record("any") }

        center.post(name: ping, object: NSObject())
        center.post(name: ping, object: nil)
        XCTAssertEqual(recorder.count, 2)
    }

    func testSeveralObservationsAreAllKept() {
        let center = NotificationCenter()
        let observations = NotificationObservations(center: center)
        defer { withExtendedLifetime(observations) {} }
        let recorder = Recorder()
        observations.observe(ping) { _ in recorder.record("first") }
        observations.observe(ping) { _ in recorder.record("second") }
        observations.observe(pong) { _ in recorder.record("third") }

        center.post(name: ping, object: nil)
        XCTAssertEqual(Set(recorder.values), ["first", "second"])
        XCTAssertEqual(recorder.count, 2)
        center.post(name: pong, object: nil)
        XCTAssertEqual(recorder.count, 3)
        XCTAssertEqual(recorder.values.last, "third")
    }

    func testReleasingTheOwnerRemovesEveryObserver() {
        let center = NotificationCenter()
        let recorder = Recorder()
        var observations: NotificationObservations? = NotificationObservations(center: center)
        observations?.observe(ping) { _ in recorder.record("ping") }
        observations?.observe(pong) { _ in recorder.record("pong") }

        center.post(name: ping, object: nil)
        XCTAssertEqual(recorder.count, 1)

        observations = nil
        center.post(name: ping, object: nil)
        center.post(name: pong, object: nil)
        XCTAssertEqual(recorder.count, 1)
    }

    func testReleasingOneOwnerLeavesTheObserversOfAnotherOwner() {
        let center = NotificationCenter()
        let recorder = Recorder()
        var first: NotificationObservations? = NotificationObservations(center: center)
        let second = NotificationObservations(center: center)
        first?.observe(ping) { _ in recorder.record("first") }
        second.observe(ping) { _ in recorder.record("second") }

        first = nil
        center.post(name: ping, object: nil)
        XCTAssertEqual(recorder.values, ["second"])
        withExtendedLifetime(second) {}
    }

    func testAnOwnerWithoutObserversCanBeReleased() {
        var observations: NotificationObservations? = NotificationObservations(center: NotificationCenter())
        XCTAssertNotNil(observations)
        observations = nil
        XCTAssertNil(observations)
    }

    func testObservationsOnOneCenterDoNotHearAnother() {
        let center = NotificationCenter()
        let other = NotificationCenter()
        let observations = NotificationObservations(center: center)
        defer { withExtendedLifetime(observations) {} }
        let recorder = Recorder()
        observations.observe(ping) { _ in recorder.record("ping") }

        other.post(name: ping, object: nil)
        XCTAssertEqual(recorder.count, 0)
        center.post(name: ping, object: nil)
        XCTAssertEqual(recorder.count, 1)
    }
}
