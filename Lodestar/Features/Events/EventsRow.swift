import SwiftUI
import LodestarKit

/// "Visible from here" or "Not visible from here", with an eye that is open or crossed out.
struct EventsVisibilityBadge: View {
    @Environment(\.palette) private var palette

    let isVisible: Bool

    var body: some View {
        Label(isVisible ? "Visible from here" : "Not visible from here",
              systemImage: isVisible ? "eye" : "eye.slash")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isVisible ? palette.positive : palette.tertiaryText)
    }
}

/// One event in a list: symbol, title, one-line summary, local date and time, the Moon's effect on a meteor shower
/// and whether the event can be seen from the observer's place. Rows are wrapped in `NavigationLink(value:)`.
struct EventsRow: View {
    @Environment(\.palette) private var palette

    let entry: EventsEntry
    let timeZone: TimeZone
    let isSouthernHemisphere: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: EventsFormat.symbol(for: entry.event))
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(palette.accent)
                .frame(width: 29, height: 29)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(EventsFormat.summary(of: entry, isSouthernHemisphere: isSouthernHemisphere, timeZone: timeZone))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                Text(EventsFormat.dayAndTime(entry.event.date, in: timeZone))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(palette.tertiaryText)
                if let interference = entry.moonInterference {
                    Label(EventsFormat.shortMoonText(interference), systemImage: "moon")
                        .font(.caption)
                        .foregroundStyle(interference.level == .strong ? palette.warning : palette.tertiaryText)
                }
                if let isVisible = entry.isVisibleFromHere {
                    EventsVisibilityBadge(isVisible: isVisible)
                        .padding(.top, 1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.tertiaryText)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// An `EventsRow` that opens the event's detail screen in the enclosing navigation stack.
struct EventsRowLink: View {
    let entry: EventsEntry
    let timeZone: TimeZone
    let isSouthernHemisphere: Bool

    var body: some View {
        NavigationLink(value: entry) {
            EventsRow(entry: entry, timeZone: timeZone, isSouthernHemisphere: isSouthernHemisphere)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EventsFormat.spokenSummary(of: entry, isSouthernHemisphere: isSouthernHemisphere,
                                                       timeZone: timeZone))
        .accessibilityHint("Opens details")
    }
}
