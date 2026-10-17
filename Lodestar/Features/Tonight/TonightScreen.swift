import SwiftUI
import LodestarKit

/// Identifies one computation: another observer, another night or a catalog that has just arrived starts a new one.
private struct TonightTaskKey: Equatable {
    let night: TonightNightKey
    let catalogID: ObjectIdentifier?
}

/// The Tonight tab's content once an observing place is known: the night selector and the cards for the chosen night.
struct TonightScreen: View {
    /// The most nights from tonight the selector reaches in either direction.
    private static let reachInDays = 366

    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let context: ObserverContext

    @State private var choice = TonightNightChoice.tonight
    @State private var report: TonightReport?
    @State private var isShowingDateSheet = false

    var body: some View {
        let taskKey = TonightTaskKey(night: TonightNightKey(context: context, choice: choice),
                                     catalogID: app.catalog.catalog.map(ObjectIdentifier.init))
        ScrollView {
            VStack(spacing: 16) {
                dateBar
                placeLine
                if let report {
                    TonightReportCards(report: report)
                } else {
                    TonightPendingCard()
                }
                TonightPolarCard(observer: context.observer, timeZone: context.timeZone)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        // Some symbols draw themselves in colour by default; night mode allows red only.
        .symbolRenderingMode(.monochrome)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if choice != .tonight {
                    Button("Tonight") { choice = .tonight }
                        .accessibilityHint("Goes back to the night that is under way")
                }
            }
        }
        .sheet(isPresented: $isShowingDateSheet) {
            dateSheet
        }
        .task(id: taskKey) {
            await keepReportFresh(for: taskKey)
        }
    }

    // MARK: Parts

    private var calendar: Calendar { context.calendar }

    /// Local noon of the date of the night under way, before the first report has arrived too.
    private var tonightStart: Date {
        report?.tonightStart ?? TonightCalculator.localNoon(of: Date(), calendar: calendar)
    }

    /// Local noon of the night the selector stands on: the one asked for, else the one shown.
    private var selectedNight: Date? {
        switch choice {
        case .tonight: return report?.nightStart
        case .date(let date): return date
        }
    }

    /// The nights the selector can reach.
    private var reach: ClosedRange<Date> {
        let first = calendar.date(byAdding: .day, value: -Self.reachInDays, to: tonightStart) ?? tonightStart
        let last = calendar.date(byAdding: .day, value: Self.reachInDays, to: tonightStart) ?? tonightStart
        return first...last
    }

    private var dateBar: some View {
        TonightDateBar(
            title: report.map { AppFormat.day($0.nightStart, in: $0.timeZone) } ?? "Tonight",
            subtitle: report.map { TonightFormat.nightLabel(nightsFromTonight: $0.nightsFromTonight) }
                ?? "Working it out",
            canGoBack: canMove(by: -1),
            canGoForward: canMove(by: 1),
            goBack: { move(by: -1) },
            goForward: { move(by: 1) },
            pickDate: { isShowingDateSheet = true })
    }

    /// Where the times are for: the site's name and its time zone.
    private var placeLine: some View {
        let zone = TonightFormat.zoneName(context.timeZone, at: report?.nightStart ?? Date())
        return Label("\(context.name) \u{00B7} times in \(zone)", systemImage: "mappin.and.ellipse")
            .font(.footnote)
            .foregroundStyle(palette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private var dateSheet: some View {
        TonightDateSheet(timeZone: context.timeZone, selected: selectedNight ?? tonightStart,
                         tonight: tonightStart, range: reach) { newChoice in
            apply(newChoice)
        }
        .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
    }

    // MARK: Choosing a night

    private func movedNight(by days: Int) -> Date? {
        guard let selectedNight else { return nil }
        return calendar.date(byAdding: .day, value: days, to: selectedNight)
    }

    private func canMove(by days: Int) -> Bool {
        movedNight(by: days).map { reach.contains($0) } ?? false
    }

    private func move(by days: Int) {
        guard let night = movedNight(by: days), reach.contains(night) else { return }
        apply(.date(night))
    }

    /// Takes the chosen night; tonight's own date means "tonight", which moves on by itself.
    private func apply(_ newChoice: TonightNightChoice) {
        if case .date(let date) = newChoice, calendar.isDate(date, inSameDayAs: tonightStart) {
            choice = .tonight
        } else {
            choice = newChoice
        }
    }

    // MARK: Computing

    /// Works the night out off the main thread. For "tonight" it keeps going: once the night is over the next
    /// one becomes tonight.
    private func keepReportFresh(for key: TonightTaskKey) async {
        repeat {
            let input = TonightInput(key: key.night, now: app.clock.now, catalog: app.catalog.catalog)
            let computed = await Task.detached(priority: .userInitiated) {
                TonightCalculator.report(for: input)
            }.value
            guard !Task.isCancelled else { return }
            report = computed
            guard key.night.choice == .tonight else { return }
            await waitUntil(computed.expiry)
        } while !Task.isCancelled
    }

    /// Returns once `date` has passed (or the task is cancelled), waking at least every quarter of an hour in
    /// case the clock changed. It always sleeps at least a second, so it can never spin.
    private func waitUntil(_ date: Date) async {
        repeat {
            let remaining = date.timeIntervalSince(app.clock.now)
            try? await Task.sleep(for: .seconds(min(max(remaining, 1), 900)))
        } while !Task.isCancelled && app.clock.now < date
    }
}
