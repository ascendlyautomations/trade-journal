import SwiftUI

@main
struct TradeTraxsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Single process graph — must not call ``CompositionRoot/bootstrap()`` here
    /// (``EnvironmentKey.defaultValue`` also resolves through ``AppLaunchEnvironment``).
    @State private var appEnvironment = AppLaunchEnvironment.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView(
                navigation: appEnvironment.navigation,
                themeManager: appEnvironment.themeManager,
                authenticationManager: appEnvironment.authentication.manager,
                authenticationCoordinator: appEnvironment.authentication.coordinator,
                authenticationLifecycle: appEnvironment.authentication.lifecycle,
                currentUserProfile: appEnvironment.currentUserProfile,
                appBootstrapState: appEnvironment.appBootstrapState,
                profileOnboardingGate: appEnvironment.profileOnboardingGate,
                allowsDevelopmentBypass: appEnvironment.authentication.configuration.allowsDevelopmentSessionBypass
            )
            .environment(\.appEnvironment, appEnvironment)
            .environment(\.navigationEnvironment, appEnvironment.navigation)
            .environment(appEnvironment.themeManager)
            .environment(appEnvironment.authentication.manager)
            .environment(appEnvironment.currentUserProfile)
            .environmentObject(OwnerAccountFilterDropdownController.shared)
            .onAppear {
                appDelegate.lifecycle = appEnvironment.lifecycle
                appDelegate.pushNotifications = appEnvironment.pushNotifications
                appEnvironment.lifecycle.pushNotifications = appEnvironment.pushNotifications
                appEnvironment.pushNotifications.bindIfNeeded()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uitesting-reset-auth") {
                    Task {
                        await appEnvironment.authentication.coordinator.logout()
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-uitesting-development-session") {
                    Task {
                        try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
                    }
                }
                applyDetailScreenshotLaunchArgumentsIfNeeded()
                applyProfileScreenshotLaunchArgumentsIfNeeded()
                applyProfileStatsScreenshotLaunchArgumentsIfNeeded()
                applyProfilePostsScreenshotLaunchArgumentsIfNeeded()
                applyFollowListScreenshotLaunchArgumentsIfNeeded()
                applyOtherProfileScreenshotLaunchArgumentsIfNeeded()
                applyMessagesScreenshotLaunchArgumentsIfNeeded()
                applyTradeRoomsScreenshotLaunchArgumentsIfNeeded()
                applyFeedScreenshotLaunchArgumentsIfNeeded()
                applyExploreScreenshotLaunchArgumentsIfNeeded()
                applyDashboardScreenshotLaunchArgumentsIfNeeded()
                applySettingsScreenshotLaunchArgumentsIfNeeded()
                applyCalendarScreenshotLaunchArgumentsIfNeeded()
                applyActivityScreenshotLaunchArgumentsIfNeeded()
                applyAddTradeScreenshotLaunchArgumentsIfNeeded()
                applyCreateScreenshotLaunchArgumentsIfNeeded()
                applyNavigationUITestLaunchArgumentsIfNeeded()
                #endif
            }
            .onChange(of: scenePhase) { _, newPhase in
                appEnvironment.lifecycle.handle(scenePhase: newPhase)
                if newPhase == .background {
                    appEnvironment.navigation.persistState()
                }
            }
        }
    }

    #if DEBUG
    /// Seeds detail cache + pushes Profile detail routes for simulator screenshots.
    private func applyDetailScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsTrade = args.contains("-uitesting-detail-trade")
        let wantsPost = args.contains("-uitesting-detail-post")
        let wantsClip = args.contains("-uitesting-detail-clip")
        let wantsAchievement = args.contains("-uitesting-detail-achievement")
        guard wantsTrade || wantsPost || wantsClip || wantsAchievement else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            let userID = await appEnvironment.authentication.sessionBridge.currentUserID
            let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")
            let cache = appEnvironment.data.detailCache
            let coordinator = appEnvironment.navigation.coordinator

            // Let the tab shell settle after auth before pushing detail.
            try? await Task.sleep(nanoseconds: 400_000_000)

            let engagement = appEnvironment.data.engagementStore
            if wantsTrade {
                let trade = ProfileTradeFixtures.samples(owner: profileID)[0]
                cache.seed(trade)
                cache.seed(accountNames: ProfileTradeFixtures.accountNames())
                cache.seed(accountModes: ProfileTradeFixtures.accountModes())
                cache.seed(accountSizes: ProfileTradeFixtures.accountSizes())
                engagement.seed(
                    EngagementSnapshot(likeCount: 12, commentCount: 3, viewerHasLiked: true),
                    for: .trade(trade.id)
                )
                coordinator.open(.profile(.trade(trade.id)))
            } else if wantsPost {
                let post = ProfilePostFixtures.samples(owner: profileID)[0]
                cache.seed(post)
                engagement.seed(
                    EngagementSnapshot(likeCount: 8, commentCount: 2, viewerHasLiked: false),
                    for: .profilePost(post.id)
                )
                coordinator.open(.profile(.post(post.id)))
            } else if wantsClip {
                let reel = ProfileClipFixtures.samples(owner: profileID)[0]
                cache.seed(reel)
                engagement.seed(
                    EngagementSnapshot(likeCount: 21, commentCount: 5, viewerHasLiked: true),
                    for: .reel(reel.id)
                )
                coordinator.open(.profile(.reel(reel.id)))
            } else if wantsAchievement {
                let achievement = ProfileAchievementFixtures.samples(owner: profileID)[0]
                cache.seed(achievement)
                engagement.seed(
                    EngagementSnapshot(likeCount: 15, commentCount: 4, viewerHasLiked: true),
                    for: .achievement(achievement.id)
                )
                coordinator.open(.profile(.achievement(achievement.id)))
            }
        }
    }

    /// Opens Profile trades with seeded engagement for list screenshots.
    private func applyProfileScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-profile-trades") else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            try? await Task.sleep(nanoseconds: 500_000_000)
            appEnvironment.navigation.coordinator.open(.tab(.profile))
            let profileID = ProfileID(
                await appEnvironment.authentication.sessionBridge.currentUserID?.rawValue
                    ?? "dev.screenshot"
            )
            let trades = ProfileTradeFixtures.samples(owner: profileID)
            let store = appEnvironment.data.engagementStore
            for (index, trade) in trades.enumerated() {
                store.seed(
                    EngagementSnapshot(
                        likeCount: 4 + index * 3,
                        commentCount: 1 + index,
                        viewerHasLiked: index == 0
                    ),
                    for: .trade(trade.id)
                )
            }
        }
    }

    /// Opens Profile Stats tab for simulator screenshots.
    private func applyProfileStatsScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-profile-stats") else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            try? await Task.sleep(nanoseconds: 500_000_000)
            appEnvironment.navigation.coordinator.open(.tab(.profile))
        }
    }

    /// Opens Profile Posts tab for simulator screenshots.
    private func applyProfilePostsScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-profile-posts") else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            try? await Task.sleep(nanoseconds: 500_000_000)
            appEnvironment.navigation.coordinator.open(.tab(.profile))
            let profileID = ProfileID(
                await appEnvironment.authentication.sessionBridge.currentUserID?.rawValue
                    ?? "dev.screenshot"
            )
            let posts = ProfilePostFixtures.samples(owner: profileID)
            let store = appEnvironment.data.engagementStore
            for (index, post) in posts.enumerated() {
                store.seed(
                    EngagementSnapshot(
                        likeCount: 6 + index * 2,
                        commentCount: 1 + index,
                        viewerHasLiked: index == 0
                    ),
                    for: .profilePost(post.id)
                )
            }
        }
    }

    /// Opens another user's unified Profile for simulator screenshots.
    private func applyOtherProfileScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-profile-other") else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            try? await Task.sleep(nanoseconds: 500_000_000)
            appEnvironment.navigation.coordinator.open(.tab(.profile))
            appEnvironment.navigation.coordinator.open(
                .profile(.otherProfile(ProfileID("dev.follower.ada")))
            )
        }
    }

    /// Opens Followers or Following for simulator screenshots.
    private func applyFollowListScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsFollowers = args.contains("-uitesting-profile-followers")
        let wantsFollowing = args.contains("-uitesting-profile-following")
        guard wantsFollowers || wantsFollowing else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            try? await Task.sleep(nanoseconds: 500_000_000)
            let profileID = ProfileID(
                await appEnvironment.authentication.sessionBridge.currentUserID?.rawValue
                    ?? "dev.screenshot"
            )
            appEnvironment.navigation.coordinator.open(.tab(.profile))
            if wantsFollowers {
                appEnvironment.navigation.coordinator.open(.profile(.followers(profileID)))
            } else {
                appEnvironment.navigation.coordinator.open(.profile(.following(profileID)))
            }
        }
    }

    /// Opens Messages home / conversation with fixture inbox for simulator screenshots.
    private func applyMessagesScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsHome = args.contains("-uitesting-messages-home")
        let wantsThread = args.contains("-uitesting-messages-thread")
        let wantsThreadSend = args.contains("-uitesting-messages-thread-send")
        guard wantsHome || wantsThread || wantsThreadSend else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            let viewerID = ProfileID(
                await appEnvironment.authentication.sessionBridge.currentUserID?.rawValue
                    ?? MessagesInboxFixtures.viewerID.rawValue
            )
            MessagesInboxStore.shared.invalidate()
            MessagesInboxFixtures.seedStore(MessagesInboxStore.shared, viewerID: viewerID)
            for profile in MessagesInboxFixtures.profiles(
                for: MessagesInboxStore.shared.conversations,
                viewerID: viewerID
            ) {
                appEnvironment.data.detailCache.seed(profile)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            appEnvironment.navigation.coordinator.open(.tab(.messages))

            if wantsThread || wantsThreadSend {
                let conversationID = ConversationID("dev-dm-ada")
                try? await Task.sleep(nanoseconds: 350_000_000)
                appEnvironment.navigation.coordinator.open(.messages(.thread(conversationID)))
            }
        }
    }

    private func applyTradeRoomsScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsHome = args.contains("-uitesting-trade-rooms-home")
        let wantsRoom = args.contains("-uitesting-trade-rooms-conversation")
            || args.contains("-uitesting-trade-rooms-channel-trades")
        let wantsMembers = args.contains("-uitesting-trade-rooms-members")
        guard wantsHome || wantsRoom || wantsMembers else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            let viewerID = ProfileID(
                await appEnvironment.authentication.sessionBridge.currentUserID?.rawValue
                    ?? TradeRoomsFixtures.viewerID.rawValue
            )
            MessagesInboxStore.shared.invalidate()
            TradeRoomsFixtures.seedInbox(MessagesInboxStore.shared, viewerID: viewerID)
            for profile in MessagesInboxFixtures.profiles(
                for: MessagesInboxStore.shared.conversations,
                viewerID: viewerID
            ) {
                appEnvironment.data.detailCache.seed(profile)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            appEnvironment.navigation.coordinator.open(.feed(.rooms))

            if wantsRoom || wantsMembers {
                try? await Task.sleep(nanoseconds: 350_000_000)
                appEnvironment.navigation.coordinator.open(
                    .feed(.room(TradeRoomsFixtures.deskRoomID))
                )
            }
            if wantsMembers {
                try? await Task.sleep(nanoseconds: 450_000_000)
                appEnvironment.navigation.coordinator.open(
                    .feed(.roomMembers(TradeRoomsFixtures.deskRoomID))
                )
            }
        }
    }

    private func applyFeedScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-feed-home") || args.contains("-uitesting-feed-text-only") else {
            return
        }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            let viewerID = ProfileID(
                await appEnvironment.authentication.sessionBridge.currentUserID?.rawValue
                    ?? FeedFixtures.viewerID.rawValue
            )
            FeedFixtures.seedDetailCache(appEnvironment.data.detailCache, viewerID: viewerID)
            appEnvironment.navigation.store.selectedTab = .feed
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    private func applyExploreScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsExplore = args.contains("-uitesting-explore-home")
        let wantsSearch = args.contains("-uitesting-explore-search")
        guard wantsExplore || wantsSearch else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            let viewerID = ProfileID(
                await appEnvironment.authentication.sessionBridge.currentUserID?.rawValue
                    ?? ExploreFixtures.viewerID.rawValue
            )
            ExploreSessionStore.shared.invalidate()
            ExploreFixtures.seedDetailCache(appEnvironment.data.detailCache, viewer: viewerID)
            ExploreSessionStore.shared.applyBootstrap(
                traders: ExploreFixtures.traders(excluding: viewerID),
                rooms: ExploreFixtures.rooms(),
                following: [],
                tradersNextCursor: nil
            )
            try? await Task.sleep(nanoseconds: 500_000_000)
            appEnvironment.navigation.coordinator.open(.tab(.feed))
            appEnvironment.navigation.coordinator.open(.feed(.explore))
        }
    }

    private func applyDashboardScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-dashboard-home")
            || args.contains("-uitesting-dashboard-propfirm")
            || args.contains("-uitesting-propfirm-detail")
        else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            appEnvironment.navigation.store.selectedTab = .home
            try? await Task.sleep(nanoseconds: 900_000_000)

            if args.contains("-uitesting-propfirm-detail") {
                appEnvironment.navigation.coordinator.open(
                    .home(.propFirm(PropFirmFixtures.accountID))
                )
            }
        }
    }

    private func applySettingsScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsHome = args.contains("-uitesting-settings-home")
        let wantsAccount = args.contains("-uitesting-settings-account")
        let wantsNotifications = args.contains("-uitesting-settings-notifications")
        let wantsMessages = args.contains("-uitesting-settings-notifications-messages")
        let wantsSubscription = args.contains("-uitesting-settings-subscription")
        let wantsPrivacy = args.contains("-uitesting-settings-privacy")
        guard wantsHome || wantsAccount || wantsNotifications || wantsMessages
            || wantsSubscription || wantsPrivacy
        else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            // Allow splash → authenticated shell to settle before pushing Settings.
            try? await Task.sleep(nanoseconds: 1_200_000_000)

            var stack: [SettingsRoute] = [.home]
            if wantsAccount { stack.append(.account) }
            else if wantsMessages { stack.append(contentsOf: [.notifications, .notificationsMessages]) }
            else if wantsNotifications { stack.append(.notifications) }
            else if wantsSubscription { stack.append(.subscription) }
            else if wantsPrivacy { stack.append(.privacy) }

            appEnvironment.navigation.coordinator.open(.settingsStack(stack))
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func applyCalendarScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsHome = args.contains("-uitesting-calendar-home")
        let wantsAccount = args.contains("-uitesting-calendar-account")
        let wantsDay = args.contains("-uitesting-calendar-day")
        guard wantsHome || wantsAccount || wantsDay else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            appEnvironment.navigation.coordinator.open(.home(.calendar))
            if wantsDay {
                try? await Task.sleep(nanoseconds: 800_000_000)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TradingCalendarDay.timeZone
                let comps = calendar.dateComponents([.year, .month], from: Date())
                let dayKey = String(
                    format: "%04d-%02d-%02d",
                    comps.year ?? 2026,
                    comps.month ?? 8,
                    8
                )
                appEnvironment.navigation.coordinator.open(.home(.tradingDay(dayKey)))
            }
        }
    }

    private func applyActivityScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsMixed = args.contains("-uitesting-activity-home")
        let wantsUnread = args.contains("-uitesting-activity-unread")
        let wantsEmpty = args.contains("-uitesting-activity-empty")
        let wantsFollowRequests = args.contains("-uitesting-activity-follow-requests")
        guard wantsMixed || wantsUnread || wantsEmpty || wantsFollowRequests else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            ActivityInboxStore.shared.invalidate()
            for profile in ActivityFixtures.profiles() {
                appEnvironment.data.detailCache.seed(profile)
            }
            if wantsEmpty {
                ActivityInboxStore.shared.replace(
                    items: [],
                    unreadCount: 0,
                    nextCursor: nil,
                    pendingFollowRequestCount: 0
                )
            } else {
                ActivityFixtures.seedStore(
                    ActivityInboxStore.shared,
                    unreadCount: wantsUnread || wantsMixed ? 2 : nil
                )
                if wantsMixed, !wantsUnread {
                    // Mixed types with subtle unread treatment.
                }
            }
            if wantsFollowRequests {
                ActivityInboxStore.shared.setPendingFollowRequestCount(
                    ActivityFixtures.followRequests().count
                )
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            appEnvironment.navigation.coordinator.open(.profile(.activity))
            if wantsFollowRequests {
                try? await Task.sleep(nanoseconds: 500_000_000)
                appEnvironment.navigation.coordinator.open(.profile(.followRequests))
            }
        }
    }

    private func applyAddTradeScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsHome = args.contains("-uitesting-addtrade-home")
        let wantsFilled = args.contains("-uitesting-addtrade-filled")
        let wantsReview = args.contains("-uitesting-addtrade-review")
        let wantsMedia = args.contains("-uitesting-addtrade-media")
        let wantsValidation = args.contains("-uitesting-addtrade-validation")
        let wantsReel = args.contains("-uitesting-addtrade-reel")
            || args.contains("-uitesting-addtrade-reel-draft")
            || args.contains("-uitesting-addtrade-reel-picker")
            || args.contains("-uitesting-addtrade-reel-selected")
        let wantsCustom = args.contains("-uitesting-addtrade-custom")
        let wantsCompact = args.contains("-uitesting-addtrade-compact")
        guard wantsHome || wantsFilled || wantsReview || wantsMedia || wantsValidation || wantsReel
            || wantsCustom || wantsCompact
        else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            // Wait for shell to settle after development session bootstrap.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            appEnvironment.navigation.coordinator.openCompose(.trade)
        }
    }

    private func applyCreateScreenshotLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let wantsChooser = args.contains("-uitesting-create-chooser")
        let wantsPost = args.contains("-uitesting-create-post")
            || args.contains("-uitesting-create-post-filled")
        let wantsAchievement = args.contains("-uitesting-create-achievement")
            || args.contains("-uitesting-create-achievement-filled")
        let wantsReel = args.contains("-uitesting-create-reel")
            || args.contains("-uitesting-create-reel-filled")
        guard wantsChooser || wantsPost || wantsAchievement || wantsReel else { return }

        Task { @MainActor in
            try? await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if wantsChooser {
                appEnvironment.navigation.coordinator.invokeCreateAction()
            } else if wantsPost {
                appEnvironment.navigation.coordinator.openCompose(.post)
            } else if wantsAchievement {
                appEnvironment.navigation.coordinator.openCompose(.achievement)
            } else if wantsReel {
                appEnvironment.navigation.coordinator.openCompose(.reel)
            }
        }
    }

    /// Seeds a deterministic authenticated shell for rendered navigation UI tests.
    private func applyNavigationUITestLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-navigation-shell") else { return }

        Task { @MainActor in
            await appEnvironment.authentication.coordinator.logout()
            try await appEnvironment.authentication.coordinator.continueAsDevelopmentSessionIfAllowed()
            let viewerID = ProfileID(
                await appEnvironment.authentication.sessionBridge.currentUserID?.rawValue
                    ?? MessagesInboxFixtures.viewerID.rawValue
            )

            MessagesInboxStore.shared.invalidate()
            MessagesInboxFixtures.seedStore(MessagesInboxStore.shared, viewerID: viewerID)
            for profile in MessagesInboxFixtures.profiles(
                for: MessagesInboxStore.shared.conversations,
                viewerID: viewerID
            ) {
                appEnvironment.data.detailCache.seed(profile)
            }

            ActivityInboxStore.shared.invalidate()
            for profile in ActivityFixtures.profiles() {
                appEnvironment.data.detailCache.seed(profile)
            }
            ActivityFixtures.seedStore(ActivityInboxStore.shared, unreadCount: 2)

            appEnvironment.navigation.store.selectedTab = .home
            if args.contains("-uitesting-navigation-start-trades") {
                appEnvironment.navigation.coordinator.pushHome(.trades)
            }
            if args.contains("-uitesting-navigation-start-trades-manage-accounts") {
                appEnvironment.navigation.coordinator.pushHome(.trades)
                appEnvironment.navigation.coordinator.pushHome(.settings(.tradingAccounts))
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }
    #endif
}
