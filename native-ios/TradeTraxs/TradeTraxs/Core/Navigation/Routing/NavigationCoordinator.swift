import Foundation
import OSLog

/// Applies ``AppDestination`` intents to ``NavigationStore``.
///
/// Constructed by CompositionRoot. Features call this (or emit destinations
/// upward) — they never mutate tab paths ad hoc across features.
@Observable
final class NavigationCoordinator {
    private let store: NavigationStore
    private var eventHandler: ((NavigationEvent) -> Void)?

    init(store: NavigationStore, eventHandler: ((NavigationEvent) -> Void)? = nil) {
        self.store = store
        self.eventHandler = eventHandler
    }

    func setEventHandler(_ handler: ((NavigationEvent) -> Void)?) {
        eventHandler = handler
    }

    // MARK: - Public API

    func open(_ destination: AppDestination) {
        switch destination {
        case .auth(let route):
            openAuth(route)
        case .tab(let tab):
            selectTab(tab)
        case .home(let route):
            pushHome(route)
        case .feed(let route):
            pushFeed(route)
        case .messages(let route):
            pushMessages(route)
        case .profile(let route):
            pushProfile(route)
        case .settingsStack(let routes):
            openSettings(routes)
        case .sheet(let sheet):
            present(sheet: sheet)
        case .fullScreen(let cover):
            present(fullScreen: cover)
        case .compose(let kind):
            openCompose(kind)
        case .pop:
            pop()
        case .popToRoot(let tab):
            popToRoot(tab ?? store.selectedTab)
        case .dismissPresentation:
            dismissPresentation()
        }
    }

    /// Marks the session authenticated and applies any pending deep link.
    func markAuthenticated() {
        store.sessionPhase = .authenticated
        store.paths.resetAuth(to: .login)
        emit(.sessionPhaseChanged(.authenticated))
        if let pending = store.pendingAfterAuth {
            store.pendingAfterAuth = nil
            open(pending.asAppDestination)
        } else if !store.restoresLastContentTab {
            store.selectedTab = .home
        }
    }

    /// Returns to the auth stack. Clears main presentations; keeps paths cleared.
    func markUnauthenticated() {
        dismissPresentation()
        store.sessionPhase = .unauthenticated
        store.paths = NavigationPathStore()
        store.paths.resetAuth(to: .login)
        store.selectedTab = .home
        store.previousContentTab = .home
        store.pendingAfterAuth = nil
        emit(.sessionPhaseChanged(.unauthenticated))
    }

    func selectTab(_ tab: TabIdentifier) {
        if tab == .create {
            invokeCreateAction()
            return
        }
        store.rememberContentTabIfNeeded(tab)
        store.selectedTab = tab
        emit(.tabSelected(tab))
    }

    /// Create tab is an action — presents chooser and keeps content tab selected.
    func invokeCreateAction() {
        emit(.createActionInvoked)
        present(sheet: .composeChooser)
    }

    func openCompose(_ kind: ComposeKind) {
        switch kind {
        case .chooser:
            present(sheet: .composeChooser)
        case .trade:
            present(fullScreen: .addTrade)
        case .quickTrade:
            present(sheet: .quickTrade)
        case .importCSV:
            present(fullScreen: .importCSV)
        case .post:
            present(fullScreen: .newPost)
        case .achievement:
            present(fullScreen: .newAchievement)
        case .reel:
            present(fullScreen: .newReel)
        case .story:
            present(fullScreen: .newStory)
        }
    }

    func stashForAuthentication(_ destination: AppDestination) {
        store.pendingAfterAuth = PendingDestination(destination: destination)
        if store.sessionPhase != .unauthenticated {
            store.sessionPhase = .unauthenticated
            store.paths.resetAuth(to: .login)
            emit(.sessionPhaseChanged(.unauthenticated))
        }
    }

    // MARK: - Stack ops

    func pushHome(_ route: HomeRoute) {
        ensureAuthenticatedOrStash(.home(route))
        guard store.sessionPhase == .authenticated else { return }
        selectTab(.home)
        store.paths.home.append(route)
        emit(.pushed(tab: .home, description: String(describing: route)))
    }

    func pushFeed(_ route: FeedRoute) {
        ensureAuthenticatedOrStash(.feed(route))
        guard store.sessionPhase == .authenticated else { return }
        selectTab(.feed)
        store.paths.feed.append(route)
        emit(.pushed(tab: .feed, description: String(describing: route)))
    }

    func pushMessages(_ route: MessagesRoute) {
        ensureAuthenticatedOrStash(.messages(route))
        guard store.sessionPhase == .authenticated else { return }
        selectTab(.messages)
        store.paths.messages.append(route)
        emit(.pushed(tab: .messages, description: String(describing: route)))
    }

    func pushProfile(_ route: ProfileRoute) {
        ensureAuthenticatedOrStash(.profile(route))
        guard store.sessionPhase == .authenticated else { return }
        selectTab(.profile)
        store.paths.profile.append(route)
        emit(.pushed(tab: .profile, description: String(describing: route)))
    }

    /// Opens Settings with a proper back stack (home → section → leaf).
    ///
    /// Replaces any existing Settings routes on the Profile path so repeated opens
    /// do not stack duplicate Settings roots.
    func openSettings(_ routes: [SettingsRoute]) {
        var normalized = routes
        if normalized.isEmpty {
            normalized = [.home]
        }
        if normalized.first != .home {
            normalized.insert(.home, at: 0)
        }
        // Deduplicate consecutive identical routes.
        var unique: [SettingsRoute] = []
        for route in normalized where unique.last != route {
            unique.append(route)
        }

        ensureAuthenticatedOrStash(.settingsStack(unique))
        guard store.sessionPhase == .authenticated else { return }
        selectTab(.profile)
        store.paths.profile.removeAll {
            if case .settings = $0 { return true }
            return false
        }
        for route in unique {
            store.paths.profile.append(.settings(route))
        }
        emit(.pushed(tab: .profile, description: "settingsStack:\(unique.map(\.rawValue).joined(separator: "/"))"))
    }

    func pop() {
        let tab = store.selectedTab
        guard tab.storesNavigationStack else { return }
        store.paths.pop(tab)
        emit(.popped(tab: tab))
    }

    func popToRoot(_ tab: TabIdentifier) {
        store.paths.popToRoot(tab)
        emit(.poppedToRoot(tab))
    }

    func present(sheet: SheetDestination) {
        store.presentedSheet = sheet
        emit(.sheetPresented(sheet))
    }

    func present(fullScreen: FullScreenDestination) {
        store.presentedFullScreen = fullScreen
        emit(.fullScreenPresented(fullScreen))
    }

    func dismissPresentation() {
        store.presentedSheet = nil
        store.presentedFullScreen = nil
        emit(.presentationDismissed)
    }

    func dismissSheet() {
        store.presentedSheet = nil
        emit(.presentationDismissed)
    }

    func dismissFullScreen() {
        store.presentedFullScreen = nil
        emit(.presentationDismissed)
    }

    // MARK: - Auth stack

    func openAuth(_ route: AuthRoute) {
        store.sessionPhase = .unauthenticated
        if route == .login {
            store.paths.auth.removeAll()
        } else if store.paths.auth.last != route {
            store.paths.auth.append(route)
        }
        emit(.sessionPhaseChanged(.unauthenticated))
    }

    // MARK: - Private

    private func ensureAuthenticatedOrStash(_ destination: AppDestination) {
        guard store.sessionPhase != .authenticated else { return }
        stashForAuthentication(destination)
    }

    private func emit(_ event: NavigationEvent) {
        switch event {
        case .tabSelected(let tab):
            AppLog.navigation.info("Tab selected: \(tab.rawValue, privacy: .public)")
        case .createActionInvoked:
            AppLog.navigation.info("Create action invoked")
        case .deepLinkFailed(let message), .notificationFailed(let message):
            AppLog.navigation.error("Navigation failed: \(message, privacy: .public)")
        default:
            AppLog.navigation.debug("\(String(describing: event), privacy: .public)")
        }
        eventHandler?(event)
    }
}
