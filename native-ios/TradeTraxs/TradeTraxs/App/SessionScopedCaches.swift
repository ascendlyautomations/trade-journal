import Foundation

/// Invalidates caches that belong to the authenticated user — not the process.
///
/// Called from ``AuthenticationCoordinator`` on logout and authenticated-user changes.
/// Features must not reset these stores themselves.
@MainActor
enum SessionScopedCaches {
    static func invalidate(
        currentUserProfile: CurrentUserProfileStore,
        data: DataEnvironment
    ) {
        if let viewerID = currentUserProfile.profile?.id {
            Task {
                await AnalyticsLocalStore.sharedStore().clearViewer(viewerID)
            }
        }
        currentUserProfile.clear()
        MessagesInboxStore.shared.invalidate()
        MessagingDomain.shared.invalidate()
        ActivityInboxStore.shared.invalidate()
        RoomNavigationFocusStore.shared.clear()
        ExploreSessionStore.shared.invalidate()
        LeaderboardSessionStore.shared.invalidate()
        Task { await LeaderboardTradeRowsCache.shared.invalidate() }
        TradeHistorySessionStore.shared.invalidate()
        FeedSessionStore.shared.invalidate()
        ProfileSessionStore.shared.invalidate()
        FeedStoriesCatalogStore.shared.invalidate()
        FeedBlockedAuthorsFilter.shared.clear()
        ViewerActiveStoryStore.shared.invalidate()
        ConversationThreadSessionStore.shared.invalidate()
        DirectConversationPairIndex.shared.invalidate()
        ConversationCreationCoordinator.shared.invalidate()
        CalendarMonthSessionStore.shared.invalidate()
        CalendarAnalyticsSessionStore.shared.invalidate()
        CalendarAnalyticsMonthDiskCache.clearAll()
        DashboardAnalyticsDiskCache.clearAll()
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
        SessionAccountsStore.shared.invalidate()
        SessionPayoutCyclesStore.shared.invalidateAll()
        SessionPayoutEntriesStore.shared.invalidate()
        WithdrawalsHistoryStore.shared.invalidate()
        SessionProfileStore.shared.invalidate()
        SessionTradeEntityStore.shared.invalidate()
        Task { await TradeDetailSessionStore.shared.resetAll() }
        SessionOwnerTradesStore.shared.invalidate()
        SessionMemberRoomsStore.shared.invalidate()
        SessionTradeRoomsDiscoveryStore.shared.invalidate()
        SessionRoomMemberTagsStore.shared.invalidate()
        ProfileRequestFlight.shared.invalidate()
        RepositoryRequestFlight.shared.invalidate()
        Task { await SessionFollowingStore.shared.invalidate() }
        SessionBootstrapStore.shared.clear()
        BackendV2BootstrapDiskCache.clearAll()
        ViewerSyncStateDiskCache.clear()
        ViewerSyncReconciliationCoordinator.shared.reset()
        ViewerSyncStateRuntime.reset()
        AnalyticsReconciliationRuntime.reset()
        Task { await AnalyticsReconciliationCoordinator.shared.reset() }
        AnalyticsRevisionRealtimeSession.shared.invalidate()
        EngagementRealtimeSession.shared.invalidate()
        SocialEntityRealtimeSession.shared.invalidate()
        RelationshipRealtimeSession.shared.invalidate()
        MessagingRealtimeDeliveryCoordinator.resetSession()
        Task { await SocialRealtimeReconciliationCoordinator.shared.reset() }
        Task { await AnalyticsRevisionRepairCoordinator.shared.reset() }
        data.cache.memory.removeAll()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
            await SessionBootstrapRefreshCommit.shared.reset()
            await ProfileAnalyticsV2ShadowSession.shared.reset()
            await ProfileAnalyticsGRDBSession.shared.reset()
        }
        SessionDiskCache.clearAll()
        SocialPersistedCacheCoordinator.clearAll()
        FeedPersistedCacheCoordinator.clearAll()
        ProfilePersistedCacheCoordinator.clearAll()
        VaultPersistedCacheCoordinator.clearAll()
        AuthenticatedLaunchPhasing.reset()
        DashboardAuthoritativeRefreshCoordinator.shared.reset()
        TradeJournalMutationStore.shared.invalidate()
        AccountMutationStore.shared.invalidate()
        ContentMutationStore.shared.invalidate()
        OwnerProfileOptimisticStore.shared.invalidate()
        FollowMutationCoordinator.shared.invalidate()
        GettingStartedStore.shared.invalidate()
        TraderDailyCheckInStore.shared.invalidate()
        BrokerImportEligibilityStore.shared.invalidate()
        AppIconBadgeSync.resetSessionMirror()
        Task {
            await DailyCheckInReminderCoordinator.shared.cancelAll()
            await TradeImportReminderCoordinator.shared.cancelAll()
        }
        SessionDailyCheckInsStore.shared.invalidate()
        PsychologyAnalyticsSessionStore.shared.update(nil)
        PsychologyCoachSessionStore.shared.invalidate()
        PsychologyGuardrailDismissStore.shared.resetSession()
        PsychologyReportSessionStore.shared.invalidate()
        CheckInHistorySessionStore.shared.invalidate()
        TradingReportSessionStore.shared.invalidate()
        CreateAchievementPrefillStore.shared.clear()
        Task { await data.cache.images.removeAllImages() }
        GlobalUploadCoordinator.shared.invalidateForSessionChange()
        SessionBillingEntitlementStore.shared.clear()
        data.detailCache.removeAll()
        data.engagementStore.removeAll()
        data.vaultStore.removeAll()
        Task { await data.realtimeHub.stop() }
        #if DEBUG
        SessionNetworkProbe.resetForTesting()
        SupabaseSessionUsage.resetForTesting()
        FeedPersistentCacheProbe.resetForTesting()
        ProfilePersistentCacheProbe.resetForTesting()
        SocialEntityCacheProbe.resetForTesting()
        TradeHistoryCacheProbe.resetForTesting()
        CalendarCacheProbe.resetForTesting()
        DiskCacheIOProbe.resetForTesting()
        ColdLaunchSummaryProbe.resetForTesting()
        #endif
    }
}
