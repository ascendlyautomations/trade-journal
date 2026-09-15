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
    let vault: any VaultRepository
    /// Session-scoped private Vault cache — shared by Feed, detail, and Vault home.
    let vaultStore: VaultStore
    let brokerIntegrations: any BrokerIntegrationRepository

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
        vault: any VaultRepository,
        vaultStore: VaultStore,
        brokerIntegrations: any BrokerIntegrationRepository
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
        self.vault = vault
        self.vaultStore = vaultStore
        self.brokerIntegrations = brokerIntegrations
    }

    enum LaunchMode: Sendable {
        case production
        /// Logged-out shell — no realtime boot, no session store wiring, unconfigured Supabase seam.
        case loginShell
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
        TradeJournalMutationStore.shared.configure(detailCache: detailCache)
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
            storeKitSync: storeKitSubscriptions
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
            engagementStore: EngagementStore(repository: interactions),
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
            vault: vaultRepository,
            vaultStore: VaultStore(repository: vaultRepository),
            brokerIntegrations: {
                let repository = DefaultBrokerIntegrationRepository(transport: transport)
                BrokerImportEligibilityStore.shared.configure(
                    broker: repository,
                    session: session
                )
                return repository
            }()
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
        let storeKitSubscriptions: any StoreKitSubscriptionServicing = StoreKitSubscriptionService(
            syncClient: LoginShellAppleSubscriptionSyncClient()
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
                    storeKitSync: storeKitSubscriptions
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
            engagementStore: EngagementStore(repository: interactions),
            ai: repositories.ai,
            tradingReports: repositories.tradingReports,
            psychologyReports: repositories.psychologyReports,
            dailyCheckIns: repositories.dailyCheckIns,
            contentReports: LoginShellContentReportRepository(),
            vault: vaultRepository,
            vaultStore: VaultStore(repository: vaultRepository),
            brokerIntegrations: LoginShellBrokerIntegrationRepository()
        )
    }
}

private struct LoginShellBrokerIntegrationRepository: BrokerIntegrationRepository {
    private func unavailable() -> AppError {
        .authentication(.sessionMissing)
    }

    func listTradovateConnections() async throws -> TradovateConnectionsResponse { throw unavailable() }
    func beginTradovateNativeOAuth(reconnectConnectionId: String?) async throws -> URL { throw unavailable() }
    func listTradovateAccounts(connectionId: String, forceRefresh: Bool) async throws -> TradovateConnectionAccountsResponse {
        throw unavailable()
    }
    func linkTradovateAccount(connectionId: String, brokerIntegrationAccountId: String, tradetraxsAccountId: String) async throws -> BrokerLinkAccountsResponse {
        throw unavailable()
    }
    func createAndLinkTradovateAccount(connectionId: String, brokerIntegrationAccountId: String, draft: TradingAccountDraft) async throws -> BrokerLinkAccountsResponse {
        throw unavailable()
    }
    func syncTradovateAccount(connectionId: String, mappingId: String) async throws -> TradovateAccountSyncResponse {
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
    func syncRithmicAccount(connectionId: String, mappingId: String) async throws -> TradovateAccountSyncResponse { throw unavailable() }
    func disconnectRithmic(connectionId: String) async throws { throw unavailable() }
}

private struct LoginShellAppleSubscriptionSyncClient: AppleSubscriptionSyncClienting {
    func sync(transactionID: String) async throws -> AppleSubscriptionSyncResponse {
        _ = transactionID
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
}
