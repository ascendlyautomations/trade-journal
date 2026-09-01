import Foundation

nonisolated enum ExploreBootstrapApplier {
    struct Applied: Sendable {
        var traders: [ExploreTraderSuggestion]
        var rooms: [ExploreRoomSuggestion]
        var followingIDs: Set<ProfileID>
        var tradersNextCursor: String?
    }

    @MainActor
    static func apply(
        _ bootstrap: ExploreBootstrapV1,
        viewerID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> Applied {
        let profiles = bootstrap.data.traders.compactMap { mapProfile($0) }
        for profile in profiles {
            detailCache.seed(profile)
        }

        var tradeSummaries: [ProfileID: ExploreTraderRanking.TradeSummary] = [:]
        for (rawID, meta) in bootstrap.data.activity_meta {
            let id = ProfileID(rawID)
            tradeSummaries[id] = ExploreTraderRanking.TradeSummary(
                tradeCount: meta.trade_count ?? 0,
                lastTradeAt: meta.last_trade_at.flatMap { ISO8601.date(from: $0) }
            )
        }

        var followerCounts: [ProfileID: Int] = [:]
        for (rawID, counts) in bootstrap.data.social_counts {
            followerCounts[ProfileID(rawID)] = counts.followers
        }

        var exclude: Set<ProfileID> = [viewerID]
        exclude.formUnion(bootstrap.data.following_ids.map { ProfileID($0) })

        let ranked = ExploreTraderRanking.rank(
            profiles: profiles,
            tradeSummaries: tradeSummaries,
            followerCounts: followerCounts,
            excluding: exclude,
            limit: max(16, profiles.count),
            minScore: 1
        )

        let rooms = bootstrap.data.rooms.map { mapRoom($0) }
        let following = Set(bootstrap.data.following_ids.map { ProfileID($0) })
        detailCache.seedViewerFollowingIDs(following)

        return Applied(
            traders: ranked,
            rooms: rooms,
            followingIDs: following,
            tradersNextCursor: bootstrap.data.traders_next_cursor
        )
    }

    private static func mapProfile(_ wire: ExploreTraderWireV1) -> Profile? {
        let dto = ProfileDTO.Profile(
            id: wire.id,
            username: wire.username,
            name: wire.name,
            bio: wire.bio,
            avatar_url: wire.avatar_url,
            trader_type: wire.trader_type,
            trading_style: wire.trading_style,
            primary_market: wire.primary_market,
            started_trading: wire.started_trading,
            is_private: wire.is_private,
            is_creator: nil,
            is_pro: nil,
            subscription_status: nil,
            created_at: wire.created_at,
            referral_code: nil
        )
        return try? ProfileMapper.mapToDomain(dto)
    }

    private static func mapRoom(_ wire: ExploreRoomWireV1) -> ExploreRoomSuggestion {
        ExploreRoomSuggestion(
            id: RoomID(wire.id),
            name: wire.name ?? "Trade Room",
            slug: wire.slug ?? "",
            description: wire.description,
            memberCount: wire.member_count?.value,
            imageURL: wire.image_url
        )
    }
}
