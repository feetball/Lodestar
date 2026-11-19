import SwiftUI
import LodestarKit

/// Tools ▸ Alignment Finder: when does the Milky Way core, the Moon, the Sun or an object stand over a ridge or in a
/// gap between trees? The user picks the target, where it should stand (a point of the recorded skyline or a window of
/// azimuth and altitude) and the period, and gets the matching stretches of each night, with the sky chart at that time
/// and, for tonight, Aim.
///
/// Push it inside a navigation stack (Settings ▸ Tools). The inputs are kept while another tab is shown.
struct AlignmentFinderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var inputs = AlignmentFinderInputs()
    /// The search runs from the night that was current when the screen opened.
    @State private var openedAt = Date()
    /// Nil while a search is under way.
    @State private var outcome: AlignmentFinderOutcome?
    @State private var isChoosingObject = false

    /// Pause before searching after an input changes, so holding a stepper does not search for every step.
    private static let searchDelay: Duration = .milliseconds(300)
    /// The lowest altitude a window may start at, in degrees: a little below the horizon, for a skyline that dips.
    private static let lowestAltitude = -10
    private static let azimuthSteps = 360

    var body: some View {
        let context = app.observerContext
        let request = context.flatMap { inputs.request(for: $0, now: openedAt) }
        Group {
            if let context {
                form(context: context, request: request)
            } else {
                NeedsLocationView()
                    .background(palette.background)
            }
        }
        .navigationTitle(AlignmentFinderText.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) {
            await search(request)
        }
        .sheet(isPresented: $isChoosingObject) {
            AlignmentFinderObjectSheet(chosen: inputs.chosenObject) { inputs.choose($0) }
                .presentationDetents([.medium, .large])
                .sheetDragIndicator(app.palette)
        }
    }

    private func form(context: ObserverContext, request: AlignmentFinderRequest?) -> some View {
        Form {
            Section {
                Text(AlignmentFinderText.intro)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(Color.clear)
            whatSection
            whereSection(skyline: AlignmentFinderRequest.skyline(of: context))
            whenSection
            AlignmentFinderResults(inputs: inputs, request: request, outcome: outcome, openedAt: openedAt,
                                   timeZone: context.timeZone)
        }
        .themedList(palette)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Runs the search for `request` once the inputs have settled, off the main thread.
    private func search(_ request: AlignmentFinderRequest?) async {
        outcome = nil
        guard let request else { return }
        try? await Task.sleep(for: Self.searchDelay)
        guard !Task.isCancelled else { return }
        let result = await Task.detached(priority: .userInitiated) { AlignmentFinderSearch.run(request) }.value
        guard !Task.isCancelled else { return }
        outcome = result
    }

    // MARK: What

    private var whatSection: some View {
        let selection = Binding<AlignmentFinderWhat>(
            get: { inputs.what },
            set: { what in
                if what == .object && inputs.chosenObject == nil {
                    isChoosingObject = true
                } else {
                    inputs.choose(what)
                }
            })
        let options = AlignmentFinderWhat.allCases.map { what in
            SettingsMenuOption(title: what == .object ? (inputs.chosenObject?.name ?? what.title) : what.title,
                               value: what)
        }
        return SettingsSection(title: "What") {
            SettingsMenuPicker(title: "Target", selection: selection, options: options)
            if inputs.what == .object {
                Button {
                    isChoosingObject = true
                } label: {
                    Label(inputs.chosenObject == nil ? "Choose object\u{2026}" : "Change object\u{2026}",
                          systemImage: "magnifyingglass")
                }
            }
        }
    }

    // MARK: Where

    private func whereSection(skyline: HorizonProfile?) -> some View {
        var footer: String? = AlignmentFinderText.windowFooter
        if inputs.place == .skyline { footer = skyline == nil ? nil : AlignmentFinderText.skylineFooter }
        return SettingsSection(title: "Where", footer: footer) {
            Picker("Where", selection: $inputs.place) {
                ForEach(AlignmentFinderPlace.allCases) { place in
                    Text(place.title).tag(place)
                }
            }
            .pickerStyle(.segmented)
            switch inputs.place {
            case .skyline: skylineRows(skyline)
            case .window: windowRows
            }
        }
    }

    @ViewBuilder
    private func skylineRows(_ skyline: HorizonProfile?) -> some View {
        if let skyline {
            AlignmentFinderSkylinePicker(profile: skyline, azimuth: $inputs.skylineAzimuth,
                                         tolerance: inputs.skylineTolerance)
            SettingsNumberField(title: "Azimuth", unit: "\u{00B0}", value: azimuthBinding($inputs.skylineAzimuth),
                                range: 0...Double(Self.azimuthSteps - 1), fractionDigits: 0)
            InfoRow(label: "Skyline there",
                    value: "\(AlignmentFinderText.altitude(skyline.altitude(at: Double(inputs.skylineAzimuth)))) \u{00B7} "
                        + AlignmentFinderText.direction(inputs.skylineAzimuth))
            stepper("Tolerance", valueText: "\u{00B1} \(inputs.skylineTolerance)\u{00B0}", value: $inputs.skylineTolerance,
                    in: 1...AlignmentFinderInputs.skylineToleranceMaximum)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(AlignmentFinderText.noSkylineTitle)
                    .font(.body.weight(.semibold))
                SettingsCaption(AlignmentFinderText.noSkyline)
            }
        }
    }

    @ViewBuilder
    private var windowRows: some View {
        SettingsNumberField(title: "Azimuth centre", unit: "\u{00B0}", value: azimuthBinding($inputs.windowAzimuth),
                            range: 0...Double(Self.azimuthSteps - 1), fractionDigits: 0)
        InfoRow(label: "Direction", value: AlignmentFinderText.direction(inputs.windowAzimuth))
        stepper("Width", valueText: "\u{00B1} \(inputs.windowTolerance)\u{00B0}", value: $inputs.windowTolerance,
                in: 1...AlignmentFinderInputs.windowToleranceMaximum)
        stepper("Lowest altitude", valueText: "\(inputs.minimumAltitude)\u{00B0}", value: $inputs.minimumAltitude,
                in: Self.lowestAltitude...inputs.maximumAltitude)
        stepper("Highest altitude", valueText: "\(inputs.maximumAltitude)\u{00B0}", value: $inputs.maximumAltitude,
                in: inputs.minimumAltitude...90)
    }

    // MARK: When

    private var whenSection: some View {
        SettingsSection(title: "When", footer: inputs.moon == .dim ? AlignmentFinderText.dimFooter : nil) {
            Picker("Period", selection: $inputs.range) {
                ForEach(AlignmentFinderRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            SettingsMenuPicker(title: "Darkness", selection: $inputs.darkness,
                               options: AlignmentFinderDarkness.allCases.map { SettingsMenuOption(title: $0.title, value: $0) })
            SettingsMenuPicker(title: "Moon", selection: $inputs.moon,
                               options: AlignmentFinderMoon.allCases.map { SettingsMenuOption(title: $0.title, value: $0) })
            if inputs.moon == .dim {
                Stepper(value: $inputs.dimPercent, in: 5...95, step: 5) {
                    stepperLabel("At most lit", valueText: "\(inputs.dimPercent)%")
                }
                .accessibilityValue("\(inputs.dimPercent)%")
            }
        }
    }

    // MARK: Controls

    /// A whole number of degrees as the number field's value; it wraps into 0…359.
    private func azimuthBinding(_ degrees: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(degrees.wrappedValue) },
                set: { degrees.wrappedValue = Int($0.rounded()) % Self.azimuthSteps })
    }

    private func stepper(_ title: String, valueText: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            stepperLabel(title, valueText: valueText)
        }
        .accessibilityValue(valueText)
    }

    private func stepperLabel(_ title: String, valueText: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(valueText)
                .monospacedDigit()
                .foregroundStyle(palette.secondaryText)
        }
    }
}

// MARK: Results

/// The results of the search: the nights with their matches, or why there are none.
private struct AlignmentFinderResults: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let inputs: AlignmentFinderInputs
    let request: AlignmentFinderRequest?
    let outcome: AlignmentFinderOutcome?
    let openedAt: Date
    let timeZone: TimeZone

    /// The matches that have not ended, grouped by night.
    private struct Night: Identifiable {
        let night: DateInterval
        let matches: [SkyWindowMatch]
        var id: Date { night.start }
    }

    var body: some View {
        if let request {
            switch outcome {
            case nil:
                SettingsSection(title: "Results") {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(AlignmentFinderText.searching)
                            .foregroundStyle(palette.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            case .failed(let message)?:
                SettingsSection(title: "Results") { SettingsCaption(message) }
            case .empty(let reason)?:
                SettingsSection(title: "Results") {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(palette.tertiaryText)
                            .accessibilityHidden(true)
                        Text(AlignmentFinderText.emptyTitle(reason, for: request))
                            .font(.headline)
                        Text(AlignmentFinderText.emptyMessage(reason, for: request, days: inputs.range.days))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            case .found(let matches, let isCutShort)?:
                found(matches, isCutShort: isCutShort)
            }
        } else {
            SettingsSection(title: "Results") { SettingsCaption(needsText) }
        }
    }

    private var needsText: String {
        if inputs.target == nil { return AlignmentFinderText.needsObject }
        if inputs.place == .skyline { return AlignmentFinderText.noSkyline }
        return AlignmentFinderText.needsLocation
    }

    @ViewBuilder
    private func found(_ matches: [SkyWindowMatch], isCutShort: Bool) -> some View {
        let aimObject = inputs.aimObject { app.catalog.object(id: $0) }
        ForEach(nights(of: matches)) { night in
            SettingsSection(title: AlignmentFinderText.nightHeader(night.night, in: timeZone)) {
                ForEach(night.matches, id: \.interval.start) { match in
                    AlignmentFinderMatchRow(match: match, timeZone: timeZone, openedAt: openedAt, aimObject: aimObject)
                }
            }
        }
        Section {
            if isCutShort { SettingsCaption(AlignmentFinderText.cutShort) }
            SettingsCaption(AlignmentFinderText.pastNote)
            if inputs.followsSun { SettingsCaption(AlignmentFinderText.sunNote) }
        }
        .listRowBackground(Color.clear)
    }

    private func nights(of matches: [SkyWindowMatch]) -> [Night] {
        var nights = [Night]()
        for match in matches where match.interval.end >= openedAt {
            if let last = nights.last, last.night.start == match.night.start {
                nights[nights.count - 1] = Night(night: last.night, matches: last.matches + [match])
            } else {
                nights.append(Night(night: match.night, matches: [match]))
            }
        }
        return nights
    }
}

/// One match: when, where in the sky and what the Moon does, with the sky chart at that time and, tonight, Aim.
private struct AlignmentFinderMatchRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let match: SkyWindowMatch
    let timeZone: TimeZone
    let openedAt: Date
    let aimObject: CelestialObject?

    private var isTonight: Bool {
        match.night.start <= openedAt && openedAt < match.night.end && match.interval.end > openedAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AlignmentFinderText.rowTitle(match, in: timeZone))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text(AlignmentFinderText.rowDetail(match))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                if !match.isAboveSkyline {
                    Text(AlignmentFinderText.behindSkyline)
                        .font(.subheadline)
                        .foregroundStyle(palette.warning)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AlignmentFinderText.rowDescription(match, in: timeZone))
            HStack(spacing: 8) {
                Button {
                    app.clock.travel(to: match.midpoint)
                    app.selectedTab = .sky
                } label: {
                    Label("Sky chart at that time", systemImage: "circle.dotted.circle")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarSecondary)
                if isTonight, let aimObject {
                    Button {
                        app.aim(at: aimObject)
                    } label: {
                        Label("Aim", systemImage: "scope")
                    }
                    .buttonStyle(.lodestarPrimary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
