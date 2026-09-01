import Foundation
import OSLog

/// Applies ``AppDestination`` intents to ``NavigationStore``.
///
/// Ordinary in-app navigation appends exactly one route to the active tab path.
/// It does not switch tabs, replace paths, or insert hidden parent screens.
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
            selectTab(.home)
            pushHome(route)
        case .feed(let route):
            selectTab(.feed)
            pushFeed(route)
        case .messages(let route):
            selectTab(.messages)
            pushMessages(route)
        case .profile(let route):
            selectTab(.profile)
            pushProfile(route)
        case .settingsStack(let routes):
            openSettingsDeepLink(routes)
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
    func markAuthenticated(applyingDeferred snapshot: NavigationState? = nil) {
        if let snapshot {
            store.selectedTab = snapshot.selectedTab == .create ? snapshot.previousContentTab : snapshot.selectedTab
            store.previousContentTab = snapshot.previousContentTab
            store.paths.home = snapshot.homePath
            store.paths.feed = snapshot.feedPath
            store.paths.messages = snapshot.messagesPath
            store.paths.profile = snapshot.profilePath
        }
        store.sessionPhase = .authenticated
        store.paths.resetAuth(to: .login)
        emit(.sessionPhaseChanged(.authenticated))
        if let pending = store.pendingAfterAuth {
            store.pendingAfterAuth = nil
            open(pending.asAppDestination)
        } else if snapshot == nil, !store.restoresLastContentTab {
            store.selectedTab = .home
        }
    }

    /// Returns to the auth stack. Clears main presentations and all tab paths.
    func markUnauthenticated(clearPersistedNavigation: Bool = false) {
        dismissPresentation()
        store.sessionPhase = .unauthenticated
        store.paths = NavigationPathStore()
        store.paths.resetAuth(to: .login)
        store.selectedTab = .home
        store.previousContentTab = .home
        store.pendingAfterAuth = nil
        emit(.sessionPhaseChanged(.unauthenticated))
        if clearPersistedNavigation {
            // Caller clears restorer via NavigationEnvironment when appropriate.
        }
    }

    func selectTab(_ tab: TabIdentifier) {
        if tab == .create {
            invokeCreateAction()
            return
        }
        if store.selectedTab != tab {
            ExperienceHaptics.play(.selection)
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
            guard store.presentedFullScreen != .newStory else { return }
            present(fullScreen: .newStory)
        }
    }

    /// Full-screen native trade editor (web `InputTradeForm` edit mode).
    func editTrade(_ tradeID: TradeID) {
        present(fullScreen: .editTrade(tradeID))
    }

    func stashForAuthentication(_ destination: AppDestination) {
        store.pendingAfterAuth = PendingDestination(destination: destination)
        if store.sessionPhase != .unauthenticated {
            store.sessionPhase = .unauthenticated
            store.paths.resetAuth(to: .login)
            emit(.sessionPhaseChanged(.unauthenticated))
        }
    }

    // MARK: - Stack ops (append-only; no tab switch)

    func pushHome(_ route: HomeRoute) {
        ensureAuthenticatedOrStash(.home(route))
        guard store.sessionPhase == .authenticated else { return }
        let pathBefore = store.paths.home.count
        store.paths.home.append(route)
        logNavigationEvent(
            action: "push",
            source: "pushHome",
            destination: String(describing: route),
            tab: .home,
            pathBefore: pathBefore,
            pathAfter: store.paths.home.count
        )
        emit(.pushed(tab: .home, description: String(describing: route)))
    }

    func pushFeed(_ route: FeedRoute) {
        ensureAuthenticatedOrStash(.feed(route))
        guard store.sessionPhase == .authenticated else { return }
        if case .room(let roomID) = route {
            InboxMarkReadCoordinator.shared.prepareOpenRoom(roomID)
        }
        let pathBefore = store.paths.feed.count
        store.paths.feed.append(route)
        logNavigationEvent(
            action: "push",
            source: "pushFeed",
            destination: String(describing: route),
            tab: .feed,
            pathBefore: pathBefore,
            pathAfter: store.paths.feed.count
        )
        emit(.pushed(tab: .feed, description: String(describing: route)))
    }

    func pushMessages(_ route: MessagesRoute) {
        ensureAuthenticatedOrStash(.messages(route))
        guard store.sessionPhase == .authenticated else { return }
        switch route {
        case .thread(let conversationID):
            InboxMarkReadCoordinator.shared.prepareOpenConversation(conversationID)
        case .room(let roomID):
            InboxMarkReadCoordinator.shared.prepareOpenRoom(roomID)
        case .roomMembers, .roomInfo, .sharedTrade, .sharedPost, .sharedReel, .profile, .settings:
            break
        }
        let pathBefore = store.paths.messages.count
        store.paths.messages.append(route)
        logNavigationEvent(
            action: "push",
            source: "pushMessages",
            destination: String(describing: route),
            tab: .messages,
            pathBefore: pathBefore,
            pathAfter: store.paths.messages.count
        )
        emit(.pushed(tab: .messages, description: String(describing: route)))
    }

    func pushProfile(_ route: ProfileRoute) {
        ensureAuthenticatedOrStash(.profile(route))
        guard store.sessionPhase == .authenticated else { return }
        if case .room(let roomID) = route {
            InboxMarkReadCoordinator.shared.prepareOpenRoom(roomID)
        }
        let pathBefore = store.paths.profile.count
        store.paths.profile.append(route)
        logNavigationEvent(
            action: "push",
            source: "pushProfile",
            destination: String(describing: route),
            tab: .profile,
            pathBefore: pathBefore,
            pathAfter: store.paths.profile.count
        )
        emit(.pushed(tab: .profile, description: String(describing: route)))
    }

    func pop() {
        let tab = store.selectedTab
        guard tab.storesNavigationStack else { return }
        let pathBefore = pathCount(for: tab)
        store.paths.pop(tab)
        logNavigationEvent(
            action: "pop",
            source: "pop",
            destination: nil,
            tab: tab,
            pathBefore: pathBefore,
            pathAfter: pathCount(for: tab)
        )
        emit(.popped(tab: tab))
    }

    func popToRoot(_ tab: TabIdentifier) {
        store.paths.popToRoot(tab)
        emit(.poppedToRoot(tab))
    }

    func present(sheet: SheetDestination) {
        if store.presentedSheet != sheet {
            ExperienceHaptics.play(.selection)
        }
        store.presentedSheet = sheet
        emit(.sheetPresented(sheet))
    }

    func present(fullScreen: FullScreenDestination) {
        if store.presentedFullScreen != fullScreen {
            ExperienceHaptics.play(.selection)
        }
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

    /// Cold deep link / external settings URL — intentional Profile tab + constructed stack.
    private func openSettingsDeepLink(_ routes: [SettingsRoute]) {
        ensureAuthenticatedOrStash(.settingsStack(routes))
        guard store.sessionPhase == .authenticated else { return }
        selectTab(.profile)
        store.paths.profile.removeAll()
        for route in routes {
            store.paths.profile.append(.settings(route))
        }
        emit(.pushed(tab: .profile, description: "settingsDeepLink:\(routes.map(\.rawValue).joined(separator: "/"))"))
    }

    private func ensureAuthenticatedOrStash(_ destination: AppDestination) {
        guard store.sessionPhase != .authenticated else { return }
        stashForAuthentication(destination)
    }

    private func pathCount(for tab: TabIdentifier) -> Int {
        switch tab {
        case .home: return store.paths.home.count
        case .feed: return store.paths.feed.count
        case .messages: return store.paths.messages.count
        case .profile: return store.paths.profile.count
        case .create: return 0
        }
    }

#if DEBUG
    private func logNavigationEvent(
        action: String,
        source: String,
        destination: String?,
        tab: TabIdentifier,
        pathBefore: Int,
        pathAfter: Int
    ) {
        AppLog.navigation.debug(
            """
            navigation.event action=\(action, privacy: .public) \
            source=\(source, privacy: .public) \
            destination=\(destination ?? "-", privacy: .public) \
            activeTab=\(self.store.selectedTab.rawValue, privacy: .public) \
            stackTab=\(tab.rawValue, privacy: .public) \
            pathBefore=\(pathBefore, privacy: .public) \
            pathAfter=\(pathAfter, privacy: .public)
            """
        )
    }
#else
    private func logNavigationEvent(
        action: String,
        source: String,
        destination: String?,
        tab: TabIdentifier,
        pathBefore: Int,
        pathAfter: Int
    ) {}
#endif

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
