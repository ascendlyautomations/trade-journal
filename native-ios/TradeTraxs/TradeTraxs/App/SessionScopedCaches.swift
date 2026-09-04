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
        ViewerActiveStoryStore.shared.invalidate()
        ConversationThreadSessionStore.shared.invalidate()
        DirectConversationPairIndex.shared.invalidate()
        ConversationCreationCoordinator.shared.invalidate()
        CalendarMonthSessionStore.shared.invalidate()
        SessionAccountsStore.shared.invalidate()
        SessionProfileStore.shared.invalidate()
        SessionTradeEntityStore.shared.invalidate()
        SessionOwnerTradesStore.shared.invalidate()
        SessionMemberRoomsStore.shared.invalidate()
        ProfileRequestFlight.shared.invalidate()
        RepositoryRequestFlight.shared.invalidate()
        Task { await SessionFollowingStore.shared.invalidate() }
        SessionBootstrapStore.shared.clear()
        BackendV2BootstrapDiskCache.clearAll()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
        }
        SessionDiskCache.clearAll()
        TradeJournalMutationStore.shared.invalidate()
        AccountMutationStore.shared.invalidate()
        ContentMutationStore.shared.invalidate()
        OwnerProfileOptimisticStore.shared.invalidate()
        FollowMutationCoordinator.shared.invalidate()
        GettingStartedStore.shared.invalidate()
        TraderDailyCheckInStore.shared.invalidate()
        Task { await DailyCheckInReminderCoordinator.shared.cancelAll() }
        SessionDailyCheckInsStore.shared.invalidate()
        PsychologyAnalyticsSessionStore.shared.update(nil)
        PsychologyCoachSessionStore.shared.invalidate()
        PsychologyGuardrailDismissStore.shared.resetSession()
        PsychologyReportSessionStore.shared.invalidate()
        CheckInHistorySessionStore.shared.invalidate()
        data.detailCache.removeAll()
        data.engagementStore.removeAll()
        Task { await data.realtimeHub.stop() }
        #if DEBUG
        SessionNetworkProbe.resetForTesting()
        SupabaseSessionUsage.resetForTesting()
        #endif
    }
}
