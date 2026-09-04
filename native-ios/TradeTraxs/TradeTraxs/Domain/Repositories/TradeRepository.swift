import Foundation

nonisolated protocol TradeRepository: Sendable {
    func trade(id: TradeID) async throws -> Trade
    /// Bounded batch by primary key — PostgREST `id=in.(…)`. Prefer ``SessionTradeEntityStore``.
    func trades(ids: [TradeID]) async throws -> [Trade]
    /// - Parameter publicOnly: When `true`, mirrors web Profile (`is_public = true`).
    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade>
    /// Bounded Calendar fetch — `entry_time` window padded for futures trading days.
    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date,
        limit: Int
    ) async throws -> [Trade]
    /// Owner journal / Trade History — bounded keyset page with server-side filters.
    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade>
    func save(_ draft: TradeDraft) async throws -> Trade
    func update(_ trade: Trade) async throws -> Trade
    /// Web `InputTradeForm` edit path — draft fields + preserve `created_at` / sync public post.
    func update(id: TradeID, draft: TradeDraft, previous: Trade) async throws -> Trade
    func delete(id: TradeID) async throws
    func images(for tradeID: TradeID) async throws -> [TradeImage]
    func notes(for tradeID: TradeID) async throws -> [TradeNote]
    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount]
    /// Web `insertTradingAccount`.
    func createAccount(ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount
    /// Web `updateTradingAccount` (+ denormalized trade name/size sync).
    func updateAccount(id: TradingAccountID, ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount
    /// Soft-hide from pickers — web `setTradingAccountActive` (not delete).
    func setAccountActive(id: TradingAccountID, isActive: Bool) async throws
    /// Web `updateTradingAccountNote`.
    func updateAccountNote(id: TradingAccountID, note: String?) async throws
    /// Dropdown visibility + optional public status label (`accounts` columns).
    func updateAccountInsightsSettings(
        id: TradingAccountID,
        ownerID: ProfileID,
        showInAccountDropdowns: Bool,
        customPublicStatus: String?
    ) async throws -> TradingAccount
    func payoutEntries(for accountID: TradingAccountID) async throws -> [AccountPayoutEntry]
    func createPayoutEntry(
        ownerID: ProfileID,
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft
    ) async throws -> AccountPayoutEntry
    func updatePayoutEntry(
        id: AccountPayoutEntryID,
        draft: AccountPayoutEntryDraft
    ) async throws -> AccountPayoutEntry
    func deletePayoutEntry(id: AccountPayoutEntryID) async throws
    /// Whitelisted public profile account cards — `rpc_v1_profile_account_insights`.
    func profileAccountInsights(for profileID: ProfileID) async throws -> [ProfileAccountInsight]
    /// Web `insertCsvTradesWithAccount` — one bulk `trades` insert (not per-row).
    func importCSVTrades(
        _ drafts: [TradeDraft],
        isInitialImport: Bool
    ) async throws -> Int
}

extension TradeRepository {
    /// Default: sequential singles (tests / incomplete backends). Production overrides with `in.()`.
    func trades(ids: [TradeID]) async throws -> [Trade] {
        var result: [Trade] = []
        result.reserveCapacity(ids.count)
        for id in Set(ids) {
            if let trade = try? await trade(id: id) {
                result.append(trade)
            }
        }
        return result
    }

    /// Default for stubs — synthesize domain trade then call ``update(_:)``.
    func update(id: TradeID, draft: TradeDraft, previous: Trade) async throws -> Trade {
        var trade = previous
        trade.id = id
        trade.accountID = draft.accountID
        trade.symbol = draft.symbol
        trade.side = draft.side
        trade.mode = draft.mode
        trade.quantity = draft.quantity
        trade.entryPrice = draft.entryPrice
        trade.exitPrice = draft.exitPrice
        trade.entryAt = draft.entryAt
        trade.exitAt = draft.exitAt
        trade.realizedPnL = draft.realizedPnL
        trade.riskReward = draft.riskReward
        trade.points = draft.points
        trade.sessionLabel = draft.sessionLabel
        trade.strategy = draft.strategy
        trade.visibility = draft.visibility
        trade.publicCaption = draft.publicCaption
        trade.thumbnail = draft.imageURL.map { MediaReference(id: $0, kind: .image, altText: nil) }
        trade.notePreview = draft.noteBody.map { String($0.prefix(140)) }
        trade.notes = draft.noteBody
        trade.timeframe = draft.timeframe
        trade.newsEvent = draft.newsEvent
        trade.confidence = draft.confidence
        trade.emotion = draft.emotion
        trade.followedPlan = draft.followedPlan
        trade.marketCondition = draft.marketCondition
        trade.psychologyNotes = draft.psychologyNotes
        trade.durationText = draft.durationText
        trade.durationSeconds = draft.durationSeconds
        trade.imageDisplayMode = draft.imageDisplayMode
        trade.updatedAt = Date()
        return try await update(trade)
    }

    func createAccount(ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        throw AppError.notImplemented(feature: "createAccount")
    }

    func updateAccount(id: TradingAccountID, ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        throw AppError.notImplemented(feature: "updateAccount")
    }

    func setAccountActive(id: TradingAccountID, isActive: Bool) async throws {
        throw AppError.notImplemented(feature: "setAccountActive")
    }

    func updateAccountNote(id: TradingAccountID, note: String?) async throws {
        throw AppError.notImplemented(feature: "updateAccountNote")
    }

    func updateAccountInsightsSettings(
        id: TradingAccountID,
        ownerID: ProfileID,
        showInAccountDropdowns: Bool,
        customPublicStatus: String?
    ) async throws -> TradingAccount {
        throw AppError.notImplemented(feature: "updateAccountInsightsSettings")
    }

    func payoutEntries(for accountID: TradingAccountID) async throws -> [AccountPayoutEntry] {
        throw AppError.notImplemented(feature: "payoutEntries")
    }

    func createPayoutEntry(
        ownerID: ProfileID,
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft
    ) async throws -> AccountPayoutEntry {
        throw AppError.notImplemented(feature: "createPayoutEntry")
    }

    func updatePayoutEntry(
        id: AccountPayoutEntryID,
        draft: AccountPayoutEntryDraft
    ) async throws -> AccountPayoutEntry {
        throw AppError.notImplemented(feature: "updatePayoutEntry")
    }

    func deletePayoutEntry(id: AccountPayoutEntryID) async throws {
        throw AppError.notImplemented(feature: "deletePayoutEntry")
    }

    func profileAccountInsights(for profileID: ProfileID) async throws -> [ProfileAccountInsight] {
        throw AppError.notImplemented(feature: "profileAccountInsights")
    }

    func importCSVTrades(
        _ drafts: [TradeDraft],
        isInitialImport: Bool
    ) async throws -> Int {
        throw AppError.notImplemented(feature: "importCSVTrades")
    }
}

extension TradeRepository {
    /// Default: page + client filter (stubs / fallbacks). Production overrides with PostgREST bounds.
    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date,
        limit: Int
    ) async throws -> [Trade] {
        let page = try await trades(
            ownedBy: profileID,
            accountID: accountID,
            page: PageRequest(limit: limit),
            publicOnly: false
        )
        return page.items.filter { trade in
            let instant = trade.entryAt
            return instant >= entryFrom && instant <= entryTo
        }
    }

    /// Default stub path: reuse owner page + local filter (tests / incomplete backends).
    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        let accountID: TradingAccountID? = {
            if case .account(let id) = query.filters.account { return id }
            return nil
        }()
        let publicOnly = query.filters.visibility == .public
        let loaded = try await trades(
            ownedBy: profileID,
            accountID: accountID,
            page: page,
            publicOnly: publicOnly
        )
        let filtered = loaded.items.filter {
            TradeHistoryLocalMatch.matches($0, query: query, context: .init())
        }
        return CursorPage(items: filtered, nextCursor: loaded.nextCursor)
    }
}

/// Client-side matcher used by stubs and as a safety net after server filtering.
nonisolated enum TradeHistoryLocalMatch {
    static func matches(
        _ trade: Trade,
        query: TradeHistoryQuery,
        context: TradeHistoryMatchContext = TradeHistoryMatchContext()
    ) -> Bool {
        let filters = query.filters
        if trade.mode == .backtest { return false }

        if case .account(let id) = filters.account, trade.accountID != id {
            return false
        }

        let bounds = filters.createdAtBounds()
        if let start = bounds.start, trade.createdAt < start { return false }
        if let end = bounds.end, trade.createdAt >= end { return false }

        let pnl = trade.realizedPnL?.amount ?? 0
        switch filters.result {
        case .any: break
        case .wins: if pnl <= 0 { return false }
        case .losses: if pnl >= 0 { return false }
        case .breakeven: if pnl != 0 { return false }
        }
        if let min = filters.pnlMin, pnl < min { return false }
        if let max = filters.pnlMax, pnl > max { return false }

        let rr = trade.riskReward
        if let min = filters.rrMin {
            guard let rr, rr >= min else { return false }
        }
        if let max = filters.rrMax {
            guard let rr, rr <= max else { return false }
        }

        switch filters.direction {
        case .any: break
        case .long: if trade.side != .long { return false }
        case .short: if trade.side != .short { return false }
        }

        if let expectedMode = filters.accountMode.tradingAccountMode {
            guard context.resolvedAccountMode(for: trade) == expectedMode else { return false }
        }

        if !filters.tradingSession.matches(sessionLabel: trade.sessionLabel) {
            return false
        }

        switch filters.visibility {
        case .any: break
        case .public: if trade.visibility != .public { return false }
        case .private: if trade.visibility != .private { return false }
        }

        let search = query.trimmedSearch
        if !search.isEmpty, !matchesSearch(trade, search: search, context: context) {
            return false
        }
        return true
    }

    private static func matchesSearch(
        _ trade: Trade,
        search: String,
        context: TradeHistoryMatchContext
    ) -> Bool {
        let needle = search
        if trade.symbol.ticker.localizedCaseInsensitiveContains(needle) { return true }
        if trade.notePreview?.localizedCaseInsensitiveContains(needle) == true { return true }
        if trade.notes?.localizedCaseInsensitiveContains(needle) == true { return true }
        if trade.strategy?.localizedCaseInsensitiveContains(needle) == true { return true }
        if trade.sessionLabel?.localizedCaseInsensitiveContains(needle) == true { return true }
        if let accountID = trade.accountID,
           context.accountTitle(for: accountID)?.localizedCaseInsensitiveContains(needle) == true
        {
            return true
        }
        return false
    }
}

/// Shared sort helpers for owner-cache seeding and local post-processing.
nonisolated enum TradeHistorySortSupport {
    static func sorted(_ rows: [Trade], sort: TradeHistorySort) -> [Trade] {
        switch sort {
        case .newest:
            return rows.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return rows.sorted { $0.createdAt < $1.createdAt }
        case .highestPnL:
            return rows.sorted {
                ($0.realizedPnL?.amount ?? 0) > ($1.realizedPnL?.amount ?? 0)
            }
        case .lowestPnL:
            return rows.sorted {
                ($0.realizedPnL?.amount ?? 0) < ($1.realizedPnL?.amount ?? 0)
            }
        case .highestRR:
            return rows.sorted {
                ($0.riskReward ?? Decimal(-999_999)) > ($1.riskReward ?? Decimal(-999_999))
            }
        case .lowestRR:
            return rows.sorted {
                ($0.riskReward ?? Decimal(999_999)) < ($1.riskReward ?? Decimal(999_999))
            }
        case .bestWin:
            return rows.sorted { lhs, rhs in
                let leftPnL = lhs.realizedPnL?.amount ?? 0
                let rightPnL = rhs.realizedPnL?.amount ?? 0
                let leftWin = leftPnL > 0
                let rightWin = rightPnL > 0
                if leftWin != rightWin { return leftWin && !rightWin }
                if leftWin && rightWin { return leftPnL > rightPnL }
                return lhs.createdAt > rhs.createdAt
            }
        case .worstLoss:
            return rows.sorted { lhs, rhs in
                let leftPnL = lhs.realizedPnL?.amount ?? 0
                let rightPnL = rhs.realizedPnL?.amount ?? 0
                let leftLoss = leftPnL < 0
                let rightLoss = rightPnL < 0
                if leftLoss != rightLoss { return leftLoss && !rightLoss }
                if leftLoss && rightLoss { return leftPnL < rightPnL }
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    static func cursor(for last: Trade, sort: TradeHistorySort) -> String? {
        switch sort {
        case .newest, .oldest, .bestWin, .worstLoss:
            return ISO8601.string(from: last.createdAt)
        case .highestPnL, .lowestPnL:
            if let pnl = last.realizedPnL?.amount {
                return NSDecimalNumber(decimal: pnl).stringValue
            }
            return ISO8601.string(from: last.createdAt)
        case .highestRR, .lowestRR:
            if let rr = last.riskReward {
                return NSDecimalNumber(decimal: rr).stringValue
            }
            return ISO8601.string(from: last.createdAt)
        }
    }
}
