import SwiftUI

/// The steps of the first-run flow, in order.
enum OnboardingStep: Int, CaseIterable {
    case welcome, mounting, permissions, nightVision
}

/// First-run flow: what Lodestar does, how the phone is mounted, where the observer is and how to protect night
/// vision. Shown instead of the tab interface until it ends with `AppModel.completeOnboarding()`.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var step = OnboardingStep.welcome

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                OnboardingWelcomePage()
                    .tag(OnboardingStep.welcome)
                OnboardingMountPage()
                    .tag(OnboardingStep.mounting)
                OnboardingPermissionsPage()
                    .tag(OnboardingStep.permissions)
                OnboardingNightPage()
                    .tag(OnboardingStep.nightVision)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            footer
        }
        .screenBackground(palette)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            OnboardingPageDots(current: step.rawValue, count: OnboardingStep.allCases.count)
            HStack(spacing: 12) {
                if step != .welcome {
                    Button("Back") { move(by: -1) }
                        .buttonStyle(.lodestarSecondary)
                }
                Button {
                    advance()
                } label: {
                    Text(step == .nightVision ? "Start Aiming" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lodestarPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(palette.background)
    }

    private func advance() {
        if step == .nightVision {
            app.completeOnboarding()
        } else {
            move(by: 1)
        }
    }

    private func move(by offset: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + offset) else { return }
        withAnimation {
            step = next
        }
    }
}

/// Dots showing the current step, drawn in the palette (the system page dots are white and grey).
private struct OnboardingPageDots: View {
    @Environment(\.palette) private var palette
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? palette.accent : palette.stroke)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
