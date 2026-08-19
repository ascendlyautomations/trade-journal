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
        CalendarMonthSessionStore.shared.invalidate()
        SessionAccountsStore.shared.invalidate()
        SessionProfileStore.shared.invalidate()
        SessionTradeEntityStore.shared.invalidate()
        SessionOwnerTradesStore.shared.invalidate()
        SessionMemberRoomsStore.shared.invalidate()
        ProfileRequestFlight.shared.invalidate()
        RepositoryRequestFlight.shared.invalidate()
        Task { await SessionFollowingStore.shared.invalidate() }
        SessionDiskCache.clearAll()
        TradeJournalMutationStore.shared.invalidate()
        AccountMutationStore.shared.invalidate()
        ContentMutationStore.shared.invalidate()
        OwnerProfileOptimisticStore.shared.invalidate()
        FollowMutationCoordinator.shared.invalidate()
        data.detailCache.removeAll()
        data.engagementStore.removeAll()
        #if DEBUG
        SessionNetworkProbe.resetForTesting()
        SupabaseSessionUsage.resetForTesting()
        #endif
    }
}
