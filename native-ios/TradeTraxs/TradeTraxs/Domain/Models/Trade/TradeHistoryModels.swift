import Foundation

/// Owner journal filters — web `/trades` semantics + native numeric P&L bounds.
///
/// Server-applied where possible (account, visibility, date, direction, P&L range,
/// symbol/notes search, sort). Tags/setup are not first-class DB columns on trades.
nonisolated struct TradeHistoryFilters: Hashable, Sendable {
    var account: DashboardAccountFilter = .all
    var dateRange: TradeHistoryDateRange = .allTime
    var customStart: Date?
    var customEnd: Date?
    var result: TradeHistoryResultFilter = .any
    var pnlMin: Decimal?
    var pnlMax: Decimal?
    var direction: TradeHistoryDirectionFilter = .any
    var visibility: TradeHistoryVisibilityFilter = .any
    var sort: TradeHistorySort = .newest

    var hasActiveConstraints: Bool {
        if case .all = account {} else { return true }
        if dateRange != .allTime { return true }
        if result != .any { return true }
        if pnlMin != nil || pnlMax != nil { return true }
        if direction != .any { return true }
        if visibility != .any { return true }
        if sort != .newest { return true }
        return false
    }

    /// Compact chip descriptors for the active filter strip.
    func activeChips(accountTitle: (TradingAccountID) -> String?) -> [TradeHistoryFilterChip] {
        var chips: [TradeHistoryFilterChip] = []
        if case .account(let id) = account {
            chips.append(.init(id: "account", title: accountTitle(id) ?? "Account"))
        }
        if dateRange != .allTime {
            chips.append(.init(id: "date", title: dateRange.title))
        }
        if result != .any {
            chips.append(.init(id: "result", title: result.title))
        }
        if let pnlMin {
            chips.append(.init(id: "pnlMin", title: "P&L ≥ \(Self.chipMoney(pnlMin))"))
        }
        if let pnlMax {
            chips.append(.init(id: "pnlMax", title: "P&L ≤ \(Self.chipMoney(pnlMax))"))
        }
        if direction != .any {
            chips.append(.init(id: "direction", title: direction.title))
        }
        if visibility != .any {
            chips.append(.init(id: "visibility", title: visibility.title))
        }
        if sort != .newest {
            chips.append(.init(id: "sort", title: sort.title))
        }
        return chips
    }

    mutating func clearChip(id: String) {
        switch id {
        case "account": account = .all
        case "date":
            dateRange = .allTime
            customStart = nil
            customEnd = nil
        case "result": result = .any
        case "pnlMin": pnlMin = nil
        case "pnlMax": pnlMax = nil
        case "direction": direction = .any
        case "visibility": visibility = .any
        case "sort": sort = .newest
        default: break
        }
    }

    mutating func reset() {
        self = TradeHistoryFilters()
    }

    /// Resolved created_at window for server/client filtering (web journal uses created_at).
    func createdAtBounds(now: Date = Date(), calendar: Calendar = .current) -> (start: Date?, end: Date?) {
        switch dateRange {
        case .allTime:
            return (nil, nil)
        case .today:
            let start = calendar.startOfDay(for: now)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return (start, nil) }
            return (start, end)
        case .thisWeek:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
            return (start, nil)
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: comps)
            return (start, nil)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)
            return (start, nil)
        case .custom:
            let start = customStart.map { calendar.startOfDay(for: $0) }
            let endExclusive: Date? = {
                guard let customEnd else { return nil }
                return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd))
            }()
            return (start, endExclusive)
        }
    }

    private static func chipMoney(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(value)"
    }
}

nonisolated struct TradeHistoryFilterChip: Hashable, Identifiable, Sendable {
    var id: String
    var title: String
}

nonisolated enum TradeHistoryDateRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allTime
    case today
    case thisWeek
    case thisMonth
    case last30Days
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime: return "All Time"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .last30Days: return "Last 30 Days"
        case .custom: return "Custom"
        }
    }
}

nonisolated enum TradeHistoryResultFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case any
    case wins
    case losses
    case breakeven

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .wins: return "Wins"
        case .losses: return "Losses"
        case .breakeven: return "Breakeven"
        }
    }
}

nonisolated enum TradeHistoryDirectionFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case any
    case long
    case short

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .long: return "Long"
        case .short: return "Short"
        }
    }
}

/// Visibility filter — `trades.is_public` (web journal Public toggle).
nonisolated enum TradeHistoryVisibilityFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case any
    case `public`
    case `private`

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .public: return "Public"
        case .private: return "Private"
        }
    }
}

nonisolated enum TradeHistorySort: String, CaseIterable, Identifiable, Hashable, Sendable {
    case newest
    case oldest
    case highestPnL
    case lowestPnL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .highestPnL: return "Highest P&L"
        case .lowestPnL: return "Lowest P&L"
        }
    }
}

/// Bounded history request — never unbounded full-history download.
nonisolated struct TradeHistoryQuery: Hashable, Sendable {
    var filters: TradeHistoryFilters
    /// Free-text search over ticker / notes / account_name (ilike). Not used for P&L.
    var searchText: String

    init(filters: TradeHistoryFilters = TradeHistoryFilters(), searchText: String = "") {
        self.filters = filters
        self.searchText = searchText
    }

    var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct TradeHistorySummary: Hashable, Sendable {
    var tradeCount: Int
    var netPnL: Decimal
    var winRate: Decimal?

    static func from(trades: [Trade]) -> TradeHistorySummary {
        let count = trades.count
        let net = trades.reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
        let wins = trades.filter { ($0.realizedPnL?.amount ?? 0) > 0 }.count
        let winRate: Decimal? = count > 0
            ? (Decimal(wins) / Decimal(count)) * 100
            : nil
        return TradeHistorySummary(tradeCount: count, netPnL: net, winRate: winRate)
    }
}
