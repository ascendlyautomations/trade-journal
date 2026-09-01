import Foundation

/// Maps `SessionBootstrapV1` into native domain + session stores.
nonisolated enum SessionBootstrapApplier {
    struct Applied: Sendable {
        var profile: Profile
        var stats: ProfileStats
        var onboardingSnapshot: ProfileOnboardingSnapshot
    }

    @MainActor
    static func apply(
        _ bootstrap: SessionBootstrapV1,
        expectedViewerID: String,
        detailCache: DetailPresentationCache?
    ) async throws -> Applied {
        let viewer = bootstrap.meta.viewer_id ?? bootstrap.data.viewer.id
        guard viewer == expectedViewerID else {
            throw BackendV2RPCError.decode("viewer_id mismatch")
        }
        try bootstrap.validateContractVersion()

        let profile = mapProfile(bootstrap, viewerID: expectedViewerID)
        let stats = mapStats(bootstrap, profileID: profile.id)
        let onboardingSnapshot = ProfileOnboardingSnapshot.from(
            session: bootstrap.data.session_profile,
            viewerID: expectedViewerID
        )

        detailCache?.seed(profile)
        // Session RPC does not include overview stats — fetch via REST in SessionBootstrapLoader.

        let following = Set(bootstrap.data.following_ids)
        await SessionFollowingStore.shared.seed(viewerID: expectedViewerID, ids: following)

        // Session RPC `accounts_summary` is picker metadata only (id/name/mode/is_active).
        // Never seed it into SessionAccountsStore — Manage Accounts needs full ACCOUNTS_SELECT rows.

        SessionBootstrapStore.shared.seed(bootstrap, source: "rpc")

        return Applied(profile: profile, stats: stats, onboardingSnapshot: onboardingSnapshot)
    }

    private static func mapProfile(_ bootstrap: SessionBootstrapV1, viewerID: String) -> Profile {
        let card = bootstrap.data.viewer
        let session = bootstrap.data.session_profile
        let avatarRef = card.avatar_url.flatMap { raw -> MediaReference? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : MediaReference(id: trimmed, kind: .image, altText: nil)
        }
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
            createdAt: Date()
        )
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
