#if DEBUG
import Foundation
import LodestarKit

/// Comets for the review screens. The app bundles bright asteroids but no comets (they come from a download), so
/// without these the comet screens would only ever show their empty states. They are real MPC orbit lines of
/// 2026-10-18 (the lines of `CometsTestData` in the LodestarKit tests), read with the engine's own parser; on that
/// date 161P/Hartley-IRAS is the one comet brighter than magnitude 10.
enum ReviewFixtures {
    static let cometLines: [String] = [
        "    CJ95O010  1997 03 29.0284  0.925995  0.994895  130.7313  281.8097   89.7335  20261017  -2.0  4.0  C/1995 O1 (Hale-Bopp)                                    MPC194091",
        "    CK23A030  2024 09 27.8337  0.391312  1.000180  308.5842   21.6759  139.0991  20261017   6.5  3.2  C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2026-O98",
        "0012P         2024 04 21.2066  0.781920  0.954748  199.0355  255.8678   74.1469  20261017   5.0  6.0  12P/Pons-Brooks                                          MPEC 2026-TI5",
        "0001P         2061 08  1.5218  0.570945  0.968030  112.1616   59.2610  162.1917  20261017   5.5  3.2  1P/Halley                                                MPC191592",
        "0002P         2027 02 10.2276  0.338603  0.847319  187.2873  334.0197   11.3480  20261017  14.4  4.0  2P/Encke                                                 MPC xxxxx",
        "0073P     bt  2027 12 25.1036  0.915911  0.700909  214.4932   52.3435    6.1794  20261017  11.5  6.0  73P-BT/Schwassmann-Wachmann                              MPC106348",
        "    CK13A010  2014 10 26.8227  1.391249  1.000073    2.5353  301.1848  128.6857  20261017   8.2  2.4  C/2013 A1 (SidingSpring)                                 MPC194130",
        "    PK26N020  2026 09 25.7701  2.422069  0.212174  218.8645   96.3812    2.2496  20261017  17.4  4.0  P/2026 N2                                                MPEC 2026-Q95",
        "0161P         2026 11 27.1783  1.265109  0.836180   47.0652    1.4736   95.7919  20261017   8.5  6.0  161P/Hartley-IRAS                                        MPEC 2026-TP0",
        "0078P         2026 06 25.1355  2.004570  0.462933  192.8100  210.4913    6.2574  20261017   5.5  8.0  78P/Gehrels                                              MPEC 2026-TP0",
        "0029P         2034 03 15.1855  5.797924  0.042915   51.2459  312.3998    9.3549  20261017   4.0  4.0  29P/Schwassmann-Wachmann                                 MPEC 2026-RA1",
        "    CK14UR1N  2031 01 16.6692 10.959316  1.004054  326.0949  190.0073   95.4457  20261017   2.5  3.2  C/2014 UN271 (Bernardinelli-Bernstein)                   MPEC 2026-TP0",
        "    CK24E010  2026 01 20.8145  0.565779  1.000381  243.6172  108.0685   75.1999  20261017   7.0  4.0  C/2024 E1 (Wierzchos)                                    MPEC 2026-O98",
        "    PK26R020  2026 10 25.2362  0.789531  0.898740  205.5263  179.2306   78.0993  20261017  16.0  4.0  P/2026 R2 (Leonard)                                      MPC xxxxx",
    ]

    static var comets: [SmallBody] {
        cometLines.compactMap { try? CometElementsParser.parseLine($0) }
    }
}

extension ReviewFixtures {
    /// The satellites of the LodestarKit tests (real element sets of 2026-10-18), read by the app's own parser. The
    /// review workflow copies the three files next to the app's resources; without them there are no satellites.
    static func satelliteGroups(now: Date) -> [SatelliteGroup] {
        let files: [(OnlineResource, String)] = [
            (.stations, "satellite_stations"), (.visual, "satellite_omm_sample"), (.starlink, "satellite_starlink_sample"),
        ]
        var groups: [SatelliteGroup] = []
        for (resource, name) in files {
            guard let group = resource.group,
                  let url = Bundle.main.url(forResource: name, withExtension: "json")
                    ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "ReviewFixtures"),
                  let data = try? Data(contentsOf: url),
                  let parsed = try? SatelliteGroup.parse(group: group, data: data, now: now) else { continue }
            groups.append(parsed.value)
        }
        return groups
    }

    /// A cloud forecast in the shape of MET Norway's answer, read by the app's own parser: hourly values from half a day
    /// before `reference` to two and a half days after it, cloudy in the evening, clear in the middle of the night, high
    /// cloud before dawn, a cloudy day after. Local solar time is taken from the longitude.
    static func forecast(around reference: Date, latitude: Double, longitude: Double) -> CloudForecast? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let first = (reference.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600 - 12 * 3_600
        var series: [[String: Any]] = []
        for hour in 0..<72 {
            let time = Date(timeIntervalSince1970: first + Double(hour) * 3_600)
            let solarHour = (time.timeIntervalSince1970 / 3_600 + longitude / 15).truncatingRemainder(dividingBy: 24)
            let local = solarHour < 0 ? solarHour + 24 : solarHour
            let layers: (low: Double, medium: Double, high: Double)
            switch local {
            case 17..<21: layers = (60, 40, 30)
            case 21..<23: layers = (20, 10, 10)
            case 23..<24, 0..<3: layers = (0, 0, 5)
            case 3..<5.5: layers = (0, 5, 60)
            case 5.5..<8: layers = (10, 30, 80)
            default: layers = (70, 60, 40)
            }
            let (low, medium, high) = layers
            let total = min(100, max(low, medium, high) + (low + medium + high) / 12)
            series.append([
                "time": formatter.string(from: time),
                "data": ["instant": ["details": [
                    "cloud_area_fraction": total, "cloud_area_fraction_low": low,
                    "cloud_area_fraction_medium": medium, "cloud_area_fraction_high": high,
                ]]],
            ])
        }
        let object: [String: Any] = [
            "type": "Feature",
            "geometry": ["type": "Point", "coordinates": [longitude, latitude, 2_130]],
            "properties": [
                "meta": ["updated_at": formatter.string(from: reference.addingTimeInterval(-3_600))],
                "timeseries": series,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? ForecastParser.parseForecast(data)
    }
}
#endif
