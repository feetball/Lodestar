import Foundation
import ImageIO
import LodestarKit

/// What was read from a photo: the EXIF numbers and the camera profile they suggest.
struct CameraPhotoResult: Hashable, Sendable {
    let metadata: CameraPhotoMetadata
    let suggestion: CameraPhotoSuggestion
}

/// Reads the EXIF tags that describe the camera and lens, with ImageIO (`FocalLength`, `FNumber`,
/// `FocalLenIn35mmFilm`, `Model` and the pixel dimensions). The picture is read once and not kept.
enum CameraPhotoReader {
    /// The camera and lens an image was taken with, or nil when the data is not an image or has no usable focal
    /// length. Reads the header only, but call it off the main actor all the same: a large file takes a moment.
    static func result(fromImageData data: Data) -> CameraPhotoResult? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        func number(_ value: Any?) -> Double? {
            guard let number = (value as? NSNumber)?.doubleValue, number.isFinite, number > 0 else { return nil }
            return number
        }
        func whole(_ value: Any?) -> Int? {
            guard let number = (value as? NSNumber)?.intValue, number > 0 else { return nil }
            return number
        }
        let metadata = CameraPhotoMetadata(
            cameraModel: tiff[kCGImagePropertyTIFFModel] as? String,
            focalLengthMillimeters: number(exif[kCGImagePropertyExifFocalLength]),
            focalLength35mmEquivalent: number(exif[kCGImagePropertyExifFocalLenIn35mmFilm]),
            aperture: number(exif[kCGImagePropertyExifFNumber]),
            pixelWidth: whole(properties[kCGImagePropertyPixelWidth]) ?? whole(exif[kCGImagePropertyExifPixelXDimension]),
            pixelHeight: whole(properties[kCGImagePropertyPixelHeight]) ?? whole(exif[kCGImagePropertyExifPixelYDimension])
        )
        guard let suggestion = metadata.suggestion() else { return nil }
        return CameraPhotoResult(metadata: metadata, suggestion: suggestion)
    }
}

/// The lines that tell what a photo said, as label and value.
enum CameraPhotoText {
    static func lines(_ result: CameraPhotoResult) -> [(label: String, value: String)] {
        let metadata = result.metadata
        let suggestion = result.suggestion
        var lines: [(label: String, value: String)] = []
        if let name = suggestion.name { lines.append(("Camera", name)) }
        let focal = "\(format(suggestion.focalLengthMillimeters, 1)) mm"
        if let equivalent = metadata.focalLength35mmEquivalent, equivalent > 0 {
            lines.append(("Focal length", "\(focal) (\(format(equivalent, 0)) mm equivalent)"))
        } else {
            lines.append(("Focal length", focal))
        }
        if let aperture = suggestion.aperture { lines.append(("Aperture", "f/\(format(aperture, 1))")) }
        if let megapixels = suggestion.megapixels { lines.append(("Resolution", "\(format(megapixels, 1)) MP")) }
        if let sensor = suggestion.sensor, let crop = suggestion.cropFactor {
            lines.append(("Sensor", "\(sensor.name) (crop factor \(format(crop, 2)))"))
        } else {
            lines.append(("Sensor", "Not in the photo: check it below"))
        }
        if let pitch = suggestion.pixelPitchMicrometers {
            lines.append(("Pixel pitch", "\(format(pitch, 2)) \u{00B5}m (estimated)"))
        }
        return lines
    }

    private static func format(_ value: Double, _ digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}
