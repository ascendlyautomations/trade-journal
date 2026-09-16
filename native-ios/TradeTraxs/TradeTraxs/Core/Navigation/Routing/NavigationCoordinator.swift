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
            if sheet == .dailyCheckIn || sheet == .tradeImportReminder {
                selectTab(.home)
            }
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

    /// Explore Mode main tabs — remains ``SessionPhase/unauthenticated`` (no authenticated services).
    func markExploreExperience() {
        dismissPresentation()
        store.sessionPhase = .unauthenticated
        store.paths.resetAuth(to: .login)
        store.selectedTab = .home
        store.previousContentTab = .home
        store.paths.home = []
        store.paths.feed = []
        store.paths.messages = []
        store.paths.profile = []
        store.pendingAfterAuth = nil
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
        if DemoProtectedNavigation.interceptComposeIfNeeded(.chooser) { return }
        emit(.createActionInvoked)
        present(sheet: .composeChooser)
    }

    func openCompose(_ kind: ComposeKind) {
        if DemoProtectedNavigation.interceptComposeIfNeeded(kind) { return }
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
        case .withdrawal:
            present(fullScreen: .withdrawal)
        }
    }

    /// Add Achievement with optional production prefill (e.g. after Record Payout).
    func openComposeAchievement() {
        openCompose(.achievement)
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
        case .roomMembers, .roomInfo, .manageRoom, .roomSettings, .sharedTrade, .sharedPost, .sharedReel, .sharedAchievement, .profile, .settings:
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

    /// Opens social trade detail on the active tab stack without switching tabs.
    func pushTradeDetail(_ tradeID: TradeID, cache: DetailPresentationCache) {
        pushSocialTrade(tradeID, cache: cache)
    }

    func pushSocialTrade(_ tradeID: TradeID, cache: DetailPresentationCache? = nil) {
        ExperienceHaptics.play(.selection)
        if let cache, let trade = cache.trade(id: tradeID) {
            cache.seed(trade)
        }
        switch store.selectedTab {
        case .home:
            pushHome(.socialTrade(tradeID))
        case .feed:
            pushFeed(.trade(tradeID))
        case .messages:
            pushMessages(.sharedTrade(tradeID))
        case .profile:
            pushProfile(.trade(tradeID))
        case .create:
            break
        }
    }

    func pushPostDetail(_ postID: PostID) {
        ExperienceHaptics.play(.selection)
        switch store.selectedTab {
        case .home:
            pushHome(.post(postID))
        case .feed:
            pushFeed(.post(postID))
        case .messages:
            pushMessages(.sharedPost(postID))
        case .profile:
            pushProfile(.post(postID))
        case .create:
            break
        }
    }

    func pushReelDetail(_ reelID: ReelID) {
        ExperienceHaptics.play(.selection)
        switch store.selectedTab {
        case .home:
            pushHome(.reel(reelID))
        case .feed:
            pushFeed(.reel(reelID))
        case .messages:
            pushMessages(.sharedReel(reelID))
        case .profile:
            pushProfile(.reel(reelID))
        case .create:
            break
        }
    }

    func pushAchievementDetail(_ achievementID: AchievementID) {
        ExperienceHaptics.play(.selection)
        switch store.selectedTab {
        case .home:
            pushHome(.achievementDetail(achievementID))
        case .feed:
            pushFeed(.achievement(achievementID))
        case .messages:
            pushMessages(.sharedAchievement(achievementID))
        case .profile:
            pushProfile(.achievement(achievementID))
        case .create:
            break
        }
    }

    func pushOtherProfile(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        switch store.selectedTab {
        case .home:
            pushHome(.otherProfile(profileID))
        case .feed:
            pushFeed(.profile(profileID))
        case .messages:
            pushMessages(.profile(profileID))
        case .profile:
            pushProfile(.otherProfile(profileID))
        case .create:
            break
        }
    }

    func pushRoom(_ roomID: RoomID) {
        ExperienceHaptics.play(.selection)
        InboxMarkReadCoordinator.shared.prepareOpenRoom(roomID)
        switch store.selectedTab {
        case .home:
            pushHome(.room(roomID))
        case .feed:
            pushFeed(.room(roomID))
        case .messages:
            pushMessages(.room(roomID))
        case .profile:
            pushProfile(.room(roomID))
        case .create:
            break
        }
    }

    /// Push using an explicit tab stack (e.g. Trade Room host) without changing the selected tab.
    func pushSharedContent(
        _ reference: SharedContentReference,
        cache: DetailPresentationCache,
        host: TradeRoomNavigationHost
    ) {
        ExperienceHaptics.play(.selection)
        switch host {
        case .messages:
            pushSharedContentOnMessagesStack(reference, cache: cache)
        case .feed:
            pushSharedContentOnFeedStack(reference, cache: cache)
        case .profile:
            pushSharedContentOnProfileStack(reference, cache: cache)
        case .home:
            pushSharedContentOnHomeStack(reference, cache: cache)
        }
    }

    func pushSharedTrade(_ tradeID: TradeID, host: TradeRoomNavigationHost, cache: DetailPresentationCache? = nil) {
        ExperienceHaptics.play(.selection)
        if let cache, let trade = cache.trade(id: tradeID) {
            cache.seed(trade)
        }
        switch host {
        case .home:
            pushHome(.socialTrade(tradeID))
        case .feed:
            pushFeed(.trade(tradeID))
        case .messages:
            pushMessages(.sharedTrade(tradeID))
        case .profile:
            pushProfile(.trade(tradeID))
        }
    }

    private func pushSharedContentOnMessagesStack(_ reference: SharedContentReference, cache: DetailPresentationCache) {
        switch reference {
        case .feedPost(let postID):
            if let post = cache.post(id: postID), let tradeID = post.linkedTradeID {
                pushMessages(.sharedTrade(tradeID))
            } else {
                pushMessages(.sharedPost(postID))
            }
        case .profilePost(let postID):
            pushMessages(.sharedPost(postID))
        case .achievementPost(let postID):
            pushMessages(.sharedAchievement(AchievementID(postID.rawValue)))
        case .reel(let reelID):
            pushMessages(.sharedReel(reelID))
        case .trade(let tradeID):
            pushMessages(.sharedTrade(tradeID))
        }
    }

    private func pushSharedContentOnFeedStack(_ reference: SharedContentReference, cache: DetailPresentationCache) {
        switch reference {
        case .feedPost(let postID):
            if let post = cache.post(id: postID), let tradeID = post.linkedTradeID {
                pushFeed(.trade(tradeID))
            } else {
                pushFeed(.post(postID))
            }
        case .profilePost(let postID):
            pushFeed(.post(postID))
        case .achievementPost(let postID):
            pushFeed(.achievement(AchievementID(postID.rawValue)))
        case .reel(let reelID):
            pushFeed(.reel(reelID))
        case .trade(let tradeID):
            pushFeed(.trade(tradeID))
        }
    }

    private func pushSharedContentOnProfileStack(_ reference: SharedContentReference, cache: DetailPresentationCache) {
        switch reference {
        case .feedPost(let postID):
            if let post = cache.post(id: postID), let tradeID = post.linkedTradeID {
                pushProfile(.trade(tradeID))
            } else {
                pushProfile(.post(postID))
            }
        case .profilePost(let postID):
            pushProfile(.post(postID))
        case .achievementPost(let postID):
            pushProfile(.achievement(AchievementID(postID.rawValue)))
        case .reel(let reelID):
            pushProfile(.reel(reelID))
        case .trade(let tradeID):
            pushProfile(.trade(tradeID))
        }
    }

    private func pushSharedContentOnHomeStack(_ reference: SharedContentReference, cache: DetailPresentationCache) {
        switch reference {
        case .feedPost(let postID):
            if let post = cache.post(id: postID), let tradeID = post.linkedTradeID {
                pushHome(.socialTrade(tradeID))
            } else {
                pushHome(.post(postID))
            }
        case .profilePost(let postID):
            pushHome(.post(postID))
        case .achievementPost(let postID):
            pushHome(.achievementDetail(AchievementID(postID.rawValue)))
        case .reel(let reelID):
            pushHome(.reel(reelID))
        case .trade(let tradeID):
            pushHome(.socialTrade(tradeID))
        }
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

    /// Owner deleted a journal trade — always land on Home → Trades (not the prior screen).
    func completeTradeDeletionNavigation() {
        dismissPresentation()
        let pathBefore = store.paths.home.count
        if store.selectedTab != .home {
            store.rememberContentTabIfNeeded(.home)
            store.selectedTab = .home
            emit(.tabSelected(.home))
        }
        store.paths.home = [.trades]
        logNavigationEvent(
            action: "replace",
            source: "completeTradeDeletionNavigation",
            destination: "trades",
            tab: .home,
            pathBefore: pathBefore,
            pathAfter: store.paths.home.count
        )
        emit(.poppedToRoot(.home))
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
