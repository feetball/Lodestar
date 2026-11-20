import XCTest
@testable import LodestarKit

/// The session log entry and its CSV and OpenAstronomyLog writers. `Fixtures/interchange/session_log_oal.xml` was written by
/// hand and validates against the OpenAstronomyLog 2.1 schema (https://github.com/openastronomylog/openastronomylog,
/// `src/oal21.xsd`, checked with libxml2).
final class SessionLogCodecTests: XCTestCase {
    /// 2026-11-19T03:15:30Z, 20:15:30 on 2026-11-18 at UTC-7.
    private let first = Date(timeIntervalSince1970: 1_795_058_130)

    private func log() -> [SessionLogEntry] {
        [
            SessionLogEntry(
                id: "id-1", date: first, targetID: "dso.M31", targetName: "Andromeda Galaxy",
                rightAscension: 10.6847, declination: 41.2687,
                siteName: "Dark Site", siteLatitude: 40.015, siteLongitude: -105.27, siteUTCOffsetMinutes: -420,
                camera: "Full Frame 36 × 24 mm", focalLength: 135, lensAperture: 2.8, sensorPixelsX: 6000, sensorPixelsY: 4000,
                exposureSeconds: 120, iso: 800, frameCount: 30, filter: "L-eXtreme",
                notes: "Good seeing, <clear> & dark \"sky\"", isImaged: true
            ),
            SessionLogEntry(
                id: "id-2", date: first.addingTimeInterval(7_200), targetID: "dso.M42", targetName: "Orion Nebula",
                rightAscension: 83.8221, declination: -5.3911,
                siteName: "Dark Site", siteLatitude: 40.015, siteLongitude: -105.27, siteUTCOffsetMinutes: -420,
                camera: "Full Frame 36 × 24 mm", focalLength: 135, lensAperture: 2.8, sensorPixelsX: 6000, sensorPixelsY: 4000,
                exposureSeconds: 60, iso: 1600, frameCount: 10, isImaged: false
            ),
            SessionLogEntry(
                id: "id-3", date: first.addingTimeInterval(86_400), targetID: "dso.M31", targetName: "Andromeda Galaxy",
                rightAscension: 10.6847, declination: 41.2687, siteName: "Backyard", isImaged: true
            ),
        ]
    }

    // MARK: Entries

    func testEntryValuesAreCleanedAndBounded() {
        let entry = SessionLogEntry(
            id: "  ", date: first, targetID: " dso.M31 ", targetName: "  \n ",
            rightAscension: 370, declination: 95, siteName: "A\tB\nC",
            siteLatitude: 91, siteLongitude: 10, siteUTCOffsetMinutes: 900,
            camera: String(repeating: "c", count: 300), focalLength: .nan, lensAperture: 500,
            sensorPixelsX: 6000, sensorPixelsY: nil,
            exposureSeconds: .infinity, iso: -5, frameCount: 10_000_000,
            filter: "x", notes: String(repeating: "n", count: 5_000), isImaged: true
        )
        XCTAssertNotNil(UUID(uuidString: entry.id))
        XCTAssertEqual(entry.targetID, "dso.M31")
        XCTAssertEqual(entry.targetName, SessionLogEntry.defaultTargetName)
        XCTAssertEqual(try XCTUnwrap(entry.rightAscension), 10, accuracy: 1e-9)
        XCTAssertEqual(entry.declination, 90)
        XCTAssertEqual(entry.siteName, "A B C")
        XCTAssertNil(entry.siteLatitude)
        XCTAssertNil(entry.siteLongitude)
        XCTAssertNil(entry.siteUTCOffsetMinutes)
        XCTAssertEqual(entry.camera.count, SessionLogEntry.maximumLabelLength)
        XCTAssertNil(entry.focalLength)
        XCTAssertNil(entry.lensAperture)
        XCTAssertNil(entry.sensorPixelsX)
        XCTAssertNil(entry.sensorPixelsY)
        XCTAssertEqual(entry.exposureSeconds, 0)
        XCTAssertEqual(entry.iso, 0)
        XCTAssertEqual(entry.frameCount, SessionLogEntry.maximumFrameCount)
        XCTAssertEqual(entry.notes.count, SessionLogEntry.maximumNotesLength)
    }

    func testCoordinatesCountOnlyAsAPair() {
        XCTAssertFalse(SessionLogEntry(date: first, targetID: "x", targetName: "x", rightAscension: 10).hasCoordinates)
        XCTAssertFalse(SessionLogEntry(date: first, targetID: "x", targetName: "x", rightAscension: .nan, declination: 5).hasCoordinates)
        XCTAssertTrue(SessionLogEntry(date: first, targetID: "x", targetName: "x", rightAscension: 10, declination: 5).hasCoordinates)
    }

    func testTotalExposureAndNights() {
        let entries = log()
        XCTAssertEqual(entries[0].totalExposureSeconds, 3_600)
        XCTAssertEqual(entries[0].night, 20_775)
        XCTAssertEqual(entries[1].night, 20_775)
        XCTAssertEqual(SessionLogCodec.nightText(entries[0].night), "2026-11-18")
        // Without a site offset the night follows UTC: 03:15 UTC belongs to the evening of the 19th, UTC-12h.
        XCTAssertEqual(SessionLogCodec.nightText(entries[2].night), "2026-11-19")
    }

    func testNightsChangeAtNoonLocalTime() {
        // 2026-11-18T11:59:59 and 12:00:00 at UTC+2 (09:59:59Z and 10:00:00Z).
        let beforeNoon = Date(timeIntervalSince1970: 1794995999)
        let atNoon = beforeNoon.addingTimeInterval(1)
        let day = SessionLogCodec.night(of: beforeNoon, utcOffsetMinutes: 120)
        XCTAssertEqual(SessionLogCodec.night(of: atNoon, utcOffsetMinutes: 120), day + 1)
        XCTAssertEqual(SessionLogCodec.night(of: beforeNoon, utcOffsetMinutes: 0), day)
        XCTAssertEqual(SessionLogCodec.night(of: atNoon, utcOffsetMinutes: 0), day)
        XCTAssertEqual(SessionLogCodec.night(of: atNoon, utcOffsetMinutes: -60), day)
    }

    // MARK: CSV

    func testCSVExportInDateOrder() {
        let expected = [
            "Date (UTC),Night,Target,Target ID,RA J2000 (deg),Dec J2000 (deg),Site,Latitude,Longitude,Camera,Focal length (mm),Aperture (f/),Exposure (s),ISO,Frames,Total exposure (s),Filter,Imaged,Notes",
            "2026-11-19T03:15:30Z,2026-11-18,Andromeda Galaxy,dso.M31,10.68470,41.26870,Dark Site,40.015,-105.27,Full Frame 36 × 24 mm,135,2.8,120,800,30,3600,L-eXtreme,yes,\"Good seeing, <clear> & dark \"\"sky\"\"\"",
            "2026-11-19T05:15:30Z,2026-11-18,Orion Nebula,dso.M42,83.82210,-5.39110,Dark Site,40.015,-105.27,Full Frame 36 × 24 mm,135,2.8,60,1600,10,600,,no,",
            "2026-11-20T03:15:30Z,2026-11-19,Andromeda Galaxy,dso.M31,10.68470,41.26870,Backyard,,,,,,0,,0,0,,yes,",
        ]
        XCTAssertEqual(SessionLogCodec.encodeCSV(log().reversed()), expected.joined(separator: "\r\n") + "\r\n")
    }

    func testCSVGuardsFormulasAndKeepsMultilineNotes() throws {
        let entry = SessionLogEntry(date: first, targetID: "custom.1", targetName: "=cmd|' /C calc'!A0", notes: "line 1\nline 2", isImaged: true)
        let table = try InterchangeCSV.parse(Array(SessionLogCodec.encodeCSV([entry]).unicodeScalars), maximumRecords: 10)
        XCTAssertEqual(table.records.count, 2)
        XCTAssertEqual(table.records[1].fields[2], "'=cmd|' /C calc'!A0")
        XCTAssertEqual(table.records[1].fields[18], "line 1\nline 2")
        XCTAssertEqual(table.records[1].fields.count, 19)
    }

    func testExportsAreCapped() {
        let entries = (0..<(SessionLogCodec.maximumEntries + 10)).map {
            SessionLogEntry(date: Date(timeIntervalSince1970: Double($0)), targetID: "t", targetName: "T\($0)")
        }
        XCTAssertEqual(SessionLogCodec.encodeCSV(entries).split(separator: "\r\n").count, SessionLogCodec.maximumEntries + 1)
    }

    // MARK: OpenAstronomyLog

    func testOpenAstronomyLogDocumentMatchesTheValidatedFixture() throws {
        let expected = try InterchangeTestSupport.fixture("session_log_oal.xml")
        XCTAssertEqual(SessionLogCodec.encodeOpenAstronomyLog(log()), expected)
    }

    func testOpenAstronomyLogWithoutEntriesHasEveryContainer() {
        let text = SessionLogCodec.encodeOpenAstronomyLog([], observer: "Ada King Lovelace")
        for name in ["sites", "sessions", "targets", "scopes", "eyepieces", "lenses", "filters", "imagers"] {
            XCTAssertTrue(text.contains("<\(name)/>") || text.contains("<\(name)>"), name)
        }
        XCTAssertTrue(text.contains("<name>Ada King</name>"))
        XCTAssertTrue(text.contains("<surname>Lovelace</surname>"))
        XCTAssertFalse(text.contains("<observation "))
    }

    func testOpenAstronomyLogEscapesTextAndDropsInvalidCharacters() {
        let entry = SessionLogEntry(
            date: first, targetID: "custom.<1>", targetName: "A & B <\"C\">",
            siteName: "Tom's \u{7}Site", siteLatitude: 10, siteLongitude: 20, notes: "x\u{1}y\u{B}z"
        )
        let text = SessionLogCodec.encodeOpenAstronomyLog([entry])
        XCTAssertTrue(text.contains("<name>A &amp; B &lt;&quot;C&quot;&gt;</name>"))
        XCTAssertTrue(text.contains("<name>Tom&apos;s Site</name>"))
        XCTAssertTrue(text.contains("xyz"))
        XCTAssertFalse(text.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" })
    }

    func testSitesWithTheSameNameButOtherPlacesStaySeparate() {
        let a = SessionLogEntry(date: first, targetID: "t", targetName: "T", siteName: "Current Location",
                                siteLatitude: 10, siteLongitude: 20, siteUTCOffsetMinutes: 60)
        let b = SessionLogEntry(date: first.addingTimeInterval(60), targetID: "t", targetName: "T", siteName: "Current Location",
                                siteLatitude: 11, siteLongitude: 20, siteUTCOffsetMinutes: 60)
        let text = SessionLogCodec.encodeOpenAstronomyLog([a, b])
        XCTAssertTrue(text.contains("id=\"site_2\""))
        XCTAssertTrue(text.contains("id=\"session_2\""))
        XCTAssertTrue(text.contains("id=\"target_1\""))
        XCTAssertFalse(text.contains("id=\"target_2\""))
    }
}
