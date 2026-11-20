import CoreGraphics
import Foundation
import LodestarKit

/// The optics of the delivered frames, for matching the sky overlay to the picture.
struct CameraGeometry: Sendable, Equatable {
    /// Field of view across the frame's width, degrees.
    var portraitHorizontalFOV: Double
    /// Field of view across the frame's height, degrees.
    var portraitVerticalFOV: Double
    /// Frame size in pixels; the frames are upright in portrait.
    var imageWidth: Int
    var imageHeight: Int

    /// The geometry of a frame of `width` × `height` pixels when the format's field of view,
    /// `longSideFieldOfView` degrees, spans the frame's long side. Pinhole model with square pixels; `nil` for
    /// unusable input.
    static func portrait(longSideFieldOfView: Double, width: Int, height: Int) -> CameraGeometry? {
        guard width > 0, height > 0, longSideFieldOfView > 0, longSideFieldOfView < 180 else { return nil }
        let longSide = Double(max(width, height))
        let shortSide = Double(min(width, height))
        let halfLong = AstroMath.radians(longSideFieldOfView) / 2
        let shortSideFieldOfView = AstroMath.degrees(2 * atan(tan(halfLong) * shortSide / longSide))
        let isPortrait = height >= width
        return CameraGeometry(portraitHorizontalFOV: isPortrait ? shortSideFieldOfView : longSideFieldOfView,
                              portraitVerticalFOV: isPortrait ? longSideFieldOfView : shortSideFieldOfView,
                              imageWidth: width, imageHeight: height)
    }
}
