import Foundation

/// Copy-trade grouping + public summaries — mirrors web `copyTradePresentation.ts`.
nonisolated enum CopyTradePresentation {
    struct ModeCounts: Equatable, Sendable {
        var live = 0
        var funded = 0
        var eval = 0
        var sim = 0
        var backtest = 0
    }

    static func isCopyTraded(tradeMode: TradeMode) -> Bool {
        tradeMode == .copyTraded
    }

    static func participatingAccountIDs(
        metadata: CopyTradeJournalMetadata,
        rowAccountID: TradingAccountID?
    ) -> [TradingAccountID] {
        var seen = Set<String>()
        var ids: [TradingAccountID] = []

        func append(_ id: TradingAccountID?) {
            guard let id else { return }
            let key = id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            ids.append(id)
        }

        append(metadata.sourceAccountID)
        for id in metadata.copiedAccountIDs { append(id) }
        append(rowAccountID)
        return ids
    }

    /// Union copy linkage across grouped sibling rows (bootstrap rows may omit source on each row).
    static func mergedCopyMetadata(
        from members: [TradeOwnerJournalSummary]
    ) -> CopyTradeJournalMetadata? {
        var source: TradingAccountID?
        var copiedSeen = Set<String>()
        var copied: [TradingAccountID] = []
        var groupID: String?

        func appendCopied(_ id: TradingAccountID) {
            let key = id.rawValue.lowercased()
            guard !copiedSeen.contains(key) else { return }
            copiedSeen.insert(key)
            copied.append(id)
        }

        for member in members {
            guard let metadata = member.copyTrade else { continue }
            if source == nil { source = metadata.sourceAccountID }
            for id in metadata.copiedAccountIDs { appendCopied(id) }
            if groupID == nil, let group = metadata.copyTradingGroupID, !group.isEmpty {
                groupID = group
            }
        }

        var participatingModes: [TradingAccountID: TradingAccountMode] = [:]
        for member in members {
            participatingModes.merge(member.copyTrade?.participatingAccountModesByID ?? [:]) { _, new in new }
        }

        if source == nil, copied.isEmpty, groupID == nil, participatingModes.isEmpty { return nil }
        return CopyTradeJournalMetadata(
            sourceAccountID: source,
            copiedAccountIDs: copied,
            copyTradingGroupID: groupID,
            participatingAccountModesByID: participatingModes
        )
    }

    static func participatingAccountModesByID(
        from members: [TradeOwnerJournalSummary]
    ) -> [TradingAccountID: TradingAccountMode] {
        var out: [TradingAccountID: TradingAccountMode] = [:]
        for member in members {
            guard let map = member.copyTrade?.participatingAccountModesByID else { continue }
            for (id, mode) in map where out[id] == nil {
                out[id] = mode
            }
        }
        return out
    }

    static func parseParticipatingAccountModes(
        _ entries: [(accountID: String, accountMode: String?)]
    ) -> [TradingAccountID: TradingAccountMode] {
        var out: [TradingAccountID: TradingAccountMode] = [:]
        for entry in entries {
            let rawID = entry.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawID.isEmpty else { continue }
            let id = TradingAccountID(rawID)
            guard out[id] == nil,
                  let modeRaw = entry.accountMode?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !modeRaw.isEmpty,
                  let mode = TradingAccountMode.parseWireValue(modeRaw)
            else { continue }
            out[id] = mode
        }
        return out
    }

    /// Authoritative participating set for one grouped copy action.
    static func participatingAccountIDsForCopyGroup(
        _ members: [TradeOwnerJournalSummary]
    ) -> [TradingAccountID] {
        var seen = Set<String>()
        var ids: [TradingAccountID] = []

        func append(_ id: TradingAccountID?) {
            guard let id else { return }
            let key = id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            ids.append(id)
        }

        if let merged = mergedCopyMetadata(from: members) {
            for id in participatingAccountIDs(metadata: merged, rowAccountID: nil) {
                append(id)
            }
        }

        for member in members {
            append(member.accountID)
            if let metadata = member.copyTrade {
                append(metadata.sourceAccountID)
                for id in metadata.copiedAccountIDs { append(id) }
            }
        }

        if ids.isEmpty, members.count > 1 {
            for member in members where isCopyTraded(tradeMode: member.summary.mode) {
                append(member.accountID)
            }
        }

        return ids
    }

    static func matchesParticipatingAccountFilter(
        item: TradeOwnerJournalSummary,
        accountID: TradingAccountID
    ) -> Bool {
        guard isCopyTraded(tradeMode: item.summary.mode) else {
            return item.accountID == accountID
        }
        if let metadata = item.copyTrade {
            let participating = participatingAccountIDs(
                metadata: metadata,
                rowAccountID: item.accountID
            )
            if !participating.isEmpty {
                return participating.contains(accountID)
            }
        }
        return item.accountID == accountID
    }

    static func matchesParticipatingAccountFilter(
        trade: Trade,
        accountID: TradingAccountID
    ) -> Bool {
        guard isCopyTraded(tradeMode: trade.mode) else {
            return trade.accountID == accountID
        }
        if let metadata = trade.copyTrade {
            let participating = participatingAccountIDs(
                metadata: metadata,
                rowAccountID: trade.accountID
            )
            if !participating.isEmpty {
                return participating.contains(accountID)
            }
        }
        return trade.accountID == accountID
    }

    /// Stable key for one copy-trade journal action (sibling rows share this).
    static func batchKey(for item: TradeOwnerJournalSummary) -> String? {
        guard isCopyTraded(tradeMode: item.summary.mode) else { return nil }
        let metadata = item.copyTrade
        return batchKey(
            userID: item.summary.ownerProfileID.rawValue,
            sourceAccountID: metadata?.sourceAccountID?.rawValue,
            copiedAccountIDs: metadata?.copiedAccountIDs.map(\.rawValue) ?? [],
            rowAccountID: item.accountID?.rawValue,
            ticker: item.summary.symbol.ticker,
            entryAt: item.summary.entryAt,
            createdAt: item.summary.createdAt
        )
    }

    static func batchKey(
        userID: String,
        sourceAccountID: String?,
        copiedAccountIDs: [String],
        rowAccountID: String?,
        ticker: String,
        entryAt: Date?,
        createdAt: Date
    ) -> String? {
        let user = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return nil }

        let source = (sourceAccountID ?? rowAccountID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var participating = Set<String>()
        let sourceTrimmed = source
        if !sourceTrimmed.isEmpty { participating.insert(sourceTrimmed) }
        for raw in copiedAccountIDs {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { participating.insert(id) }
        }
        if let row = rowAccountID?.trimmingCharacters(in: .whitespacesAndNewlines), !row.isEmpty {
            participating.insert(row)
        }
        let participatingSorted = participating.sorted().joined(separator: ",")

        let tick = ticker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let entry = ISO8601.string(from: entryAt ?? createdAt)

        let copiedRaw = copiedAccountIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hasAuthoritativeStamp = !source.isEmpty && !copiedRaw.isEmpty
        if hasAuthoritativeStamp {
            return "\(user)|\(source)|\(participatingSorted)|\(tick)|\(entry)"
        }

        let created = String(ISO8601.string(from: createdAt).prefix(19))
        guard !created.isEmpty else { return nil }
        return "\(user)|\(source)|\(participatingSorted)|\(tick)|\(entry)|\(created)"
    }

    /// Owner Trades list line — `Name • Mode • •••1234`.
    static func ownerJournalAccountLine(
        accountID: TradingAccountID,
        member: TradeOwnerJournalSummary?,
        accounts: [TradingAccount]
    ) -> String {
        if let account = accounts.first(where: { $0.id == accountID }) {
            return ownerJournalAccountLine(for: account)
        }
        let name = member?.accountName
        let mode = member?.summary.accountMode ?? .live
        var parts: [String] = []
        let displayName = TradingAccountDisplay.ownerDropdownDisplayName(name)
        if !displayName.isEmpty {
            parts.append(displayName)
        }
        parts.append(TradingAccountDisplay.ownerDropdownModeLabel(mode))
        return parts.joined(separator: TradingAccountDisplay.separator)
    }

    static func ownerJournalAccountLine(for account: TradingAccount) -> String {
        var parts: [String] = []
        let displayName = TradingAccountDisplay.ownerDropdownDisplayName(account.name)
        if !displayName.isEmpty {
            parts.append(displayName)
        }
        parts.append(TradingAccountDisplay.ownerDropdownModeLabel(account.mode))
        if let suffix = TradingAccountDisplay.maskedAccountNumberSuffix(account.accountNumber) {
            parts.append(suffix)
        }
        return parts.joined(separator: TradingAccountDisplay.separator)
    }

    /// Mode count segment only — `1 Live • 2 Funded` (Live → Funded → Eval → Sim → Backtest).
    static func modeCountSegment(from counts: ModeCounts) -> String? {
        var parts: [String] = []
        if counts.live > 0 { parts.append("\(counts.live) Live") }
        if counts.funded > 0 { parts.append("\(counts.funded) Funded") }
        if counts.eval > 0 { parts.append("\(counts.eval) Eval") }
        if counts.sim > 0 { parts.append("\(counts.sim) Sim") }
        if counts.backtest > 0 { parts.append("\(counts.backtest) Backtest") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    /// Public social line — `Copy Traded across 3 accounts • 1 Eval • 2 Funded`.
    static func publicAcrossAccountsSummary(
        participatingAccountCount: Int,
        counts: ModeCounts
    ) -> String? {
        guard participatingAccountCount > 0 else { return nil }
        let noun = participatingAccountCount == 1 ? "account" : "accounts"
        let prefix = "Copy Traded across \(participatingAccountCount) \(noun)"
        guard let modes = modeCountSegment(from: counts) else { return prefix }
        return "\(prefix) • \(modes)"
    }

    static func publicAcrossAccountsSummary(
        participatingAccountIDs: [TradingAccountID],
        accountModes: [TradingAccountMode?]
    ) -> String? {
        guard !participatingAccountIDs.isEmpty,
              participatingAccountIDs.count == accountModes.count
        else { return nil }
        return publicAcrossAccountsSummary(
            participatingAccountCount: participatingAccountIDs.count,
            counts: modeCounts(accountModes: accountModes)
        )
    }

    static func accountLookupKey(_ id: TradingAccountID) -> String {
        id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func accountMode(
        in map: [TradingAccountID: TradingAccountMode],
        for accountID: TradingAccountID
    ) -> TradingAccountMode? {
        if let mode = map[accountID] { return mode }
        let key = accountLookupKey(accountID)
        return map.first { accountLookupKey($0.key) == key }?.value
    }

    static func resolvedPublicAccountMode(
        summary: TradeSummary,
        linkageAccountMode: String? = nil,
        accountModesByID: [TradingAccountID: TradingAccountMode] = [:],
        accountID: TradingAccountID? = nil
    ) -> TradingAccountMode? {
        if let linkageAccountMode,
           let parsed = TradingAccountMode.parseWireValue(linkageAccountMode)
        {
            return parsed
        }
        if let mode = summary.accountMode { return mode }
        if let accountID, let mode = accountMode(in: accountModesByID, for: accountID) { return mode }
        if let badge = summary.publicAccountBadge,
           let parsed = TradingAccountMode.parseWireValue(badge)
        {
            return parsed
        }
        return nil
    }

    static func publicAccountModeForParticipatingAccount(
        accountID: TradingAccountID,
        member: TradeOwnerJournalSummary?,
        accountModesByID: [TradingAccountID: TradingAccountMode] = [:]
    ) -> TradingAccountMode? {
        if let member {
            if let mode = resolvedPublicAccountMode(
                summary: member.summary,
                accountModesByID: accountModesByID,
                accountID: accountID
            ) {
                return mode
            }
        }
        return accountMode(in: accountModesByID, for: accountID)
    }

    /// Per-account mode from sibling journal rows (Profile V2 linkage `account_mode` on each row).
    static func siblingAccountModeByID(
        members: [TradeOwnerJournalSummary],
        accountModesByID: [TradingAccountID: TradingAccountMode] = [:]
    ) -> [String: TradingAccountMode] {
        var map: [String: TradingAccountMode] = [:]
        for member in members {
            guard let accountID = member.accountID else { continue }
            guard let mode = publicAccountModeForParticipatingAccount(
                accountID: accountID,
                member: member,
                accountModesByID: accountModesByID
            ) else { continue }
            map[accountLookupKey(accountID)] = mode
        }
        return map
    }

    static func modeCountsForParticipatingAccounts(
        participatingAccountIDs: [TradingAccountID],
        members: [TradeOwnerJournalSummary],
        accountModesByID: [TradingAccountID: TradingAccountMode] = [:]
    ) -> ModeCounts {
        let memberByAccountKey = Dictionary(
            members.compactMap { item -> (String, TradeOwnerJournalSummary)? in
                guard let accountID = item.accountID else { return nil }
                return (accountLookupKey(accountID), item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let payloadModes = participatingAccountModesByID(from: members)
        let siblingModes = siblingAccountModeByID(
            members: members,
            accountModesByID: accountModesByID
        )
        var seen = Set<String>()
        var modes: [TradingAccountMode?] = []
        for accountID in participatingAccountIDs {
            let key = accountLookupKey(accountID)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let member = memberByAccountKey[key]
            let mode =
                accountMode(in: payloadModes, for: accountID)
                ?? siblingModes[key]
                ?? publicAccountModeForParticipatingAccount(
                    accountID: accountID,
                    member: member,
                    accountModesByID: accountModesByID
                )
            modes.append(mode)
        }
        return modeCounts(accountModes: modes)
    }

    static func modeCountsForCopyGroupMembers(
        _ members: [TradeOwnerJournalSummary],
        accountModesByID: [TradingAccountID: TradingAccountMode] = [:]
    ) -> ModeCounts {
        let participating = participatingAccountIDsForCopyGroup(members)
        guard !participating.isEmpty else { return ModeCounts() }
        return modeCountsForParticipatingAccounts(
            participatingAccountIDs: participating,
            members: members,
            accountModesByID: accountModesByID
        )
    }

    static func publicAcrossAccountsSummary(
        for members: [TradeOwnerJournalSummary],
        accountModesByID: [TradingAccountID: TradingAccountMode] = [:]
    ) -> String? {
        guard let first = members.first,
              isCopyTraded(tradeMode: first.summary.mode)
        else { return nil }

        let participating = participatingAccountIDsForCopyGroup(members)
        guard !participating.isEmpty else { return nil }

        let counts = modeCountsForParticipatingAccounts(
            participatingAccountIDs: participating,
            members: members,
            accountModesByID: accountModesByID
        )
        return publicAcrossAccountsSummary(
            participatingAccountCount: participating.count,
            counts: counts
        )
    }

    /// Legacy feed string — prefer ``publicAcrossAccountsSummary(for:accountModesByID:)``.
    static func publicModeSummary(counts: ModeCounts) -> String? {
        guard let modes = modeCountSegment(from: counts) else { return nil }
        return "Copy Traded on \(modes)"
    }

    /// Mode-count tail of a canonical public copy summary — `2 Funded • 1 Eval`.
    /// Returns nil when the summary has no participating modes.
    static func modeCountSegment(fromPublicSummary summary: String?) -> String? {
        guard let summary else { return nil }
        let line = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        let acrossPrefix = "Copy Traded across "
        if line.hasPrefix(acrossPrefix) {
            guard let separator = line.range(of: " • ") else { return nil }
            let suffix = line[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : suffix
        }

        let onPrefix = "Copy Traded on "
        if line.hasPrefix(onPrefix) {
            let suffix = line.dropFirst(onPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : suffix
        }

        return nil
    }

    static func modeCounts(accountModes: [TradingAccountMode?]) -> ModeCounts {
        var counts = ModeCounts()
        for mode in accountModes {
            switch mode {
            case .live: counts.live += 1
            case .funded: counts.funded += 1
            case .evaluation: counts.eval += 1
            case .sim: counts.sim += 1
            case .backtest: counts.backtest += 1
            case nil: break
            }
        }
        return counts
    }

    /// Modes from loaded profile journal rows (linkage `account_mode` / per-row summary).
    static func accountModesByID(
        from journalItems: [TradeOwnerJournalSummary]
    ) -> [TradingAccountID: TradingAccountMode] {
        var out: [TradingAccountID: TradingAccountMode] = [:]
        for item in journalItems {
            guard let accountID = item.accountID,
                  let mode = resolvedPublicAccountMode(
                      summary: item.summary,
                      accountID: accountID
                  )
            else { continue }
            out[accountID] = mode
        }
        return out
    }

    static func mergedAccountModes(
        journalItems: [TradeOwnerJournalSummary],
        accountModesByID: [TradingAccountID: TradingAccountMode]
    ) -> [TradingAccountID: TradingAccountMode] {
        var merged = accountModesByID
        for (accountID, mode) in Self.accountModesByID(from: journalItems) {
            if merged[accountID] == nil {
                merged[accountID] = mode
            }
        }
        return merged
    }
}
