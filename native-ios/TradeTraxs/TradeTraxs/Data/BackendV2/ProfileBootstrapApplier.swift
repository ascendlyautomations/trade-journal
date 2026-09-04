import Foundation

nonisolated enum ProfileBootstrapApplier {
    @MainActor
    static func apply(
        _ bootstrap: ProfileBootstrapV1,
        profileID: ProfileID,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil
    ) throws -> ProfileState {
        guard let header = bootstrap.data.profile else {
            throw BackendV2RPCError.decode("profile missing")
        }

        let viewer = bootstrap.data.viewer
        var state = ProfileState()
        state.profileID = profileID
        state.isOwner = viewer.is_own_profile
        state.isFollowing = viewer.is_following
        state.isRequested = viewer.is_requested
        state.followsYou = viewer.follows_you
        state.canViewTrades = viewer.can_view_trades
        if !viewer.is_own_profile {
            detailCache.setViewerFollows(profileID, isFollowing: viewer.is_following)
        }

        let profile = mapProfile(header, profileID: profileID)
        state.profile = profile
        detailCache.seed(profile)

        let stats = mapStats(bootstrap, profileID: profileID)
        state.stats = stats
        detailCache.seed(stats: stats)

        if let roomWire = bootstrap.data.owned_room {
            let room = TradeRoom(
                id: RoomID(roomWire.id),
                ownerProfileID: profileID,
                name: roomWire.name ?? "Trade Room",
                slug: roomWire.slug ?? "",
                description: nil,
                image: nil,
                memberCount: 0,
                showsOnProfile: roomWire.show_on_profile ?? true,
                createdAt: .now
            )
            state.ownedTradeRoom = room
            detailCache.seedOwnedTradeRoom(room, for: profileID)
        }
        state.didResolveTradeRoom = true

        if let page = bootstrap.data.trades_page {
            let mapped = mapTrades(page.items, ownerID: profileID)
            state.trades = mapped.trades
            state.tradesNextCursor = page.page_meta.has_more ? page.page_meta.next_cursor : nil
            state.didLoadTrades = true
            detailCache.seed(publicTrades: mapped.trades, for: profileID)
            let metadata = mapAccountMetadata(from: page.items)
            state.accountNames = metadata.names
            state.accountModes = metadata.modes
            state.accountSizes = metadata.sizes
            detailCache.seedPublicAccountMetadata(
                names: metadata.names,
                modes: metadata.modes,
                sizes: metadata.sizes,
                for: profileID
            )
            applyAuthoritativeAccountModes(
                from: bootstrap.data.public_account_modes,
                into: &state.accountModes
            )
            detailCache.seed(accountModes: state.accountModes)
            applyTradeEngagement(bootstrap.data.trade_engagement, store: engagementStore)
        }

        let mappedStories = StoryBootstrapMapping.map(bootstrap.data.active_stories ?? [])
        state.activeStories = mappedStories
        for story in mappedStories {
            detailCache.seed(story)
        }
        if state.isOwner, let profileID = state.profileID {
            ViewerActiveStoryStore.shared.sync(viewerID: profileID, stories: mappedStories)
        }

        state.phase = .loaded
        state.didBootstrap = true
        state.errorMessage = nil
        return state
    }

    private static func mapProfile(
        _ header: ProfileBootstrapV1.ProfileHeaderWire,
        profileID: ProfileID
    ) -> Profile {
        Profile(
            id: profileID,
            userID: UserID(header.id),
            username: header.username ?? "",
            displayName: ProfileIdentitySanitizer.sanitizedPublicField(header.name)
                ?? ProfileIdentitySanitizer.sanitizedPublicField(header.username)
                ?? header.username
                ?? "",
            bio: header.bio,
            avatar: header.avatar_url.map {
                MediaReference(id: $0, kind: .image, altText: nil)
            },
            traderType: TraderType.parse(header.trader_type) ?? .futures,
            tradingStyle: header.trading_style,
            primaryMarket: header.primary_market,
            startedTradingAt: ISO8601.date(from: header.started_trading ?? ""),
            isPrivate: header.is_private ?? false,
            isCreator: false,
            createdAt: ISO8601.date(from: header.created_at ?? "") ?? .now
        )
    }

    private static func mapStats(
        _ bootstrap: ProfileBootstrapV1,
        profileID: ProfileID
    ) -> ProfileStats {
        let data = bootstrap.data
        let publicStats = data.public_stats
        let totalTrades = publicStats?.total_trades ?? 0
        let wins = publicStats?.wins ?? 0
        let winRate: Decimal = totalTrades > 0
            ? Decimal(wins) / Decimal(totalTrades)
            : 0

        let postCount: Int = {
            guard let raw = data.section_counts?["profile_posts"] else { return 0 }
            if case .number(let value) = raw { return Int(value) }
            return 0
        }()

        return ProfileStats(
            profileID: profileID,
            followerCount: data.followers_count,
            followingCount: data.following_count,
            postCount: postCount,
            tradeCount: totalTrades,
            publicTradeCount: totalTrades,
            winRate: winRate,
            profitFactor: publicStats?.profit_factor?.decimal,
            netPnL: publicStats?.total_pnl?.decimal,
            averageRR: publicStats?.average_rr?.decimal,
            payoutTotal: publicStats?.payout_total?.decimal,
            expectancy: nil
        )
    }

    private static func mapTrades(
        _ rows: [DashboardTradeWireV1],
        ownerID: ProfileID
    ) -> (trades: [Trade], skipped: Int) {
        var trades: [Trade] = []
        var skipped = 0
        for row in rows {
            let dto = row.asTradeDTO(ownerID: ownerID.rawValue)
            do {
                trades.append(try TradeMapper.mapToDomain(dto))
            } catch {
                skipped += 1
            }
        }
        return (trades, skipped)
    }

    private static func mapAccountMetadata(from rows: [DashboardTradeWireV1]) -> (
        names: [TradingAccountID: String],
        modes: [TradingAccountID: TradingAccountMode],
        sizes: [TradingAccountID: Decimal]
    ) {
        var names: [TradingAccountID: String] = [:]
        var modes: [TradingAccountID: TradingAccountMode] = [:]
        var sizes: [TradingAccountID: Decimal] = [:]
        for row in rows {
            guard let idRaw = row.account_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !idRaw.isEmpty
            else { continue }
            let accountID = TradingAccountID(idRaw)
            if let accountName = row.account_name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !accountName.isEmpty
            {
                names[accountID] = accountName
            }
            if let modeLabel = row.account_type ?? row.mode,
               let parsed = TradingAccountMode.parseWireValue(modeLabel)
            {
                modes[accountID] = parsed
            }
            if let size = row.account_size?.decimal {
                sizes[accountID] = size
            }
        }
        return (names, modes, sizes)
    }

    private static func applyAuthoritativeAccountModes(
        from wire: [String: String]?,
        into modes: inout [TradingAccountID: TradingAccountMode]
    ) {
        guard let wire else { return }
        for (accountID, rawMode) in wire {
            guard let parsed = TradingAccountMode.parseWireValue(rawMode) else { continue }
            modes[TradingAccountID(accountID)] = parsed
        }
    }

    @MainActor
    private static func applyTradeEngagement(
        _ engagement: [String: ProfileBootstrapV1.TradeEngagementWire]?,
        store: EngagementStore?
    ) {
        guard let engagement, let store else { return }
        for (tradeID, wire) in engagement {
            let target = InteractionTarget.trade(TradeID(tradeID))
            store.seed(
                EngagementSnapshot(
                    likeCount: wire.like_count,
                    commentCount: wire.comment_count,
                    viewerHasLiked: wire.liked_by_me
                ),
                for: target
            )
        }
    }
}
