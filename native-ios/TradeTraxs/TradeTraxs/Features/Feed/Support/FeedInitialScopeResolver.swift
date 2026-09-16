import Foundation

/// Chooses the first Feed scope from the viewer's following count (no extra network).
enum FeedInitialScopeResolver {
    static let followingThreshold = 5

    @MainActor
    static func defaultScope(followingCount: Int) -> FeedScope {
        followingCount >= followingThreshold ? .following : .global
    }

    /// Authoritative following count from session bootstrap / profile stats — never fetches the full list.
    @MainActor
    static func authoritativeFollowingCount(
        userID: UserID,
        profileStore: CurrentUserProfileStore?
    ) async -> Int {
        if let count = profileStore?.stats?.followingCount {
            return max(0, count)
        }

        let uid = userID.rawValue
        if let bootstrap = SessionBootstrapStore.shared.last,
           matchesViewer(bootstrap, uid: uid)
        {
            return bootstrap.data.following_ids.count
        }

        if let disk = BackendV2BootstrapDiskCache.loadSession(viewerID: uid),
           matchesViewer(disk.bootstrap, uid: uid)
        {
            return disk.bootstrap.data.following_ids.count
        }

        if let cached = await SessionFollowingStore.shared.cached(viewerID: uid) {
            return cached.count
        }

        return 0
    }

    @MainActor
    static func resolvedInitialScope(
        userID: UserID,
        profileStore: CurrentUserProfileStore?
    ) async -> FeedScope {
        let count = await authoritativeFollowingCount(
            userID: userID,
            profileStore: profileStore
        )
        return defaultScope(followingCount: count)
    }

    private static func matchesViewer(_ bootstrap: SessionBootstrapV1, uid: String) -> Bool {
        let metaViewer = bootstrap.meta.viewer_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        if metaViewer == uid { return true }
        return bootstrap.data.viewer.id == uid
    }
}

extension FeedScope {
    static func defaultForFollowingCount(_ count: Int) -> FeedScope {
        FeedInitialScopeResolver.defaultScope(followingCount: count)
    }
}
