import SwiftUI
import LodestarKit

/// The meridian countdown of the mount strip, for a German equatorial mount that has to flip when it has tracked past
/// the meridian: "Meridian in 25 min", a warning under 15 minutes, "Past the meridian: flip" after it. Display only:
/// nothing is sent to the mount.
enum MountMeridian {
    /// The countdown turns into a warning below this many seconds.
    static let warningSeconds = 15.0 * 60

    /// Where the mount is on its way to the meridian limit.
    enum Phase: Sendable, Equatable {
        /// More than `warningSeconds` to go.
        case ahead
        /// Less than `warningSeconds` to go.
        case soon
        /// The target has reached the limit: the mount has to flip.
        case past
    }

    /// What the chip says and how urgent it is.
    struct Chip: Sendable, Equatable {
        let text: String
        let phase: Phase

        var tone: ChipTone {
            switch phase {
            case .ahead: return .neutral
            case .soon: return .warning
            case .past: return .critical
            }
        }

        var systemImage: String { phase == .past ? "exclamationmark.triangle.fill" : "clock" }
    }

    /// The chip for a mount that is tracking the sky, or `nil` when there is nothing to say: no position or tracking
    /// yet, a slew or nudge in progress, a Sky-Watcher mount set up as alt-azimuth, or one already on its normal pier
    /// side (looking west, where it can track on past the meridian: it has flipped).
    ///
    /// The hour angle is the one of the place the mount points at; the limit is the driver's meridian limit when it has
    /// one (a Sky-Watcher mount: its overlap past the meridian), else 0°.
    static func chip(status: MountStatus, detail: MountDriverDetail?, observer: Observer, date: Date) -> Chip? {
        guard let position = status.position, status.isTracking == true, status.phase == .idle else { return nil }
        if detail?.arrangement == .altAzimuth || detail?.pierSide == .east { return nil }
        let apparent = SkyFrame(date: date, observer: observer).apparentPlace(j2000: position)
        let hourAngle = MeridianClock.hourAngle(of: apparent, at: date, observer: observer)
        guard let window = MeridianClock.flipWindow(hourAngle: hourAngle,
                                                    limitDegrees: detail?.meridianLimitDegrees ?? 0) else { return nil }
        return chip(for: window)
    }

    /// The chip for a countdown.
    static func chip(for window: MeridianFlipWindow) -> Chip {
        if window.isPastLimit { return Chip(text: "Past the meridian: flip", phase: .past) }
        let seconds = window.secondsUntilLimit
        let minutes = Int64((seconds / 60).rounded(.down))
        let text = minutes == 0 ? "Meridian in under 1 min"
            : "Meridian in \(ObjectDetailMeridian.durationText(minutes: minutes))"
        return Chip(text: text, phase: seconds < warningSeconds ? .soon : .ahead)
    }
}

/// The chip of `MountMeridian` for the connected mount; nothing while it has nothing to say.
struct MountMeridianChip: View {
    @Environment(AppModel.self) private var app

    private var service: MountService { MountService.shared }

    var body: some View {
        let chip = app.observerContext.flatMap {
            MountMeridian.chip(status: service.status, detail: service.driverDetail, observer: $0.observer,
                               date: app.clock.now)
        }
        Group {
            if let chip {
                StatusChip(systemImage: chip.systemImage, text: chip.text, tone: chip.tone)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // A mount that has to flip is said once, when the chip turns into that: the text no longer changes after it.
        .onChange(of: chip?.phase) { _, phase in
            if phase == .past {
                AccessibilityNotification.Announcement("Past the meridian: flip").post()
            }
        }
    }
}
