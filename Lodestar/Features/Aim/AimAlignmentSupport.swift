import Foundation
import LodestarKit

/// A bright object that can serve as a reference for star alignment.
struct AimAlignmentCandidate: Identifiable, Sendable {
    let object: CelestialObject
    /// Apparent (refracted) position when the list was made.
    let horizontal: HorizontalCoordinate
    let magnitude: Double?

    var id: String { object.id }
}

/// A candidate with its distance from where the camera points, for sorting.
struct AimAlignmentRow: Identifiable {
    let candidate: AimAlignmentCandidate
    /// Degrees from the camera's boresight; `nil` while the sensors deliver nothing.
    let separation: Double?

    var id: String { candidate.id }
}

enum AimAlignmentCandidates {
    /// Lower limit of the altitude: objects this high are easy to find and clear of the haze, degrees.
    static let minimumAltitude = 15.0
    /// Upper limit: the alignment solver rejects objects close to the zenith, where azimuth means little.
    static let maximumAltitude = AlignmentModel.maximumAltitude - 2
    /// Stars at least this bright are offered.
    static let starMagnitudeLimit = 2.0
    /// Planets at least this bright are offered.
    static let planetMagnitudeLimit = 3.0

    /// The Moon, the bright planets and the bright stars that are between the altitude limits at `date`. The Sun is
    /// never offered: it must not be pointed at without a solar filter. Searches the catalog, so run it off the main
    /// actor.
    static func make(catalog: Catalog, observer: Observer, date: Date) -> [AimAlignmentCandidate] {
        let frame = SkyFrame(date: date, observer: observer)
        var candidates: [AimAlignmentCandidate] = []
        func add(_ object: CelestialObject, magnitude: Double?) {
            let horizontal = frame.horizontal(of: object, refraction: true)
            if (minimumAltitude...maximumAltitude).contains(horizontal.altitude) {
                candidates.append(AimAlignmentCandidate(object: object, horizontal: horizontal, magnitude: magnitude))
            }
        }
        for body in SolarSystemBody.allCases where body != .sun {
            guard let object = catalog.object(id: SkySnapshotBuilder.objectID(for: body)) else { continue }
            let magnitude = frame.state(of: body).apparentMagnitude
            if body != .moon, (magnitude ?? .infinity) > planetMagnitudeLimit { continue }
            add(object, magnitude: magnitude)
        }
        for star in catalog.renderStars.prefix(while: { $0.magnitude <= starMagnitudeLimit }) {
            if let object = catalog.object(id: star.id) {
                add(object, magnitude: star.magnitude)
            }
        }
        return candidates
    }
}

/// The outcome of the last alignment step, shown in the sheet.
enum AimAlignmentNotice {
    case success(String)
    case failure(String)

    var text: String {
        switch self {
        case .success(let text), .failure(let text): return text
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

extension AlignmentError {
    /// An explanation a photographer can act on.
    func aimMessage(forObject name: String) -> String {
        switch self {
        case .nonFiniteInput:
            return "The sensors gave an unusable reading. Hold the phone still for a moment and sync again."
        case .boresightTooHigh(let altitude):
            return "The camera points almost straight up (\(AngleFormatter.formatDegrees(altitude, decimals: 0))). Alignment needs an object below \(Int(AlignmentModel.maximumAltitude))\u{00B0}: choose a lower one."
        case .targetTooHigh(let altitude):
            return "\(name) is too high in the sky (\(AngleFormatter.formatDegrees(altitude, decimals: 0))) for a reliable alignment. Choose an object below \(Int(AlignmentModel.maximumAltitude))\u{00B0}."
        case .implausibleCorrection(let degrees):
            return "This would need a correction of \(AngleFormatter.formatDegrees(degrees, decimals: 0)), more than a bracket can cause. Check that \(name) is really in the middle of the frame and that the right mount is chosen in Settings."
        }
    }
}
