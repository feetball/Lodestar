import SwiftUI
import LodestarKit

/// Plans a mosaic and starts it: the area to cover (the target, the Milky Way arch or a custom rectangle), the overlap,
/// how the camera is held and the lens from Settings, with the resulting grid, panel count and warnings. While a mosaic
/// is running its progress is shown on top, and the plan below can replace it ("Restart with this plan").
struct AimMosaicSheet: View {
    let model: AimViewModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// The areas a mosaic can cover.
    private enum SourceChoice: String, CaseIterable, Identifiable {
        case target, milkyWay, custom

        var id: String { rawValue }
    }

    @State private var chosenSource: SourceChoice?
    @State private var overlapPercent = MosaicPlanner.defaultOverlap * 100
    /// The photographer's choice of orientation; `nil` follows the planner's recommendation.
    @State private var chosenOrientation: MosaicOrientation?
    @State private var customWidth = 30.0
    @State private var customHeight = 20.0
    /// Where the camera pointed when the sheet opened (or was told to take it again): the centre of a custom area.
    @State private var customCenter: HorizontalCoordinate?
    /// The instant the Milky Way arch is worked out for.
    @State private var snapshotDate = Date()
    @State private var result: Result<AimMosaicPlanResult, AimMosaicProblem>?
    @State private var isPlanning = false

    /// Pause before planning after an input changes, so dragging a slider does not plan for every step.
    private static let planningDelay: Duration = .milliseconds(150)
    private static let overlapRangePercent = (MosaicPlanner.overlapRange.lowerBound * 100)...(MosaicPlanner.overlapRange.upperBound * 100)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.mosaicSession.isActive {
                        runningCard
                    }
                    plannerContent
                }
                .padding(16)
            }
            footer
        }
        .background(palette.background)
        .foregroundStyle(palette.primaryText)
        .tint(palette.accent)
        .presentationBackground(palette.background)
        .onAppear {
            snapshotDate = app.clock.now
            takeCurrentPointing()
        }
        .task(id: request) {
            await plan()
        }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack {
            Text("Mosaic")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.lodestarSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                start()
            } label: {
                Label(model.mosaicSession.isActive ? "Restart with this plan" : "Start",
                      systemImage: model.mosaicSession.isActive ? "arrow.counterclockwise" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarPrimary)
            .disabled(planResult == nil || isPlanning)
            Text("Lodestar then steers to each panel in turn and tells you how far to rotate the camera.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
    }

    // MARK: Running

    private var runningCard: some View {
        let session = model.mosaicSession
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "In progress", systemImage: "square.grid.3x3")
            Text(session.title)
                .font(.title3.weight(.semibold))
            Text(session.progressText)
                .font(.headline)
                .foregroundStyle(palette.accent)
            if let plan = session.plan {
                Text(AimMosaicPlanner.gridText(plan))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            if let position = session.positionText {
                Text(position)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            Button {
                model.finishMosaic()
            } label: {
                Label("Finish mosaic", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
        .accessibilityElement(children: .contain)
    }

    // MARK: Planner

    @ViewBuilder
    private var plannerContent: some View {
        sourceCard
        if source == .custom { customCard }
        settingsCard
        summaryCard
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardTitle(title: "Cover", systemImage: "viewfinder")
            sourceRow(.target, title: "Fit target", systemImage: "scope",
                      detail: fitProblem == nil ? "\(app.target?.name ?? "The target"), with a 20% margin" : nil,
                      problem: fitProblem)
            sourceRow(.milkyWay, title: "Milky Way arch panorama", systemImage: "sparkles",
                      detail: "The arch above the horizon right now, edge to edge.", problem: nil)
            sourceRow(.custom, title: "Custom size", systemImage: "rectangle.dashed",
                      detail: "A rectangle centered where the camera points.", problem: nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func sourceRow(_ choice: SourceChoice, title: String, systemImage: String, detail: String?,
                           problem: String?) -> some View {
        let isSelected = source == choice
        return Button {
            chosenSource = choice
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    if let problem {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(palette.warning)
                    } else if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(problem == nil ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(problem != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(problem ?? detail ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(problem == nil ? "Covers this area with the mosaic." : "Not available.")
    }

    private var customCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Custom size", systemImage: "rectangle.dashed")
            AimMosaicSliderRow(title: "Width", valueText: AngleFormatter.formatDegrees(customWidth, decimals: 0),
                               value: $customWidth, range: AimMosaicPlanner.customWidthRange, step: 1)
            AimMosaicSliderRow(title: "Height", valueText: AngleFormatter.formatDegrees(customHeight, decimals: 0),
                               value: $customHeight, range: AimMosaicPlanner.customHeightRange, step: 1)
            if let customCenter {
                Text("Centered on \(AppFormat.azimuth(customCenter.azimuth)), altitude \(AppFormat.altitude(customCenter.altitude)).")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text("Waiting for the motion sensors to know where the camera points.")
                    .font(.footnote)
                    .foregroundStyle(palette.warning)
            }
            Button {
                takeCurrentPointing()
            } label: {
                Label("Use where the camera points now", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Shots", systemImage: "slider.horizontal.3")
            AimMosaicSliderRow(title: "Overlap", valueText: "\(Int(overlapPercent.rounded()))%", value: $overlapPercent,
                               range: Self.overlapRangePercent, step: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text("Camera held in")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                Picker("Camera orientation", selection: orientationBinding) {
                    ForEach(MosaicOrientation.allCases, id: \.self) { orientation in
                        Text(AimMosaicPlanner.name(of: orientation)).tag(orientation)
                    }
                }
                .pickerStyle(.segmented)
                if let recommendation {
                    Text(recommendation)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            lensRows
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private var lensRows: some View {
        let setup = app.lensSetup
        let frame = setup.fieldOfView
        return VStack(alignment: .leading, spacing: 6) {
            InfoRow(label: "Lens", value: "\(setup.focalLengthMillimeters.formatted(.number.precision(.fractionLength(0...1)))) mm \u{00B7} \(setup.sensor.name)")
            InfoRow(label: "Frame", value: "\(AngleFormatter.formatDegrees(frame.horizontal, decimals: 1)) \u{00D7} \(AngleFormatter.formatDegrees(frame.vertical, decimals: 1))")
            Text("The lens comes from Settings.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "Plan", systemImage: "square.grid.3x3")
            switch result {
            case .success(let planned)?:
                planRows(planned)
            case .failure(let problem)?:
                Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.warning)
            case nil:
                if isPlanning || request != nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(palette.accent)
                        Text("Planning\u{2026}")
                            .foregroundStyle(palette.secondaryText)
                    }
                } else {
                    Text(source == .custom ? "Waiting for the camera\u{2019}s direction." : "Choose what to cover.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func planRows(_ planned: AimMosaicPlanResult) -> some View {
        let plan = planned.plan
        InfoRow(label: "Rows \u{00D7} columns", value: rowsByColumnsText(plan))
        InfoRow(label: "Panels", value: "\(plan.panelCount)")
        InfoRow(label: "Covers", value: "\(AngleFormatter.formatDegrees(plan.coverage.widthDegrees, decimals: 0)) \u{00D7} \(AngleFormatter.formatDegrees(plan.coverage.heightDegrees, decimals: 0))")
        InfoRow(label: "Panel", value: "\(AngleFormatter.formatDegrees(plan.frame.horizontal, decimals: 1)) \u{00D7} \(AngleFormatter.formatDegrees(plan.frame.vertical, decimals: 1)) as held")
        InfoRow(label: "Overlap", value: overlapText(plan))
        if let first = plan.orderedPanels.first {
            InfoRow(label: "Starts at", value: "Row \(first.row + 1), column \(first.column + 1)")
        }
        ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
            Label(AimMosaicPlanner.text(for: warning), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.warning)
        }
    }

    /// "2 \u{00D7} 3", or "3 \u{00D7} up to 4" when the rows differ in length.
    private func rowsByColumnsText(_ plan: MosaicPlan) -> String {
        plan.isRectangular ? "\(plan.rows) \u{00D7} \(plan.columns)" : "\(plan.rows) \u{00D7} up to \(plan.columns)"
    }

    private func overlapText(_ plan: MosaicPlan) -> String {
        let requested = AppFormat.percent(plan.overlap)
        guard let achieved = plan.achievedOverlap, achieved - plan.overlap >= 0.01 else { return requested }
        return "\(requested) (\(AppFormat.percent(achieved)) achieved)"
    }

    // MARK: State

    /// The area chosen, or the first one that works.
    private var source: SourceChoice {
        switch chosenSource {
        case .target?: return fitProblem == nil ? .target : .custom
        case let choice?: return choice
        case nil: return fitProblem == nil ? .target : .custom
        }
    }

    /// Why the target cannot be fitted, or `nil` when it can.
    private var fitProblem: String? { AimMosaicPlanner.fitProblem(for: app.target) }

    private var planResult: AimMosaicPlanResult? {
        if case .success(let planned)? = result { return planned }
        return nil
    }

    /// The segmented control shows the orientation of the plan (the recommendation until the person chooses).
    private var orientationBinding: Binding<MosaicOrientation> {
        Binding(get: { chosenOrientation ?? planResult?.plan.orientation ?? .landscape },
                set: { chosenOrientation = $0 })
    }

    private var recommendation: String? {
        guard let planned = planResult else { return nil }
        let name = AimMosaicPlanner.name(of: planned.recommendedOrientation)
        return planned.plan.orientation == planned.recommendedOrientation
            ? "Best for this area: \(name)."
            : "\(name) needs fewer panels for this area."
    }

    /// What the planner is asked for, or `nil` when it cannot be asked yet.
    private var request: AimMosaicRequest? {
        guard let context = app.observerContext else { return nil }
        let planSource: AimMosaicRequest.Source
        switch source {
        case .target:
            guard let target = app.target else { return nil }
            planSource = .target(target)
        case .milkyWay:
            planSource = .milkyWayArch
        case .custom:
            guard let customCenter else { return nil }
            planSource = .custom(width: customWidth, height: customHeight, center: customCenter)
        }
        return AimMosaicRequest(source: planSource, overlap: overlapPercent / 100, orientation: chosenOrientation,
                                frame: app.lensSetup.fieldOfView, observer: context.observer, date: snapshotDate)
    }

    // MARK: Actions

    /// Plans for the current request off the main actor; restarted whenever the request changes.
    private func plan() async {
        guard let request else {
            result = nil
            isPlanning = false
            return
        }
        isPlanning = true
        try? await Task.sleep(for: Self.planningDelay)
        guard !Task.isCancelled else { return }
        let planned = await Task.detached(priority: .userInitiated) {
            AimMosaicPlanner.plan(for: request)
        }.value
        guard !Task.isCancelled else { return }
        result = planned
        isPlanning = false
    }

    /// Takes the direction the camera points in as the centre of a custom area.
    private func takeCurrentPointing() {
        if let frame = model.engine.frame() {
            customCenter = frame.pointing.boresight
            // The centre is an altitude and azimuth of this instant, and the planner turns it into sky coordinates
            // with `snapshotDate`: it has to be the same instant, or the centre is off by the sky's turn since.
            snapshotDate = app.clock.now
        } else if customCenter == nil, let target = model.skyContent?.snapshot.target {
            customCenter = target.horizontal
        }
    }

    private func start() {
        guard let planned = planResult else { return }
        model.startMosaic(plan: planned.plan, title: planned.title)
        dismiss()
    }
}

/// A slider with its title and current value on one line; VoiceOver reads the value text.
private struct AimMosaicSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityHidden(true)
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            .tint(palette.accent)
            .accessibilityValue(valueText)
        }
    }
}
