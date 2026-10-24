import Foundation

/// Payout achievement that has not been matched to a withdrawal or cycle yet.
nonisolated struct UnmatchedPayoutAchievement: Sendable {
    var id: String
    var kind: AchievementKind
    var title: String
    var amount: Decimal
    var achievedAt: Date
    var accountID: TradingAccountID?
    var linkedCycleID: String?
    var linkedEntryID: String?
}

/// Unified payout history row — manual ledger + funded prop-firm cycles.
nonisolated struct PayoutHistoryItem: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case liveLedger
        case otherLedger
        case fundedCycle
        case achievementProp
        case achievementLive
    }

    var id: String
    var amount: Decimal
    var date: Date
    var accountID: TradingAccountID
    var ledgerEntryID: AccountPayoutEntryID?
    var source: Source
    var note: String?
    var imageURL: String? = nil

    var isEditable: Bool { ledgerEntryID != nil }
}

nonisolated enum PayoutHistorySupport {
    static func buildHistory(
        accounts: [TradingAccount],
        entriesByAccount: [TradingAccountID: [AccountPayoutEntry]],
        cyclesByAccount: [TradingAccountID: [AccountPayoutCycle]]
    ) -> [PayoutHistoryItem] {
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var items: [PayoutHistoryItem] = []

        for (accountID, entries) in entriesByAccount {
            let account = accountsByID[accountID]
            let source: PayoutHistoryItem.Source = account.map { account in
                PropFirmPayoutPolicy.supportsLiveWithdrawal(for: account) ? .liveLedger : .otherLedger
            } ?? .otherLedger
            for entry in entries {
                items.append(
                    PayoutHistoryItem(
                        id: "ledger:\(entry.id.rawValue)",
                        amount: entry.amount.amount,
                        date: entry.payoutDate,
                        accountID: accountID,
                        ledgerEntryID: entry.id,
                        source: source,
                        note: entry.note,
                        imageURL: entry.imageURL
                    )
                )
            }
        }

        for (accountID, cycles) in cyclesByAccount {
            let completed = PropFirmPayoutCycleSupport.selectCompletedPayoutHistory(cycles)
            for cycle in completed {
                guard let amount = cycle.payoutAmount, amount > 0 else { continue }
                let date = cycle.endedAt ?? cycle.startedAt
                items.append(
                    PayoutHistoryItem(
                        id: "cycle:\(cycle.id)",
                        amount: amount,
                        date: date,
                        accountID: accountID,
                        ledgerEntryID: nil,
                        source: .fundedCycle,
                        note: cycle.note
                    )
                )
            }
        }

        return items.sorted { $0.date > $1.date }
    }

    /// Payout achievements that never became a withdrawal or payout cycle.
    static func missingAchievementPayouts(
        achievements: [UnmatchedPayoutAchievement],
        recorded: [PayoutHistoryItem]
    ) -> [PayoutHistoryItem] {
        let window: TimeInterval = 14 * 24 * 60 * 60
        let completedCycleIDs = Set(
            recorded
                .filter { $0.source == .fundedCycle }
                .map { $0.id.replacingOccurrences(of: "cycle:", with: "") }
        )
        let ledgerIDs = Set(recorded.compactMap { $0.ledgerEntryID?.rawValue })
        let cent = Decimal(string: "0.01") ?? 0.01

        return achievements.compactMap { achievement in
            guard achievement.amount > 0 else { return nil }
            if let entryID = achievement.linkedEntryID, ledgerIDs.contains(entryID) { return nil }
            if let cycleID = achievement.linkedCycleID, completedCycleIDs.contains(cycleID) { return nil }
            if let accountID = achievement.accountID,
               recorded.contains(where: { item in
                   item.accountID == accountID
                   && abs(item.amount - achievement.amount) < cent
                   && abs(item.date.timeIntervalSince(achievement.achievedAt)) <= window
               }) {
                return nil
            }
            let prop = achievement.kind == .propFirmPayout
            return PayoutHistoryItem(
                id: "achievement:\(achievement.id)",
                amount: achievement.amount,
                date: achievement.achievedAt,
                accountID: achievement.accountID ?? TradingAccountID(""),
                ledgerEntryID: nil,
                source: prop ? .achievementProp : .achievementLive,
                note: achievement.title
            )
        }
    }

    static func loadMissingAchievementPayouts(
        achievements repository: any AchievementRepository,
        profileID: ProfileID,
        recorded: [PayoutHistoryItem]
    ) async -> [PayoutHistoryItem] {
        let page = try? await repository.achievements(
            for: profileID,
            page: PageRequest(limit: 500),
            publicOnly: false
        )
        let links = (try? await repository.withdrawalAchievementLinks(for: profileID)) ?? []
        var linkByID: [AchievementID: WithdrawalAchievementLinkRow] = [:]
        for link in links {
            linkByID[link.achievementID] = link
        }
        let rows: [UnmatchedPayoutAchievement] = (page?.items ?? []).compactMap { achievement in
            guard achievement.kind == .propFirmPayout || achievement.kind == .liveTradingPayout else { return nil }
            guard let amount = achievement.value?.amount, amount > 0 else { return nil }
            let link = linkByID[achievement.id]
            let title = achievement.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return UnmatchedPayoutAchievement(
                id: achievement.id.rawValue,
                kind: achievement.kind,
                title: title.isEmpty ? (achievement.kind == .propFirmPayout ? "Prop Firm Payout" : "Payout") : title,
                amount: amount,
                achievedAt: achievement.achievedAt,
                accountID: achievement.accountID,
                linkedCycleID: link?.payoutCycleID,
                linkedEntryID: link?.ledgerEntryID?.rawValue
            )
        }
        return missingAchievementPayouts(achievements: rows, recorded: recorded)
    }

    static func summary(for items: [PayoutHistoryItem]) -> (total: Decimal, count: Int, average: Decimal?) {
        guard !items.isEmpty else { return (0, 0, nil) }
        let total = items.reduce(Decimal.zero) { $0 + $1.amount }
        let count = items.count
        let average = total / Decimal(count)
        return (total, count, average)
    }

    static func liveWithdrawals(
        from items: [PayoutHistoryItem],
        accountsByID: [TradingAccountID: TradingAccount]
    ) -> [PayoutHistoryItem] {
        items
            .filter { isLiveWithdrawal($0, account: accountsByID[$0.accountID]) }
            .sorted { $0.date > $1.date }
    }

    static func propPayouts(
        from items: [PayoutHistoryItem],
        accountsByID: [TradingAccountID: TradingAccount]
    ) -> [PayoutHistoryItem] {
        items
            .filter { isPropPayout($0, account: accountsByID[$0.accountID]) }
            .sorted { $0.date > $1.date }
    }

    static func isLiveWithdrawal(_ item: PayoutHistoryItem, account: TradingAccount?) -> Bool {
        switch item.source {
        case .fundedCycle:
            return false
        case .liveLedger:
            return true
        case .otherLedger:
            return account?.mode == .live
        case .achievementProp:
            return false
        case .achievementLive:
            return true
        }
    }

    static func isPropPayout(_ item: PayoutHistoryItem, account: TradingAccount?) -> Bool {
        switch item.source {
        case .fundedCycle:
            return true
        case .liveLedger:
            return false
        case .otherLedger:
            // Past prop payouts, including eval accounts, were saved on the ledger.
            return account?.isPropFirmAccount == true
        case .achievementProp:
            return true
        case .achievementLive:
            return false
        }
    }
}
