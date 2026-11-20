import Foundation
import LodestarKit

/// The values of the log sheet while it is open, and how they become an entry.
///
/// The numbers are kept as the text that was typed, so that a half-typed "1." does not jump around.
struct SessionLogDraft: Equatable {
    /// The identifier of the entry being edited; `nil` for a new entry.
    var existingID: String?
    var date: Date
    var targetID: String
    var targetName: String
    var rightAscension: Double?
    var declination: Double?
    var siteName: String
    var siteLatitude: Double?
    var siteLongitude: Double?
    var siteUTCOffsetMinutes: Int?
    var camera: String
    var focalLength: Double?
    var lensAperture: Double?
    var sensorPixelsX: Int?
    var sensorPixelsY: Int?
    var exposureText: String
    var isoText: String
    var framesText: String
    var filter: String
    var notes: String
    var isImaged: Bool

    /// The decimals the exposure field shows when an entry is opened. Six keep 1/8000 s (0.000125 s) whole; fewer round
    /// a short exposure to "0", and that is what Save would then store. Trailing zeros are dropped, so 30 s reads "30".
    private static let exposureFractionDigits = 6

    /// A new entry for `object`: now, the observing site, the camera and lens of Settings, the NPF exposure as the exposure
    /// to start from, and the filter chosen in Settings.
    static func new(for object: CelestialObject, context: ObserverContext?, lens: LensSetup,
                    filter: ImagingFilter, now: Date) -> SessionLogDraft {
        let position = object.j2000
        let npf = ExposureCalculator.maxExposure(rule: .npf, setup: lens, declination: position?.declination).seconds
        var offsetMinutes: Int?
        if let zone = context?.timeZone {
            let seconds = zone.secondsFromGMT(for: now) - Int(zone.daylightSavingTimeOffset(for: now))
            offsetMinutes = seconds / 60
        }
        var pixelsX: Int?
        var pixelsY: Int?
        if let pitch = lens.pixelPitchMicrometers, pitch > 0 {
            pixelsX = Int((lens.sensor.widthMillimeters * 1000 / pitch).rounded())
            pixelsY = Int((lens.sensor.heightMillimeters * 1000 / pitch).rounded())
        }
        return SessionLogDraft(
            existingID: nil, date: now, targetID: object.id, targetName: object.name,
            rightAscension: position?.rightAscension, declination: position?.declination,
            siteName: context?.name ?? "",
            siteLatitude: context?.observer.location.latitude, siteLongitude: context?.observer.location.longitude,
            siteUTCOffsetMinutes: offsetMinutes, camera: lens.sensor.name,
            focalLength: lens.focalLengthMillimeters, lensAperture: lens.aperture,
            sensorPixelsX: pixelsX, sensorPixelsY: pixelsY,
            exposureText: npf.isFinite && npf >= 1 ? String(Int(npf.rounded())) : "",
            isoText: "", framesText: "", filter: filter == .none ? "" : filter.displayName,
            notes: "", isImaged: false)
    }

    /// The draft of an existing entry.
    init(editing entry: SessionLogEntry) {
        existingID = entry.id
        date = entry.date
        targetID = entry.targetID
        targetName = entry.targetName
        rightAscension = entry.rightAscension
        declination = entry.declination
        siteName = entry.siteName
        siteLatitude = entry.siteLatitude
        siteLongitude = entry.siteLongitude
        siteUTCOffsetMinutes = entry.siteUTCOffsetMinutes
        camera = entry.camera
        focalLength = entry.focalLength
        lensAperture = entry.lensAperture
        sensorPixelsX = entry.sensorPixelsX
        sensorPixelsY = entry.sensorPixelsY
        exposureText = entry.exposureSeconds > 0
            ? SettingsNumberText.text(for: entry.exposureSeconds, fractionDigits: Self.exposureFractionDigits) : ""
        isoText = entry.iso > 0 ? String(entry.iso) : ""
        framesText = entry.frameCount > 0 ? String(entry.frameCount) : ""
        filter = entry.filter
        notes = entry.notes
        isImaged = entry.isImaged
    }

    init(existingID: String?, date: Date, targetID: String, targetName: String, rightAscension: Double?,
         declination: Double?, siteName: String, siteLatitude: Double?, siteLongitude: Double?,
         siteUTCOffsetMinutes: Int?, camera: String, focalLength: Double?, lensAperture: Double?,
         sensorPixelsX: Int?, sensorPixelsY: Int?, exposureText: String, isoText: String, framesText: String,
         filter: String, notes: String, isImaged: Bool) {
        self.existingID = existingID
        self.date = date
        self.targetID = targetID
        self.targetName = targetName
        self.rightAscension = rightAscension
        self.declination = declination
        self.siteName = siteName
        self.siteLatitude = siteLatitude
        self.siteLongitude = siteLongitude
        self.siteUTCOffsetMinutes = siteUTCOffsetMinutes
        self.camera = camera
        self.focalLength = focalLength
        self.lensAperture = lensAperture
        self.sensorPixelsX = sensorPixelsX
        self.sensorPixelsY = sensorPixelsY
        self.exposureText = exposureText
        self.isoText = isoText
        self.framesText = framesText
        self.filter = filter
        self.notes = notes
        self.isImaged = isImaged
    }

    /// The exposure in seconds: 0 for an empty field, `nil` for text that is not a number of seconds from 0 to a day.
    var exposureSeconds: Double? {
        let text = exposureText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if text.isEmpty { return 0 }
        guard let value = Double(text), value.isFinite, value >= 0, value <= SessionLogEntry.maximumExposureSeconds else {
            return nil
        }
        return value
    }

    /// The ISO value: 0 for an empty field, `nil` for text that is not a whole number up to the highest ISO.
    var iso: Int? {
        wholeNumber(isoText, maximum: SessionLogEntry.maximumISO)
    }

    /// The number of frames: 0 for an empty field, `nil` for text that is not a whole number up to the most frames.
    var frameCount: Int? {
        wholeNumber(framesText, maximum: SessionLogEntry.maximumFrameCount)
    }

    /// Whether every number field holds a usable value.
    var isValid: Bool {
        exposureSeconds != nil && iso != nil && frameCount != nil
    }

    /// The entry the draft stands for; fields that are not valid count as not recorded.
    func entry() -> SessionLogEntry {
        SessionLogEntry(
            id: existingID ?? UUID().uuidString, date: date, targetID: targetID, targetName: targetName,
            rightAscension: rightAscension, declination: declination, siteName: siteName,
            siteLatitude: siteLatitude, siteLongitude: siteLongitude, siteUTCOffsetMinutes: siteUTCOffsetMinutes,
            camera: camera, focalLength: focalLength, lensAperture: lensAperture,
            sensorPixelsX: sensorPixelsX, sensorPixelsY: sensorPixelsY, exposureSeconds: exposureSeconds ?? 0,
            iso: iso ?? 0, frameCount: frameCount ?? 0, filter: filter, notes: notes, isImaged: isImaged)
    }

    private func wholeNumber(_ text: String, maximum: Int) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        guard let value = Int(trimmed), value >= 0, value <= maximum else { return nil }
        return value
    }
}

/// How entries read in lists.
enum SessionLogFormat {
    /// "30 × 2 min · ISO 800 · L-eXtreme · Imaged".
    static func summary(of entry: SessionLogEntry) -> String {
        var parts: [String] = []
        if entry.frameCount > 0, entry.exposureSeconds > 0 {
            parts.append("\(entry.frameCount) \u{00D7} \(AngleFormatter.formatExposure(seconds: entry.exposureSeconds))")
        } else if entry.frameCount > 0 {
            parts.append("\(entry.frameCount) frames")
        } else if entry.exposureSeconds > 0 {
            parts.append(AngleFormatter.formatExposure(seconds: entry.exposureSeconds))
        }
        if entry.iso > 0 { parts.append("ISO \(entry.iso)") }
        if !entry.filter.isEmpty { parts.append(entry.filter) }
        parts.append(entry.isImaged ? "Imaged" : "Not imaged")
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The date and time of an entry in the time zone of the device.
    static func dateText(of entry: SessionLogEntry) -> String {
        entry.date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "Night of Fri, Nov 18": the title of a night's section.
    static func nightTitle(_ night: Int64) -> String {
        let noon = Date(timeIntervalSince1970: Double(night) * 86_400 + 43_200)
        return "Night of " + AppFormat.day(noon, in: TimeZone(secondsFromGMT: 0) ?? .current)
    }
}
