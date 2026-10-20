import SwiftUI
import UIKit
import LodestarKit

/// The row of status chips at the top: sensors, compass, alignment, location and camera.
struct AimStatusChips: View {
    let model: AimViewModel
    /// The screen's sheet, where the help page is presented from: this view is rebuilt when the display turns.
    @Binding var sheet: AimSheet?
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    /// Fractional deviation of the measured magnetic field from the expected one above which the compass is suspect.
    private static let interferenceThreshold = 0.25

    /// One chip. Chips that explain a problem with an iOS permission open the settings when tapped.
    private struct Item: Identifiable {
        let id: String
        let systemImage: String
        let text: String
        var tone: ChipTone = .neutral
        var opensSettings = false
    }

    var body: some View {
        AimFlowLayout {
            ForEach(items) { item in
                if item.opensSettings {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        // Padded to the minimum touch target.
                        StatusChip(systemImage: item.systemImage, text: item.text, tone: item.tone)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the iOS settings to allow camera access. The virtual sky still works.")
                } else {
                    StatusChip(systemImage: item.systemImage, text: item.text, tone: item.tone)
                }
            }
            SatelliteStreakChip(model: model)
            // The alignment and mount sheets leave the display usable, and the screen shows one sheet at a time. The
            // chip stays in its place, so the other chips do not move, but is out of reach while a sheet is up.
            HelpButton(topic: .aimScreen, appearance: .chip, action: { sheet = .help })
                .opacity(sheet == nil ? 1 : 0)
                .disabled(sheet != nil)
                .accessibilityHidden(sheet != nil)
        }
        .frame(maxWidth: .infinity)
    }

    private var items: [Item] {
        sensorItems + headingItems + [alignmentItem] + locationItems + cameraItems
    }

    // MARK: Sensors and heading

    private var sensorItems: [Item] {
        switch app.motion.status {
        case .starting:
            return [Item(id: "sensors", systemImage: "gyroscope", text: "Starting sensors")]
        case .failed:
            return [Item(id: "sensors", systemImage: "exclamationmark.triangle.fill", text: "Sensor problem", tone: .critical)]
        case .idle, .running, .unavailable:
            return []
        }
    }

    private var headingItems: [Item] {
        let motion = app.motion
        var items: [Item] = []
        if motion.headingSource == .gyroLock {
            items.append(Item(id: "heading", systemImage: "gyroscope", text: "Gyro lock"))
            if !motion.isGyroHeadingReferenced {
                items.append(Item(id: "heading-reference", systemImage: "exclamationmark.triangle.fill",
                                  text: "Set heading: align on a star", tone: .warning))
            }
        } else {
            items.append(compassItem(quality: motion.compassQuality))
        }
        if let disturbance = motion.magneticDisturbance, disturbance > Self.interferenceThreshold {
            items.append(Item(id: "interference", systemImage: "bolt.horizontal.fill", text: "Magnetic interference",
                              tone: .warning))
        }
        return items
    }

    private func compassItem(quality: CompassQuality) -> Item {
        switch quality {
        case .high: return Item(id: "heading", systemImage: "safari", text: "Compass good", tone: .positive)
        case .medium: return Item(id: "heading", systemImage: "safari", text: "Compass fair")
        case .low, .uncalibrated: return Item(id: "heading", systemImage: "safari", text: "Compass poor", tone: .warning)
        case .unavailable: return Item(id: "heading", systemImage: "safari", text: "No compass", tone: .warning)
        }
    }

    // MARK: Alignment, location and camera

    private var alignmentItem: Item {
        let alignment = app.alignment
        guard alignment.isAligned else { return Item(id: "alignment", systemImage: "scope", text: "Not aligned") }
        let error = alignment.pointingUncertainty ?? alignment.rmsResidual
        let count = alignment.points.count
        let accuracy = AngleFormatter.formatDegrees(error, decimals: error < 10 ? 1 : 0)
        return Item(id: "alignment", systemImage: "scope",
                    text: "Aligned \u{00B1}\(accuracy) \u{00B7} \(count) pt\(count == 1 ? "" : "s")",
                    tone: error <= 1 ? .positive : (error <= 3 ? .neutral : .warning))
    }

    private var locationItems: [Item] {
        guard app.location.isReducedAccuracy, app.observerContext?.source == .device else { return [] }
        return [Item(id: "location", systemImage: "location.circle", text: "Approx. location")]
    }

    private var cameraItems: [Item] {
        guard model.configuration.wantsCameraPreview else {
            return [Item(id: "camera", systemImage: "sparkles", text: "Virtual sky")]
        }
        switch app.camera.authorization {
        case .denied, .restricted:
            return [Item(id: "camera", systemImage: "video.slash", text: "Camera off \u{00B7} Settings", tone: .warning,
                         opensSettings: true)]
        case .unavailable:
            return [Item(id: "camera", systemImage: "video.slash", text: "No camera \u{00B7} virtual sky")]
        case .notDetermined, .authorized:
            guard app.camera.errorDescription != nil else { return [] }
            return [Item(id: "camera", systemImage: "video.slash", text: "Camera paused", tone: .warning)]
        }
    }
}
