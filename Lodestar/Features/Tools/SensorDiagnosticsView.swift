import SwiftUI
import LodestarKit

/// Live self-checks of the motion sensors and the CoreMotion convention (read-only, drawn in the palette so it is
/// safe to use at night): the raw attitude matrix, the camera boresight, the gravity check, the top-edge heading to
/// compare with the iOS Compass app, the compass and the reference frame.
///
/// Push it inside a navigation stack (Settings ▸ About). It refreshes ten times a second and needs the motion
/// service to run while it is visible.
struct SensorDiagnosticsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            SensorDiagnosticsForm(date: timeline.date)
        }
        .navigationTitle("Sensor Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            app.keepsMotionRunning = true
        }
        .onDisappear {
            app.keepsMotionRunning = false
        }
    }
}

/// The diagnostics for the newest motion sample at `date`.
private struct SensorDiagnosticsForm: View {
    /// Above this fractional deviation from the expected field strength the compass is probably disturbed.
    private static let interferenceThreshold = 0.25

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let date: Date

    var body: some View {
        let snapshot = app.motion.latestSample().map(SensorDiagnosticsSnapshot.init(sample:))
        let magnetic = app.observerContext.flatMap { SensorDiagnosticsMagneticModel(location: $0.location, date: date) }
        Form {
            statusSection(hasSample: snapshot != nil)
            if let snapshot {
                matrixSection(snapshot)
                boresightSection(snapshot)
                gravitySection(snapshot)
                topEdgeSection(snapshot, magnetic: magnetic)
                compassSection(snapshot, magnetic: magnetic)
            }
            referenceSection(snapshot)
        }
        .themedList(palette)
    }

    // MARK: Sections

    private func statusSection(hasSample: Bool) -> some View {
        SettingsSection(title: "Motion Sensors") {
            switch app.motion.status {
            case .unavailable:
                SettingsCaption("This iPhone has no motion sensors. The Simulator has none either, so these checks "
                                + "need a real device.")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(palette.critical)
            case .idle, .starting:
                SettingsCaption("Starting the motion sensors\u{2026}")
            case .running:
                if hasSample {
                    StatusChip(systemImage: "waveform.path.ecg", text: "Receiving samples", tone: .positive)
                } else {
                    SettingsCaption("Waiting for the first sample\u{2026}")
                }
            }
        }
    }

    private func matrixSection(_ snapshot: SensorDiagnosticsSnapshot) -> some View {
        SettingsSection(
            title: "Attitude Matrix",
            footer: "CoreMotion's rotation matrix M, with v_device = M \u{00B7} v_reference. Its rows are the device "
                + "axes (right edge, top edge, screen normal) written in the reference frame (north, west, up).") {
            SensorMatrixGrid(matrix: snapshot.matrix)
        }
    }

    private func boresightSection(_ snapshot: SensorDiagnosticsSnapshot) -> some View {
        SettingsSection(
            title: "Camera Boresight",
            footer: "The direction the back camera looks along, from the matrix: azimuth = atan2(m32, \u{2212}m31), "
                + "altitude = asin(\u{2212}m33).") {
            InfoRow(label: "Azimuth from true north", value: AppFormat.azimuth(snapshot.boresight.azimuth))
            InfoRow(label: "Altitude", value: AppFormat.altitude(snapshot.boresight.altitude))
            InfoRow(label: "Azimuth within the frame",
                    value: AngleFormatter.formatAzimuth(snapshot.boresightInFrame.azimuth))
            InfoRow(label: "LodestarKit agrees",
                    value: snapshot.boresightsAgree
                        ? "Yes"
                        : "No, \(AngleFormatter.formatDegrees(snapshot.boresightDisagreement, decimals: 2)) apart")
        }
    }

    private func gravitySection(_ snapshot: SensorDiagnosticsSnapshot) -> some View {
        SettingsSection(
            title: "Gravity Check",
            footer: "If M maps reference vectors to device vectors, gravity in device coordinates equals the third "
                + "column of M, (\u{2212}m13, \u{2212}m23, \u{2212}m33). The residual must stay below "
                + "\(SensorDiagnosticsSnapshot.gravityTolerance.formatted()) g. In symmetric poses, such as upright "
                + "with the camera pointing east, both mappings agree and the check proves nothing: tilt the phone.") {
            HStack {
                verdictChip(snapshot.gravityVerdict)
                Spacer(minLength: 0)
            }
            InfoRow(label: "Gravity (device)", value: Self.vector(snapshot.gravity))
            InfoRow(label: "Residual, reference \u{2192} device",
                    value: Self.residual(snapshot.referenceToDeviceResidual))
            InfoRow(label: "Residual, device \u{2192} reference",
                    value: Self.residual(snapshot.deviceToReferenceResidual))
        }
    }

    private func topEdgeSection(_ snapshot: SensorDiagnosticsSnapshot,
                                magnetic: SensorDiagnosticsMagneticModel?) -> some View {
        SettingsSection(
            title: "Top-Edge Heading",
            footer: "Lay the phone flat, screen up, with its top edge towards a known bearing and compare with the iOS "
                + "Compass app (it shows magnetic north unless Use True North is on in its settings). A constant "
                + "difference of 90\u{00B0} or 270\u{00B0} would mean the north axis of the convention is wrong.") {
            HStack {
                if snapshot.isFlat {
                    StatusChip(systemImage: "iphone", text: "Flat", tone: .positive)
                } else {
                    StatusChip(systemImage: "exclamationmark.triangle", text: "Not flat", tone: .warning)
                }
                Spacer(minLength: 0)
            }
            InfoRow(label: "Tilt from flat", value: AngleFormatter.formatDegrees(snapshot.tiltFromFlat))
            InfoRow(label: "True heading", value: AppFormat.azimuth(snapshot.topEdgeHeading))
            if let magnetic {
                let magneticHeading = AstroMath.normalizeDegrees(snapshot.topEdgeHeading - magnetic.declination)
                InfoRow(label: "Magnetic heading", value: AppFormat.azimuth(magneticHeading))
            }
        }
    }

    private func compassSection(_ snapshot: SensorDiagnosticsSnapshot,
                                magnetic: SensorDiagnosticsMagneticModel?) -> some View {
        SettingsSection(title: "Compass") {
            InfoRow(label: "Compass quality", value: app.motion.compassQuality.rawValue.capitalized)
            InfoRow(label: "Field measured", value: Self.microtesla(snapshot.magneticFieldMicrotesla))
            if let magnetic {
                InfoRow(label: "Field expected (WMM)", value: Self.microtesla(magnetic.expectedFieldMicrotesla))
                if let measured = snapshot.magneticFieldMicrotesla {
                    let deviation = magnetic.deviation(ofMeasured: measured)
                    HStack {
                        if deviation > Self.interferenceThreshold {
                            StatusChip(systemImage: "exclamationmark.triangle", text: "Interference suspected",
                                       tone: .warning)
                        } else {
                            StatusChip(systemImage: "checkmark", text: "Field as expected", tone: .positive)
                        }
                        Spacer(minLength: 0)
                    }
                    InfoRow(label: "Deviation", value: AppFormat.percent(deviation))
                }
                InfoRow(label: "Averaged deviation", value: AppFormat.percent(app.motion.magneticDisturbance))
                InfoRow(label: "Declination",
                        value: AngleFormatter.formatSignedDegrees(magnetic.declination, decimals: 2))
                InfoRow(label: "Inclination",
                        value: AngleFormatter.formatSignedDegrees(magnetic.inclination, decimals: 1))
                InfoRow(label: "Horizontal field", value: Self.microtesla(magnetic.horizontalFieldMicrotesla))
                InfoRow(label: "Compass here", value: Self.reliabilityText(magnetic.reliability))
                if !magnetic.isCurrent {
                    SettingsCaption("The World Magnetic Model 2025 is outside its validity (2025\u{2013}2030); "
                                    + "declination and field strength are extrapolated.")
                }
            } else {
                SettingsCaption("The expected field and the declination come from the World Magnetic Model and need "
                                + "a location.")
            }
        }
    }

    private func referenceSection(_ snapshot: SensorDiagnosticsSnapshot?) -> some View {
        SettingsSection(title: "Reference Frame") {
            InfoRow(label: "Reference", value: app.motion.referenceDescription)
            InfoRow(label: "Heading source", value: app.motion.headingSource.title)
            InfoRow(label: "Gyro heading referenced", value: app.motion.isGyroHeadingReferenced ? "Yes" : "No")
            InfoRow(label: "Frame epoch", value: "\(app.motion.frameEpoch)")
            if let snapshot {
                InfoRow(label: "Reference azimuth",
                        value: AngleFormatter.formatSignedDegrees(snapshot.referenceAzimuth, decimals: 2))
                InfoRow(label: "Rotation speed", value: AngleFormatter.formatDegrees(snapshot.angularSpeed) + "/s")
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func verdictChip(_ verdict: SensorDiagnosticsSnapshot.GravityVerdict) -> some View {
        switch verdict {
        case .pass: StatusChip(systemImage: "checkmark.circle", text: "PASS", tone: .positive)
        case .fail: StatusChip(systemImage: "xmark.circle", text: "FAIL", tone: .critical)
        case .inconclusive: StatusChip(systemImage: "exclamationmark.triangle", text: "Tilt the phone", tone: .warning)
        }
    }

    private static func vector(_ v: Vector3) -> String {
        String(format: "(%+.3f, %+.3f, %+.3f)", v.x, v.y, v.z)
    }

    private static func residual(_ value: Double) -> String {
        String(format: "%.3f g", value)
    }

    private static func microtesla(_ value: Double?) -> String {
        guard let value else { return AppFormat.missing }
        return String(format: "%.1f \u{00B5}T", value)
    }

    private static func reliabilityText(_ reliability: CompassReliability) -> String {
        switch reliability {
        case .reliable: return "Reliable"
        case .caution: return "Caution zone: degraded"
        case .blackout: return "Blackout zone: do not trust"
        }
    }
}

/// The nine entries of the attitude matrix in a monospaced grid.
private struct SensorMatrixGrid: View {
    @Environment(\.palette) private var palette
    let matrix: Matrix3

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        Text(String(format: "%+.4f", matrix[row, column]))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rotation matrix")
        .accessibilityValue(spokenRows)
    }

    /// "Row 1: …, Row 2: …": the entries a screen reader reads out.
    private var spokenRows: String {
        let rows = [matrix.r0, matrix.r1, matrix.r2].enumerated().map { index, row in
            "Row \(index + 1): " + [row.x, row.y, row.z].map { String(format: "%+.4f", $0) }.joined(separator: ", ")
        }
        return rows.joined(separator: ". ")
    }
}
