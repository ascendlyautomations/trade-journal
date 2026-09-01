import Foundation
import OSLog

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
                SupabaseQuery.select(TradeDTO.profileListSelect),
                SupabaseQuery.eq("id", id.rawValue),
            ]
        )
        return try TradeMapper.mapToDomain(dto)
    }

    func trades(ids: [TradeID]) async throws -> [Trade] {
        let unique = Array(Set(ids.map(\.rawValue))).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [] }
        var items: [Trade] = []
        items.reserveCapacity(unique.count)
        for chunk in unique.chunked(into: 80) {
            let rows: [TradeDTO.Trade] = try await supabase.database.select(
                TradeDTO.Trade.self,
                from: "trades",
                query: [
                    SupabaseQuery.select(TradeDTO.profileListSelect),
                    SupabaseQuery.isIn("id", chunk),
                ]
            )
            items.append(contentsOf: Self.mapTradesSkippingFailures(rows))
        }
        return items
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        let key = Self.ownedTradesFlightKey(
            profileID: profileID,
            accountID: accountID,
            page: page,
            publicOnly: publicOnly
        )
        return try await RepositoryRequestFlight.shared.coalesce(
            key: key,
            resource: "trades.owned"
        ) { [supabase] in
            var query = SupabaseQuery.page(page) + [
                SupabaseQuery.select(publicOnly ? TradeDTO.profileListSelect : "*"),
                SupabaseQuery.eq("user_id", profileID.rawValue),
            ]
            if publicOnly {
                // Mirror web Profile: `.eq("is_public", true)`.
                query.append(SupabaseQuery.eq("is_public", "true"))
            }
            if let accountID {
                query.append(SupabaseQuery.eq("account_id", accountID.rawValue))
            }
            let rows: [TradeDTO.Trade] = try await supabase.database.select(
                TradeDTO.Trade.self,
                from: "trades",
                query: query
            )
            // Soft-skip malformed rows — never fail the entire Profile list (web soft-empty).
            let items = Self.mapTradesSkippingFailures(rows)
            return CursorPage(
                items: items,
                nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
            )
        }
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date,
        limit: Int
    ) async throws -> [Trade] {
        var query: [URLQueryItem] = [
            SupabaseQuery.select(TradeDTO.profileListSelect),
            SupabaseQuery.eq("user_id", profileID.rawValue),
            URLQueryItem(name: "entry_time", value: "gte.\(ISO8601.string(from: entryFrom))"),
            URLQueryItem(name: "entry_time", value: "lte.\(ISO8601.string(from: entryTo))"),
            URLQueryItem(name: "order", value: "entry_time.asc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let accountID {
            query.append(SupabaseQuery.eq("account_id", accountID.rawValue))
        }
        let rows: [TradeDTO.Trade] = try await supabase.database.select(
            TradeDTO.Trade.self,
            from: "trades",
            query: query
        )
        return Self.mapTradesSkippingFailures(rows)
    }

    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        let key = Self.tradeHistoryFlightKey(profileID: profileID, query: query, page: page)
        return try await RepositoryRequestFlight.shared.coalesce(
            key: key,
            resource: "trades.history"
        ) { [supabase] in
            try await Self.fetchTradeHistory(
                profileID: profileID,
                query: query,
                page: page,
                supabase: supabase
            )
        }
    }

    private static func fetchTradeHistory(
        profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest,
        supabase: SupabaseInfrastructure
    ) async throws -> CursorPage<Trade> {
        TradeMappingTelemetry.beginLoad("trades.history")
        defer { TradeMappingTelemetry.endLoad() }

        let filters = query.filters
        let (orderColumn, ascending): (String, Bool) = {
            switch filters.sort {
            case .newest: return ("created_at", false)
            case .oldest: return ("created_at", true)
            case .highestPnL: return ("pnl", false)
            case .lowestPnL: return ("pnl", true)
            }
        }()

        var items = SupabaseQuery.page(page, orderColumn: orderColumn, ascending: ascending) + [
            SupabaseQuery.select(TradeDTO.historyListSelect),
            SupabaseQuery.eq("user_id", profileID.rawValue),
            // Web journal excludes backtest from the performance/list pipeline.
            URLQueryItem(name: "mode", value: "neq.backtest"),
        ]

        if case .account(let accountID) = filters.account {
            items.append(SupabaseQuery.eq("account_id", accountID.rawValue))
        }

        switch filters.visibility {
        case .any:
            break
        case .public:
            items.append(SupabaseQuery.eq("is_public", "true"))
        case .private:
            items.append(SupabaseQuery.eq("is_public", "false"))
        }

        let bounds = filters.createdAtBounds()
        if let start = bounds.start {
            items.append(URLQueryItem(name: "created_at", value: "gte.\(ISO8601.string(from: start))"))
        }
        if let end = bounds.end {
            items.append(URLQueryItem(name: "created_at", value: "lt.\(ISO8601.string(from: end))"))
        }

        switch filters.direction {
        case .any:
            break
        case .long:
            // Avoid a second `or=` param (reserved for text search).
            items.append(
                SupabaseQuery.isIn("direction", ["Long", "long", "Buy", "buy", "LONG", "BUY"])
            )
        case .short:
            items.append(
                SupabaseQuery.isIn("direction", ["Short", "short", "Sell", "sell", "SHORT", "SELL"])
            )
        }

        // Result presets + explicit numeric P&L bounds (server-side — not string search).
        switch filters.result {
        case .any:
            break
        case .wins:
            items.append(URLQueryItem(name: "pnl", value: "gt.0"))
        case .losses:
            items.append(URLQueryItem(name: "pnl", value: "lt.0"))
        case .breakeven:
            items.append(URLQueryItem(name: "pnl", value: "eq.0"))
        }
        if let pnlLower = filters.pnlMin {
            items.append(URLQueryItem(name: "pnl", value: "gte.\(Self.pnlQueryValue(pnlLower))"))
        }
        if let pnlUpper = filters.pnlMax {
            items.append(URLQueryItem(name: "pnl", value: "lte.\(Self.pnlQueryValue(pnlUpper))"))
        }

        let search = query.trimmedSearch
        if !search.isEmpty {
            let escaped = Self.escapeILike(search)
            items.append(
                URLQueryItem(
                    name: "or",
                    value: "(ticker.ilike.*\(escaped)*,notes.ilike.*\(escaped)*,account_name.ilike.*\(escaped)*,strategy.ilike.*\(escaped)*)"
                )
            )
        }

        let rows: [TradeDTO.Trade] = try await supabase.database.select(
            TradeDTO.Trade.self,
            from: "trades",
            query: items
        )
        let mapped = Self.mapTradesSkippingFailures(rows)
        let cursor: String? = {
            guard rows.count >= page.limit, let last = rows.last else { return nil }
            switch filters.sort {
            case .newest, .oldest:
                return last.created_at
            case .highestPnL, .lowestPnL:
                if let pnl = last.pnl?.decimal {
                    return NSDecimalNumber(decimal: pnl).stringValue
                }
                return last.created_at
            }
        }()
        return CursorPage(items: mapped, nextCursor: cursor)
    }

    private static func pnlQueryValue(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func escapeILike(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func importCSVTrades(
        _ drafts: [TradeDraft],
        isInitialImport: Bool
    ) async throws -> Int {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        guard !drafts.isEmpty else { return 0 }
        // Web `insertCsvTradesWithAccount` / `trades.insert(rows)` — one bulk POST.
        let rows: [TradeDTO.InsertBody] = drafts.map { draft in
            var body = TradeMapper.insertBody(from: draft, userID: userID)
            body.is_public = false
            body.is_initial_import = isInitialImport
            return body
        }
        try await supabase.database.insert(rows, into: "trades")
        return rows.count
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
        let trade = try TradeMapper.mapToDomain(dto)

        // Web `saveManualTrade`: public trades also create a `posts` row for the feed.
        if draft.visibility == .public {
            let post = TradeDTO.TradePostInsertBody(
                user_id: userID.rawValue,
                trade_id: trade.id.rawValue,
                image_url: draft.imageURL,
                pnl: draft.realizedPnL.map { NSDecimalNumber(decimal: $0.amount).doubleValue },
                rr: draft.riskReward.map { NSDecimalNumber(decimal: $0).doubleValue },
                caption: draft.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            do {
                try await supabase.database.insert(post, into: "posts")
            } catch {
                // Trade already exists — surface post failure without rolling back the journal row
                // (same soft-failure class as web logging; user still has the trade).
                AppLog.networking.error(
                    "Public trade post insert failed — \(String(describing: error), privacy: .public)"
                )
            }
        }
        return trade
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

    func update(id: TradeID, draft: TradeDraft, previous: Trade) async throws -> Trade {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let body = TradeMapper.updateBody(from: draft, createdAt: previous.createdAt)
        #if DEBUG
        TradeUpdateDiagnostics.logUpdateAttempt(tradeID: id, body: body)
        #endif
        _ = try await supabase.database.update(
            body,
            table: "trades",
            query: [
                SupabaseQuery.select(TradeDTO.profileListSelect),
                SupabaseQuery.eq("id", id.rawValue),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ],
            returning: TradeDTO.Trade.self
        )
        // Authoritative read — same select as Trade Detail / list seeds (PATCH representation can omit columns).
        let trade = try await trade(id: id)
        #if DEBUG
        TradeUpdateDiagnostics.logVerifyPersisted(tradeID: id, draft: draft, persisted: trade)
        #endif

        // Web edit: upsert public feed post, or delete when privatized.
        if draft.visibility == .public {
            struct PostUpsertRow: Decodable { var trade_id: String? }
            let post = TradeDTO.TradePostInsertBody(
                user_id: userID.rawValue,
                trade_id: trade.id.rawValue,
                image_url: draft.imageURL,
                pnl: draft.realizedPnL.map { NSDecimalNumber(decimal: $0.amount).doubleValue },
                rr: draft.riskReward.map { NSDecimalNumber(decimal: $0).doubleValue },
                caption: draft.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            do {
                _ = try await supabase.database.upsert(
                    post,
                    into: "posts",
                    onConflict: "trade_id",
                    returning: PostUpsertRow.self,
                    select: "trade_id"
                )
            } catch {
                AppLog.networking.error(
                    "Public trade post upsert failed — \(String(describing: error), privacy: .public)"
                )
            }
        } else if previous.visibility == .public {
            try? await supabase.database.delete(
                from: "posts",
                query: [SupabaseQuery.eq("trade_id", id.rawValue)]
            )
        }

        return trade
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
            page: PageRequest(limit: 500),
            publicOnly: false
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

    /// Mirror web `ACCOUNTS_SELECT` column order/meanings + owner insight columns + `user_id`.
    private static let accountsSelect =
        "id,account_number,name,account_size,mode,category,is_active,can_add_trades,note,consistency,max_drawdown,daily_drawdown,profit_target,winning_days,winning_day_threshold,show_in_account_dropdowns,custom_public_status,payout_drawdown_behavior,user_id"

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        // Mirror web `loadTradingAccounts` / `ACCOUNTS_SELECT` — `trades.account_id` → `accounts.id`.
        // Do NOT query `user_accounts` (free-plan name registry; different UUIDs).
        // SessionAccountsStore also coalesces; repo flight is a defensive identical-key layer.
        try await RepositoryRequestFlight.shared.coalesce(
            key: "trades.accounts:\(profileID.rawValue)",
            resource: "trades.accounts"
        ) { [supabase] in
            let rows: [TradeDTO.Account] = try await supabase.database.select(
                TradeDTO.Account.self,
                from: "accounts",
                query: [
                    SupabaseQuery.select(Self.accountsSelect),
                    SupabaseQuery.eq("user_id", profileID.rawValue),
                ]
            )
            let mapped = rows.compactMap { dto -> TradingAccount? in
                do {
                    return try TradingAccountMapper.mapToDomain(dto)
                } catch {
                    AppLog.networking.error(
                        "Skipping accounts row — \(String(describing: error), privacy: .public)"
                    )
                    return nil
                }
            }
            TradingAccountOwnerDiagnostics.logLoadSummary(accounts: mapped, source: .restSelect)
            return mapped
        }
    }

    func createAccount(ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        let size = draft.sizeDigits.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !size.isEmpty else {
            throw AppError.unknown(message: "Account Value is required.")
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppError.unknown(message: "Account name is required.")
        }

        // Free-plan create limit is enforced by DB trigger; Pro is unlimited.
        let body = TradingAccountMapper.writeBody(
            ownerID: ownerID,
            draft: draft,
            isActive: true,
            canAddTrades: true
        )
        do {
            let row: TradeDTO.Account = try await supabase.database.insert(
                body,
                into: "accounts",
                returning: TradeDTO.Account.self
            )
            return try TradingAccountMapper.mapToDomain(row)
        } catch {
            throw Self.mapAccountMutationError(error)
        }
    }

    func updateAccount(
        id: TradingAccountID,
        ownerID: ProfileID,
        draft: TradingAccountDraft
    ) async throws -> TradingAccount {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppError.unknown(message: "Account name is required.")
        }
        let body = TradingAccountMapper.writeBody(ownerID: nil, draft: draft)
        do {
            let row: TradeDTO.Account = try await supabase.database.update(
                body,
                table: "accounts",
                query: [
                    SupabaseQuery.eq("id", id.rawValue),
                    SupabaseQuery.eq("user_id", ownerID.rawValue),
                ],
                returning: TradeDTO.Account.self
            )
            let account = try TradingAccountMapper.mapToDomain(row)
            // Web `syncTradesAfterAccountRename` — keep denormalized trade labels in sync.
            struct TradeLabels: Encodable {
                var account_name: String
                var account_size: String?
            }
            _ = try? await supabase.database.update(
                TradeLabels(
                    account_name: account.name,
                    account_size: draft.sizeDigits.isEmpty ? nil : draft.sizeDigits
                ),
                table: "trades",
                query: [SupabaseQuery.eq("account_id", id.rawValue)],
                returning: TradeDTO.Trade.self
            )
            return account
        } catch {
            throw Self.mapAccountMutationError(error)
        }
    }

    func setAccountActive(id: TradingAccountID, isActive: Bool) async throws {
        struct Body: Encodable { var is_active: Bool }
        let _: TradeDTO.Account = try await supabase.database.update(
            Body(is_active: isActive),
            table: "accounts",
            query: [SupabaseQuery.eq("id", id.rawValue)],
            returning: TradeDTO.Account.self
        )
    }

    func updateAccountNote(id: TradingAccountID, note: String?) async throws {
        struct Body: Encodable { var note: String? }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let _: TradeDTO.Account = try await supabase.database.update(
            Body(note: (trimmed?.isEmpty == false) ? trimmed : nil),
            table: "accounts",
            query: [SupabaseQuery.eq("id", id.rawValue)],
            returning: TradeDTO.Account.self
        )
    }

    func updateAccountInsightsSettings(
        id: TradingAccountID,
        ownerID: ProfileID,
        showInAccountDropdowns: Bool,
        customPublicStatus: String?
    ) async throws -> TradingAccount {
        let trimmedStatus = customPublicStatus?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = TradeDTO.AccountSettingsBody(
            show_in_account_dropdowns: showInAccountDropdowns,
            custom_public_status: (trimmedStatus?.isEmpty == false) ? trimmedStatus : nil
        )
        let row: TradeDTO.Account = try await supabase.database.update(
            body,
            table: "accounts",
            query: [
                SupabaseQuery.eq("id", id.rawValue),
                SupabaseQuery.eq("user_id", ownerID.rawValue),
            ],
            returning: TradeDTO.Account.self
        )
        return try TradingAccountMapper.mapToDomain(row)
    }

    func payoutEntries(for accountID: TradingAccountID) async throws -> [AccountPayoutEntry] {
        let rows: [TradeDTO.AccountPayoutEntryRow] = try await supabase.database.select(
            TradeDTO.AccountPayoutEntryRow.self,
            from: "account_payout_entries",
            query: [
                SupabaseQuery.select("id,account_id,user_id,amount,payout_date,note,created_at,updated_at"),
                SupabaseQuery.eq("account_id", accountID.rawValue),
                URLQueryItem(name: "order", value: "payout_date.desc,id.desc"),
            ]
        )
        return rows.compactMap { try? AccountPayoutEntryMapper.mapToDomain($0) }
    }

    func createPayoutEntry(
        ownerID: ProfileID,
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft
    ) async throws -> AccountPayoutEntry {
        let body = try AccountPayoutEntryMapper.writeBody(
            ownerID: ownerID,
            accountID: accountID,
            draft: draft
        )
        let row: TradeDTO.AccountPayoutEntryRow = try await supabase.database.insert(
            body,
            into: "account_payout_entries",
            returning: TradeDTO.AccountPayoutEntryRow.self
        )
        return try AccountPayoutEntryMapper.mapToDomain(row)
    }

    func updatePayoutEntry(
        id: AccountPayoutEntryID,
        draft: AccountPayoutEntryDraft
    ) async throws -> AccountPayoutEntry {
        let body = try AccountPayoutEntryMapper.updateBody(from: draft)
        let row: TradeDTO.AccountPayoutEntryRow = try await supabase.database.update(
            body,
            table: "account_payout_entries",
            query: [SupabaseQuery.eq("id", id.rawValue)],
            returning: TradeDTO.AccountPayoutEntryRow.self
        )
        return try AccountPayoutEntryMapper.mapToDomain(row)
    }

    func deletePayoutEntry(id: AccountPayoutEntryID) async throws {
        try await supabase.database.delete(
            from: "account_payout_entries",
            query: [SupabaseQuery.eq("id", id.rawValue)]
        )
    }

    func profileAccountInsights(for profileID: ProfileID) async throws -> [ProfileAccountInsight] {
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_profile_account_insights",
            parametersJSON: try JSONEncoder().encode(["p_identifier": profileID.rawValue])
        )
        return try ProfileAccountInsightMapper.mapAccounts(from: data)
    }

    private static func mapAccountMutationError(_ error: Error) -> Error {
        let text = String(describing: error)
        if text.contains("23505") || text.localizedCaseInsensitiveContains("duplicate") {
            return AppError.unknown(message: "An account with this name already exists.")
        }
        if text.localizedCaseInsensitiveContains("free plan")
            || text.localizedCaseInsensitiveContains("can_add_trades")
        {
            return AppError.unknown(
                message: "Free plan allows up to \(FreeTierPolicy.maxTradeEntryAccounts) active accounts. Upgrade to Pro for unlimited accounts."
            )
        }
        if let app = error as? AppError { return app }
        return AppError.unknown(message: "Couldn't save account. Check your connection and try again.")
    }

    // MARK: - Request flight keys

    private static func tradeHistoryFlightKey(
        profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) -> String {
        let queryKey = query.cacheKey(profileID: profileID)
        let cursor = page.cursor ?? "-"
        return "trades.history:\(queryKey):limit=\(page.limit):cursor=\(cursor)"
    }

    private static func ownedTradesFlightKey(
        profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) -> String {
        let cursor = page.cursor ?? "-"
        let account = accountID?.rawValue ?? "-"
        return "trades.owned:\(profileID.rawValue):pub=\(publicOnly):acct=\(account):limit=\(page.limit):cursor=\(cursor)"
    }

    // MARK: - Mapping

    private static func mapTradesSkippingFailures(_ rows: [TradeDTO.Trade]) -> [Trade] {
        rows.compactMap { dto in
            do {
                return try TradeMapper.mapToDomain(dto)
            } catch {
                TradeMappingTelemetry.recordSkippedTrade()
                let id = dto.id ?? "unknown"
                AppLog.networking.error(
                    "Skipping trade \(id, privacy: .public) — \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
    }
}
