import SwiftUI
import LodestarKit

/// Star alignment: the person centres a bright reference object in the camera and syncs, which teaches the app the
/// compass error and how the phone sits on the camera. The sheet shows what the alignment has found so far.
///
/// The chosen object becomes the guidance target while the sheet is open, so the arrows lead to it; the real target
/// is back when the sheet closes. The sheet is small by default and leaves the sky behind it usable.
struct AlignmentSheet: View {
    let model: AimViewModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [AimAlignmentCandidate] = []
    @State private var rows: [AimAlignmentRow] = []
    @State private var selected: AimAlignmentCandidate?
    @State private var notice: AimAlignmentNotice?
    /// Whether the sync also tells a connected GoTo mount that it points at the object.
    @State private var syncsMount = true

    /// Seconds between the refreshes of the candidates' positions and of their order.
    private static let candidateRefreshInterval = 30.0
    private static let sortInterval = 2.5

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    explanation
                    if let notice {
                        noticeBanner(notice)
                    }
                    if let selected {
                        AimReferenceCard(model: model, candidate: selected)
                    } else {
                        candidateList
                    }
                    AimAlignmentSummaryCard(alignment: app.alignment, onRemove: remove(at:), onReset: reset)
                }
                .padding(16)
            }
            footer
        }
        .background(palette.background)
        .foregroundStyle(palette.primaryText)
        .presentationBackground(palette.background)
        .task(id: app.observerContext?.observer) {
            await refreshCandidates()
        }
        .task {
            await keepRowsSorted()
        }
        .onDisappear {
            model.alignmentTarget = nil
        }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack {
            Text("Align on a star")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HelpButton(topic: .alignment, appearance: .inline)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.lodestarSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// The sync button, always in reach.
    private var footer: some View {
        VStack(spacing: 8) {
            if let selected {
                MountAlignmentSyncRow(isOn: $syncsMount, objectName: selected.object.name)
                Button {
                    sync()
                } label: {
                    Label("Centered \u{2014} Sync", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarPrimary)
                Button("Choose another object") { deselect() }
                    .buttonStyle(.lodestarSecondary)
            } else {
                Text("Choose a bright star or planet from the list.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
    }

    // MARK: Content

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Alignment teaches Lodestar which way north really is for your phone and how the phone sits on the camera. Pick a bright star or planet, steer the tripod until it is in the middle of your camera\u{2019}s frame, then tap Sync. A second object in another part of the sky makes it far more accurate.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            if app.motion.headingSource == .gyroLock && !app.motion.isGyroHeadingReferenced {
                Label("Gyro lock has no heading yet. One alignment sets it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.warning)
            }
        }
    }

    private func noticeBanner(_ notice: AimAlignmentNotice) -> some View {
        Label(notice.text, systemImage: notice.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(notice.isSuccess ? palette.positive : palette.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aimPanel(palette, padding: 12)
    }

    @ViewBuilder
    private var candidateList: some View {
        CardTitle(title: "Reference objects", systemImage: "star")
        if rows.isEmpty {
            Text("No bright star or planet is between 15\u{00B0} and 78\u{00B0} right now. Try again later or after the sky has darkened.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        } else {
            Text("Sorted by distance from where your camera points.")
                .font(.footnote)
                .foregroundStyle(palette.tertiaryText)
            ForEach(rows) { row in
                AimCandidateRow(row: row) { select(row.candidate) }
            }
        }
    }

    // MARK: Actions

    private func reset() {
        app.resetAlignment()
        notice = nil
    }

    private func select(_ candidate: AimAlignmentCandidate) {
        selected = candidate
        notice = nil
        model.alignmentTarget = candidate.object
    }

    private func deselect() {
        selected = nil
        model.alignmentTarget = nil
        sortRows()
    }

    /// Records the camera's attitude together with the object's true apparent position at this instant.
    private func sync() {
        guard let selected, let sample = app.motion.latestSample(), let observer = app.observerContext?.observer else {
            notice = .failure("The motion sensors are not delivering data yet. Wait a moment and sync again.")
            return
        }
        let now = Date()
        let apparent = SkyFrame(date: now, observer: observer).horizontal(of: selected.object, refraction: true)
        let point = AlignmentPoint(attitude: sample.rawAttitude, target: apparent, timestamp: now, name: selected.object.name)
        do {
            let alignment = try app.alignment.adding(point, mount: app.mountProfile)
            app.alignment = alignment
            notice = .success(successText(for: selected.object.name, alignment: alignment))
            syncMountIfWanted(to: selected.object, observer: observer)
            deselect()
        } catch let error as AlignmentError {
            notice = .failure(error.aimMessage(forObject: selected.object.name))
        } catch {
            notice = .failure("The alignment could not be calculated. Try again.")
        }
    }

    /// The star is centred in the camera, which sits on the GoTo mount: the mount takes it as its position as well.
    private func syncMountIfWanted(to object: CelestialObject, observer: Observer) {
        guard syncsMount, MountService.shared.isConnected, MountService.shared.capabilities?.canSync == true else { return }
        Task { await MountService.shared.syncMount(to: object, observer: observer) }
    }

    private func successText(for name: String, alignment: AlignmentModel) -> String {
        if alignment.points.count < 2 {
            return "Aligned on \(name). Add a second object in another part of the sky to tell compass and bracket errors apart."
        }
        let uncertainty = alignment.pointingUncertainty ?? alignment.rmsResidual
        return "Aligned on \(name). Expected accuracy \u{00B1}\(AngleFormatter.formatDegrees(uncertainty, decimals: uncertainty < 10 ? 1 : 0))."
    }

    private func remove(at index: Int) {
        do {
            app.alignment = try app.alignment.removingPoint(at: index, mount: app.mountProfile)
            notice = nil
        } catch let error as AlignmentError {
            notice = .failure(error.aimMessage(forObject: "the object"))
        } catch {
            notice = .failure("The point could not be removed.")
        }
    }

    // MARK: Candidates

    /// Makes the list of reference objects now and again every half minute.
    private func refreshCandidates() async {
        guard let catalog = app.catalog.catalog, let observer = app.observerContext?.observer else { return }
        while !Task.isCancelled {
            let date = Date()
            let list = await Task.detached(priority: .userInitiated) {
                AimAlignmentCandidates.make(catalog: catalog, observer: observer, date: date)
            }.value
            guard !Task.isCancelled else { return }
            candidates = list
            sortRows()
            try? await Task.sleep(for: .seconds(Self.candidateRefreshInterval))
        }
    }

    /// Re-sorts the list by distance from the camera now and then; while an object is chosen the list is hidden.
    private func keepRowsSorted() async {
        while !Task.isCancelled {
            if selected == nil { sortRows() }
            try? await Task.sleep(for: .seconds(Self.sortInterval))
        }
    }

    private func sortRows() {
        let boresight = model.engine.frame()?.pointing.boresightVector
        let unsorted = candidates.map { candidate in
            AimAlignmentRow(candidate: candidate, separation: boresight.map { $0.angle(to: candidate.horizontal.unitVector) })
        }
        rows = unsorted.sorted { lhs, rhs in
            switch (lhs.separation, rhs.separation) {
            case let (first?, second?): return first < second
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (lhs.candidate.magnitude ?? 99) < (rhs.candidate.magnitude ?? 99)
            }
        }
    }
}
