import Foundation
import Observation

/// Session-level Activity source of truth (list + unread). Survives leaving Activity.
///
/// Dashboard bell and Activity home both observe this store. Realtime patches mutate
/// in place — no polling.
@Observable
@MainActor
final class ActivityInboxStore {
    static let shared = ActivityInboxStore()

    static let pageSize = 40

    private(set) var items: [ActivityNotification] = []
    private(set) var unreadCount = 0
    private(set) var pendingFollowRequestCount = 0
    /// True once the Activity feed page has been hydrated (not merely unread count).
    private(set) var hasLoaded = false
    /// True once unread count (+ Realtime) is available for the Dashboard bell.
    private(set) var hasBootstrappedUnread = false
    private(set) var lastLoadedAt: Date?
    private(set) var nextCursor: String?
    private(set) var isLoadingMore = false
    private(set) var hasMore = true

    private var realtimeTask: Task<Void, Never>?
    private var startedForUserID: String?
    private var isStarting = false
    private var isBootstrappingUnread = false

    private init() {}

    var hasUnread: Bool { unreadCount > 0 }

    func replace(
        items: [ActivityNotification],
        unreadCount: Int,
        nextCursor: String?,
        pendingFollowRequestCount: Int = 0
    ) {
        self.items = Self.sortNewestFirst(items)
        self.unreadCount = max(0, unreadCount)
        self.nextCursor = nextCursor
        self.hasMore = nextCursor != nil
        self.pendingFollowRequestCount = max(0, pendingFollowRequestCount)
        hasLoaded = true
        hasBootstrappedUnread = true
        lastLoadedAt = .now
    }

    func append(page items: [ActivityNotification], nextCursor: String?) {
        var merged = self.items
        let existing = Set(merged.map(\.id))
        for item in items where !existing.contains(item.id) {
            merged.append(item)
        }
        self.items = Self.sortNewestFirst(merged)
        self.nextCursor = nextCursor
        self.hasMore = nextCursor != nil
        isLoadingMore = false
    }

    func setLoadingMore(_ value: Bool) {
        isLoadingMore = value
    }

    func setPendingFollowRequestCount(_ count: Int) {
        pendingFollowRequestCount = max(0, count)
    }

    func upsert(_ notification: ActivityNotification) {
        guard notification.kind.isInboxType else { return }
        var next = items
        if let index = next.firstIndex(where: { $0.id == notification.id }) {
            let wasUnread = !next[index].isRead
            let nowUnread = !notification.isRead
            next[index] = notification
            if wasUnread, !nowUnread {
                unreadCount = max(0, unreadCount - 1)
            } else if !wasUnread, nowUnread {
                unreadCount += 1
            }
        } else {
            next.insert(notification, at: 0)
            if !notification.isRead {
                unreadCount += 1
            }
        }
        items = Self.sortNewestFirst(next)
        hasLoaded = true
    }

    func remove(id: NotificationID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if !items[index].isRead {
            unreadCount = max(0, unreadCount - 1)
        }
        items.remove(at: index)
    }

    func markReadLocally(id: NotificationID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isRead else { return }
        items[index].isRead = true
        // Reassign for Observation.
        items = items
        unreadCount = max(0, unreadCount - 1)
    }

    func markAllReadLocally() {
        items = items.map { item in
            var copy = item
            copy.isRead = true
            return copy
        }
        unreadCount = 0
    }

    func setUnreadCount(_ count: Int) {
        unreadCount = max(0, count)
    }

    /// Dashboard bell path — unread count + Realtime only (no Activity feed hydration).
    func ensureUnreadBootstrap(
        notifications: any NotificationRepository,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) {
        Task {
            await bootstrapUnreadIfNeeded(
                notifications: notifications,
                session: session,
                realtimeHub: realtimeHub
            )
        }
    }

    /// Legacy alias — prefer ``ensureUnreadBootstrap`` from Dashboard.
    func ensureStarted(
        notifications: any NotificationRepository,
        followRequests: (any FollowRequestRepository)?,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) {
        _ = followRequests
        ensureUnreadBootstrap(
            notifications: notifications,
            session: session,
            realtimeHub: realtimeHub
        )
    }

    /// Activity screen path — hydrate first feed page (+ follow requests) when needed.
    func startIfNeeded(
        notifications: any NotificationRepository,
        followRequests: (any FollowRequestRepository)?,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) async {
        await bootstrapUnreadIfNeeded(
            notifications: notifications,
            session: session,
            realtimeHub: realtimeHub
        )

        guard let userID = await session.currentUserID?.rawValue else { return }
        if startedForUserID == userID, hasLoaded { return }
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        // Fixture / session cache already painted — attach Realtime without refetch.
        if hasLoaded, startedForUserID == nil {
            startedForUserID = userID
            hasBootstrappedUnread = true
            startRealtime(
                userID: userID,
                notifications: notifications,
                session: session,
                realtimeHub: realtimeHub
            )
            return
        }

        if startedForUserID != userID {
            invalidateRealtimeOnly()
            items = []
            unreadCount = 0
            pendingFollowRequestCount = 0
            hasLoaded = false
            hasBootstrappedUnread = false
            nextCursor = nil
            hasMore = true
            startedForUserID = userID
        }

        do {
            let page = try await DashboardLoadProbe.measure(
                "activity.notifications.page",
                kind: .network,
                blocksFirstUsefulRender: false,
                note: "Activity feed page=\(Self.pageSize)"
            ) {
                try await notifications.notifications(
                    page: PageRequest(limit: Self.pageSize)
                )
            }
            DashboardLoadProbe.recordNotificationRows(page.items.count)

            let previousFollowCount = pendingFollowRequestCount
            let previousUnread = unreadCount
            async let unreadTask = notifications.unreadCount()
            async let followTask: Int = {
                guard let followRequests else { return previousFollowCount }
                return (try? await followRequests.pendingRequests().count) ?? previousFollowCount
            }()
            let unread = (try? await unreadTask) ?? previousUnread
            let followCount = await followTask
            replace(
                items: page.items,
                unreadCount: unread,
                nextCursor: page.nextCursor,
                pendingFollowRequestCount: followCount
            )
        } catch {
            // Soft-fail — keep prior cache if any.
            if !hasLoaded {
                hasLoaded = true
            }
        }

        startRealtime(
            userID: userID,
            notifications: notifications,
            session: session,
            realtimeHub: realtimeHub
        )
    }

    func bootstrapUnreadIfNeeded(
        notifications: any NotificationRepository,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) async {
        guard let userID = await session.currentUserID?.rawValue else { return }
        if startedForUserID == userID, hasBootstrappedUnread {
            if realtimeTask == nil {
                startRealtime(
                    userID: userID,
                    notifications: notifications,
                    session: session,
                    realtimeHub: realtimeHub
                )
            }
            return
        }
        guard !isBootstrappingUnread else { return }
        isBootstrappingUnread = true
        defer { isBootstrappingUnread = false }

        if startedForUserID != userID {
            invalidateRealtimeOnly()
            items = []
            unreadCount = 0
            pendingFollowRequestCount = 0
            hasLoaded = false
            hasBootstrappedUnread = false
            nextCursor = nil
            hasMore = true
            startedForUserID = userID
        }

        do {
            let unread = try await DashboardLoadProbe.measure(
                "activity.unreadCount",
                kind: .network,
                blocksFirstUsefulRender: false,
                note: "Prefer count=exact; no row payloads"
            ) {
                try await notifications.unreadCount()
            }
            setUnreadCount(unread)
            hasBootstrappedUnread = true
        } catch {
            // Soft-fail — bell stays at 0 until next successful bootstrap.
            hasBootstrappedUnread = true
        }

        startRealtime(
            userID: userID,
            notifications: notifications,
            session: session,
            realtimeHub: realtimeHub
        )
    }

    func refresh(
        notifications: any NotificationRepository,
        followRequests: (any FollowRequestRepository)?
    ) async throws {
        let previousFollowCount = pendingFollowRequestCount
        async let pageTask = notifications.notifications(
            page: PageRequest(limit: Self.pageSize)
        )
        async let unreadTask = notifications.unreadCount()
        async let followTask: Int = {
            guard let followRequests else { return previousFollowCount }
            return (try? await followRequests.pendingRequests().count) ?? previousFollowCount
        }()
        let page = try await pageTask
        let unread = try await unreadTask
        let followCount = await followTask
        replace(
            items: page.items,
            unreadCount: unread,
            nextCursor: page.nextCursor,
            pendingFollowRequestCount: followCount
        )
    }

    func loadMore(notifications: any NotificationRepository) async throws {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let page = try await notifications.notifications(
            page: PageRequest(cursor: cursor, limit: Self.pageSize)
        )
        append(page: page.items, nextCursor: page.nextCursor)
    }

    func invalidate() {
        invalidateRealtimeOnly()
        items = []
        unreadCount = 0
        pendingFollowRequestCount = 0
        hasLoaded = false
        hasBootstrappedUnread = false
        lastLoadedAt = nil
        nextCursor = nil
        hasMore = true
        startedForUserID = nil
        isStarting = false
        isBootstrappingUnread = false
    }

    func resetForTesting() {
        invalidate()
    }

    // MARK: - Private

    private func invalidateRealtimeOnly() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    private func startRealtime(
        userID: String,
        notifications: any NotificationRepository,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) {
        guard let realtimeHub else { return }
        invalidateRealtimeOnly()
        let channel = RealtimeChannelID(kind: .notifications, topic: "user:\(userID)")
        realtimeTask = Task { [weak self] in
            try? await realtimeHub.subscriptions.subscribe(channel)
            let token = await session.accessToken
            for await signal in realtimeHub.watchNotifications(
                userID: userID,
                accessToken: token
            ) {
                guard let self else { break }
                await self.applyRealtime(signal: signal, notifications: notifications)
            }
        }
    }

    private func applyRealtime(
        signal: MessageRealtimeSignal,
        notifications: any NotificationRepository
    ) async {
        guard let rawID = signal.messageID else { return }
        let id = NotificationID(rawID)
        switch signal.kind {
        case .insert, .update:
            if let item = try? await notifications.notification(id: id) {
                upsert(item)
            } else if signal.kind == .update {
                // Soft miss — recount unread.
                if let count = try? await notifications.unreadCount() {
                    setUnreadCount(count)
                }
            }
        case .delete:
            remove(id: id)
        }
    }

    private static func sortNewestFirst(_ items: [ActivityNotification]) -> [ActivityNotification] {
        items.sorted { $0.createdAt > $1.createdAt }
    }
}
