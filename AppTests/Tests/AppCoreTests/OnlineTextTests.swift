import Foundation
import XCTest
@testable import AppCore

/// The words of Settings > Online Data.
final class OnlineTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_300_000)

    private func ago(_ seconds: TimeInterval) -> String {
        OnlineText.since(now.addingTimeInterval(-seconds), now: now)
    }

    // MARK: Since

    func testNeverWithoutADate() {
        XCTAssertEqual(OnlineText.since(nil, now: now), "Never")
        XCTAssertEqual(OnlineText.never, "Never")
    }

    func testUnderAMinuteIsJustNow() {
        XCTAssertEqual(ago(0), "Just now")
        XCTAssertEqual(ago(59), "Just now")
        XCTAssertEqual(ago(59.9), "Just now")
    }

    func testADateInTheFutureIsJustNow() {
        XCTAssertEqual(ago(-1), "Just now")
        XCTAssertEqual(ago(-86_400), "Just now")
    }

    func testMinutes() {
        XCTAssertEqual(ago(60), "1 min ago")
        XCTAssertEqual(ago(119), "1 min ago")
        XCTAssertEqual(ago(5 * 60), "5 min ago")
        XCTAssertEqual(ago(59 * 60), "59 min ago")
        XCTAssertEqual(ago(60 * 60 - 1), "59 min ago")
    }

    func testHours() {
        XCTAssertEqual(ago(60 * 60), "1 h ago")
        XCTAssertEqual(ago(2 * 3600 + 59 * 60), "2 h ago")
        XCTAssertEqual(ago(12 * 3600), "12 h ago")
        XCTAssertEqual(ago(47 * 3600 + 59 * 60), "47 h ago")
    }

    func testDays() {
        XCTAssertEqual(ago(48 * 3600), "2 days ago")
        XCTAssertEqual(ago(71 * 3600 + 59 * 60), "2 days ago")
        XCTAssertEqual(ago(72 * 3600), "3 days ago")
        XCTAssertEqual(ago(10 * 86_400), "10 days ago")
    }

    // MARK: Next update

    func testTheNextUpdateSentence() {
        XCTAssertEqual(OnlineText.nextUpdate("16:30"), "Next update possible after 16:30.")
        XCTAssertEqual(OnlineText.nextUpdate(""), "Next update possible after .")
    }

    // MARK: Fixed texts

    func testTheLabels() {
        XCTAssertEqual(OnlineText.sectionTitle, "Online Data")
        XCTAssertEqual(OnlineText.firstTimeTitle, "Online data is optional")
        XCTAssertEqual(OnlineText.firstTimeConfirm, "Turn on")
        XCTAssertEqual(OnlineText.firstTimeCancel, "Not now")
        XCTAssertEqual(OnlineText.updateNow, "Update now")
        XCTAssertEqual(OnlineText.updating, "Updating\u{2026}")
    }

    func testTheIntroSaysEverythingIsOffAndOptional() {
        XCTAssertTrue(OnlineText.intro.hasPrefix("Lodestar works fully offline."))
        XCTAssertTrue(OnlineText.intro.contains("Everything is off until you switch it on"))
    }

    func testTheFooterPromisesDeletingKeepingAndNoBackgroundWork() {
        XCTAssertTrue(OnlineText.footer.contains("Switching a feed off deletes what it downloaded."))
        XCTAssertTrue(OnlineText.footer.contains("A failed download keeps the data you already have."))
        XCTAssertTrue(OnlineText.footer.contains("Nothing runs in the background"))
    }

    func testTheFirstTimeExplanationNamesWhatLeavesThePhone() {
        let body = OnlineText.firstTimeBody
        XCTAssertTrue(body.contains("HTTPS request"))
        XCTAssertTrue(body.contains("IP address"))
        XCTAssertTrue(body.contains("name and version"))
        XCTAssertTrue(body.contains("Only the cloud forecast also sends your location, rounded to about 10 km."))
        XCTAssertTrue(body.contains("Switching a feed off deletes what it downloaded."))
    }

    // MARK: Per feed

    func testEveryFeedHasADistinctPurpose() {
        let purposes = OnlineFeed.allCases.map { OnlineText.purpose($0) }
        XCTAssertEqual(Set(purposes).count, OnlineFeed.allCases.count)
        for purpose in purposes {
            XCTAssertFalse(purpose.isEmpty)
            XCTAssertTrue(purpose.hasSuffix("."), purpose)
        }
    }

    func testThePurposes() {
        XCTAssertEqual(OnlineText.purpose(.satellites),
                       "Shows when the ISS and other bright satellites cross your sky, on the Tonight screen and in Aim.")
        XCTAssertEqual(OnlineText.purpose(.starlink),
                       "Warns in Aim when Starlink satellites are likely to cross your frame during an exposure.")
        XCTAssertEqual(OnlineText.purpose(.comets), "Adds the current comets to the object list, the sky chart and Aim.")
        XCTAssertEqual(OnlineText.purpose(.clouds), "Shows tonight's hourly cloud cover on the Tonight screen.")
    }

    func testEveryFeedSaysWhoSeesTheIPAddress() {
        for feed in OnlineFeed.allCases {
            XCTAssertTrue(OnlineText.leavesPhone(feed).contains("sees your IP address"), "\(feed)")
        }
    }

    func testEveryFeedNamesItsProvidersHost() {
        for feed in OnlineFeed.allCases {
            let text = OnlineText.leavesPhone(feed)
            for resource in feed.resources {
                // The text names the registered domain, which is the host without a leading "www.".
                let domain = resource.host.hasPrefix("www.") ? String(resource.host.dropFirst(4)) : resource.host
                XCTAssertTrue(text.contains(domain), "\(feed): \(domain)")
            }
        }
    }

    func testOnlyTheCloudForecastSaysItSendsALocation() {
        XCTAssertTrue(OnlineText.leavesPhone(.clouds).contains("your location rounded to 0.1\u{00B0}"))
        XCTAssertTrue(OnlineText.leavesPhone(.clouds).contains("the rounded location"))
        for feed in [OnlineFeed.satellites, .starlink, .comets] {
            XCTAssertFalse(OnlineText.leavesPhone(feed).contains("location"), "\(feed)")
        }
    }

    func testStarlinkSaysItWaitsForAnUnmeteredNetwork() {
        XCTAssertTrue(OnlineText.leavesPhone(.starlink).contains("only on an unmetered network such as Wi-Fi"))
        XCTAssertTrue(OnlineResource.starlink.requiresUnmetered)
        for feed in [OnlineFeed.satellites, .comets, .clouds] {
            XCTAssertFalse(OnlineText.leavesPhone(feed).contains("unmetered"), "\(feed)")
        }
    }

    func testTheDescribedRatesAgreeWithTheRules() {
        XCTAssertTrue(OnlineText.leavesPhone(.satellites).contains("at most every 12 to 24 hours"))
        XCTAssertEqual(OnlineResource.stations.refreshInterval, 12 * 3600)
        XCTAssertEqual(OnlineResource.visual.refreshInterval, 24 * 3600)
        XCTAssertTrue(OnlineText.leavesPhone(.starlink).contains("once a day"))
        XCTAssertEqual(OnlineResource.starlink.refreshInterval, 24 * 3600)
        XCTAssertTrue(OnlineText.leavesPhone(.comets).contains("at most once a day"))
        XCTAssertEqual(OnlineResource.comets.minimumInterval, 24 * 3600)
    }
}
