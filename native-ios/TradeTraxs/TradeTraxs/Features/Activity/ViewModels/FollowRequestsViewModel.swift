import Foundation
import Observation

struct FollowRequestRowModel: Identifiable, Hashable {
    var id: FollowRequestID
    var request: FollowRequest
    var profile: Profile?
    var isBusy: Bool
}

@Observable
@MainActor
final class FollowRequestsViewModel {
    private let followRequests: any FollowRequestRepository
    private let notifications: any NotificationRepository
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let inboxStore: ActivityInboxStore

    private(set) var phase: ActivityLoadPhase = .idle
    private(set) var rows: [FollowRequestRowModel] = []
    private var busyIDs: Set<FollowRequestID> = []

    init(
        followRequests: any FollowRequestRepository,
        notifications: any NotificationRepository,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        inboxStore: ActivityInboxStore = .shared
    ) {
        self.followRequests = followRequests
        self.notifications = notifications
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.inboxStore = inboxStore
    }

    var showsEmpty: Bool {
        phase == .loaded && rows.isEmpty
    }

    func loadIfNeeded() {
        Task { await load() }
    }

    func refresh() async {
        await load()
    }

    func openProfile(_ profileID: ProfileID) {
        navigationCoordinator.open(.profile(.otherProfile(profileID)))
    }

    func approve(_ id: FollowRequestID) {
        guard !busyIDs.contains(id) else { return }
        let snapshot = rows
        let requester = rows.first(where: { $0.id == id })?.request.requesterProfileID
        busyIDs.insert(id)
        rows = rows.filter { $0.id != id }
        inboxStore.setPendingFollowRequestCount(max(0, inboxStore.pendingFollowRequestCount - 1))
        Task {
            do {
                try await followRequests.approve(id: id)
                if let requester {
                    FollowMutationCoordinator.shared.noteIncomingFollowAccepted(requester: requester)
                }
                busyIDs.remove(id)
            } catch {
                busyIDs.remove(id)
                rows = snapshot
                inboxStore.setPendingFollowRequestCount(snapshot.count)
                phase = .failed(MessagesInboxSupport.message(for: error))
            }
        }
    }

    func decline(_ id: FollowRequestID) {
        guard !busyIDs.contains(id) else { return }
        let snapshot = rows
        busyIDs.insert(id)
        rows = rows.filter { $0.id != id }
        inboxStore.setPendingFollowRequestCount(max(0, inboxStore.pendingFollowRequestCount - 1))
        Task {
            do {
                try await followRequests.decline(id: id)
                busyIDs.remove(id)
            } catch {
                busyIDs.remove(id)
                rows = snapshot
                inboxStore.setPendingFollowRequestCount(snapshot.count)
                phase = .failed(MessagesInboxSupport.message(for: error))
            }
        }
    }

    private func load() async {
        if rows.isEmpty { phase = .loading }
        do {
            #if DEBUG
            let useFixtures = ProcessInfo.processInfo.arguments.contains(
                "-uitesting-activity-follow-requests"
            )
            let requests = useFixtures
                ? ActivityFixtures.followRequests()
                : try await followRequests.pendingRequests()
            #else
            let requests = try await followRequests.pendingRequests()
            #endif
            let ids = requests.map(\.requesterProfileID)
            var profilesByID: [ProfileID: Profile] = [:]
            for id in ids {
                if let cached = detailCache.profile(id: id) {
                    profilesByID[id] = cached
                }
            }
            let missing = ids.filter { profilesByID[$0] == nil }
            if !missing.isEmpty, let fetched = try? await notifications.profiles(ids: missing) {
                for profile in fetched {
                    detailCache.seed(profile)
                    profilesByID[profile.id] = profile
                }
            }
            #if DEBUG
            if useFixtures {
                for profile in ActivityFixtures.profiles() {
                    detailCache.seed(profile)
                    profilesByID[profile.id] = profile
                }
            }
            #endif
            rows = requests.map { request in
                FollowRequestRowModel(
                    id: request.id,
                    request: request,
                    profile: profilesByID[request.requesterProfileID],
                    isBusy: busyIDs.contains(request.id)
                )
            }
            inboxStore.setPendingFollowRequestCount(rows.count)
            phase = .loaded
        } catch {
            if rows.isEmpty {
                phase = .failed(MessagesInboxSupport.message(for: error))
            } else {
                phase = .loaded
            }
        }
    }
}
