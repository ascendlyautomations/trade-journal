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
    private let realtimeHub: RealtimeHub?
    private let inboxStore: ActivityInboxStore
    private let router: any NotificationRouting

    private(set) var phase: ActivityLoadPhase = .idle
    private(set) var actors: [ProfileID: Profile] = [:]
    private(set) var isMarkingAllRead = false
    private var hydrationTask: Task<Void, Never>?

    init(
        notifications: any NotificationRepository,
        followRequests: any FollowRequestRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: ActivityInboxStore = .shared,
        router: any NotificationRouting = NotificationRouter()
    ) {
        self.notifications = notifications
        self.followRequests = followRequests
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore
        self.router = router
    }

    var sections: [ActivitySectionModel] {
        ActivityPresentation.sections(from: inboxStore.items, actors: actors)
    }

    var showsEmpty: Bool {
        phase == .loaded && inboxStore.items.isEmpty && inboxStore.pendingFollowRequestCount == 0
    }

    var unreadCount: Int { inboxStore.unreadCount }
    var pendingFollowRequestCount: Int { inboxStore.pendingFollowRequestCount }
    var isLoadingMore: Bool { inboxStore.isLoadingMore }
    var hasMore: Bool { inboxStore.hasMore }

    func loadIfNeeded() {
        Task { await load(force: false) }
    }

    func refresh() async {
        await load(force: true)
    }

    func loadMoreIfNeeded(currentID: NotificationID) {
        guard hasMore, !isLoadingMore else { return }
        guard let last = inboxStore.items.last, last.id == currentID else { return }
        Task {
            do {
                try await inboxStore.loadMore(notifications: notifications)
                await hydrateActors(for: inboxStore.items)
            } catch {
                // Soft-fail pagination.
            }
        }
    }

    func open(_ row: ActivityRowModel) {
        if row.isUnread {
            markRead(id: row.id)
        }
        let destination = ActivityNotificationRouting.appDestination(
            for: row.notification,
            router: router
        )
        navigationCoordinator.open(destination)
    }

    func openActor(_ profileID: ProfileID) {
        navigationCoordinator.open(.profile(.otherProfile(profileID)))
    }

    func openFollowRequests() {
        navigationCoordinator.open(.profile(.followRequests))
    }

    func openNotificationSettings() {
        navigationCoordinator.openSettings([.home, .notifications])
    }

    func markRead(id: NotificationID) {
        inboxStore.markReadLocally(id: id)
        Task {
            do {
                try await notifications.markRead(id: id)
            } catch {
                // Soft-fail — next refresh reconciles.
            }
        }
    }

    func markAllRead() {
        guard unreadCount > 0, !isMarkingAllRead else { return }
        isMarkingAllRead = true
        let previousItems = inboxStore.items
        let previousUnread = inboxStore.unreadCount
        inboxStore.markAllReadLocally()
        Task {
            defer { isMarkingAllRead = false }
            do {
                try await notifications.markAllRead()
            } catch {
                inboxStore.replace(
                    items: previousItems,
                    unreadCount: previousUnread,
                    nextCursor: inboxStore.nextCursor,
                    pendingFollowRequestCount: inboxStore.pendingFollowRequestCount
                )
                phase = .failed(MessagesInboxSupport.message(for: error))
            }
        }
    }

    // MARK: - Private

    private func load(force: Bool) async {
        if !force, inboxStore.hasLoaded {
            phase = .loaded
            await hydrateActors(for: inboxStore.items)
            await inboxStore.startIfNeeded(
                notifications: notifications,
                followRequests: followRequests,
                session: session,
                realtimeHub: realtimeHub
            )
            return
        }

        if !inboxStore.hasLoaded {
            phase = .loading
        }

        await inboxStore.startIfNeeded(
            notifications: notifications,
            followRequests: followRequests,
            session: session,
            realtimeHub: realtimeHub
        )

        if force {
            do {
                try await inboxStore.refresh(
                    notifications: notifications,
                    followRequests: followRequests
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
        } else {
            phase = .loaded
        }

        await hydrateActors(for: inboxStore.items)
    }

    private func hydrateActors(for items: [ActivityNotification]) async {
        let ids = Array(Set(items.compactMap(\.actorProfileID)))
        guard !ids.isEmpty else { return }

        var next = actors
        var missing: [ProfileID] = []
        for id in ids {
            if let cached = detailCache.profile(id: id) {
                next[id] = cached
            } else if next[id] == nil {
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
}
