import Foundation
import Observation

enum DemoExitAuthIntent: Sendable {
    case signIn
    case createAccount
}

/// Owns the process ``AppEnvironment`` and completes deferred bootstrap on demand (sign-in).
@Observable
@MainActor
final class AppLaunchController {
    static let shared = AppLaunchController()

    private(set) var environment: AppEnvironment
    private(set) var bootstrapGeneration: UInt64 = 0
    private(set) var isDemoExperienceActive = false
    private(set) var demoExitAuthIntent: DemoExitAuthIntent?

    func consumeDemoExitAuthIntent() -> DemoExitAuthIntent? {
        defer { demoExitAuthIntent = nil }
        return demoExitAuthIntent
    }

    private var deferredContext: DeferredBootstrapContext?
    private var fullBootstrapTask: Task<AppEnvironment, Never>?
    private var preDemoEnvironment: AppEnvironment?

    private init() {
        StartupTrace.begin("AppLaunchController.init")
        StartupTrace.anchorAppStartIfNeeded()
        StartupTrace.event("swiftUIAppInit")
        let result = CompositionRoot.bootstrap()
        environment = result.environment
        deferredContext = result.deferredContext
        StartupTrace.end("AppLaunchController.init")
        // Logged-out: production stack loads only via ``ensureFullBootstrapComplete()`` (sign-in).
    }

    /// Sign-in and other authenticated operations await the live data/network stack.
    func ensureFullBootstrapComplete() async {
        guard deferredContext != nil || environment.isDeferredBootstrapPending else { return }
        if let task = fullBootstrapTask {
            _ = await task.value
            return
        }
        guard let deferredContext else { return }
        StartupTrace.event("ensureFullBootstrapComplete.started")
        let context = deferredContext
        fullBootstrapTask = Task { @MainActor in
            StartupTrace.begin("CompositionRoot.completeDeferredBootstrap")
            let full = await CompositionRoot.completeDeferredBootstrap(context: context)
            StartupTrace.end("CompositionRoot.completeDeferredBootstrap")
            self.applyFullEnvironment(full)
            return full
        }
        _ = await fullBootstrapTask?.value
    }

    /// Logged-out Explore Mode — local demo journal + guest public community reads.
    func enterDemoExplore() {
        guard !isDemoExperienceActive else { return }
        guard environment.authentication.manager.state.isUnauthenticatedForDemoEntry else { return }

        preDemoEnvironment = environment
        isDemoExperienceActive = true
        AuthLandingInstallState.shared.recordLoggedOutAuthLandingPresented()
        DemoExperienceSupport.setExploreLiveCommunityReadsActive(true)

        let configuration = environment.configuration
        let demoEnvironment = CompositionRoot.buildExploreDemoEnvironment(
            configuration: configuration,
            featureFlags: environment.featureFlags,
            lifecycle: environment.lifecycle,
            themeManager: environment.themeManager,
            navigation: environment.navigation,
            authentication: environment.authentication
        )

        SessionScopedCaches.invalidate(
            currentUserProfile: environment.currentUserProfile,
            data: environment.data
        )
        demoEnvironment.navigation.coordinator.markExploreExperience()

        ExploreSessionStore.shared.invalidate()

        environment = demoEnvironment
        bootstrapGeneration &+= 1
        StartupTrace.event("demoExplore.entered")
        ExploreModeConversionPromptCoordinator.shared.exploreModeDidEnter()
    }

    func exitDemoExplore(authIntent: DemoExitAuthIntent? = nil) {
        guard isDemoExperienceActive else { return }
        ExploreModeConversionPromptCoordinator.shared.exploreModeDidExit()
        isDemoExperienceActive = false
        DemoExperienceSupport.setExploreLiveCommunityReadsActive(false)
        demoExitAuthIntent = authIntent

        SessionScopedCaches.invalidate(
            currentUserProfile: environment.currentUserProfile,
            data: environment.data
        )

        if let preDemo = preDemoEnvironment {
            environment = preDemo
        }
        preDemoEnvironment = nil

        environment.navigation.coordinator.markUnauthenticated(clearPersistedNavigation: true)
        environment.currentUserProfile.clear()
        environment.profileOnboardingGate.reset()
        bootstrapGeneration &+= 1
        StartupTrace.event("demoExplore.exited")
    }

    private func applyFullEnvironment(_ full: AppEnvironment) {
        environment = full
        bootstrapGeneration &+= 1
        deferredContext = nil
        fullBootstrapTask = nil
    }

}

private extension AuthenticationState {
    var isUnauthenticatedForDemoEntry: Bool {
        switch self {
        case .unauthenticated, .failure:
            return true
        default:
            return false
        }
    }
}
