import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The feeds, the resources behind them (URLs, limits, intervals) and the privacy-relevant rounding of the forecast request.
final class OnlineFeedTests: XCTestCase {
    // MARK: Feeds

    func testThereAreFourFeedsInSettingsOrder() {
        XCTAssertEqual(OnlineFeed.allCases, [.satellites, .starlink, .comets, .clouds])
    }

    func testTheIdentifierIsTheRawValue() {
        XCTAssertEqual(OnlineFeed.satellites.id, "satellites")
        XCTAssertEqual(OnlineFeed.starlink.id, "starlink")
        XCTAssertEqual(OnlineFeed.comets.id, "comets")
        XCTAssertEqual(OnlineFeed.clouds.id, "clouds")
    }

    func testTitlesAreTheNamesInSettings() {
        XCTAssertEqual(OnlineFeed.satellites.title, "Satellite passes")
        XCTAssertEqual(OnlineFeed.starlink.title, "Starlink streak warnings")
        XCTAssertEqual(OnlineFeed.comets.title, "Comets")
        XCTAssertEqual(OnlineFeed.clouds.title, "Cloud forecast")
    }

    func testEachFeedOwnsItsFiles() {
        XCTAssertEqual(OnlineFeed.satellites.resources, [.stations, .visual])
        XCTAssertEqual(OnlineFeed.starlink.resources, [.starlink])
        XCTAssertEqual(OnlineFeed.comets.resources, [.comets])
        XCTAssertEqual(OnlineFeed.clouds.resources, [.forecast])
    }

    func testEveryResourceBelongsToExactlyOneFeed() {
        for resource in OnlineResource.allCases {
            let owners = OnlineFeed.allCases.filter { $0.resources.contains(resource) }
            XCTAssertEqual(owners, [resource.feed], "\(resource)")
        }
    }

    // MARK: Resources

    func testCacheKeysAreDistinctAndFixed() {
        XCTAssertEqual(OnlineResource.stations.key, "celestrak-stations")
        XCTAssertEqual(OnlineResource.visual.key, "celestrak-visual")
        XCTAssertEqual(OnlineResource.starlink.key, "celestrak-starlink")
        XCTAssertEqual(OnlineResource.comets.key, "mpc-comets")
        XCTAssertEqual(OnlineResource.forecast.key, "met-forecast")
        XCTAssertEqual(Set(OnlineResource.allCases.map(\.key)).count, OnlineResource.allCases.count)
    }

    func testHostsAreTheProvidersAndMatchTheRequestAddress() {
        XCTAssertEqual(OnlineResource.stations.host, "celestrak.org")
        XCTAssertEqual(OnlineResource.visual.host, "celestrak.org")
        XCTAssertEqual(OnlineResource.starlink.host, "celestrak.org")
        XCTAssertEqual(OnlineResource.comets.host, "www.minorplanetcenter.net")
        XCTAssertEqual(OnlineResource.forecast.host, "api.met.no")
        for resource in OnlineResource.allCases {
            XCTAssertEqual(resource.url(latitude: 32.8, longitude: -96.8)?.host, resource.host, "\(resource)")
        }
    }

    func testSizeLimits() {
        XCTAssertEqual(OnlineResource.stations.maximumBytes, 512 * 1024)
        XCTAssertEqual(OnlineResource.visual.maximumBytes, 1_048_576)
        XCTAssertEqual(OnlineResource.starlink.maximumBytes, 16 * 1024 * 1024)
        XCTAssertEqual(OnlineResource.comets.maximumBytes, 2 * 1024 * 1024)
        XCTAssertEqual(OnlineResource.forecast.maximumBytes, 1_048_576)
    }

    func testRefreshIntervals() {
        XCTAssertEqual(OnlineResource.stations.refreshInterval, 12 * 3600)
        XCTAssertEqual(OnlineResource.visual.refreshInterval, 24 * 3600)
        XCTAssertEqual(OnlineResource.starlink.refreshInterval, 24 * 3600)
        XCTAssertEqual(OnlineResource.comets.refreshInterval, 24 * 3600)
        XCTAssertEqual(OnlineResource.forecast.refreshInterval, 3600)
    }

    func testMinimumIntervalsAfterASuccess() {
        // CelesTrak: never more often than every two hours.
        XCTAssertEqual(OnlineResource.stations.minimumInterval, 7200)
        XCTAssertEqual(OnlineResource.visual.minimumInterval, 7200)
        XCTAssertEqual(OnlineResource.starlink.minimumInterval, 7200)
        XCTAssertEqual(OnlineResource.comets.minimumInterval, 24 * 3600)
        XCTAssertEqual(OnlineResource.forecast.minimumInterval, 600)
    }

    func testRetryIntervalsAfterAFailure() {
        XCTAssertEqual(OnlineResource.stations.retryInterval, 7200)
        XCTAssertEqual(OnlineResource.visual.retryInterval, 7200)
        XCTAssertEqual(OnlineResource.starlink.retryInterval, 7200)
        XCTAssertEqual(OnlineResource.comets.retryInterval, 3600)
        XCTAssertEqual(OnlineResource.forecast.retryInterval, 600)
    }

    func testOnlyStarlinkWaitsForAnUnmeteredNetwork() {
        XCTAssertTrue(OnlineResource.starlink.requiresUnmetered)
        for resource in [OnlineResource.stations, .visual, .comets, .forecast] {
            XCTAssertFalse(resource.requiresUnmetered, "\(resource)")
        }
    }

    func testOnlyTheStationsHaveAStaleDataLimit() {
        XCTAssertEqual(OnlineResource.stations.staleDataDays, 2)
        for resource in [OnlineResource.visual, .starlink, .comets, .forecast] {
            XCTAssertNil(resource.staleDataDays, "\(resource)")
        }
    }

    func testSatelliteResourcesMapToTheirCelesTrakGroup() {
        XCTAssertEqual(OnlineResource.stations.group, ElementSetGroup.stations)
        XCTAssertEqual(OnlineResource.visual.group, ElementSetGroup.visual)
        XCTAssertEqual(OnlineResource.starlink.group, ElementSetGroup.starlink)
        XCTAssertNil(OnlineResource.comets.group)
        XCTAssertNil(OnlineResource.forecast.group)
    }

    // MARK: Addresses

    func testSatelliteAddresses() {
        XCTAssertEqual(OnlineResource.stations.url()?.absoluteString,
                       "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=json")
        XCTAssertEqual(OnlineResource.visual.url()?.absoluteString,
                       "https://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=json")
        XCTAssertEqual(OnlineResource.starlink.url()?.absoluteString,
                       "https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=json")
    }

    func testCometAddress() {
        XCTAssertEqual(OnlineResource.comets.url()?.absoluteString,
                       "https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt")
    }

    func testOnlyTheForecastSendsTheLocation() {
        for resource in [OnlineResource.stations, .visual, .starlink, .comets] {
            let withPlace = resource.url(latitude: 32.8473, longitude: -96.7712)
            XCTAssertEqual(withPlace, resource.url(), "\(resource)")
            XCTAssertFalse(withPlace?.absoluteString.contains("lat=") ?? true, "\(resource)")
            XCTAssertFalse(withPlace?.absoluteString.contains("lon=") ?? true, "\(resource)")
        }
    }

    func testTheForecastAddressNeedsAPlace() {
        XCTAssertNil(OnlineResource.forecast.url())
        XCTAssertNil(OnlineResource.forecast.url(latitude: 32.8, longitude: nil))
        XCTAssertNil(OnlineResource.forecast.url(latitude: nil, longitude: -96.8))
    }

    func testTheForecastAddressCarriesTheRoundedPlace() {
        XCTAssertEqual(OnlineResource.forecast.url(latitude: 32.8473, longitude: -96.7712)?.absoluteString,
                       "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=32.8&lon=-96.8")
    }

    func testTheForecastRequestCarriesNoMorePrecisionThanTenthsOfADegreeAndNoElevation() throws {
        let url = try XCTUnwrap(OnlineResource.forecast.url(latitude: 32.84729183, longitude: -96.77123456))
        let text = url.absoluteString
        XCTAssertFalse(text.contains("32.84"), text)
        XCTAssertFalse(text.contains("96.77"), text)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.map(\.name), ["lat", "lon"])
        XCTAssertEqual(items.map(\.value), ["32.8", "-96.8"])
    }

    func testEveryAddressIsHTTPS() {
        for resource in OnlineResource.allCases {
            XCTAssertEqual(resource.url(latitude: 10, longitude: 20)?.scheme, "https", "\(resource)")
        }
    }

    // MARK: Coordinates

    func testTheStepIsATenthOfADegree() {
        XCTAssertEqual(OnlineCoordinates.stepDegrees, 0.1, accuracy: 0.0)
    }

    func testRoundingToTenthsOfADegree() {
        let table: [(Double, String)] = [
            (32.84, "32.8"), (32.86, "32.9"), (-96.77, "-96.8"), (0.0, "0.0"), (0.04, "0.0"), (0.06, "0.1"),
            (-0.04, "0.0"), (-0.06, "-0.1"), (89.96, "90.0"), (-89.96, "-90.0"),
        ]
        for (degrees, expected) in table {
            XCTAssertEqual(OnlineCoordinates.rounded(degrees), expected, "\(degrees)")
        }
    }

    func testHalfARoundsUpLikeAndroid() {
        // These values are exact in binary, so the half step is exact too.
        XCTAssertEqual(OnlineCoordinates.rounded(32.25), "32.3")
        XCTAssertEqual(OnlineCoordinates.rounded(0.25), "0.3")
        XCTAssertEqual(OnlineCoordinates.rounded(-0.25), "-0.2")
        XCTAssertEqual(OnlineCoordinates.rounded(-1.25), "-1.2")
        XCTAssertEqual(OnlineCoordinates.rounded(1.75), "1.8")
    }

    func testTinyNegativeValuesNeverBecomeMinusZero() {
        XCTAssertEqual(OnlineCoordinates.rounded(-0.0), "0.0")
        XCTAssertEqual(OnlineCoordinates.rounded(-0.01), "0.0")
        XCTAssertFalse(OnlineCoordinates.query(latitude: -0.03, longitude: -0.02).contains("-0.0"))
    }

    func testNonFiniteValuesRoundToZero() {
        XCTAssertEqual(OnlineCoordinates.rounded(.nan), "0.0")
        XCTAssertEqual(OnlineCoordinates.rounded(.infinity), "0.0")
        XCTAssertEqual(OnlineCoordinates.rounded(-.infinity), "0.0")
    }

    func testTheQueryNamesLatitudeThenLongitude() {
        XCTAssertEqual(OnlineCoordinates.query(latitude: 32.8473, longitude: -96.7712), "lat=32.8&lon=-96.8")
    }

    func testTheQueryKeepsTheLatitudeWithinThePoles() {
        XCTAssertEqual(OnlineCoordinates.query(latitude: 95, longitude: 0), "lat=90.0&lon=0.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: -95, longitude: 0), "lat=-90.0&lon=0.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: .infinity, longitude: 0), "lat=90.0&lon=0.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: -.infinity, longitude: 0), "lat=-90.0&lon=0.0")
    }

    func testTheQueryWrapsTheLongitudeIntoHalfATurnEitherWay() {
        XCTAssertEqual(OnlineCoordinates.query(latitude: 0, longitude: 190), "lat=0.0&lon=-170.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: 0, longitude: -190), "lat=0.0&lon=170.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: 0, longitude: 360), "lat=0.0&lon=0.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: 0, longitude: 540), "lat=0.0&lon=180.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: 0, longitude: 180), "lat=0.0&lon=180.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: 0, longitude: -180), "lat=0.0&lon=-180.0")
    }

    func testANonFiniteLongitudeBecomesZeroInTheQuery() {
        XCTAssertEqual(OnlineCoordinates.query(latitude: 10, longitude: .nan), "lat=10.0&lon=0.0")
        XCTAssertEqual(OnlineCoordinates.query(latitude: 10, longitude: .infinity), "lat=10.0&lon=0.0")
    }

    func testNoQueryEverCarriesMoreThanOneDecimalAndStaysWithinATwentiethOfADegree() {
        var latitude = -90.0
        while latitude <= 90.0 {
            var longitude = -180.0
            while longitude <= 180.0 {
                let query = OnlineCoordinates.query(latitude: latitude, longitude: longitude)
                let parts = query.split(separator: "&").map { $0.split(separator: "=").map(String.init) }
                XCTAssertEqual(parts.count, 2, query)
                guard parts.count == 2, parts[0].count == 2, parts[1].count == 2 else { return }
                XCTAssertEqual(parts[0][0], "lat")
                XCTAssertEqual(parts[1][0], "lon")
                for (value, original) in [(parts[0][1], latitude), (parts[1][1], longitude)] {
                    let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
                    XCTAssertEqual(pieces.count, 2, "\(value) from \(original)")
                    XCTAssertEqual(pieces.last?.count, 1, "\(value) from \(original)")
                    XCTAssertEqual(Double(value) ?? .nan, original, accuracy: 0.05 + 1e-6, "\(value) from \(original)")
                }
                XCTAssertFalse(query.contains("-0.0"), query)
                longitude += 7.3719
            }
            latitude += 3.1337
        }
    }

    func testTheKeyTellsPlacesApartAsFarAsTheRequestDoes() {
        XCTAssertEqual(OnlineCoordinates.key(latitude: 32.8473, longitude: -96.7712), "32.8,-96.8")
        XCTAssertEqual(OnlineCoordinates.key(latitude: 32.81, longitude: -96.79),
                       OnlineCoordinates.key(latitude: 32.84, longitude: -96.76))
        XCTAssertNotEqual(OnlineCoordinates.key(latitude: 32.84, longitude: -96.76),
                          OnlineCoordinates.key(latitude: 32.86, longitude: -96.76))
        XCTAssertNotEqual(OnlineCoordinates.key(latitude: 32.84, longitude: -96.76),
                          OnlineCoordinates.key(latitude: 32.84, longitude: -96.74))
    }

    // MARK: User agent

    func testTheUserAgentNamesTheAppItsVersionAndTheSupportPage() {
        XCTAssertEqual(OnlineUserAgent.make(version: "1.2"),
                       "Lodestar/1.2 (+https://feetball.github.io/Lodestar/support.html)")
        XCTAssertEqual(OnlineUserAgent.supportURL, "https://feetball.github.io/Lodestar/support.html")
    }

    func testTheUserAgentNeverHoldsAnEmailAddress() {
        XCTAssertFalse(OnlineUserAgent.supportURL.contains("@"))
        XCTAssertFalse(OnlineUserAgent.make(version: "1.0").contains("@"))
        XCTAssertFalse(OnlineUserAgent.current.contains("@"))
    }

    func testTheCurrentUserAgentStartsWithTheAppName() {
        let agent = OnlineUserAgent.current
        XCTAssertTrue(agent.hasPrefix("Lodestar/"), agent)
        XCTAssertTrue(agent.hasSuffix(" (+\(OnlineUserAgent.supportURL))"), agent)
    }
}
