import Foundation
import OSLog

/// Data subgraph injected through ``DependencyContainer``.
///
/// CompositionRoot → AppEnvironment → DependencyContainer → DataEnvironment
final class DataEnvironment {
    let configuration: DataConfiguration
    let supabase: SupabaseInfrastructure
    let session: any SessionProviding
    let cache: CacheStack
    let persistence: any PersistenceProviding
    let realtimeHub: RealtimeHub
    let imagePipeline: any ImagePipeline
    let uploadService: any UploadService
    let downloadService: any DownloadService
    let objectStorage: any ObjectStorageProviding
    let edgeFunctions: any EdgeFunctionClient
    let rpc: any RPCClient
    /// Profile / Feed list → detail seed cache (no duplicate entity fetches).
    let detailCache: DetailPresentationCache

    let trades: any TradeRepository
    let tradeDetailRepository: any TradeDetailRepository
    let profiles: any ProfileRepository
    let feed: any FeedRepository
    let messages: any MessageRepository
    let rooms: any RoomRepository
    let notifications: any NotificationRepository
    let followRequests: any FollowRequestRepository
    let calendar: any CalendarRepository
    let leaderboard: any LeaderboardRepository
    let explore: any ExploreRepository
    let search: any SearchRepository
    let billing: any BillingRepository
    let storeKitSubscriptions: any StoreKitSubscriptionServicing
    let account: any AccountRepository
    let analytics: any AnalyticsRepository
    let achievements: any AchievementRepository
    let referrals: any ReferralRepository
    let notificationPreferences: any NotificationPreferencesRepository
    let authentication: any AuthenticationRepository
    let home: any HomeRepository
    /// Platform likes/comments — content-agnostic (Trade / Post / Clip / Feed).
    let interactions: any InteractionRepository
    /// Session-scoped engagement cache shared by lists + detail.
    let engagementStore: EngagementStore
    /// Shared BFF AI contracts (analyze-trade, future coach endpoints).
    let ai: any AIRepository
    /// Dashboard Trading Reports — web-parity deterministic generator + notify.
    let tradingReports: any TradingReportRepository
    let psychologyReports: any PsychologyReportRepository
    let dailyCheckIns: any TraderDailyCheckInRepository
    let contentReports: any ContentReportRepository
    let userSubmissions: any UserSubmissionRepository
    let vault: any VaultRepository
    /// Session-scoped private Vault cache — shared by Feed, detail, and Vault home.
    let vaultStore: VaultStore
    let brokerIntegrations: any BrokerIntegrationRepository
    let adminUsers: any AdminUsersRepository
    let adminContentReports: any AdminContentReportsRepository
    let adminBugReports: any AdminBugReportsRepository
    let adminSupportTickets: any AdminSupportTicketsRepository
    let adminProductFeedback: any AdminProductFeedbackRepository
    let adminUsageAnalytics: any AdminUsageAnalyticsRepository

    init(
        configuration: DataConfiguration,
        supabase: SupabaseInfrastructure,
        session: any SessionProviding,
        cache: CacheStack,
        persistence: any PersistenceProviding,
        realtimeHub: RealtimeHub,
        imagePipeline: any ImagePipeline,
        uploadService: any UploadService,
        downloadService: any DownloadService,
        objectStorage: any ObjectStorageProviding,
        edgeFunctions: any EdgeFunctionClient,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        trades: any TradeRepository,
        tradeDetailRepository: any TradeDetailRepository,
        profiles: any ProfileRepository,
        feed: any FeedRepository,
        messages: any MessageRepository,
        rooms: any RoomRepository,
        notifications: any NotificationRepository,
        followRequests: any FollowRequestRepository,
        calendar: any CalendarRepository,
        leaderboard: any LeaderboardRepository,
        explore: any ExploreRepository,
        search: any SearchRepository,
        billing: any BillingRepository,
        storeKitSubscriptions: any StoreKitSubscriptionServicing,
        account: any AccountRepository,
        analytics: any AnalyticsRepository,
        achievements: any AchievementRepository,
        referrals: any ReferralRepository,
        notificationPreferences: any NotificationPreferencesRepository,
        authentication: any AuthenticationRepository,
        home: any HomeRepository,
        interactions: any InteractionRepository,
        engagementStore: EngagementStore,
        ai: any AIRepository,
        tradingReports: any TradingReportRepository,
        psychologyReports: any PsychologyReportRepository,
        dailyCheckIns: any TraderDailyCheckInRepository,
        contentReports: any ContentReportRepository,
        userSubmissions: any UserSubmissionRepository,
        vault: any VaultRepository,
        vaultStore: VaultStore,
        brokerIntegrations: any BrokerIntegrationRepository,
        adminUsers: any AdminUsersRepository,
        adminContentReports: any AdminContentReportsRepository,
        adminBugReports: any AdminBugReportsRepository,
        adminSupportTickets: any AdminSupportTicketsRepository,
        adminProductFeedback: any AdminProductFeedbackRepository,
        adminUsageAnalytics: any AdminUsageAnalyticsRepository
    ) {
        self.configuration = configuration
        self.supabase = supabase
        self.session = session
        self.cache = cache
        self.persistence = persistence
        self.realtimeHub = realtimeHub
        self.imagePipeline = imagePipeline
        self.uploadService = uploadService
        self.downloadService = downloadService
        self.objectStorage = objectStorage
        self.edgeFunctions = edgeFunctions
        self.rpc = rpc
        self.detailCache = detailCache
        self.trades = trades
        self.tradeDetailRepository = tradeDetailRepository
        self.profiles = profiles
        self.feed = feed
        self.messages = messages
        self.rooms = rooms
        self.notifications = notifications
        self.followRequests = followRequests
        self.calendar = calendar
        self.leaderboard = leaderboard
        self.explore = explore
        self.search = search
        self.billing = billing
        self.storeKitSubscriptions = storeKitSubscriptions
        self.account = account
        self.analytics = analytics
        self.achievements = achievements
        self.referrals = referrals
        self.notificationPreferences = notificationPreferences
        self.authentication = authentication
        self.home = home
        self.interactions = interactions
        self.engagementStore = engagementStore
        self.ai = ai
        self.tradingReports = tradingReports
        self.psychologyReports = psychologyReports
        self.dailyCheckIns = dailyCheckIns
        self.contentReports = contentReports
        self.userSubmissions = userSubmissions
        self.vault = vault
        self.vaultStore = vaultStore
        self.brokerIntegrations = brokerIntegrations
        self.adminUsers = adminUsers
        self.adminContentReports = adminContentReports
        self.adminBugReports = adminBugReports
        self.adminSupportTickets = adminSupportTickets
        self.adminProductFeedback = adminProductFeedback
        self.adminUsageAnalytics = adminUsageAnalytics
    }

    enum LaunchMode: Sendable {
        case production
        /// Logged-out shell — no realtime boot, no session store wiring, unconfigured Supabase seam.
        case loginShell
        /// Explore Mode — local demo journal + guest public community repositories.
        case demoExplore
    }

    static func make(
        appConfiguration: AppConfiguration,
        networking: NetworkingEnvironment? = nil,
        session: any SessionProviding,
        authenticationManager: AuthenticationManager,
        launchMode: LaunchMode = .production
    ) -> DataEnvironment {
        if launchMode == .loginShell {
            return makeLoginShell(
                appConfiguration: appConfiguration,
                session: session,
                authenticationManager: authenticationManager
            )
        }
        if launchMode == .demoExplore {
            guard let networking else {
                fatalError("DataEnvironment demoExplore requires NetworkingEnvironment for guest community reads")
            }
            return makeDemoExploreShell(
                appConfiguration: appConfiguration,
                networking: networking,
                authenticationManager: authenticationManager
            )
        }
        guard let networking else {
            fatalError("DataEnvironment production launch requires NetworkingEnvironment")
        }
        let configuration = DataConfiguration.make(for: appConfiguration)
        let supabase = SupabaseInfrastructure.make(
            appConfiguration: appConfiguration,
            networking: networking,
            session: session
        )
        let imageCache = TieredImageCache()
        let cache = CacheStack(
            memory: PlaceholderMemoryCache(),
            disk: PlaceholderDiskCache(),
            images: imageCache,
            queries: PlaceholderQueryCache()
        )
        let persistence = PlaceholderPersistenceProvider()
        let realtimeHub = RealtimeHub(realtime: supabase.realtime)
        let storage = SupabaseObjectStorageProvider(storage: supabase.storage)
        let uploadService = DefaultUploadService(storage: storage)
        let downloadService = DefaultDownloadService(storage: storage)
        let imagePipeline = DefaultImagePipeline(
            cache: imageCache,
            storage: storage,
            downloadService: downloadService
        )
        let edgeFunctions = DefaultEdgeFunctionClient(provider: supabase.edgeFunctions)
        let rpc = DefaultRPCClient(provider: supabase.rpc, database: supabase.database)

        if configuration.enablesRealtime, supabase.client.isConfigured {
            realtimeHub.start()
        }
        RealtimePressureSnapshotProvider.bind(realtimeHub: realtimeHub)

        AppLog.application.info(
            "DataEnvironment ready — Supabase configured=\(supabase.client.isConfigured, privacy: .public)"
        )

        let defaultProfiles = DefaultProfileRepository(
            supabase: supabase,
            cache: cache,
            session: session
        )
        #if DEBUG
        let profiles: any ProfileRepository = DevelopmentProfileRepository(wrapping: defaultProfiles)
        #else
        let profiles: any ProfileRepository = defaultProfiles
        #endif

        let interactions: any InteractionRepository = DefaultInteractionRepository(
            supabase: supabase,
            session: session
        )
        let vaultRepository: any VaultRepository = DefaultVaultRepository(
            supabase: supabase,
            session: session
        )
        let tradesRepository: any TradeRepository = DefaultTradeRepository(
            supabase: supabase,
            cache: cache,
            session: session
        )
        let detailCache = DetailPresentationCache()
        let tradeDetailRepository: any TradeDetailRepository = DefaultTradeDetailRepository(
            trades: tradesRepository,
            session: session,
            detailCache: detailCache
        )
        let vaultStore = makeVaultStore(repository: vaultRepository, session: session)
        TradeJournalMutationStore.shared.configure(detailCache: detailCache, vaultStore: vaultStore)
        ContentMutationStore.shared.configure(vaultStore: vaultStore)
        GettingStartedStore.shared.configure(
            rpc: rpc,
            session: session,
            realtimeHub: realtimeHub
        )
        let dailyCheckInRepository: any TraderDailyCheckInRepository = DefaultTraderDailyCheckInRepository(
            supabase: supabase,
            cache: cache
        )
        TraderDailyCheckInStore.shared.configure(
            repository: dailyCheckInRepository,
            session: session,
            realtimeHub: realtimeHub
        )
        AnalyticsRevisionRepairNetworkObserver.shared.configure(
            reachability: networking.reachability
        )

        let transport = supabase.transport ?? SupabaseTransport(
            client: networking.client,
            requestBuilder: networking.requestBuilder,
            configuration: appConfiguration
        )
        let appleSubscriptionSync = AppleSubscriptionSyncClient(transport: transport)
        let storeKitSubscriptions: any StoreKitSubscriptionServicing = StoreKitSubscriptionService(
            syncClient: appleSubscriptionSync
        )
        let billing: any BillingRepository = DefaultBillingRepository(
            supabase: supabase,
            cache: cache,
            storeKitSync: storeKitSubscriptions,
            entitlementClient: appleSubscriptionSync
        )

        let engagementStore = makeEngagementStore(interactions: interactions, session: session)
        return DataEnvironment(
            configuration: configuration,
            supabase: supabase,
            session: session,
            cache: cache,
            persistence: persistence,
            realtimeHub: realtimeHub,
            imagePipeline: imagePipeline,
            uploadService: uploadService,
            downloadService: downloadService,
            objectStorage: storage,
            edgeFunctions: edgeFunctions,
            rpc: rpc,
            detailCache: detailCache,
            trades: tradesRepository,
            tradeDetailRepository: tradeDetailRepository,
            profiles: profiles,
            feed: DefaultFeedRepository(supabase: supabase, cache: cache, session: session),
            messages: DefaultMessageRepository(supabase: supabase, cache: cache, session: session),
            rooms: DefaultRoomRepository(supabase: supabase, cache: cache),
            notifications: DefaultNotificationRepository(
                supabase: supabase,
                cache: cache,
                session: session
            ),
            followRequests: DefaultFollowRequestRepository(
                supabase: supabase,
                session: session
            ),
            calendar: DefaultCalendarRepository(supabase: supabase, cache: cache),
            leaderboard: DefaultLeaderboardRepository(),
            explore: DefaultExploreRepository(supabase: supabase),
            search: DefaultSearchRepository(supabase: supabase, cache: cache),
            billing: billing,
            storeKitSubscriptions: storeKitSubscriptions,
            account: DefaultAccountRepository(supabase: supabase),
            analytics: DefaultAnalyticsRepository(supabase: supabase),
            achievements: DefaultAchievementRepository(supabase: supabase, cache: cache),
            referrals: DefaultReferralRepository(supabase: supabase, cache: cache),
            notificationPreferences: DefaultNotificationPreferencesRepository(
                supabase: supabase,
                cache: cache
            ),
            authentication: DefaultAuthenticationRepository(manager: authenticationManager),
            home: DefaultHomeRepository(supabase: supabase, cache: cache, session: session),
            interactions: interactions,
            engagementStore: engagementStore,
            ai: DefaultAIRepository(supabase: supabase, session: session),
            tradingReports: DefaultTradingReportRepository(
                trades: tradesRepository,
                session: session,
                detailCache: detailCache,
                supabase: supabase
            ),
            psychologyReports: DefaultPsychologyReportRepository(
                trades: tradesRepository,
                dailyCheckIns: dailyCheckInRepository,
                session: session,
                detailCache: detailCache
            ),
            dailyCheckIns: dailyCheckInRepository,
            contentReports: DefaultContentReportRepository(supabase: supabase),
            userSubmissions: DefaultUserSubmissionRepository(
                supabase: supabase,
                session: session,
                profiles: profiles
            ),
            vault: vaultRepository,
            vaultStore: vaultStore,
            brokerIntegrations: {
                let repository = DefaultBrokerIntegrationRepository(transport: transport)
                BrokerImportEligibilityStore.shared.configure(
                    broker: repository,
                    session: session
                )
                return repository
            }(),
            adminUsers: DefaultAdminUsersRepository(supabase: supabase),
            adminContentReports: DefaultAdminContentReportsRepository(supabase: supabase),
            adminBugReports: DefaultAdminBugReportsRepository(supabase: supabase),
            adminSupportTickets: DefaultAdminSupportTicketsRepository(supabase: supabase),
            adminProductFeedback: DefaultAdminProductFeedbackRepository(supabase: supabase),
            adminUsageAnalytics: DefaultAdminUsageAnalyticsRepository(supabase: supabase)
        )
    }

    private static func makeLoginShell(
        appConfiguration: AppConfiguration,
        session: any SessionProviding,
        authenticationManager: AuthenticationManager
    ) -> DataEnvironment {
        // Login shell uses `SupabaseInfrastructure.unconfigured` (no transport). Production
        // `Default*` repos are inert at init except `DefaultContentReportRepository`, which
        // must not be constructed here — use `LoginShellContentReportRepository` instead.
        let configuration = StartupTrace.measure("LoginShell.DataConfiguration") {
            DataConfiguration.make(for: appConfiguration)
        }
        let supabase = SupabaseInfrastructure.unconfigured
        let cache = CacheStack.placeholder()
        let persistence = PlaceholderPersistenceProvider()
        let realtimeHub = StartupTrace.measure("LoginShell.RealtimeHub") {
            RealtimeHub(realtime: supabase.realtime)
        }
        let storage = SupabaseObjectStorageProvider(storage: supabase.storage)
        let uploadService = DefaultUploadService(storage: storage)
        let downloadService = DefaultDownloadService(storage: storage)
        // Login does not load media — avoid DefaultImagePipeline / URLSession.shared / ImageIO on cold launch.
        let imagePipeline: any ImagePipeline = StartupTrace.measure("LoginShell.ImagePipeline") {
            PlaceholderImagePipeline()
        }
        let edgeFunctions = DefaultEdgeFunctionClient(provider: supabase.edgeFunctions)
        let rpc = DefaultRPCClient(provider: supabase.rpc, database: supabase.database)
        let detailCache = DetailPresentationCache()
        let defaultProfiles = DefaultProfileRepository(
            supabase: supabase,
            cache: cache,
            session: session
        )
        #if DEBUG
        let profiles: any ProfileRepository = StartupTrace.measure("LoginShell.Profiles") {
            DevelopmentProfileRepository(wrapping: defaultProfiles)
        }
        #else
        let profiles: any ProfileRepository = defaultProfiles
        #endif
        let interactions: any InteractionRepository = DefaultInteractionRepository(
            supabase: supabase,
            session: session
        )
        let vaultRepository: any VaultRepository = DefaultVaultRepository(
            supabase: supabase,
            session: session
        )
        let tradesRepository: any TradeRepository = DefaultTradeRepository(
            supabase: supabase,
            cache: cache,
            session: session
        )
        let tradeDetailRepository: any TradeDetailRepository = DefaultTradeDetailRepository(
            trades: tradesRepository,
            session: session,
            detailCache: detailCache
        )
        let loginShellBillingClient = LoginShellAppleSubscriptionSyncClient()
        let storeKitSubscriptions: any StoreKitSubscriptionServicing = StoreKitSubscriptionService(
            syncClient: loginShellBillingClient
        )
        let repositories = StartupTrace.measure("LoginShell.Repositories") {
            (
                feed: DefaultFeedRepository(supabase: supabase, cache: cache, session: session),
                messages: DefaultMessageRepository(supabase: supabase, cache: cache, session: session),
                rooms: DefaultRoomRepository(supabase: supabase, cache: cache),
                notifications: DefaultNotificationRepository(
                    supabase: supabase,
                    cache: cache,
                    session: session
                ),
                followRequests: DefaultFollowRequestRepository(supabase: supabase, session: session),
                calendar: DefaultCalendarRepository(supabase: supabase, cache: cache),
                leaderboard: DefaultLeaderboardRepository(),
                explore: DefaultExploreRepository(supabase: supabase),
                search: DefaultSearchRepository(supabase: supabase, cache: cache),
                billing: DefaultBillingRepository(
                    supabase: supabase,
                    cache: cache,
                    storeKitSync: storeKitSubscriptions,
                    entitlementClient: loginShellBillingClient
                ),
                account: DefaultAccountRepository(supabase: supabase),
                analytics: DefaultAnalyticsRepository(supabase: supabase),
                achievements: DefaultAchievementRepository(supabase: supabase, cache: cache),
                referrals: DefaultReferralRepository(supabase: supabase, cache: cache),
                notificationPreferences: DefaultNotificationPreferencesRepository(
                    supabase: supabase,
                    cache: cache
                ),
                home: DefaultHomeRepository(supabase: supabase, cache: cache, session: session),
                ai: DefaultAIRepository(supabase: supabase, session: session),
                dailyCheckIns: DefaultTraderDailyCheckInRepository(supabase: supabase, cache: cache),
                psychologyReports: DefaultPsychologyReportRepository(
                    trades: tradesRepository,
                    dailyCheckIns: DefaultTraderDailyCheckInRepository(supabase: supabase, cache: cache),
                    session: session,
                    detailCache: detailCache
                ),
                tradingReports: DefaultTradingReportRepository(
                    trades: tradesRepository,
                    session: session,
                    detailCache: detailCache,
                    supabase: supabase
                )
            )
        }
        AppLog.application.info("DataEnvironment ready — login shell (deferred production stack)")

        return DataEnvironment(
            configuration: configuration,
            supabase: supabase,
            session: session,
            cache: cache,
            persistence: persistence,
            realtimeHub: realtimeHub,
            imagePipeline: imagePipeline,
            uploadService: uploadService,
            downloadService: downloadService,
            objectStorage: storage,
            edgeFunctions: edgeFunctions,
            rpc: rpc,
            detailCache: detailCache,
            trades: tradesRepository,
            tradeDetailRepository: tradeDetailRepository,
            profiles: profiles,
            feed: repositories.feed,
            messages: repositories.messages,
            rooms: repositories.rooms,
            notifications: repositories.notifications,
            followRequests: repositories.followRequests,
            calendar: repositories.calendar,
            leaderboard: repositories.leaderboard,
            explore: repositories.explore,
            search: repositories.search,
            billing: repositories.billing,
            storeKitSubscriptions: storeKitSubscriptions,
            account: repositories.account,
            analytics: repositories.analytics,
            achievements: repositories.achievements,
            referrals: repositories.referrals,
            notificationPreferences: repositories.notificationPreferences,
            authentication: DefaultAuthenticationRepository(manager: authenticationManager),
            home: repositories.home,
            interactions: interactions,
            engagementStore: makeEngagementStore(interactions: interactions, session: session),
            ai: repositories.ai,
            tradingReports: repositories.tradingReports,
            psychologyReports: repositories.psychologyReports,
            dailyCheckIns: repositories.dailyCheckIns,
            contentReports: LoginShellContentReportRepository(),
            userSubmissions: LoginShellUserSubmissionRepository(),
            vault: vaultRepository,
            vaultStore: VaultStore(repository: vaultRepository),
            brokerIntegrations: LoginShellBrokerIntegrationRepository(),
            adminUsers: LoginShellAdminUsersRepository(),
            adminContentReports: LoginShellAdminContentReportsRepository(),
            adminBugReports: LoginShellAdminBugReportsRepository(),
            adminSupportTickets: LoginShellAdminSupportTicketsRepository(),
            adminProductFeedback: LoginShellAdminProductFeedbackRepository(),
            adminUsageAnalytics: LoginShellAdminUsageAnalyticsRepository()
        )
    }

    /// Logged-out Explore Mode — ``ExploreGuestRepositories`` + local demo journal repositories.
    private static func makeDemoExploreShell(
        appConfiguration: AppConfiguration,
        networking: NetworkingEnvironment,
        authenticationManager: AuthenticationManager
    ) -> DataEnvironment {
        let configuration = DataConfiguration.make(for: appConfiguration)
        let session: any SessionProviding = DemoSessionProvider()
        let supabase = SupabaseInfrastructure.make(
            appConfiguration: appConfiguration,
            networking: networking,
            session: session
        )
        let imageCache = TieredImageCache()
        let cache = CacheStack(
            memory: PlaceholderMemoryCache(),
            disk: PlaceholderDiskCache(),
            images: imageCache,
            queries: PlaceholderQueryCache()
        )
        let persistence = PlaceholderPersistenceProvider()
        let realtimeHub = RealtimeHub(realtime: supabase.realtime)
        let storage = SupabaseObjectStorageProvider(storage: supabase.storage)
        let uploadService = DefaultUploadService(storage: storage)
        let downloadService = DefaultDownloadService(storage: storage)
        let imagePipeline: any ImagePipeline = DefaultImagePipeline(
            cache: imageCache,
            storage: storage,
            downloadService: downloadService
        )
        let edgeFunctions = DefaultEdgeFunctionClient(provider: supabase.edgeFunctions)
        let rpc = DefaultRPCClient(provider: supabase.rpc, database: supabase.database)
        let detailCache = DetailPresentationCache()
        MainActor.assumeIsolated {
            DemoCanonicalDataset.seedDetailCache(detailCache)
        }

        let tradesRepository: any TradeRepository = DemoTradeRepository()
        let tradeDetailRepository: any TradeDetailRepository = DefaultTradeDetailRepository(
            trades: tradesRepository,
            session: session,
            detailCache: detailCache
        )
        let profiles: any ProfileRepository = DemoProfileRepository()
        let achievements: any AchievementRepository = DemoAchievementRepository()
        let interactions: any InteractionRepository = DemoInteractionRepository()
        let feedRepository: any FeedRepository = DemoFeedRepository()
        let exploreRepository: any ExploreRepository = DemoExploreRepository()
        let roomsRepository: any RoomRepository = DemoExploreRoomsRepository(supabase: supabase, cache: cache)
        let messagesRepository: any MessageRepository = DemoExploreMessageRepository()
        let storeKitSubscriptions: any StoreKitSubscriptionServicing = DemoStoreKitSubscriptionService()

        let psychologyReports: any PsychologyReportRepository = DefaultPsychologyReportRepository(
            trades: DemoTradeRepository(),
            dailyCheckIns: DemoCheckInRepository(),
            session: session,
            detailCache: detailCache
        )
        let tradingReports: any TradingReportRepository = DefaultTradingReportRepository(
            trades: DemoTradeRepository(),
            session: session,
            detailCache: detailCache,
            supabase: supabase
        )

        AppLog.application.info(
            "DataEnvironment ready — explore (local journal + guest Feed/Explore/Rooms; configured=\(supabase.client.isConfigured, privacy: .public))"
        )

        return DataEnvironment(
            configuration: configuration,
            supabase: supabase,
            session: session,
            cache: cache,
            persistence: persistence,
            realtimeHub: realtimeHub,
            imagePipeline: imagePipeline,
            uploadService: uploadService,
            downloadService: downloadService,
            objectStorage: storage,
            edgeFunctions: edgeFunctions,
            rpc: rpc,
            detailCache: detailCache,
            trades: tradesRepository,
            tradeDetailRepository: tradeDetailRepository,
            profiles: profiles,
            feed: feedRepository,
            messages: messagesRepository,
            rooms: roomsRepository,
            notifications: DemoNotificationRepository(),
            followRequests: DemoFollowRequestRepository(),
            calendar: DemoCalendarRepository(),
            leaderboard: DefaultLeaderboardRepository(),
            explore: exploreRepository,
            search: DemoSearchRepository(),
            billing: DemoBillingRepository(),
            storeKitSubscriptions: storeKitSubscriptions,
            account: DemoAccountRepository(),
            analytics: DemoAnalyticsRepository(),
            achievements: achievements,
            referrals: DemoReferralRepository(),
            notificationPreferences: DemoNotificationPreferencesRepository(),
            authentication: DefaultAuthenticationRepository(manager: authenticationManager),
            home: DemoHomeRepository(),
            interactions: interactions,
            engagementStore: makeEngagementStore(interactions: interactions, session: session),
            ai: DemoAIRepository(),
            tradingReports: tradingReports,
            psychologyReports: psychologyReports,
            dailyCheckIns: DemoCheckInRepository(),
            contentReports: LoginShellContentReportRepository(),
            userSubmissions: DemoUserSubmissionRepository(),
            vault: DemoVaultRepository(),
            vaultStore: VaultStore(repository: DemoVaultRepository()),
            brokerIntegrations: LoginShellBrokerIntegrationRepository(),
            adminUsers: LoginShellAdminUsersRepository(),
            adminContentReports: LoginShellAdminContentReportsRepository(),
            adminBugReports: LoginShellAdminBugReportsRepository(),
            adminSupportTickets: LoginShellAdminSupportTicketsRepository(),
            adminProductFeedback: LoginShellAdminProductFeedbackRepository(),
            adminUsageAnalytics: LoginShellAdminUsageAnalyticsRepository()
        )
    }
    @MainActor
    private static func makeEngagementStore(
        interactions: any InteractionRepository,
        session: any SessionProviding
    ) -> EngagementStore {
        SocialPresentationWriteThroughCoordinator.shared.configure(session: session)
        let store = EngagementStore(repository: interactions)
        store.configurePresentationWriteThrough(SocialPresentationWriteThroughCoordinator.shared)
        return store
    }

    @MainActor
    private static func makeVaultStore(
        repository: any VaultRepository,
        session: any SessionProviding
    ) -> VaultStore {
        let store = VaultStore(repository: repository)
        VaultPersistedCacheCoordinator.shared.configure(store: store, session: session)
        store.configurePersistence(VaultPersistedCacheCoordinator.shared)
        return store
    }
}

private struct LoginShellAdminUsageAnalyticsRepository: AdminUsageAnalyticsRepository {
    func fetchBundle(seriesDays: Int) async throws -> AdminUsageAnalyticsBundle {
        _ = seriesDays
        throw AppError.authentication(.sessionMissing)
    }
}

private struct LoginShellAdminSupportTicketsRepository: AdminSupportTicketsRepository {
    private func unavailable() -> AppError {
        .authentication(.sessionMissing)
    }

    func fetchTickets(
        queue: AdminSupportTicketQueueFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminSupportTicketPage {
        _ = (queue, limit, offset)
        throw unavailable()
    }

    func updateTicketReview(ticketID: String, update: AdminSupportTicketReviewUpdate) async throws {
        _ = (ticketID, update)
        throw unavailable()
    }
}

private struct LoginShellAdminProductFeedbackRepository: AdminProductFeedbackRepository {
    private func unavailable() -> AppError {
        .authentication(.sessionMissing)
    }

    func fetchFeedback(
        queue: AdminProductFeedbackQueueFilter,
        type: AdminProductFeedbackTypeFilter,
        status: AdminProductFeedbackStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminProductFeedbackPage {
        _ = (queue, type, status, limit, offset)
        throw unavailable()
    }

    func updateFeedbackReview(feedbackID: String, update: AdminProductFeedbackReviewUpdate) async throws {
        _ = (feedbackID, update)
        throw unavailable()
    }
}

private struct LoginShellAdminBugReportsRepository: AdminBugReportsRepository {
    private func unavailable() -> AppError {
        .authentication(.sessionMissing)
    }

    func fetchReports(
        status: AdminBugReportStatusFilter,
        severity: AdminBugReportSeverityFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminBugReportPage {
        _ = (status, severity, limit, offset)
        throw unavailable()
    }

    func updateReportStatus(
        reportID: String,
        status: BugReportStatus,
        previousStatus: BugReportStatus,
        existingResolvedAt: Date?
    ) async throws {
        _ = (reportID, status, previousStatus, existingResolvedAt)
        throw unavailable()
    }
}

private struct LoginShellAdminContentReportsRepository: AdminContentReportsRepository {
    private func unavailable() -> AppError {
        .authentication(.sessionMissing)
    }

    func fetchReports(
        status: AdminContentReportStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminContentReportPage {
        _ = (status, limit, offset)
        throw unavailable()
    }

    func updateReportStatus(
        reportID: String,
        status: ContentReportStatus,
        reviewerID: ProfileID
    ) async throws {
        _ = (reportID, status, reviewerID)
        throw unavailable()
    }
}

private struct LoginShellAdminUsersRepository: AdminUsersRepository {
    private func unavailable() -> AppError {
        .authentication(.sessionMissing)
    }

    func fetchDirectory(_ query: AdminUserDirectoryQuery) async throws -> AdminUserDirectoryPage {
        _ = query
        throw unavailable()
    }

    func fetchActivityCounts(targetUserID: ProfileID) async throws -> AdminUserActivityCounts {
        _ = targetUserID
        throw unavailable()
    }

    func banUser(targetUserID: ProfileID, adminUserID: ProfileID, reason: String) async throws {
        _ = (targetUserID, adminUserID, reason)
        throw unavailable()
    }

    func unbanUser(targetUserID: ProfileID, adminUserID: ProfileID) async throws {
        _ = (targetUserID, adminUserID)
        throw unavailable()
    }

    func setHiddenFromCommunity(targetUserID: ProfileID, adminUserID: ProfileID, hidden: Bool) async throws {
        _ = (targetUserID, adminUserID, hidden)
        throw unavailable()
    }

    func fetchDeletionPreview(targetUserID: ProfileID) async throws -> AdminUserDeletionPreview {
        _ = targetUserID
        throw unavailable()
    }

    func deleteUser(targetUserID: ProfileID) async throws {
        _ = targetUserID
        throw unavailable()
    }
}

private struct LoginShellBrokerIntegrationRepository: BrokerIntegrationRepository {
    private func unavailable() -> AppError {
        .authentication(.sessionMissing)
    }

    func listTradovateConnections() async throws -> TradovateConnectionsResponse { throw unavailable() }
    func beginTradovateNativeOAuth(
        reconnectConnectionId: String?,
        apiEnvironment: String?
    ) async throws -> URL { throw unavailable() }
    func listTradovateAccounts(connectionId: String, forceRefresh: Bool) async throws -> TradovateConnectionAccountsResponse {
        throw unavailable()
    }
    func linkTradovateAccount(connectionId: String, brokerIntegrationAccountId: String, tradetraxsAccountId: String) async throws -> BrokerLinkAccountsResponse {
        throw unavailable()
    }
    func createAndLinkTradovateAccount(connectionId: String, brokerIntegrationAccountId: String, draft: TradingAccountDraft) async throws -> BrokerLinkAccountsResponse {
        throw unavailable()
    }
    func syncTradovateAccount(
        connectionId: String,
        mappingId: String,
        mode: TradovateSyncRequestMode
    ) async throws -> TradovateAccountSyncResponse {
        throw unavailable()
    }
    func runBrokerImport(mappingIds: [String]) async throws -> BrokerManualImportResponse { throw unavailable() }
    func importEligibility() async throws -> BrokerImportEligibilityResponse { throw unavailable() }
    func disconnectTradovate(connectionId: String) async throws { throw unavailable() }
    func fetchRithmicConnectCapabilities() async throws -> RithmicConnectCapabilitiesResponse { throw unavailable() }
    func listRithmicConnections() async throws -> TradovateConnectionsResponse { throw unavailable() }
    func connectRithmic(username: String, password: String, systemName: String?, reconnectConnectionId: String?) async throws -> RithmicConnectOutcome {
        throw unavailable()
    }
    func listRithmicAccounts(connectionId: String) async throws -> TradovateConnectionAccountsResponse { throw unavailable() }
    func linkRithmicAccount(connectionId: String, brokerIntegrationAccountId: String, tradetraxsAccountId: String) async throws -> BrokerLinkAccountsResponse {
        throw unavailable()
    }
    func createAndLinkRithmicAccount(connectionId: String, brokerIntegrationAccountId: String, draft: TradingAccountDraft) async throws -> BrokerLinkAccountsResponse {
        throw unavailable()
    }
    func syncRithmicAccount(
        connectionId: String,
        mappingId: String,
        password: String?
    ) async throws -> TradovateAccountSyncResponse { throw unavailable() }
    func disconnectRithmic(connectionId: String) async throws { throw unavailable() }
}

private struct DemoAnalyticsRepository: AnalyticsRepository {
    func track(event: String, properties: [String: String]) async {
        _ = (event, properties)
    }
}

private struct DemoAccountRepository: AccountRepository {
    func deleteAuthenticatedAccount() async throws { throw DemoAuthRequired.error }
    func exportAuthenticatedAccountData() async throws -> Data { throw DemoAuthRequired.error }
}

private struct DemoCalendarRepository: CalendarRepository {
    func events(for profileID: ProfileID, interval: DateIntervalValue) async throws -> [CalendarEvent] {
        _ = (profileID, interval)
        return []
    }

    func event(id: CalendarEventID) async throws -> CalendarEvent {
        throw AppError.domain(.notFound(entity: "calendarEvent", id: id.rawValue))
    }

    func upsert(_ event: CalendarEvent) async throws -> CalendarEvent { throw DemoAuthRequired.error }
    func delete(id: CalendarEventID) async throws { throw DemoAuthRequired.error }
}

private struct DemoSearchRepository: SearchRepository {
    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest,
        excludingProfileID: ProfileID?
    ) async throws -> CursorPage<SearchResult> {
        _ = (query, kinds, page, excludingProfileID)
        return CursorPage(items: [], nextCursor: nil)
    }
}

private struct DemoNotificationPreferencesRepository: NotificationPreferencesRepository {
    func preferences(for userID: ProfileID) async throws -> NotificationPreferences {
        SettingsFixtures.preferences(userID: userID)
    }

    func update(
        _ patch: [NotificationPreferenceKey: Bool],
        for userID: ProfileID
    ) async throws -> NotificationPreferences {
        _ = patch
        throw DemoAuthRequired.error
    }
}

private struct DemoCheckInRepository: TraderDailyCheckInRepository {
    func checkIn(for profileID: ProfileID, date: String) async throws -> TraderDailyCheckIn? {
        guard profileID == DemoExperienceSupport.profileID else { return nil }
        return DemoCanonicalDataset.checkIns().first { $0.checkInDate == date }
    }

    func checkIns(
        for profileID: ProfileID,
        from startDate: String,
        to endDate: String
    ) async throws -> [TraderDailyCheckIn] {
        guard profileID == DemoExperienceSupport.profileID else { return [] }
        return DemoCanonicalDataset.checkIns().filter {
            $0.checkInDate >= startDate && $0.checkInDate <= endDate
        }
    }

    func upsert(
        _ draft: TraderDailyCheckInDraft,
        for profileID: ProfileID
    ) async throws -> TraderDailyCheckIn {
        _ = (draft, profileID)
        throw DemoAuthRequired.error
    }
}

private struct DemoFollowRequestRepository: FollowRequestRepository {
    func pendingRequests() async throws -> [FollowRequest] { [] }
    func approve(id: FollowRequestID) async throws { throw DemoAuthRequired.error }
    func decline(id: FollowRequestID) async throws { throw DemoAuthRequired.error }
}

private struct DemoNotificationRepository: NotificationRepository {
    func notifications(page: PageRequest) async throws -> CursorPage<ActivityNotification> {
        _ = page
        return CursorPage(items: DemoGraph.notifications(), nextCursor: nil)
    }

    func notification(id: NotificationID) async throws -> ActivityNotification? {
        DemoGraph.notifications().first { $0.id == id }
    }

    func unreadCount() async throws -> Int {
        DemoGraph.notifications().filter { !$0.isRead }.count
    }

    func markRead(id: NotificationID) async throws { _ = id }
    func markRead(ids: [NotificationID]) async throws -> Int { ids.count }
    func markMessageNotificationsRead() async throws -> Int { 0 }
    func markRoomNotificationsRead(roomID: RoomID, slug: String?) async throws -> Int {
        _ = (roomID, slug)
        return 0
    }

    func markAllRead() async throws {}
    func delete(id: NotificationID) async throws { throw DemoAuthRequired.error }
    func delete(ids: [NotificationID]) async throws -> Int { throw DemoAuthRequired.error }
    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        ids.compactMap(DemoGraph.profile(id:))
    }
}

private struct LoginShellAppleSubscriptionSyncClient: AppleSubscriptionSyncClienting {
    func sync(transactionID: String, signedTransactionInfo: String) async throws -> AppleSubscriptionSyncResponse {
        _ = transactionID
        _ = signedTransactionInfo
        return AppleSubscriptionSyncResponse(
            traxProActive: false,
            source: nil,
            productId: nil,
            billingInterval: nil,
            expiresAt: nil,
            appleSubscriptionStatus: nil
        )
    }

    func fetchEntitlement() async throws -> BillingEntitlementResponse {
        BillingEntitlementResponse(
            traxProActive: false,
            source: nil,
            plan: nil,
            billingInterval: nil,
            subscriptionStatus: nil,
            trialEndsAt: nil,
            currentPeriodEndsAt: nil,
            cancelAtPeriodEnd: nil,
            appleExpiresAt: nil,
            appleProductId: nil
        )
    }

    func fetchMonetizationConfig() async throws -> IosMonetizationConfigResponse {
        throw AppError.unknown(message: "Monetization config is unavailable")
    }
}
