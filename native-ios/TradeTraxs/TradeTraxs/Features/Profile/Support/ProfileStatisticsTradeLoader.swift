import Foundation

/// Paginates public trade rows for Profile → Stats timeframe filters when server mode payloads
/// are All Time only. Owner profiles reuse ``SessionOwnerTradesStore`` (Dashboard hydration).
enum ProfileStatisticsTradeLoader {
    static func loadPublicTradeInputs(
        profileID: ProfileID,
        trades: any TradeRepository,
        rpc: (any RPCClient)?,
        accountModes: [TradingAccountID: TradingAccountMode],
        session: any SessionProviding,
        detailCache: DetailPresentationCache
    ) async throws -> [ProfileStatisticsMetrics.TradeInput] {
        let isOwnProfile = await isViewingOwnProfile(session: session, profileID: profileID)
        let loadedTrades: [Trade]
        let source: String

        if isOwnProfile {
            loadedTrades = try await loadOwnProfileTrades(
                profileID: profileID,
                repository: trades,
                detailCache: detailCache
            )
            source = "ownerTradesStore"
        } else if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
            loadedTrades = try await loadOtherProfileTrades(
                profileID: profileID,
                rpc: rpc,
                repository: trades
            )
            source = "profileTabJournalOrRepository"
        } else {
            loadedTrades = try await loadPublicTradesFromRepository(
                profileID: profileID,
                repository: trades
            )
            source = "repositoryPublic"
        }

        let publicTrades = loadedTrades.filter {
            DashboardScopeFilterSupport.isProfileStatisticsPublicTrade($0)
        }

        #if DEBUG
        ProfileStatsTrace.tradeInputsHydration(
            subject: profileID.rawValue,
            source: source,
            loaded: publicTrades.count,
            sessionTagged: publicTrades.filter {
                TradingSessionLabel.canonicalLabel(fromStored: $0.sessionLabel) != nil
            }.count
        )
        #endif

        return publicTrades.map {
            ProfileStatisticsMetrics.tradeInput(from: $0, accountModes: accountModes)
        }
    }

    // MARK: - Owner (Dashboard-aligned hydration)

    private static func loadOwnProfileTrades(
        profileID: ProfileID,
        repository: any TradeRepository,
        detailCache: DetailPresentationCache
    ) async throws -> [Trade] {
        try await loadOwnProfileTradesOnMainActor(
            profileID: profileID,
            repository: repository,
            detailCache: detailCache
        )
    }

    @MainActor
    private static func loadOwnProfileTradesOnMainActor(
        profileID: ProfileID,
        repository: any TradeRepository,
        detailCache: DetailPresentationCache
    ) async throws -> [Trade] {
        _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
            for: profileID,
            detailCache: detailCache
        )
        return try await SessionOwnerTradesStore.shared.ensureCompleteAnalyticsSnapshot(
            for: profileID,
            detailCache: detailCache,
            repository: repository
        )
    }

    // MARK: - Other profiles (public journal RPC, no lossy TradeSummary preview)

    private static func loadOtherProfileTrades(
        profileID: ProfileID,
        rpc: any RPCClient,
        repository: any TradeRepository
    ) async throws -> [Trade] {
        var collected: [Trade] = []
        var seen = Set<TradeID>()
        var cursor: String?
        repeat {
            let applied = try await ProfileTabBootstrapLoader.load(
                tab: .trades,
                profileID: profileID,
                rpc: rpc,
                detailCache: nil,
                cursor: cursor
            )
            guard let journal = applied.profileTradeJournalItems, !journal.isEmpty else {
                if collected.isEmpty {
                    return try await loadPublicTradesFromRepository(
                        profileID: profileID,
                        repository: repository
                    )
                }
                let remainder = try await loadPublicTradesFromRepository(
                    profileID: profileID,
                    repository: repository
                )
                for trade in remainder where seen.insert(trade.id).inserted {
                    collected.append(trade)
                }
                return collected
            }
            for item in journal where seen.insert(item.id).inserted {
                collected.append(TradeSummaryMapper.listMatchTrade(from: item))
            }
            cursor = applied.nextCursor
        } while cursor != nil
        return collected
    }

    private static func loadPublicTradesFromRepository(
        profileID: ProfileID,
        repository: any TradeRepository
    ) async throws -> [Trade] {
        var collected: [Trade] = []
        var seen = Set<TradeID>()
        var cursor: String?
        repeat {
            let page = try await repository.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(cursor: cursor, limit: ProfileTabBootstrapLoader.defaultPageSize),
                publicOnly: true
            )
            for trade in page.items where seen.insert(trade.id).inserted {
                collected.append(trade)
            }
            cursor = page.nextCursor
        } while cursor != nil
        return collected
    }

    private static func isViewingOwnProfile(
        session: any SessionProviding,
        profileID: ProfileID
    ) async -> Bool {
        guard let viewerID = await session.currentUserID else { return false }
        return ProfileID(viewerID.rawValue) == profileID
    }
}