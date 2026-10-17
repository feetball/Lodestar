import Foundation

/// How the phone is attached to the camera: the camera's optical axis and "up" direction expressed
/// in the phone's device frame, and how a movement of the camera is drawn on the phone's screen.
///
/// "Photographer" below is the person standing behind the camera and looking through it, so the
/// camera's *right* is `cameraAxis × cameraUp`.
///
/// The on-screen arrow is drawn in device coordinates (x towards the right edge, y towards the top
/// edge of the portrait phone). The camera's right and up directions are laid onto the screen plane
/// by the smallest rotation that makes the optical axis point into the screen, the way a person
/// reading it looks. For a back-camera mount that rotation is the identity: the arrow is the
/// physical direction on the screen, whichever way the phone is turned in the clamp. For a phone
/// lying on top of the camera the picture is tilted up to face the reader, so the top of the screen
/// means "tilt the lens up".
public struct MountProfile: Hashable, Codable, Sendable, Identifiable {
    private static let maximumIdentifierLength = 64
    private static let maximumNameLength = 80
    /// Smallest sine of the angle between `cameraUp` and `cameraAxis` that is accepted.
    private static let minimumAxisUpSine = 0.1

    /// Stable identifier, e.g. `"backCamera.portrait"`.
    public let id: String
    /// Display name.
    public let name: String
    /// The camera's optical axis (towards the scene) in device coordinates; a unit vector.
    public let cameraAxis: Vector3
    /// The camera's "up" (towards the top of the picture) in device coordinates; a unit vector
    /// perpendicular to `cameraAxis`.
    public let cameraUp: Vector3
    /// Device-frame direction in which a movement to the camera's right is drawn on the screen:
    /// a unit vector in the screen plane (z = 0).
    public let screenRight: Vector3
    /// Device-frame direction in which a movement to the camera's up is drawn on the screen:
    /// a unit vector in the screen plane (z = 0).
    public let screenUp: Vector3

    /// The camera's right (towards the right of the picture) in device coordinates.
    public var cameraRight: Vector3 { cameraAxis.cross(cameraUp) }

    /// `axis` and `up` must already be perpendicular unit vectors.
    private init(id: String, name: String, axis: Vector3, up: Vector3) {
        self.id = id
        self.name = name
        self.cameraAxis = axis
        self.cameraUp = up
        let screen = Self.screenAxes(axis: axis, up: up)
        self.screenRight = screen.right
        self.screenUp = screen.up
    }

    /// A mount with arbitrary geometry. `cameraUp` is made perpendicular to `cameraAxis`; `nil` is
    /// returned when a vector is not finite, has no length, or the two directions are within
    /// about 6° of being parallel.
    public static func custom(name: String = "Custom", cameraAxis: Vector3, cameraUp: Vector3) -> MountProfile? {
        make(id: "custom", name: name, axis: cameraAxis, up: cameraUp)
    }

    private static func make(id: String, name: String, axis: Vector3, up: Vector3) -> MountProfile? {
        guard axis.isFinite, up.isFinite else { return nil }
        let unitAxis = axis.normalized
        let upLength = up.length
        guard unitAxis != .zero, upLength > 0 else { return nil }
        let perpendicular = up - unitAxis * unitAxis.dot(up)
        guard perpendicular.length >= minimumAxisUpSine * upLength else { return nil }
        return MountProfile(id: String(id.prefix(maximumIdentifierLength)),
                            name: String(name.prefix(maximumNameLength)),
                            axis: unitAxis,
                            up: perpendicular.normalized)
    }

    /// Lays the camera's right and up onto the screen plane (see the type documentation).
    private static func screenAxes(axis: Vector3, up: Vector3) -> (right: Vector3, up: Vector3) {
        let readerLooks = Vector3(0, 0, -1) // into the screen
        let turn = axis.cross(readerLooks)
        let rotation: Matrix3
        if turn.length < 1e-12 {
            // Parallel: nothing to do. Anti-parallel (axis out of the screen): half a turn about "up".
            rotation = axis.dot(readerLooks) > 0 ? .identity : Matrix3.rotation(axis: up, angleRadians: .pi)
        } else {
            rotation = Matrix3.rotation(axis: turn, angleRadians: atan2(turn.length, axis.dot(readerLooks)))
        }
        let right = rotation * axis.cross(up)
        let screenUp = rotation * up
        return (Vector3(right.x, right.y, 0).normalized, Vector3(screenUp.x, screenUp.y, 0).normalized)
    }

    // MARK: Presets

    /// The phone's back camera looks along the lens, phone upright in portrait: the camera's up is
    /// the top edge of the phone, its right the right edge.
    public static let backCameraPortrait = MountProfile(
        id: "backCamera.portrait", name: "Back camera, portrait",
        axis: Vector3(0, 0, -1), up: Vector3(0, 1, 0))

    /// Back camera, phone upside down in the clamp: the camera's up is the bottom edge.
    public static let backCameraPortraitUpsideDown = MountProfile(
        id: "backCamera.portraitUpsideDown", name: "Back camera, upside down",
        axis: Vector3(0, 0, -1), up: Vector3(0, -1, 0))

    /// Back camera, phone turned like `UIDeviceOrientation.landscapeLeft`: top edge towards the
    /// photographer's left, home button / charging port on the right. The camera's up is the
    /// device +x axis (the right edge of the portrait phone), its right the device −y axis.
    public static let backCameraLandscapeLeft = MountProfile(
        id: "backCamera.landscapeLeft", name: "Back camera, landscape (top edge left)",
        axis: Vector3(0, 0, -1), up: Vector3(1, 0, 0))

    /// Back camera, phone turned like `UIDeviceOrientation.landscapeRight`: top edge towards the
    /// photographer's right, home button / charging port on the left. The camera's up is the
    /// device −x axis, its right the device +y axis.
    public static let backCameraLandscapeRight = MountProfile(
        id: "backCamera.landscapeRight", name: "Back camera, landscape (top edge right)",
        axis: Vector3(0, 0, -1), up: Vector3(-1, 0, 0))

    /// The phone lies screen-up on top of the camera with its top edge pointing along the lens.
    /// The optical axis is device +y and the camera's up is the screen normal (+z); the camera's
    /// right is the phone's right edge. The screen draws "tilt up" towards the top edge.
    public static let flatOnTopTopEdgeForward = MountProfile(
        id: "flatOnTop.topEdgeForward", name: "Flat on top, top edge forward",
        axis: Vector3(0, 1, 0), up: Vector3(0, 0, 1))

    /// The phone lies screen-up on top of the camera with its top edge towards the photographer
    /// (the lens points along the bottom edge). The optical axis is device −y, the camera's up the
    /// screen normal, the camera's right the phone's left edge (device −x).
    public static let flatOnTopTopEdgeBack = MountProfile(
        id: "flatOnTop.topEdgeBack", name: "Flat on top, top edge back",
        axis: Vector3(0, -1, 0), up: Vector3(0, 0, 1))

    /// All built-in presets in the order a settings screen should list them.
    public static let presets: [MountProfile] = [
        backCameraPortrait, backCameraPortraitUpsideDown, backCameraLandscapeLeft, backCameraLandscapeRight,
        flatOnTopTopEdgeForward, flatOnTopTopEdgeBack,
    ]

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, cameraAxis, cameraUp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let axis = try container.decode(Vector3.self, forKey: .cameraAxis)
        let up = try container.decode(Vector3.self, forKey: .cameraUp)
        guard let mount = Self.make(id: id, name: name, axis: axis, up: up) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "The camera axis and up vectors do not describe a valid mount."))
        }
        self = mount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(cameraAxis, forKey: .cameraAxis)
        try container.encode(cameraUp, forKey: .cameraUp)
    }
}
