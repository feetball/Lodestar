import SwiftUI
import LodestarKit

/// One pass: its sky path, the rise, peak and set with their direction and height, the visible stretch and the brightness,
/// and the two ways to Aim: follow the satellite live, or wait at the point where the pass peaks.
struct SatellitePassDetailView: View {
    let item: SatellitePassItem
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var track: PassTrack?

    /// The peak counts as passed this long after it, so a countdown can still be started at the moment itself.
    private static let peakGrace: TimeInterval = 30

    /// The track of the pass and the look at its highest point, worked out together.
    private struct PassTrack: Sendable {
        let looks: [SatelliteLook]
        let peak: SatelliteLook?
    }

    private var observer: Observer? { app.observerContext?.observer }
    private var timeZone: TimeZone { app.observerContext?.timeZone ?? .autoupdatingCurrent }

    var body: some View {
        // The detail moves on every ten seconds, not with the clock's second.
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(AppFormat.day(item.start, in: timeZone)) \u{00B7} \(SatelliteText.span(item, in: timeZone))")
                        .font(.body)
                        .foregroundStyle(palette.secondaryText)
                    pathSection
                    passCard(now: timeline.date)
                    aimSection(now: timeline.date)
                    TonightNote(text: SatelliteText.attribution, style: .footnote)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .screenBackground(palette)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: observer) {
            guard let observer else {
                track = nil
                return
            }
            // One point every five seconds from rise to set, worked out off the main actor.
            let item = item
            track = await Task.detached(priority: .userInitiated) {
                PassTrack(looks: item.satellite.track(from: item.pass.rise.date, to: item.pass.set.date, step: 5, observer: observer),
                     peak: item.satellite.look(at: item.peak.date, observer: observer))
            }.value
        }
    }

    @ViewBuilder
    private var pathSection: some View {
        if let track, track.looks.count >= 2 {
            VStack(spacing: 6) {
                SatellitePathView(looks: track.looks, peak: track.peak, description: SatelliteText.spokenPath(item, in: timeZone))
                TonightNote(text: SatelliteText.pathNote, style: .footnote)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func passCard(now: Date) -> some View {
        let pass = item.pass
        return VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "Pass", systemImage: "clock")
            InfoRow(label: "Rise", value: SatelliteText.point(pass.rise, in: timeZone))
            InfoRow(label: "Peak", value: SatelliteText.point(item.peak, in: timeZone))
            InfoRow(label: "Set", value: SatelliteText.point(pass.set, in: timeZone))
            if let span = pass.visibleSpan {
                InfoRow(label: "Visible",
                        value: "\(SatelliteText.timeWithSeconds(span.start, in: timeZone)) \u{2013} "
                            + "\(SatelliteText.timeWithSeconds(span.end, in: timeZone)) (\(SatelliteText.duration(span.duration)))")
            }
            InfoRow(label: "Magnitude", value: SatelliteText.magnitude(item))
            if !item.isFresh(at: now) {
                TonightNote(text: SatelliteText.stale, style: .warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
    }

    private func aimSection(now: Date) -> some View {
        let peakPassed = now > item.peak.date.addingTimeInterval(Self.peakGrace)
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Aim", systemImage: "scope")
            Button {
                guard let observer else { return }
                app.satelliteAim.start(.follow(item, observer: observer))
                app.selectedTab = .aim
            } label: {
                Text(SatelliteText.follow).frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarPrimary)
            .disabled(observer == nil)
            Button {
                guard let observer else { return }
                app.satelliteAim.start(.peak(item, observer: observer))
                app.selectedTab = .aim
            } label: {
                Text(SatelliteText.wait).frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarSecondary)
            .disabled(observer == nil || peakPassed)
            TonightNote(text: SatelliteText.actionsNote, style: .footnote)
        }
    }
}
