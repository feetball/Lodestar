import Foundation
import LodestarKit

/// Clock positions on a polar-scope reticle.
enum ToolsPolarClock {
    /// The clock time for a direction measured clockwise from 12 o'clock: 30° per hour, so 315° is "10:30".
    static func text(angle: Double) -> String {
        guard angle.isFinite else { return AppFormat.missing }
        let totalMinutes = Int((AstroMath.normalizeDegrees(angle) * 2).rounded()) % 720
        let hour = totalMinutes / 60 == 0 ? 12 : totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hour):\(minutes < 10 ? "0" : "")\(minutes)"
    }
}
