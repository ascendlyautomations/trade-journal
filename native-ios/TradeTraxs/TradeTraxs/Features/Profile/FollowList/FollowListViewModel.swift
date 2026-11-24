import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class FollowListViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let kind: FollowListKind
    let listOwnerID: ProfileID

    private(set) var phase: Phase = .idle
    private(set) var items: [Profile] = []
    private(set) var viewerFollowingIDs: Set<ProfileID> = []
    private(set) var isRefreshing = false
    var searchText = ""
    var pendingRemove: Profile?
    var pendingUnfollow: Profile?
    var removeFollowerErrorMessage: String?

    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator

    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var hasLoaded = false
    private var nextCursor: String?
    private var hasMorePages = false
    private(set) var isLoadingMore = false
    private var viewerID: ProfileID?
    private var inFlightFollow: Set<ProfileID> = []
    private var inFlightRemove: Set<ProfileID> = []
    /// Filters stale paginated rows until the server reflects the removal.
    private var suppressedFollowerIDs: Set<ProfileID> = []
    /// Set when the list loads and the authenticated viewer owns this followers list.
    private var canRemoveIncomingFollowers = false

    init(
        kind: FollowListKind,
        listOwnerID: ProfileID,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.kind = kind
        self.listOwnerID = listOwnerID
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
    }

    var isOwnList: Bool {
        guard let viewerID else { return false }
        return viewerID == listOwnerID
    }

    var title: String { kind.title }

    var visibleItems: [Profile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.displayName.lowercased().contains(query)
                || $0.username.lowercased().contains(query)
        }
    }

    var showsEmpty: Bool {
        phase == .loaded && items.isEmpty
    }

    var showsFilteredEmpty: Bool {
        phase == .loaded && !items.isEmpty && visibleItems.isEmpty
    }

    /// Bumped by ``FollowMutationCoordinator``, read from views so follow buttons stay in sync across screens.
    var followRevision: Int { FollowMutationCoordinator.shared.revision }

    /// Authenticated viewer, used to label the viewer's own row in the list.
    var authenticatedProfileID: ProfileID? { viewerID }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        loadTask = Task { await performLoad(forceNetwork: false) }
    }

    func refresh() async {
        loadTask?.cancel()
        loadMoreTask?.cancel()
        nextCursor = nil
        hasMorePages = false
        isRefreshing = true
        await performLoad(forceNetwork: true)
        isRefreshing = false
    }

    func loadMoreIfNeeded(currentProfileID: ProfileID) {
        guard inFlightRemove.isEmpty else { return }
        guard hasMorePages, !isLoadingMore, loadMoreTask == nil else { return }
        guard let last = items.last?.id, last == currentProfileID else { return }
        loadMoreTask = Task { await performLoadMore() }
    }

    func openProfile(_ profile: Profile) {
        if profile.id == viewerID {
            ExperienceHaptics.play(.selection)
            navigationCoordinator.open(.tab(.profile))
            navigationCoordinator.open(.popToRoot(.profile))
            return
        }
        navigationCoordinator.pushOtherProfile(profile.id)
    }

    func isFollowing(_ profile: Profile) -> Bool {
        guard profile.id != viewerID else { return false }
        if kind == .following, isOwnList {
            return items.contains { $0.id == profile.id }
        }
        guard let viewerID else { return false }
        return FollowMutationCoordinator.shared.isFollowing(viewer: viewerID, target: profile.id)
    }

    func toggleFollow(for profile: Profile) {
        guard profile.id != viewerID else { return }
        if isFollowing(profile) {
            pendingUnfollow = profile
            return
        }
        Task { await follow(profile) }
    }

    func confirmUnfollow(_ profile: Profile) async {
        await unfollow(profile)
    }

    func requestRemove(_ profile: Profile) {
        guard kind == .followers, isOwnList else { return }
        pendingRemove = profile
    }

    func confirmRemove(_ profile: Profile) async {
        await removeFollower(profile)
    }

    // MARK: - Private

    private func performLoad(forceNetwork: Bool) async {
        let userID = await session.currentUserID
        viewerID = userID.map { ProfileID($0.rawValue) }

        if !forceNetwork, let cached = cachedList(), !cached.isEmpty {
            items = filterSuppressedFollowers(cached)
            FollowListRemoveDiagnostics.performLoadAppliedList(count: items.count, source: "cache")
            canRemoveIncomingFollowers = kind == .followers && viewerID == listOwnerID
            hasLoaded = true
            phase = .loaded
            await loadViewerFollowing(forceNetwork: false)
            syncViewerFollowingFromCache()
            loadTask = nil
            return
        }

        if forceNetwork {
            nextCursor = nil
            hasMorePages = false
        }

        if items.isEmpty {
            phase = .loading
        }

        if ProfileSectionSupport.isLocalDevelopmentProfile(listOwnerID) {
            applyFixtures()
            hasLoaded = true
            phase = .loaded
            loadTask = nil
            return
        }

        do {
            let page: CursorPage<Profile>
            let request = PageRequest(cursor: nil, limit: FollowListPagination.pageSize)
            switch kind {
            case .followers:
                page = try await profiles.followers(
                    of: listOwnerID,
                    page: request
                )
            case .following:
                page = try await profiles.following(
                    of: listOwnerID,
                    page: request
                )
            }
            guard !Task.isCancelled else { return }
            items = filterSuppressedFollowers(page.items)
            FollowListRemoveDiagnostics.performLoadAppliedList(count: items.count, source: "network")
            canRemoveIncomingFollowers = kind == .followers && viewerID == listOwnerID
            nextCursor = page.nextCursor
            hasMorePages = page.nextCursor != nil
            seedListCache(page.items)
            hasLoaded = true
            phase = .loaded
            await loadViewerFollowing(forceNetwork: forceNetwork)
            syncViewerFollowingFromCache()
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func performLoadMore() async {
        guard hasMorePages, let cursor = nextCursor, !cursor.isEmpty else {
            loadMoreTask = nil
            return
        }
        guard !ProfileSectionSupport.isLocalDevelopmentProfile(listOwnerID) else {
            loadMoreTask = nil
            return
        }
        isLoadingMore = true
        defer {
            isLoadingMore = false
            loadMoreTask = nil
        }
        do {
            let request = PageRequest(cursor: cursor, limit: FollowListPagination.pageSize)
            let page: CursorPage<Profile>
            switch kind {
            case .followers:
                page = try await profiles.followers(of: listOwnerID, page: request)
            case .following:
                page = try await profiles.following(of: listOwnerID, page: request)
            }
            guard !Task.isCancelled else { return }
            var seen = Set(items.map(\.id))
            for profile in filterSuppressedFollowers(page.items) where !seen.contains(profile.id) {
                items.append(profile)
                seen.insert(profile.id)
            }
            nextCursor = page.nextCursor
            hasMorePages = page.nextCursor != nil
            seedListCache(items)
        } catch {
            // Keep existing rows, user can retry by scrolling again.
        }
    }

    private func loadViewerFollowing(forceNetwork: Bool) async {
        guard let viewerID else { return }
        if !forceNetwork, let cached = detailCache.viewerFollowingIDs() {
            viewerFollowingIDs = cached
            return
        }
        if !forceNetwork {
            await FollowMutationCoordinator.shared.hydrateViewerFollowingRelationshipsIfNeeded(viewer: viewerID)
            if let cached = detailCache.viewerFollowingIDs() {
                viewerFollowingIDs = cached
                return
            }
        }
        if ProfileSectionSupport.isLocalDevelopmentProfile(viewerID)
            || ProfileSectionSupport.isLocalDevelopmentProfile(listOwnerID)
        {
            let ids = Set(FollowListFixtures.following(owner: viewerID).map(\.id))
            viewerFollowingIDs = ids
            FollowMutationCoordinator.shared.seedViewerFollowingRelationships(ids: ids, viewer: viewerID)
            return
        }
        do {
            let ids = try await fetchCompleteViewerFollowingIDs(viewerID: viewerID)
            viewerFollowingIDs = ids
            FollowMutationCoordinator.shared.seedViewerFollowingRelationships(ids: ids, viewer: viewerID)
        } catch {
            // Soft-fail, buttons default to Follow.
        }
    }

    private func fetchCompleteViewerFollowingIDs(viewerID: ProfileID) async throws -> Set<ProfileID> {
        var ids = Set<ProfileID>()
        var cursor: String?
        repeat {
            let page = try await profiles.following(
                of: viewerID,
                page: PageRequest(cursor: cursor, limit: FollowListPagination.pageSize)
            )
            ids.formUnion(page.items.map(\.id))
            cursor = page.nextCursor
        } while cursor != nil
        return ids
    }

    private func syncViewerFollowingFromCache() {
        if let ids = detailCache.viewerFollowingIDs() {
            viewerFollowingIDs = ids
        }
    }

    private func follow(_ profile: Profile) async {
        guard let viewerID, !inFlightFollow.contains(profile.id) else { return }
        inFlightFollow.insert(profile.id)
        defer { inFlightFollow.remove(profile.id) }

        let previous = viewerFollowingIDs
        viewerFollowingIDs.insert(profile.id)
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerID,
            target: profile.id,
            isFollowing: true
        )
        ExperienceHaptics.play(.selection)

        if profile.id.rawValue.hasPrefix("dev.") {
            return
        }

        do {
            try await profiles.follow(from: viewerID, to: profile.id)
            syncViewerFollowingFromCache()
        } catch {
            viewerFollowingIDs = previous
            FollowMutationCoordinator.shared.applyEdgeChange(
                viewer: viewerID,
                target: profile.id,
                isFollowing: false
            )
            syncViewerFollowingFromCache()
            ExperienceHaptics.play(.warning)
        }
    }

    private func unfollow(_ profile: Profile) async {
        guard let viewerID, !inFlightFollow.contains(profile.id) else { return }
        inFlightFollow.insert(profile.id)
        defer { inFlightFollow.remove(profile.id) }

        let previous = viewerFollowingIDs
        viewerFollowingIDs.remove(profile.id)
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerID,
            target: profile.id,
            isFollowing: false
        )

        // Keep Following list in sync when unfollowing from that screen.
        if kind == .following, listOwnerID == viewerID {
            applyListItemsMutation {
                items.removeAll { $0.id == profile.id }
                seedListCache(items)
            }
        }
        ExperienceHaptics.play(.selection)

        if profile.id.rawValue.hasPrefix("dev.") {
            return
        }

        do {
            try await profiles.unfollow(from: viewerID, to: profile.id)
            syncViewerFollowingFromCache()
        } catch {
            viewerFollowingIDs = previous
            FollowMutationCoordinator.shared.applyEdgeChange(
                viewer: viewerID,
                target: profile.id,
                isFollowing: true
            )
            if kind == .following, listOwnerID == viewerID, !items.contains(where: { $0.id == profile.id }) {
                applyListItemsMutation {
                    items.insert(profile, at: 0)
                    seedListCache(items)
                }
            }
            syncViewerFollowingFromCache()
            ExperienceHaptics.play(.warning)
        }
    }

    /// Owner removes an incoming follower (delete `followers` row follower→owner).
    private func removeFollower(_ profile: Profile) async {
        guard kind == .followers else {
            FollowListRemoveDiagnostics.guardFailed("kindNotFollowers")
            return
        }
        guard canRemoveIncomingFollowers || isOwnList else {
            FollowListRemoveDiagnostics.guardFailed("notOwnFollowersList")
            removeFollowerErrorMessage = "You can only remove followers from your own list."
            return
        }
        guard !inFlightRemove.contains(profile.id) else {
            FollowListRemoveDiagnostics.guardFailed("removeAlreadyInFlight")
            return
        }

        loadTask?.cancel()
        loadMoreTask?.cancel()
        inFlightRemove.insert(profile.id)
        defer { inFlightRemove.remove(profile.id) }

        removeFollowerErrorMessage = nil
        let previous = items
        let removedID = profile.id
        let countBefore = items.count
        suppressedFollowerIDs.insert(removedID)

        applyListItemsMutation {
            items.removeAll { $0.id == removedID }
            seedListCache(items)
        }
        FollowListRemoveDiagnostics.optimistic(
            beforeCount: countBefore,
            afterCount: items.count,
            followerID: removedID.rawValue
        )
        await deferListCollectionSnapshot()
        FollowMutationCoordinator.shared.applyFollowerRemoved(owner: listOwnerID, follower: removedID)
        ExperienceHaptics.play(.warning)

        if removedID.rawValue.hasPrefix("dev.") {
            FollowListRemoveDiagnostics.apiSucceeded(followerID: removedID.rawValue)
            return
        }

        FollowListRemoveDiagnostics.apiStarted(followerID: removedID.rawValue, ownerID: listOwnerID.rawValue)
        do {
            try await profiles.removeFollower(removedID, from: listOwnerID)
            FollowListRemoveDiagnostics.apiSucceeded(followerID: removedID.rawValue)
        } catch {
            let message = ProfileSectionSupport.message(for: error)
            FollowListRemoveDiagnostics.apiFailed(followerID: removedID.rawValue, message: message)
            suppressedFollowerIDs.remove(removedID)
            applyListItemsMutation {
                items = previous
                seedListCache(previous)
            }
            FollowListRemoveDiagnostics.rollback(followerID: removedID.rawValue, restoredCount: items.count)
            await deferListCollectionSnapshot()
            FollowMutationCoordinator.shared.applyIncomingFollowAccepted(
                owner: listOwnerID,
                requester: removedID
            )
            removeFollowerErrorMessage = message
            ExperienceHaptics.play(.warning)
        }
    }

    /// Applies a single list snapshot, no implicit row animations that fight UITableView diffs.
    private func applyListItemsMutation(_ mutation: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, mutation)
    }

    /// Lets `UICollectionView` finish applying the prior item count before relationship revision bumps re-render rows.
    private func deferListCollectionSnapshot() async {
        await Task.yield()
    }

    private func filterSuppressedFollowers(_ profiles: [Profile]) -> [Profile] {
        guard !suppressedFollowerIDs.isEmpty else { return profiles }
        return profiles.filter { !suppressedFollowerIDs.contains($0.id) }
    }

    private func applyFixtures() {
        // Fixture owners are local-only, treat the list owner as the viewer when
        // the session has no authenticated user (unit tests / offline screenshots).
        if viewerID == nil {
            viewerID = listOwnerID
        }
        canRemoveIncomingFollowers = kind == .followers && viewerID == listOwnerID
        if listOwnerID == DemoExperienceSupport.profileID {
            switch kind {
            case .followers:
                items = DemoGraph.followers()
            case .following:
                items = DemoGraph.following()
            }
        } else {
            switch kind {
            case .followers:
                items = FollowListFixtures.followers(owner: listOwnerID)
            case .following:
                items = FollowListFixtures.following(owner: listOwnerID)
            }
        }
        seedListCache(items)
        let followingIDs = Set(FollowListFixtures.following(owner: listOwnerID).map(\.id))
        // Viewer following set includes fixture following + overlap (Ada).
        viewerFollowingIDs = followingIDs
        detailCache.seedViewerFollowingIDs(followingIDs)
    }

    private func cachedList() -> [Profile]? {
        switch kind {
        case .followers: return detailCache.followers(for: listOwnerID)
        case .following: return detailCache.following(for: listOwnerID)
        }
    }

    private func seedListCache(_ items: [Profile]) {
        switch kind {
        case .followers: detailCache.seed(followers: items, for: listOwnerID)
        case .following: detailCache.seed(following: items, for: listOwnerID)
        }
    }
}
