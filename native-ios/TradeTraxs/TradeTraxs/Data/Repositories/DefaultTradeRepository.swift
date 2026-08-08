import Foundation

/// Production ``TradeRepository`` backed by Supabase PostgREST / RPC.
nonisolated struct DefaultTradeRepository: TradeRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let session: any SessionProviding

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        session: any SessionProviding
    ) {
        self.supabase = supabase
        self.cache = cache
        self.session = session
    }

    func trade(id: TradeID) async throws -> Trade {
        let dto: TradeDTO.Trade = try await supabase.database.selectOne(
            TradeDTO.Trade.self,
            from: "trades",
            query: [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("id", id.rawValue),
            ]
        )
        return try TradeMapper.mapToDomain(dto)
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        var query = SupabaseQuery.page(page) + [
            SupabaseQuery.select("*"),
            SupabaseQuery.eq("user_id", profileID.rawValue),
        ]
        if let accountID {
            query.append(SupabaseQuery.eq("account_id", accountID.rawValue))
        }
        let rows: [TradeDTO.Trade] = try await supabase.database.select(
            TradeDTO.Trade.self,
            from: "trades",
            query: query
        )
        let items = try rows.map(TradeMapper.mapToDomain)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let body = TradeMapper.insertBody(from: draft, userID: userID)
        let dto: TradeDTO.Trade = try await supabase.database.insert(
            body,
            into: "trades",
            returning: TradeDTO.Trade.self
        )
        return try TradeMapper.mapToDomain(dto)
    }

    func update(_ trade: Trade) async throws -> Trade {
        let body = try TradeMapper.mapToDTO(trade)
        let dto: TradeDTO.Trade = try await supabase.database.update(
            body,
            table: "trades",
            query: [SupabaseQuery.eq("id", trade.id.rawValue)],
            returning: TradeDTO.Trade.self
        )
        return try TradeMapper.mapToDomain(dto)
    }

    func delete(id: TradeID) async throws {
        struct Params: Encodable { var p_trade_id: String }
        let data = try JSONEncoder().encode(Params(p_trade_id: id.rawValue))
        _ = try await supabase.database.rpcData(
            functionName: "delete_own_trade",
            parametersJSON: data
        )
    }

    func images(for tradeID: TradeID) async throws -> [TradeImage] {
        let trade = try await trade(id: tradeID)
        // Screenshot lives on the trade row today (`image_url`).
        _ = trade
        let rows: [TradeDTO.Trade] = try await supabase.database.select(
            TradeDTO.Trade.self,
            from: "trades",
            query: [
                SupabaseQuery.select("id,image_url"),
                SupabaseQuery.eq("id", tradeID.rawValue),
            ]
        )
        guard let url = rows.first?.image_url, !url.isEmpty else { return [] }
        return [
            TradeImage(
                id: TradeImageID(url),
                tradeID: tradeID,
                media: MediaReference(id: url, kind: .image, altText: nil),
                sortOrder: 0
            ),
        ]
    }

    func notes(for tradeID: TradeID) async throws -> [TradeNote] {
        let rows: [TradeDTO.Trade] = try await supabase.database.select(
            TradeDTO.Trade.self,
            from: "trades",
            query: [
                SupabaseQuery.select("id,notes,created_at"),
                SupabaseQuery.eq("id", tradeID.rawValue),
            ]
        )
        guard let note = rows.first?.notes, !note.isEmpty else { return [] }
        let created = ISO8601.date(from: rows.first?.created_at) ?? Date()
        return [
            TradeNote(
                id: TradeNoteID(tradeID.rawValue),
                tradeID: tradeID,
                body: note,
                createdAt: created,
                updatedAt: created
            ),
        ]
    }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        let page = try await trades(
            ownedBy: profileID,
            accountID: nil,
            page: PageRequest(limit: 500)
        )
        let inInterval = page.items.filter {
            $0.entryAt >= interval.start && $0.entryAt <= interval.end
        }
        let wins = inInterval.filter { ($0.realizedPnL?.amount ?? 0) > 0 }.count
        let losses = inInterval.filter { ($0.realizedPnL?.amount ?? 0) < 0 }.count
        let total = inInterval.reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
        let count = inInterval.count
        let average = count > 0 ? total / Decimal(count) : 0
        let winRate = count > 0 ? Decimal(wins) / Decimal(count) : 0
        return TradeStatistics(
            tradeCount: count,
            winCount: wins,
            lossCount: losses,
            totalPnL: Money(amount: total),
            averagePnL: Money(amount: average),
            averageRiskReward: nil,
            winRate: winRate
        )
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        let rows: [TradeDTO.Account] = try await supabase.database.select(
            TradeDTO.Account.self,
            from: "user_accounts",
            query: [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        return try rows.map(TradingAccountMapper.mapToDomain)
    }
}
