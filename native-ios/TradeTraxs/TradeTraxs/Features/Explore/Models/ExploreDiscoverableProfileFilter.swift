import Foundation

/// Category chips for Suggested Traders — maps to `profiles.trader_type`.
nonisolated enum SuggestedTraderCategoryTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case futures
    case options
    case investors
    case forex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .futures: return "Futures"
        case .options: return "Options"
        case .investors: return "Investors"
        case .forex: return "Forex"
        }
    }

    var traderType: TraderType? {
        switch self {
        case .all: return nil
        case .futures: return .futures
        case .options: return .options
        case .investors: return .investor
        case .forex: return .forex
        }
    }
}

/// Server / client filter for public discoverable profiles.
nonisolated struct ExploreDiscoverableProfileFilter: Sendable, Hashable {
    var traderType: TraderType?
    var strategyQuery: String?

    static let inactive = ExploreDiscoverableProfileFilter()

    init(traderType: TraderType? = nil, strategyQuery: String? = nil) {
        self.traderType = traderType
        self.strategyQuery = strategyQuery
    }

    init(category: SuggestedTraderCategoryTab, strategyQuery: String?) {
        self.traderType = category.traderType
        self.strategyQuery = strategyQuery
    }

    var normalizedStrategyQuery: String? {
        let trimmed = strategyQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count >= 2 else { return nil }
        return trimmed
    }

    var usesServerStrategyQuery: Bool {
        normalizedStrategyQuery != nil
    }

    static func matches(_ profile: Profile, filter: ExploreDiscoverableProfileFilter) -> Bool {
        if let type = filter.traderType, profile.traderType != type {
            return false
        }
        if let query = filter.normalizedStrategyQuery {
            return profileMatchesStrategyQuery(profile, query: query)
        }
        return true
    }

    /// Only `trading_style` and `trading_model` — never bio or trade history.
    static func profileMatchesStrategyQuery(_ profile: Profile, query: String) -> Bool {
        let needle = query.lowercased()
        let fields = [profile.tradingStyle, profile.tradingModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return fields.contains { $0.lowercased().contains(needle) }
    }
}