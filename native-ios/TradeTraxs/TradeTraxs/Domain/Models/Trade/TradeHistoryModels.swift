import Foundation

/// Owner journal filters — web `/trades` semantics + native numeric P&L / RR bounds.
///
/// Server-applied where possible (account, visibility, date, direction, P&L range,
/// symbol/notes/setup/session/account search, sort). Account mode and RR also filter
/// locally when served from the owner trade cache.
nonisolated struct TradeHistoryFilters: Hashable, Sendable {
    var account: DashboardAccountFilter = .all
    var dateRange: TradeHistoryDateRange = .allTime
    var customStart: Date?
    var customEnd: Date?
    var result: TradeHistoryResultFilter = .any
    var pnlMin: Decimal?
    var pnlMax: Decimal?
    var rrMin: Decimal?
    var rrMax: Decimal?
    var direction: TradeHistoryDirectionFilter = .any
    var accountMode: TradeHistoryAccountModeFilter = .all
    var tradingSession: TradeHistorySessionFilter = .all
    var visibility: TradeHistoryVisibilityFilter = .any
    var sort: TradeHistorySort = .newest

    /// Any non-default filter or sort selection.
    var hasActiveConstraints: Bool {
        hasActiveFilterConstraints || sort != .newest
    }

    /// Filter chips / empty-state — excludes sort (sort lives in the filter sheet only).
    var hasActiveFilterConstraints: Bool {
        if case .all = account {} else { return true }
        if dateRange != .allTime { return true }
        if result != .any { return true }
        if pnlMin != nil || pnlMax != nil { return true }
        if rrMin != nil || rrMax != nil { return true }
        if direction != .any { return true }
        if accountMode != .all { return true }
        if tradingSession != .all { return true }
        if visibility != .any { return true }
        return false
    }

    /// Compact chip descriptors for the active filter strip (sort excluded).
    func activeChips(accountTitle: (TradingAccountID) -> String?) -> [TradeHistoryFilterChip] {
        var chips: [TradeHistoryFilterChip] = []
        if case .account(let id) = account {
            chips.append(.init(id: "account", title: accountTitle(id) ?? "Account"))
        }
        if dateRange != .allTime {
            chips.append(.init(id: "date", title: dateRange.title))
        }
        if result != .any {
            chips.append(.init(id: "result", title: result.chipTitle))
        }
        if let pnlMin {
            chips.append(.init(id: "pnlMin", title: "P&L ≥ \(Self.chipMoney(pnlMin))"))
        }
        if let pnlMax {
            chips.append(.init(id: "pnlMax", title: "P&L ≤ \(Self.chipMoney(pnlMax))"))
        }
        if let rrMin {
            chips.append(.init(id: "rrMin", title: "RR ≥ \(Self.chipRR(rrMin))"))
        }
        if let rrMax {
            chips.append(.init(id: "rrMax", title: "RR ≤ \(Self.chipRR(rrMax))"))
        }
        if direction != .any {
            chips.append(.init(id: "direction", title: direction.title))
        }
        if accountMode != .all {
            chips.append(.init(id: "accountMode", title: accountMode.title))
        }
        if tradingSession != .all {
            chips.append(.init(id: "tradingSession", title: tradingSession.title))
        }
        if visibility != .any {
            chips.append(.init(id: "visibility", title: visibility.title))
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
        case "rrMin": rrMin = nil
        case "rrMax": rrMax = nil
        case "direction": direction = .any
        case "accountMode": accountMode = .all
        case "tradingSession": tradingSession = .all
        case "visibility": visibility = .any
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

    private static func chipRR(_ value: Decimal) -> String {
        let formatted = NSDecimalNumber(decimal: value).stringValue
        return "\(formatted)R"
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
        case .any: return "All"
        case .wins: return "Winners"
        case .losses: return "Losers"
        case .breakeven: return "Breakeven"
        }
    }

    var chipTitle: String { title }
}

nonisolated enum TradeHistoryDirectionFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case any
    case long
    case short

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "All"
        case .long: return "Long"
        case .short: return "Short"
        }
    }
}

/// Authoritative account mode filter — maps to ``TradingAccountMode`` / denormalized trade mode.
nonisolated enum TradeHistoryAccountModeFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case live
    case funded
    case eval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .live: return "Live"
        case .funded: return "Funded"
        case .eval: return "Eval"
        }
    }

    var tradingAccountMode: TradingAccountMode? {
        switch self {
        case .all: return nil
        case .live: return .live
        case .funded: return .funded
        case .eval: return .evaluation
        }
    }
}

/// Trading session filter — matches authoritative `trades.session` labels.
nonisolated enum TradeHistorySessionFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case ny
    case london
    case asia
    case after

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .ny: return "NY"
        case .london: return "London"
        case .asia: return "Asia"
        case .after: return "After"
        }
    }

    func matches(sessionLabel: String?) -> Bool {
        guard self != .all else { return true }
        let normalized = (sessionLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        switch self {
        case .all: return true
        case .ny: return normalized.localizedCaseInsensitiveCompare("NY") == .orderedSame
        case .london: return normalized.localizedCaseInsensitiveCompare("London") == .orderedSame
        case .asia: return normalized.localizedCaseInsensitiveCompare("Asia") == .orderedSame
        case .after: return normalized.localizedCaseInsensitiveCompare("After") == .orderedSame
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
    case highestRR
    case lowestRR
    case bestWin
    case worstLoss

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .highestPnL: return "Highest P&L"
        case .lowestPnL: return "Lowest P&L"
        case .highestRR: return "Highest RR"
        case .lowestRR: return "Lowest RR"
        case .bestWin: return "Best Win"
        case .worstLoss: return "Worst Loss"
        }
    }
}

/// Optional resolver context for local trade-history matching.
nonisolated struct TradeHistoryMatchContext: Hashable, Sendable {
    var accountTitles: [TradingAccountID: String] = [:]
    var accountModes: [TradingAccountID: TradingAccountMode] = [:]

    func accountTitle(for accountID: TradingAccountID?) -> String? {
        guard let accountID else { return nil }
        return accountTitles[accountID]
    }

    func resolvedAccountMode(for trade: Trade) -> TradingAccountMode? {
        ProfileStatisticsMetrics.resolveAccountMode(trade: trade, accountModes: accountModes)
    }
}

/// Bounded history request — never unbounded full-history download.
nonisolated struct TradeHistoryQuery: Hashable, Sendable {
    var filters: TradeHistoryFilters
    /// Free-text search over ticker / notes / setup / session / account name.
    var searchText: String

    init(filters: TradeHistoryFilters = TradeHistoryFilters(), searchText: String = "") {
        self.filters = filters
        self.searchText = searchText
    }

    var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cacheKey(profileID: ProfileID) -> String {
        var parts: [String] = []
        parts.append(profileID.rawValue)
        parts.append(String(describing: filters.account))
        parts.append(filters.dateRange.rawValue)
        parts.append(String(filters.customStart?.timeIntervalSince1970 ?? 0))
        parts.append(String(filters.customEnd?.timeIntervalSince1970 ?? 0))
        parts.append(filters.result.rawValue)
        parts.append(filters.pnlMin.map(String.init(describing:)) ?? "")
        parts.append(filters.pnlMax.map(String.init(describing:)) ?? "")
        parts.append(filters.rrMin.map(String.init(describing:)) ?? "")
        parts.append(filters.rrMax.map(String.init(describing:)) ?? "")
        parts.append(filters.direction.rawValue)
        parts.append(filters.accountMode.rawValue)
        parts.append(filters.tradingSession.rawValue)
        parts.append(filters.visibility.rawValue)
        parts.append(filters.sort.rawValue)
        parts.append(trimmedSearch.lowercased())
        return parts.joined(separator: "|")
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
