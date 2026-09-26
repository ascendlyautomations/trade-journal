import Foundation

/// Maps `SessionBootstrapV1` into native domain + session stores.
nonisolated enum SessionBootstrapApplier {
    struct Applied: Sendable {
        var profile: Profile
        var stats: ProfileStats
        var onboardingSnapshot: ProfileOnboardingSnapshot
    }

    static func mapApplied(
        _ bootstrap: SessionBootstrapV1,
        expectedViewerID: String
    ) throws -> Applied {
        let viewer = bootstrap.meta.viewer_id ?? bootstrap.data.viewer.id
        guard viewer == expectedViewerID else {
            throw BackendV2RPCError.decode("viewer_id mismatch")
        }
        try bootstrap.validateContractVersion()
        let profile = mapProfile(bootstrap, viewerID: expectedViewerID)
        let stats = mapStats(bootstrap, profileID: profile.id)
        let onboardingSnapshot = ProfileOnboardingSnapshot.from(
            session: bootstrap.data.session_profile,
            viewer: bootstrap.data.viewer,
            viewerID: expectedViewerID
        )
        return Applied(profile: profile, stats: stats, onboardingSnapshot: onboardingSnapshot)
    }

    @MainActor
    static func apply(
        _ bootstrap: SessionBootstrapV1,
        expectedViewerID: String,
        detailCache: DetailPresentationCache?,
        serverAuthoritative: Bool = false
    ) async throws -> Applied {
        var bootstrap = bootstrap
        SessionBootstrapStore.shared.reconcileAdoptedAvatar(
            &bootstrap,
            serverAuthoritative: serverAuthoritative
        )
        let applied = try mapApplied(bootstrap, expectedViewerID: expectedViewerID)
        detailCache?.seed(applied.profile)
        // Session RPC does not include overview stats — fetch via REST in SessionBootstrapLoader.

        let following = Set(bootstrap.data.following_ids.map { ProfileID($0) })
        detailCache?.seedViewerFollowingIDs(following)
        await SessionFollowingStore.shared.seed(viewerID: expectedViewerID, ids: Set(bootstrap.data.following_ids))

        // Session RPC `accounts_summary` is picker metadata only (id/name/mode/is_active).
        // Never seed it into SessionAccountsStore — Manage Accounts needs full ACCOUNTS_SELECT rows.

        SessionBootstrapStore.shared.seed(bootstrap, source: "rpc")

        return applied
    }

    private static func mapProfile(_ bootstrap: SessionBootstrapV1, viewerID: String) -> Profile {
        let card = bootstrap.data.viewer
        let session = bootstrap.data.session_profile
        let avatarRef = SessionBootstrapStore.normalizedAvatarURL(
            session: session.avatar_url,
            viewer: card.avatar_url
        ).map { MediaReference(id: $0, kind: .image, altText: nil) }
        return Profile(
            id: ProfileID(viewerID),
            userID: UserID(viewerID),
            username: card.username ?? session.username ?? viewerID,
            displayName: card.display_name ?? card.username ?? session.username ?? "Trader",
            bio: session.bio,
            avatar: avatarRef,
            traderType: TraderType.parse(session.trader_type),
            tradingStyle: session.trading_style,
            primaryMarket: session.primary_market,
            startedTradingAt: ISO8601.date(from: session.started_trading ?? ""),
            isPrivate: session.is_private ?? card.is_private,
            isCreator: session.creator_access ?? false,
            createdAt: Self.accountCreatedAt(from: session.created_at)
        )
    }

    private static func accountCreatedAt(from raw: String?) -> Date {
        if let parsed = ISO8601.date(from: raw) {
            return parsed
        }
        ContextualTourDebug.log(
            "session_profile.created_at missing or unparsed raw=\(raw ?? "nil"); not using a synthetic now"
        )
        return Date(timeIntervalSince1970: 0)
    }

    private static func mapStats(_ bootstrap: SessionBootstrapV1, profileID: ProfileID) -> ProfileStats {
        ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: bootstrap.data.following_ids.count,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0,
            winRate: nil,
            profitFactor: nil,
            netPnL: nil,
            averageRR: nil,
            payoutTotal: nil,
            expectancy: nil
        )
    }

}
