import Foundation
import Observation

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

    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator

    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var viewerID: ProfileID?
    private var inFlightFollow: Set<ProfileID> = []

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

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        loadTask = Task { await performLoad(forceNetwork: false) }
    }

    func refresh() async {
        loadTask?.cancel()
        isRefreshing = true
        await performLoad(forceNetwork: true)
        isRefreshing = false
    }

    func openProfile(_ profile: Profile) {
        ExperienceHaptics.play(.selection)
        if profile.id == viewerID {
            navigationCoordinator.open(.tab(.profile))
            navigationCoordinator.open(.popToRoot(.profile))
            return
        }
        navigationCoordinator.open(.profile(.otherProfile(profile.id)))
    }

    func isFollowing(_ profile: Profile) -> Bool {
        viewerFollowingIDs.contains(profile.id)
    }

    func toggleFollow(for profile: Profile) {
        guard profile.id != viewerID else { return }
        if isFollowing(profile) {
            pendingUnfollow = profile
            return
        }
        Task { await follow(profile) }
    }

    func confirmUnfollow() async {
        guard let profile = pendingUnfollow else { return }
        pendingUnfollow = nil
        await unfollow(profile)
    }

    func requestRemove(_ profile: Profile) {
        guard kind == .followers, isOwnList else { return }
        pendingRemove = profile
    }

    func confirmRemove() async {
        guard let profile = pendingRemove else { return }
        pendingRemove = nil
        await removeFollower(profile)
    }

    // MARK: - Private

    private func performLoad(forceNetwork: Bool) async {
        let userID = await session.currentUserID
        viewerID = userID.map { ProfileID($0.rawValue) }

        if !forceNetwork, let cached = cachedList() {
            items = cached
            viewerFollowingIDs = detailCache.viewerFollowingIDs() ?? []
            hasLoaded = true
            phase = .loaded
            if detailCache.viewerFollowingIDs() == nil {
                await loadViewerFollowing(forceNetwork: false)
            }
            loadTask = nil
            return
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
            switch kind {
            case .followers:
                page = try await profiles.followers(
                    of: listOwnerID,
                    page: PageRequest(limit: 500)
                )
            case .following:
                page = try await profiles.following(
                    of: listOwnerID,
                    page: PageRequest(limit: 500)
                )
            }
            guard !Task.isCancelled else { return }
            items = page.items
            seedListCache(page.items)
            hasLoaded = true
            phase = .loaded
            await loadViewerFollowing(forceNetwork: forceNetwork)
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func loadViewerFollowing(forceNetwork: Bool) async {
        guard let viewerID else { return }
        if !forceNetwork, let cached = detailCache.viewerFollowingIDs() {
            viewerFollowingIDs = cached
            return
        }
        if !forceNetwork, let cachedFollowing = detailCache.following(for: viewerID) {
            let ids = Set(cachedFollowing.map(\.id))
            viewerFollowingIDs = ids
            detailCache.seedViewerFollowingIDs(ids)
            return
        }
        if ProfileSectionSupport.isLocalDevelopmentProfile(viewerID)
            || ProfileSectionSupport.isLocalDevelopmentProfile(listOwnerID)
        {
            let ids = Set(FollowListFixtures.following(owner: viewerID).map(\.id))
            viewerFollowingIDs = ids
            detailCache.seedViewerFollowingIDs(ids)
            return
        }
        do {
            let page = try await profiles.following(of: viewerID, page: PageRequest(limit: 500))
            let ids = Set(page.items.map(\.id))
            viewerFollowingIDs = ids
            detailCache.seedViewerFollowingIDs(ids)
            detailCache.seed(following: page.items, for: viewerID)
        } catch {
            // Soft-fail — buttons default to Follow.
        }
    }

    private func follow(_ profile: Profile) async {
        guard let viewerID, !inFlightFollow.contains(profile.id) else { return }
        inFlightFollow.insert(profile.id)
        defer { inFlightFollow.remove(profile.id) }

        let previous = viewerFollowingIDs
        viewerFollowingIDs.insert(profile.id)
        detailCache.setViewerFollows(profile.id, isFollowing: true)
        ExperienceHaptics.play(.selection)

        if profile.id.rawValue.hasPrefix("dev.") {
            return
        }

        do {
            try await profiles.follow(from: viewerID, to: profile.id)
        } catch {
            viewerFollowingIDs = previous
            detailCache.seedViewerFollowingIDs(previous)
            ExperienceHaptics.play(.warning)
        }
    }

    private func unfollow(_ profile: Profile) async {
        guard let viewerID, !inFlightFollow.contains(profile.id) else { return }
        inFlightFollow.insert(profile.id)
        defer { inFlightFollow.remove(profile.id) }

        let previous = viewerFollowingIDs
        viewerFollowingIDs.remove(profile.id)
        detailCache.setViewerFollows(profile.id, isFollowing: false)

        // Keep Following list in sync when unfollowing from that screen.
        if kind == .following, listOwnerID == viewerID {
            items.removeAll { $0.id == profile.id }
            seedListCache(items)
        }
        ExperienceHaptics.play(.selection)

        if profile.id.rawValue.hasPrefix("dev.") {
            return
        }

        do {
            try await profiles.unfollow(from: viewerID, to: profile.id)
        } catch {
            viewerFollowingIDs = previous
            detailCache.seedViewerFollowingIDs(previous)
            if kind == .following, listOwnerID == viewerID, !items.contains(where: { $0.id == profile.id }) {
                items.insert(profile, at: 0)
                seedListCache(items)
            }
            ExperienceHaptics.play(.warning)
        }
    }

    /// Remove follower = delete edge where they follow me (existing unfollow API inverted).
    private func removeFollower(_ profile: Profile) async {
        guard let viewerID, kind == .followers, isOwnList else { return }

        let previous = items
        items.removeAll { $0.id == profile.id }
        seedListCache(items)
        ExperienceHaptics.play(.warning)

        if profile.id.rawValue.hasPrefix("dev.") {
            return
        }

        do {
            try await profiles.unfollow(from: profile.id, to: viewerID)
        } catch {
            items = previous
            seedListCache(previous)
            ExperienceHaptics.play(.warning)
        }
    }

    private func applyFixtures() {
        switch kind {
        case .followers:
            items = FollowListFixtures.followers(owner: listOwnerID)
        case .following:
            items = FollowListFixtures.following(owner: listOwnerID)
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
