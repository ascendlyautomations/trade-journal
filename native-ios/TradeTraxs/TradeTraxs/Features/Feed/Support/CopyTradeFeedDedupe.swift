import Foundation

/// Wire linkage for one feed trade post — mirrors web `CopyTradeWireRow`.
nonisolated struct CopyTradeFeedLinkage: Equatable, Sendable {
    var postID: String
    var userID: String
    var accountID: String?
    var sourceAccountID: String?
    var copiedAccountIDs: [String]
    var ticker: String
    var entryTimeRaw: String
    var createdAt: Date
    var accountMode: TradingAccountMode?
    var participatingAccountModesByID: [TradingAccountID: TradingAccountMode] = [:]
}

/// Read-time feed dedupe for copy-trade posts — presentation only.
nonisolated enum CopyTradeFeedDedupe {
    struct Plan: Sendable, Equatable {
        var visiblePostIDs: Set<String>
        var publicModeSummaryByPostID: [String: String]
        var batchKeyByPostID: [String: String]
    }

    static func plan(from rows: [FeedItemV1]) -> Plan {
        var linkages: [CopyTradeFeedLinkage] = []
        linkages.reserveCapacity(rows.count)

        for row in rows {
            guard FeedBootstrapApplier.feedItemKind(row.kind) == .trade,
                  let linkage = parseLinkage(row)
            else { continue }
            linkages.append(linkage)
        }

        var batchMembers: [String: [CopyTradeFeedLinkage]] = [:]
        for linkage in linkages {
            guard let key = batchKey(for: linkage) else { continue }
            batchMembers[key, default: []].append(linkage)
        }

        var visiblePostIDs = Set<String>()
        var publicModeSummaryByPostID: [String: String] = [:]
        var batchKeyByPostID: [String: String] = [:]

        var consumedBatch = Set<String>()
        for row in rows {
            guard FeedBootstrapApplier.feedItemKind(row.kind) == .trade,
                  let linkage = parseLinkage(row),
                  let key = batchKey(for: linkage)
            else {
                visiblePostIDs.insert(row.id)
                continue
            }

            batchKeyByPostID[row.id] = key

            if consumedBatch.contains(key) { continue }
            consumedBatch.insert(key)

            let members = batchMembers[key] ?? [linkage]
            let representative = pickRepresentative(from: members, feedOrder: rows.map(\.id))
            visiblePostIDs.insert(representative.postID)

            if let summary = publicModeSummary(for: members) {
                publicModeSummaryByPostID[representative.postID] = summary
            }
        }

        return Plan(
            visiblePostIDs: visiblePostIDs,
            publicModeSummaryByPostID: publicModeSummaryByPostID,
            batchKeyByPostID: batchKeyByPostID
        )
    }

    static func filterItems(_ items: [FeedItem], plan: Plan) -> [FeedItem] {
        items.filter { item in
            switch item.kind {
            case .trade:
                return plan.visiblePostIDs.contains(item.id)
            default:
                return true
            }
        }
    }

    /// One visible row per copy batch within a single timeline snapshot.
    static func dedupeTimeline(_ entries: [FeedTimelineEntry]) -> [FeedTimelineEntry] {
        var seenBatch = Set<String>()
        var out: [FeedTimelineEntry] = []
        for entry in FeedSupport.sortDescending(entries) {
            if let key = batchKey(for: entry) {
                if seenBatch.contains(key) { continue }
                seenBatch.insert(key)
            }
            out.append(entry)
        }
        return out
    }

    static func mergeTimeline(
        existing: [FeedTimelineEntry],
        incoming: [FeedTimelineEntry]
    ) -> [FeedTimelineEntry] {
        var seenIDs = Set(existing.map(\.id))
        var seenBatch = batchKeys(in: existing)

        var appended: [FeedTimelineEntry] = []
        for entry in incoming {
            if seenIDs.contains(entry.id) { continue }
            if let key = batchKey(for: entry), seenBatch.contains(key) { continue }
            if let key = batchKey(for: entry) {
                seenBatch.insert(key)
            }
            seenIDs.insert(entry.id)
            appended.append(entry)
        }
        return FeedSupport.sortDescending(existing + appended)
    }

    static func batchKeys(in entries: [FeedTimelineEntry]) -> Set<String> {
        Set(entries.compactMap { batchKey(for: $0) })
    }

    static func batchKey(for entry: FeedTimelineEntry) -> String? {
        guard case .trade(_, let summary) = entry else { return nil }
        return summary.copyTradeFeedBatchKey
    }

    static func applyPresentation(to summary: TradeSummary, plan: Plan, postID: String) -> TradeSummary {
        var updated = summary
        if let key = plan.batchKeyByPostID[postID] {
            updated.copyTradeFeedBatchKey = key
        }
        if let line = plan.publicModeSummaryByPostID[postID] {
            updated.copyTradePublicModeSummary = line
        }
        return updated
    }

    // MARK: - Internals

    static func parseLinkage(_ row: FeedItemV1) -> CopyTradeFeedLinkage? {
        let nested = object(row.payload["trades"]) ?? [:]
        let tradeModeRaw = string(nested, keys: ["trade_mode"]) ?? ""
        let executionMode = TradeMapper.mapExecutionMode(
            tradeMode: tradeModeRaw,
            mode: string(nested, keys: ["mode"]),
            accountType: string(nested, keys: ["account_type"])
        )
        guard CopyTradePresentation.isCopyTraded(tradeMode: executionMode) else { return nil }

        let userID = string(nested, keys: ["user_id"]) ?? row.author_id
        let entryRaw =
            string(nested, keys: ["entry_time"])
            ?? string(nested, keys: ["trade_date"])
            ?? row.created_at
        guard let created = ISO8601.date(from: row.created_at) else { return nil }

        let copied = stringArray(nested["copied_account_ids"])
        let accountMode =
            TradingAccountMode.parseWireValue(string(nested, keys: ["account_type"]))
            ?? TradingAccountMode.parseWireValue(string(nested, keys: ["account_mode"]))
            ?? TradingAccountMode.parseWireValue(string(nested, keys: ["mode"]))

        let participatingModes = parseParticipatingAccountModes(nested["participating_account_modes"])

        return CopyTradeFeedLinkage(
            postID: row.id,
            userID: userID,
            accountID: string(nested, keys: ["account_id"]),
            sourceAccountID: string(nested, keys: ["source_account_id"]),
            copiedAccountIDs: copied,
            ticker: string(nested, keys: ["ticker"]) ?? "",
            entryTimeRaw: entryRaw,
            createdAt: created,
            accountMode: accountMode,
            participatingAccountModesByID: participatingModes
        )
    }

    static func parseParticipatingAccountModes(_ value: JSONValue?) -> [TradingAccountID: TradingAccountMode] {
        guard case .array(let items) = value else { return [:] }
        let entries: [(String, String?)] = items.compactMap { element -> (String, String?)? in
            guard case .object(let obj) = element,
                  case .string(let accountID) = obj["account_id"]
            else { return nil }
            let mode: String?
            if case .string(let raw) = obj["account_mode"] {
                mode = raw
            } else {
                mode = nil
            }
            return (accountID, mode)
        }
        return CopyTradePresentation.parseParticipatingAccountModes(entries)
    }

    static func batchKey(for linkage: CopyTradeFeedLinkage) -> String? {
        let entryAt = ISO8601.date(from: linkage.entryTimeRaw) ?? linkage.createdAt
        return CopyTradePresentation.batchKey(
            userID: linkage.userID,
            sourceAccountID: linkage.sourceAccountID,
            copiedAccountIDs: linkage.copiedAccountIDs,
            rowAccountID: linkage.accountID,
            ticker: linkage.ticker,
            entryAt: entryAt,
            createdAt: linkage.createdAt
        )
    }

    private static func pickRepresentative(
        from members: [CopyTradeFeedLinkage],
        feedOrder: [String]
    ) -> CopyTradeFeedLinkage {
        let order = Dictionary(uniqueKeysWithValues: feedOrder.enumerated().map { ($1, $0) })
        let sorted = members.sorted {
            (order[$0.postID] ?? Int.max) < (order[$1.postID] ?? Int.max)
        }
        if let source = sorted.first(where: { member in
            let source = (member.sourceAccountID ?? member.accountID ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let account = (member.accountID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !source.isEmpty && source == account
        }) {
            return source
        }
        return sorted[0]
    }

    private static func publicModeSummary(for members: [CopyTradeFeedLinkage]) -> String? {
        CopyTradePresentation.publicAcrossAccountsSummary(
            for: members.map { $0.ownerJournalMember() }
        )
    }

    private static func string(_ payload: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if case .string(let value) = payload[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func object(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let nested) = value else { return nil }
        return nested
    }

    private static func stringArray(_ value: JSONValue?) -> [String] {
        guard case .array(let items) = value else { return [] }
        return items.compactMap { element -> String? in
            if case .string(let raw) = element {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }
    }
}

nonisolated extension CopyTradeFeedLinkage {
    func ownerJournalMember() -> TradeOwnerJournalSummary {
        let source = sourceAccountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let copied = copiedAccountIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { TradingAccountID($0) }
        let metadata = CopyTradeJournalMetadata(
            sourceAccountID: source.flatMap { $0.isEmpty ? nil : TradingAccountID($0) },
            copiedAccountIDs: copied,
            copyTradingGroupID: nil,
            participatingAccountModesByID: participatingAccountModesByID
        )
        let rowAccountID = accountID.flatMap { raw -> TradingAccountID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : TradingAccountID(trimmed)
        }
        let entryAt = ISO8601.date(from: entryTimeRaw) ?? createdAt
        let summary = TradeSummary(
            id: TradeID(postID),
            ownerProfileID: ProfileID(userID),
            symbol: Symbol(ticker: ticker),
            side: .long,
            realizedPnL: nil,
            riskReward: nil,
            points: nil,
            quantity: 0,
            entryAt: entryAt,
            exitAt: nil,
            createdAt: createdAt,
            visibility: .public,
            publicCaption: nil,
            notePreview: nil,
            thumbnail: nil,
            imageDisplayMode: .fit,
            mode: .copyTraded,
            accountMode: accountMode,
            publicAccountBadge: nil,
            durationSeconds: nil,
            durationText: nil
        )
        return TradeOwnerJournalSummary(
            summary: summary,
            accountID: rowAccountID,
            accountName: nil,
            strategy: nil,
            entryPrice: nil,
            exitPrice: nil,
            sessionLabel: nil,
            copyTrade: metadata
        )
    }
}
