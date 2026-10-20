import SwiftUI
import LodestarKit

/// The rows of a comet or an asteroid in the detail screen's "Now" card: the badges ("Photographable", the warnings),
/// the brightness estimate and the distances, elongation, phase and date of the orbit. `detail` is `nil` when the
/// orbit cannot be evaluated now.
struct SmallBodyNowRows: View {
    let detail: SmallBodyDetail?

    var body: some View {
        if let detail {
            rows(for: detail.info)
        } else {
            StatusChip(systemImage: "exclamationmark.triangle", text: SmallBodyText.capitalized(SmallBodyText.noCurrentOrbit),
                       tone: .warning)
        }
    }

    @ViewBuilder
    private func rows(for info: SmallBodyInfo) -> some View {
        let warnings = info.warnings
        if info.isPhotographable || !warnings.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { badges(info, warnings) }
                VStack(alignment: .leading, spacing: 8) { badges(info, warnings) }
            }
        }
        InfoRow(label: "Brightness", value: SmallBodyText.magnitude(info.magnitude, sentence: true))
        InfoRow(label: "Distance from Earth", value: ObjectDetailDistance.astronomicalUnits(info.earthDistanceAU).text)
        InfoRow(label: "Distance from Sun", value: ObjectDetailDistance.astronomicalUnits(info.sunDistanceAU).text)
        InfoRow(label: "Elongation", value: SmallBodyText.elongation(info.elongation))
        InfoRow(label: "Phase angle", value: AngleFormatter.formatDegrees(info.phaseAngle, decimals: 0))
        InfoRow(label: "Orbit elements", value: SmallBodyText.elementsDate(of: info.body))
    }

    @ViewBuilder
    private func badges(_ info: SmallBodyInfo, _ warnings: [SmallBodyWarning]) -> some View {
        if info.isPhotographable {
            StatusChip(systemImage: "camera", text: SmallBodyText.photographable, tone: .positive)
        }
        ForEach(warnings, id: \.self) { warning in
            StatusChip(systemImage: "exclamationmark.triangle", text: SmallBodyText.sentence(warning), tone: .warning)
        }
    }
}

/// Which way a comet's ion tail points and how far to tilt the camera to lay it along the frame. Nothing is drawn for
/// an asteroid, a comet without a tail direction, or while the detail is being computed.
struct SmallBodyTailCard: View {
    @Environment(\.palette) private var palette
    let detail: SmallBodyDetail?

    var body: some View {
        if let tail = detail?.tail {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "Comet Tail", systemImage: "sparkle")
                Text(SmallBodyText.tailTitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                InfoRow(label: "Points", value: SmallBodyText.tailDirection(tail.angleFromVertical))
                InfoRow(label: "Camera tilt", value: SmallBodyText.cameraTilt(tail.cameraTilt))
                Text(SmallBodyText.tailNote)
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if tail.isForeshortened {
                    Text(SmallBodyText.tailForeshortened)
                        .font(.footnote)
                        .foregroundStyle(palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(palette)
        }
    }
}

/// A favourite comet or asteroid without a current orbit, as a row of the Favorites section: its designation, "no
/// current orbit", and the star that removes it from the favourites. Made for a row of the Objects list.
struct SmallBodyNoOrbitRow: View {
    @Environment(\.palette) private var palette
    let id: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ObjectIcon(category: SmallBodyFavorites.category(ofID: id))
                VStack(alignment: .leading, spacing: 2) {
                    Text(SmallBodyFavorites.name(ofID: id))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                    Text(SmallBodyFavorites.subtitle(ofID: id))
                        .font(.footnote)
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SmallBodyFavorites.spoken(ofID: id))
            Button(action: onRemove) {
                Image(systemName: "star.fill")
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(SmallBodyFavorites.name(ofID: id)) from favorites")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .listRowInsets(EdgeInsets())
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.stroke)
    }
}
