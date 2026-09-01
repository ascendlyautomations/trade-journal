import Foundation
import OSLog

/// Navigation subgraph injected through ``AppEnvironment``.
///
/// CompositionRoot → AppEnvironment → NavigationEnvironment → Store/Coordinator
@Observable
final class NavigationEnvironment {
    let store: NavigationStore
    let coordinator: NavigationCoordinator
    let deepLinkParser: any DeepLinkParsing
    let deepLinkRouter: DeepLinkRouter
    let notificationRouter: any NotificationRouting
    let notificationRouterFacade: NotificationRouterFacade
    let stateRestorer: any NavigationStateRestoring
    let sceneRestoration: any SceneRestoring
    let splitSupport: any SplitNavigationSupporting
    /// Paths/tab snapshot deferred until session validation succeeds.
    private(set) var deferredAuthenticatedSnapshot: NavigationState?

    init(
        store: NavigationStore,
        coordinator: NavigationCoordinator,
        deepLinkParser: any DeepLinkParsing = DeepLinkParser(),
        notificationRouter: any NotificationRouting = NotificationRouter(),
        stateRestorer: any NavigationStateRestoring = UserDefaultsNavigationStateRestorer(),
        sceneRestoration: any SceneRestoring = SceneRestorationBridge(),
        splitSupport: any SplitNavigationSupporting = SplitNavigationSupport()
    ) {
        self.store = store
        self.coordinator = coordinator
        self.deepLinkParser = deepLinkParser
        self.deepLinkRouter = DeepLinkRouter(parser: deepLinkParser)
        self.notificationRouter = notificationRouter
        self.notificationRouterFacade = NotificationRouterFacade(router: notificationRouter)
        self.stateRestorer = stateRestorer
        self.sceneRestoration = sceneRestoration
        self.splitSupport = splitSupport
    }

    /// Persist current navigation snapshot (call on background / scene resign).
    func persistState() {
        stateRestorer.save(store.snapshot)
        AppLog.navigation.debug("Navigation state persisted")
    }

    func clearPersistedState() {
        stateRestorer.clear()
    }

    func deferAuthenticatedSnapshot(_ snapshot: NavigationState) {
        deferredAuthenticatedSnapshot = snapshot
    }

    func consumeDeferredAuthenticatedSnapshot() -> NavigationState? {
        let snapshot = deferredAuthenticatedSnapshot
        deferredAuthenticatedSnapshot = nil
        return snapshot
    }

    func clearDeferredAuthenticatedSnapshot() {
        deferredAuthenticatedSnapshot = nil
    }
}
