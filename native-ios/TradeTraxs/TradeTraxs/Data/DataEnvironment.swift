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
    let calendar: any CalendarRepository
    let leaderboard: any LeaderboardRepository
    let search: any SearchRepository
    let billing: any BillingRepository
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
        calendar: any CalendarRepository,
        leaderboard: any LeaderboardRepository,
        search: any SearchRepository,
        billing: any BillingRepository,
        analytics: any AnalyticsRepository,
        achievements: any AchievementRepository,
        referrals: any ReferralRepository,
        notificationPreferences: any NotificationPreferencesRepository,
        authentication: any AuthenticationRepository,
        home: any HomeRepository,
        interactions: any InteractionRepository,
        engagementStore: EngagementStore
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
        self.calendar = calendar
        self.leaderboard = leaderboard
        self.search = search
        self.billing = billing
        self.analytics = analytics
        self.achievements = achievements
        self.referrals = referrals
        self.notificationPreferences = notificationPreferences
        self.authentication = authentication
        self.home = home
        self.interactions = interactions
        self.engagementStore = engagementStore
    }

    static func make(
        appConfiguration: AppConfiguration,
        networking: NetworkingEnvironment,
        session: any SessionProviding,
        authenticationManager: AuthenticationManager
    ) -> DataEnvironment {
        let configuration = DataConfiguration.make(for: appConfiguration)
        let supabase = SupabaseInfrastructure.make(
            appConfiguration: appConfiguration,
            networking: networking,
            session: session
        )
        let imageCache = InMemoryImageCache()
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
            detailCache: DetailPresentationCache(),
            trades: DefaultTradeRepository(supabase: supabase, cache: cache, session: session),
            profiles: profiles,
            feed: DefaultFeedRepository(supabase: supabase, cache: cache, session: session),
            messages: DefaultMessageRepository(supabase: supabase, cache: cache, session: session),
            rooms: DefaultRoomRepository(supabase: supabase, cache: cache),
            notifications: DefaultNotificationRepository(
                supabase: supabase,
                cache: cache,
                session: session
            ),
            calendar: DefaultCalendarRepository(supabase: supabase, cache: cache),
            leaderboard: DefaultLeaderboardRepository(supabase: supabase, cache: cache),
            search: DefaultSearchRepository(supabase: supabase, cache: cache),
            billing: DefaultBillingRepository(supabase: supabase, cache: cache),
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
            engagementStore: EngagementStore(repository: interactions)
        )
    }
}
