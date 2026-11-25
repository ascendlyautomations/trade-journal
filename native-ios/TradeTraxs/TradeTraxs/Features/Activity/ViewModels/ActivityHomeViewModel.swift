import Foundation
import Observation

@Observable
@MainActor
final class ActivityHomeViewModel {
    private let notifications: any NotificationRepository
    private let followRequests: any FollowRequestRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let navigationHost: ActivityNavigationHost
    private let realtimeHub: RealtimeHub?
    private let inboxStore: ActivityInboxStore
    private let router: any NotificationRouting
    private let rpc: (any RPCClient)?

    private(set) var phase: ActivityLoadPhase = .idle
    private(set) var actors: [ProfileID: Profile] = [:]
    private(set) var isMarkingAllRead = false
    private var hydrationTask: Task<Void, Never>?

    var dateFilter: ActivityNotificationDateFilter = .allTime
    var typeFilter: ActivityNotificationTypeCategory = .allTypes
    var customDateInterval: DateInterval?
    var showsCustomDateSheet = false
    var draftCustomRangeStart: Date?
    var draftCustomRangeEnd: Date?

    private(set) var filteredItems: [ActivityNotification] = []
    private(set) var filteredNextCursor: String?
    private(set) var filteredHasMore = false
    private(set) var filteredIsLoadingMore = false
    private(set) var isReloadingFiltered = false
    private var filteredReloadTask: Task<Void, Never>?
    private var filterReloadGeneration: UInt = 0

    init(
        notifications: any NotificationRepository,
        followRequests: any FollowRequestRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        navigationHost: ActivityNavigationHost = .home,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: ActivityInboxStore,
        router: any NotificationRouting,
        rpc: (any RPCClient)? = nil
    ) {
        self.notifications = notifications
        self.followRequests = followRequests
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore
        self.router = router
        self.rpc = rpc
    }

    var sections: [ActivitySectionModel] {
        ActivityPresentation.sections(
            from: presentationItems,
            actors: resolvedActors(for: presentationItems)
        )
    }

    var showsEmpty: Bool {
        guard phase == .loaded else { return false }
        if usesListFilters {
            return presentationItems.isEmpty && !isReloadingFiltered
        }
        return inboxStore.items.isEmpty && inboxStore.pendingFollowRequestCount == 0
    }

    var emptyStateTitle: String {
        usesListFilters ? "No matching activity" : "No activity yet"
    }

    var emptyStateMessage: String {
        if usesListFilters {
            return "Try a different date range or notification type."
        }
        return "When people interact with your trades, posts, profile, or Trade Rooms, you'll see it here."
    }

    var unreadCount: Int { inboxStore.unreadCount }
    var pendingFollowRequestCount: Int { inboxStore.pendingFollowRequestCount }
    var isLoadingMore: Bool {
        usesListFilters ? filteredIsLoadingMore : inboxStore.isLoadingMore
    }
    var hasMore: Bool {
        usesListFilters ? filteredHasMore : inboxStore.hasMore
    }

    var usesListFilters: Bool {
        ActivityNotificationFilterSupport.isFilterActive(
            dateFilter: dateFilter,
            customInterval: customDateInterval,
            typeCategory: typeFilter
        )
    }

    var listFilter: ActivityNotificationListFilter {
        ActivityNotificationFilterSupport.listFilter(
            dateFilter: dateFilter,
            customInterval: customDateInterval,
            typeCategory: typeFilter
        )
    }

    var dateFilterLabel: String {
        ActivityNotificationFilterSupport.compactDateLabel(
            dateFilter: dateFilter,
            customInterval: customDateInterval
        )
    }

    var typeFilterLabel: String {
        typeFilter.compactLabel
    }

    var canApplyCustomDateRange: Bool {
        draftCustomRangeStart != nil && draftCustomRangeEnd != nil
    }

    private var presentationItems: [ActivityNotification] {
        usesListFilters ? filteredItems : inboxStore.items
    }

    func loadIfNeeded() {
        if inboxStore.hasAuthoritativeFeedForSession, inboxStore.hasLoaded {
            phase = .loaded
            seedActorsFromDetailCache(for: inboxStore.items)
            return
        }
        guard hydrationTask == nil else { return }
        hydrationTask = Task {
            defer { hydrationTask = nil }
            await load(force: false)
        }
    }

    func refresh() async {
        ActivityFeedBootstrapPriorityGate.setScreenActive(true)
        defer { ActivityFeedBootstrapPriorityGate.setScreenActive(false) }
        await load(force: true)
    }

    func loadMoreIfNeeded(currentID: NotificationID) {
        guard hasMore, !isLoadingMore else { return }
        guard let last = presentationItems.last, last.id == currentID else { return }
        if usesListFilters {
            Task { await loadMoreFilteredIfNeeded() }
        } else {
            Task {
                do {
                    try await inboxStore.loadMore(notifications: notifications)
                    await hydrateActors(for: inboxStore.items)
                } catch {
                    // Soft-fail pagination.
                }
            }
        }
    }

    func selectDateFilter(_ value: ActivityNotificationDateFilter) {
        if value == .custom {
            ExperienceHaptics.play(.selection)
            draftCustomRangeStart = customDateInterval?.start ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())
            draftCustomRangeEnd = customDateInterval?.end ?? Date()
            showsCustomDateSheet = true
            return
        }
        guard dateFilter != value else { return }
        ExperienceHaptics.play(.selection)
        dateFilter = value
        customDateInterval = nil
        scheduleFilteredReload()
    }

    func selectTypeFilter(_ value: ActivityNotificationTypeCategory) {
        guard typeFilter != value else { return }
        ExperienceHaptics.play(.selection)
        typeFilter = value
        scheduleFilteredReload()
    }

    func applyCustomDateRange() {
        guard let start = draftCustomRangeStart, let end = draftCustomRangeEnd else { return }
        customDateInterval = DashboardScopeFilterSupport.normalizedCustomInterval(start: start, end: end)
        dateFilter = .custom
        scheduleFilteredReload()
    }

    func open(_ row: ActivityRowModel) {
        ExperienceHaptics.play(.selection)
        if row.isUnread {
            for id in row.groupedNotificationIDs {
                markRead(id: id, playHaptic: false)
            }
        }
        if let roomID = row.notification.roomID,
           row.notification.kind == .roomMention || row.notification.kind == .roomJoin
        {
            RoomNavigationFocusStore.shared.seed(
                roomID: roomID,
                sectionID: row.notification.sectionID,
                messageID: row.notification.roomMessageID?.rawValue
            )
        }
        ActivityNotificationRouting.open(
            row.notification,
            host: navigationHost,
            coordinator: navigationCoordinator,
            detailCache: detailCache,
            router: router
        )
    }

    func openActor(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        switch navigationHost {
        case .home:
            navigationCoordinator.pushHome(.otherProfile(profileID))
        case .profile:
            navigationCoordinator.pushProfile(.otherProfile(profileID))
        }
    }

    func openFollowRequests() {
        ExperienceHaptics.play(.selection)
        switch navigationHost {
        case .home:
            navigationCoordinator.pushHome(.followRequests)
        case .profile:
            navigationCoordinator.open(.profile(.followRequests))
        }
    }

    func openNotificationSettings() {
        ExperienceHaptics.play(.selection)
        switch navigationHost {
        case .home:
            navigationCoordinator.pushHome(.settings(.notifications))
        case .profile:
            navigationCoordinator.pushProfile(.settings(.notifications))
        }
    }

    func markRead(id: NotificationID, playHaptic: Bool = true) {
        if playHaptic {
            ExperienceHaptics.play(.selection)
        }
        guard let existing = presentationItems.first(where: { $0.id == id }), !existing.isRead else {
            return
        }
        if inboxStore.items.contains(where: { $0.id == id }) {
            inboxStore.markReadLocally(id: id)
        } else {
            markFilteredReadLocally(id: id)
        }
        patchFilteredItem(id: id) { $0.isRead = true }
        Task {
            do {
                try await notifications.markRead(id: id)
                AppIconBadgeSync.refresh(animated: true)
            } catch {
                if inboxStore.items.contains(where: { $0.id == id }) {
                    inboxStore.markUnreadLocally(id: id)
                } else {
                    patchFilteredItem(id: id) { $0.isRead = false }
                    inboxStore.setUnreadCount(inboxStore.unreadCount + 1)
                }
            }
        }
    }

    func markRead(row: ActivityRowModel) {
        ExperienceHaptics.play(.selection)
        let unreadIDs = row.groupedNotificationIDs.filter { id in
            presentationItems.first(where: { $0.id == id })?.isRead == false
        }
        guard !unreadIDs.isEmpty else { return }

        let started = CFAbsoluteTimeGetCurrent()
        let inboxIDs = unreadIDs.filter { id in inboxStore.items.contains(where: { $0.id == id }) }
        if !inboxIDs.isEmpty {
            inboxStore.markReadLocally(ids: inboxIDs)
        }
        for id in unreadIDs where !inboxIDs.contains(id) {
            markFilteredReadLocally(id: id)
        }
        for id in unreadIDs {
            patchFilteredItem(id: id) { $0.isRead = true }
        }
        Task {
            do {
                _ = try await notifications.markRead(ids: unreadIDs)
                AppIconBadgeSync.refresh(animated: true)
                NotificationReadDiagnostics.logBulkMarkRead(
                    ids: unreadIDs.count,
                    requests: 1,
                    dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
                )
            } catch {
                for id in unreadIDs where inboxIDs.contains(id) {
                    inboxStore.markUnreadLocally(id: id)
                }
                for id in unreadIDs {
                    patchFilteredItem(id: id) { $0.isRead = false }
                }
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func markUnread(row: ActivityRowModel) {
        ExperienceHaptics.play(.selection)
        let readIDs = row.groupedNotificationIDs.filter { id in
            presentationItems.first(where: { $0.id == id })?.isRead == true
        }
        guard !readIDs.isEmpty else { return }

        let inboxIDs = readIDs.filter { id in inboxStore.items.contains(where: { $0.id == id }) }
        if !inboxIDs.isEmpty {
            inboxStore.markUnreadLocally(ids: inboxIDs)
        }
        for id in readIDs where !inboxIDs.contains(id) {
            markFilteredUnreadLocally(id: id)
        }
        for id in readIDs {
            patchFilteredItem(id: id) { $0.isRead = false }
        }
        Task {
            do {
                _ = try await notifications.markUnread(ids: readIDs)
                AppIconBadgeSync.refresh(animated: true)
            } catch {
                for id in readIDs where inboxIDs.contains(id) {
                    inboxStore.markReadLocally(id: id)
                }
                for id in readIDs {
                    patchFilteredItem(id: id) { $0.isRead = true }
                }
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func delete(row: ActivityRowModel) {
        ExperienceHaptics.play(.selection)
        let ids = row.groupedNotificationIDs
        let removedSnapshot = ids.compactMap { id in presentationItems.first(where: { $0.id == id }) }
        guard !removedSnapshot.isEmpty else { return }
        let removedFromInbox = inboxStore.removeLocally(ids: ids)
        removeFilteredLocally(ids: ids)

        Task {
            do {
                _ = try await notifications.delete(ids: ids)
                AppIconBadgeSync.refresh(animated: true)
            } catch {
                inboxStore.restoreLocally(removedFromInbox)
                filteredItems.append(contentsOf: removedSnapshot.filter { item in
                    !filteredItems.contains(where: { $0.id == item.id })
                })
                filteredItems.sort { $0.createdAt > $1.createdAt }
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func markAllRead() {
        guard unreadCount > 0, !isMarkingAllRead else {
            ActivityMarkReadDiagnostics.logMarkAllRead(
                outcome: .skipped,
                unreadBefore: unreadCount,
                rowCount: inboxStore.items.count
            )
            return
        }
        isMarkingAllRead = true
        let previousItems = inboxStore.items
        let previousUnread = inboxStore.unreadCount
        let rowCount = previousItems.count
        inboxStore.markAllReadLocally()
        Task {
            defer { isMarkingAllRead = false }
            do {
                try await notifications.markAllRead()
                let reconciledUnread = (try? await notifications.unreadCount()) ?? 0
                inboxStore.confirmMarkAllRead(unreadCount: reconciledUnread)
                if usesListFilters {
                    filteredItems = filteredItems.map { item in
                        var copy = item
                        copy.isRead = true
                        return copy
                    }
                }
                ActivityMarkReadDiagnostics.logMarkAllRead(
                    outcome: .success,
                    unreadBefore: previousUnread,
                    rowCount: rowCount
                )
            } catch {
                inboxStore.replace(
                    items: previousItems,
                    unreadCount: previousUnread,
                    nextCursor: inboxStore.nextCursor,
                    pendingFollowRequestCount: inboxStore.pendingFollowRequestCount
                )
                ExperienceHaptics.play(.warning)
                ActivityMarkReadDiagnostics.logMarkAllRead(
                    outcome: .failure,
                    unreadBefore: previousUnread,
                    rowCount: rowCount,
                    errorType: ActivityMarkReadDiagnostics.errorType(error)
                )
            }
        }
    }

    // MARK: - Private

    private func load(force: Bool) async {
        if force {
            if !inboxStore.hasLoaded {
                phase = .loading
            }
        } else if !inboxStore.hasAuthoritativeFeedForSession {
            phase = .loading
        } else if inboxStore.hasLoaded {
            phase = .loaded
            seedActorsFromDetailCache(for: inboxStore.items)
        } else {
            phase = .loading
        }

        await inboxStore.startIfNeeded(
            notifications: notifications,
            followRequests: followRequests,
            session: session,
            realtimeHub: realtimeHub,
            detailCache: detailCache,
            rpc: rpc,
            feedPresentation: true
        )

        if force {
            if usesListFilters {
                await reloadFilteredList(reset: true)
            } else {
                do {
                    try await inboxStore.refresh(
                        notifications: notifications,
                        followRequests: followRequests,
                        detailCache: detailCache,
                        rpc: rpc
                    )
                    phase = .loaded
                } catch {
                    if inboxStore.items.isEmpty {
                        phase = .failed(MessagesInboxSupport.message(for: error))
                    } else {
                        phase = .loaded
                    }
                    return
                }
            }
        } else if usesListFilters {
            await reloadFilteredList(reset: true)
        } else {
            phase = .loaded
        }

        if usesListFilters {
            phase = .loaded
        }

        await hydrateActors(for: presentationItems)
#if DEBUG
        let grouped = ActivityPresentation.sections(from: inboxStore.items, actors: actors)
            .flatMap(\.rows)
            .count
        ActivityPipelineProbe.record(
            stage: "viewModelLoaded",
            stored: inboxStore.items.count,
            grouped: grouped
        )
#endif
    }

    private func resolvedActors(for items: [ActivityNotification]) -> [ProfileID: Profile] {
        var map = actors
        for id in Set(items.compactMap(\.actorProfileID)) {
            if map[id] == nil, let cached = detailCache.profile(id: id) {
                map[id] = cached
            }
        }
        return map
    }

    private func seedActorsFromDetailCache(for items: [ActivityNotification]) {
        var next = actors
        var changed = false
        for id in Set(items.compactMap(\.actorProfileID)) {
            if next[id] == nil, let cached = detailCache.profile(id: id) {
                next[id] = cached
                changed = true
            }
        }
        if changed {
            actors = next
        }
    }

    private func hydrateActors(for items: [ActivityNotification]) async {
        seedActorsFromDetailCache(for: items)
        let ids = Array(Set(items.compactMap(\.actorProfileID)))
        guard !ids.isEmpty else { return }

        var next = actors
        var missing: [ProfileID] = []
        for id in ids {
            if next[id] == nil {
                missing.append(id)
            }
        }

        if !missing.isEmpty {
            // Prefer shared session profile cache (single-flight across features).
            if let profiles = try? await SessionProfileStore.shared.profiles(
                ids: missing,
                detailCache: detailCache,
                repository: profiles
            ) {
                for profile in profiles {
                    detailCache.seed(profile)
                    next[profile.id] = profile
                }
            }
        }

        actors = next
    }

    private func scheduleFilteredReload() {
        if usesListFilters {
            scheduleFilteredReloadImmediate()
        } else {
            filteredItems = []
            filteredNextCursor = nil
            filteredHasMore = false
            filterReloadGeneration &+= 1
        }
    }

    private func scheduleFilteredReloadImmediate() {
        filterReloadGeneration &+= 1
        let generation = filterReloadGeneration
        filteredReloadTask?.cancel()
        filteredReloadTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, generation == filterReloadGeneration else { return }
            await reloadFilteredList(reset: true)
        }
    }

    private func reloadFilteredList(reset: Bool) async {
        guard usesListFilters else { return }
        if reset {
            isReloadingFiltered = true
            filteredItems = []
            filteredNextCursor = nil
            filteredHasMore = false
        }
        defer { isReloadingFiltered = false }

        guard let userID = await session.currentUserID else { return }
        let viewerID = ProfileID(userID.rawValue)
        let filter = listFilter
        let limit = ActivityInboxStore.pageSize

        if let rpc, let applied = try? await ActivityBootstrapLoader.load(
            viewerID: viewerID,
            rpc: rpc,
            limit: limit,
            cursor: nil,
            filter: filter
        ) {
            ActivityBootstrapApplier.seedActors(applied.actorProfiles, detailCache: detailCache)
            filteredItems = applied.items
            filteredNextCursor = applied.nextCursor
            filteredHasMore = applied.nextCursor != nil
            phase = .loaded
            await hydrateActors(for: filteredItems)
            return
        }

        do {
            let page = try await notifications.notifications(
                page: PageRequest(limit: limit),
                filter: filter
            )
            filteredItems = page.items
            filteredNextCursor = page.nextCursor
            filteredHasMore = page.nextCursor != nil
            phase = .loaded
            await hydrateActors(for: filteredItems)
        } catch {
            if filteredItems.isEmpty {
                phase = .failed(MessagesInboxSupport.message(for: error))
            } else {
                phase = .loaded
            }
        }
    }

    private func loadMoreFilteredIfNeeded() async {
        guard filteredHasMore, !filteredIsLoadingMore, let cursor = filteredNextCursor else { return }
        filteredIsLoadingMore = true
        defer { filteredIsLoadingMore = false }
        let filter = listFilter
        guard let userID = await session.currentUserID else { return }
        let viewerID = ProfileID(userID.rawValue)

        if let rpc, let applied = try? await ActivityBootstrapLoader.load(
            viewerID: viewerID,
            rpc: rpc,
            limit: ActivityInboxStore.pageSize,
            cursor: cursor,
            filter: filter
        ) {
            ActivityBootstrapApplier.seedActors(applied.actorProfiles, detailCache: detailCache)
            appendFiltered(page: applied.items, nextCursor: applied.nextCursor)
            await hydrateActors(for: filteredItems)
            return
        }

        if let page = try? await notifications.notifications(
            page: PageRequest(cursor: cursor, limit: ActivityInboxStore.pageSize),
            filter: filter
        ) {
            appendFiltered(page: page.items, nextCursor: page.nextCursor)
            await hydrateActors(for: filteredItems)
        }
    }

    private func appendFiltered(page items: [ActivityNotification], nextCursor: String?) {
        var merged = filteredItems
        let existing = Set(merged.map(\.id))
        for item in items where !existing.contains(item.id) {
            merged.append(item)
        }
        filteredItems = merged.sorted { $0.createdAt > $1.createdAt }
        filteredNextCursor = nextCursor
        filteredHasMore = nextCursor != nil
    }

    private func markFilteredReadLocally(id: NotificationID) {
        guard let index = filteredItems.firstIndex(where: { $0.id == id }),
              !filteredItems[index].isRead
        else { return }
        filteredItems[index].isRead = true
        inboxStore.setUnreadCount(max(0, inboxStore.unreadCount - 1))
    }

    private func markFilteredUnreadLocally(id: NotificationID) {
        guard let index = filteredItems.firstIndex(where: { $0.id == id }),
              filteredItems[index].isRead
        else { return }
        filteredItems[index].isRead = false
        inboxStore.setUnreadCount(inboxStore.unreadCount + 1)
    }

    private func patchFilteredItem(id: NotificationID, patch: (inout ActivityNotification) -> Void) {
        guard let index = filteredItems.firstIndex(where: { $0.id == id }) else { return }
        patch(&filteredItems[index])
    }

    private func removeFilteredLocally(ids: [NotificationID]) {
        let targets = Set(ids)
        guard !targets.isEmpty else { return }
        filteredItems.removeAll { targets.contains($0.id) }
    }
}
