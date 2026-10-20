import SwiftUI
import LodestarKit

/// "Satellite passes" on the Tonight screen: the next visible passes of the night shown, the ISS first, each with its time,
/// peak height and direction and brightness. Appears only while the Satellite passes feed is on; it opens the Passes
/// screen and the pass details. `night` is the Tonight screen's own night (sunset to sunrise).
struct TonightSatelliteCard: View {
    let observer: Observer
    let night: DateInterval
    let timeZone: TimeZone
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var board = SatellitePassBoard()

    /// The most passes the card lists.
    private static let limit = 4

    var body: some View {
        let online = app.online
        if online.isEnabled(.satellites) {
            // The card moves on once a minute, not with the clock's second.
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                content(now: timeline.date)
            }
            .task(id: SatelliteBoardKey(generation: online.satellites.generation, observer: observer, isOn: true)) {
                await board.keepCurrent(app: app, observer: observer)
            }
        }
    }

    private func content(now: Date) -> some View {
        let online = app.online
        let library = online.satellites
        let status = online.status(.satellites)
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: SatelliteText.cardTitle, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            if !library.hasPassData {
                TonightNote(text: status.isUpdating || status.error == nil ? SatelliteText.loading : (status.error ?? ""))
            } else if let items = board.items {
                passes(items, library: library, now: now)
            } else {
                TonightNote(text: SatelliteText.finding)
            }
            if library.hasPassData {
                NavigationLink {
                    SatellitePassesView(board: board)
                } label: {
                    Text(SatelliteText.allPasses).frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarSecondary)
            }
            TonightNote(text: SatelliteText.attribution, style: .footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    @ViewBuilder
    private func passes(_ items: [SatellitePassItem], library: SatelliteLibrary, now: Date) -> some View {
        if night.end <= now {
            TonightNote(text: SatelliteText.nightOver)
        } else if night.start > now.addingTimeInterval(Double(SatellitePasses.horizonDays) * 86_400) {
            TonightNote(text: SatelliteText.tooFar)
        } else {
            let list = SatellitePasses.tonight(items, night: night, now: now, limit: Self.limit)
            if list.isEmpty {
                TonightNote(text: SatelliteText.noPassesTonight)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { TonightRowSeparator() }
                        NavigationLink {
                            SatellitePassDetailView(item: item)
                        } label: {
                            SatellitePassRow(item: item, timeZone: timeZone, now: now, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if library.isPassDataStale(at: now) {
                TonightNote(text: SatelliteText.stale, style: .warning)
            }
        }
    }
}

/// One pass: the satellite and its brightness over the visible time, the peak and a tag when its orbit data is old.
struct SatellitePassRow: View {
    let item: SatellitePassItem
    let timeZone: TimeZone
    let now: Date
    var showsChevron = false
    @Environment(\.palette) private var palette

    var body: some View {
        let isFresh = item.isFresh(at: now)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    Spacer(minLength: 8)
                    Text(SatelliteText.magnitude(item))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryText)
                }
                Text("\(SatelliteText.span(item, in: timeZone)) \u{00B7} \(SatelliteText.peak(item.peak))"
                     + (isFresh ? "" : " \u{00B7} \(SatelliteText.staleTag)"))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isFresh ? palette.secondaryText : palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
