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
    private var notificationsRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var activeRealtimeUserID: String?
    private weak var activeRealtimeHub: RealtimeHub?
    private var realtimeWatchSessionGeneration: UInt64 = 0
    private var realtimeWatchBoundGeneration: UInt64?
    private var startedForUserID: String?
    private var isStarting = false
    private var isBootstrappingUnread = false
    private var persistedViewerID: ProfileID?
    private var seenNotificationEventKeys: Set<String> = []

    private init() {}

    var hasUnread: Bool { unreadCount > 0 }

    func replace(
        items: [ActivityNotification],
        unreadCount: Int,
        nextCursor: String?,
        pendingFollowRequestCount: Int = 0
    ) {
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        let publishStart = CFAbsoluteTimeGetCurrent()
        MainThreadWorkProbe.measure("activity.replace", surface: "activity") {
            self.items = sorted
            self.unreadCount = max(0, unreadCount)
            self.nextCursor = nextCursor
            self.hasMore = nextCursor != nil
            self.pendingFollowRequestCount = max(0, pendingFollowRequestCount)
            hasLoaded = true
            hasBootstrappedUnread = true
            lastLoadedAt = .now
        }
        MainThreadWorkProbe.publish(
            surface: "activity",
            items: sorted.count,
            durationMs: Int((CFAbsoluteTimeGetCurrent() - publishStart) * 1000)
        )
        ActivityPipelineProbe.record(stage: "published", stored: sorted.count)
        AppIconBadgeSync.refresh(animated: true)
        schedulePersistSnapshot()
    }

    /// Restores Activity presentation from a viewer-scoped disk snapshot (cold launch).
    func hydrateFromDisk(
        viewerID: ProfileID,
        items: [ActivityNotification],
        unreadCount: Int,
        pendingFollowRequestCount: Int,
        nextCursor: String?,
        savedAt: Date
    ) {
        persistedViewerID = viewerID
        self.items = Self.sortNewestFirst(items)
        self.unreadCount = max(0, unreadCount)
        self.pendingFollowRequestCount = max(0, pendingFollowRequestCount)
        self.nextCursor = nextCursor
        self.hasMore = nextCursor != nil
        hasLoaded = !items.isEmpty
        hasBootstrappedUnread = true
        lastLoadedAt = savedAt
    }

    /// Merge authoritative catch-up rows without dropping older cached pages.
    func mergeCatchUp(
        items: [ActivityNotification],
        unreadCount: Int,
        pendingFollowRequestCount: Int? = nil
    ) {
        let existingItems = self.items
        let merged = MainThreadWorkProbe.measure("activity.mergeCatchUp.prepare", surface: "activity") {
            var byID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
            for item in items {
                byID[item.id] = item
            }
            return Array(byID.values.sorted { $0.createdAt > $1.createdAt }.prefix(SocialDiskCache.maxActivityItems))
        }
        MainThreadWorkProbe.measure("activity.mergeCatchUp.apply", surface: "activity") {
            self.items = merged
            setUnreadCount(unreadCount)
            if let pendingFollowRequestCount {
                self.pendingFollowRequestCount = max(0, pendingFollowRequestCount)
            }
            hasLoaded = true
            lastLoadedAt = .now
        }
        schedulePersistSnapshot()
#if DEBUG
        SocialCacheProbe.recordActivityCatchup(items: items.count, fullBootstrap: false)
#endif
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
        schedulePersistSnapshot()
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
        AppIconBadgeSync.refresh(animated: true)
        schedulePersistSnapshot()
    }

    func remove(id: NotificationID) {
        _ = removeLocally(ids: [id])
    }

    /// Optimistic swipe-delete — returns removed rows for rollback.
    @discardableResult
    func removeLocally(ids: [NotificationID]) -> [ActivityNotification] {
        let targets = Set(ids)
        guard !targets.isEmpty else { return [] }
        let removed = items.filter { targets.contains($0.id) }
        guard !removed.isEmpty else { return [] }

        let unreadRemoved = removed.filter { !$0.isRead }.count
        items = items.filter { !targets.contains($0.id) }
        if unreadRemoved > 0 {
            unreadCount = max(0, unreadCount - unreadRemoved)
            AppIconBadgeSync.refresh(animated: true)
        }
        schedulePersistSnapshot()
        return removed
    }

    /// Rolls back a failed optimistic ``removeLocally``.
    func restoreLocally(_ notifications: [ActivityNotification]) {
        guard !notifications.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var unreadRestored = 0
        for notification in notifications where byID[notification.id] == nil {
            byID[notification.id] = notification
            if !notification.isRead {
                unreadRestored += 1
            }
        }
        items = Self.sortNewestFirst(Array(byID.values))
        if unreadRestored > 0 {
            unreadCount += unreadRestored
            AppIconBadgeSync.refresh(animated: true)
        }
        schedulePersistSnapshot()
    }

    func markReadLocally(id: NotificationID) {
        _ = markReadLocally(ids: [id])
    }

    @discardableResult
    func markReadLocally(ids: [NotificationID]) -> Int {
        let targets = Set(ids)
        guard !targets.isEmpty else { return 0 }
        var marked = 0
        var next = items
        for index in next.indices where targets.contains(next[index].id) && !next[index].isRead {
            next[index].isRead = true
            marked += 1
        }
        guard marked > 0 else { return 0 }
        items = next
        unreadCount = max(0, unreadCount - marked)
        AppIconBadgeSync.refresh(animated: true)
        return marked
    }

    @discardableResult
    func markMessageNotificationsReadLocally() -> Int {
        var marked = 0
        var next = items
        for index in next.indices where next[index].kind == .message && !next[index].isRead {
            next[index].isRead = true
            marked += 1
        }
        guard marked > 0 else { return 0 }
        items = next
        unreadCount = max(0, unreadCount - marked)
        AppIconBadgeSync.refresh(animated: true)
        return marked
    }

    @discardableResult
    func markRoomNotificationsReadLocally(roomID: RoomID, slug: String?) -> Int {
        let roomToken = roomID.rawValue
        let slugToken = slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var marked = 0
        var next = items
        for index in next.indices where !next[index].isRead && matchesRoomNotification(next[index], roomID: roomToken, slug: slugToken) {
            next[index].isRead = true
            marked += 1
        }
        guard marked > 0 else { return 0 }
        items = next
        unreadCount = max(0, unreadCount - marked)
        AppIconBadgeSync.refresh(animated: true)
        return marked
    }

    private func matchesRoomNotification(
        _ notification: ActivityNotification,
        roomID: String,
        slug: String
    ) -> Bool {
        let isRoomKind = notification.kind == .roomJoin || notification.kind == .roomMention
        let mentionsRoom = notification.roomID?.rawValue == roomID
            || (!roomID.isEmpty && notification.body.contains(roomID))
            || (!slug.isEmpty && notification.body.contains(slug))
        return isRoomKind || mentionsRoom
    }

    /// Rolls back a failed optimistic ``markReadLocally``.
    func markUnreadLocally(id: NotificationID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].isRead else { return }
        items[index].isRead = false
        items = items
        unreadCount += 1
    }

    func markAllReadLocally() {
        items = items.map { item in
            var copy = item
            copy.isRead = true
            return copy
        }
        unreadCount = 0
    }

    /// Confirms server-side mark-all-read — keeps rows read and reconciles badge count.
    func confirmMarkAllRead(unreadCount: Int) {
        markAllReadLocally()
        setUnreadCount(unreadCount)
    }

    func setUnreadCount(_ count: Int) {
        unreadCount = max(0, count)
        AppIconBadgeSync.refresh(animated: true)
    }

    /// Dashboard bell path — unread count + Realtime only (no Activity feed hydration).
    func ensureUnreadBootstrap(
        notifications: any NotificationRepository,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?,
        detailCache: DetailPresentationCache? = nil,
        rpc: (any RPCClient)? = nil
    ) {
        Task.detached(priority: .utility) {
            await ActivityInboxStore.shared.bootstrapUnreadIfNeeded(
                notifications: notifications,
                session: session,
                realtimeHub: realtimeHub,
                detailCache: detailCache,
                rpc: rpc
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
        realtimeHub: RealtimeHub?,
        detailCache: DetailPresentationCache? = nil,
        rpc: (any RPCClient)? = nil,
        feedPresentation: Bool = false
    ) async {
        await bootstrapUnreadIfNeeded(
            notifications: notifications,
            session: session,
            realtimeHub: realtimeHub,
            detailCache: detailCache,
            rpc: rpc
        )

        guard let userID = await session.currentUserID?.rawValue else { return }
        let viewerID = ProfileID(userID)

        if feedPresentation, startedForUserID == userID, hasLoaded {
            startRealtime(
                userID: userID,
                notifications: notifications,
                session: session,
                realtimeHub: realtimeHub
            )
            await syncPresentedFeed(
                viewerID: viewerID,
                notifications: notifications,
                followRequests: followRequests,
                detailCache: detailCache,
                rpc: rpc
            )
            return
        }

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
            realtimeWatchSessionGeneration &+= 1
            invalidateRealtimeOnly()
            items = []
            unreadCount = 0
            pendingFollowRequestCount = 0
            hasLoaded = false
            hasBootstrappedUnread = false
            nextCursor = nil
            hasMore = true
            startedForUserID = userID
            persistedViewerID = ProfileID(userID)
            _ = SocialPersistedCacheCoordinator.hydrateActivity(
                viewerID: ProfileID(userID),
                store: self
            )
        }

        if hasLoaded {
            startRealtime(
                userID: userID,
                notifications: notifications,
                session: session,
                realtimeHub: realtimeHub
            )
            if feedPresentation {
                await syncPresentedFeed(
                    viewerID: viewerID,
                    notifications: notifications,
                    followRequests: followRequests,
                    detailCache: detailCache,
                    rpc: rpc
                )
            } else {
                await catchUpActivityIfNeeded(
                    viewerID: viewerID,
                    detailCache: detailCache,
                    rpc: rpc
                )
            }
            return
        }

        if let applied = await loadRpcBootstrapIfAvailable(
            viewerID: ProfileID(userID),
            detailCache: detailCache,
            rpc: rpc,
            limit: Self.pageSize,
            cursor: nil
        ) {
            replace(
                items: applied.items,
                unreadCount: applied.unreadCount,
                nextCursor: applied.nextCursor,
                pendingFollowRequestCount: applied.pendingFollowRequestCount
            )
#if DEBUG
            SocialCacheProbe.recordActivityCatchup(items: applied.items.count, fullBootstrap: true)
#endif
            startRealtime(
                userID: userID,
                notifications: notifications,
                session: session,
                realtimeHub: realtimeHub
            )
            return
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
        realtimeHub: RealtimeHub?,
        detailCache: DetailPresentationCache? = nil,
        rpc: (any RPCClient)? = nil
    ) async {
        if DemoExperienceSupport.skipsAuthenticatedViewerServices { return }
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
            realtimeWatchSessionGeneration &+= 1
            invalidateRealtimeOnly()
            items = []
            unreadCount = 0
            pendingFollowRequestCount = 0
            hasLoaded = false
            hasBootstrappedUnread = false
            nextCursor = nil
            hasMore = true
            startedForUserID = userID
            persistedViewerID = ProfileID(userID)
            if SocialPersistedCacheCoordinator.hydrateActivity(viewerID: ProfileID(userID), store: self) {
                hasBootstrappedUnread = true
            }
        }

        if let applied = await loadRpcBootstrapIfAvailable(
            viewerID: ProfileID(userID),
            detailCache: detailCache,
            rpc: rpc,
            limit: 0,
            cursor: nil
        ) {
            setUnreadCount(applied.unreadCount)
            if !hasLoaded {
                pendingFollowRequestCount = applied.pendingFollowRequestCount
            }
            hasBootstrappedUnread = true
            startRealtime(
                userID: userID,
                notifications: notifications,
                session: session,
                realtimeHub: realtimeHub
            )
            return
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
        followRequests: (any FollowRequestRepository)?,
        detailCache: DetailPresentationCache? = nil,
        rpc: (any RPCClient)? = nil
    ) async throws {
        if let viewerRaw = startedForUserID,
           let applied = await loadRpcBootstrapIfAvailable(
               viewerID: ProfileID(viewerRaw),
               detailCache: detailCache,
               rpc: rpc,
               limit: Self.pageSize,
               cursor: nil
           )
        {
            replace(
                items: applied.items,
                unreadCount: applied.unreadCount,
                nextCursor: applied.nextCursor,
                pendingFollowRequestCount: applied.pendingFollowRequestCount
            )
            return
        }

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
        realtimeWatchSessionGeneration &+= 1
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
        persistedViewerID = nil
        seenNotificationEventKeys.removeAll()
        AppIconBadgeController.shared.clear()
    }

    private func schedulePersistSnapshot() {
        guard let persistedViewerID else { return }
        let blob = SocialDiskCache.ActivityBlob(
            viewerID: persistedViewerID.rawValue,
            savedAt: Date(),
            items: items,
            unreadCount: unreadCount,
            pendingFollowRequestCount: pendingFollowRequestCount,
            nextCursor: nextCursor
        )
        Task.detached(priority: .utility) {
            SocialDiskCache.saveActivity(blob)
        }
    }

    /// Authoritative first-page sync when Activity is on screen (replace, not merge-only catch-up).
    private func syncPresentedFeed(
        viewerID: ProfileID,
        notifications: any NotificationRepository,
        followRequests: (any FollowRequestRepository)?,
        detailCache: DetailPresentationCache?,
        rpc: (any RPCClient)?
    ) async {
        if let applied = await loadRpcBootstrapIfAvailable(
            viewerID: viewerID,
            detailCache: detailCache,
            rpc: rpc,
            limit: Self.pageSize,
            cursor: nil
        ) {
            replace(
                items: applied.items,
                unreadCount: applied.unreadCount,
                nextCursor: applied.nextCursor,
                pendingFollowRequestCount: applied.pendingFollowRequestCount
            )
#if DEBUG
            SocialCacheProbe.recordActivityCatchup(items: applied.items.count, fullBootstrap: true)
#endif
            ActivityPipelineProbe.record(stage: "presentedFeedBootstrap", stored: applied.items.count)
            return
        }

        do {
            let page = try await notifications.notifications(
                page: PageRequest(limit: Self.pageSize)
            )
            let previousFollowCount = pendingFollowRequestCount
            async let unreadTask = notifications.unreadCount()
            async let followTask: Int = {
                guard let followRequests else { return previousFollowCount }
                return (try? await followRequests.pendingRequests().count) ?? previousFollowCount
            }()
            let unread = (try? await unreadTask) ?? unreadCount
            let followCount = await followTask
            replace(
                items: page.items,
                unreadCount: unread,
                nextCursor: page.nextCursor,
                pendingFollowRequestCount: followCount
            )
            ActivityPipelineProbe.record(stage: "presentedFeedREST", stored: page.items.count)
        } catch {
            ActivityPipelineProbe.record(stage: "presentedFeedFailed", note: String(describing: error))
        }
    }

    /// Unread-only reconnect repair — bell/badge correctness without full feed bootstrap.
    func repairUnreadAfterReconnect(
        viewerID: ProfileID,
        notifications: any NotificationRepository,
        detailCache: DetailPresentationCache?,
        rpc: (any RPCClient)?
    ) async {
        if let applied = await loadRpcBootstrapIfAvailable(
            viewerID: viewerID,
            detailCache: detailCache,
            rpc: rpc,
            limit: 0,
            cursor: nil
        ) {
            setUnreadCount(applied.unreadCount)
            if !hasLoaded {
                pendingFollowRequestCount = applied.pendingFollowRequestCount
            }
            return
        }
        if let unread = try? await notifications.unreadCount() {
            setUnreadCount(unread)
        }
    }

    /// Bounded Activity catch-up after Realtime reconnect — merge only, no wipe.
    func repairAfterReconnect(
        viewerID: ProfileID,
        detailCache: DetailPresentationCache?,
        rpc: (any RPCClient)?
    ) async {
        await catchUpActivityIfNeeded(
            viewerID: viewerID,
            detailCache: detailCache,
            rpc: rpc
        )
    }

    private func catchUpActivityIfNeeded(
        viewerID: ProfileID,
        detailCache: DetailPresentationCache?,
        rpc: (any RPCClient)?
    ) async {
        guard let applied = await loadRpcBootstrapIfAvailable(
            viewerID: viewerID,
            detailCache: detailCache,
            rpc: rpc,
            limit: Self.pageSize,
            cursor: nil
        ) else {
            return
        }
        mergeCatchUp(
            items: applied.items,
            unreadCount: applied.unreadCount,
            pendingFollowRequestCount: applied.pendingFollowRequestCount
        )
    }

    func resetForTesting() {
        invalidate()
    }

    // MARK: - Private

    private func loadRpcBootstrapIfAvailable(
        viewerID: ProfileID,
        detailCache: DetailPresentationCache?,
        rpc: (any RPCClient)?,
        limit: Int,
        cursor: String?
    ) async -> ActivityBootstrapApplier.Applied? {
        guard let rpc else { return nil }
        guard let applied = try? await ActivityBootstrapLoader.load(
            viewerID: viewerID,
            rpc: rpc,
            limit: limit,
            cursor: cursor
        ) else { return nil }
        ActivityBootstrapApplier.seedActors(applied.actorProfiles, detailCache: detailCache)
        return applied
    }

    private func invalidateRealtimeOnly() {
        realtimeTask?.cancel()
        realtimeTask = nil
        let userID = activeRealtimeUserID
        let hub = activeRealtimeHub
        activeRealtimeUserID = nil
        activeRealtimeHub = nil
        let consumer = notificationsRealtimeConsumer
        notificationsRealtimeConsumer = nil
        realtimeWatchBoundGeneration = nil
        guard let userID, let hub else { return }
        Task {
            await hub.releaseWatch(consumer)
            try? await hub.subscriptions.unsubscribe(
                RealtimeChannelID(kind: .notifications, topic: "user:\(userID)")
            )
        }
    }

    private func startRealtime(
        userID: String,
        notifications: any NotificationRepository,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) {
        guard let realtimeHub else { return }
        if activeRealtimeUserID == userID,
           realtimeTask != nil,
           notificationsRealtimeConsumer != nil,
           realtimeWatchBoundGeneration == realtimeWatchSessionGeneration
        {
            return
        }
        invalidateRealtimeOnly()
        activeRealtimeUserID = userID
        activeRealtimeHub = realtimeHub
        realtimeWatchBoundGeneration = realtimeWatchSessionGeneration
#if DEBUG
        SocialCacheProbe.setRealtimeSubscribed(true)
#endif
        let channel = RealtimeChannelID(kind: .notifications, topic: "user:\(userID)")
        realtimeTask = Task { [weak self] in
            try? await realtimeHub.subscriptions.subscribe(channel)
            let token = await session.accessToken
            let watch = realtimeHub.watchNotifications(
                userID: userID,
                accessToken: token,
                debugOwner: "ActivityInbox"
            )
            guard let self else { return }
            self.notificationsRealtimeConsumer = watch.consumer
            for await signal in watch.events {
                await self.applyRealtime(signal: signal, notifications: notifications)
            }
            self.realtimeTask = nil
        }
    }

    private func applyRealtime(
        signal: MessageRealtimeSignal,
        notifications: any NotificationRepository
    ) async {
        guard let rawID = signal.messageID else { return }
        let id = NotificationID(rawID)
        let dedupeKey = "\(signal.kind.rawValue):\(rawID)"
        if seenNotificationEventKeys.contains(dedupeKey) {
#if DEBUG
            ActivityRealtimeDebugLog.duplicateDeliveryIgnored(id: rawID)
#endif
            return
        }
        seenNotificationEventKeys.insert(dedupeKey)

        switch signal.kind {
        case .insert, .update:
            var hydrated = false
            if let payload = signal.recordPayload,
               var merged = ActivityNotificationRealtimeMerge.notification(from: payload)
            {
                if signal.kind == .update,
                   let existing = items.first(where: { $0.id == id })
                {
                    if merged.actorProfileID == nil { merged.actorProfileID = existing.actorProfileID }
                    if merged.title.isEmpty { merged.title = existing.title }
                    if merged.body.isEmpty { merged.body = existing.body }
                }
                if ActivityNotificationRealtimeMerge.needsRowHydration(merged) {
#if DEBUG
                    ActivityRealtimeDebugLog.notificationHydration(id: rawID, reason: "missing_actor")
#endif
                    if let row = try? await notifications.notification(id: id) {
                        upsert(row)
                        hydrated = true
                    } else {
                        upsert(merged)
                    }
                } else {
                    upsert(merged)
                }
#if DEBUG
                if signal.kind == .insert {
                    ActivityRealtimeDebugLog.notificationInsert(id: rawID, hydrated: hydrated)
                } else {
                    ActivityRealtimeDebugLog.notificationUpdate(id: rawID, hydrated: hydrated)
                }
#endif
            } else if let item = try? await notifications.notification(id: id) {
#if DEBUG
                ActivityRealtimeDebugLog.networkFallback(reason: "payload_merge_miss")
                if signal.kind == .insert {
                    ActivityRealtimeDebugLog.notificationInsert(id: rawID, hydrated: true)
                } else {
                    ActivityRealtimeDebugLog.notificationUpdate(id: rawID, hydrated: true)
                }
#endif
                upsert(item)
            } else if signal.kind == .update {
                if let existing = items.first(where: { $0.id == id }) {
                    var patched = existing
                    if let payload = signal.recordPayload,
                       let dto = PostgresChangeRecordCodec.decode(NotificationDTO.Item.self, from: payload)
                    {
                        if let read = dto.read ?? dto.is_read { patched.isRead = read }
                    }
                    upsert(patched)
                } else if let count = try? await notifications.unreadCount() {
#if DEBUG
                    ActivityRealtimeDebugLog.networkFallback(reason: "update_unread_recount")
#endif
                    setUnreadCount(count)
                }
            }
        case .delete:
#if DEBUG
            ActivityRealtimeDebugLog.notificationDelete(id: rawID)
#endif
            remove(id: id)
        }
    }

    private static func sortNewestFirst(_ items: [ActivityNotification]) -> [ActivityNotification] {
        items.sorted { $0.createdAt > $1.createdAt }
    }
}

#if DEBUG
extension ActivityInboxStore {
    func testing_applyRealtime(signal: MessageRealtimeSignal, notifications: any NotificationRepository) async {
        await applyRealtime(signal: signal, notifications: notifications)
    }
}
#endif
