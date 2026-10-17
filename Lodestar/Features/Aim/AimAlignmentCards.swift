import SwiftUI
import LodestarKit

/// A reference object in the alignment list: name, kind, brightness, position and distance from the camera.
struct AimCandidateRow: View {
    let row: AimAlignmentRow
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let object = row.candidate.object
        let position = row.candidate.horizontal
        Button(action: action) {
            HStack(spacing: 12) {
                ObjectIcon(category: object.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(object.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    Text("\(object.category.displayName) \u{00B7} \(AppFormat.magnitude(row.candidate.magnitude))")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(AppFormat.altitude(position.altitude)) \u{00B7} \(AppFormat.azimuth(position.azimuth))")
                    if let separation = row.separation {
                        Text("\(AppFormat.separation(separation)) away")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The chosen reference object with the distance still to go, refreshed four times a second.
struct AimReferenceCard: View {
    let model: AimViewModel
    let candidate: AimAlignmentCandidate
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "Center this object", systemImage: "scope")
            HStack(spacing: 12) {
                ObjectIcon(category: candidate.object.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.object.name)
                        .font(.title3.weight(.semibold))
                    Text("\(AppFormat.altitude(candidate.horizontal.altitude)) \u{00B7} \(AppFormat.azimuth(candidate.horizontal.azimuth))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                }
            }
            TimelineView(.animation(minimumInterval: 0.25)) { _ in
                progress
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aimPanel(palette, padding: 12)
    }

    @ViewBuilder
    private var progress: some View {
        if let guidance = model.engine.frame()?.guidance {
            let summary = AimGuidanceSummary(guidance)
            if summary.isOnTarget {
                Label("Close \u{2014} center it exactly, then Sync", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(palette.positive)
            } else if summary.isNearZenith {
                Label("\(AimFormat.angle(summary.separation)) away. Near zenith \u{2014} follow the arrow.", systemImage: "arrow.up.circle")
                    .foregroundStyle(palette.guidance)
            } else {
                Label("\(summary.pan.verb) \(AimFormat.angle(summary.pan.degrees)), \(summary.tilt.verb.lowercased()) \(AimFormat.angle(summary.tilt.degrees))",
                      systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .foregroundStyle(palette.guidance)
            }
        } else {
            Label("Waiting for the sensors\u{2026}", systemImage: "gyroscope")
                .foregroundStyle(palette.secondaryText)
        }
    }
}

/// What the alignment has found so far, its points and a way to start over.
struct AimAlignmentSummaryCard: View {
    let alignment: AlignmentModel
    let onRemove: (Int) -> Void
    let onReset: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "Current alignment", systemImage: "checkmark.seal")
            if alignment.isAligned {
                InfoRow(label: "Heading correction",
                        value: AngleFormatter.formatSignedDegrees(alignment.headingOffset, decimals: 1))
                InfoRow(label: "Bracket correction",
                        value: AngleFormatter.formatDegrees(alignment.deviceCorrection.length, decimals: 1))
                InfoRow(label: "Fit error (RMS)", value: AngleFormatter.formatDegrees(alignment.rmsResidual, decimals: 2))
                if let uncertainty = alignment.pointingUncertainty {
                    InfoRow(label: "Expected accuracy",
                            value: "\u{00B1}\(AngleFormatter.formatDegrees(uncertainty, decimals: uncertainty < 10 ? 1 : 0))")
                }
                ForEach(Array(alignment.points.enumerated()), id: \.offset) { index, point in
                    pointRow(index: index, point: point)
                }
                Button(action: onReset) {
                    Label("Reset alignment", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.lodestarSecondary)
            } else {
                Text("Not aligned yet. Without alignment the arrows trust the compass and assume the phone sits exactly as the mount in Settings says.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aimPanel(palette, padding: 12)
    }

    private func pointRow(index: Int, point: AlignmentPoint) -> some View {
        let name = point.name ?? "Point \(index + 1)"
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                if alignment.residuals.indices.contains(index) {
                    Text("Off by \(AngleFormatter.formatDegrees(alignment.residuals[index], decimals: 2)) after the fit")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Spacer(minLength: 8)
            Button {
                onRemove(index)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
            .accessibilityLabel("Remove \(name)")
        }
    }
}
