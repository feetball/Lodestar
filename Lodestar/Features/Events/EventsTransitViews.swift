import SwiftUI
import UIKit
import LodestarKit

// MARK: Section of the calendar

/// "ISS transits of the Sun and Moon" in the calendar: the next transits within 50 km, each a row that opens its detail.
/// Without the satellite feed or with orbit data too old it is a one-line hint with a button to Online Data.
struct EventsTransitCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let context: ObserverContext
    let now: Date
    @State private var model = EventsTransitModel.shared

    /// What starts a search: the data, the place and the hour.
    private struct SearchKey: Equatable {
        let generation: Int
        let isOn: Bool
        let context: ObserverContext
        let hour: Int
    }

    var body: some View {
        let online = app.online
        let isOn = online.isEnabled(.satellites)
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: EventsTransitText.title, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            switch EventsTransits.availability(isFeedOn: isOn, library: online.satellites, at: now) {
            case .off: hint(EventsTransitText.offHint)
            case .needsData: hint(EventsTransitText.dataHint)
            case .ready: transits
            }
            TonightNote(text: SatelliteText.attribution, style: .footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
        .task(id: SearchKey(generation: online.satellites.generation, isOn: isOn, context: context,
                            hour: Int(now.timeIntervalSince1970 / 3_600))) {
            search()
        }
    }

    /// Starts the search for the current data, or forgets the transits when there is none to search with.
    private func search() {
        let online = app.online
        let satellites = EventsTransits.satellites(in: online.satellites, at: now)
        if online.isEnabled(.satellites), !satellites.isEmpty {
            model.refresh(satellites: satellites, observer: context.observer, now: now)
        } else {
            model.clear()
        }
    }

    private func hint(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TonightNote(text: text)
            Button {
                app.selectedTab = .settings
            } label: {
                Text(EventsTransitText.onlineData).frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
        }
    }

    @ViewBuilder
    private var transits: some View {
        if let items = model.items {
            let upcoming = EventsTransits.upcoming(items, now: now)
            if upcoming.isEmpty {
                TonightNote(text: EventsTransitText.none)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { TonightRowSeparator() }
                        EventsTransitRowLink(item: item, timeZone: context.timeZone)
                    }
                }
                TonightNote(text: EventsTransitText.note, style: .footnote)
            }
        } else {
            TonightNote(text: EventsTransitText.finding)
        }
    }
}

/// One transit that opens its detail screen in the enclosing navigation stack.
private struct EventsTransitRowLink: View {
    @Environment(\.palette) private var palette

    let item: EventsTransitItem
    let timeZone: TimeZone

    var body: some View {
        NavigationLink(value: item) {
            HStack(spacing: 12) {
                Image(systemName: item.transit.body == .sun ? "sun.max" : "moon")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 29, height: 29)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(EventsTransitText.title(item))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(EventsTransitText.rowDetail(item, in: timeZone))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(item.satelliteName)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EventsTransitText.spokenRow(item, in: timeZone))
        .accessibilityHint("Opens details")
    }
}

// MARK: Detail

/// Everything about one transit: when and where in the sky, how long it lasts, how big the satellite looks, where the
/// centreline is (with a button that copies its coordinates), how to expose, and a button to aim at the Sun or the Moon.
struct EventsTransitDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let item: EventsTransitItem

    /// The Sun, waiting for the user to confirm that the lens has a solar filter.
    @State private var isConfirmingSun = false
    @State private var didCopy = false

    private var transit: SatelliteTransit { item.transit }
    private var isSun: Bool { transit.body == .sun }
    private var timeZone: TimeZone { app.observerContext?.timeZone ?? .autoupdatingCurrent }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if isSun { EventsSafetyNotice() }
                transitCard
                centrelineCard
                exposureCard
                aimCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .symbolRenderingMode(.monochrome)
        .screenBackground(palette)
        .navigationTitle(EventsTransitText.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(EventsTransitText.title(item)) \u{00B7} \(item.satelliteName)")
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text("\(AppFormat.day(transit.date, in: timeZone)) \u{00B7} \(EventsTransitText.time(item, in: timeZone))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var transitCard: some View {
        let body = EventsTransitText.bodyName(transit.body)
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: EventsTransitText.detailTitle, systemImage: "clock")
            InfoRow(label: "\(body) altitude", value: AngleFormatter.formatDegrees(transit.bodyAltitude, decimals: 1))
            InfoRow(label: "\(body) azimuth", value: AppFormat.azimuth(transit.bodyAzimuth))
            InfoRow(label: "Sky", value: EventsTransitText.sky(isDaylight: transit.isDaylight, isNight: transit.isNight))
            InfoRow(label: "Seen from here",
                    value: EventsTransitText.fromHere(isFromSite: transit.isFromSite, separation: transit.minimumSeparation,
                                                      bodyRadius: transit.bodyAngularRadius))
            if transit.isFromSite {
                InfoRow(label: "Crossing here", value: EventsTransitText.duration(transit.siteDurationSeconds))
            }
            InfoRow(label: "Longest crossing", value: EventsTransitText.duration(transit.centrelineDurationSeconds))
            InfoRow(label: "Satellite size",
                    value: EventsTransitText.size(catalogNumber: transit.catalogNumber, angularSize: transit.satelliteAngularSize))
            InfoRow(label: "Satellite range", value: EventsTransitText.range(transit.satelliteRangeKilometers))
            if !item.hasFreshElements {
                TonightNote(text: EventsTransitText.approximateNote, style: .footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private var centrelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: EventsTransitText.centrelineTitle, systemImage: "location.north.line")
            if let centreline = transit.centreline {
                let coordinates = EventsTransitText.coordinates(centreline.location)
                InfoRow(label: "Distance", value: EventsTransitText.distance(centreline.distanceMeters))
                InfoRow(label: "Direction", value: EventsTransitText.bearing(centreline.bearing))
                InfoRow(label: "Coordinates", value: coordinates)
                Button {
                    UIPasteboard.general.string = coordinates
                    didCopy = true
                } label: {
                    Label(didCopy ? EventsTransitText.copied : EventsTransitText.copy, systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarSecondary)
                TonightNote(text: transit.isFromSite ? EventsTransitText.fromHereNote : EventsTransitText.centrelineNote,
                            style: .footnote)
            } else {
                TonightNote(text: EventsTransitText.noCentreline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private var exposureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: EventsTransitText.exposureTitle, systemImage: "camera")
            Text(isSun ? EventsTransitText.exposureSun : EventsTransitText.exposureMoon)
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    /// The Sun or the Moon from the catalog, which may still be loading.
    private var target: CelestialObject? {
        app.catalog.catalog?.object(id: EventsAiming.identifier(of: transit.body))
    }

    private var aimCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isConfirmingSun, let sun = target {
                Button {
                    isConfirmingSun = false
                    app.aim(at: sun)
                } label: {
                    Text("My lens has a solar filter: aim at the Sun")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarPrimary)
                Button {
                    isConfirmingSun = false
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarSecondary)
            } else {
                Button {
                    guard let object = target else { return }
                    if isSun { isConfirmingSun = true } else { app.aim(at: object) }
                } label: {
                    Label(EventsTransitText.aimLabel(transit.body), systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarPrimary)
                .disabled(target == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }
}
