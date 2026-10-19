import SwiftUI

/// Top-level view: onboarding on first launch, then the tab interface. Applies the active
/// palette (normal or red night mode) to the whole window; at night the white status bar is hidden.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        let palette = app.palette

        Group {
            if let host = reviewHost {
                host
            } else if app.settings.hasCompletedOnboarding {
                // Every tab hides the system tab bar, whose glass the night palette does not reach, and the app's own
                // bar (`AppTabBar`) takes its place in a bottom safe area inset.
                TabView(selection: $app.selectedTab) {
                    AimView()
                        .toolbar(.hidden, for: .tabBar)
                        .tag(AppTab.aim)
                    ObjectsView()
                        .statusBarHidden(app.isNightModeActive)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(AppTab.objects)
                    SkyChartView()
                        .statusBarHidden(app.isNightModeActive)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(AppTab.sky)
                    TonightView()
                        .statusBarHidden(app.isNightModeActive)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(AppTab.tonight)
                    SettingsView()
                        .statusBarHidden(app.isNightModeActive)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(AppTab.settings)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AppTabBar(selection: $app.selectedTab)
                }
            } else {
                OnboardingView()
            }
        }
        .themedRoot(palette, redFilter: app.settings.redFilterOverlay)
        .onChange(of: palette, initial: true) { _, newPalette in
            BarAppearance.apply(newPalette)
            NightWindowFilter.setActive(NightChrome.isActive("win", night: newPalette.isNight))
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            app.handleScenePhase(phase)
        }
        .onChange(of: app.settings) { _, _ in
            app.syncServices()
        }
        .task {
            await app.launch()
        }
        .lodestarWidgets()
    }
}
