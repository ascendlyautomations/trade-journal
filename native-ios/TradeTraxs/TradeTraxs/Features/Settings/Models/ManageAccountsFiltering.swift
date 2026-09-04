import Foundation

/// Session-local Manage Accounts filter/sort state — in-memory only.
enum ManageAccountsFiltering {
    enum PropFirmFilter: Hashable {
        case all
        case firm(String)

        var menuTitle: String {
            switch self {
            case .all: return "All Prop Firms"
            case .firm(let name): return name
            }
        }
    }

    enum ModeFilter: Hashable {
        case all
        case mode(TradingAccountMode)

        var menuTitle: String {
            switch self {
            case .all: return "All Types"
            case .mode(let mode): return modeFilterLabel(mode)
            }
        }
    }

    static func modeFilterLabel(_ mode: TradingAccountMode) -> String {
        switch mode {
        case .evaluation: return "Evaluation"
        case .funded: return "Funded"
        case .live: return "Live"
        case .sim: return "Sim"
        case .backtest: return "Backtest"
        }
    }

    enum Sort: Hashable {
        case accountName
        case propFirm
        case accountType

        var menuTitle: String {
            switch self {
            case .accountName: return "Account Name"
            case .propFirm: return "Prop Firm"
            case .accountType: return "Account Type"
            }
        }
    }

    static func availablePropFirms(from accounts: [TradingAccount]) -> [String] {
        let names = accounts.compactMap { TradingAccountDisplay.propFirmName(for: $0) }
        return Array(Set(names)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static func availableModes(from accounts: [TradingAccount]) -> [TradingAccountMode] {
        let modes = Set(accounts.map(\.mode))
        let order: [TradingAccountMode] = [.evaluation, .funded, .live, .sim, .backtest]
        return order.filter { modes.contains($0) }
    }

    static func apply(
        to accounts: [TradingAccount],
        propFirm: PropFirmFilter,
        mode: ModeFilter,
        sort: Sort
    ) -> [TradingAccount] {
        var result = accounts
        if case .firm(let name) = propFirm {
            result = result.filter { TradingAccountDisplay.propFirmName(for: $0) == name }
        }
        if case .mode(let selected) = mode {
            result = result.filter { $0.mode == selected }
        }
        return sorted(result, by: sort)
    }

    static func hasActiveFilters(propFirm: PropFirmFilter, mode: ModeFilter) -> Bool {
        if case .all = propFirm, case .all = mode { return false }
        return true
    }

    private static func sorted(_ accounts: [TradingAccount], by sort: Sort) -> [TradingAccount] {
        switch sort {
        case .accountName:
            return accounts.sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .propFirm:
            return accounts.sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
                let left = TradingAccountDisplay.propFirmName(for: lhs) ?? lhs.name
                let right = TradingAccountDisplay.propFirmName(for: rhs) ?? rhs.name
                let compare = left.localizedCaseInsensitiveCompare(right)
                if compare != .orderedSame { return compare == .orderedAscending }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .accountType:
            return accounts.sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
                let left = modeFilterLabel(lhs.mode)
                let right = modeFilterLabel(rhs.mode)
                let compare = left.localizedCaseInsensitiveCompare(right)
                if compare != .orderedSame { return compare == .orderedAscending }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
