import ActivityKit
import SwiftUI
import WidgetKit

/// The Live Activity of a followed satellite pass: a banner on the Lock Screen and the Dynamic Island with the satellite's
/// name, a countdown to the rise and then to the peak, how high the pass gets and where to look. The app starts and ends it
/// (`SatellitePassActivityController`).
struct SatellitePassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SatellitePassActivityAttributes.self) { context in
            let view = SatellitePassView(context: context)
            SatellitePassBanner(view: view)
                .activityBackgroundTint(view.palette.background)
                .activitySystemActionForegroundColor(view.palette.accent)
        } dynamicIsland: { context in
            let view = SatellitePassView(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(view.name, systemImage: SatellitePassView.symbol)
                        .font(.headline)
                        .foregroundStyle(view.palette.primary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    view.countdown(font: .title3.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    view.facts
                }
            } compactLeading: {
                Image(systemName: SatellitePassView.symbol)
                    .foregroundStyle(view.palette.accent)
            } compactTrailing: {
                view.countdown(font: .caption.weight(.semibold))
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: SatellitePassView.symbol)
                    .foregroundStyle(view.palette.accent)
            }
            .keylineTint(view.palette.accent)
        }
    }
}

/// The colours of the activity: the widgets' own look by day, pure red on black when the app was in night mode when the
/// activity started.
struct SatellitePassPalette {
    let background: Color
    let primary: Color
    let secondary: Color
    let accent: Color

    init(isNight: Bool) {
        if isNight {
            background = .black
            primary = Color(red: 0.9, green: 0, blue: 0)
            secondary = Color(red: 0.62, green: 0, blue: 0)
            accent = Color(red: 1, green: 0, blue: 0)
        } else {
            background = TonightStyle.background
            primary = TonightStyle.primaryText
            secondary = TonightStyle.secondaryText
            accent = TonightStyle.accent
        }
    }
}

/// What the activity shows at the moment it is drawn. The stage is the one the app set or the one the clock says, whichever
/// is later, so the activity is right even when the app was suspended at the rise or the peak.
struct SatellitePassView {
    static let symbol = "point.topleft.down.to.point.bottomright.curvepath"

    let name: String
    let timeline: SatellitePassTimeline
    let stage: SatellitePassTimeline.Stage
    let palette: SatellitePassPalette

    init(context: ActivityViewContext<SatellitePassActivityAttributes>, now: Date = Date()) {
        name = context.attributes.name
        timeline = context.attributes.timeline
        stage = max(context.state.stage, context.attributes.timeline.stage(at: now))
        palette = SatellitePassPalette(isNight: context.attributes.isNight)
    }

    /// The countdown to the rise or the peak, or the word for a pass past the peak.
    @ViewBuilder
    func countdown(font: Font) -> some View {
        if let target = timeline.countdownTarget(in: stage) {
            let now = Date()
            Text(timerInterval: min(now, target)...target, countsDown: true,
                 showsHours: target.timeIntervalSince(now) >= 3_600)
                .font(font.monospacedDigit())
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.trailing)
        } else {
            Text(SatellitePassWords.countdownLabel(stage))
                .font(font)
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// How high the pass gets and where to look.
    var facts: some View {
        HStack {
            Text(SatellitePassWords.maximum(timeline.peakAltitude))
            Spacer(minLength: 8)
            Text(SatellitePassWords.look(timeline.lookAzimuth(in: stage), in: stage))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(palette.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    var spoken: String {
        SatellitePassWords.spoken(name: name, timeline: timeline, stage: stage)
    }
}

/// The Lock Screen banner.
struct SatellitePassBanner: View {
    let view: SatellitePassView

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(view.name, systemImage: SatellitePassView.symbol)
                        .font(.headline)
                        .foregroundStyle(view.palette.primary)
                        .lineLimit(1)
                    Text(SatellitePassWords.countdownLabel(view.stage))
                        .font(.caption)
                        .foregroundStyle(view.palette.secondary)
                }
                Spacer(minLength: 8)
                view.countdown(font: .largeTitle.weight(.semibold))
            }
            view.facts
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(view.spoken)
    }
}
