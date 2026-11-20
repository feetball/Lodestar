import Foundation
import LodestarKit

/// The border of the camera's picture on the sky: the outline of the lens setup in the camera's frame (x right, y up, z
/// along the optical axis, see `CameraFrameOutline`) turned to where the camera points.
enum AimLensFrame {
    /// Points per edge of a rectilinear frame, whose edges are straight: the four edges need no more.
    static let rectilinearSamplesPerEdge = 4

    /// Points per edge of a fisheye frame, whose edges and circle are curves.
    static let fisheyeSamplesPerEdge = 24

    /// How many points per edge draw the frame of `lens` without visible corners; `rectilinear` is the count for a
    /// rectilinear frame, for a view that wants more than the Aim screen's four.
    static func samplesPerEdge(for lens: LensSetup, rectilinear: Int = rectilinearSamplesPerEdge) -> Int {
        lens.projection.isFisheye ? fisheyeSamplesPerEdge : rectilinear
    }

    /// The border of the picture of `lens` in the camera's frame, drawn with the right number of points.
    static func outline(of lens: LensSetup, rectilinearSamplesPerEdge: Int = rectilinearSamplesPerEdge) -> [Vector3] {
        CameraFrameOutline.directions(setup: lens,
                                      samplesPerEdge: samplesPerEdge(for: lens, rectilinear: rectilinearSamplesPerEdge))
    }

    /// `outline` as world directions for the pointing `solution`: `right * x + up * y + forward * z`.
    static func worldDirections(of outline: [Vector3], pointing solution: PointingSolution) -> [Vector3] {
        let right = solution.cameraRightVector
        let up = solution.cameraUpVector
        let forward = solution.boresightVector
        return outline.map { right * $0.x + up * $0.y + forward * $0.z }
    }
}
