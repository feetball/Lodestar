import Foundation
import LodestarKit

/// What the mosaic sheet asks the planner for.
struct AimMosaicRequest: Equatable, Sendable {
    /// What the mosaic covers.
    enum Source: Equatable, Sendable {
        /// The area of an object with a catalog size, with a margin.
        case target(CelestialObject)
        /// The arch of the Milky Way above the horizon, as a horizontal panorama.
        case milkyWayArch
        /// A rectangle of `width` × `height` degrees centred where the camera pointed (azimuth and altitude).
        case custom(width: Double, height: Double, center: HorizontalCoordinate)
    }

    var source: Source
    /// The overlap of neighbouring panels as a fraction of the frame, in `MosaicPlanner.overlapRange`.
    var overlap: Double
    /// How the camera is held; `nil` takes the planner's recommendation.
    var orientation: MosaicOrientation?
    /// The lens's picture in landscape orientation.
    var frame: FrameSize
    var observer: Observer
    /// The instant the Milky Way arch and a custom centre are taken at.
    var date: Date
}

/// A plan, with the orientation the planner recommends for the area.
struct AimMosaicPlanResult: Sendable {
    let plan: MosaicPlan
    let recommendedOrientation: MosaicOrientation
    /// What the mosaic covers, in words.
    let title: String
}

/// A reason there is no plan, in words for the person.
struct AimMosaicProblem: Error, Equatable, Sendable {
    let message: String
}

/// Turns a request into a plan. Pure and thread safe: planning up to 500 panels is not instant, so run it off the main
/// actor.
enum AimMosaicPlanner {
    /// The margin a fitted object gets around it.
    static let fitMargin = MosaicRegion.defaultMargin
    /// The range of a custom area's sides in degrees.
    static let customWidthRange: ClosedRange<Double> = 2...180
    static let customHeightRange: ClosedRange<Double> = 2...120

    static func plan(for request: AimMosaicRequest) -> Result<AimMosaicPlanResult, AimMosaicProblem> {
        do {
            let (region, title) = try region(for: request)
            let recommended = try MosaicPlanner.recommendedOrientation(region: region, frame: request.frame,
                                                                       overlap: request.overlap)
            let plan = try MosaicPlanner.plan(region: region, frame: request.frame,
                                              orientation: request.orientation ?? recommended,
                                              overlap: request.overlap,
                                              observerLatitude: request.observer.location.latitude)
            return .success(AimMosaicPlanResult(plan: plan, recommendedOrientation: recommended, title: title))
        } catch let problem as AimMosaicProblem {
            return .failure(problem)
        } catch let error as MosaicError {
            return .failure(AimMosaicProblem(message: message(for: error)))
        } catch {
            return .failure(AimMosaicProblem(message: "This mosaic cannot be planned."))
        }
    }

    /// Why `object` cannot be fitted by a mosaic, or `nil` when it can.
    static func fitProblem(for object: CelestialObject?) -> String? {
        guard let object else { return "Choose a target first." }
        do {
            _ = try MosaicRegion.fitting(object: object, margin: fitMargin)
            return nil
        } catch let error as MosaicError {
            return message(for: error, object: object)
        } catch {
            return "\(object.name) cannot be covered by a mosaic."
        }
    }

    // MARK: Regions

    private static func region(for request: AimMosaicRequest) throws -> (MosaicRegion, String) {
        switch request.source {
        case .target(let object):
            return (try MosaicRegion.fitting(object: object, margin: fitMargin), object.name)
        case .milkyWayArch:
            let sky = SkyFrame(date: request.date, observer: request.observer)
            guard let region = MilkyWayPanorama.arch(frame: sky).panoramaRegion() else {
                throw AimMosaicProblem(message: "The Milky Way is below the horizon right now.")
            }
            return (region, "Milky Way arch")
        case .custom(let width, let height, let center):
            let sky = SkyFrame(date: request.date, observer: request.observer)
            let place = sky.j2000(fromHorizontal: center, refracted: true)
            let title = "Custom \(AngleFormatter.formatDegrees(width, decimals: 0)) \u{00D7} "
                + AngleFormatter.formatDegrees(height, decimals: 0)
            return (.equatorial(center: place, width: width, height: height), title)
        }
    }

    // MARK: Messages

    static func message(for error: MosaicError, object: CelestialObject? = nil) -> String {
        switch error {
        case .objectNotFixed:
            return "The Sun, the Moon and the planets move across the sky, so a mosaic cannot be planned for them."
        case .objectHasNoSize:
            return "\(object?.name ?? "This object") has no known angular size. Choose a nebula, galaxy or large cluster, or use a custom size."
        case .tooManyPanels(let count, let limit):
            return "This would take \(count) panels; the limit is \(limit). Use a wider lens or a smaller area."
        case .invalidWidth, .invalidHeight, .invalidAzimuthSpan, .invalidAltitudeRange:
            return "The area is too large to map. Choose a smaller one."
        case .invalidFrame:
            return "The lens in Settings has no usable field of view. Check the focal length and sensor."
        case .invalidOverlap:
            return "The overlap must be between 10% and 50%."
        case .invalidMargin, .invalidLatitude, .nonFiniteInput:
            return "This mosaic cannot be planned."
        }
    }

    // MARK: Descriptions

    /// "2 rows × 3 columns · 6 panels", or "10 panels in 3 rows" when the rows differ.
    static func gridText(_ plan: MosaicPlan) -> String {
        if plan.panelCount == 1 { return "1 panel" }
        if plan.isRectangular {
            return "\(plural(plan.rows, "row")) \u{00D7} \(plural(plan.columns, "column")) \u{00B7} \(plan.panelCount) panels"
        }
        return "\(plan.panelCount) panels in \(plural(plan.rows, "row"))"
    }

    /// The same grid for VoiceOver.
    static func spokenGridText(_ plan: MosaicPlan) -> String {
        if plan.panelCount == 1 { return "1 panel" }
        if plan.isRectangular {
            return "\(plural(plan.rows, "row")) by \(plural(plan.columns, "column")), \(plan.panelCount) panels"
        }
        return "\(plan.panelCount) panels in \(plural(plan.rows, "row"))"
    }

    /// What a warning of the plan means for the photographer.
    static func text(for warning: MosaicWarning) -> String {
        switch warning {
        case .tooManyPanels(let count):
            return "\(count) panels is a lot: shooting takes long and the sky moves meanwhile. A wider lens or a smaller area helps."
        case .overlapNotMet(let fraction):
            return "\(AppFormat.percent(fraction)) of the area is covered. Raise the overlap or use a wider lens."
        }
    }

    static func name(of orientation: MosaicOrientation) -> String {
        orientation == .landscape ? "Landscape" : "Portrait"
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
