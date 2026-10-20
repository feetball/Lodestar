import SwiftUI
import LodestarKit

/// One object in the Objects list: icon, names, a one-line description and, on the right, where the object
/// is in the sky now or when it rises.
struct ObjectRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The widest the trailing column (the position, or "Below horizon" over the rising time) grows before its text
    /// wraps, so the names keep the rest of the row.
    @ScaledMetric(relativeTo: .footnote) private var statusWidth: CGFloat = 112

    let object: CelestialObject
    /// Where the object is now; `nil` while positions are not known.
    var position: ObjectSkyPosition?
    var isFavorite = false
    /// The observer's time zone, for rising times.
    var timeZone: TimeZone = .current
    /// Whether to name how prominent a deep-sky object is (the catalogue lists and the prominence order).
    var showsProminence = false

    var body: some View {
        HStack(spacing: 12) {
            ObjectIcon(category: object.category)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    names
                    skyPosition
                }
            } else {
                names
                Spacer(minLength: 8)
                skyPosition
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ObjectsFormat.spokenSummary(of: object, position: position, isFavorite: isFavorite,
                                                        in: timeZone, showsProminence: showsProminence))
    }

    /// At the largest text sizes nothing is cut: every line wraps instead.
    private var linesWrap: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            nameLine
            Text(ObjectsFormat.subtitle(of: object, magnitude: position?.magnitude, position: position))
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                // The kind, magnitude, elongation and warnings of a comet or an asteroid take up to three lines.
                .lineLimit(linesWrap ? nil : (object.smallBody == nil ? 1 : 3))
            if let line = ObjectsFormat.catalogueLine(of: object, showsProminence: showsProminence) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(linesWrap ? nil : 1)
            }
        }
    }

    /// The name with its first other designation and the favorite star. They share a line when they fit; otherwise the
    /// designation (which tells similar comets apart) and the star go under the name, so the name is not split at a
    /// hyphen and the designation is not cut.
    private var nameLine: some View {
        let designation = ObjectsFormat.extraDesignation(of: object)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                nameText
                if let designation {
                    designationText(designation)
                }
                if isFavorite {
                    favoriteStar
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                nameText
                if designation != nil || isFavorite {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let designation {
                            designationText(designation)
                        }
                        if isFavorite {
                            favoriteStar
                        }
                    }
                }
            }
        }
    }

    private var nameText: some View {
        Text(SmallBodyText.displayName(object))
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.primaryText)
            .lineLimit(linesWrap ? nil : 2)
    }

    private func designationText(_ designation: String) -> some View {
        Text(designation)
            .font(.subheadline)
            .foregroundStyle(palette.tertiaryText)
            .lineLimit(linesWrap ? nil : 1)
    }

    private var favoriteStar: some View {
        Image(systemName: "star.fill")
            .font(.caption)
            .foregroundStyle(palette.accent)
    }

    @ViewBuilder
    private var skyPosition: some View {
        if let position {
            VStack(alignment: linesWrap ? .leading : .trailing, spacing: 2) {
                if position.isAboveHorizon {
                    Text(ObjectsFormat.altitudeAndDirection(of: position))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .lineLimit(linesWrap ? nil : 1)
                } else {
                    Text(ObjectsFormat.hiddenText(for: position))
                        .font(.subheadline)
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(linesWrap ? nil : 2)
                    if let rising = ObjectsFormat.risingText(for: position, in: timeZone) {
                        // "Rises tomorrow 7:27 AM" takes two lines here rather than being cut.
                        Text(rising)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(linesWrap ? nil : 2)
                    }
                }
            }
            .monospacedDigit()
            .multilineTextAlignment(linesWrap ? .leading : .trailing)
            .frame(maxWidth: linesWrap ? nil : statusWidth, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
