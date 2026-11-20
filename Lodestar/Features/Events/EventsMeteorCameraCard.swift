import SwiftUI
import LodestarKit

/// Where to point the camera for a meteor shower, how many meteors to expect in the frame of the user's lens, and a
/// button that aims at that place. The advice is for the moment of the night when the radiant is highest in the dark;
/// it is worked out off the main actor.
struct EventsMeteorCameraCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    let event: AstronomicalEvent
    let shower: MeteorShower
    let context: ObserverContext
    /// The advice, which the detail screen's Aim button reads too.
    @Binding var state: EventsMeteorCameraState

    /// What the advice depends on; the GPS accuracy and the like do not start it again.
    private struct Inputs: Hashable, Sendable {
        let eventDate: Date
        let showerCode: String
        let location: GeographicLocation
        let timeZoneIdentifier: String
    }

    private var inputs: Inputs {
        Inputs(eventDate: event.date, showerCode: shower.code, location: context.location,
               timeZoneIdentifier: context.timeZone.identifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Camera", systemImage: "camera")
            switch state {
            case .loading:
                TonightNote(text: "Working out where to point the camera\u{2026}")
            case .noDarkness:
                TonightNote(text: "The sky does not get fully dark at your location that night, so there is no camera advice.")
            case .radiantBelowHorizon:
                TonightNote(text: "The radiant stays below the horizon all night from here, so there is no place to frame.")
            case .ready(let plan):
                ready(plan)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{2022}")
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(EventsMeteorCamera.tip)
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(palette)
        .task(id: inputs) {
            await work()
        }
    }

    /// Works the advice out off the main actor and shows it, unless the inputs changed meanwhile.
    private func work() async {
        let (event, shower, context) = (self.event, self.shower, self.context)
        let computed = await Task.detached(priority: .userInitiated) {
            EventsMeteorCamera.state(event: event, shower: shower, context: context)
        }.value
        guard !Task.isCancelled else { return }
        state = computed
    }

    @ViewBuilder
    private func ready(_ plan: EventsMeteorCameraPlan) -> some View {
        let advice = plan.advice
        let lens = app.lensSetup
        let perHour = EventsMeteorCamera.expectedPerHour(plan, shower: shower, lens: lens)
        VStack(alignment: .leading, spacing: 6) {
            Text(EventsMeteorCamera.aimText(advice))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            TonightNote(text: advice.reason)
            if let moonNote = advice.moonNote {
                TonightNote(text: moonNote)
            }
            Text(EventsMeteorCamera.countText(perHour: perHour, radiantAltitude: plan.radiantAltitude,
                                              lensText: EventsMeteorCamera.lensText(lens)))
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            TonightNote(text: "For \(EventsFormat.dayAndTime(plan.time, in: context.timeZone)), when the radiant is "
                        + "highest in the dark. \(EventsMeteorCamera.estimateNote)", style: .footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        Button {
            app.aim(at: EventsMeteorCamera.target(shower: shower, advice: advice))
        } label: {
            Label("Aim camera there", systemImage: "scope")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LodestarButtonStyle(kind: .secondary))
    }
}
