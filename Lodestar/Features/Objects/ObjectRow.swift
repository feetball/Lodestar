import SwiftUI
import LodestarKit

/// One object in the Objects list: icon, names, a one-line description and, on the right, where the object
/// is in the sky now or when it rises.
struct ObjectRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let object: CelestialObject
    /// Where the object is now; `nil` while positions are not known.
    var position: ObjectSkyPosition?
    var isFavorite = false
    /// The observer's time zone, for rising times.
    var timeZone: TimeZone = .current

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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ObjectsFormat.spokenSummary(of: object, position: position, isFavorite: isFavorite,
                                                        in: timeZone))
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(object.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                if let designation = ObjectsFormat.extraDesignation(of: object) {
                    Text(designation)
                        .font(.subheadline)
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                }
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                }
            }
            Text(ObjectsFormat.subtitle(of: object, magnitude: position?.magnitude))
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var skyPosition: some View {
        if let position {
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                if position.isAboveHorizon {
                    Text(ObjectsFormat.altitudeAndDirection(of: position))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.accent)
                } else {
                    Text("Below horizon")
                        .font(.subheadline)
                        .foregroundStyle(palette.tertiaryText)
                    if let rising = ObjectsFormat.risingText(for: position, in: timeZone) {
                        Text(rising)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
            .monospacedDigit()
            .lineLimit(1)
        }
    }
}
