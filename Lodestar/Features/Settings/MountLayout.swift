import Foundation
import LodestarKit

/// How a phone mount looks, derived from the mount's geometry so every preset (and any future one) gets a picture.
enum MountLayout: Equatable {
    /// The phone is clamped to the back of the camera, screen towards the photographer, its own camera looking
    /// along the lens. `rotation` is how far the phone is turned clockwise from upright, in degrees.
    case backCamera(rotation: Double)
    /// The phone lies screen-up on top of the camera, its top edge pointing along the lens or towards the photographer.
    case flatOnTop(topEdgeForward: Bool)
    /// Any other geometry.
    case custom

    init(_ profile: MountProfile) {
        let axis = profile.cameraAxis
        let up = profile.cameraUp
        if axis.dot(Vector3(0, 0, -1)) > 0.99 {
            // `cameraUp` is the phone edge that ends up at the top of the picture.
            self = .backCamera(rotation: AstroMath.normalizeSignedDegrees(-AstroMath.atan2Deg(up.x, up.y)))
        } else if abs(axis.y) > 0.99, up.dot(Vector3(0, 0, 1)) > 0.99 {
            self = .flatOnTop(topEdgeForward: axis.y > 0)
        } else {
            self = .custom
        }
    }

    /// One or two sentences on how the phone sits on the camera.
    var summary: String {
        switch self {
        case .backCamera(let rotation):
            switch Int(rotation.rounded()) {
            case 0:
                return "Upright on the back of the camera, screen towards you, its rear camera looking along the lens."
            case 180, -180:
                return "Upside down on the back of the camera, its rear camera looking along the lens."
            case -90:
                return "On its side with the top edge to your left, its rear camera looking along the lens."
            case 90:
                return "On its side with the top edge to your right, its rear camera looking along the lens."
            default:
                return "On the back of the camera, its rear camera looking along the lens."
            }
        case .flatOnTop(let topEdgeForward):
            return topEdgeForward
                ? "Flat on top of the camera, screen up, its top edge pointing along the lens."
                : "Flat on top of the camera, screen up, its top edge pointing towards you."
        case .custom:
            return "A custom mount."
        }
    }
}
