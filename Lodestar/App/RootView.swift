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
                TabView(selection: $app.selectedTab) {
                    AimView()
                        .tabItem { Label(AppTab.aim.title, systemImage: AppTab.aim.systemImage) }
                        .tag(AppTab.aim)
                    ObjectsView()
                        .statusBarHidden(app.isNightModeActive)
                        .tabItem { Label(AppTab.objects.title, systemImage: AppTab.objects.systemImage) }
                        .tag(AppTab.objects)
                    SkyChartView()
                        .statusBarHidden(app.isNightModeActive)
                        .tabItem { Label(AppTab.sky.title, systemImage: AppTab.sky.systemImage) }
                        .tag(AppTab.sky)
                    TonightView()
                        .statusBarHidden(app.isNightModeActive)
                        .tabItem { Label(AppTab.tonight.title, systemImage: AppTab.tonight.systemImage) }
                        .tag(AppTab.tonight)
                    SettingsView()
                        .statusBarHidden(app.isNightModeActive)
                        .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                        .tag(AppTab.settings)
                }
            } else {
                OnboardingView()
            }
        }
        .themedRoot(palette, redFilter: app.settings.redFilterOverlay)
        .onChange(of: palette, initial: true) { _, newPalette in
            BarAppearance.apply(newPalette)
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
