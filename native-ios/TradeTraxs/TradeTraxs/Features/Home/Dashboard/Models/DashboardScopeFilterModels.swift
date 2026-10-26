import Foundation

/// Client-side dashboard scope — account picker stays separate; these apply to KPIs, charts, insights, psych.
nonisolated struct DashboardClientScopeFilter: Equatable, Sendable {
    var accountFilter: DashboardAccountFilter
    var dateRange: DashboardDateRange
    var customInterval: DateInterval?
    var accountMode: ProfileStatisticsMetrics.Mode
    var showPublicOnly: Bool
    /// Linked trading accounts — Profile Stats uses these before trade denormalization.
    var linkedAccountModes: [TradingAccountID: TradingAccountMode] = [:]

    static let defaultAccountMode: ProfileStatisticsMetrics.Mode = .all

    var usesCustomTimeRange: Bool { customInterval != nil }

    /// Custom date ranges are not in V3 presets — always recompute from trade rows.
    var requiresLocalMetricsRecompute: Bool {
        usesCustomTimeRange || dateRange == .oneYear
    }

    /// Web dashboard filters (account type, public) — client trade rows like `useDashboardAnalytics`.
    var requiresClientTradeScopeOverlay: Bool {
        showPublicOnly || accountMode != Self.defaultAccountMode
    }

    var needsClientScopedTradeMetrics: Bool {
        requiresLocalMetricsRecompute || requiresClientTradeScopeOverlay
    }
}

/// Time period row in the dashboard filter sheet (presets + custom range).
nonisolated enum DashboardTimePeriodPicker: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case sevenDays
    case thirtyDays
    case ninetyDays
    case oneYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Time"
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .ninetyDays: return "90D"
        case .oneYear: return "1Y"
        case .custom: return "Custom Range"
        }
    }

    var dateRange: DashboardDateRange? {
        switch self {
        case .all: return .all
        case .sevenDays: return .sevenDays
        case .thirtyDays: return .thirtyDays
        case .ninetyDays: return .ninetyDays
        case .oneYear: return .oneYear
        case .custom: return nil
        }
    }

    init(dateRange: DashboardDateRange, usesCustomRange: Bool) {
        if usesCustomRange {
            self = .custom
            return
        }
        switch dateRange {
        case .all: self = .all
        case .sevenDays: self = .sevenDays
        case .thirtyDays: self = .thirtyDays
        case .ninetyDays: self = .ninetyDays
        case .oneYear, .ytd: self = .oneYear
        }
    }
}

/// Dashboard visibility filter — mirrors web `showPublicOnly`.
nonisolated enum DashboardTradeVisibilityFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allTrades
    case publicOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTrades: return "All Trades"
        case .publicOnly: return "Public Only"
        }
    }
}

/// Editable filter sheet state — applied on confirm.
nonisolated struct DashboardScopeFilterDraft: Equatable, Sendable {
    var timePeriod: DashboardTimePeriodPicker = .thirtyDays
    var customStart: Date?
    var customEnd: Date?
    var accountType: ProfileStatisticsMetrics.Mode = .all
    var visibility: DashboardTradeVisibilityFilter = .allTrades

    static var defaults: DashboardScopeFilterDraft {
        DashboardScopeFilterDraft(timePeriod: .thirtyDays)
    }
}

nonisolated enum DashboardScopeFilterSupport {
    static let dashboardAccountTypeCases: [ProfileStatisticsMetrics.Mode] = [
        .all, .live, .funded, .eval,
    ]

    static func accountTypeTitle(_ mode: ProfileStatisticsMetrics.Mode) -> String {
        switch mode {
        case .all: return "All"
        case .live: return "Live"
        case .funded: return "Funded"
        case .eval: return "Evaluation"
        case .sim: return "Sim"
        case .backtest: return "Backtest"
        }
    }

    static func normalizedCustomInterval(start: Date, end: Date, calendar: Calendar = .current) -> DateInterval {
        let orderedStart = min(start, end)
        let orderedEnd = max(start, end)
        let dayStart = calendar.startOfDay(for: orderedStart)
        let endDayStart = calendar.startOfDay(for: orderedEnd)
        let dayEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDayStart) ?? orderedEnd
        return DateInterval(start: dayStart, end: dayEnd)
    }

    /// Profile → Stats mode chip — same as ``ProfileStatisticsMetrics/resolveAccountMode`` + ``matchesMode``.
    static func matchesProfileStatisticsAccountModeFilter(
        trade: Trade,
        linkedAccountModes: [TradingAccountID: TradingAccountMode],
        selected: ProfileStatisticsMetrics.Mode
    ) -> Bool {
        let input = ProfileStatisticsMetrics.TradeInput(
            pnl: trade.realizedPnL?.amount,
            createdAt: trade.createdAt,
            isLong: trade.side == .long,
            session: trade.sessionLabel,
            accountMode: ProfileStatisticsMetrics.resolveAccountMode(
                trade: trade,
                accountModes: linkedAccountModes
            ),
            sortKey: trade.id.rawValue
        )
        if selected != .backtest, input.accountMode == .backtest { return false }
        return ProfileStatisticsMetrics.matchesMode(input, selected)
    }

    /// Web dashboard gear — `String(trade.mode ?? trade.account_type ?? "")`.
    static func webDashboardAccountTypeToken(wireMode: String?, wireAccountType: String?) -> String {
        let mode = wireMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !mode.isEmpty { return mode }
        return wireAccountType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    static func webDashboardAccountTypeToken(for trade: Trade) -> String {
        let wire = webDashboardAccountTypeToken(
            wireMode: trade.wireMode,
            wireAccountType: trade.wireAccountType
        )
        if !wire.isEmpty { return wire }
        // Disk cache rows mapped before `wireMode` existed — still denormalized on `accountMode`.
        if let accountMode = trade.accountMode {
            return ProfileStatisticsMetrics.accountTypeString(for: accountMode)
        }
        return ""
    }

    /// Web `resolveDashboardTradeDate` — entry time is the analytics timestamp.
    static func dashboardTradeFilterDate(for trade: Trade) -> Date {
        trade.entryAt
    }

    /// True when filtering `trades` cannot drop rows that belong in `scope`.
    /// Preset windows are covered once the cached page reaches past the window start.
    /// All-time / custom ranges that extend beyond the page need a complete snapshot.
    static func cachedOwnerTradesCoverAnalyticsScope(
        trades: [Trade],
        scope: DashboardClientScopeFilter,
        historyComplete: Bool,
        pageLimit: Int = SessionOwnerTradesStore.analyticsPageLimit
    ) -> Bool {
        if historyComplete { return true }
        if trades.count < pageLimit { return true }
        guard let start = analyticsLowerBound(for: scope) else { return false }
        guard let oldest = trades.map(\.entryAt).min() else { return false }
        return oldest <= start
    }

    /// Inclusive entry-time start for the active dashboard window. Nil means unbounded (all time).
    static func analyticsLowerBound(for scope: DashboardClientScopeFilter, now: Date = Date()) -> Date? {
        if let interval = scope.customInterval {
            return interval.start
        }
        switch scope.dateRange {
        case .all:
            return nil
        case .sevenDays:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .thirtyDays:
            return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .ninetyDays:
            return Calendar.current.date(byAdding: .day, value: -90, to: now)
        case .oneYear:
            return Calendar.current.date(byAdding: .day, value: -365, to: now)
        case .ytd:
            let year = Calendar.current.component(.year, from: now)
            return Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))
        }
    }

    static func webDashboardAccountTypeToken(for input: DashboardChartMetrics.Input) -> String {
        webDashboardAccountTypeToken(for: input.trade)
    }

    static func makeChartInput(
        trade: Trade,
        linkedAccountType: String?
    ) -> DashboardChartMetrics.Input {
        DashboardChartMetrics.Input(
            trade: trade,
            accountType: linkedAccountType
        )
    }

    /// Profile Stats tab — `profileTradeMatchesStatisticsMode` / `analyticsModeEffective`.
    static func profileStatisticsEffectiveMode(for trade: Trade) -> TradingAccountMode? {
        let candidates = [
            trade.wireAccountType,
            trade.wireMode,
        ]
        for raw in candidates {
            guard let parsed = TradingAccountMode.parseWireValue(raw) else { continue }
            return parsed
        }
        return trade.accountMode
    }

    static func matchesWebDashboardAccountTypeFilter(
        input: DashboardChartMetrics.Input,
        selected: ProfileStatisticsMetrics.Mode
    ) -> Bool {
        guard selected != .all else { return true }
        let token = webDashboardAccountTypeToken(for: input)
        guard !token.isEmpty else { return false }
        switch selected {
        case .eval:
            return token == "eval" || token == "evaluation"
        case .funded:
            return token == "funded"
        case .live:
            return token == "live"
        case .sim:
            return token == "sim" || token == "replay"
        case .backtest:
            return token == "backtest"
        case .all:
            return true
        }
    }

    static func matchesProfileStatisticsModeFilter(
        trade: Trade,
        selected: ProfileStatisticsMetrics.Mode
    ) -> Bool {
        let effective = profileStatisticsEffectiveMode(for: trade)
        if effective == .backtest, selected != .backtest { return false }
        return ProfileStatisticsMetrics.matchesMode(
            ProfileStatisticsMetrics.TradeInput(
                pnl: trade.realizedPnL?.amount,
                createdAt: trade.exitAt ?? trade.entryAt,
                isLong: trade.side == .long,
                session: trade.sessionLabel,
                accountMode: effective
            ),
            selected
        )
    }

    /// Profile Stats public universe — `is_public = true` only (not public note alone).
    static func isProfileStatisticsPublicTrade(_ trade: Trade) -> Bool {
        trade.visibility == .public
    }

    /// Web dashboard `tradeIsPublic` — DB flag or non-empty public note.
    static func isWebDashboardPublicTrade(_ trade: Trade) -> Bool {
        if trade.visibility == .public { return true }
        let note = trade.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !note.isEmpty
    }

    static func compactTimeLabel(
        dateRange: DashboardDateRange,
        customInterval: DateInterval?,
        now: Date = Date()
    ) -> String {
        if let customInterval {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "M/d/yy"
            let start = formatter.string(from: customInterval.start)
            let end = formatter.string(from: customInterval.end)
            return "\(start) – \(end)"
        }
        return dateRange.title
    }
}

// MARK: - Persistence

nonisolated enum DashboardScopeFilterPersistence {
    private static func storageKey(profileID: ProfileID) -> String {
        "dashboard.scopeFilters.v1.\(profileID.rawValue)"
    }

    struct Stored: Codable, Equatable, Sendable {
        var dateRangeRaw: String?
        var customStart: Date?
        var customEnd: Date?
        var accountModeRaw: String?
        var showPublicOnly: Bool?
        var hasUserSelectedDateRange: Bool?
    }

    static func load(profileID: ProfileID) -> Stored? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(profileID: profileID)) else {
            return nil
        }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    static func save(profileID: ProfileID, stored: Stored) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(profileID: profileID))
    }
}
