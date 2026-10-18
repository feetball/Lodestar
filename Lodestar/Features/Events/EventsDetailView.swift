import SwiftUI
import LodestarKit

/// One astronomical event: what it is, when and where to look from the observer's place, how to photograph it, and the
/// buttons that aim at it or show it in the sky chart.
struct EventsDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let entry: EventsEntry

    @State private var now = Date()

    private var event: AstronomicalEvent { entry.event }

    var body: some View {
        let context = app.observerContext
        let timeZone = context?.timeZone ?? .autoupdatingCurrent
        let isSouthern = (context?.location.latitude ?? 0) < 0
        ScrollView {
            VStack(spacing: 16) {
                EventsHeaderCard(entry: entry, now: now, timeZone: timeZone)
                if case .solarEclipse = event.details {
                    EventsSafetyNotice()
                }
                EventsActionsCard(entry: entry, subjects: EventsCalculator.aimSubjects(of: event, now: now))
                EventsFactsCard(entry: entry, isSouthernHemisphere: isSouthern, timeZone: timeZone)
                EventsWhenCard(entry: entry, timeZone: timeZone, placeName: context?.name)
                EventsContactsCard(entry: entry, timeZone: timeZone)
                EventsGuideCards(guide: EventsGuide.make(for: entry, isSouthernHemisphere: isSouthern))
                if case .meteorShower = event.details {
                    TonightNote(text: "Meteor shower data: International Meteor Organization.", style: .footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .symbolRenderingMode(.monochrome)
        .screenBackground(palette)
        .navigationTitle(event.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            now = app.clock.now
        }
    }
}

// MARK: Header

/// The event's name, its local date and time, and whether it can be seen from here.
private struct EventsHeaderCard: View {
    @Environment(\.palette) private var palette

    let entry: EventsEntry
    let now: Date
    let timeZone: TimeZone

    private var event: AstronomicalEvent { entry.event }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: EventsFormat.symbol(for: event))
                    .font(.system(size: 26, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(palette.accent)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(event.kind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(EventsFormat.fullDateTime(event.date, in: timeZone))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text("\(EventsFormat.countdown(to: event.date, from: now, in: timeZone)) \u{00B7} times in "
                     + EventsFormat.zoneName(timeZone, at: event.date))
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryText)
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    @ViewBuilder
    private var chips: some View {
        if let isVisible = entry.isVisibleFromHere {
            StatusChip(systemImage: isVisible ? "eye" : "eye.slash",
                       text: isVisible ? "Visible from here" : "Not visible from here",
                       tone: isVisible ? .positive : .neutral)
        }
        if let interference = entry.moonInterference {
            StatusChip(systemImage: "moon", text: EventsFormat.shortMoonText(interference),
                       tone: interference.level == .strong ? .warning : .neutral)
        }
    }
}

// MARK: Safety

/// The warning that goes with every solar eclipse, and with aiming at the Sun.
struct EventsSafetyNotice: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Solar filter required", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(palette.warning)
            Text("Never look at the Sun, and never point a camera, binoculars or a telescope at it, without a certified "
                 + "solar filter (ISO 12312-2) fitted over the front of the lens. Even a few seconds can permanently "
                 + "damage your eyes and the camera\u{2019}s sensor.")
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.warning, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Actions

/// "Aim at ..." for each thing the event points at, and "Show in Sky chart".
private struct EventsActionsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let entry: EventsEntry
    let subjects: [EventsCalculator.AimSubject]

    /// The Sun, waiting for the user to confirm that the lens has a solar filter.
    @State private var pendingSun: CelestialObject?

    private var event: AstronomicalEvent { entry.event }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pendingSun {
                solarConfirmation(pendingSun)
            } else {
                ForEach(Array(subjects.enumerated()), id: \.offset) { index, subject in
                    aimButton(subject, isPrimary: index == 0)
                }
                Button {
                    showInSkyChart()
                } label: {
                    Label("Show in Sky chart", systemImage: "circle.dotted.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LodestarButtonStyle(kind: subjects.isEmpty ? .primary : .secondary))
                .accessibilityHint("Opens the Sky tab at the time of the event")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func aimButton(_ subject: EventsCalculator.AimSubject, isPrimary: Bool) -> some View {
        Button {
            aim(at: subject)
        } label: {
            Label("Aim at \(subject.title)", systemImage: "scope")
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LodestarButtonStyle(kind: isPrimary ? .primary : .secondary))
        .disabled(!canAim(at: subject))
    }

    /// The solar-system bodies come from the catalog, which may still be loading; the other targets do not need it.
    private func canAim(at subject: EventsCalculator.AimSubject) -> Bool {
        if case .body = subject { return app.catalog.catalog != nil }
        return true
    }

    private func aim(at subject: EventsCalculator.AimSubject) {
        guard let object = EventsAiming.object(for: subject, in: app.catalog.catalog) else { return }
        if object.category == .sun {
            pendingSun = object
        } else {
            app.aim(at: object)
        }
    }

    private func solarConfirmation(_ sun: CelestialObject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EventsSafetyNotice()
            Button {
                pendingSun = nil
                app.aim(at: sun)
            } label: {
                Text("My lens has a solar filter: aim at the Sun")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarPrimary)
            Button {
                pendingSun = nil
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
        }
    }

    /// Travels the sky chart to the best time of the event, or to the event itself, and opens the Sky tab.
    private func showInSkyChart() {
        app.clock.travel(to: event.visibility?.bestTime ?? event.date)
        app.selectedTab = .sky
    }
}

// MARK: Facts

private struct EventsFactsCard: View {
    @Environment(\.palette) private var palette

    let entry: EventsEntry
    let isSouthernHemisphere: Bool
    let timeZone: TimeZone

    var body: some View {
        let rows = EventsDetailModel.facts(of: entry, isSouthernHemisphere: isSouthernHemisphere, timeZone: timeZone)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "Details", systemImage: "info.circle")
                ForEach(rows) { row in
                    InfoRow(label: row.label, value: row.value)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(palette)
        }
    }
}

// MARK: When

/// The local times of the event and whether the observer can see it.
private struct EventsWhenCard: View {
    @Environment(\.palette) private var palette

    let entry: EventsEntry
    let timeZone: TimeZone
    let placeName: String?

    var body: some View {
        let rows = EventsDetailModel.times(of: entry, timeZone: timeZone)
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: placeName.map { "When, from \($0)" } ?? "When", systemImage: "clock")
            ForEach(rows) { row in
                InfoRow(label: row.label, value: row.value)
            }
            if let sentence = EventsDetailModel.visibilitySentence(of: entry, timeZone: timeZone) {
                TonightNote(text: sentence)
            }
            if let rule = EventsDetailModel.windowRule(of: entry) {
                TonightNote(text: rule, style: .footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }
}

// MARK: Eclipse contacts

/// The contacts of an eclipse with the altitude of the Moon or Sun at each; contacts below the horizon are dimmed.
private struct EventsContactsCard: View {
    @Environment(\.palette) private var palette

    let entry: EventsEntry
    let timeZone: TimeZone

    private var subject: String {
        if case .solarEclipse = entry.event.details { return "Sun" }
        return "Moon"
    }

    var body: some View {
        let contacts = EventsDetailModel.contacts(of: entry)
        if !contacts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "Timeline", systemImage: "list.bullet.clipboard")
                ForEach(contacts) { contact in
                    if contact.id != contacts.first?.id {
                        TonightRowSeparator()
                    }
                    row(contact)
                }
                TonightNote(text: "Contacts are for a flat horizon. Those with the \(subject) below the horizon cannot "
                            + "be seen.", style: .footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(palette)
        }
    }

    private func row(_ contact: EventsContactRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(contact.name)
                .font(.subheadline)
                .foregroundStyle(contact.isBelowHorizon ? palette.tertiaryText : palette.primaryText)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(AppFormat.time(contact.time, in: timeZone))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(contact.isBelowHorizon ? palette.tertiaryText : palette.primaryText)
                Text(altitudeText(contact))
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryText)
            }
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(contact.name), \(AppFormat.time(contact.time, in: timeZone)), \(spokenAltitude(contact))")
    }

    private func altitudeText(_ contact: EventsContactRow) -> String {
        contact.isBelowHorizon ? "\(subject) below the horizon"
                               : "\(subject) \(EventsDetailModel.position(altitude: contact.altitude, azimuth: contact.azimuth))"
    }

    private func spokenAltitude(_ contact: EventsContactRow) -> String {
        contact.isBelowHorizon ? "\(subject) below the horizon, cannot be seen"
                               : "\(subject) \(EventsDetailModel.position(altitude: contact.altitude, azimuth: contact.azimuth))"
    }
}

// MARK: Guide

/// What the event is, why to photograph it, and tips.
private struct EventsGuideCards: View {
    @Environment(\.palette) private var palette

    let guide: EventsGuide

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "What it is", systemImage: "text.book.closed")
                paragraph(guide.about)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(palette)
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "Photographing it", systemImage: "camera")
                paragraph(guide.why)
                ForEach(Array(guide.tips.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .foregroundStyle(palette.accent)
                            .accessibilityHidden(true)
                        paragraph(tip)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(palette)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(palette.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
