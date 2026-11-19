import SwiftUI
import LodestarKit

/// The previewed moment in words for the readouts: the time in the observer's time zone, the weekday when it is not
/// today, and whether it lies ahead.
struct AimPreviewMoment {
    let time: String
    let day: String?
    let isFuture: Bool

    /// "02:15", or "Fri 02:15" when it is not today.
    var text: String { day.map { "\($0) \(time)" } ?? time }
}

extension AimViewModel {
    /// The time zone the preview's times are shown in: the observer's.
    var previewTimeZone: TimeZone { app.observerContext?.timeZone ?? .current }

    /// The previewed moment, or `nil` while the sky is live.
    var previewMoment: AimPreviewMoment? {
        guard isPreviewing else { return nil }
        let zone = previewTimeZone
        let date = self.date
        let sameDay = AimPreview.isSameDay(date, as: app.clock.now, in: zone)
        let weekday = date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, timeZone: zone)
            .weekday(.abbreviated))
        return AimPreviewMoment(time: AppFormat.time(date, in: zone), day: sameDay ? nil : weekday,
                                isFuture: previewOffset > 0)
    }
}

/// The chip at the top while the sky is previewed: "Preview 02:15" (or "Preview · Daylight at 14:20" when the Sun is up
/// then) with a "Live" button that ends the preview.
struct AimPreviewChip: View {
    let model: AimViewModel
    let moment: AimPreviewMoment
    @Environment(\.palette) private var palette

    var body: some View {
        let isDaylight = model.isDaylightAtPreview == true
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption.weight(.semibold))
            Text(AimPreview.chipText(time: moment.time, day: moment.day, isDaylight: isDaylight))
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(AimPreview.spokenChip(time: moment.time, day: moment.day, isDaylight: isDaylight))
            Button {
                model.endPreview()
            } label: {
                Text("Live")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Returns to the live sky.")
        }
        .padding(.leading, 12)
        .foregroundStyle(palette.warning)
        .background(Capsule().fill(palette.surface))
        .overlay(Capsule().strokeBorder(palette.warning.opacity(0.8), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// The compact time bar above the controls: the previewed date and time, how far from now it is, a "Now" button, the
/// sheet for any date and time, and steps of an hour and a quarter of an hour either way. Shown while the Time button of
/// the controls is on.
struct AimTimeBar: View {
    let model: AimViewModel
    @Binding var sheet: AimSheet?
    @Environment(\.palette) private var palette

    var body: some View {
        if model.isTimeBarOpen {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    readout
                    Spacer(minLength: 4)
                    Button("Now") { model.endPreview() }
                        .buttonStyle(AimTimeBarButtonStyle(horizontalPadding: 14))
                        .disabled(!model.isPreviewing)
                        .accessibilityLabel("Back to now")
                    Button {
                        sheet = .previewTime
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .buttonStyle(AimTimeBarButtonStyle(horizontalPadding: 14))
                    .accessibilityLabel("Choose date and time")
                }
                // Time runs left to right in every language: the earlier steps, then the later ones.
                HStack(spacing: 6) {
                    ForEach(AimPreview.Step.allCases) { step in
                        Button {
                            model.stepPreview(step)
                        } label: {
                            Text(step.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AimTimeBarButtonStyle(horizontalPadding: 4))
                        .accessibilityLabel(step.spokenTitle)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .aimPanel(palette, padding: 8, opacity: 0.97)
        }
    }

    /// The previewed date and time, and below it either "Live" or how far from now it is and in which time zone.
    private var readout: some View {
        let date = model.date
        let zone = model.previewTimeZone
        return VStack(alignment: .leading, spacing: 3) {
            Text(AppFormat.dateTime(date, in: zone))
                .font(.headline.monospacedDigit())
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if model.isPreviewing {
                Text("\(AppFormat.relative(date, from: model.app.clock.now)) \u{00B7} \(zone.abbreviation(for: date) ?? zone.identifier)")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            } else {
                StatusChip(systemImage: "dot.radiowaves.left.and.right", text: "Live", tone: .positive)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A capsule button of the bar, like the secondary `LodestarButtonStyle` but tighter, so that four of them share a
/// phone's width.
struct AimTimeBarButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    let horizontalPadding: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(palette.accent)
            .background(Capsule().fill(palette.surfaceRaised))
            .overlay(Capsule().strokeBorder(palette.accent.opacity(0.6), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}
