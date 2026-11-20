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
    /// What reading an image came to.
    enum Outcome: Hashable, Sendable {
        /// The camera and lens the image says it was taken with.
        case result(CameraPhotoResult)
        /// The image gives a focal length that a camera profile cannot have (a phone's ultra wide lens is about 2 mm).
        case focalLengthOutOfRange(millimeters: Double)
        /// The data is not an image, or the image says nothing about its focal length.
        case noLens
    }

    /// The camera and lens an image was taken with. Reads the header only, but call it off the main actor all the
    /// same: a large file takes a moment.
    static func read(fromImageData data: Data) -> Outcome {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .noLens
        }
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
        guard let suggestion = metadata.suggestion() else {
            // Without a suggestion the focal length is missing or outside the range the profiles keep.
            if let millimeters = metadata.focalLengthMillimeters {
                return .focalLengthOutOfRange(millimeters: millimeters)
            }
            return .noLens
        }
        return .result(CameraPhotoResult(metadata: metadata, suggestion: suggestion))
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
        // A pitch outside the range of a camera profile is left out of the profile, so it is left out here as well: it
        // comes from a picture that was reduced or cropped.
        if let pitch = suggestion.pixelPitchMicrometers, CameraProfile.pixelPitchRange.contains(pitch) {
            lines.append(("Pixel pitch", "\(format(pitch, 2)) \u{00B5}m (estimated)"))
        }
        return lines
    }

    /// What is said when the picture has no usable lens.
    static let noLensMessage = "That picture does not say which lens it was taken with. Choose a photo straight from "
        + "the camera, not a screenshot or an edited copy."

    /// What is said when the picture names a focal length that a profile cannot have, such as 2.2 mm.
    static func focalLengthMessage(millimeters: Double) -> String {
        let range = LensSetup.focalLengthRange
        return "That picture says its lens is \(format(millimeters, 1)) mm, but a profile takes focal lengths from "
            + "\(format(range.lowerBound, 0)) to \(format(range.upperBound, 0)) mm. Add a preset and change its "
            + "numbers instead."
    }

    private static func format(_ value: Double, _ digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}
