import Foundation
import Observation

/// Single source of truth for Follow / Unfollow in-memory propagation.
///
/// Network mutations stay in ``ProfileRepository``. Every successful (or optimistic)
/// edge change patches DetailPresentationCache, SessionFollowingStore, disk,
/// Explore, Leaderboard, owner stats, and the active Profile header — then bumps
/// ``revision`` so Feed / lists can react without timers or forced full reloads.
@Observable
@MainActor
final class FollowMutationCoordinator {
    static let shared = FollowMutationCoordinator()

    enum Kind: Equatable {
        case followed(viewer: ProfileID, target: ProfileID)
        case unfollowed(viewer: ProfileID, target: ProfileID)
        case followerRemoved(owner: ProfileID, follower: ProfileID)
        case followRequestApproved(owner: ProfileID, requester: ProfileID)
    }

    private(set) var revision: Int = 0
    private(set) var latest: Kind?

    weak var detailCache: DetailPresentationCache?
    weak var currentUserProfile: CurrentUserProfileStore?
    private weak var activeProfileContent: ProfileContentStore?
    private weak var activeProfileScreen: ProfileScreenViewModel?

    private init() {}

    func configure(
        detailCache: DetailPresentationCache,
        currentUserProfile: CurrentUserProfileStore
    ) {
        self.detailCache = detailCache
        self.currentUserProfile = currentUserProfile
    }

    /// Profile screens register so header counts / Follow button stay live.
    func registerActiveProfile(screen: ProfileScreenViewModel) {
        activeProfileScreen = screen
        activeProfileContent = screen.contentStore
    }

    func unregisterActiveProfile(screen: ProfileScreenViewModel) {
        if activeProfileScreen === screen {
            activeProfileScreen = nil
            activeProfileContent = nil
        }
    }

    /// Apply viewer→target edge change across all session caches (idempotent).
    func applyEdgeChange(
        viewer: ProfileID,
        target: ProfileID,
        isFollowing: Bool
    ) {
        guard viewer != target else { return }

        let previous = resolvedIsFollowing(viewer: viewer, target: target)
        let changed = previous != isFollowing

        patchDetailCache(viewer: viewer, target: target, isFollowing: isFollowing, countsChanged: changed)
        patchSessionFollowing(viewer: viewer, target: target, isFollowing: isFollowing)
        patchExplore(target: target, isFollowing: isFollowing, countsChanged: changed)
        patchLeaderboard(target: target, isFollowing: isFollowing, countsChanged: changed)

        if changed {
            let delta = isFollowing ? 1 : -1
            currentUserProfile?.applyFollowingCountDelta(delta)
            if viewer == currentUserProfile?.profile?.id {
                // Owner stats already patched via CurrentUserProfileStore when present.
            }
        }

        syncActiveProfile(target: target, isFollowing: isFollowing)
        syncActiveOwnerFollowingCount(viewer: viewer)

        latest = isFollowing
            ? .followed(viewer: viewer, target: target)
            : .unfollowed(viewer: viewer, target: target)
        SessionNetworkProbe.record(
            .localMutation,
            resource: isFollowing ? "follow.edge.follow" : "follow.edge.unfollow",
            detail: "\(viewer.rawValue)->\(target.rawValue)"
        )
        revision += 1
    }

    /// Owner removed someone from their Followers list (they→me edge deleted).
    func applyFollowerRemoved(owner: ProfileID, follower: ProfileID) {
        if var stats = detailCache?.stats(for: owner) {
            stats.followerCount = max(0, stats.followerCount - 1)
            detailCache?.seed(stats: stats)
        }
        if var followerStats = detailCache?.stats(for: follower) {
            followerStats.followingCount = max(0, followerStats.followingCount - 1)
            detailCache?.seed(stats: followerStats)
        }
        if var list = detailCache?.followers(for: owner) {
            list.removeAll { $0.id == follower }
            detailCache?.seed(followers: list, for: owner)
        }
        if owner == currentUserProfile?.profile?.id {
            currentUserProfile?.applyFollowerCountDelta(-1)
        }
        syncActiveProfileStats(profileID: owner)
        latest = .followerRemoved(owner: owner, follower: follower)
        revision += 1
    }

    /// Incoming follow request approved — requester now follows the authenticated owner.
    func noteIncomingFollowAccepted(requester: ProfileID) {
        guard let owner = currentUserProfile?.profile?.id else { return }
        applyIncomingFollowAccepted(owner: owner, requester: requester)
    }

    /// Incoming follow request approved — requester now follows owner.
    func applyIncomingFollowAccepted(owner: ProfileID, requester: ProfileID) {
        if var stats = detailCache?.stats(for: owner) {
            stats.followerCount = max(0, stats.followerCount + 1)
            detailCache?.seed(stats: stats)
        }
        if var requesterStats = detailCache?.stats(for: requester) {
            requesterStats.followingCount = max(0, requesterStats.followingCount + 1)
            detailCache?.seed(stats: requesterStats)
        }
        if owner == currentUserProfile?.profile?.id {
            currentUserProfile?.applyFollowerCountDelta(1)
        }
        syncActiveProfileStats(profileID: owner)
        latest = .followRequestApproved(owner: owner, requester: requester)
        revision += 1
    }

    /// Shared read for any screen — prefer edge map, then complete following set.
    func isFollowing(viewer: ProfileID, target: ProfileID) -> Bool {
        resolvedIsFollowing(viewer: viewer, target: target)
    }

    func invalidate() {
        latest = nil
        revision = 0
        activeProfileContent = nil
        activeProfileScreen = nil
    }

    // MARK: - Private

    private func resolvedIsFollowing(viewer: ProfileID, target: ProfileID) -> Bool {
        if let edge = detailCache?.viewerFollowEdge(for: target) {
            return edge
        }
        if let set = detailCache?.viewerFollowingIDs() {
            return set.contains(target)
        }
        return ExploreSessionStore.shared.viewerFollowingIDs.contains(target)
            || LeaderboardSessionStore.shared.followingIDs.contains(target)
    }

    private func patchDetailCache(
        viewer: ProfileID,
        target: ProfileID,
        isFollowing: Bool,
        countsChanged: Bool
    ) {
        guard let detailCache else { return }
        detailCache.setViewerFollows(target, isFollowing: isFollowing)

        // Keep a complete following set coherent when it already exists.
        if var ids = detailCache.viewerFollowingIDs() {
            if isFollowing {
                ids.insert(target)
            } else {
                ids.remove(target)
            }
            detailCache.seedViewerFollowingIDs(ids)
        }

        guard countsChanged else { return }

        if var targetStats = detailCache.stats(for: target) {
            targetStats.followerCount = max(
                0,
                targetStats.followerCount + (isFollowing ? 1 : -1)
            )
            detailCache.seed(stats: targetStats)
        }
        if var viewerStats = detailCache.stats(for: viewer) {
            viewerStats.followingCount = max(
                0,
                viewerStats.followingCount + (isFollowing ? 1 : -1)
            )
            detailCache.seed(stats: viewerStats)
        }

        if var followingList = detailCache.following(for: viewer) {
            if isFollowing {
                if !followingList.contains(where: { $0.id == target }),
                   let profile = detailCache.profile(id: target)
                {
                    followingList.insert(profile, at: 0)
                }
            } else {
                followingList.removeAll { $0.id == target }
            }
            detailCache.seed(following: followingList, for: viewer)
        }

        if var followersList = detailCache.followers(for: target) {
            if isFollowing {
                if !followersList.contains(where: { $0.id == viewer }),
                   let profile = detailCache.profile(id: viewer)
                {
                    followersList.insert(profile, at: 0)
                }
            } else {
                followersList.removeAll { $0.id == viewer }
            }
            detailCache.seed(followers: followersList, for: target)
        }
    }

    private func patchSessionFollowing(
        viewer: ProfileID,
        target: ProfileID,
        isFollowing: Bool
    ) {
        Task {
            await SessionFollowingStore.shared.setFollowing(
                viewerID: viewer.rawValue,
                targetID: target.rawValue,
                isFollowing: isFollowing
            )
            if let ids = await SessionFollowingStore.shared.cached(viewerID: viewer.rawValue) {
                SessionDiskCache.saveFollowing(ids: Array(ids), for: viewer)
            }
        }
    }

    private func patchExplore(target: ProfileID, isFollowing: Bool, countsChanged: Bool) {
        ExploreSessionStore.shared.applyFollowEdge(
            target,
            isFollowing: isFollowing,
            adjustFollowerCount: countsChanged
        )
    }

    private func patchLeaderboard(target: ProfileID, isFollowing: Bool, countsChanged: Bool) {
        LeaderboardSessionStore.shared.applyFollowEdge(
            target,
            isFollowing: isFollowing,
            adjustFollowerCount: countsChanged
        )
    }

    private func syncActiveProfile(target: ProfileID, isFollowing: Bool) {
        guard let content = activeProfileContent,
              content.resolvedProfileID == target
        else { return }
        content.applyExternalFollowState(
            isFollowing: isFollowing,
            stats: detailCache?.stats(for: target)
        )
        if let screen = activeProfileScreen {
            screen.applyExternalFollowState(
                isFollowing: isFollowing,
                stats: detailCache?.stats(for: target)
            )
        }
    }

    private func syncActiveOwnerFollowingCount(viewer: ProfileID) {
        guard let content = activeProfileContent,
              content.resolvedProfileID == viewer,
              content.isOwner
        else { return }
        content.applyExternalFollowState(
            isFollowing: content.isFollowing,
            stats: detailCache?.stats(for: viewer)
        )
        activeProfileScreen?.applyExternalFollowState(
            isFollowing: false,
            stats: detailCache?.stats(for: viewer)
        )
    }

    private func syncActiveProfileStats(profileID: ProfileID) {
        guard let content = activeProfileContent,
              content.resolvedProfileID == profileID
        else { return }
        content.applyExternalFollowState(
            isFollowing: content.isFollowing,
            stats: detailCache?.stats(for: profileID)
        )
        activeProfileScreen?.applyExternalFollowState(
            isFollowing: content.isFollowing,
            stats: detailCache?.stats(for: profileID)
        )
    }
}
