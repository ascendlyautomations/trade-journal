import Foundation

/// Eval → funded lifecycle (mirrors web `accountLifecycle.ts`).
nonisolated enum TradingAccountLifecyclePolicy {
    static func lifecycleID(for account: TradingAccount) -> TradingAccountID {
        account.accountLifecycleID ?? account.id
    }

    static func countDistinctAccountSlots(_ accounts: [TradingAccount]) -> Int {
        Set(accounts.map { lifecycleID(for: $0).rawValue }).count
    }

    static func isCompletedEvaluation(_ account: TradingAccount) -> Bool {
        account.graduatedToAccountID != nil
    }

    static func isFundedSuccessor(_ account: TradingAccount) -> Bool {
        account.graduatedFromAccountID != nil
    }

    static func canUpgradeToFunded(_ account: TradingAccount) -> Bool {
        guard account.isPropFirmAccount, account.mode == .evaluation else { return false }
        return !isCompletedEvaluation(account)
    }

    enum ManagementRow: Identifiable, Sendable {
        case standalone(TradingAccount)
        case lifecycle(funded: TradingAccount, evaluation: TradingAccount?)

        var id: String {
            switch self {
            case .standalone(let account):
                return account.id.rawValue
            case .lifecycle(let funded, _):
                return funded.id.rawValue
            }
        }
    }

    static func managementRows(from accounts: [TradingAccount]) -> [ManagementRow] {
        let byID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var consumedEval = Set<TradingAccountID>()
        var rows: [ManagementRow] = []

        for account in accounts where account.graduatedFromAccountID != nil {
            let evalID = account.graduatedFromAccountID
            let eval = evalID.flatMap { byID[$0] }
            rows.append(.lifecycle(funded: account, evaluation: eval))
            if let eval { consumedEval.insert(eval.id) }
        }

        for account in accounts {
            if consumedEval.contains(account.id) { continue }
            if isCompletedEvaluation(account) { continue }
            if rows.contains(where: {
                switch $0 {
                case .standalone(let a): return a.id == account.id
                case .lifecycle(let funded, let eval):
                    return funded.id == account.id || eval?.id == account.id
                }
            }) {
                continue
            }
            rows.append(.standalone(account))
        }

        return rows.sorted { lhs, rhs in
            let title: (ManagementRow) -> String = { row in
                switch row {
                case .standalone(let account): return account.name
                case .lifecycle(let funded, _): return funded.name
                }
            }
            return title(lhs).localizedCaseInsensitiveCompare(title(rhs)) == .orderedAscending
        }
    }
}