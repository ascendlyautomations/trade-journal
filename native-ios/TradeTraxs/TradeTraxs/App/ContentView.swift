import SwiftUI

/// Legacy template entry — unused by production launch.
///
/// Kept only so previews/tests that still reference `ContentView` compile.
/// Launch chrome is ``AppRootView``.
struct ContentView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        AppRootView(
            navigation: appEnvironment.navigation,
            themeManager: appEnvironment.themeManager,
            authenticationManager: appEnvironment.authentication.manager,
            authenticationCoordinator: appEnvironment.authentication.coordinator,
            authenticationLifecycle: appEnvironment.authentication.lifecycle,
            currentUserProfile: appEnvironment.currentUserProfile,
            appBootstrapState: appEnvironment.appBootstrapState,
            profileOnboardingGate: appEnvironment.profileOnboardingGate,
            contentReportPresenter: appEnvironment.contentReportPresenter,
            allowsDevelopmentBypass: appEnvironment.authentication.configuration.allowsDevelopmentSessionBypass
        )
    }
}

#Preview("App Root") {
    let environment = CompositionRoot.bootstrap()
    AppRootView(
        navigation: environment.navigation,
        themeManager: environment.themeManager,
        authenticationManager: environment.authentication.manager,
        authenticationCoordinator: environment.authentication.coordinator,
        authenticationLifecycle: environment.authentication.lifecycle,
        currentUserProfile: environment.currentUserProfile,
        appBootstrapState: environment.appBootstrapState,
        profileOnboardingGate: environment.profileOnboardingGate,
        contentReportPresenter: environment.contentReportPresenter,
        allowsDevelopmentBypass: environment.authentication.configuration.allowsDevelopmentSessionBypass
    )
    .environment(\.appEnvironment, environment)
    .environment(environment.themeManager)
    .environment(environment.currentUserProfile)
}
