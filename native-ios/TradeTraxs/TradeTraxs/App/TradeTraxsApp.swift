import SwiftUI

@main
struct TradeTraxsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appEnvironment = CompositionRoot.bootstrap()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView(
                navigation: appEnvironment.navigation,
                themeManager: appEnvironment.themeManager,
                authenticationManager: appEnvironment.authentication.manager,
                authenticationCoordinator: appEnvironment.authentication.coordinator,
                authenticationLifecycle: appEnvironment.authentication.lifecycle
            )
            .environment(\.appEnvironment, appEnvironment)
            .environment(\.navigationEnvironment, appEnvironment.navigation)
            .environment(appEnvironment.themeManager)
            .environment(appEnvironment.authentication.manager)
            .onAppear {
                appDelegate.lifecycle = appEnvironment.lifecycle
            }
            .onChange(of: scenePhase) { _, newPhase in
                appEnvironment.lifecycle.handle(scenePhase: newPhase)
                if newPhase == .background {
                    appEnvironment.navigation.persistState()
                }
            }
        }
    }
}
