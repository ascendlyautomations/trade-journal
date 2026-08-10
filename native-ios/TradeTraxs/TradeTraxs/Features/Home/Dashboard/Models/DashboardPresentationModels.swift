import Foundation

/// Dashboard date-range presets — mirrors web `timeFilter` ids.
nonisolated enum DashboardDateRange: String, CaseIterable, Identifiable, Sendable {
    case all
    case sevenDays
    case thirtyDays
    case ninetyDays
    case ytd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Time"
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .ninetyDays: return "90D"
        case .ytd: return "YTD"
        }
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .sevenDays:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= start
        case .thirtyDays:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= start
        case .ninetyDays:
            guard let start = calendar.date(byAdding: .day, value: -90, to: now) else { return true }
            return date >= start
        case .ytd:
            let year = calendar.component(.year, from: now)
            var comps = DateComponents()
            comps.year = year
            comps.month = 1
            comps.day = 1
            guard let start = calendar.date(from: comps) else { return true }
            return date >= start
        }
    }
}

nonisolated enum DashboardAccountFilter: Hashable, Sendable {
    case all
    case account(TradingAccountID)

    var title: String {
        switch self {
        case .all: return "All Accounts"
        case .account: return "Account"
        }
    }
}

nonisolated enum DashboardLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

nonisolated struct DashboardMetricChip: Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var value: String
    var tone: DashboardMetricTone
}

nonisolated enum DashboardMetricTone: Hashable, Sendable {
    case neutral
    case positive
    case negative
}

nonisolated struct DashboardBarPoint: Identifiable, Hashable, Sendable {
    var id: String { label }
    var label: String
    var value: Double
}

nonisolated struct DashboardWinLossPoint: Identifiable, Hashable, Sendable {
    var id: String { label }
    var label: String
    var count: Int
}

nonisolated struct DashboardHoldTimeRow: Identifiable, Hashable, Sendable {
    var id: String { label }
    var label: String
    var value: String
}

nonisolated struct DashboardInsightItem: Identifiable, Hashable, Sendable {
    var id: String
    var body: String
}
